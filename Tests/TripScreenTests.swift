import XCTest
@testable import MetroTimer

// Версія 1.4: те, що змінилося на шляху від «Поїхали» до «Я вийшов».
// Головне питання до кожного тесту — чи не зсуває зміна попередження в
// небезпечний бік (пізніше за станцію або на поїзд, якого немає).
final class TripScreenTests: XCTestCase {
    private let repo = MetroRepository.shared
    private let start = Date(timeIntervalSince1970: 1_760_000_000)
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

    private func plan(_ from: String, _ to: String) throws -> ActiveTrip {
        try XCTUnwrap(TripPlanner.plan(fromId: from, toId: to, start: start, repo: repo))
    }

    // «Ми тут» на станції попереду моделі: людина пізно натиснула «Поїхали»,
    // поїзд далі, ніж думає розрахунок. Відлік має зсунутися раніше.
    func testTapStationAheadMovesCountdownEarlier() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        let now = trip.events[2].arrival.addingTimeInterval(5)      // модель: біля [2]
        XCTAssertEqual(trip.currentAnchorIndex(at: now), 2)
        let fixed = try XCTUnwrap(TripEngine.positionCorrection(of: trip, at: 4, now: now, repo: repo))
        XCTAssertLessThan(fixed.arrivalDate, trip.arrivalDate)
        XCTAssertLessThan(fixed.alertDate, trip.alertDate)
        XCTAssertEqual(fixed.manualCorrections, trip.manualCorrections + 1)
        XCTAssertEqual(fixed.lateCorrections ?? 0, 0, "поїзд попереду — це не запізнення")
        // Станція, яку назвала людина, — поточна; наступна — за нею.
        XCTAssertEqual(fixed.nextEventIndex(at: now), 5)
    }

    // «Ми тут» позаду моделі: поїзд стояв у тунелі. Відлік має відкотитися,
    // а журнал — записати «поїзд відстає».
    func testTapStationBehindMovesCountdownLaterAndCountsLate() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        let now = trip.events[6].arrival.addingTimeInterval(5)      // модель: біля [6]
        let fixed = try XCTUnwrap(TripEngine.positionCorrection(of: trip, at: 4, now: now, repo: repo))
        XCTAssertGreaterThan(fixed.arrivalDate, trip.arrivalDate)
        XCTAssertEqual(fixed.lateCorrections, (trip.lateCorrections ?? 0) + 1)
        // Поїзд стоїть на названій станції зараз: до наступної — стоянка плюс перегін.
        let timing = repo.timing(from: trip.events[4].stationId, to: trip.events[5].stationId)
        let dwell = repo.timing(from: trip.events[3].stationId, to: trip.events[4].stationId).dwell
        XCTAssertEqual(fixed.events[5].arrival.timeIntervalSince(now),
                       TimeInterval(dwell + timing.travel), accuracy: 1)
    }

    // Станція посадки: «поїзд щойно рушив» — відлік заново від зараз, без стоянки.
    func testTapOriginRestartsFromNow() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        let now = start.addingTimeInterval(90)
        let fixed = try XCTUnwrap(TripEngine.positionCorrection(of: trip, at: 0, now: now, repo: repo))
        XCTAssertEqual(fixed.arrivalDate.timeIntervalSince(now),
                       trip.arrivalDate.timeIntervalSince(start), accuracy: 1)
    }

    // Станція виходу — не поправка, а прибуття: чиста частина її не перераховує.
    func testTapDestinationIsNotACorrection() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        XCTAssertNil(TripEngine.positionCorrection(of: trip, at: trip.events.count - 1,
                                                   now: start, repo: repo))
        XCTAssertNil(TripEngine.positionCorrection(of: trip, at: 99, now: start, repo: repo))
    }

    // Після пересадки тап по станції посадки нової лінії = «Поїзд рушив».
    func testTapTransferRowEqualsBoarded() throws {
        let trip = try plan("universytet", "poshtova-ploshcha")
        let index = try XCTUnwrap(trip.transferIndex)
        let now = trip.events[index - 1].arrival.addingTimeInterval(200)
        let tapped = try XCTUnwrap(TripEngine.positionCorrection(of: trip, at: index, now: now, repo: repo))
        let boarded = try XCTUnwrap(TripPlanner.replan(trip: trip, anchoredAt: index, now: now, repo: repo))
        XCTAssertEqual(tapped.arrivalDate, boarded.arrivalDate)
    }

    // «Виходьте» читалося як наказ. Прибуття — це розрахунок: заголовок каже,
    // що має бути за вікном, текст просить звірити з табличкою.
    func testArrivalNotificationAsksToCheckTheSign() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        let arrival = try XCTUnwrap(NotificationScheduler.plan(for: trip, now: start)
            .first { $0.id == "trip.arrival" })
        XCTAssertTrue(arrival.title.contains("Хрещатик"))
        XCTAssertTrue(arrival.title.hasPrefix("Має бути"))
        XCTAssertTrue(arrival.body.contains("табличк"))
        XCTAssertFalse(arrival.body.hasPrefix("Виходьте"))
    }

    // Будильник без AlarmKit: те саме попередження ще двічі, з кроком 15 с,
    // і завжди раніше за прибуття — інакше «розбудили» б уже за станцією.
    func testRepeatNudgesFollowTheOneStopWarning() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        let plain = NotificationScheduler.plan(for: trip, now: start)
        XCTAssertFalse(plain.contains { $0.id.hasPrefix("trip.nudge.") })

        let loud = NotificationScheduler.plan(for: trip, now: start, repeatNudges: true)
        let nudges = loud.filter { $0.id.hasPrefix("trip.nudge.") }
        XCTAssertEqual(nudges.map(\.id), ["trip.nudge.1", "trip.nudge.2"])
        XCTAssertEqual(nudges[0].date, trip.alertDate.addingTimeInterval(15))
        XCTAssertEqual(nudges[1].date, trip.alertDate.addingTimeInterval(30))
        XCTAssertTrue(nudges.allSatisfy { $0.date < trip.arrivalDate })
        XCTAssertTrue(nudges.allSatisfy { $0.title == L10n.notifNextTitle(trip.destinationName) })

        // Маршрут в одну зупинку: «наступна — ваша» збігається зі стартом —
        // будити тоді нема кого, повторюється прибуття (як і будильник).
        let short = try plan("universytet", "teatralna")
        let shortNudges = NotificationScheduler.plan(for: short, now: start, repeatNudges: true)
            .filter { $0.id.hasPrefix("trip.nudge.") }
        XCTAssertEqual(shortNudges.first?.date, short.arrivalDate.addingTimeInterval(15))
    }

    // Коли дзвонить будильник: за зупинку до виходу; якщо цей момент позаду —
    // на прибутті; після прибуття — ніколи.
    func testWakeAlarmFireDate() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        XCTAssertEqual(WakeAlarm.fireDate(for: trip, now: start), trip.alertDate)
        XCTAssertEqual(WakeAlarm.fireDate(for: trip, now: trip.alertDate.addingTimeInterval(1)),
                       trip.arrivalDate)
        XCTAssertNil(WakeAlarm.fireDate(for: trip, now: trip.arrivalDate))
    }

    // «Я вийшов» з картки: прибуття зараховано, похибку — ні (тиснуть уже на
    // ескалаторі), а запит оцінки тепер можливий і без замірів.
    func testCardArrivalCountsTripButNotError() throws {
        let trip = try plan("lisova", "chernihivska")
        let card = TripLogEntry(trip: trip, outcome: .arrived,
                                endedAt: trip.arrivalDate.addingTimeInterval(150),
                                confirmedOnCard: true)
        XCTAssertTrue(card.finished)
        XCTAssertEqual(card.outcome, .arrived)
        XCTAssertNil(card.errorSeconds)
        XCTAssertEqual(card.fromId, "lisova")
        XCTAssertEqual(card.toId, "chernihivska")

        XCTAssertFalse(TripLogStore.deservesReviewPrompt([card, card]))
        XCTAssertTrue(TripLogStore.deservesReviewPrompt([card, card, card]))

        // Де похибку виміряно, поріг ±30 с лишається.
        let off = TripLogEntry(trip: trip, outcome: .arrived,
                               endedAt: trip.arrivalDate.addingTimeInterval(90))
        XCTAssertFalse(TripLogStore.deservesReviewPrompt([off, off, off]))
        let good = TripLogEntry(trip: trip, outcome: .arrived,
                                endedAt: trip.arrivalDate.addingTimeInterval(10))
        XCTAssertTrue(TripLogStore.deservesReviewPrompt([good, card, card]))
        // Кинута поїздка прибуттям не рахується.
        let stopped = TripLogEntry(trip: trip, outcome: .stopped, endedAt: start)
        XCTAssertFalse(TripLogStore.deservesReviewPrompt([card, card, stopped]))
    }

    // Старий журнал (до 1.4) без нових полів читається, а не губиться.
    func testLegacyLogEntryStillDecodes() throws {
        let legacy = """
        [{"id":"5C2B0D52-3F0C-4C66-9D4B-3A7B2C1D0E9F","date":"2026-09-01T08:00:00Z",
          "fromName":"Лісова","toName":"Хрещатик","plannedSeconds":900,"finalSeconds":930,
          "manualCorrections":0,"gpsCorrections":0,"transfers":0,"finished":true,
          "outcome":"arrived","confirmedSeconds":940}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([TripLogEntry].self, from: Data(legacy.utf8))
        XCTAssertEqual(entries.first?.errorSeconds, 10)
        XCTAssertNil(entries.first?.fromId)
    }

    // Текст «Буду на…»: обрана станція і київський час, округлений до хвилини.
    func testShareArrivalText() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        let text = trip.shareArrivalText(repo: repo)
        let rounded = Date(timeIntervalSince1970:
            (trip.arrivalDate.timeIntervalSince1970 / 60).rounded() * 60)
        XCTAssertTrue(text.contains("«Хрещатик»"), text)
        XCTAssertTrue(text.contains(MetroRepository.kyivClock.string(from: rounded)), text)
        XCTAssertTrue(text.contains("metrotimer.app"))

        // Обрали «Золоті ворота», а з поїзда виходять на «Театральній»: у тексті —
        // обрана станція і час уже після переходу.
        let walked = try plan("universytet", "zoloti-vorota")
        XCTAssertEqual(walked.events.last?.stationId, "teatralna")
        let walk = try XCTUnwrap(repo.transfers.first {
            Set([$0.fromId, $0.toId]) == Set(["teatralna", "zoloti-vorota"])
        })
        XCTAssertEqual(walked.arrivalAtChosenStation(repo: repo),
                       walked.arrivalDate.addingTimeInterval(TimeInterval(walk.walkSeconds)))
        XCTAssertTrue(walked.shareArrivalText(repo: repo).contains("«Золоті ворота»"))
        XCTAssertEqual(trip.arrivalAtChosenStation(repo: repo), trip.arrivalDate)
    }

    // Позначки станцій на смузі острова: по одній на проміжну зупинку, по
    // порядку, всередині смуги. Після поправки пройдені не злипаються в одну.
    func testStationMarksOnTheBar() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        let marks = MetroActivityAttributes.ContentState.stationMarks(trip: trip, now: start)
        XCTAssertEqual(marks.count, trip.events.count - 2)
        XCTAssertEqual(marks, marks.sorted())
        XCTAssertTrue(marks.allSatisfy { $0 > 0 && $0 < 1 })

        let now = trip.events[5].arrival
        let fixed = try XCTUnwrap(TripPlanner.replan(trip: trip, anchoredAt: 5, now: now, repo: repo))
        let after = MetroActivityAttributes.ContentState.stationMarks(trip: fixed, now: now)
        XCTAssertEqual(after.count, marks.count)
        XCTAssertEqual(Set(after.map { ($0 * 1000).rounded() }).count, after.count,
                       "риски не мають злипатися")
        XCTAssertEqual(after, after.sorted())
    }

    // «Перед вашою: Театральна» — станція перед виходом; для маршруту в одну
    // зупинку це станція посадки, і рядок не потрібен.
    func testPenultimateStationOnTheCard() throws {
        let trip = try plan("akademmistechko", "khreshchatyk")
        let state = MetroActivityAttributes.ContentState(trip: trip, now: start)
        XCTAssertEqual(state.penultimateName, "Театральна")

        let short = try plan("universytet", "teatralna")
        XCTAssertNil(MetroActivityAttributes.ContentState(trip: short, now: start).penultimateName)
    }
}
