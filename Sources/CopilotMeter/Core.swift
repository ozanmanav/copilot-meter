import Darwin
import Foundation

struct GitHubHost: Equatable, Sendable {
    let name: String

    init?(_ value: String) {
        let hostURL = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let address = hostURL.contains("://") ? hostURL : "https://\(hostURL)"
        guard let url = URLComponents(string: address), url.scheme == "https",
              url.path.isEmpty || url.path == "/", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil, let host = url.host,
              host == "github.com" || (
                host.hasSuffix(".ghe.com")
                  && host.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*\.ghe\.com$"#, options: .regularExpression) != nil
              ) else {
            return nil
        }

        name = host
    }

    var settingsURL: URL? {
        URL(string: "https://\(name)\(name == "github.com" ? "/settings/billing/usage" : "/settings/copilot")")
    }
}

struct AccountQuota: Sendable {
    let host: GitHubHost
    let plan: PlanQuota
}

struct CopilotIdentity: Decodable {
    let host: String
    let login: String?
}

struct CopilotAccount: Decodable {
    let authInfo: CopilotIdentity
    let selectionId: String

    static func select(from accounts: [Self], for host: GitHubHost) throws -> Self {
        let matches = accounts.filter { GitHubHost($0.authInfo.host) == host }
        guard let first = matches.first else {
            throw QuotaError.notSignedIn(host)
        }
        guard matches.allSatisfy({
            $0.authInfo.login?.lowercased() == first.authInfo.login?.lowercased()
        }), matches.count == 1 || first.authInfo.login != nil else {
            throw QuotaError.ambiguousAccount(host)
        }
        return first
    }
}

struct PlanQuota: Decodable, Sendable {
    let remainingPercentage: Double
    let isUnlimitedEntitlement: Bool

    var usedPercentage: Int? {
        guard !isUnlimitedEntitlement, (0...100).contains(remainingPercentage) else {
            return nil
        }

        return Int((100 - remainingPercentage).rounded())
    }

    var title: String {
        usedPercentage.map { "\($0)%" } ?? "—"
    }
}

enum QuotaError: LocalizedError, Equatable {
    case missingCLI
    case timedOut
    case invalidResponse
    case unavailable
    case unsupportedCLI
    case requestFailed
    case invalidHost
    case notSignedIn(GitHubHost?)
    case ambiguousAccount(GitHubHost)

    var errorDescription: String? {
        switch self {
        case .missingCLI:
            return "Copilot CLI not found. Install it and run make install again."
        case .timedOut:
            return "Copilot CLI did not respond in time."
        case .invalidResponse:
            return "Copilot CLI returned an unreadable quota response."
        case .unavailable:
            return "No plan quota was reported. Check your Copilot CLI sign-in."
        case .unsupportedCLI:
            return "This Copilot CLI does not support quota lookup. Update it and reinstall the meter."
        case .requestFailed:
            return "Could not read quota. Check copilot login and try again."
        case .invalidHost:
            return "Use github.com or a GitHub Enterprise Cloud host ending in .ghe.com."
        case .notSignedIn(let host):
            return host.map { "No Copilot session for \($0.name). Run: copilot login --host https://\($0.name)" }
                ?? "No Copilot session found. Run: copilot login"
        case .ambiguousAccount(let host):
            return "Multiple Copilot accounts on \(host.name). Switch to the desired account in Copilot CLI."
        }
    }
}

struct QuotaResult: Decodable {
    struct Snapshots: Decodable {
        let premiumInteractions: PlanQuota?

        enum CodingKeys: String, CodingKey {
            case premiumInteractions = "premium_interactions"
        }
    }

    let quotaSnapshots: Snapshots

    func planQuota() throws -> PlanQuota {
        guard let quota = quotaSnapshots.premiumInteractions else {
            throw QuotaError.unavailable
        }
        guard quota.isUnlimitedEntitlement || quota.usedPercentage != nil else {
            throw QuotaError.invalidResponse
        }
        return quota
    }
}

struct RPCReply<Value: Decodable>: Decodable {
    struct Failure: Decodable {
        let code: Int
    }

    let id: Int
    let result: Value?
    let error: Failure?

