import SwiftUI

@main
struct DataGuardApp: App {
    init() { NotificationService.shared.configure() }
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

private enum Page: String, CaseIterable, Identifiable {
    case dashboard = "대시보드", diagnostics = "인터페이스 진단", settings = "설정"
    var id: Self { self }
    var symbol: String {
        switch self { case .dashboard: "gauge.with.dots.needle.33percent"; case .diagnostics: "network"; case .settings: "slider.horizontal.3" }
    }
}
struct RootView: View {
    @State private var model = AppModel.shared
    @State private var selection: Page? = .dashboard
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.symbol).tag(page)
            }
            .navigationTitle("DataGuard")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("기기 사용량 추정", systemImage: "shield.lefthalf.filled")
                    Text("셀룰러를 직접 차단하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
        } detail: {
            NavigationStack {
                Group {
                    switch selection ?? .dashboard {
                    case .dashboard: DashboardView(model: model)
                    case .diagnostics: DiagnosticsView(model: model)
                    case .settings: SettingsView(model: model)
                    }
                }
                .safeAreaInset(edge: .top) {
                    if model.state.settings.testMode {
                        HStack {
                            Label("테스트 모드 · 단축어도 가상 사용량을 반환합니다", systemImage: "testtube.2")
                            Spacer()
                            Button("테스트 종료") { model.disableTestMode() }.buttonStyle(.bordered)
                        }.font(.callout).padding().background(.orange.opacity(0.16))
                    }
                }
            }
        }
        .alert("확인 필요", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            model.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                guard scenePhase == .active else { break }
                model.refresh()
            }
        }
    }
}
