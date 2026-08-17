import XCTest
@testable import MetroTimer

// Две языковые версии живут парами в Strings.swift; здесь проверяется, что
// переключение действительно меняет весь текст и ничего не осталось зашитым.
final class LocalizationTests: XCTestCase {
    private let repo = MetroRepository.shared
    private var saved: Language = .uk

    override func setUp() {
        super.setUp()
        saved = appLanguage
    }

    override func tearDown() {
        appLanguage = saved
        super.tearDown()
    }

    private func inLanguage<T>(_ language: Language, _ body: () -> T) -> T {
        appLanguage = language
        return body()
    }

    func testBundleDeclaresBothLanguages() throws {
        // По этому списку App Store показывает локализации, а iOS выбирает язык.
        let declared = Set(Bundle.main.localizations)
        XCTAssertTrue(declared.contains("uk"), "оголошені: \(declared)")
        XCTAssertTrue(declared.contains("en"), "оголошені: \(declared)")
    }

    func testEveryStringSwitchesLanguage() throws {
        // Выборка по всем экранам: если строку забыли обернуть в tr(), она
        // останется украинской и тест это поймает.
        let samples: [(String, () -> String)] = [
            ("go", { L10n.go }),
            ("startHint", { L10n.startHint }),
            ("pickOrigin", { L10n.pickOrigin }),
            ("stopTrip", { L10n.stopTrip }),
            ("arrived", { L10n.arrived }),
            ("lastStopAhead", { L10n.lastStopAhead }),
            ("correctionTitle", { L10n.correctionTitle }),
            ("transferBoarded", { L10n.transferBoarded }),
            ("transferWaitHint", { L10n.transferWaitHint }),
            ("alertsToggle", { L10n.alertsToggle }),
            ("onboardingStep2", { L10n.onboardingStep2 }),
            ("aboutDisclaimer", { L10n.aboutDisclaimer }),
            ("aboutHowBody", { L10n.aboutHowBody }),
            ("aboutDataBody", { L10n.aboutDataBody }),
            ("journalEmpty", { L10n.journalEmpty }),
            ("calibHint", { L10n.calibHint }),
            ("notifExplainBody", { L10n.notifExplainBody }),
            ("notifArrivalBody", { L10n.notifArrivalBody }),
            ("routeError", { L10n.routeError }),
            ("a11yOrigin", { L10n.a11yOrigin }),
        ]
        for (name, value) in samples {
            let uk = inLanguage(.uk, value)
            let en = inLanguage(.en, value)
            XCTAssertFalse(uk.isEmpty, name)
            XCTAssertFalse(en.isEmpty, name)
            XCTAssertNotEqual(uk, en, "\(name): текст не змінюється з мовою")
            XCTAssertFalse(en.contains(where: { "їієґ".contains($0) }),
                           "\(name): в англійському тексті залишилась кирилиця — \(en)")
        }
    }

    func testFunctionsWithArgumentsSwitchToo() throws {
        let uk = inLanguage(.uk) { L10n.notifNextTitle("Хрещатик") }
        let en = inLanguage(.en) { L10n.notifNextTitle("Khreshchatyk") }
        XCTAssertTrue(uk.contains("Хрещатик"))
        XCTAssertTrue(en.contains("Khreshchatyk"))
        XCTAssertNotEqual(uk, en)

        XCTAssertNotEqual(inLanguage(.uk) { L10n.routeMinutes(12) },
                          inLanguage(.en) { L10n.routeMinutes(12) })
        XCTAssertNotEqual(inLanguage(.uk) { L10n.serviceLastSoon("X", time: "22:30") },
                          inLanguage(.en) { L10n.serviceLastSoon("X", time: "22:30") })
    }

    func testPluralsInBothLanguages() throws {
        inLanguage(.uk) {
            XCTAssertEqual(L10n.stopsWord(1), "зупинка")
            XCTAssertEqual(L10n.stopsWord(3), "зупинки")
            XCTAssertEqual(L10n.stopsWord(12), "зупинок")
        }
        inLanguage(.en) {
            XCTAssertEqual(L10n.stopsWord(1), "stop")
            XCTAssertEqual(L10n.stopsWord(3), "stops")
            XCTAssertEqual(L10n.stopsWord(12), "stops")
            XCTAssertEqual(L10n.stopsRemaining(1), "1 stop to go")
        }
    }

    func testStationNamesFollowLanguage() throws {
        let station = try XCTUnwrap(repo.station(id: "khreshchatyk"))
        XCTAssertEqual(inLanguage(.uk) { station.localizedName }, "Хрещатик")
        XCTAssertEqual(inLanguage(.en) { station.localizedName }, "Khreshchatyk")

        // Английские имена есть у всех станций и не совпадают с украинскими.
        for station in repo.data.stations {
            XCTAssertFalse(station.nameEn.isEmpty, station.id)
            XCTAssertNotEqual(station.nameEn, station.nameUk, station.id)
            XCTAssertFalse(station.nameEn.contains(where: { "їієґ".contains($0) }), station.id)
        }
    }

    func testTripEventsCarryBothNames() throws {
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: "universytet", toId: "poshtova-ploshcha",
                                                  start: Date(), repo: repo))
        for event in trip.events {
            XCTAssertNotNil(event.nameEn, event.stationId)
            XCTAssertEqual(inLanguage(.uk) { event.displayName }, event.nameUk)
            XCTAssertEqual(inLanguage(.en) { event.displayName }, event.nameEn)
        }
        // Заголовок экрана поездки, острова и уведомлений — одно и то же поле.
        XCTAssertEqual(inLanguage(.uk) { trip.destinationName }, "Поштова площа")
        XCTAssertEqual(inLanguage(.en) { trip.destinationName }, "Poshtova Ploshcha")

        // Поездка, сохранённая прошлой версией: nameEn нет — показываем украинское,
        // а не пустоту (декодирование не должно падать).
        let legacy = """
        {"stationId":"khreshchatyk","nameUk":"Хрещатик","lineId":"m1",
         "arrival":0,"departure":0,"isStop":true,"isTransfer":false}
        """
        let decoded = try JSONDecoder().decode(StopEvent.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.nameEn)
        XCTAssertEqual(inLanguage(.en) { decoded.displayName }, "Хрещатик")
    }
}
