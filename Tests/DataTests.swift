import XCTest
@testable import MetroTimer

// Данные метро и локальные хранилища: ошибка здесь тихо портит все расчёты.
final class DataTests: XCTestCase {

    // ── Виходи (1.2) ──────────────────────────────────────────────────

    func testExitsCoverEveryStation() {
        let repo = MetroRepository.shared
        for line in repo.lines {
            for id in line.stationIds {
                XCTAssertFalse(ExitStore.shared.exits(for: id).isEmpty,
                               "станція без виходів у датасеті: \(id)")
            }
        }
    }

    func testExitsDataSane() {
        let repo = MetroRepository.shared
        var total = 0
        for line in repo.lines {
            for id in line.stationIds {
                for exit in ExitStore.shared.exits(for: id) {
                    total += 1
                    // 2 км уздовж осі — явно битий запис; найдовший реальний
                    // перехід («Хрещатик») лишається в межах.
                    XCTAssertLessThan(abs(exit.alongM), 2000, "\(id): alongM=\(exit.alongM)")
                    if let ref = exit.ref {
                        XCTAssertFalse(ref.isEmpty)
                    }
                }
            }
        }
        XCTAssertGreaterThan(total, 200, "датасет підозріло малий: \(total)")
    }

    func testCarPositionRespectsTravelDirection() {
        // Вихід у «голові» forward-осі: їдемо forward → перші вагони,
        // їдемо назад → останні. Далекий перехід — без порад.
        XCTAssertEqual(CarPosition(alongM: 40, travellingForward: true), .first)
        XCTAssertEqual(CarPosition(alongM: 40, travellingForward: false), .last)
        XCTAssertEqual(CarPosition(alongM: -40, travellingForward: true), .last)
        XCTAssertEqual(CarPosition(alongM: 10, travellingForward: true), .middle)
        XCTAssertNil(CarPosition(alongM: 435, travellingForward: true))
    }

    private let repo = MetroRepository.shared

    // stopsWord ветвится по глобальному appLanguage, который берётся из
    // preferredLocalizations хост-приложения. Без фиксации прогон на симуляторе
    // с английским языком валил бы проверки украинских склонений.
    private var savedLanguage: Language = .uk

    override func setUp() {
        super.setUp()
        savedLanguage = appLanguage
        appLanguage = .uk
    }

    override func tearDown() {
        appLanguage = savedLanguage
        super.tearDown()
    }

    // 9. Консистентность бандл-данных: то, на что молча полагается весь код.
    func testBundledMetroData() throws {
        XCTAssertEqual(repo.data.stations.count, 52)
        XCTAssertEqual(repo.lines.count, 3)

        let ids = repo.data.stations.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "дубликат id уронит построение словарей")

        for line in repo.lines {
            XCTAssertFalse(line.stationIds.isEmpty)
            for stationId in line.stationIds {
                XCTAssertNotNil(repo.station(id: stationId), "\(stationId) нет в станциях")
            }
            // У каждой соседней пары должен быть сегмент в обе стороны.
            // Именно seedTiming, а не timing: timing подмешивает калибровку
            // с этого устройства, и тест бандл-данных ловил бы чужие замеры.
            for (a, b) in zip(line.stationIds, line.stationIds.dropFirst()) {
                XCTAssertGreaterThan(repo.seedTiming(from: a, to: b).travel, 0, "\(a)→\(b)")
                XCTAssertGreaterThan(repo.seedTiming(from: b, to: a).travel, 0, "\(b)→\(a)")
            }
        }

        // Координаты — в границах Киева (грубый bbox защищает от опечаток).
        for station in repo.data.stations {
            XCTAssertTrue((50.2...50.6).contains(station.lat), "\(station.id) широта")
            XCTAssertTrue((30.2...30.8).contains(station.lon), "\(station.id) долгота")
        }

        // Каждая пара линий связана пересадкой, узлы — на разных линиях.
        for transfer in repo.data.transfers {
            let fromLine = repo.line(ofStation: transfer.fromId)?.id
            let toLine = repo.line(ofStation: transfer.toId)?.id
            XCTAssertNotNil(fromLine)
            XCTAssertNotNil(toLine)
            XCTAssertNotEqual(fromLine, toLine, "пересадка внутри одной линии бессмысленна")
            XCTAssertGreaterThan(transfer.walkSeconds, 0)
        }
        XCTAssertEqual(repo.data.transfers.count, 3)

        // Статус «рух припинено» есть у всех перегонов и сейчас нигде не взведён;
        // если участок закроют — маршрут через него не должен строиться.
        for segment in repo.data.segments {
            XCTAssertNotNil(segment.isSuspended, "\(segment.fromId)>\(segment.toId)")
        }
        let suspended = repo.data.segments.filter { $0.isSuspended == true }
        XCTAssertTrue(suspended.isEmpty, "на серпень 2026 рух відновлено скрізь")
        for segment in suspended {
            XCTAssertNil(TripPlanner.plan(fromId: segment.fromId, toId: segment.toId,
                                          start: Date(), repo: repo),
                         "маршрут через закриту ділянку будуватись не повинен")
        }

