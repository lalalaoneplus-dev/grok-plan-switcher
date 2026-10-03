import Foundation

enum GrokCLI {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static var executable: URL? {
        let candidates = [
            home.appendingPathComponent(".grok/bin/grok"),
            URL(fileURLWithPath: "/opt/homebrew/bin/grok"),
            URL(fileURLWithPath: "/usr/local/bin/grok")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var version: String {
        guard let executable else { return "unknown" }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let parts = output.split(whereSeparator: \.isWhitespace)
            return parts.count > 1 ? String(parts[1]) : "unknown"
        } catch {
            return "unknown"
        }
    }

    static func open(plan: GrokPlan, signIn: Bool, workingDirectory: String) throws {
        guard let executable else { throw CLIError.notInstalled }

        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Grok Plan Switcher", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let commandFile = support.appendingPathComponent("Plan-\(plan.number).command")
        let command = """
        #!/bin/zsh
        export GROK_HOME=\(quote(plan.home.path))
        cd -- \(quote(workingDirectory)) || exit 1
        exec \(quote(executable.path))\(signIn ? " login" : "")
        """
        try Data(command.utf8).write(to: commandFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: commandFile.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", commandFile.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError.terminalFailed }
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private enum CLIError: LocalizedError {
    case notInstalled
    case terminalFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled: "Grok Build CLI was not found. Install it, then reopen this app."
        case .terminalFailed: "Could not open Terminal."
        }
    }
}
