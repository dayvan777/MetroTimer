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

    // Скільки поспіль невдалих спроб терпимо, перш ніж сказати про це вголос.
    // Мовчазний відмова гірша за відсутність функції: «банера немає» читалося б
    // як «тривоги немає», хоча насправді ми просто не знаємо.
    private static let failuresBeforeUnavailable = 3

    enum State: Equatable {
        case unknown        // ще не питали
        case quiet
        case alert
        case unavailable    // джерело не відповідає — ми НЕ знаємо, чи є тривога
    }

    @Published private(set) var state: State = .unknown
    @Published private(set) var updatedAt: Date?

    private var timer: Timer?
    private var isFetching = false
    private var consecutiveFailures = 0

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private init() {}

    // MARK: - Життєвий цикл опитування

    func startIfEnabled() {
        #if DEBUG
        // Тривоги трапляються рідко, а відмова джерела — ще рідше. Щоб перевірити
        // вигляд обох станів: simctl launch ... -MTForceAlert 1 | -MTForceAlertFail 1
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "MTForceAlert") != nil {
            state = .alert
            updatedAt = Date()
            return
        }
        if defaults.string(forKey: "MTForceAlertFail") != nil {
            state = .unavailable
            return
        }
        #endif
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
            consecutiveFailures = 0
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
            guard let fetched else {
                // Джерело не відповіло. Кілька спроб тримаємо останній відомий
                // стан (мережа в метро зникає постійно), далі — чесно кажемо,
                // що не знаємо, замість того щоб мовчки показувати «тривоги немає».
                self.consecutiveFailures += 1
                if self.consecutiveFailures >= Self.failuresBeforeUnavailable {
                    self.state = .unavailable
                }
                return
            }
            self.consecutiveFailures = 0
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
