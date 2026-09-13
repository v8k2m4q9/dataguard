import Foundation

struct CounterBaseline: Codable, Sendable {
    var index: UInt32
    var rx: UInt64
    var tx: UInt64
}
struct UsageStore: Codable, Sendable {
    var usedBytes: UInt64 = 0
    var lastIncreaseBytes: UInt64 = 0
    var lastSampleAt: Date?
    var previousSampleAt: Date?
    var lastUptime: TimeInterval?
    var cycleStart: Date?
    var baselines: [String: CounterBaseline] = [:]
    var needsReview = true
    var reviewReason = "최초 측정 이전의 이번 달 사용량을 확인하고 보정하세요."
    var notifiedLevel = 0
    var history: [UsageSample] = []

    mutating func markUncertain(_ reason: String) {
        needsReview = true
        reviewReason = reason
    }
    mutating func ingest(_ interfaces: [InterfaceSnapshot], settings: SettingsStore, now: Date, uptime: TimeInterval) {
        let start = settings.cycleStart(at: now)
        if let cycleStart, cycleStart != start {
            usedBytes = 0
            notifiedLevel = 0
            history = []
            // A cross-boundary delta cannot be split accurately. Charge all of it to the new cycle.
            markUncertain("청구 기간이 바뀌었습니다. 경계에 걸친 증가량을 새 기간에 포함했으므로 사용량을 확인하세요.")
        }
        cycleStart = start
        var restarted = false
        if let lastSampleAt, let lastUptime {
            let elapsed = now.timeIntervalSince(lastSampleAt)
            restarted = uptime < lastUptime || abs((uptime - lastUptime) - elapsed) > 5
            if restarted {
                markUncertain("재부팅 또는 시간 변경이 감지되었습니다. 복구할 수 없는 사용량이 있을 수 있습니다.")
            } else if elapsed > 900 {
                markUncertain("15분 이상 측정 공백입니다. 카운터 순환·재생성으로 누락된 사용량이 있을 수 있습니다.")
            }
        }
        let names = settings.selectedInterfaces.isEmpty
            ? Set(interfaces.filter(\.isCellularCandidate).map(\.name)) : settings.selectedInterfaces
        if settings.selectedInterfaces.isEmpty {
            markUncertain("셀룰러 인터페이스가 검증되지 않았습니다. 진단 화면에서 확인 후 선택하세요.")
        }
        if names.isEmpty { markUncertain("측정 가능한 셀룰러 인터페이스를 찾지 못했습니다.") }
        var increase: UInt64 = 0
        for name in names {
            guard let current = interfaces.first(where: { $0.name == name }), let rx = current.rx, let tx = current.tx else {
                markUncertain("선택한 인터페이스가 없거나 카운터를 제공하지 않습니다: \(name)")
                continue // Keep the previous baseline; never silently clear accumulated usage.
            }
            if let previous = baselines[name] {
                if restarted || previous.index != current.index {
                    increase += rx + tx
                    markUncertain("인터페이스 재생성·재부팅 이후의 카운터를 더했습니다. 통신사 사용량으로 보정하세요.")
                } else {
                    // Treat decreases as a reset lower bound, not a guessed 32-bit wrap.
                    // A wrap and a reset cannot be distinguished; require reconciliation.
                    increase += rx >= previous.rx ? rx - previous.rx : rx
                    increase += tx >= previous.tx ? tx - previous.tx : tx
                    if rx < previous.rx || tx < previous.tx {
                        markUncertain("카운터 감소: 초기화와 32비트 순환을 구분할 수 없습니다. 사용량 보정이 필요합니다.")
                    }
                }
            } else {
                markUncertain("새 인터페이스의 기준값을 저장했습니다. 이전 사용량은 보정이 필요합니다.")
            }
            baselines[name] = CounterBaseline(index: current.index, rx: rx, tx: tx)
        }
        usedBytes += increase
        lastIncreaseBytes = increase
        previousSampleAt = lastSampleAt
        lastSampleAt = now
        lastUptime = uptime
        history.append(UsageSample(date: now, total: usedBytes, increase: increase))
        history = Array(history.suffix(100))
    }

