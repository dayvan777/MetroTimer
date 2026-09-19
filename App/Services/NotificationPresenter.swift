import UserNotifications

// Без делегата iOS не показывает уведомления приложению на переднем плане —
// пассажир с открытым экраном поездки не получил бы «Наступна — ваша».
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        // Нагадування «на станції» показано — воно одноразове, дзвіночок гасне.
        if notification.request.identifier == BeaconScheduler.arrivalId {
            Task { @MainActor in BeaconScheduler.shared.noteArrivalFired() }
        }
        completionHandler([.banner, .sound, .list])
    }

    // Нагадування «Час у метро?»: кнопка «Поїхали» — явний людський тап,
    // тож вона стартує відлік (застосунок відкривається через .foreground).
    // Тап по тілу — лише підставляє станції, як ярлик Siri: контракт
    // «"Поїхали" людина тисне сама» лишається недоторканим.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if response.notification.request.identifier == BeaconScheduler.arrivalId {
            Task { @MainActor in BeaconScheduler.shared.noteArrivalFired() }
        }
        guard response.notification.request.content.categoryIdentifier == ReminderService.categoryId,
              let from = info["from"] as? String,
              let to = info["to"] as? String else {
            completionHandler()
            return
        }
        let action = response.actionIdentifier
        Task { @MainActor in
            let engine = TripEngine.shared
            if action == ReminderService.actionGoId {
                // Під час живої поїздки нічого не чіпаємо: екран зайнятий нею.
                if engine.trip == nil {
                    await engine.start(fromId: from, toId: to)
                }
            } else if action == UNNotificationDefaultActionIdentifier,
                      engine.trip == nil,
                      let lineId = MetroRepository.shared.line(ofStation: from)?.id {
                engine.pendingPrefill = RecentTrip(lineId: lineId, fromId: from, toId: to)
            }
            completionHandler()
        }
    }
}