    static func decodeFrame(_ data: Data, id: Int) throws -> Value? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let header = String(decoding: data[..<separator.lowerBound], as: UTF8.self)
        let lengthPrefix = "content-length:"
        guard let lengthLine = header.components(separatedBy: "\r\n").first(where: {
            $0.lowercased().hasPrefix(lengthPrefix)
        }), let length = Int(lengthLine.dropFirst(lengthPrefix.count).trimmingCharacters(in: .whitespaces)),
            (1...CopilotCLI.responseLimit).contains(length) else {
            throw QuotaError.invalidResponse
        }

        let start = separator.upperBound
        guard data.endIndex - start >= length else {
            return nil
        }

        let reply: Self
        do {
            reply = try JSONDecoder().decode(Self.self, from: data[start..<(start + length)])
        } catch is DecodingError {
            throw QuotaError.invalidResponse
        }
        guard reply.id == id else {
            throw QuotaError.invalidResponse
        }
        if let error = reply.error {
            throw error.code == -32601 ? QuotaError.unsupportedCLI : QuotaError.requestFailed
        }

        guard let result = reply.result else {
            throw QuotaError.invalidResponse
        }
        return result
    }
}

struct CopilotCLI: Sendable {
    fileprivate static let responseLimit = 256 * 1024

    func fetchQuota() throws -> AccountQuota {
        var environment = ProcessInfo.processInfo.environment
        var target: GitHubHost?
        if let configuredHost = environment["COPILOT_METER_HOST"] {
            guard let host = GitHubHost(configuredHost) else {
                throw QuotaError.invalidHost
            }
            target = host
            environment["COPILOT_GH_HOST"] = host.name
            // A token inherited from the shell may belong to a different host.
            for variable in ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"] {
                environment.removeValue(forKey: variable)
            }
        }

        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        let search = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + defaults
        let cli = environment["COPILOT_METER_CLI"]
            ?? search.map { "\($0)/copilot" }.first(where: FileManager.default.isExecutableFile(atPath:))
        guard let cli, FileManager.default.isExecutableFile(atPath: cli) else {
            throw QuotaError.missingCLI
        }

        let input = Pipe()
        let output = Pipe()
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw QuotaError.requestFailed
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["--headless", "--no-auto-update", "--stdio"]
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let active: CurrentAccount = try request("account.getCurrentAuth", id: 1, input: input, output: output)
        let activeHost = active.authInfo.flatMap { GitHubHost($0.host) }
        guard let host = target ?? activeHost else {
            throw QuotaError.notSignedIn(nil)
        }

        var params: [String: String] = [:]
        if host != activeHost {
            let accounts: [CopilotAccount] = try request("account.getAllUsers", id: 2, input: input, output: output)
            params["selectionId"] = try CopilotAccount.select(from: accounts, for: host).selectionId
        }
        let quota: QuotaResult = try request("account.getQuota", id: 3, params: params, input: input, output: output)
        return AccountQuota(host: host, plan: try quota.planQuota())
    }

    private struct CurrentAccount: Decodable {
        let authInfo: CopilotIdentity?
    }

    private func request<Value: Decodable>(
        _ method: String, id: Int, params: [String: String] = [:], input: Pipe, output: Pipe
    ) throws -> Value {
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ])
        var frame = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        frame.append(body)
        do {
            try input.fileHandleForWriting.write(contentsOf: frame)
        } catch {
            throw QuotaError.requestFailed
        }
        return try readResponse(id: id, from: output.fileHandleForReading)
    }

    private func readResponse<Value: Decodable>(id: Int, from handle: FileHandle) throws -> Value {
        let deadline = DispatchTime.now() + .seconds(15)
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        while buffer.count < Self.responseLimit {
            let now = DispatchTime.now()
            guard now < deadline else {
                throw QuotaError.timedOut
            }
            let milliseconds = (deadline.uptimeNanoseconds - now.uptimeNanoseconds + 999_999) / 1_000_000
            let ready = poll(&descriptor, 1, Int32(milliseconds))
            if ready == 0 {
                throw QuotaError.timedOut
            }
            if ready < 0 && errno == EINTR {
                continue
            }
            guard ready > 0 else {
                throw QuotaError.requestFailed
            }

            let count = read(handle.fileDescriptor, &chunk, chunkSize)
            if count < 0 && errno == EINTR {
                continue
            }
            guard count > 0 else {
                throw buffer.isEmpty ? QuotaError.requestFailed : QuotaError.invalidResponse
            }
            buffer.append(contentsOf: chunk.prefix(count))
            if let response = try RPCReply<Value>.decodeFrame(buffer, id: id) {
                return response
            }
        }

        throw QuotaError.invalidResponse
    }
}
