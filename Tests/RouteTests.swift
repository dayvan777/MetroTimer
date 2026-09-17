import XCTest
@testable import MetroTimer

// Книжка маршрутів і пошук станцій. Логіка чиста (RouteBook — значення),
// тому тести не торкаються файла пристрою — рівно та пастка, на якій
// уже обпікся тест бандл-даних із чужою калібровкою.
final class RouteTests: XCTestCase {
    private let repo = MetroRepository.shared

    private let home = RecentTrip(lineId: "m2", fromId: "heroiv-dnipra", toId: "hidropark")
    private let work = RecentTrip(lineId: "m1", fromId: "vokzalna", toId: "khreshchatyk")
    private let gym  = RecentTrip(lineId: "m3", fromId: "syrets", toId: "osokorky")
    private let dacha = RecentTrip(lineId: "m1", fromId: "arsenalna", toId: "lisova")

    // MARK: - Закритий файл — не порожній файл

    // Процес може підняти кнопка Live Activity із заблокованого екрана: файли під
    // completeUnlessOpen у цю мить не читаються. Раніше сховища сприймали це як
    // «файла нема», стартували порожніми і першим же збереженням стирали закріплені
    // маршрути, журнал і калібрування. Замок імітуємо правами 000: атомарний запис
    // його обходить (перейменування в теці) — рівно як у житті.
    private func lockedFile(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("locktest-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        try body(url)
    }

    private func setLocked(_ locked: Bool, _ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: locked ? 0o000 : 0o644],
                                              ofItemAtPath: url.path)
    }

    func testLockedRouteBookIsNotOverwritten() throws {
        try lockedFile { url in
            RouteStore(fileURL: url).rememberRecent(home)
            let onDisk = try Data(contentsOf: url)

            try setLocked(true, url)
            let blind = RouteStore(fileURL: url)
            XCTAssertTrue(blind.isLocked)
            XCTAssertTrue(blind.book.recents.isEmpty, "прочитати не вдалося — у пам'яті порожньо")
            blind.rememberRecent(work)

            try setLocked(false, url)
            XCTAssertEqual(try Data(contentsOf: url), onDisk, "файл на диску не зачеплено")
            blind.reloadIfLocked()
            XCTAssertFalse(blind.isLocked)
            XCTAssertEqual(blind.book.recents, [home])
            blind.rememberRecent(work)
            XCTAssertEqual(RouteStore(fileURL: url).book.recents, [work, home], "після розблокування пишемо як завжди")
        }
    }

    func testLockedJournalKeepsOldEntriesAndTheBlindOne() throws {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let first = try XCTUnwrap(TripPlanner.plan(fromId: "vokzalna", toId: "khreshchatyk", start: start, repo: repo))
        let second = try XCTUnwrap(TripPlanner.plan(fromId: "syrets", toId: "osokorky", start: start, repo: repo))
        try lockedFile { url in
            TripLogStore(fileURL: url).append(trip: first, outcome: .arrived, at: start)

            try setLocked(true, url)
            let blind = TripLogStore(fileURL: url)
            XCTAssertTrue(blind.isLocked)
            blind.append(trip: second, outcome: .expired, at: start.addingTimeInterval(3600))

            try setLocked(false, url)
            blind.reloadIfLocked()
            XCTAssertEqual(blind.entries.map(\.outcome), [.expired, .arrived], "сліпий запис зверху, старий на місці")
            XCTAssertEqual(TripLogStore(fileURL: url).entries.map(\.outcome), [.expired, .arrived], "і на диску теж")
        }
    }

    func testLockedCalibrationIsNotOverwritten() throws {
        try lockedFile { url in
            let store = CalibrationStore(fileURL: url)
            XCTAssertTrue(store.recordTravel(from: "vokzalna", to: "universytet", seconds: 100))
            store.save()

            try setLocked(true, url)
            let blind = CalibrationStore(fileURL: url)
            XCTAssertTrue(blind.isLocked)
            XCTAssertNil(blind.record(from: "vokzalna", to: "universytet"))
            blind.save()

            try setLocked(false, url)
            blind.reloadIfLocked()
            XCTAssertEqual(blind.record(from: "vokzalna", to: "universytet")?.travelSeconds, 100)
        }
    }

    // 1. Останні: повтор піднімається нагору без дубля, хвіст обрізається.
    func testRecentsDedupeAndCap() {
        var book = RouteBook()
        book = book.addingRecent(home)
        book = book.addingRecent(work)
        book = book.addingRecent(home)
        XCTAssertEqual(book.recents, [home, work], "повтор не множиться, лише спливає")
        book = book.addingRecent(gym)
        book = book.addingRecent(dacha)
        XCTAssertEqual(book.recents.count, RouteBook.maxRecents)
        XCTAssertEqual(book.recents.first, dacha, "найновіший — перший")
        XCTAssertFalse(book.recents.contains(work), "найстаріший випав")
    }

    // 2. Закріплені: перемикач додає і прибирає, стеля тримається.
    func testFavoritesToggleAndCap() {
        var book = RouteBook()
        book = book.togglingFavorite(home)
        XCTAssertTrue(book.isFavorite(home))
        book = book.togglingFavorite(home)
        XCTAssertFalse(book.isFavorite(home), "другий тап знімає зірку")

        for i in 0..<(RouteBook.maxFavorites + 2) {
            book = book.togglingFavorite(
                RecentTrip(lineId: "m1", fromId: "s\(i)", toId: "t\(i)"))
        }
        XCTAssertEqual(book.favorites.count, RouteBook.maxFavorites)
        XCTAssertEqual(book.favorites.first?.fromId, "s7", "новіші витісняють старіші")
    }

    // 3. Закріплений маршрут не показується вдруге серед «останніх».
    func testDisplayedRecentsExcludeFavorites() {
        var book = RouteBook()
        book = book.addingRecent(home)
        book = book.addingRecent(work)
        book = book.togglingFavorite(home)
        XCTAssertEqual(book.displayedRecents, [work])
        XCTAssertEqual(book.recents.count, 2, "у сховищі маршрут лишається — зірку можна зняти")
    }

    // 4. Міграція з UserDefaults перших версій: хвіст довше стелі обрізається.
    func testLegacyMigrationCapsRecents() {
        let legacy = [home, work, gym, dacha, home]
        let book = RouteBook(migratingLegacy: legacy)
        XCTAssertEqual(book.recents, [home, work, gym])
        XCTAssertTrue(book.favorites.isEmpty)
    }

    // 5. Пошук: без регістру, апострофа і мови.
    // ── Нагадування (1.1) ─────────────────────────────────────────────

    func testReminderStoredAndRemoved() {
        var book = RouteBook()
        book = book.togglingFavorite(home)
        let reminder = RouteReminder(weekdays: [2, 3, 4, 5, 6], hour: 8, minute: 15)
        book = book.settingReminder(reminder, for: home)
        XCTAssertEqual(book.reminder(for: home), reminder)
        book = book.settingReminder(nil, for: home)
        XCTAssertNil(book.reminder(for: home))
    }

    func testUnpinDropsReminder() {
        // Знята зірка забирає і розклад: «привидні» сповіщення про маршрут,
        // якого немає в закріплених, — найгірше, що може зробити ця функція.
        var book = RouteBook()
        book = book.togglingFavorite(home)
        book = book.settingReminder(RouteReminder(weekdays: [2], hour: 7, minute: 0), for: home)
        book = book.togglingFavorite(home)   // unpin
        XCTAssertNil(book.reminder(for: home))
    }

    func testBookV10DecodesWithoutReminders() {
        // Файл, записаний версією 1.0 (без ключа reminders), мусить читатися.
        let legacyJSON = """
        {"favorites": [], "recents": []}
        """.data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(RouteBook.self, from: legacyJSON)
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.reminders)
    }

    func testReminderRoundTripsThroughJSON() {
        var book = RouteBook()
        book = book.togglingFavorite(work)
        book = book.settingReminder(RouteReminder(weekdays: [6, 7], hour: 22, minute: 45), for: work)
        let data = try! JSONEncoder().encode(book)
        let decoded = try! JSONDecoder().decode(RouteBook.self, from: data)
        XCTAssertEqual(decoded.reminder(for: work),
                       RouteReminder(weekdays: [6, 7], hour: 22, minute: 45))
    }

    func testUkrainianStopsPluralization() {
        // 1/21 зупинка · 2–4/22 зупинки · 5–20/11–14 зупинок.
        XCTAssertTrue(L10n.routeStops(1).contains("зупинка") || L10n.routeStops(1).contains("stop"))
        for (n, form) in [(2, "зупинки"), (4, "зупинки"), (5, "зупинок"), (11, "зупинок"),
                          (12, "зупинок"), (14, "зупинок"), (21, "зупинка"), (22, "зупинки"),
                          (25, "зупинок")] {
            let text = L10n.routeStops(n)
            if text.contains("stop") { continue }   // англійська локаль симулятора
            XCTAssertTrue(text.hasSuffix(form), "\(n) → \(text)")
        }
    }

    func testStationSearch() {
        XCTAssertEqual(repo.stations(matching: "вокз").map(\.station.id), ["vokzalna"])
        // «Лукʼянівська» в даних — з модифікаторним апострофом U+02BC;
        // запит без апострофа зобов'язаний її знаходити.
        XCTAssertEqual(repo.stations(matching: "ЛУКЯН").map(\.station.id), ["lukianivska"])
        XCTAssertEqual(repo.stations(matching: "лук'ян").map(\.station.id), ["lukianivska"])
        // Англійська назва — для другої локалізації.
        XCTAssertTrue(repo.stations(matching: "hero").map(\.station.id)
            .contains("heroiv-dnipra"))
        // Лінія в результаті — справжня лінія станції: чип у списку фарбується нею.
        let hydro = repo.stations(matching: "гідропарк")
        XCTAssertEqual(hydro.count, 1)
        XCTAssertEqual(hydro.first?.line.id, "m1")
        // Порожній чи безглуздий запит — порожня відповідь, а не всі 52 станції.
        XCTAssertTrue(repo.stations(matching: "   ").isEmpty)
        XCTAssertTrue(repo.stations(matching: "qqq").isEmpty)
    }
}
