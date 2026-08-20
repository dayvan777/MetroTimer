import Foundation
import UserNotifications

final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private static let nextStopId = "trip.nextStop"
    private static let arrivalId = "trip.arrival"

    private init() {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // Что именно планируется — чистая функция без UserNotifications: так её
    // проверяют тесты, а schedule(for:) только раскладывает результат по системе.
    struct PlannedNotification: Equatable {
        let id: String
        let title: String
        let body: String
        let date: Date
    }

    // Все уведомления планируются разом в момент старта (и после каждой коррекции):
    // «наступна — ваша» и прибытие, плюс по предупреждению на каждую пересадку.
    static func plan(for trip: ActiveTrip, now: Date) -> [PlannedNotification] {
        var requests: [PlannedNotification] = []

        // Устаревшее «наступна — ваша» (переплан уже за станцией выхода) не шлём:
        // иначе оно приходит одновременно с «Виходьте».
        if trip.alertDate > now || trip.arrivalDate.timeIntervalSince(now) > 30 {
            requests.append(PlannedNotification(
                id: nextStopId,
                title: L10n.notifNextTitle(trip.destinationName),
                body: L10n.notifNextBody,
                date: trip.alertDate))
        }
        requests.append(PlannedNotification(
            id: arrivalId,
            title: trip.destinationName,
            body: L10n.notifArrivalBody,
            date: trip.arrivalDate))

        // Пересадка: предупреждаем на остановке перед станцией выхода.
        for (index, event) in trip.events.enumerated() where event.isTransfer && !event.isStop {
            // Пересадка уже позади: после «Поїзд рушив» или ±1 нельзя слать
            // «перейдіть на…» второй раз — система шлёт просроченное сразу же.
            guard event.arrival > now else { continue }
            let exitStation = trip.events[index - 1]
            // Нет предыдущей остановки — едем с самой пересадочной станции:
            // сказать об этом надо сразу, ждать нечего.
            let alertAt = trip.events[..<max(index - 1, 0)].last(where: \.isStop)?.arrival
                ?? now.addingTimeInterval(1)
            guard alertAt > now else { continue }
            requests.append(PlannedNotification(
                id: "trip.transfer.\(index)",
                title: L10n.notifNextTitle(exitStation.displayName),
                body: L10n.notifTransferBody(event.displayName),
                date: alertAt))
        }
        return requests
    }

    func schedule(for trip: ActiveTrip, now: Date = Date()) {
        cancelAll()
        let center = UNUserNotificationCenter.current()
        for planned in Self.plan(for: trip, now: now) {
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let interval = max(1, planned.date.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: planned.id, content: content,
                                             trigger: trigger))
        }
    }

    // Снимаем только уведомления поездки. removeAllPendingNotificationRequests()
    // сносил бы и «kyiv.airAlert» от AlertService: коррекция ±1 или GPS-снэп,
    // случившиеся в ту же секунду, что и начало тревоги, глушили бы её молча.
    // Список фиксированный и синхронный — асинхронная выборка pending успела бы
    // удалить уже перепланированные запросы, потому что префикс у них тот же.
    private static var tripIdentifiers: [String] {
        [nextStopId, arrivalId] + (0..<maxTransferSlots).map { "trip.transfer.\($0)" }
    }

    // С запасом: самая длинная линия Киева — 18 станций, маршрут с пересадкой короче.
    private static let maxTransferSlots = 64

    func cancelAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.tripIdentifiers)
    }
}
