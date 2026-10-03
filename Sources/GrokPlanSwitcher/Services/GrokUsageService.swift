import Foundation

private struct GrokCredential {
    let token: String
    let userID: String
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class GrokUsageService: @unchecked Sendable {
    private let session = URLSession(
        configuration: .ephemeral,
        delegate: RejectRedirects(),
        delegateQueue: nil
    )

    func status(for plan: GrokPlan) async -> PlanStatus {
        do {
            let credential = try Self.credential(for: plan)
            return .ready(try await fetchUsage(credential))
        } catch GrokUsageError.notConnected {
            return .notConnected
        } catch GrokUsageError.expired, GrokUsageError.rejected, GrokUsageError.missingAccountID,
                GrokUsageError.unreadableCredentials {
            return .signInAgain
        } catch let error as GrokUsageError {
            return .failed(error.localizedDescription)
        } catch {
            return .failed("Could not load usage. Try refreshing.")
        }
    }

    private func fetchUsage(_ credential: GrokCredential) async throws -> UsageSnapshot {
        // ponytail: mirrors Grok Build's internal billing route; switch to a public quota API if xAI ships one.
        let url = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue(credential.userID, forHTTPHeaderField: "x-userid")
        request.setValue(GrokCLI.version, forHTTPHeaderField: "x-grok-client-version")
        request.setValue("headless", forHTTPHeaderField: "x-grok-client-mode")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw GrokUsageError.network }
            switch response.statusCode {
            case 200..<300:
                return try UsageSnapshot.parse(data)
            case 401, 403:
                throw GrokUsageError.rejected
            default:
                throw GrokUsageError.server(response.statusCode)
            }
        } catch let error as GrokUsageError {
            throw error
        } catch {
            throw GrokUsageError.network
        }
    }

    private static func credential(for plan: GrokPlan) throws -> GrokCredential {
        let file = plan.home.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw GrokUsageError.notConnected
        }
        guard let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
              size.intValue <= 1_048_576,
              let data = try? Data(contentsOf: file),
              let store = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokUsageError.unreadableCredentials
        }

        let scopes = store.keys
            .filter { $0.hasPrefix("https://auth.x.ai::") || $0 == "https://accounts.x.ai/sign-in" }
            .sorted { $0.hasPrefix("https://auth.x.ai::") && !$1.hasPrefix("https://auth.x.ai::") }

        for scope in scopes {
            guard let entry = store[scope] as? [String: Any] else { continue }
            let mode = (entry["auth_mode"] as? String ?? entry["authMode"] as? String)?.lowercased()
            if mode == "weblogin" { continue }

            let token = entry["key"] as? String
            let userID = entry["user_id"] as? String ?? entry["userId"] as? String
            guard let token, !token.isEmpty else { continue }
            guard let userID, !userID.isEmpty else { throw GrokUsageError.missingAccountID }

            let expiresAt = Self.date(entry["expires_at"] as? String ?? entry["expiresAt"] as? String)
            if let expiresAt, expiresAt <= .now { throw GrokUsageError.expired }
            return GrokCredential(token: token, userID: userID)
        }

        throw GrokUsageError.notConnected
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
