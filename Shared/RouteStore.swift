import Foundation

// Закріплені та останні маршрути. Пара «звідки → куди» — найпромовистіше,
// що застосунок знає про людину: де вона буває щодня. Тому книжка маршрутів
// лежить не в UserDefaults (той потрапляє в резервні копії завжди), а в
// зашифрованому файлі, виключеному з бекапів, — за тим самим правилом, що
// журнал поїздок і калібрування.
// Модель нагадування лежить у Shared: RouteBook (спільний із віджетом код)
// мусить її бачити, а UN-логіка лишається в застосунку (ReminderService).
struct RouteReminder: Codable, Equatable, Hashable {
    // Calendar.weekday: 1 = неділя … 7 = субота.
    var weekdays: Set<Int>
    var hour: Int
    var minute: Int
}

struct RouteBook: Codable, Equatable {
    var favorites: [RecentTrip] = []
    var recents: [RecentTrip] = []
    // Нагадування живуть поруч із маршрутами не випадково: «щобудня о 8:15
    // з Оболоні» — такий самий чутливий факт, як і сам маршрут, тож і захист
    // у нього той самий (шифрований файл поза бекапами). Optional — щоб файли
    // версії 1.0 декодувалися без міграції.
    var reminders: [String: RouteReminder]? = nil

    // Шість закріплених покривають «додому/на роботу» всієї родини; довший
    // ряд чипів перестає читатися одним поглядом.
    static let maxFavorites = 6
    static let maxRecents = 3

    init() {}

    // Перші версії тримали останні маршрути в UserDefaults — забираємо один раз.
    init(migratingLegacy recents: [RecentTrip]) {
        self.recents = Array(recents.prefix(Self.maxRecents))
    }

    // Чиста логіка окремо від диска: її ганяють тести, не чіпаючи файл пристрою.
    func addingRecent(_ route: RecentTrip) -> RouteBook {
        var book = self
        book.recents = Array(([route] + recents.filter { $0 != route }).prefix(Self.maxRecents))
        return book
    }

    func togglingFavorite(_ route: RecentTrip) -> RouteBook {
        var book = self
        if favorites.contains(route) {
            book.favorites = favorites.filter { $0 != route }
            book.reminders?[Self.reminderKey(route)] = nil
        } else {
            book.favorites = Array(([route] + favorites).prefix(Self.maxFavorites))
        }
        return book
    }

    func isFavorite(_ route: RecentTrip) -> Bool { favorites.contains(route) }

    static func reminderKey(_ route: RecentTrip) -> String { "\(route.fromId)>\(route.toId)" }

    func reminder(for route: RecentTrip) -> RouteReminder? {
        reminders?[Self.reminderKey(route)]
    }

    func settingReminder(_ reminder: RouteReminder?, for route: RecentTrip) -> RouteBook {
        var book = self
        var map = book.reminders ?? [:]
        map[Self.reminderKey(route)] = reminder
        book.reminders = map
        return book
    }

    // Закріплений маршрут не дублюється серед «останніх»: ряд чипів
    // читається один раз, а не двічі.
    var displayedRecents: [RecentTrip] { recents.filter { !favorites.contains($0) } }
}

final class RouteStore {
    static let shared = RouteStore()

    private(set) var book: RouteBook

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("routes.json")
    }

    private static let legacyRecentsKey = "recentTrips"

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(RouteBook.self, from: data) {
            book = decoded
        } else {
            let legacy = UserDefaults.standard.data(forKey: Self.legacyRecentsKey)
                .flatMap { try? JSONDecoder().decode([RecentTrip].self, from: $0) } ?? []
            book = RouteBook(migratingLegacy: legacy)
            if !book.recents.isEmpty { save() }
            UserDefaults.standard.removeObject(forKey: Self.legacyRecentsKey)
        }
    }

    func rememberRecent(_ route: RecentTrip) {
        book = book.addingRecent(route)
        save()
    }

    func toggleFavorite(_ route: RecentTrip) {
        book = book.togglingFavorite(route)
        save()
    }

    func setReminder(_ reminder: RouteReminder?, for route: RecentTrip) {
        book = book.settingReminder(reminder, for: route)
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(book) {
            try? data.write(to: Self.fileURL, options: .atomic)
            FileManager.default.protectAsLocalOnly(Self.fileURL)
        }
    }
}
