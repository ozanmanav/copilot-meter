import Foundation
import Testing
@testable import CopilotMeter

struct CopilotMeterTests {
    @Test
    func acceptsEnterpriseHostURLsAndRejectsOtherDestinations() {
        #expect(GitHubHost("https://ACME-DEV.ghe.com/")?.name == "acme-dev.ghe.com")
        #expect(GitHubHost("acme-dev.ghe.com")?.settingsURL?.host == "acme-dev.ghe.com")
        #expect(GitHubHost("http://acme.ghe.com") == nil)
        #expect(GitHubHost("https://acme.ghe.com.example.com") == nil)
        #expect(GitHubHost("https://acme.ghe.com/other") == nil)
    }

    @Test
    func selectsOnlyAccountsOnTheRequestedHost() throws {
        let host = try #require(GitHubHost("https://acme.ghe.com/"))
        let personal = CopilotAccount(authInfo: .init(host: "https://github.com", login: "dev"), selectionId: "personal")
        let enterprise = CopilotAccount(authInfo: .init(host: "https://ACME.ghe.com", login: "dev"), selectionId: "work")
        let duplicate = CopilotAccount(authInfo: .init(host: "acme.ghe.com", login: "DEV"), selectionId: "work-duplicate")
        let different = CopilotAccount(authInfo: .init(host: "acme.ghe.com", login: "another"), selectionId: "other")

        #expect(try CopilotAccount.select(from: [personal, enterprise, duplicate], for: host).selectionId == "work")
        #expect(throws: QuotaError.notSignedIn(host)) {
            try CopilotAccount.select(from: [personal], for: host)
        }
        #expect(throws: QuotaError.ambiguousAccount(host)) {
            try CopilotAccount.select(from: [enterprise, different], for: host)
        }
    }

    @Test
    func showsUsedPlanQuotaInsteadOfRemainingOrChatQuota() throws {
        let response = frame(#"""
        {"id":1,"result":{"quotaSnapshots":{
          "chat":{"remainingPercentage":100,"isUnlimitedEntitlement":true},
          "premium_interactions":{"remainingPercentage":19.9,"isUnlimitedEntitlement":false}
        }}}
        """#)

        #expect(try quota(response)?.title == "80%")
        #expect(try quota(response.dropLast()) == nil)
    }

    @Test
    func doesNotDisplayZeroForAnUnlimitedPlan() throws {
        let response = frame(#"""
        {"id":1,"result":{"quotaSnapshots":{
          "premium_interactions":{"remainingPercentage":100,"isUnlimitedEntitlement":true}
        }}}
        """#)

        let decoded = try quota(response)
        let quota = try #require(decoded)
        #expect(quota.usedPercentage == nil)
    }

    @Test
    func reportsAnUnsupportedRPCInsteadOfDisplayingZero() {
        let response = frame(#"{"id":1,"error":{"code":-32601,"message":"Method not found"}}"#)
        #expect(throws: QuotaError.unsupportedCLI) {
            try quota(response)
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
            try quota(noPlan)
        }
        #expect(throws: QuotaError.invalidResponse) {
            try quota(invalid)
        }
    }

    private func quota(_ data: Data) throws -> PlanQuota? {
        try RPCReply<QuotaResult>.decodeFrame(data, id: 1)?.planQuota()
    }

    private func frame(_ body: String) -> Data {
        Data("Content-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
    }
}
