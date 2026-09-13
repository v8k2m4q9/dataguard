import AppIntents
import Foundation

struct CellularUsageEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cellular Usage")
    static let defaultQuery = CellularUsageQuery()
    var id: String = "current"
    @Property(title: "usedBytes") var usedBytes: Int
    @Property(title: "usedGB") var usedGB: Double
    @Property(title: "remainingToCutoffGB") var remainingToCutoffGB: Double
    @Property(title: "remainingToAllowanceGB") var remainingToAllowanceGB: Double
    @Property(title: "status") var status: String
    @Property(title: "shouldBlock") var shouldBlock: Bool
    @Property(title: "increaseBytes") var increaseBytes: Int
    @Property(title: "rapidUsage") var rapidUsage: Bool
    @Property(title: "requiresReview") var requiresReview: Bool
    @Property(title: "isSimulated") var isSimulated: Bool
    @Property(title: "sampledAt") var sampledAt: Date
    @Property(title: "explanation") var explanation: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(usedGB) GB · \(status)") }
    init() {}
    init(_ report: UsageReport) {
        usedBytes = Int(clamping: report.usedBytes)
        usedGB = report.usedGB
        remainingToCutoffGB = report.remainingToCutoffGB
        remainingToAllowanceGB = report.remainingToAllowanceGB
        status = report.status.rawValue
        shouldBlock = report.shouldBlock
        increaseBytes = Int(clamping: report.increaseBytes)
        rapidUsage = report.rapidUsage
        requiresReview = report.requiresReview
        isSimulated = report.isSimulated
        sampledAt = report.isSimulated ? Date() : (report.sampledAt ?? .distantPast)
        explanation = report.message
    }
}
struct CellularUsageQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [CellularUsageEntity] {
        guard identifiers.contains("current") else { return [] }
        return [CellularUsageEntity(try await AppModel.shared.checkAndNotify())]
    }
    func suggestedEntities() async throws -> [CellularUsageEntity] { [] }
}
struct GetCellularUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Cellular Usage"
    static let description = IntentDescription("셀룰러 추정 사용량과 shouldBlock, 측정 확인 필요 여부를 반환합니다. GB는 Decimal 단위입니다.")
    static let openAppWhenRun = false
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CellularUsageEntity> {
        .result(value: CellularUsageEntity(try await AppModel.shared.checkAndNotify()))
    }
}
struct CheckDataLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Data Limit"
    static let description = IntentDescription("현재 사용량과 셀룰러 중단 권고를 한국어 문장으로 반환합니다.")
    static let openAppWhenRun = false
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let message: String
        do { message = try await AppModel.shared.checkAndNotify().message }
        catch { message = "측정 실패. 안전을 위해 셀룰러 데이터를 끄고 DataGuard를 열어 확인하세요. " + error.localizedDescription }
        return .result(value: message)
    }
}
struct ShouldBlockCellularIntent: AppIntent {
    static let title: LocalizedStringResource = "Should Block Cellular"
    static let description = IntentDescription("IF 조건에 바로 쓰는 Boolean. 설정한 차단 기준에 도달하면 true입니다. 앱이 직접 셀룰러를 끄지는 않습니다.")
    static let openAppWhenRun = false
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let shouldBlock: Bool
        do { shouldBlock = try await AppModel.shared.checkAndNotify().shouldBlock }
        catch { shouldBlock = false }
        return .result(value: shouldBlock)
    }
}
struct DataGuardShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetCellularUsageIntent(), phrases: ["Get cellular usage with \(.applicationName)"], shortTitle: "사용량 상세 확인", systemImageName: "chart.bar")
        AppShortcut(intent: CheckDataLimitIntent(), phrases: ["Check data limit with \(.applicationName)"], shortTitle: "데이터 한도 확인", systemImageName: "gauge.with.dots.needle.33percent")
        AppShortcut(intent: ShouldBlockCellularIntent(), phrases: ["Should I stop cellular with \(.applicationName)"], shortTitle: "차단 권장 확인", systemImageName: "exclamationmark.shield")
    }
}
