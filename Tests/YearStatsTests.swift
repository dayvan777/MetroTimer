import XCTest
@testable import MetroTimer

// «Мій рік у метро»: підсумок із журналу. Цифри мають бути чесними — картку
// відправляють друзям, і «214 поїздок» не може рахувати кинуті поїздки чи
// минулий рік.
final class YearStatsTests: XCTestCase {
    private let repo = MetroRepository.shared
    private var saved: Language = .uk

    override func setUp() {
        super.setUp()
        saved = appLanguage
        appLanguage = .uk
    }

    override func tearDown() {
        appLanguage = saved
        super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        MetroRepository.kyivCalendar.date(from: DateComponents(year: year, month: month, day: day,
                                                               hour: 8))!
    }

    private func entry(_ from: String, _ to: String, on day: Date,
                       outcome: TripOutcome = .expired) throws -> TripLogEntry {
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: from, toId: to, start: day, repo: repo))
        return TripLogEntry(trip: trip, outcome: outcome, endedAt: trip.arrivalDate)
    }

    func testYearSummary() throws {
        let entries = [
            try entry("lisova", "khreshchatyk", on: date(2026, 9, 1)),
            try entry("lisova", "khreshchatyk", on: date(2026, 9, 2)),
            try entry("khreshchatyk", "lisova", on: date(2026, 9, 2), outcome: .arrived),
            try entry("teremky", "heroiv-dnipra", on: date(2026, 9, 3)),
            // Кинута поїздка і минулий рік у підсумок не йдуть.
            try entry("lisova", "arsenalna", on: date(2026, 9, 4), outcome: .stopped),
            try entry("lisova", "khreshchatyk", on: date(2025, 12, 30)),
        ]
        let stats = YearStats.compute(entries: entries, year: 2026, repo: repo)
        XCTAssertEqual(stats.trips, 4)
        XCTAssertTrue(stats.isEnough)
        XCTAssertEqual(stats.favoriteStationId, "khreshchatyk")
        XCTAssertEqual(stats.longest?.fromId, "teremky", "синя лінія з кінця в кінець — найдовша")
        // Станції за вікном: 7 + 7 + 7 + 17 (Теремки → Героїв Дніпра).
        XCTAssertEqual(stats.stationsPassed, 7 + 7 + 7 + 17)
        XCTAssertEqual(stats.lineShares.values.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(stats.lineShares["m1"] ?? 0, 21.0 / 38.0, accuracy: 0.0001)
        XCTAssertEqual(stats.firstTrip, date(2026, 9, 1))
        let planned = entries.prefix(4).map(\.finalSeconds).reduce(0, +)
        XCTAssertEqual(stats.minutes, Int((Double(planned) / 60).rounded()), accuracy: 1)
    }

    // Записи до 1.4 знають лише назви — їх знаходимо за назвою будь-якою мовою.
    func testLegacyEntriesMatchByName() throws {
        let legacy = """
        [{"id":"5C2B0D52-3F0C-4C66-9D4B-3A7B2C1D0E9F","date":"2026-09-01T08:00:00Z",
          "fromName":"Lisova","toName":"Хрещатик","plannedSeconds":1200,"finalSeconds":1200,
          "manualCorrections":0,"gpsCorrections":0,"transfers":0,"finished":true,"outcome":"expired"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([TripLogEntry].self, from: Data(legacy.utf8))
        let stats = YearStats.compute(entries: entries, year: 2026, repo: repo)
        XCTAssertEqual(stats.trips, 1)
        XCTAssertEqual(stats.favoriteStationId, "khreshchatyk")
        XCTAssertEqual(stats.stationsPassed, 7)
        XCTAssertFalse(stats.isEnough, "з однієї поїздки картки не робимо")
    }

    func testEmptyJournal() {
        let stats = YearStats.compute(entries: [], year: 2026, repo: repo)
        XCTAssertEqual(stats.trips, 0)
        XCTAssertNil(stats.favoriteStationId)
        XCTAssertNil(stats.longest)
        XCTAssertTrue(stats.lineShares.isEmpty)
    }

    func testTripsWordPlurals() {
        XCTAssertEqual(L10n.yearTrips(1), "поїздка")
        XCTAssertEqual(L10n.yearTrips(3), "поїздки")
        XCTAssertEqual(L10n.yearTrips(11), "поїздок")
        XCTAssertEqual(L10n.yearTrips(214), "поїздок")
        XCTAssertEqual(L10n.yearTrips(21), "поїздка")
    }
}
