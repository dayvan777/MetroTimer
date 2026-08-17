import XCTest
@testable import MetroTimer

// Планировщик — ядро продукта: любая ошибка здесь = вибрация на чужой станции.
final class PlannerTests: XCTestCase {
    private let repo = MetroRepository.shared
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func plan(_ from: String, _ to: String) -> ActiveTrip? {
        TripPlanner.plan(fromId: from, toId: to, start: start, repo: repo)
    }

    // 1. Одна линия в обе стороны: состав, монотонность, стоянки, симметрия.
    func testPlanSameLineBothDirections() throws {
        let forward = try XCTUnwrap(plan("akademmistechko", "khreshchatyk"))
        XCTAssertEqual(forward.events.count, 11)                 // 10 перегонов
        XCTAssertEqual(forward.events.first?.arrival, start)
        XCTAssertEqual(forward.events.first?.stationId, "akademmistechko")
        XCTAssertEqual(forward.events.last?.stationId, "khreshchatyk")

        for (a, b) in zip(forward.events, forward.events.dropFirst()) {
            XCTAssertLessThan(a.arrival, b.arrival, "времена должны строго расти")
            XCTAssertLessThanOrEqual(a.arrival, a.departure)
        }
        // Стоянка только на промежуточных открытых станциях; на конечной — нет.
        for (index, event) in forward.events.enumerated() {
            let isIntermediate = index > 0 && index < forward.events.count - 1
            let dwell = event.departure.timeIntervalSince(event.arrival)
            if isIntermediate && event.isStop && !event.isTransfer {
                XCTAssertGreaterThan(dwell, 0, "\(event.stationId): нужна стоянка")
            } else {
                XCTAssertEqual(dwell, 0, accuracy: 0.001, "\(event.stationId): лишняя стоянка")
            }
        }

        let backward = try XCTUnwrap(plan("khreshchatyk", "akademmistechko"))
        XCTAssertEqual(backward.events.count, forward.events.count)
        XCTAssertEqual(backward.events.map(\.stationId), forward.events.map(\.stationId).reversed())
        // Времена перегонов направленные, но суммарно поездка сопоставима.
        let f = forward.arrivalDate.timeIntervalSince(start)
        let b = backward.arrivalDate.timeIntervalSince(start)
        XCTAssertEqual(f, b, accuracy: 180, "туда и обратно не должны отличаться на минуты")
    }

    // 2. Гварды: невалидные пары не должны давать поездку.
    func testPlanGuards() {
        XCTAssertNil(plan("lisova", "lisova"), "from == to")
        XCTAssertNil(plan("no-such-station", "lisova"))
        XCTAssertNil(plan("lisova", "no-such-station"))
        // Закрытых станций в текущих данных нет; если появятся — не пункт назначения.
        for station in repo.data.stations where station.isClosed {
            XCTAssertNil(plan("lisova", station.id), "\(station.id) закрыта")
        }
    }

    // 3. Пересадка: ровно один переход, время перехода, уникальность станций.
    func testPlanWithTransfer() throws {
        let trip = try XCTUnwrap(plan("universytet", "poshtova-ploshcha"))
        let transfers = trip.events.filter(\.isTransfer)
        XCTAssertEqual(transfers.count, 1)
        let transfer = try XCTUnwrap(transfers.first)
        XCTAssertEqual(transfer.lineId, "m2", "переход помечается линией, на которую садимся")

        let index = try XCTUnwrap(trip.events.firstIndex(where: \.isTransfer))
        let exitId = trip.events[index - 1].stationId
        let walk = transfer.arrival.timeIntervalSince(trip.events[index - 1].departure)
        let node = try XCTUnwrap(repo.data.transfers.first {
            ($0.fromId == exitId && $0.toId == transfer.stationId)
                || ($0.toId == exitId && $0.fromId == transfer.stationId)
        })
        // Пересадка = ходьба + среднее ожидание поезда по расписанию на момент
        // выхода на платформу (см. ScheduleTests: вечером оно втрое больше).
        let platform = trip.events[index - 1].departure
            .addingTimeInterval(TimeInterval(node.walkSeconds))
        let forward = try XCTUnwrap(repo.isForward(lineId: transfer.lineId,
                                                   from: transfer.stationId,
                                                   to: trip.events[index + 1].stationId))
        let wait = try XCTUnwrap(repo.expectedWaitSeconds(lineId: transfer.lineId,
                                                          forward: forward, at: platform))
        XCTAssertEqual(walk, TimeInterval(node.walkSeconds + wait), accuracy: 1)

        // ForEach в UI ключуется по stationId — дубликаты сломали бы список.
        XCTAssertEqual(Set(trip.events.map(\.stationId)).count, trip.events.count)

        // Пересадка как последний шаг: станция назначения = станция пересадки.
        let short = try XCTUnwrap(plan("teatralna", "zoloti-vorota"))
        XCTAssertEqual(short.events.count, 2)
        XCTAssertTrue(try XCTUnwrap(short.events.last).isStop, "конечная всегда остановка")
    }

