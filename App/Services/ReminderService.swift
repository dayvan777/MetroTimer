import Foundation
import UserNotifications

// Нагадування «час у метро»: щотижневі локальні сповіщення у вибрані дні.
// Жодного фону і жодної мережі — UNCalendarNotificationTrigger спрацьовує сам,
// а маршрут стартує лише людською рукою: кнопкою «Поїхали» у сповіщенні
// (застосунок відкриється і запустить відлік) або тапом по тілу — тоді
// станції просто підставляться, як від ярлика Siri.
@MainActor
final class ReminderService {
    static let shared = ReminderService()

    // Константи nonisolated: делегат сповіщень читає їх поза головним актором.
    nonisolated static let categoryId = "MT_REMINDER"
    nonisolated static let actionGoId = "MT_REMINDER_GO"
    private nonisolated static let idPrefix = "MT_REMINDER_"

    private init() {}

    // Категорію реєструємо до кінця запуску — інакше перша ж доставка
    // прийде без кнопки «Поїхали».
    static func registerCategory() {
        let go = UNNotificationAction(
            identifier: actionGoId, title: L10n.reminderGo,
            options: [.foreground])
        let category = UNNotificationCategory(
            identifier: categoryId, actions: [go], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // Єдина точка правди — RouteBook. Кожен виклик знімає всі наші запити
    // і ставить заново: ідемпотентно, тому можна смикати при кожній активації.
    func resync() {
        Task { @MainActor in
            let book = RouteStore.shared.book
            let center = UNUserNotificationCenter.current()
            // async-версія API замість колбека: без @Sendable-замикань і
            // без пересилання non-Sendable center між ізоляціями.
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for route in book.favorites {
                guard let reminder = book.reminder(for: route) else { continue }
                Self.schedule(reminder, for: route)
            }
        }
    }

    private static func schedule(_ reminder: RouteReminder, for route: RecentTrip) {
        let repo = MetroRepository.shared
        guard let from = repo.station(id: route.fromId)?.localizedName,
              let to = repo.station(id: route.toId)?.localizedName else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.reminderNotifTitle
        content.body = "\(from) → \(to)"
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["from": route.fromId, "to": route.toId]
        for weekday in reminder.weekdays.sorted() {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = reminder.hour
            components.minute = reminder.minute
            let request = UNNotificationRequest(
                identifier: "\(idPrefix)\(RouteBook.reminderKey(route))_\(weekday)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
            UNUserNotificationCenter.current().add(request)
        }
    }
}
