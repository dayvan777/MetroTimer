import XCTest
@testable import MetroTimer

// «Нагадування на станції»: що саме взводиться за геозоною. Головна небезпека —
// зона не на тій станції: сповіщення біля чужої платформи гірше за тишу.
final class BeaconTests: XCTestCase {

    private let repo = MetroRepository.shared

    // Маршрут у два перегони: попередження на передостанній зупинці
    // і прибуття на станції виходу, саме в цьому порядку.
    func testPlanHasPrevStopAndArrival() {
        let beacons = BeaconScheduler.plan(fromId: "universytet", toId: "khreshchatyk", repo: repo)
        XCTAssertEqual(beacons.map(\.id), [BeaconScheduler.nextId, BeaconScheduler.arrivalId])
        XCTAssertEqual(beacons.map(\.stationId), ["teatralna", "khreshchatyk"])
        // Координати — саме тих станцій, з сид-даних.
        let teatralna = repo.station(id: "teatralna")!
        XCTAssertEqual(beacons[0].lat, teatralna.lat)
        XCTAssertEqual(beacons[0].lon, teatralna.lon)
        XCTAssertFalse(beacons[0].title.isEmpty)
        XCTAssertFalse(beacons[1].title.isEmpty)
    }

    // Одна зупинка шляху: передостання станція — це станція посадки, пасажир
    // уже в її зоні, тригер на в'їзд не спрацює — взводиться лише прибуття.
    func testPlanOneStopSkipsBoardingStation() {
        let beacons = BeaconScheduler.plan(fromId: "universytet", toId: "teatralna", repo: repo)
        XCTAssertEqual(beacons.map(\.id), [BeaconScheduler.arrivalId])
        XCTAssertEqual(beacons[0].stationId, "teatralna")
    }

    // Пара одного пересадкового вузла: поїзда нема, планувальник повертає nil —
    // і нагадуванню нема чого взводити.
    func testPlanWalkOnlyPairIsEmpty() {
        let beacons = BeaconScheduler.plan(fromId: "teatralna", toId: "zoloti-vorota", repo: repo)
        XCTAssertTrue(beacons.isEmpty)
    }

    // Вихід одразу після пересадки: «наступна — ваша» на станції перед
    // вузлом збрехало б (попереду ще перехід пішки), а сам вузол пасажир
    // проходить ногами — взводиться лише прибуття.
    func testPlanTransferBeforeDestinationArmsOnlyArrival() {
        let beacons = BeaconScheduler.plan(fromId: "universytet", toId: "lukianivska", repo: repo)
        XCTAssertEqual(beacons.map(\.id), [BeaconScheduler.arrivalId])
        XCTAssertEqual(beacons[0].stationId, "lukianivska")
    }

    // Друга зупинка після пересадки: попередня станція — вже нова лінія,
    // поїзд її проминає — попередження законне.
    func testPlanAfterTransferPrevStopIsOnNewLine() {
        let beacons = BeaconScheduler.plan(fromId: "universytet", toId: "dorohozhychi", repo: repo)
        XCTAssertEqual(beacons.map(\.stationId), ["lukianivska", "dorohozhychi"])
    }
}
