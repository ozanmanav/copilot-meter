import Foundation
import Testing
@testable import CopilotMeter

struct CopilotMeterTests {
    @Test
    func showsUsedPlanQuotaInsteadOfRemainingOrChatQuota() throws {
        let response = frame(#"""
        {"id":1,"result":{"quotaSnapshots":{
          "chat":{"remainingPercentage":100,"isUnlimitedEntitlement":true},
          "premium_interactions":{"remainingPercentage":19.9,"isUnlimitedEntitlement":false}
        }}}
        """#)

        #expect(try QuotaReply.decodeFrame(response)?.title == "80%")
        #expect(try QuotaReply.decodeFrame(response.dropLast()) == nil)
    }

    @Test
    func doesNotDisplayZeroForAnUnlimitedPlan() throws {
        let response = frame(#"""
        {"id":1,"result":{"quotaSnapshots":{
          "premium_interactions":{"remainingPercentage":100,"isUnlimitedEntitlement":true}
        }}}
        """#)

        let decoded = try QuotaReply.decodeFrame(response)
        let quota = try #require(decoded)
        #expect(quota.usedPercentage == nil)
    }

    @Test
    func reportsAnUnsupportedRPCInsteadOfDisplayingZero() {
        let response = frame(#"{"id":1,"error":{"code":-32601,"message":"Method not found"}}"#)
        #expect(throws: QuotaError.unsupportedCLI) {
            try QuotaReply.decodeFrame(response)
        }
    }

    @Test
    func rejectsMissingAndInvalidQuotas() {
        let noPlan = frame(#"{"id":1,"result":{"quotaSnapshots":{}}}"#)
        let invalid = frame(#"""
        {"id":1,"result":{"quotaSnapshots":{
          "premium_interactions":{"remainingPercentage":101,"isUnlimitedEntitlement":false}
        }}}
        """#)

        #expect(throws: QuotaError.unavailable) {
            try QuotaReply.decodeFrame(noPlan)
        }
        #expect(throws: QuotaError.invalidResponse) {
            try QuotaReply.decodeFrame(invalid)
        }
    }

    private func frame(_ body: String) -> Data {
        Data("Content-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
    }
}
