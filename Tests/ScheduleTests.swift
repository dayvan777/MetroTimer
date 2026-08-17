import XCTest
@testable import MetroTimer

// Режим работы метро: интервалы движения (ожидание на пересадке) и
// перший/останній поїзд. Ошибка здесь тихо сдвигает весь расчёт на минуты.
final class ScheduleTests: XCTestCase {
    private let repo = MetroRepository.shared

    // Понедельник 17.08.2026 — рабочий день; воскресенье 16.08.2026 — выходной.
    private func kyiv(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        components.minute = minute
        return MetroRepository.kyivCalendar.date(from: components)!
    }

    // MARK: - Интервалы движения

    func testHeadwayTableCoversSchedule() throws {
        // 3 линии × 17 часов (06:00–22:00) × рабочий/выходной.
        XCTAssertEqual(repo.data.headways.count, 3 * 17 * 2)
        for line in repo.lines {
            for isHoliday in [false, true] {
                let hours = repo.data.headways
                    .filter { $0.lineId == line.id && $0.isHoliday == isHoliday }
                    .map(\.hour).sorted()
                XCTAssertEqual(hours, Array(6...22), "\(line.id) holiday=\(isHoliday)")
            }
        }
        // Правдоподобность: от 2:45 в час пик до 11 минут поздно вечером.
        for row in repo.data.headways {
            for value in [row.forwardStart, row.forwardEnd, row.backwardStart, row.backwardEnd] {
                XCTAssertTrue((150...700).contains(value), "\(row.lineId) \(row.hour): \(value)")
            }
        }
    }

    func testHeadwayInterpolatesInsideHour() throws {
        // M1, рабочий день, 08:00–09:00 прямий: 3:30 → 2:45 (210 → 165 сек).
        let start = try XCTUnwrap(repo.headwaySeconds(lineId: "m1", forward: true, at: kyiv(17, 8)))
        let middle = try XCTUnwrap(repo.headwaySeconds(lineId: "m1", forward: true, at: kyiv(17, 8, 30)))
        let end = try XCTUnwrap(repo.headwaySeconds(lineId: "m1", forward: true, at: kyiv(17, 9)))
        XCTAssertEqual(start, 210)
        XCTAssertEqual(middle, 188, "середина часа — середина между 210 и 165")
        XCTAssertEqual(end, 165, "09:00 — уже начало следующего часа")

        // Вне расписания берётся ближайший известный час, а не nil и не ноль.
        let night = try XCTUnwrap(repo.headwaySeconds(lineId: "m1", forward: true, at: kyiv(17, 3)))
        XCTAssertEqual(night, 540, "до открытия — интервал на 06:00")
        let late = try XCTUnwrap(repo.headwaySeconds(lineId: "m1", forward: true, at: kyiv(17, 23, 40)))
        XCTAssertEqual(late, 540, "после закрытия — интервал на конец 22-го часа")
    }

    func testHeadwayDependsOnDayType() throws {
        // Утро понедельника — час пик; утро воскресенья — обычный интервал.
        let weekday = try XCTUnwrap(repo.headwaySeconds(lineId: "m1", forward: true, at: kyiv(17, 8, 30)))
        let holiday = try XCTUnwrap(repo.headwaySeconds(lineId: "m1", forward: true, at: kyiv(16, 8, 30)))
        XCTAssertLessThan(weekday, holiday, "у вихідний поїзди ходять рідше")
    }

    // MARK: - Ожидание на пересадке

    func testTransferWaitFollowsTimeOfDay() throws {
        // Академмістечко (M1) → Позняки (M3), пересадка на Золоті ворота.
        let peak = try XCTUnwrap(TripPlanner.plan(fromId: "akademmistechko", toId: "pozniaky",
                                                  start: kyiv(17, 8), repo: repo))
        let evening = try XCTUnwrap(TripPlanner.plan(fromId: "akademmistechko", toId: "pozniaky",
                                                    start: kyiv(17, 22), repo: repo))
        let peakDuration = peak.arrivalDate.timeIntervalSince(peak.startDate)
        let eveningDuration = evening.arrivalDate.timeIntervalSince(evening.startDate)
        XCTAssertGreaterThan(eveningDuration, peakDuration + 60,
                             "вечером ожидание поезда на пересадке заметно больше")

        // Ход и стоянки одинаковы — разница только в ожидании на пересадке.
        let transferIndex = try XCTUnwrap(peak.transferIndex)
        let peakWalk = peak.events[transferIndex].arrival
            .timeIntervalSince(peak.events[transferIndex - 1].departure)
        let eveningWalk = evening.events[transferIndex].arrival
            .timeIntervalSince(evening.events[transferIndex - 1].departure)
        XCTAssertEqual(eveningDuration - peakDuration, eveningWalk - peakWalk, accuracy: 1)
        // Пеший переход Театральна→Золоті ворота = 150 с; остальное — ожидание.
        XCTAssertGreaterThan(peakWalk, 150)
    }

