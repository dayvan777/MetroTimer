import CoreLocation
import UserNotifications

// «Нагадування на станції» — відповідь на питання konovalov.kirill «можна не
// робити початок поїздки?»: без відліку і без кнопки «Поїхали» iOS сама показує
// сповіщення, коли пасажир фізично опиняється біля станції виходу.
//
// Механіка — UNLocationNotificationTrigger: геозону стежить система, застосунок
// локацію не отримує взагалі (його може навіть не бути в пам'яті), тому фонові
// режими не потрібні і обіцянка «нічого не збираємо» лишається правдою.
// Потрібен лише дозвіл «під час використання».
//
// Під землею телефон визначає місце за стільниковою мережею: 4G покриває
// 45 із 46 станцій і тунелі між ними (спільний проєкт операторів, 2023).
// Точність і затримка спрацювання в тунелях не гарантовані — функція чесно
// назвається експериментальною, класичний відлік лишається головним шляхом.
@MainActor
final class BeaconScheduler: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = BeaconScheduler()

    static let nextId = "beacon.next"
    static let arrivalId = "beacon.arrival"

    struct RoutePair: Equatable {
        let fromId: String
        let toId: String
    }

    // Пара, на яку взведено нагадування; nil — не взведено. Після пострілу
    // «прибуття» система сама знімає запити, стан чистять willPresent
    // (передній план) і refresh() при поверненні в застосунок.
    @Published private(set) var armedPair: RoutePair?

    enum Tuning {
        // Радіус зони — станційний крок, як GPS-снэп (400 м): міжстанційні
        // відстані 1–2 км, зони сусідніх станцій не перетинаються, а вхід
        // у зону з тунелю дає сповіщенню фору перед відкриттям дверей.
        static let radiusMeters: CLLocationDistance = 400
    }

    struct PlannedBeacon: Equatable {
        let id: String
        let stationId: String
        let title: String
        let body: String
        let lat: Double
        let lon: Double
    }

    // Чиста частина — що саме взводиться: передостання зупинка маршруту
    // («наступна — ваша») і станція виходу («виходьте»). Тексти ті самі, що
    // у сповіщень відліку: для пасажира це одна й та сама подія.
    // nonisolated: чиста функція без стану — тести кличуть її без MainActor.
    nonisolated static func plan(fromId: String, toId: String, repo: MetroRepository,
                                 now: Date = Date()) -> [PlannedBeacon] {
        guard let trip = TripPlanner.plan(fromId: fromId, toId: toId, start: now, repo: repo),
              let destEvent = trip.events.last,
              let dest = repo.station(id: destEvent.stationId) else { return [] }
        var beacons = [PlannedBeacon(id: arrivalId, stationId: dest.id,
                                     title: destEvent.displayName,
                                     body: L10n.notifArrivalBody,
                                     lat: dest.lat, lon: dest.lon)]
        // Безпосередньо попередня подія маршруту. Закрита станція теж годиться:
        // поїзд її зону фізично проминає. Не годяться дві речі: пересадка
        // одразу перед виходом (пасажир іде вузлом пішки, «наступна — ваша»
        // ввело б в оману) і станція відправлення (пасажир уже в її зоні,
        // а тригер спрацьовує лише на перетині межі ззовні).
        if let prevEvent = trip.events.dropLast().last,
           !prevEvent.isTransfer, prevEvent.stationId != fromId,
           let prev = repo.station(id: prevEvent.stationId) {
            beacons.insert(PlannedBeacon(id: nextId, stationId: prev.id,
                                         title: L10n.notifNextTitle(destEvent.displayName),
                                         body: L10n.notifNextBody,
                                         lat: prev.lat, lon: prev.lon), at: 0)
        }
        return beacons
    }

    enum ArmResult: Equatable {
        case armed
        case locationDenied
        case noRoute
    }

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        Task { await restore() }
    }

    func arm(fromId: String, toId: String, repo: MetroRepository) async -> ArmResult {
        let beacons = Self.plan(fromId: fromId, toId: toId, repo: repo)
        guard !beacons.isEmpty else { return .noRoute }
        await NotificationScheduler.shared.requestAuthorization()
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestWhenInUse()
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return .locationDenied
        }
        disarm()
        let center = UNUserNotificationCenter.current()
        for beacon in beacons {
            let content = UNMutableNotificationContent()
            content.title = beacon.title
            content.body = beacon.body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["fromId": fromId, "toId": toId]
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: beacon.lat, longitude: beacon.lon),
                radius: Tuning.radiusMeters, identifier: beacon.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            try? await center.add(UNNotificationRequest(
                identifier: beacon.id, content: content,
                trigger: UNLocationNotificationTrigger(region: region, repeats: false)))
        }
        armedPair = RoutePair(fromId: fromId, toId: toId)
        return .armed
    }

    func disarm() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.nextId, Self.arrivalId])
        armedPair = nil
    }

    // Сповіщення прибуття вже показано — нагадування відпрацювало.
    func noteArrivalFired() {
        disarm()
    }

    // Звіряє стан із системою: після пострілу у фоні або перевстановлення
    // застосунку pending-запитів уже немає, дзвіночок не має брехати.
    func refresh() {
        Task { await restore() }
    }

    private func restore() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == Self.arrivalId }),
              let from = request.content.userInfo["fromId"] as? String,
              let to = request.content.userInfo["toId"] as? String else {
            armedPair = nil
            return
        }
        armedPair = RoutePair(fromId: from, toId: to)
    }

    private func requestWhenInUse() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // Виклик приходить і в момент призначення делегата зі статусом
        // notDetermined — це ще не відповідь людини, чекаємо визначеного.
        guard status != .notDetermined else { return }
        Task { @MainActor in
            authContinuation?.resume(returning: status)
            authContinuation = nil
        }
    }
}
