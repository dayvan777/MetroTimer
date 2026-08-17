import Foundation
import SwiftUI

// Единая точка управления поездкой. Живёт в процессе приложения;
// из виджета вызывается только через AdjustTripIntent (система поднимает процесс приложения).
@MainActor
final class TripEngine: ObservableObject {
    static let shared = TripEngine()

    @Published private(set) var trip: ActiveTrip?
    @Published private(set) var recents: [RecentTrip] = []
    @Published var notificationsDenied = false

    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private static let tripKey = "activeTrip"
    private static let recentsKey = "recentTrips"

    let repo = MetroRepository.shared

    private init() {
        restore()
    }

    // MARK: - Персистентность

    private func restore() {
        if let data = defaults.data(forKey: Self.recentsKey),
           let decoded = try? JSONDecoder().decode([RecentTrip].self, from: data) {
            recents = decoded
        }
        guard let data = defaults.data(forKey: Self.tripKey),
              let saved = try? JSONDecoder().decode(ActiveTrip.self, from: data) else { return }
        if saved.expiryDate < Date() {
            // Поездка истекла, пока приложение было убито: закрываем зависшую
            // Live Activity и записываем поездку в журнал как завершённую.
            defaults.removeObject(forKey: Self.tripKey)
            ActivityController.shared.endAllImmediately()
            TripLogStore.shared.append(trip: saved, finished: true)
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
        let entry = RecentTrip(lineId: lineId, fromId: fromId, toId: toId)
        var list = recents.filter { $0 != entry }
        list.insert(entry, at: 0)
        recents = Array(list.prefix(3))
        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: Self.recentsKey)
        }
    }

    // MARK: - Жизненный цикл поездки

    // Возвращает false, если пара станций невалидна (в т.ч. разные линии).
    // askForNotifications = false — пользователь осознанно едет без сповіщень:
    // системный промпт не показываем, поездка всё равно стартует.
    @discardableResult
    func start(fromId: String, toId: String, askForNotifications: Bool = true) async -> Bool {
        // Двойной тап «Поїхали» / гонка с восстановлением: вторая поездка поверх живой невозможна.
        guard trip == nil else { return false }
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
        guard let planned = TripPlanner.plan(fromId: fromId, toId: toId, start: Date(), repo: repo),
              let line = repo.line(ofStation: planned.toId) else { return false }

        trip = planned
        persistTrip()
        rememberRecent(fromId: fromId, toId: toId, lineId: planned.lineId)
        NotificationScheduler.shared.schedule(for: planned)
        ActivityController.shared.start(trip: planned, line: line)
        startTicker()
        return true
    }

    func stopByUser() {
        guard let trip else { return }
        stopTicker()
        NotificationScheduler.shared.cancelAll()
        ActivityController.shared.endAllImmediately()
        TripLogStore.shared.append(trip: trip, finished: false)
        self.trip = nil
        persistTrip()
    }

    // Ручная коррекция из приложения или из Live Activity (App Intent, iOS 17+).
    func adjust(by delta: Int) async {
        guard let current = trip,
              var replanned = TripPlanner.replan(trip: current, nextStopShift: delta,
                                                 now: Date(), repo: repo) else { return }
        replanned.manualCorrections += 1
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
            startTicker()
        }
    }

    private func finalizeArrivedTrip() {
        // Идемпотентность: финализируется только реально доехавшая поездка —
        // просроченный вызов при уже заменённом trip не должен её стирать.
        guard let trip, Date() >= trip.expiryDate else { return }
        stopTicker()
        Task { await ActivityController.shared.end(trip: trip) }
        TripLogStore.shared.append(trip: trip, finished: true)
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
