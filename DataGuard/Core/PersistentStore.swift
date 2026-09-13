import Foundation

struct StoredState: Codable, Sendable {
    var version = 1
    var settings = SettingsStore()
    var usage = UsageStore()
    var testLastBytes: UInt64?
    var testLastSampleAt: Date?
    var testNotifiedLevel = 0
}

// All app + in-process App Intent operations use the same MainActor owner.
// No await occurs between reading and writing a transaction.
@MainActor
final class PersistentStore {
    let url: URL
    init(url: URL) { self.url = url }
    convenience init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(url: root.appendingPathComponent("DataGuard/state.json"))
    }
    func read() throws -> StoredState {
        guard FileManager.default.fileExists(atPath: url.path) else { return StoredState() }
        let state = try JSONDecoder().decode(StoredState.self, from: Data(contentsOf: url))
        guard state.version == 1, state.settings.validationError == nil else {
            throw StoreError.invalid("저장 파일 버전 또는 설정이 잘못되었습니다. 원본을 보존하고 측정을 중단했습니다.")
        }
        return state
    }
    func write(_ state: StoredState) throws {
        let data = try JSONEncoder().encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
