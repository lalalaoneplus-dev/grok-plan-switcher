import XCTest
@testable import GrokPlanSwitcher

final class UsageSnapshotTests: XCTestCase {
    func testWeeklyRemainingAndResetAreParsed() throws {
        let json = #"{"config":{"creditUsagePercent":27.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-18T10:30:00Z"}}}"#
        let fetchedAt = Date(timeIntervalSince1970: 1_000)

        let snapshot = try UsageSnapshot.parse(Data(json.utf8), fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.remainingPercent, 72.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.periodName, "this week")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertNotNil(snapshot.resetAt)
    }

    func testOmittedPercentWithCurrentPeriodMeansNoUsageYet() throws {
        let json = #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-18T10:30:00Z"}}}"#

        let snapshot = try UsageSnapshot.parse(Data(json.utf8))

        XCTAssertEqual(snapshot.remainingPercent, 100)
    }

    func testExhaustedPreferredPlanFallsBackOnlyToAvailableAccount() {
        let now = Date(timeIntervalSince1970: 1_000)
        let first = UsageSnapshot(remainingPercent: 0, resetAt: nil, periodType: nil, fetchedAt: now)
        let second = UsageSnapshot(remainingPercent: 35, resetAt: nil, periodType: nil, fetchedAt: now)
        let statuses: [Int: PlanStatus] = [1: .ready(first), 2: .ready(second)]

        XCTAssertEqual(GrokPlan.planToUse(preferred: GrokPlan.all[0], statuses: statuses), GrokPlan.all[1])
        XCTAssertNil(GrokPlan.planToUse(preferred: GrokPlan.all[1], statuses: [1: .ready(first), 2: .ready(first)]))
    }
}
