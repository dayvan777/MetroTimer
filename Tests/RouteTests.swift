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