    mutating func reconcile(bytes: UInt64, interfaces: [InterfaceSnapshot], settings: SettingsStore, now: Date, uptime: TimeInterval) throws {
        guard !settings.selectedInterfaces.isEmpty,
              settings.selectedInterfaces.allSatisfy({ name in interfaces.contains { $0.name == name && $0.rx != nil && $0.tx != nil } }) else {
            throw StoreError.invalid("현재 카운터를 읽을 수 있는 인터페이스를 진단에서 먼저 선택하세요.")
        }
        usedBytes = bytes
        baselines = [:]
        lastSampleAt = nil
        lastUptime = nil
        cycleStart = settings.cycleStart(at: now)
        history = []
        notifiedLevel = 0
        ingest(interfaces, settings: settings, now: now, uptime: uptime)
        needsReview = false
        reviewReason = "사용자 보정 이후의 기기 추정값입니다. 누락 없는 측정을 보장하지 않습니다."
    }
}
struct UsageSample: Codable, Identifiable, Sendable {
    var date: Date
    var total: UInt64
    var increase: UInt64
    var id: Date { date }
}
enum UsageStatus: String, Sendable {
    case safe, warning, critical, block, unknown
    var level: Int {
        switch self { case .safe, .unknown: 0; case .warning: 1; case .critical: 2; case .block: 3 }
    }
}
struct UsageReport: Sendable {
    var usedBytes: UInt64
    var increaseBytes: UInt64
    var sampledAt: Date?
    var previousSampleAt: Date?
    var status: UsageStatus
    var shouldBlock: Bool
    var requiresReview: Bool
    var isSimulated: Bool
    var rapidUsage: Bool
    var reason: String
    var settings: SettingsStore
    var usedGB: Double { Double(usedBytes) / 1_000_000_000 }
    var remainingToCutoffGB: Double { max(0, settings.cutoffGB - usedGB) }
    var remainingToAllowanceGB: Double { max(0, settings.allowanceGB - usedGB) }
    static func make(settings: SettingsStore, usage: UsageStore, simulatedIncrease: UInt64 = 0) -> Self {
        let bytes = settings.testMode ? settings.bytes(settings.simulatedGB) : usage.usedBytes
        let review = !settings.testMode && usage.needsReview
        let threshold: UsageStatus = bytes >= settings.bytes(settings.cutoffGB) ? .block
            : bytes >= settings.bytes(settings.criticalGB) ? .critical
            : bytes >= settings.bytes(settings.warningGB) ? .warning : .safe
        let increase = settings.testMode ? simulatedIncrease : usage.lastIncreaseBytes
        return Self(usedBytes: bytes, increaseBytes: increase, sampledAt: usage.lastSampleAt,
                    previousSampleAt: usage.previousSampleAt, status: threshold,
                    shouldBlock: threshold == .block, requiresReview: review, isSimulated: settings.testMode,
                    rapidUsage: settings.rapidWarningEnabled && increase >= 300_000_000 && bytes >= settings.bytes(settings.warningGB),
                    reason: settings.testMode ? "테스트 데이터입니다. 실제 사용량이 아닙니다." : usage.reviewReason, settings: settings)
    }
    var message: String {
        let prefix = isSimulated ? "[테스트] " : ""
        let summary = shouldBlock ? "데이터 차단 기준에 도달했습니다. 셀룰러 데이터를 끄세요."
            : String(format: "셀룰러 데이터 %.2f GB 사용 (추정). 차단 기준까지 약 %.0f MB 남았습니다.", usedGB, remainingToCutoffGB * 1000)
        return prefix + summary + (requiresReview ? " 측정 신뢰도 안내: " + reason : "")
    }
}
enum StoreError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): text } }
}
