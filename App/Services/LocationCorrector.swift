import Combine
import CoreLocation
import Foundation

// Foreground-only GPS-корректор: на наземных участках делает автоматически то,
// что кнопки ±1 делают вручную. Логика и границы применимости — в GPS.md.
// Фоновых режимов нет: в фоне iOS сам перестаёт выдавать локации.
@MainActor
final class LocationCorrector: NSObject, CLLocationManagerDelegate {
    static let shared = LocationCorrector()

    // Пороги задокументированы в GPS.md — менять синхронно.
    private enum Tuning {
        static let maxHorizontalAccuracy: CLLocationAccuracy = 100
        static let snapRadius: CLLocationDistance = 400
        static let minCorrectionInterval: TimeInterval = 30
        // Кэшированный фикс при старте менеджера может быть старым — снэп назад по маршруту.
        static let maxFixAge: TimeInterval = 10
    }

    private let manager = CLLocationManager()
    private let engine = TripEngine.shared
    private var subscription: AnyCancellable?
    private var isRunning = false
    private var lastCorrectionAt = Date.distantPast
    // Последний GPS-якорь текущей поездки: (индекс в маршруте, момент входа в радиус).
    private var lastLearnAnchor: (tripStart: Date, routeIndex: Int, at: Date)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 50
    }

    // GPS включается только на поездках с наземными (isSurface) станциями в маршруте
    // и выключается, как только такой поездки нет.
    func activate() {
        subscription = engine.$trip
            .map { trip in
                trip.map(Self.routeHasSurfaceStations) ?? false
            }
            .removeDuplicates()
            .sink { [weak self] shouldRun in
                shouldRun ? self?.startUpdates() : self?.stopUpdates()
            }
    }

    private static func routeHasSurfaceStations(_ trip: ActiveTrip) -> Bool {
        trip.events.contains { MetroRepository.shared.station(id: $0.stationId)?.isSurface == true }
    }

    private var surfaceTripActive: Bool {
        engine.trip.map(Self.routeHasSurfaceStations) ?? false
    }

    private func startUpdates() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard !isRunning else { return }
            isRunning = true
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    private func stopUpdates() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // Смена статуса (в т.ч. стартовый вызов) — запускаем только если
            // прямо сейчас идёт поездка с наземными станциями.
            if self.surfaceTripActive {
                self.startUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handle(location)
        }
    }

    // MARK: - Коррекция

    private func handle(_ location: CLLocation) {
        guard let trip = engine.trip,
              location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= Tuning.maxHorizontalAccuracy,
              Date().timeIntervalSince(location.timestamp) <= Tuning.maxFixAge
        else { return }

        // Ближайшая наземная станция маршрута; межстанционный шаг 1–2 км,
        // так что победитель в радиусе снэпа однозначен. Координаты подземных
        // станций в данных есть, но для снэпа не годятся: под землёй GPS нет.
        var best: (index: Int, distance: CLLocationDistance)?
        for (index, event) in trip.events.enumerated() {
            guard let station = engine.repo.station(id: event.stationId),
                  station.isSurface else { continue }
            let distance = location.distance(from: CLLocation(latitude: station.lat,
                                                              longitude: station.lon))
            if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (index, distance)
            }
        }
        guard let best, best.distance <= Tuning.snapRadius else { return }

        learn(anchorIndex: best.index, trip: trip)

        guard Date().timeIntervalSince(lastCorrectionAt) >= Tuning.minCorrectionInterval
        else { return }
        lastCorrectionAt = Date()
        Task { await engine.syncPosition(anchorIndex: best.index) }
    }

    // Пассивная автокалибровка: смена якоря на следующую по маршруту наземную
    // станцию = реальный замер перегона. Дельта минус стоянка → CalibrationStore,
    // тот же механизм усреднения, что и у ручной калибровки.
    private func learn(anchorIndex: Int, trip: ActiveTrip) {
        let now = Date()
        defer {
            if lastLearnAnchor?.routeIndex != anchorIndex || lastLearnAnchor?.tripStart != trip.startDate {
                lastLearnAnchor = (trip.startDate, anchorIndex, now)
            }
        }
        guard let last = lastLearnAnchor,
              last.tripStart == trip.startDate,
              // Якорь на станции отправления включает ожидание поезда на платформе —
              // это не замер хода: учим только начиная со второй станции маршрута.
              last.routeIndex >= 1,
              anchorIndex == last.routeIndex + 1 else { return }

        let from = trip.events[last.routeIndex]
        let to = trip.events[anchorIndex]
        guard !to.isTransfer, !from.isTransfer else { return }
        // Дельта «подъезд к prev → подъезд к next» = стоянка на prev + ход prev→next;
        // стоянка prev принадлежит сегменту, приходящему в prev.
        let prevOfFrom = trip.events[last.routeIndex - 1]
        let dwell = TimeInterval(engine.repo.timing(from: prevOfFrom.stationId,
                                                    to: from.stationId).dwell)
        let travel = now.timeIntervalSince(last.at) - dwell
        // Границы правдоподобия — общие с ручной калибровкой (CalibrationStore):
        // мусор одинаково опасен, откуда бы он ни пришёл, а хранилище отсеет
        // его само и скажет об этом.
        guard CalibrationStore.shared.recordTravel(from: from.stationId, to: to.stationId,
                                                   seconds: travel) else { return }
        CalibrationStore.shared.save()
    }
}
