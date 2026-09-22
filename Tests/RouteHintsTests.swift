import XCTest
@testable import MetroTimer

// Підказки до посадки (1.4): старі назви в пошуку, напрямок «як на табличці»
// і в який бік поїзда сідати. Помилка тут — поїзд не в той бік або вагон не
// в тому кінці, тож краще промовчати, ніж збрехати.
final class RouteHintsTests: XCTestCase {
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

    private func found(_ query: String) -> [String] {
        repo.stations(matching: query).map(\.station.id)
    }

    // Кияни досі кажуть «Петрівка» і «Льва Толстого».
    func testOldAndColloquialNamesFindStations() {
        XCTAssertEqual(found("Петрівка"), ["pochaina"])
        XCTAssertEqual(found("льва толстого"), ["ploshcha-ukrainskykh-heroiv"])
        XCTAssertEqual(found("Дружби народів"), ["zvirynetska"])
        XCTAssertEqual(found("Республіканський"), ["olimpiiska"])
        XCTAssertEqual(found("проспект перемоги"), ["beresteiska"])
        XCTAssertEqual(found("КПІ"), ["politekhnichnyi-instytut"])
        XCTAssertEqual(found("ВДНГ"), ["vystavkovyi-tsentr"])
        XCTAssertEqual(found("Tolstoho"), ["ploshcha-ukrainskykh-heroiv"])
        XCTAssertEqual(found("Golden Gate"), ["zoloti-vorota"])
        // Чинні назви працюють, як і раніше.
        XCTAssertEqual(found("Хрещ"), ["khreshchatyk"])
        XCTAssertTrue(found("zzzz").isEmpty)
    }

    // Кожен синонім веде на станцію, що існує, — опечатка в id мовчки
    // вимкнула б пошук за старою назвою.
    func testEveryAliasPointsToARealStation() {
        for id in MetroRepository.searchAliases.keys {
            XCTAssertNotNil(repo.station(id: id), id)
        }
    }

    // Напрямок — кінцева в бік руху, як на табличці над платформою.
    func testDirectionIsTheTerminus() {
        XCTAssertEqual(repo.terminus(boardingAt: "universytet", toward: "khreshchatyk")?.id, "lisova")
        XCTAssertEqual(repo.terminus(boardingAt: "universytet", toward: "vokzalna")?.id,
                       "akademmistechko")
        XCTAssertEqual(repo.terminus(boardingAt: "zoloti-vorota", toward: "lukianivska")?.id, "syrets")
        XCTAssertNil(repo.terminus(boardingAt: "universytet", toward: "universytet"))
    }

    func testTransferRowNamesDirection() {
        let row = L10n.transferRow("Золоті ворота", minutes: 3, toward: "Сирець")
        XCTAssertTrue(row.contains("напрямок «Сирець»"), row)
        XCTAssertEqual(L10n.transferRow("Золоті ворота", minutes: 3),
                       "Пересадка на «Золоті ворота» · ~3 хв")
    }

    // «Куди сідати»: лише неглибокі станції (де напрямкам можна вірити) і
    // кінці в бік руху саме цієї поїздки; на маршруті з пересадкою — мовчимо.
    func testBoardingSidesFollowTravelDirection() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        var checked = 0
        for line in repo.lines {
            for (i, to) in line.stationIds.enumerated() where i > 0 {
                let trip = try XCTUnwrap(TripPlanner.plan(fromId: line.stationIds[0], toId: to,
                                                          start: start, repo: repo))
                let forward = ExitStore.shared.boardingSides(for: to, travellingForward: true)
                let backward = ExitStore.shared.boardingSides(for: to, travellingForward: false)
                guard !forward.isEmpty else {
                    XCTAssertNil(SelectionView.boardingHint(for: trip, repo: repo), to)
                    continue
                }
                checked += 1
                XCTAssertTrue(ExitStore.shared.directionalHintsAllowed(for: to), to)
                XCTAssertEqual(SelectionView.boardingHint(for: trip, repo: repo),
                               L10n.boardingSides(forward), to)
                // Кожна підказка правдива: з цього кінця поїзда справді є вихід
                // до названого орієнтира — для обох напрямків руху.
                for (sides, isForward) in [(forward, true), (backward, false)] {
                    XCTAssertEqual(Set(sides.map(\.label)).count, sides.count, "\(to): повтор орієнтира")
                    for side in sides {
                        XCTAssertTrue(ExitStore.shared.exits(for: to).contains {
                            ($0.poi ?? $0.street) == side.label
                                && CarPosition(alongM: $0.alongM, travellingForward: isForward) == side.cars
                        }, "\(to): \(side.cars) \(side.label)")
                    }
                }
            }
        }
        // Хоч одна станція з підказкою в даних має бути — інакше функція
        // мовчки нічого не показує.
        XCTAssertGreaterThan(checked, 0)

        let withTransfer = try XCTUnwrap(TripPlanner.plan(fromId: "universytet", toId: "poshtova-ploshcha",
                                                          start: start, repo: repo))
        XCTAssertNil(SelectionView.boardingHint(for: withTransfer, repo: repo))
    }
}
