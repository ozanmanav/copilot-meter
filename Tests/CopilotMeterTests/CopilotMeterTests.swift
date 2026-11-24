import Foundation
import Testing
@testable import CopilotMeter

struct CopilotMeterTests {
    @Test
    func roundsPercentage() {
        #expect(UsageMath.percentage(used: 375, allowance: 1_500) == 25)
        #expect(UsageMath.percentage(used: 1_001, allowance: 1_500) == 67)
    }

    @Test
    func capsPercentage() {
        #expect(UsageMath.percentage(used: 20_000, allowance: 1_500) == 999)
        #expect(UsageMath.percentage(used: -10, allowance: 1_500) == 0)
        #expect(UsageMath.percentage(used: 10, allowance: 0) == 0)
    }

    @Test
    func sumsUsageItems() throws {
        let json = #"""
        {
          "usageItems": [
            { "grossQuantity": 18.5 },
            { "grossQuantity": 21 }
          ]
        }
        """#

        let report = try JSONDecoder().decode(UsageReport.self, from: Data(json.utf8))
        #expect(report.usedCredits == 39.5)
    }
}