    func testTransferWithoutBoardingHasNoWait() throws {
        // Пересадочный узел и есть пункт назначения: садиться в поезд не нужно.
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: "akademmistechko", toId: "zoloti-vorota",
                                                  start: kyiv(17, 22), repo: repo))
        let index = try XCTUnwrap(trip.transferIndex)
        let walk = trip.events[index].arrival.timeIntervalSince(trip.events[index - 1].departure)
        XCTAssertEqual(walk, 150, accuracy: 1, "только пеший переход, без ожидания поезда")
    }

    // «Поїзд рушив» после пересадки: неопределённое ожидание заменяется фактом.
    func testBoardingAtTransferReanchors() throws {
        let start = kyiv(17, 22)
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: "akademmistechko", toId: "pozniaky",
                                                  start: start, repo: repo))
        let index = try XCTUnwrap(trip.transferIndex)

        // Пассажир на пересадке: подошёл к платформе, поезд ещё не тронулся.
        let atTransfer = trip.events[index - 1].arrival.addingTimeInterval(60)
        XCTAssertTrue(trip.isChangingLines(at: atTransfer))
        XCTAssertFalse(trip.isChangingLines(at: start), "на старте пересадка ещё далеко")
        XCTAssertFalse(trip.isChangingLines(at: trip.arrivalDate), "после прибытия — тоже нет")

        // Поезд рушив раньше среднего — вся оставшаяся часть маршрута сдвигается назад.
        let boarded = try XCTUnwrap(TripPlanner.replan(trip: trip, anchoredAt: index,
                                                       now: atTransfer, repo: repo))
        XCTAssertLessThan(boarded.arrivalDate, trip.arrivalDate)
        let firstLeg = repo.timing(from: boarded.events[index].stationId,
                                   to: boarded.events[index + 1].stationId).travel
        XCTAssertEqual(boarded.events[index + 1].arrival,
                       atTransfer.addingTimeInterval(TimeInterval(firstLeg)),
                       "следующая станция — ровно перегон от момента отправления")

        // Окно кнопки закрывается только на следующей станции: до тех пор
        // повторный тап остаётся законной поправкой (поезд стоял дольше).
        XCTAssertTrue(boarded.hasBoardedByModel(at: atTransfer), "подсказка меняется сразу")
        XCTAssertFalse(trip.hasBoardedByModel(at: atTransfer), "до тапа посадки ещё не было")
        XCTAssertTrue(boarded.isChangingLines(at: atTransfer.addingTimeInterval(30)))
        XCTAssertFalse(boarded.isChangingLines(at: boarded.events[index + 1].arrival))
    }

    // Live Activity повинна знати, що пасажир на пересадці: саме за цим прапорцем
    // на екрані блокування зʼявляється кнопка «Поїзд рушив».
    func testActivityStateFlagsTransfer() throws {
        let start = kyiv(17, 22)
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: "heroiv-dnipra", toId: "hidropark",
                                                  start: start, repo: repo))
        let index = try XCTUnwrap(trip.transferIndex)
        let atTransfer = trip.events[index - 1].arrival.addingTimeInterval(30)

        let onTheWay = MetroActivityAttributes.ContentState(trip: trip, now: start)
        XCTAssertEqual(onTheWay.isChangingLines, false)
        let changing = MetroActivityAttributes.ContentState(trip: trip, now: atTransfer)
        XCTAssertEqual(changing.isChangingLines, true)

        // Після підтвердження посадки кнопка більше не потрібна на наступній станції.
        let boarded = try XCTUnwrap(TripPlanner.replan(trip: trip, anchoredAt: index,
                                                       now: atTransfer, repo: repo))
        let after = MetroActivityAttributes.ContentState(
            trip: boarded, now: boarded.events[index + 1].arrival)
        XCTAssertEqual(after.isChangingLines, false)
    }

    // Полевая проверка 17.08.2026: модель давала 7 хв на пересадку Майдан→Хрещатик,
    // реальность — 2 (поезд стоял, пассажир забежал). Оценка обязана быть
    // смещена в раннюю сторону: лучше предупредить рано, чем после станции.
    func testTransferEstimateBiasedEarly() throws {
        for hour in [8, 12, 17, 20, 22] {
            let date = kyiv(17, hour)
            let headway = try XCTUnwrap(repo.headwaySeconds(lineId: "m1", forward: true, at: date))
            let planned = try XCTUnwrap(repo.expectedWaitSeconds(lineId: "m1", forward: true, at: date))
            let average = try XCTUnwrap(repo.averageWaitSeconds(lineId: "m1", forward: true, at: date))
            XCTAssertLessThan(planned, average, "о \(hour):00 відлік має йти попереду, а не всередині")
            XCTAssertEqual(planned, Int(Double(headway) * 0.25))
            XCTAssertEqual(average, headway / 2)
        }

        // Увесь перехід Майдан → Хрещатик має вкладатися в 4 хвилини навіть
        // ввечері, коли інтервал найбільший.
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: "heroiv-dnipra", toId: "hidropark",
                                                  start: kyiv(17, 22), repo: repo))
        let index = try XCTUnwrap(trip.transferIndex)
        let transfer = trip.events[index].arrival
            .timeIntervalSince(trip.events[index - 1].departure)
        XCTAssertLessThanOrEqual(transfer, 4 * 60)
        XCTAssertGreaterThanOrEqual(transfer, 2 * 60, "менше пішого переходу бути не може")
    }

    // MARK: - Перший/останній поїзд

    func testServiceHoursData() throws {
        XCTAssertEqual(repo.data.serviceHours.count, repo.data.stations.count)
        for hours in repo.data.serviceHours {
            XCTAssertNotNil(repo.station(id: hours.stationId), hours.stationId)
            let known = [hours.forwardFirst, hours.forwardLast,
                         hours.backwardFirst, hours.backwardLast].compactMap { $0 }
            XCTAssertFalse(known.isEmpty, "\(hours.stationId): нет ни одного направления")
            for seconds in known {
                XCTAssertTrue((5 * 3600...24 * 3600).contains(seconds), "\(hours.stationId): \(seconds)")
            }
            if let first = hours.forwardFirst, let last = hours.forwardLast {
                XCTAssertLessThan(first, last)
            }
        }
        // У конечных поезд отправляется только в одну сторону.
        let akadem = try XCTUnwrap(repo.data.serviceHours.first { $0.stationId == "akademmistechko" })
        XCTAssertNotNil(akadem.forwardFirst)
        XCTAssertNil(akadem.backwardFirst, "Академмістечко — конечная M1")
    }

    func testServiceWindowDirectionMatters() throws {
        // Из Академмістечка можно ехать только «вперёд» по линии.
        XCTAssertNotNil(repo.serviceWindow(fromId: "akademmistechko", towardId: "lisova",
                                           on: kyiv(17, 12)))
        XCTAssertNil(repo.serviceWindow(fromId: "akademmistechko", towardId: "akademmistechko",
                                        on: kyiv(17, 12)))
        let window = try XCTUnwrap(repo.serviceWindow(fromId: "akademmistechko", towardId: "lisova",
                                                      on: kyiv(17, 12)))
        XCTAssertEqual(window.first, kyiv(17, 5, 51), "перший поїзд о 05:51")
        XCTAssertEqual(window.last, kyiv(17, 22, 30), "останній — о 22:30")
    }

    func testServiceIssueDetectsClosedAndLastTrain() throws {
        func issue(at date: Date) -> ServiceIssue? {
            guard let trip = TripPlanner.plan(fromId: "akademmistechko", toId: "khreshchatyk",
                                              start: date, repo: repo) else { return nil }
            return TripPlanner.serviceIssue(for: trip, repo: repo)
        }

        XCTAssertNil(issue(at: kyiv(17, 12)), "среди дня предупреждать не о чем")

        guard case let .beforeFirst(_, time)? = issue(at: kyiv(17, 4)) else {
            return XCTFail("ночью метро закрыто")
        }
        XCTAssertEqual(time, kyiv(17, 5, 51))

        guard case let .afterLast(_, last)? = issue(at: kyiv(17, 23, 30)) else {
            return XCTFail("после последнего поезда — предупреждение")
        }
        XCTAssertEqual(last, kyiv(17, 22, 30))

        guard case .lastSoon? = issue(at: kyiv(17, 22, 10)) else {
            return XCTFail("за 20 минут до последнего поезда — мягкая подсказка")
        }
    }

    // Пересадка проверяется отдельно: на первый поезд успеть можно, на второй — нет.
    func testServiceIssueChecksTransferBoarding() throws {
        let trip = try XCTUnwrap(TripPlanner.plan(fromId: "akademmistechko", toId: "pozniaky",
                                                  start: kyiv(17, 22, 20), repo: repo))
        let index = try XCTUnwrap(trip.transferIndex)
        let boarding = trip.events[index].arrival
        let window = try XCTUnwrap(repo.serviceWindow(fromId: trip.events[index].stationId,
                                                      towardId: trip.events[index + 1].stationId,
                                                      on: boarding))
        XCTAssertGreaterThan(boarding, window.last, "к пересадке последний поезд уже уйдёт")
        guard case let .afterLast(station, _)? = TripPlanner.serviceIssue(for: trip, repo: repo) else {
            return XCTFail("предупреждение должно указывать на пересадку")
        }
        XCTAssertEqual(station, trip.events[index].nameUk)
    }
}