    // 4. Ручная коррекция ±1, включая обе границы.
    func testReplanByStopShift() throws {
        let trip = try XCTUnwrap(plan("akademmistechko", "khreshchatyk"))
        let now = start.addingTimeInterval(300)                  // где-то в пути
        let before = trip.stopsRemaining(at: now)

        let plus = try XCTUnwrap(TripPlanner.replan(trip: trip, nextStopShift: 1,
                                                    now: now, repo: repo))
        XCTAssertEqual(plus.stopsRemaining(at: now), before + 1)
        let minus = try XCTUnwrap(TripPlanner.replan(trip: plus, nextStopShift: -1,
                                                     now: now, repo: repo))
        XCTAssertEqual(minus.stopsRemaining(at: now), before)

        // «+1» на станции отправления = «поїзд ще не рушив»: отсчёт начинается
        // заново от «зараз», поэтому прибытие уезжает ровно на время ожидания.
        let waited = start.addingTimeInterval(60)
        let atStart = try XCTUnwrap(TripPlanner.replan(trip: trip, nextStopShift: 1,
                                                       now: waited, repo: repo))
        XCTAssertEqual(atStart.stopsRemaining(at: waited), trip.stopsRemaining(at: start))
        XCTAssertEqual(atStart.arrivalDate.timeIntervalSince(trip.arrivalDate), 60, accuracy: 2)

        // «−1» у конечной уже некуда — модель не должна выдумывать станции.
        XCTAssertNil(TripPlanner.replan(trip: trip, nextStopShift: -1,
                                        now: trip.arrivalDate, repo: repo))
        // А «+1» после модельного прибытия обязан работать: поезд ещё едет.
        let overdue = try XCTUnwrap(TripPlanner.replan(trip: trip, nextStopShift: 1,
                                                       now: trip.arrivalDate, repo: repo))
        XCTAssertEqual(overdue.stopsRemaining(at: trip.arrivalDate), 1)
    }

    // 5. Якорная перепланировка (GPS): прошлое стамплено, будущее пересчитано.
    func testReplanAnchored() throws {
        let trip = try XCTUnwrap(plan("lisova", "khreshchatyk"))
        let now = start.addingTimeInterval(600)
        for anchor in trip.events.indices {
            let replanned = try XCTUnwrap(TripPlanner.replan(trip: trip, anchoredAt: anchor,
                                                             now: now, repo: repo))
            XCTAssertEqual(replanned.currentAnchorIndex(at: now), anchor)
            for index in 0...anchor {
                XCTAssertLessThanOrEqual(replanned.events[index].arrival, now)
            }
            for (a, b) in zip(replanned.events, replanned.events.dropFirst()) {
                XCTAssertLessThan(a.arrival, b.arrival)
            }
            XCTAssertEqual(replanned.startDate, trip.startDate, "старт поездки не переписываем")
            XCTAssertEqual(replanned.initialArrival, trip.initialArrival, "план для журнала — тоже")
        }
        XCTAssertNil(TripPlanner.replan(trip: trip, anchoredAt: -1, now: now, repo: repo))
        XCTAssertNil(TripPlanner.replan(trip: trip, anchoredAt: trip.events.count,
                                        now: now, repo: repo))
    }

    // 6. Производные состояния поездки, на которых держатся UI и остров.
    func testTripDerivedState() throws {
        let trip = try XCTUnwrap(plan("akademmistechko", "khreshchatyk"))
        XCTAssertEqual(trip.stopsRemaining(at: start), trip.events.filter(\.isStop).count - 1)
        XCTAssertEqual(trip.nextStop(at: start)?.stationId, trip.events[1].stationId)
        XCTAssertEqual(trip.expiryDate, trip.arrivalDate.addingTimeInterval(600))

        // После прибытия: следующей нет, якорь — на конечной, зупинок ноль.
        let after = trip.arrivalDate.addingTimeInterval(1)
        XCTAssertNil(trip.nextEventIndex(at: after))
        XCTAssertEqual(trip.currentAnchorIndex(at: after), trip.events.count - 1)
        XCTAssertEqual(trip.stopsRemaining(at: after), 0)
        XCTAssertNil(trip.nextStop(at: after))

        // «Наступна — ваша» = прибытие на предпоследнюю остановку.
        XCTAssertEqual(trip.alertDate, trip.events[trip.events.count - 2].arrival)

        // С пересадкой в конце alert берётся от перехода, а не от станции выхода.
        let transferTrip = try XCTUnwrap(plan("teatralna", "lukianivska"))
        let transferEvent = try XCTUnwrap(transferTrip.events.first(where: \.isTransfer))
        XCTAssertGreaterThanOrEqual(transferTrip.alertDate, transferEvent.arrival)
    }