        // GPS-снэп ищет станцию в радиусе 400 м — наземные не должны «слипаться».
        let surface = repo.data.stations.filter(\.isSurface)
        XCTAssertFalse(surface.isEmpty)
        for line in repo.lines {
            let onLine = line.stationIds.compactMap { id in surface.first { $0.id == id } }
            for (a, b) in zip(onLine, onLine.dropFirst()) {
                XCTAssertGreaterThan(distance(a, b), 800, "\(a.id) и \(b.id) слишком близко")
            }
        }
    }

    // 10. Калибровка, тайминги и склонение зупинок.
    func testTimingAndPlurals() throws {
        // Незнакомая пара — безопасный дефолт, а не ноль и не крэш.
        let unknown = repo.timing(from: "lisova", to: "syrets")
        XCTAssertGreaterThan(unknown.travel, 0)
        XCTAssertGreaterThan(unknown.dwell, 0)

        // Замер калибровки усредняется и переопределяет сид. Пара синтетическая:
        // реальные перегоны могли быть откалиброваны на этом устройстве.
        let store = CalibrationStore.shared
        let (a, b) = ("test-seg-a", "test-seg-b")
        store.recordTravel(from: a, to: b, seconds: 100)
        let record = try XCTUnwrap(store.record(from: a, to: b))
        XCTAssertEqual(record.travelSamples, 1)
        XCTAssertEqual(try XCTUnwrap(record.travelSeconds), 100, accuracy: 0.001)
        store.recordTravel(from: a, to: b, seconds: 120)
        let averaged = try XCTUnwrap(store.record(from: a, to: b))
        XCTAssertEqual(averaged.travelSamples, 2)
        XCTAssertEqual(try XCTUnwrap(averaged.travelSeconds), 110, accuracy: 0.001)
        XCTAssertEqual(repo.timing(from: a, to: b).travel, 110, "калибровка перебивает сид")
        XCTAssertEqual(repo.timing(from: a, to: b).dwell, 25, "стоянка остаётся сидовой")

        // Неправдоподобный замер не должен попасть в базу ни при каких условиях:
        // перегон с ходом 0.2 с молча съедает станцию из отсчёта.
        let (c, d) = ("test-junk-a", "test-junk-b")
        XCTAssertFalse(store.recordTravel(from: c, to: d, seconds: 0.2), "0.2 с — не замер")
        XCTAssertFalse(store.recordTravel(from: c, to: d, seconds: 5000), "83 минуты — не замер")
        XCTAssertFalse(store.recordDwell(from: c, to: d, seconds: 0.16), "0.16 с — не стоянка")
        XCTAssertNil(store.record(from: c, to: d), "мусор не создаёт записи")
        XCTAssertEqual(repo.timing(from: c, to: d).travel, repo.seedTiming(from: c, to: d).travel,
                       "после отброшенного замера остаётся сид")

        // Файл, написанный прошлой версией без этих проверок, чинится при чтении.
        let dirty = CalibrationRecord(travelSeconds: 0.2, travelSamples: 1,
                                      dwellSeconds: 30, dwellSamples: 1)
        let cleaned = dirty.sanitized()
        XCTAssertNil(cleaned.travelSeconds, "битый ход выбрасывается")
        XCTAssertEqual(cleaned.travelSamples, 0, "вместе со счётчиком проб")
        XCTAssertEqual(try XCTUnwrap(cleaned.dwellSeconds), 30, accuracy: 0.001,
                       "правдоподобная стоянка остаётся")
        XCTAssertTrue(CalibrationRecord(travelSeconds: 0.2, travelSamples: 1,
                                        dwellSeconds: 0.1, dwellSamples: 1)
                        .sanitized().isEmpty, "запись без единого валидного поля — пустая")

        // Украинские формы: 1 зупинка, 2–4 зупинки, 5+ зупинок, 11–14 — зупинок.
        XCTAssertEqual(L10n.stopsWord(1), "зупинка")
        XCTAssertEqual(L10n.stopsWord(2), "зупинки")
        XCTAssertEqual(L10n.stopsWord(4), "зупинки")
        XCTAssertEqual(L10n.stopsWord(5), "зупинок")
        XCTAssertEqual(L10n.stopsWord(11), "зупинок")
        XCTAssertEqual(L10n.stopsWord(12), "зупинок")
        XCTAssertEqual(L10n.stopsWord(14), "зупинок")
        XCTAssertEqual(L10n.stopsWord(21), "зупинка")
        XCTAssertEqual(L10n.stopsWord(22), "зупинки")
        XCTAssertEqual(L10n.stopsWord(25), "зупинок")
        XCTAssertEqual(L10n.stopsWord(111), "зупинок")
    }

    // 11. Журнал: ради него и запускается бета, поэтому он обязан отличать
    // «пассажир подтвердил прибытие» от «бросил» и от «истекла по модели».
    func testTripLogOutcomes() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: "lisova", toId: "chernihivska",
                                                  start: start, repo: repo))
        let planned = Int(trip.arrivalDate.timeIntervalSince(start))

        // Подтверждённое прибытие на 40 секунд позже расчёта: модель спешила.
        let late = TripLogEntry(trip: trip, outcome: .arrived,
                                endedAt: trip.arrivalDate.addingTimeInterval(40))
        XCTAssertTrue(late.finished)
        XCTAssertEqual(late.confirmedSeconds, planned + 40)
        XCTAssertEqual(late.errorSeconds, 40, "плюс — доехал позже расчёта")

        // Вышел раньше расчёта — опасная сторона: предупреждение пришло бы
        // после нужной станции. Раньше такая поездка писалась как «зупинено».
        let early = TripLogEntry(trip: trip, outcome: .arrived,
                                 endedAt: trip.arrivalDate.addingTimeInterval(-25))
        XCTAssertEqual(early.errorSeconds, -25)
        XCTAssertTrue(early.finished)

        // Брошенная поездка не даёт знания о точности вообще.
        let stopped = TripLogEntry(trip: trip, outcome: .stopped, endedAt: start.addingTimeInterval(60))
        XCTAssertFalse(stopped.finished)
        XCTAssertNil(stopped.confirmedSeconds)
        XCTAssertNil(stopped.errorSeconds, "без подтверждения прибытия ошибка неизвестна")

        // Истёкшая по модели: доехал, но реального времени мы не знаем.
        let expired = TripLogEntry(trip: trip, outcome: .expired, endedAt: trip.expiryDate)
        XCTAssertTrue(expired.finished)
        XCTAssertNil(expired.errorSeconds)

        // Медиана считается только по подтверждённым.
        XCTAssertEqual(TripLogStore.medianError(of: [late, early, stopped, expired]), 40)
        XCTAssertNil(TripLogStore.medianError(of: [stopped, expired]))
        XCTAssertEqual(TripLogStore.medianError(of: [late]), 40)
    }

    // 12. Направление коррекции должно доживать до журнала: «часто поправляли»
    // и «в какую сторону мы врём» — разные вопросы.
    func testCorrectionDirectionReachesLog() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        var trip = try XCTUnwrap(TripPlanner.plan(fromId: "lisova", toId: "chernihivska",
                                                  start: start, repo: repo))
        trip.manualCorrections = 3
        trip.lateCorrections = 2
        let entry = TripLogEntry(trip: trip, outcome: .arrived, endedAt: trip.arrivalDate)
        XCTAssertEqual(entry.manualCorrections, 3)
        XCTAssertEqual(entry.lateCorrections, 2, "два «+1» — поезд отставал")
    }

    // 13. Оценку просим только там, где приложение себя оправдало: иначе
    // одна звезда от тех, у кого отсчёт разошёлся, прилетит первой.
    func testReviewPromptIsEarned() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: "lisova", toId: "chernihivska",
                                                  start: start, repo: repo))
        func entry(_ errorSeconds: Int) -> TripLogEntry {
            TripLogEntry(trip: trip, outcome: .arrived,
                         endedAt: trip.arrivalDate.addingTimeInterval(TimeInterval(errorSeconds)))
        }
        let accurate = [entry(10), entry(-5), entry(20)]
        XCTAssertEqual(TripLogStore.medianError(of: accurate), 10)

        // Одна-две удачные поездки — ещё не доказательство.
        XCTAssertTrue(TripLogStore.medianError(of: [entry(120), entry(150), entry(200)])
                        .map { abs($0) > 30 } ?? false, "промахи не проходят порог")

        // Брошенные поездки в счёт не идут.
        let stopped = TripLogEntry(trip: trip, outcome: .stopped, endedAt: start)
        XCTAssertNil(stopped.errorSeconds)
        XCTAssertNil(TripLogStore.medianError(of: [stopped, stopped]))
    }

    // 14. Журнал прошлой версии не знает про outcome — он должен читаться,
    // а не пропадать целиком вместе со всей историей пассажира.
    func testOldLogEntryStillDecodes() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","date":"2026-08-01T10:00:00Z","fromName":"Лісова",
          "toName":"Чернігівська","plannedSeconds":120,"finalSeconds":120,
          "manualCorrections":0,"gpsCorrections":0,"transfers":0,"finished":true}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([TripLogEntry].self, from: Data(legacy.utf8))
        let entry = try XCTUnwrap(entries.first)
        XCTAssertTrue(entry.finished)
        XCTAssertNil(entry.outcome, "старая запись не знает исхода — и это нормально")
        XCTAssertNil(entry.errorSeconds)
        XCTAssertNil(entry.lateCorrections)
    }

    private func distance(_ a: Station, _ b: Station) -> Double {
        let earth = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let lat1 = a.lat * .pi / 180
        let lat2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earth * 2 * asin(min(1, sqrt(h)))
    }
}
