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
