import SwiftUI

@main
struct MetroTimerApp: App {
    @StateObject private var engine = TripEngine.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Делегат должен стоять до окончания запуска — иначе foreground-показ не работает.
        NotificationPresenter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        activate()
                    } else {
                        AlertService.shared.stop()
                        // Тикер обновляет только остров и только в foreground.
                        engine.suspendTicker()
                    }
                }
                // onChange не срабатывает для начального значения scenePhase.
                // Без этого холодный старт с восстановленной поездкой зависел бы
                // от того, пройдёт ли SwiftUI через .inactive → .active.
                // Обе операции идемпотентны, повторный вызов безвреден.
                // .task {} уже на главном акторе, activate() синхронная — await не нужен.
                .task { activate() }
        }
    }

    // Всё, что нужно сделать, когда приложение оказалось на переднем плане.
    @MainActor
    private func activate() {
        engine.refresh()
        // Тривоги опитуємо лише поки застосунок відкритий.
        AlertService.shared.startIfEnabled()
    }
}

struct RootView: View {
    @EnvironmentObject private var engine: TripEngine

    var body: some View {
        ZStack {
            if engine.trip != nil {
                TripView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity))
            } else {
                SelectionView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: engine.trip != nil)
        // Всё приложение — «подземная» тёмная тема.
        .preferredColorScheme(.dark)
        // Не на пути запуска: CLLocationManager и XPC поднимаем после первого кадра.
        .task { LocationCorrector.shared.activate() }
        .onOpenURL { url in
            handle(url)
        }
        .onAppear {
            #if DEBUG
            // Отладочный автостарт: simctl launch ... -MTStartFrom <id> -MTStartTo <id>
            let defaults = UserDefaults.standard
            let from = defaults.string(forKey: "MTStartFrom")
            let to = defaults.string(forKey: "MTStartTo")
            let delta = defaults.string(forKey: "MTAdjust").flatMap(Int.init)
            // Перемотка поездки к станции: -MTAnchor <индекс события> — иначе
            // до пересадки в симуляторе пришлось бы ждать двадцать минут.
            let anchor = defaults.string(forKey: "MTAnchor").flatMap(Int.init)
            for key in ["MTStartFrom", "MTStartTo", "MTAdjust", "MTAnchor"] {
                defaults.removeObject(forKey: key)
            }
            // Один Task на всё: коррекции применяются строго после старта.
            Task {
                if let from, let to {
                    // В проде старт при активной поездке невозможен (UI занят TripView);
                    // хук воспроизводит это правило явно.
                    if engine.trip != nil {
                        engine.stopByUser()
                    }
                    await engine.start(fromId: from, toId: to)
                }
                if let anchor { await engine.syncPosition(anchorIndex: anchor) }
                if let delta { await engine.adjust(by: delta) }
            }
            #endif
        }
    }

    // metrotimer://trip — тап по Live Activity просто открывает приложение.
    private func handle(_ url: URL) {
        #if DEBUG
        // Отладочный запуск поездки диплинком: metrotimer://start?from=<id>&to=<id>
        guard url.host == "start",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let from = components.queryItems?.first(where: { $0.name == "from" })?.value,
              let to = components.queryItems?.first(where: { $0.name == "to" })?.value
        else { return }
        Task { await engine.start(fromId: from, toId: to) }
        #endif
    }
}
