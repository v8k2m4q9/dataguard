import Foundation

enum DisplayUnit: String, Codable, CaseIterable, Sendable {
    case gb = "GB", gib = "GiB"
    var divisor: Double { self == .gb ? 1_000_000_000 : 1_073_741_824 }
    func format(_ bytes: UInt64) -> String {
        String(format: "%.2f %@", Double(bytes) / divisor, rawValue)
    }
}

struct SettingsStore: Codable, Equatable, Sendable {
    // Plan amounts always use decimal GB; changing display units never changes thresholds.
    var allowanceGB = 5.0
    var warningGB = 3.5
    var criticalGB = 3.8
    var cutoffGB = 4.0
    var billingDay = 1
    var timeZoneID = TimeZone.current.identifier
    var displayUnit = DisplayUnit.gb
    var selectedInterfaces: Set<String> = []
    var rapidWarningEnabled = true
    var testMode = false
    var simulatedGB = 3.4
    var safetyReserveGB: Double { allowanceGB - cutoffGB }
    var validationError: String? {
        let values = [allowanceGB, warningGB, criticalGB, cutoffGB, simulatedGB]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 10_000 }) else { return "0~10,000 범위의 숫자를 입력하세요." }
        guard allowanceGB > 0, warningGB > 0, warningGB < criticalGB,
              criticalGB < cutoffGB, cutoffGB < allowanceGB else {
            return "0 < 경고 < 위험 < 차단 권장 기준 < 월 한도 순서로 설정하세요."
        }
        guard (1...31).contains(billingDay), TimeZone(identifier: timeZoneID) != nil else { return "유효한 청구 시작일과 시간대가 필요합니다." }
        return nil
    }
    func bytes(_ gb: Double) -> UInt64 { UInt64(max(0, min(10_000, gb.isFinite ? gb : 0)) * 1_000_000_000) }
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
        return c
    }
    func cycleStart(at now: Date) -> Date {
        let c = calendar
        let month = c.dateInterval(of: .month, for: now)!.start
        func start(_ date: Date) -> Date {
            let last = c.range(of: .day, in: .month, for: date)!.count
            return c.date(byAdding: .day, value: min(billingDay, last) - 1, to: date)!
        }
        let candidate = start(month)
        return now >= candidate ? candidate : start(c.date(byAdding: .month, value: -1, to: month)!)
    }
}
