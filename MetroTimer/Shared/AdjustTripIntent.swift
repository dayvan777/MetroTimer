import AppIntents
import Foundation

// Кнопки «−1» / «+1» в Live Activity (iOS 17+).
// LiveActivityIntent выполняется в процессе приложения — фоновые режимы не нужны.
@available(iOS 17.0, *)
struct AdjustTripIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Корекція зупинок" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Зсув")
    var delta: Int

    init() {}

    init(delta: Int) {
        self.delta = delta
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await TripEngine.shared.adjust(by: delta)
        return .result()
    }
}

// «Поїзд рушив» прямо з екрана блокування — головна поправка на маршруті
// з пересадкою. Очікування поїзда на новій лінії неможливо вгадати (полева
// перевірка: модель давала 7 хв, реальність — 2), і єдине точне джерело —
// сам пасажир у момент відправлення. Тому кнопка має бути там, де людина
// вже дивиться на телефон: у Live Activity, без розблокування й відкриття.
@available(iOS 17.0, *)
struct BoardedTransferIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Поїзд рушив" }
    static var isDiscoverable: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TripEngine.shared.boardedAfterTransfer()
        return .result()
    }
}
