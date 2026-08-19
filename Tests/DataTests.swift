import XCTest
@testable import MetroTimer

// Данные метро и локальные хранилища: ошибка здесь тихо портит все расчёты.
final class DataTests: XCTestCase {
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
            for (a, b) in zip(line.stationIds, line.stationIds.dropFirst()) {
                XCTAssertGreaterThan(repo.timing(from: a, to: b).travel, 0, "\(a)→\(b)")
                XCTAssertGreaterThan(repo.timing(from: b, to: a).travel, 0, "\(b)→\(a)")
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
