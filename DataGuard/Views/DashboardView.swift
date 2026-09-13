import SwiftUI

struct DashboardView: View {
    var model: AppModel
    private var tint: Color {
        guard let report = model.report else { return .orange }
        switch report.status { case .safe: return .teal; case .warning, .unknown: return .orange; case .critical, .block: return .red }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label("사용량 단계 (추정)", systemImage: "gauge.with.dots.needle")
                    Spacer()
                    Text(model.report?.status.rawValue.uppercased() ?? "UNKNOWN")
                        .font(.headline.monospaced()).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(tint.opacity(0.12), in: Capsule()).foregroundStyle(tint)
                }
                if let report = model.report {
                    usageCard(report)
                    if report.shouldBlock {
                        Label("차단 기준 도달 · 셀룰러 사용 중단 권장", systemImage: "exclamationmark.shield")
                            .font(.headline).foregroundStyle(tint)
                    }
                    if report.requiresReview {
                        GroupBox("측정 신뢰도 안내") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(report.reason)
                                Text("사용량 단계는 기록된 추정값 기준입니다. 공백 동안 Wi-Fi만 사용한 것을 알고 있다면 다시 보정할 필요는 없습니다. 앱이 당시 연결 상태를 확인한 것은 아니며, 셀룰러 사용량이 불확실하면 통신사 값과 비교하세요.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.foregroundStyle(.orange)
                    }
                    if report.rapidUsage {
                        Label("최근 두 측정 사이 300 MB 이상 증가했습니다.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    GroupBox("최근 측정") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("증가량", value: report.settings.displayUnit.format(report.increaseBytes))
                            if let date = report.sampledAt { LabeledContent("측정 시각", value: date.formatted(date: .abbreviated, time: .standard)) }
                            if let date = report.previousSampleAt { LabeledContent("이전 시각", value: date.formatted(date: .abbreviated, time: .standard)) }
                            Text("두 측정 시점 사이의 증가량이며 실시간 속도가 아닙니다.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                } else {
                    ContentUnavailableView("측정 결과 없음", systemImage: "exclamationmark.shield", description: Text("측정이나 저장에 실패했을 수 있습니다. 안전을 위해 셀룰러 사용을 중단하고 다시 확인하세요."))
                }
                Button(action: model.refresh) { Label("지금 사용량 확인", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                VStack(alignment: .leading, spacing: 10) {
                    Label("안전하게 시작하기", systemImage: "checklist").font(.headline)
                    Text("1. 진단에서 실제 셀룰러 인터페이스를 확인·선택하세요.\n2. 설정에서 이번 달 현재 사용량을 보정하세요.\n3. 단축어의 차단 권장 확인을 앱 실행 자동화에 연결하세요.")
                }
                Text("DataGuard의 데이터 사용량은 기기에서 추정한 값이며 통신사 과금 데이터와 다를 수 있습니다. 초과 요금 방지를 위해 충분한 안전 여유를 설정하세요.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("앱이 열린 동안 30초마다, 앱 재진입과 단축어 실행 시 측정합니다. 백그라운드 상시 감시와 실시간 차단을 보장하지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 850)
                .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("데이터 사용량")
    }
    private func usageCard(_ report: UsageReport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(report.isSimulated ? "시뮬레이션" : "기기 추정 누적량").font(.subheadline).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(report.settings.displayUnit.format(report.usedBytes)).font(.system(size: 46, weight: .semibold, design: .rounded))
                    Text("/ \(report.settings.displayUnit.format(report.settings.bytes(report.settings.allowanceGB)))").foregroundStyle(.secondary)
                }
                Text(report.settings.displayUnit.format(report.usedBytes)).font(.largeTitle.bold())
            }.minimumScaleFactor(0.65)
            ProgressView(value: min(report.usedGB / report.settings.allowanceGB, 1)).tint(tint)
                .accessibilityLabel("월 한도 사용 비율")
            LabeledContent("차단 권장 기준까지", value: report.settings.displayUnit.format(report.settings.bytes(report.remainingToCutoffGB)))
            LabeledContent("월 한도까지 (추정)", value: report.settings.displayUnit.format(report.settings.bytes(report.remainingToAllowanceGB)))
            Divider()
            LabeledContent("차단 권장 기준", value: String(format: "%.2f GB", report.settings.cutoffGB))
            LabeledContent("안전 여유", value: String(format: "%.2f GB", report.settings.safetyReserveGB))
            if report.requiresReview { Text("측정 공백·누락 가능성은 아래 측정 신뢰도 안내를 확인하세요.").font(.caption).foregroundStyle(.secondary) }
            if let cycle = model.state.usage.cycleStart { Text("기간 시작: \(cycle.formatted(date: .abbreviated, time: .omitted)) · \(report.settings.timeZoneID)").font(.caption).foregroundStyle(.secondary) }
        }.padding(24).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
