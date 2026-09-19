import XCTest
@testable import MetroTimer

// Снап «ви біля станції»: неправильна підказка в центрі, де станції стоять
// за 300–700 м, гірша за відсутність підказки.
final class LocatorTests: XCTestCase {

    private let repo = MetroRepository.shared

    // Точка впритул до станції: снап знаходить саме її.
    func testSnapFindsStationNextToFix() {
        let station = repo.station(id: "universytet")!
        let found = StationLocator.snap(lat: station.lat + 0.0005, lon: station.lon, repo: repo)
        XCTAssertEqual(found?.id, "universytet")
    }

    // Далеко від метро (Виноградар): підказки немає.
    func testSnapReturnsNilFarFromMetro() {
        XCTAssertNil(StationLocator.snap(lat: 50.50, lon: 30.36, repo: repo))
    }

    // Точка між двома сусідніми станціями, зміщена до однієї: перемагає ближча.
    func testSnapPrefersClosestStation() {
        let teatralna = repo.station(id: "teatralna")!
        let zoloti = repo.station(id: "zoloti-vorota")!
        let lat = teatralna.lat * 0.8 + zoloti.lat * 0.2
        let lon = teatralna.lon * 0.8 + zoloti.lon * 0.2
        XCTAssertEqual(StationLocator.snap(lat: lat, lon: lon, repo: repo)?.id, "teatralna")
    }
}
