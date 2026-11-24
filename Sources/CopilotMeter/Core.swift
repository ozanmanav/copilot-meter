import Foundation

struct UsageSnapshot: Equatable, Sendable {
    let usedCredits: Double
    let allowance: Double
    let account: String
    let fetchedAt: Date

    var percentage: Int {
        UsageMath.percentage(used: usedCredits, allowance: allowance)
    }
}

enum UsageMath {
    static func percentage(used: Double, allowance: Double) -> Int {
        guard allowance > 0, used.isFinite, allowance.isFinite else {
            return 0
        }

        return min(999, max(0, Int(((used / allowance) * 100).rounded())))
    }
}

struct UsageReport: Decodable {
    let usageItems: [UsageItem]

    var usedCredits: Double {
        usageItems.reduce(0) { $0 + $1.grossQuantity }
    }
}

struct UsageItem: Decodable {
    let grossQuantity: Double
}

enum GitHubUsageError: LocalizedError {
    case missingGitHubCLI
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingGitHubCLI:
            return "GitHub CLI (gh) was not found. Install it with brew install gh."
        case .commandFailed(let message):
            return message
        case .invalidResponse:
            return "GitHub returned a response that Copilot Meter could not read."
        }
    }
}

struct GitHubCLI: Sendable {
    private let executableURL: URL?

    init(fileManager: FileManager = .default) {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]

        executableURL = candidates
            .first(where: fileManager.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    func fetchSnapshot(allowance: Double) throws -> UsageSnapshot {
        guard let executableURL else {
            throw GitHubUsageError.missingGitHubCLI
        }

        let account = try run(
            executableURL: executableURL,
            arguments: ["api", "--hostname", "github.com", "/user", "--jq", ".login"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !account.isEmpty else {
            throw GitHubUsageError.invalidResponse
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)

        guard let year = components.year, let month = components.month else {
            throw GitHubUsageError.invalidResponse
        }

        let endpoint = "/users/\(account)/settings/billing/ai_credit/usage?year=\(year)&month=\(month)"
        let output = try run(
            executableURL: executableURL,
            arguments: [
                "api",
                "--hostname",
                "github.com",
                "-H",
                "X-GitHub-Api-Version: 2026-03-10",
                endpoint
            ]
        )

        let report: UsageReport
        do {
            report = try JSONDecoder().decode(UsageReport.self, from: Data(output.utf8))
        } catch {
            throw GitHubUsageError.invalidResponse
        }

        return UsageSnapshot(
            usedCredits: report.usedCredits,
            allowance: allowance,
            account: account,
            fetchedAt: now
        )
    }

    private func run(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw GitHubUsageError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let fallback = "GitHub could not load Copilot usage."
            throw GitHubUsageError.commandFailed(
                authorizationHint(for: message ?? "") ?? (message?.isEmpty == false ? message! : fallback)
            )
        }

        return String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    }

    private func authorizationHint(for message: String) -> String? {
        guard message.localizedCaseInsensitiveContains("user scope") else {
            return nil
        }

        return "GitHub billing access is not authorized. Run: gh auth refresh -h github.com -s user"
    }
}
