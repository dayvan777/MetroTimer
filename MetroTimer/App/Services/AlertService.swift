import Foundation
import SwiftUI
import UserNotifications

// Повітряні тривоги — ЄДИНЕ місце в застосунку, яке ходить у мережу, і лише
// коли користувач сам увімкнув перемикач (за замовчуванням вимкнено — базовий
// сценарій лишається повністю офлайн).
//
// Джерело: публічний фід статусів по областях (ключ не потрібен, персональні
// дані не передаються — це звичайний GET без параметрів).
// Опитування тільки поки застосунок відкритий: жодних фонових режимів.
@MainActor
final class AlertService: ObservableObject {
    static let shared = AlertService()

    static let enabledKey = "airAlertsEnabled"
    private static let endpoint = URL(string: "https://ubilling.net.ua/aerialalerts/")!
    private static let kyivKey = "м. Київ"
    private static let pollInterval: TimeInterval = 60
    private static let notificationId = "kyiv.airAlert"

    enum State: Equatable {
        case unknown        // ще не питали або мережа недоступна
        case quiet
        case alert
    }

    @Published private(set) var state: State = .unknown
    @Published private(set) var updatedAt: Date?

    private var timer: Timer?
    private var isFetching = false

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private init() {}

    // MARK: - Життєвий цикл опитування

    func startIfEnabled() {
        guard isEnabled else { stop(); return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // Перемикач у налаштуваннях застосунку.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            startIfEnabled()
        } else {
            stop()
            state = .unknown
            updatedAt = nil
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        }
    }

    // MARK: - Запит

    func refresh() {
        guard isEnabled, !isFetching else { return }
        isFetching = true
        Task { [weak self] in
            let fetched = await Self.fetchKyivAlert()
            guard let self else { return }
            self.isFetching = false
            guard let fetched else { return }        // мережа недоступна — лишаємо як було
            let newState: State = fetched ? .alert : .quiet
            let wasQuiet = self.state == .quiet
            self.state = newState
            self.updatedAt = Date()
            // Сповіщаємо лише про ПОЧАТОК тривоги і лише під час поїздки:
            // поза поїздкою для цього є спеціалізовані застосунки.
            if newState == .alert, wasQuiet, TripEngine.shared.trip != nil {
                Self.notifyAlertStarted()
            }
        }
    }

    // nil — не вдалося дізнатися (немає мережі, зміна формату тощо).
    private static func fetchKyivAlert() async -> Bool? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = json["states"] as? [String: Any],
              let kyiv = states[kyivKey] as? [String: Any],
              let active = kyiv["alertnow"] as? Bool
        else { return nil }
        return active
    }

    private static func notifyAlertStarted() {
        let content = UNMutableNotificationContent()
        content.title = L10n.alertNotifTitle
        content.body = L10n.alertNotifBody
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: notificationId, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}
