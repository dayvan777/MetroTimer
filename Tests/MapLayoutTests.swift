import XCTest
@testable import MetroTimer

// Розкладка схеми — теж дані, і в неї ті самі вимоги, що й до графіка:
// повнота і несуперечність. Схема, де загубилася станція, гірша за її
// відсутність.
final class MapLayoutTests: XCTestCase {
    let repo = MetroRepository.shared

    func testEveryStationHasASpot() {
        for line in repo.lines {
            for id in line.stationIds {
                XCTAssertNotNil(MetroMapLayout.point(id), "нема координати: \(id)")
            }
        }
    }

    func testNoOrphanSpots() {
        let known = Set(repo.lines.flatMap(\.stationIds))
        for id in MetroMapLayout.spots.keys {
            XCTAssertTrue(known.contains(id), "координата без станції: \(id)")
        }
    }

    func testSpotsInsideCanvas() {
        for (id, spot) in MetroMapLayout.spots {
            XCTAssertTrue((0...MetroMapLayout.canvasSize.width).contains(spot.x), id)
            XCTAssertTrue((0...MetroMapLayout.canvasSize.height).contains(spot.y), id)
        }
    }

    // Станції не злипаються: мінімальна дистанція тримає і точки, і тапи.
    func testMinimumSpacing() {
        let all = MetroMapLayout.spots.map { ($0.key, $0.value) }
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                let dx = all[i].1.x - all[j].1.x, dy = all[i].1.y - all[j].1.y
                let distance = (dx * dx + dy * dy).squareRoot()
                XCTAssertGreaterThanOrEqual(distance, 28,
                    "занадто близько: \(all[i].0) і \(all[j].0) (\(Int(distance))pt)")
            }
        }
    }

    // Сегменти канону Бека: кожен перегін — горизонталь, вертикаль або 45°.
    func testBeckAngles() {
        for line in repo.lines {
            for (a, b) in zip(line.stationIds, line.stationIds.dropFirst()) {
                guard let pa = MetroMapLayout.point(a), let pb = MetroMapLayout.point(b) else {
                    continue
                }
                let dx = abs(pa.x - pb.x), dy = abs(pa.y - pb.y)
                let isCanon = dx < 0.5 || dy < 0.5 || abs(dx - dy) < 0.5
                XCTAssertTrue(isCanon, "перегін не 45/90: \(a) → \(b) (dx \(dx), dy \(dy))")
            }
        }
    }

    // Пересадкові пари стоять поруч — інакше «місток» перетне півсхеми.
    func testTransferPairsAreClose() {
        for transfer in repo.transfers {
            guard let pa = MetroMapLayout.point(transfer.fromId),
                  let pb = MetroMapLayout.point(transfer.toId) else {
                XCTFail("нема координат пересадки"); continue
            }
            let dx = pa.x - pb.x, dy = pa.y - pb.y
            XCTAssertLessThanOrEqual((dx * dx + dy * dy).squareRoot(), 120,
                                     "\(transfer.fromId) ↔ \(transfer.toId)")
        }
    }
}
