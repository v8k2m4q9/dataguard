import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private let disk = PersistentStore()
    private var busy = false
    private var pending: UsageReport?
    func configure() { UNUserNotificationCenter.current().delegate = self }
    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    func notifyIfNeeded(_ report: UsageReport) async {
        pending = report
        guard !busy else { return }
        busy = true
        defer { busy = false }
        while let report = pending {
            pending = nil
            await deliver(report)
        }
    }
    private func deliver(_ report: UsageReport) async {
        let center = UNUserNotificationCenter.current()
        let permission = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(permission.authorizationStatus) else { return }
        do {
            var state = try disk.read()
            // Ignore a result overtaken by settings changes, correction, or a new billing cycle.
            guard state.settings == report.settings,
                  report.isSimulated || (state.usage.lastSampleAt == report.sampledAt && state.usage.usedBytes == report.usedBytes) else { return }
            let previous = report.isSimulated ? state.testNotifiedLevel : state.usage.notifiedLevel
            guard let level = NotificationPolicy.nextLevel(bytes: report.usedBytes, settings: state.settings, notifiedLevel: previous) else { return }
            let content = UNMutableNotificationContent()
            let prefix = report.isSimulated ? "[테스트] " : ""
            switch level {
            case 3: content.title = prefix + "데이터 차단 기준 도달"
            case 2: content.title = prefix + "데이터 사용량 위험"
            default: content.title = prefix + String(format: "데이터 %.2f GB 사용", report.usedGB)
            }
            content.body = level == 3 ? "초과 요금 방지를 위해 셀룰러 데이터를 끄세요."
                : String(format: "안전 차단 기준 %.2f GB까지 약 %.0f MB 남았습니다.", report.settings.cutoffGB, report.remainingToCutoffGB * 1000)
            if report.requiresReview { content.body += " 측정 누락 가능성이 있습니다. 앱에서 측정 신뢰도 안내를 확인하세요." }
            content.sound = .default
            let token = "dataguard-\(report.isSimulated ? "test" : "live")-\(state.usage.cycleStart?.timeIntervalSince1970 ?? 0)-\(level)"
            if report.isSimulated { state.testNotifiedLevel = level } else { state.usage.notifiedLevel = level }
            try disk.write(state) // Reserve before awaiting to prevent duplicate notifications.
            do {
                try await center.add(UNNotificationRequest(identifier: token, content: content, trigger: nil))
            } catch {
                var latest = try disk.read()
                if latest.settings == state.settings && latest.usage.cycleStart == state.usage.cycleStart {
                    if report.isSimulated && latest.testNotifiedLevel == level { latest.testNotifiedLevel = previous }
                    if !report.isSimulated && latest.usage.notifiedLevel == level { latest.usage.notifiedLevel = previous }
                    try disk.write(latest)
                }
                throw error
            }
        } catch {
            AppModel.shared.notice = "알림을 전송하지 못했습니다: \(error.localizedDescription)"
        }
    }
}
