import SwiftUI

struct DiagnosticsView: View {
    var model: AppModel
    @State private var reference: [InterfaceSnapshot] = []
    @State private var referenceAt: Date?
    var body: some View {
        List {
            Section("실제 기기에서 검증") {
                Text("인터페이스 이름은 Apple의 공개 API 계약이 아닙니다. pdp_ip 접두사는 후보 표시일 뿐입니다. Wi-Fi를 끄고 소량의 데이터를 사용해 증가량을 비교하세요.")
                Text("RX / TX 각각 32비트이며 4,294,967,296 bytes마다 순환할 수 있습니다. 여러 인터페이스를 선택하면 중복 집계될 수 있습니다.")
                Button("비교 기준 저장") { model.refresh(); reference = model.interfaces; referenceAt = Date() }
                if let referenceAt { Text("비교 기준: \(referenceAt.formatted(date: .omitted, time: .standard))").font(.caption) }
                if model.interfaces.isEmpty { Text("인터페이스가 없거나 아직 측정하지 않았습니다.").foregroundStyle(.orange) }
            }
            ForEach(model.interfaces) { item in
                Section(item.name) {
                    LabeledContent("Index", value: String(item.index))
                    LabeledContent("RX", value: format(item.rx))
                    LabeledContent("TX", value: format(item.tx))
                    LabeledContent("RX + TX", value: format(item.total))
                    LabeledContent("Cellular candidate", value: item.isCellularCandidate ? "미검증 후보" : "아니요")
                    if let previous = reference.first(where: { $0.name == item.name }) {
                        LabeledContent("기준 이후 RX / TX", value: "\(delta(item.rx, previous.rx)) / \(delta(item.tx, previous.tx))")
                    }
                    Toggle("이 인터페이스 사용 (Expert)", isOn: Binding(
                        get: { model.state.settings.selectedInterfaces.contains(item.name) },
                        set: { model.selectInterface(item.name, enabled: $0) }))
                    ForEach(item.addresses, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                }
            }
            let missing = model.state.settings.selectedInterfaces.subtracting(Set(model.interfaces.map(\.name)))
            if !missing.isEmpty {
                Section("현재 사라진 선택 인터페이스") {
                    ForEach(missing.sorted(), id: \.self) { name in
                        Button("\(name) 선택 해제") { model.selectInterface(name, enabled: false) }
                    }
                }
            }
        }
        .navigationTitle("인터페이스 진단")
        .toolbar { Button("새로 측정", systemImage: "arrow.clockwise", action: model.refresh) }
        .onAppear { model.refresh() }
    }
    private func format(_ bytes: UInt64?) -> String {
        guard let bytes else { return "제공되지 않음" }
        return "\(model.state.settings.displayUnit.format(bytes)) · \(bytes) bytes"
    }
    private func delta(_ now: UInt64?, _ before: UInt64?) -> String {
        guard let now, let before else { return "미확인" }
        guard now >= before else { return "초기화/순환" }
        return String(format: "%.1f MB", Double(now - before) / 1_000_000)
    }
}
