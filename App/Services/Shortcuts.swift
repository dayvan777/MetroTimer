import AppIntents
import Foundation

// «Siri, останній маршрут у Метро-таймер» — дорогою до платформи. Застосунок
// відкривається з уже підставленими станціями; «Поїхали» людина тисне сама
// в мить відправлення — цей контракт ярлик не обходить. Закріплений маршрут
// має пріоритет над останнім: «додому» важливіше за випадкову вчорашню поїздку.
@available(iOS 16.4, *)
struct RepeatLastTripIntent: AppIntent {
    static var title: LocalizedStringResource { "Останній маршрут" }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        let book = RouteStore.shared.book
        if TripEngine.shared.trip == nil,
           let route = book.favorites.first ?? book.recents.first {
            TripEngine.shared.pendingPrefill = route
        }
        return .result()
    }
}

@available(iOS 16.4, *)
struct MetroTimerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RepeatLastTripIntent(),
                    phrases: [
                        "Останній маршрут у \(.applicationName)",
                        "Last route in \(.applicationName)",
                    ],
                    shortTitle: "Останній маршрут",
                    systemImageName: "tram.fill")
    }
}
