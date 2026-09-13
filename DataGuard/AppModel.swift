import Foundation
import Observation

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    private let disk = PersistentStore()
    var state = StoredState()
    var interfaces: [InterfaceSnapshot] = []
    var report: UsageReport?
    var errorMessage: String?
    var notice: String?

    @discardableResult
    func check() throws -> UsageReport {
        do {
            var next = try disk.read()
            let samples = try NetworkUsageMonitor.snapshot()
            interfaces = samples
            var simulatedIncrease: UInt64 = 0
            let previousTestDate = next.testLastSampleAt
            if next.settings.testMode {
                let current = next.settings.bytes(next.settings.simulatedGB)
                if let previous = next.testLastBytes { simulatedIncrease = current >= previous ? current - previous : 0 }
                next.testLastBytes = current
                next.testLastSampleAt = Date()
            } else {
                next.usage.ingest(samples, settings: next.settings, now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
            }
            try disk.write(next)
            state = next
            var result = UsageReport.make(settings: next.settings, usage: next.usage, simulatedIncrease: simulatedIncrease)
            if next.settings.testMode {
                result.sampledAt = next.testLastSampleAt
                result.previousSampleAt = previousTestDate
            }
            report = result
            errorMessage = nil
            return result
        } catch {
            report = nil // Never expose a cached SAFE result after failed measurement or persistence.
            errorMessage = "측정/저장 실패. 셀룰러 사용을 중단하고 확인하세요. \(error.localizedDescription)"
            throw error
        }
    }
    func checkAndNotify() async throws -> UsageReport {
        let result = try check()
        await NotificationService.shared.notifyIfNeeded(result)
        return result
    }
    func refresh() {
        guard let result = try? check() else { return }
        Task { await NotificationService.shared.notifyIfNeeded(result) }
    }
    func saveSettings(_ settings: SettingsStore) {
        do {
            if let error = settings.validationError { throw StoreError.invalid(error) }
            var next = try disk.read()
            if next.settings.selectedInterfaces != settings.selectedInterfaces {
                next.usage.baselines = [:]
                next.usage.markUncertain("측정 인터페이스가 변경되었습니다. 현재 통신사 사용량으로 보정하세요.")
            }
            if next.settings.billingDay != settings.billingDay || next.settings.timeZoneID != settings.timeZoneID {
                // Preserve used bytes on a configuration change, instead of accidentally giving a fresh allowance.
                next.usage.cycleStart = settings.cycleStart(at: Date())
                next.usage.markUncertain("청구 기간 설정이 바뀌었습니다. 누적량을 보존했으며 보정이 필요합니다.")
            }
            if next.settings.testMode != settings.testMode {
                next.testLastBytes = nil
                next.testLastSampleAt = nil
                next.testNotifiedLevel = 0
            }
            next.settings = settings
            try disk.write(next)
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func selectInterface(_ name: String, enabled: Bool) {
        do {
            var settings = try disk.read().settings
            if enabled { settings.selectedInterfaces.insert(name) } else { settings.selectedInterfaces.remove(name) }
            saveSettings(settings)
        } catch { errorMessage = error.localizedDescription }
    }
    func reconcile(gb: Double) {
        do {
            guard gb.isFinite, gb >= 0, gb <= 10_000 else { throw StoreError.invalid("사용량은 0~10,000 GB 범위여야 합니다.") }
            var next = try disk.read()
            guard !next.settings.testMode else { throw StoreError.invalid("테스트 모드를 먼저 끄세요.") }
            let samples = try NetworkUsageMonitor.snapshot()
            try next.usage.reconcile(bytes: next.settings.bytes(gb), interfaces: samples,
                                     settings: next.settings, now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
            try disk.write(next)
            refresh()
            notice = "사용량을 보정했습니다. 이후 카운터 증가량을 더합니다."
        } catch { errorMessage = error.localizedDescription }
    }
    func resetNow() { reconcile(gb: 0) }
    func disableTestMode() {
        do { var settings = try disk.read().settings; settings.testMode = false; saveSettings(settings) }
        catch { errorMessage = error.localizedDescription }
    }
}
