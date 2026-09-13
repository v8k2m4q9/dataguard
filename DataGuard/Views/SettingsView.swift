import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @State private var draft = SettingsStore()
    @State private var correctionGB = 0.0
    @State private var confirmReset = false
    @State private var confirmCorrection = false
    @State private var saved = false
    @State private var notificationMessage: String?
    var body: some View {
        Form {
            Section("요금제 · 모든 기준은 Decimal GB") {
                amount("월 데이터 한도", value: $draft.allowanceGB)
                amount("경고", value: $draft.warningGB)
                amount("위험 경고", value: $draft.criticalGB)
                amount("차단 권장 기준", value: $draft.cutoffGB)
                amount("안전 여유", value: Binding(get: { draft.safetyReserveGB }, set: { draft.cutoffGB = draft.allowanceGB - $0 }))
                Text("차단 권장 기준 + 안전 여유 = 월 한도. 한쪽을 바꾸면 다른 값이 함께 바뀝니다.").font(.caption)
                if draft.cutoffGB >= 4.5 && draft.allowanceGB <= 5.0 || draft.safetyReserveGB < 0.5 {
                    Text("안전 여유가 작습니다. 고화질 동영상 사용 중 한도를 초과할 수 있습니다.").foregroundStyle(.orange)
                }
                if let error = draft.validationError { Text(error).foregroundStyle(.red) }
            }
            Section("청구 기간과 표시") {
                Stepper("매월 \(draft.billingDay)일 시작", value: $draft.billingDay, in: 1...31)
                Text("해당 날짜가 없는 달은 그 달의 마지막 날에 시작합니다.").font(.caption)
                LabeledContent("청구 시간대", value: draft.timeZoneID)
                Button("현재 기기 시간대로 변경") { draft.timeZoneID = TimeZone.current.identifier }
                Picker("표시 단위", selection: $draft.displayUnit) {
                    ForEach(DisplayUnit.allCases, id: \.self) { unit in Text(unit.rawValue).tag(unit) }
                }
                Text("GB = 10억 bytes · GiB = 1,073,741,824 bytes. 표시를 바꿔도 요금제 기준과 단축어 GB 값은 바뀌지 않습니다.").font(.caption)
                Toggle("Rapid Usage Warning", isOn: $draft.rapidWarningEnabled)
            }
            Section("Developer / Test Mode") {
                Toggle("가상 사용량 사용", isOn: $draft.testMode)
                if draft.testMode {
                    Picker("가상 사용량", selection: $draft.simulatedGB) {
                        ForEach([0.0, 3.4, 3.5, 3.8, 3.99, 4.0, 4.5, 5.0], id: \.self) { value in
                            Text(String(format: "%.2f GB", value)).tag(value)
                        }
                    }
                    Text("단축어의 shouldBlock도 가상값에 따라 바뀝니다. 연결한 Apple 액션은 실제 셀룰러를 끌 수 있습니다. 테스트 후 종료하세요.").foregroundStyle(.orange)
                }
            }
            Section {
                Button("설정 저장") {
                    model.saveSettings(draft)
                    saved = model.errorMessage == nil
                }.disabled(draft.validationError != nil)
                if saved { Text("저장했습니다.").foregroundStyle(.secondary) }
            }
            Section("실제 사용량 보정") {
                Text("처음 알려주신 사용량은 0바이트입니다. 진단 테스트 중 사용한 데이터까지 반영해 현재 이번 달 누적량을 입력하세요. 통신사 조회값은 반영이 늦을 수 있습니다.")
                amount("현재 사용량 (GB)", value: $correctionGB)
                Button("이 값으로 보정") { confirmCorrection = true }.disabled(model.state.settings.testMode)
                if let notice = model.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                Text("선택한 인터페이스의 기준값을 새로 저장합니다. 불확실성 경고는 보정 후 해제되지만 정확한 과금량을 보장하지는 않습니다.").font(.caption)
            }
            Section("수동 초기화") {
                Button("Reset now · 0으로 초기화", role: .destructive) { confirmReset = true }.disabled(model.state.settings.testMode)
                Text("앱 누적량만 초기화됩니다. 통신사 과금량과 iPad 설정의 통계는 초기화되지 않습니다.").font(.caption)
            }
            Section("로컬 알림") {
                Button("알림 권한 요청 / 확인") {
                    Task {
                        do {
                            let allowed = try await NotificationService.shared.requestPermission()
                            notificationMessage = allowed ? "알림이 허용되었습니다." : "알림이 꺼져 있습니다. iPad 설정 > 알림 > DataGuard에서 허용하세요."
                            model.refresh()
                        } catch { notificationMessage = error.localizedDescription }
                    }
                }
                if let notificationMessage { Text(notificationMessage).font(.caption) }
                Text("측정할 때 새로 도달한 가장 높은 단계에서 한 번 알립니다. 백그라운드에서 측정 자체를 예약하지는 않습니다.").font(.caption)
            }
            Section("단축어 연결") {
                Text("단축어에서 DataGuard의 ‘Should Block Cellular’를 실행하고 결과가 참이면 Apple의 셀룰러 데이터 끄기 액션을 연결하세요. 해당 액션이 실제 iPad에 없다면 알림을 표시하고 제어 센터에서 직접 끄세요.")
                Text("shouldBlock은 설정한 차단 기준에 도달했을 때만 참입니다. 측정 확인 필요 상태는 앱에서 별도로 안내합니다.").font(.caption)
            }
        }
        .navigationTitle("설정")
        .onAppear { draft = model.state.settings }
        .onChange(of: draft) { _, _ in saved = false }
        .confirmationDialog("앱 누적량을 0으로 초기화할까요?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("0으로 초기화", role: .destructive) { model.resetNow() }
        } message: { Text("이미 사용한 과금 데이터는 사라지지 않습니다. 이번 달 사용량이 실제로 0인지 확인하세요.") }
        .confirmationDialog("현재 사용량을 보정할까요?", isPresented: $confirmCorrection, titleVisibility: .visible) {
            Button(String(format: "%.3f GB로 보정", correctionGB)) { model.reconcile(gb: correctionGB) }
        } message: { Text("기존 앱 누적량을 입력한 값으로 바꾸고 현재 카운터를 기준으로 다시 측정합니다.") }
    }
    private func amount(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number.precision(.fractionLength(0...3)))
                .multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(maxWidth: 130)
                .accessibilityLabel(label)
        }
    }
}
