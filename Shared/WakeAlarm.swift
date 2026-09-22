import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

// Будильник за зупинку до виходу — для тих, хто в метро засинає.
//
// Звичайне сповіщення в беззвучному режимі лише раз вібрує, і людину, що
// задрімала з телефоном у кишені, воно не будить. Сайт колись обіцяв, що
// сповіщення «пробиває беззвучний режим», — неправда (ревю 22.09.2026).
// На iOS 26+ є AlarmKit: справжній будильник, який дзвонить крізь беззвучний
// режим і Фокус, доки його не вимкнуть. На старіших iOS або без дозволу —
// те саме сповіщення тричі поспіль (NotificationScheduler.plan, repeatNudges).
//
// Вмикає людина сама, перемикачем на екрані поїздки: гучний дзвінок у вагоні,
// якого не просили, гірший за тишу. Вибір запам'ятовується на наступні поїздки.
// Фонових режимів не треба: будильник, як і сповіщення, планується заздалегідь.
@MainActor
final class WakeAlarm: ObservableObject {
    static let shared = WakeAlarm()

    static let enabledKey = "wakeAlarmEnabled"
    // Ідентифікатор запланованого будильника: після перезапуску застосунку
    // його треба зняти, коли поїздка закінчиться або перерахується.
    private static let alarmIdKey = "wakeAlarmId"

    @Published private(set) var isEnabled: Bool
    // Людина відмовила будильникам у Параметрах: чесно кажемо, що буде натомість.
    @Published private(set) var isDenied = false

    private let defaults = UserDefaults.standard

    private init() {
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        refreshDenied()
    }

    // Справжній будильник існує на цій версії iOS.
    static var isAlarmKitAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    // Коли дзвонити — ActiveTrip.wakeDate: те саме правило, що й для повторів.
    nonisolated static func fireDate(for trip: ActiveTrip, now: Date) -> Date? {
        trip.wakeDate(now: now)
    }

    // Дзвонить саме AlarmKit (є і дозволено).
    var usesAlarmKit: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        #endif
        return false
    }

    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        #if canImport(AlarmKit)
        if enabled, #available(iOS 26.0, *),
           AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
        #endif
        refreshDenied()
    }

    private func refreshDenied() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            isDenied = AlarmManager.shared.authorizationState == .denied
            return
        }
        #endif
        isDenied = false
    }

    // Будильник завжди один: попередній знімаємо, новий ставимо за поточним
    // планом. Кличеться на старті і після кожної поправки (±1, тап по станції, GPS).
    // true — справжній будильник стоїть; false — ні (вимкнено, немає AlarmKit,
    // немає дозволу або система відмовила), і тоді будити мають повтори сповіщень.
    @discardableResult
    func schedule(for trip: ActiveTrip, now: Date = Date()) async -> Bool {
        cancel()
        guard isEnabled, let date = Self.fireDate(for: trip, now: now) else { return false }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
            let title = date == trip.alertDate
                ? L10n.wakeAlarmTitle(trip.destinationName)
                : L10n.notifArrivalTitle(trip.destinationName)
            let lineHex = MetroRepository.shared.line(id: trip.events.last?.lineId ?? trip.lineId)?.colorHex
            let tint = Color(hex: lineHex ?? "#FF9500")
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title))
            } else {
                alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: title),
                    stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: L10n.wakeStop),
                                            textColor: .white, systemImageName: "checkmark"))
            }
            let attributes = AlarmAttributes<WakeAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert), metadata: nil, tintColor: tint)
            let id = UUID()
            do {
                _ = try await AlarmManager.shared.schedule(
                    id: id,
                    configuration: AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
                        schedule: .fixed(date), attributes: attributes))
                defaults.set(id.uuidString, forKey: Self.alarmIdKey)
                return true
            } catch {
                return false
            }
        }
        #endif
        return false
    }

    func cancel() {
        guard let raw = defaults.string(forKey: Self.alarmIdKey) else { return }
        defaults.removeObject(forKey: Self.alarmIdKey)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let id = UUID(uuidString: raw) {
            // Уже дзвонить («Я вийшов» посеред дзвінка) — спершу зупинити, потім зняти.
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
        }
        #endif
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {}
#endif