    // 7. Что уходит в уведомления: состав, тексты, отсутствие мусора из прошлого.
    func testNotificationPlan() throws {
        let trip = try XCTUnwrap(plan("akademmistechko", "khreshchatyk"))
        let planned = NotificationScheduler.plan(for: trip, now: start)
        XCTAssertEqual(planned.map(\.id), ["trip.nextStop", "trip.arrival"])
        XCTAssertEqual(planned[0].date, trip.alertDate)
        XCTAssertEqual(planned[1].date, trip.arrivalDate)
        XCTAssertTrue(planned[0].title.contains(trip.destinationName))

        // Пересадка добавляет своё предупреждение — до момента выхода.
        let withTransfer = try XCTUnwrap(plan("universytet", "poshtova-ploshcha"))
        let transferPlan = NotificationScheduler.plan(for: withTransfer, now: start)
        let transferNotes = transferPlan.filter { $0.id.hasPrefix("trip.transfer.") }
        XCTAssertEqual(transferNotes.count, 1)
        let exitIndex = try XCTUnwrap(withTransfer.events.firstIndex(where: \.isTransfer)) - 1
        XCTAssertLessThanOrEqual(try XCTUnwrap(transferNotes.first).date,
                                 withTransfer.events[exitIndex].arrival)

        // Пересадка позади: «перейдіть на…» повторять нельзя — просроченное
        // уведомление система выдаёт немедленно, уже после самой пересадки.
        let transferIndex = exitIndex + 1
        let boarded = try XCTUnwrap(
            TripPlanner.replan(trip: withTransfer, anchoredAt: transferIndex,
                               now: withTransfer.events[exitIndex].arrival, repo: repo))
        let afterBoarding = NotificationScheduler.plan(
            for: boarded, now: withTransfer.events[exitIndex].arrival)
        XCTAssertTrue(afterBoarding.allSatisfy { !$0.id.hasPrefix("trip.transfer.") })

        // Едем с самой пересадочной станции: сказать надо сразу, но ровно один раз.
        let fromNode = try XCTUnwrap(plan("khreshchatyk", "poshtova-ploshcha"))
        let atStart = NotificationScheduler.plan(for: fromNode, now: start)
        XCTAssertEqual(atStart.filter { $0.id.hasPrefix("trip.transfer.") }.count, 1)
        let index = try XCTUnwrap(fromNode.transferIndex)
        let afterWalk = NotificationScheduler.plan(for: fromNode,
                                                   now: fromNode.events[index].arrival)
        XCTAssertTrue(afterWalk.allSatisfy { !$0.id.hasPrefix("trip.transfer.") })

        // После прибытия «наступна — ваша» уже не нужна: остаётся только «Виходьте».
        let late = NotificationScheduler.plan(for: trip, now: trip.arrivalDate)
        XCTAssertEqual(late.map(\.id), ["trip.arrival"])
        XCTAssertLessThanOrEqual(planned.count, 64, "лимит iOS на pending-уведомления")
    }

    // 8. Состояние Live Activity: не дёргается внутри перегона, меняется на остановке.
    func testActivityContentState() throws {
        let trip = try XCTUnwrap(plan("akademmistechko", "khreshchatyk"))
        let firstLeg = trip.events[1].arrival.addingTimeInterval(-5)
        XCTAssertEqual(MetroActivityAttributes.ContentState(trip: trip, now: start),
                       MetroActivityAttributes.ContentState(trip: trip, now: firstLeg),
                       "внутри перегона состояние обязано совпадать — иначе лишние пуши")
        XCTAssertNotEqual(MetroActivityAttributes.ContentState(trip: trip, now: firstLeg),
                          MetroActivityAttributes.ContentState(trip: trip,
                                                               now: trip.events[1].arrival))

        let state = MetroActivityAttributes.ContentState(trip: trip, now: start)
        XCTAssertEqual(state.lineColorHex, repo.line(id: "m1")?.colorHex)
        let encoded = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(MetroActivityAttributes.ContentState.self,
                                                from: encoded), state)

        // После прибытия остров показывает конечную, а не пустую строку.
        let arrived = MetroActivityAttributes.ContentState(trip: trip, now: trip.expiryDate)
        XCTAssertEqual(arrived.stopsRemaining, 0)
        XCTAssertEqual(arrived.nextStationName, trip.destinationName)
    }
}
