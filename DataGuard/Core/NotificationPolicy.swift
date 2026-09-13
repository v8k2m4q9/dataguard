import Foundation

struct NotificationPolicy {
    static func level(bytes: UInt64, settings: SettingsStore) -> Int {
        if bytes >= settings.bytes(settings.cutoffGB) { return 3 }
        if bytes >= settings.bytes(settings.criticalGB) { return 2 }
        if bytes >= settings.bytes(settings.warningGB) { return 1 }
        return 0
    }
    static func nextLevel(bytes: UInt64, settings: SettingsStore, notifiedLevel: Int) -> Int? {
        let level = level(bytes: bytes, settings: settings)
        return level > notifiedLevel ? level : nil
    }
}
