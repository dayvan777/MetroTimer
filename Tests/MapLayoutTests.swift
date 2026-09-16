import XCTest
@testable import MetroTimer

// Розкладка схеми — теж дані, і в неї ті самі вимоги, що й до графіка:
// повнота і несуперечність. Схема, де загубилася станція, гірша за її
// відсутність.
final class MapLayoutTests: XCTestCase {
    let repo = MetroRepository.shared

    // Щипок: точка холста під центром екрана не рухається, а послідовність
    // «кадр під час жесту → стан після» дає той самий зсув, що один крок.
    // Саме дві різні формули для цих двох моментів давали «стрибок» схеми.
    func testZoomKeepsCanvasPointUnderScreenCenter() {
        let view = CGSize(width: 430, height: 820)
        let center = CGPoint(x: 215, y: 410)
        for (scale, offset, factor) in [(0.35, CGSize(width: 12, height: 60), 2.1),
                                        (1.0, CGSize(width: -300, height: -420), 0.5),
                                        (2.4, CGSize(width: -900, height: -1500), 1.25)] as [(CGFloat, CGSize, CGFloat)] {
            // Яка точка холста зараз під центром екрана.
            let canvasBefore = CGPoint(x: (center.x - offset.width) / scale,
                                       y: (center.y - offset.height) / scale)
            let zoomed = MetroMapLayout.zoomedOffset(base: offset, factor: factor, viewSize: view)
            let newScale = scale * factor
            let canvasAfter = CGPoint(x: (center.x - zoomed.width) / newScale,
                                      y: (center.y - zoomed.height) / newScale)
            XCTAssertEqual(canvasBefore.x, canvasAfter.x, accuracy: 0.001)
            XCTAssertEqual(canvasBefore.y, canvasAfter.y, accuracy: 0.001)

            // Два кроки (1.5 і потім factor/1.5) = один крок factor: без стрибка між кадрами.
            let half = MetroMapLayout.zoomedOffset(base: offset, factor: 1.5, viewSize: view)
            let rest = MetroMapLayout.zoomedOffset(base: half, factor: factor / 1.5, viewSize: view)
            XCTAssertEqual(rest.width, zoomed.width, accuracy: 0.001)
            XCTAssertEqual(rest.height, zoomed.height, accuracy: 0.001)
        }
    }

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
