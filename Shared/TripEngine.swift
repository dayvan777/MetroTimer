import Foundation
import SwiftUI

// Единая точка управления поездкой. Живёт в процессе приложения;
// из виджета вызывается только через AdjustTripIntent (система поднимает процесс приложения).
@MainActor
final class TripEngine: ObservableObject {
    static let shared = TripEngine()

    @Published private(set) var trip: ActiveTrip?
    // Что показывают чипы под кнопкой: закреплённые и последние (без дублей).
    @Published private(set) var recents: [RecentTrip] = []
    @Published private(set) var favorites: [RecentTrip] = []
    // Маршрут, который просят подставить извне — диплинк или ярлык Siri.
    // Только подстановка: «Поїхали» человек жмёт сам в момент отправления.
    @Published var pendingPrefill: RecentTrip?
    @Published var notificationsDenied = false
    // «Живі активності» выключены в Параметрах или карточку не удалось создать:
    // отсчёта на экране блокировки не будет, и об этом надо сказать вслух.
    @Published private(set) var liveActivityUnavailable = false

    private var timer: Timer?
    // В start() есть await, поэтому одного `guard trip == nil` мало:
    // второй тап успевает пройти проверку, пока первый ждёт разрешений.
    private var isStarting = false
    private let defaults = UserDefaults.standard
    // Активная поездка остаётся в UserDefaults сознательно: её читает интент
    // с заблокированного экрана, а строгая защита файла в этот момент закрыта.
    private static let tripKey = "activeTrip"

    let repo = MetroRepository.shared

    private init() {
        restore()
    }

    // MARK: - Персистентность

    private func restore() {
        refreshRoutes()
        guard let data = defaults.data(forKey: Self.tripKey),
              let saved = try? JSONDecoder().decode(ActiveTrip.self, from: data) else { return }
        if saved.expiryDate < Date() {
            // Поездка истекла, пока приложение было убито: закрываем зависшую
            // Live Activity и записываем поездку в журнал как завершённую.
            defaults.removeObject(forKey: Self.tripKey)
            ActivityController.shared.endAllImmediately()
            TripLogStore.shared.append(trip: saved, outcome: .expired)
        } else {
            trip = saved
            ActivityController.shared.attachIfNeeded()
        }
    }

    private func persistTrip() {
        if let trip, let data = try? JSONEncoder().encode(trip) {
            defaults.set(data, forKey: Self.tripKey)
        } else {
            defaults.removeObject(forKey: Self.tripKey)
        }
    }

    private func rememberRecent(fromId: String, toId: String, lineId: String) {
        RouteStore.shared.rememberRecent(RecentTrip(lineId: lineId, fromId: fromId, toId: toId))
        refreshRoutes()
    }

    private func refreshRoutes() {
        favorites = RouteStore.shared.book.favorites
        recents = RouteStore.shared.book.displayedRecents
    }

    // MARK: - Закреплённые маршруты

    func toggleFavorite(fromId: String, toId: String) {
        guard let lineId = repo.line(ofStation: fromId)?.id else { return }
        RouteStore.shared.toggleFavorite(RecentTrip(lineId: lineId, fromId: fromId, toId: toId))
        refreshRoutes()
    }

    func isFavorite(fromId: String, toId: String) -> Bool {
        guard let lineId = repo.line(ofStation: fromId)?.id else { return false }
        return RouteStore.shared.book.isFavorite(
            RecentTrip(lineId: lineId, fromId: fromId, toId: toId))
    }

    // MARK: - Жизненный цикл поездки

    // Возвращает false, если пара станций невалидна (в т.ч. разные линии).
    // askForNotifications = false — пользователь осознанно едет без сповіщень:
    // системный промпт не показываем, поездка всё равно стартует.
    // boardedAt — момент нажатия «Поїхали», а НЕ момент, когда мы досюда дошли:
    // между ними лежит диалог разрешений, и привязка модели к нему сдвигала бы
    // весь отсчёт и оба уведомления на время, потраченное на промпты.
    @discardableResult
    func start(fromId: String, toId: String, askForNotifications: Bool = true,
               at boardedAt: Date = Date()) async -> Bool {
        // Двойной тап «Поїхали» / гонка с восстановлением: вторая поездка поверх живой невозможна.
        // isStarting держит окно от первой проверки до присвоения trip — внутри есть await.
        guard trip == nil, !isStarting else { return false }
        isStarting = true
        defer { isStarting = false }
        #if DEBUG
        let skipAuth = ProcessInfo.processInfo.environment["MT_SKIP_NOTIF_AUTH"] != nil
        #else
        let skipAuth = false
        #endif
        if !skipAuth {
            let status = await NotificationScheduler.shared.authorizationStatus()
            if status == .notDetermined {
                if askForNotifications {
                    let granted = await NotificationScheduler.shared.requestAuthorization()
                    notificationsDenied = !granted
                } else {
                    notificationsDenied = true
                }
            } else {
                notificationsDenied = status == .denied
            }
        }

        // Цвет Live Activity — линия станции выхода: она актуальна в момент,
        // когда пассажир смотрит на остров чаще всего.
        guard let planned = TripPlanner.plan(fromId: fromId, toId: toId, start: boardedAt, repo: repo),
              let line = repo.line(ofStation: planned.toId) else { return false }

        trip = planned
        persistTrip()
        rememberRecent(fromId: fromId, toId: toId, lineId: planned.lineId)
        NotificationScheduler.shared.schedule(for: planned)
        liveActivityUnavailable = !ActivityController.shared.start(trip: planned, line: line)
        startTicker()
        return true
    }

