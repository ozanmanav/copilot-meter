import Darwin
import Foundation

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

enum QuotaError: LocalizedError {
    case missingCLI
    case timedOut
    case invalidResponse
    case unavailable
    case unsupportedCLI
    case requestFailed

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
        }
    }
}

struct QuotaReply: Decodable {
    struct Result: Decodable {
        struct Snapshots: Decodable {
            let premiumInteractions: PlanQuota?

            enum CodingKeys: String, CodingKey {
                case premiumInteractions = "premium_interactions"
            }
        }

        let quotaSnapshots: Snapshots
    }

    struct Failure: Decodable {
        let code: Int
    }

    let id: Int
    let result: Result?
    let error: Failure?

    static func decodeFrame(_ data: Data) throws -> PlanQuota? {
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
        guard reply.id == 1 else {
            throw QuotaError.invalidResponse
        }
        if let error = reply.error {
            throw error.code == -32601 ? QuotaError.unsupportedCLI : QuotaError.requestFailed
        }

        guard let quota = reply.result?.quotaSnapshots.premiumInteractions else {
            throw QuotaError.unavailable
        }
        guard quota.isUnlimitedEntitlement || quota.usedPercentage != nil else {
            throw QuotaError.invalidResponse
        }

        return quota
    }
}

struct CopilotCLI: Sendable {
    fileprivate static let responseLimit = 64 * 1024

    func fetchQuota() throws -> PlanQuota {
        let paths = ProcessInfo.processInfo.environment
        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        let search = (paths["PATH"] ?? "").split(separator: ":").map(String.init) + defaults
        let cli = paths["COPILOT_METER_CLI"]
            ?? search.map { "\($0)/copilot" }.first(where: FileManager.default.isExecutableFile(atPath:))
        guard let cli, FileManager.default.isExecutableFile(atPath: cli) else {
            throw QuotaError.missingCLI
        }

        let input = Pipe()
        let output = Pipe()
        let request = #"{"jsonrpc":"2.0","id":1,"method":"account.getQuota","params":{}}"#
        let frame = "Content-Length: \(request.utf8.count)\r\n\r\n\(request)"
        try input.fileHandleForWriting.write(contentsOf: Data(frame.utf8))
        try input.fileHandleForWriting.close()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["--headless", "--no-auto-update", "--stdio"]
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

        return try readQuota(from: output.fileHandleForReading)
    }

    private func readQuota(from handle: FileHandle) throws -> PlanQuota {
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
            if let quota = try QuotaReply.decodeFrame(buffer) {
                return quota
            }
        }

        throw QuotaError.invalidResponse
    }
}
