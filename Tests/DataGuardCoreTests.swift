import XCTest
@testable import DataGuardCore

final class DataGuardCoreTests: XCTestCase {
    func settings() -> SettingsStore {
        var s = SettingsStore(); s.selectedInterfaces = ["cell-test"]; s.timeZoneID = "UTC"; return s
    }
    let date = ISO8601DateFormatter().date(from: "2026-09-13T00:00:00Z")!
    func snapshot(_ rx: UInt64, _ tx: UInt64, index: UInt32 = 1) -> [InterfaceSnapshot] {
        [InterfaceSnapshot(name: "cell-test", index: index, rx: rx, tx: tx)]
    }
    func calibrated(_ rx: UInt64 = 100, _ tx: UInt64 = 200, used: UInt64 = 0) throws -> UsageStore {
        var u = UsageStore()
        try u.reconcile(bytes: used, interfaces: snapshot(rx, tx), settings: settings(), now: date, uptime: 1000)
        return u
    }
    func testFirstSampleDoesNotCountBootLifetimeAsMonthlyUsage() {
        var u = UsageStore(); u.ingest(snapshot(4_000_000_000, 1000), settings: settings(), now: date, uptime: 1000)
        XCTAssertEqual(u.usedBytes, 0)
        XCTAssertTrue(u.needsReview)
        XCTAssertFalse(UsageReport.make(settings: settings(), usage: u).shouldBlock)
    }
    func testRxAndTxDeltasAccumulateOnce() throws {
        var u = try calibrated()
        u.ingest(snapshot(1100, 2200), settings: settings(), now: date.addingTimeInterval(10), uptime: 1010)
        XCTAssertEqual(u.usedBytes, 3000)
        XCTAssertEqual(u.lastIncreaseBytes, 3000)
        u.ingest(snapshot(1100, 2200), settings: settings(), now: date.addingTimeInterval(20), uptime: 1020)
        XCTAssertEqual(u.usedBytes, 3000)
        XCTAssertFalse(u.needsReview)
    }
    func testIndependentDirectionalResetDoesNotHideBehindOtherDirection() throws {
        var u = try calibrated(1000, 1000)
        u.ingest(snapshot(10, 5000), settings: settings(), now: date.addingTimeInterval(10), uptime: 1010)
        XCTAssertEqual(u.usedBytes, 4010)
        XCTAssertTrue(u.needsReview)
    }
    func test32BitWrapRetainsReviewSeparatelyFromUsageThreshold() throws {
        var u = try calibrated(UInt64(UInt32.max) - 10, 0)
        u.ingest(snapshot(10, 0), settings: settings(), now: date.addingTimeInterval(1), uptime: 1001)
        XCTAssertEqual(u.usedBytes, 10) // Deliberately a lower bound, not an invented exact wrap.
        let report = UsageReport.make(settings: settings(), usage: u)
        XCTAssertFalse(report.shouldBlock)
        XCTAssertTrue(report.requiresReview)
    }
    func testMissingInterfacePreservesTotalAndBaseline() throws {
        var u = try calibrated(100, 200, used: 3_000_000_000)
        u.ingest([], settings: settings(), now: date.addingTimeInterval(10), uptime: 1010)
        XCTAssertEqual(u.usedBytes, 3_000_000_000)
        XCTAssertEqual(u.baselines["cell-test"]?.rx, 100)
        XCTAssertTrue(u.needsReview)
        u.ingest(snapshot(200, 300), settings: settings(), now: date.addingTimeInterval(20), uptime: 1020)
        XCTAssertEqual(u.usedBytes, 3_000_000_200)
        XCTAssertTrue(u.needsReview) // Sticky until explicit reconciliation.
    }
    func testRecreatedInterfaceCountsCurrentAndRequestsReview() throws {
        var u = try calibrated()
        u.ingest(snapshot(500, 600, index: 2), settings: settings(), now: date.addingTimeInterval(10), uptime: 1010)
        XCTAssertEqual(u.usedBytes, 1100)
        XCTAssertTrue(u.needsReview)
    }
    func testRebootEvenWhenCountersIncrease() throws {
        var u = try calibrated()
        u.ingest(snapshot(1000, 2000), settings: settings(), now: date.addingTimeInterval(10), uptime: 5)
        XCTAssertEqual(u.usedBytes, 3000)
        XCTAssertTrue(u.needsReview)
    }
    func testLongGapAndClockChangeRequireReview() throws {
        var u = try calibrated()
        u.ingest(snapshot(100, 200), settings: settings(), now: date.addingTimeInterval(901), uptime: 1901)
        XCTAssertTrue(u.needsReview)
        u = try calibrated()
        u.ingest(snapshot(100, 200), settings: settings(), now: date.addingTimeInterval(-100), uptime: 1010)
        XCTAssertTrue(u.needsReview)
    }
    func testCalibratedUsageSurvivesTestModeAndLongGap() throws {
        var u = try calibrated(used: 300_000_000)
        var s = settings()
        s.testMode = true
        s.simulatedGB = 4
        XCTAssertTrue(UsageReport.make(settings: s, usage: u).shouldBlock)
        s.testMode = false
        u.ingest(snapshot(100, 200), settings: s, now: date.addingTimeInterval(3600), uptime: 4600)
        let report = UsageReport.make(settings: s, usage: u)
        XCTAssertEqual(report.usedBytes, 300_000_000)
        XCTAssertEqual(report.status, .safe)
        XCTAssertFalse(report.shouldBlock)
        XCTAssertTrue(report.requiresReview)
        XCTAssertTrue(report.message.contains(report.reason))
        XCTAssertFalse(report.message.contains("끄세요"))
    }
    func testReviewDoesNotHideAnyUsageThreshold() throws {
        for (bytes, expected) in [(300_000_000, UsageStatus.safe), (3_500_000_000, .warning), (3_800_000_000, .critical), (4_000_000_000, .block)] {
            var u = try calibrated(used: UInt64(bytes))
            u.markUncertain("측정 공백")
            let report = UsageReport.make(settings: settings(), usage: u)
            XCTAssertEqual(report.status, expected)
            XCTAssertEqual(report.shouldBlock, expected == .block)
            XCTAssertTrue(report.requiresReview)
            XCTAssertTrue(report.message.contains("측정 공백"))
        }
    }
    func testMonthlyBoundaryConservativelyAssignsWholeDeltaToNewCycle() throws {
        let formatter = ISO8601DateFormatter()
        let before = formatter.date(from: "2026-09-30T23:59:50Z")!
        let after = formatter.date(from: "2026-10-01T00:00:10Z")!
        var u = UsageStore()
        try u.reconcile(bytes: 3_000_000_000, interfaces: snapshot(100, 200), settings: settings(), now: before, uptime: 1000)
        u.notifiedLevel = 3
        u.ingest(snapshot(200, 300), settings: settings(), now: after, uptime: 1020)
        XCTAssertEqual(u.usedBytes, 200)
        XCTAssertEqual(u.notifiedLevel, 0)
        XCTAssertTrue(u.needsReview)
    }
    func testDay31ClampsAndUsesPreviousMonthBeforeBoundary() {
        var s = settings(); s.billingDay = 31
        let f = ISO8601DateFormatter()
        XCTAssertEqual(s.cycleStart(at: f.date(from: "2026-02-28T12:00:00Z")!), f.date(from: "2026-02-28T00:00:00Z")!)
        XCTAssertEqual(s.cycleStart(at: f.date(from: "2026-02-27T12:00:00Z")!), f.date(from: "2026-01-31T00:00:00Z")!)
        XCTAssertEqual(s.cycleStart(at: f.date(from: "2028-02-29T12:00:00Z")!), f.date(from: "2028-02-29T00:00:00Z")!)
    }
    func testThresholdEdgesAndRapidUsage() throws {
        let cases: [(UInt64, UsageStatus)] = [(0,.safe),(3_499_999_999,.safe),(3_500_000_000,.warning),(3_799_999_999,.warning),(3_800_000_000,.critical),(3_999_999_999,.critical),(4_000_000_000,.block),(5_000_000_000,.block)]
        for (bytes, expected) in cases {
            var u = try calibrated(used: bytes)
            u.lastIncreaseBytes = 300_000_000
            let report = UsageReport.make(settings: settings(), usage: u)
            XCTAssertEqual(report.status, expected)
            XCTAssertEqual(report.shouldBlock, expected == .block)
            XCTAssertEqual(report.rapidUsage, bytes >= 3_500_000_000)
        }
    }
    func testTestModeDoesNotChangeLiveUsageAndUnitsDoNotChangeThresholds() throws {
        let u = try calibrated(used: 1234)
        var s = settings(); s.testMode = true; s.simulatedGB = 4; s.displayUnit = .gib
        let report = UsageReport.make(settings: s, usage: u)
        XCTAssertTrue(report.shouldBlock)
        XCTAssertTrue(report.isSimulated)
        XCTAssertEqual(report.usedGB, 4)
        XCTAssertEqual(u.usedBytes, 1234)
        XCTAssertEqual(s.displayUnit.format(1_073_741_824), "1.00 GiB")
    }
    func testInvalidSettingsAndUnavailableCalibration() {
        var s = settings(); s.cutoffGB = 6; XCTAssertNotNil(s.validationError)
        s = settings(); s.warningGB = .nan; XCTAssertNotNil(s.validationError)
        s = settings(); s.billingDay = 32; XCTAssertNotNil(s.validationError)
        var u = UsageStore()
        XCTAssertThrowsError(try u.reconcile(bytes: 0, interfaces: [], settings: settings(), now: date, uptime: 1))
    }
    func testNotificationsOnlyHighestNewLevel() {
        XCTAssertEqual(NotificationPolicy.nextLevel(bytes: 3_900_000_000, settings: settings(), notifiedLevel: 0), 2)
        XCTAssertNil(NotificationPolicy.nextLevel(bytes: 3_900_000_000, settings: settings(), notifiedLevel: 2))
        XCTAssertNil(NotificationPolicy.nextLevel(bytes: 3_500_000_000, settings: settings(), notifiedLevel: 2))
        XCTAssertEqual(NotificationPolicy.nextLevel(bytes: 4_000_000_000, settings: settings(), notifiedLevel: 2), 3)
    }
    @MainActor
    func testPersistenceRoundTripAndCorruptionIsNotSilentlyReset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = PersistentStore(url: dir.appendingPathComponent("state.json"))
        var state = StoredState(); state.usage = try calibrated(used: 3_700_000_000)
        try disk.write(state)
        XCTAssertEqual(try disk.read().usage.usedBytes, 3_700_000_000)
        try Data("broken".utf8).write(to: disk.url)
        XCTAssertThrowsError(try disk.read())
        XCTAssertEqual(try String(contentsOf: disk.url, encoding: .utf8), "broken")
    }
    func testActualHostInterfaceEnumerationDoesNotDuplicateNames() throws {
        let items = try NetworkUsageMonitor.snapshot()
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(items.count, Set(items.map(\.name)).count)
        XCTAssertTrue(items.allSatisfy { $0.rx == nil || $0.rx! <= UInt64(UInt32.max) })
    }
}