    // outcome решает, что попадёт в журнал. Разница не косметическая:
    // «Я на місці» — единственный момент, когда мы узнаём реальное время
    // прибытия и можем сравнить его с расчётом. «Зупинити» такого не даёт.
    func stopByUser(outcome: TripOutcome = .stopped) {
        guard let trip else { return }
        liveActivityUnavailable = false
        stopTicker()
        NotificationScheduler.shared.cancelAll()
        ActivityController.shared.endAllImmediately()
        TripLogStore.shared.append(trip: trip, outcome: outcome)
        self.trip = nil
        persistTrip()
    }

    // Ручная коррекция из приложения или из Live Activity (App Intent, iOS 17+).
    func adjust(by delta: Int) async {
        guard let current = trip,
              var replanned = TripPlanner.replan(trip: current, nextStopShift: delta,
                                                 now: Date(), repo: repo) else { return }
        replanned.manualCorrections += 1
        // Направление важнее количества: «+1» означает, что поезд отстаёт
        // от расчёта, «−1» — что опережает. Без этого журнал отвечал только
        // на «часто ли поправляли», а нужен ответ «в какую сторону мы врём».
        if delta > 0 { replanned.lateCorrections = (replanned.lateCorrections ?? 0) + 1 }
        await apply(replanned)
    }

    // «Поїзд рушив» после пересадки. Ожидание поезда на новой линии — самый
    // неопределённый кусок маршрута (модель знает только среднее по расписанию);
    // тап в момент отправления убирает эту неопределённость целиком.
    func boardedAfterTransfer() async {
        let now = Date()
        guard let current = trip, current.isChangingLines(at: now),
              let index = current.transferIndex,
              var replanned = TripPlanner.replan(trip: current, anchoredAt: index,
                                                 now: now, repo: repo) else { return }
        replanned.manualCorrections += 1
        await apply(replanned)
    }

    // GPS-коррекция: поезд подтверждённо у станции anchorIndex маршрута (см. GPS.md).
    func syncPosition(anchorIndex: Int) async {
        let now = Date()
        guard let current = trip else { return }
        guard anchorIndex != current.currentAnchorIndex(at: now),
              var replanned = TripPlanner.replan(trip: current, anchoredAt: anchorIndex,
                                                 now: now, repo: repo) else { return }
        replanned.gpsCorrections += 1
        await apply(replanned)
    }

    private func apply(_ replanned: ActiveTrip) async {
        trip = replanned
        persistTrip()
        NotificationScheduler.shared.schedule(for: replanned)
        await ActivityController.shared.update(trip: replanned)
    }

    // Вызывается при выходе в foreground.
    func refresh() {
        guard let trip else {
            // Без поездки не должно оставаться живых активностей (страховка).
            ActivityController.shared.endAllImmediately()
            return
        }
        if trip.expiryDate < Date() {
            finalizeArrivedTrip()
        } else {
            ActivityController.shared.attachIfNeeded()
            // Тумблер могли переключить, пока приложение было свёрнуто.
            if ActivityController.shared.areActivitiesEnabled { liveActivityUnavailable = false }
            startTicker()
        }
    }

    // Вызывается при уходе сцены из .active. Тикер обновляет только остров и
    // только пока жив процесс: за пределами foreground он впустую стучит раз
    // в секунду на .common runloop mode (шторка уведомлений, Пункт управления).
    func suspendTicker() {
        stopTicker()
    }

    private func finalizeArrivedTrip() {
        // Идемпотентность: финализируется только реально доехавшая поездка —
        // просроченный вызов при уже заменённом trip не должен её стирать.
        guard let trip, Date() >= trip.expiryDate else { return }
        stopTicker()
        Task { await ActivityController.shared.end(trip: trip) }
        TripLogStore.shared.append(trip: trip, outcome: .expired)
        self.trip = nil
        persistTrip()
    }

    // MARK: - Тикер (работает только пока жив процесс приложения)

    private func startTicker() {
        stopTicker()
        // Таймер живёт на главном ранлупе — мы уже на MainActor, Task не нужен.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicker() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let trip else { stopTicker(); return }
        let now = Date()
        // Модельное прибытие — не факт: до expiryDate поездка живёт,
        // юзер может добавить +1 (или GPS поправит). Финализация — только по грейсу.
        if now >= trip.expiryDate {
            finalizeArrivedTrip()
            return
        }
        ActivityController.shared.updateIfChanged(trip: trip, now: now)
    }
}
