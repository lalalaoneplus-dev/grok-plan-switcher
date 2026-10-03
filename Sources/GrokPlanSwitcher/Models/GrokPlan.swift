import Foundation

struct GrokPlan: Identifiable, Equatable, Sendable {
    let number: Int

    var id: Int { number }
    var name: String { "Plan \(number)" }
    var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(number == 1 ? ".grok" : ".grok-plan2", isDirectory: true)
    }

    static let all = [GrokPlan(number: 1), GrokPlan(number: 2)]

    static func planToUse(preferred: GrokPlan, statuses: [Int: PlanStatus]) -> GrokPlan? {
        guard case .ready(let usage) = statuses[preferred.id], usage.remainingPercent <= 0 else {
            return preferred
        }
        return all.first { plan in
            guard plan != preferred, case .ready(let usage) = statuses[plan.id] else { return false }
            return usage.remainingPercent > 0
        }
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let remainingPercent: Double
    let resetAt: Date?
    let periodType: String?
    let fetchedAt: Date

    var periodName: String {
        if periodType?.localizedCaseInsensitiveContains("weekly") == true { return "this week" }
        if periodType?.localizedCaseInsensitiveContains("monthly") == true { return "this month" }
        return "this period"
    }

    static func parse(_ data: Data, fetchedAt: Date = .now) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(BillingResponse.self, from: data)
        guard let config = response.config else { throw GrokUsageError.missingUsage }

        let usedPercent: Double
        if let percent = config.creditUsagePercent, percent.isFinite {
            usedPercent = percent
        } else if let limit = config.monthlyLimit?.val, limit > 0,
                  let used = config.used?.val {
            usedPercent = used / limit * 100
        } else if config.currentPeriod != nil {
            usedPercent = 0
        } else {
            throw GrokUsageError.missingUsage
        }

        return UsageSnapshot(
            remainingPercent: min(100, max(0, 100 - usedPercent)),
            resetAt: Self.parseDate(config.currentPeriod?.end ?? config.billingPeriodEnd),
            periodType: config.currentPeriod?.type,
            fetchedAt: fetchedAt
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
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

private struct BillingResponse: Decodable {
    let config: BillingConfig?
}

private struct BillingConfig: Decodable {
    let creditUsagePercent: Double?
    let currentPeriod: BillingPeriod?
    let monthlyLimit: CentValue?
    let used: CentValue?
    let billingPeriodEnd: String?
}

private struct BillingPeriod: Decodable {
    let type: String?
    let end: String?
}

private struct CentValue: Decodable {
    let val: Double?
}

enum PlanStatus: Equatable {
    case checking
    case notConnected
    case signInAgain
    case ready(UsageSnapshot)
    case failed(String)
}

enum GrokUsageError: LocalizedError {
    case notConnected
    case expired
    case missingAccountID
    case unreadableCredentials
    case missingUsage
    case rejected
    case server(Int)
    case network

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not signed in yet."
        case .expired: "This login expired. Sign in again."
        case .missingAccountID: "Sign in again to refresh this profile."
        case .unreadableCredentials: "Could not read this Grok login. Sign in again."
        case .missingUsage: "Grok returned no usage data. Try refreshing."
        case .rejected: "Grok rejected this login. Sign in again."
        case .server(let code): "Grok usage is temporarily unavailable (\(code))."
        case .network: "Could not reach Grok. Check your connection and refresh."
        }
    }
}
