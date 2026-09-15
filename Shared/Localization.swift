import Foundation

// Две языковые версии живут парами прямо в Strings.swift — так их физически
// нельзя рассинхронизировать (в .strings-файлах ключ легко забыть).
// Info.plist-строки (запросы геолокации и движения) локализуются системой
// через App/Localization/*.lproj/InfoPlist.strings.
enum Language {
    case uk, en
}

// Меняется только при перезапуске (iOS перезапускает приложение при смене
// языка), поэтому var, а не вычисляемое свойство: тестам нужно переключать.
var appLanguage: Language = detectLanguage()

func detectLanguage() -> Language {
    // Спочатку — перша мова телефону (або вибір для цього застосунку в
    // Параметрах iOS: він теж потрапляє сюди). Раніше ми питали
    // preferredLocalizations, а вона віддає «en», щойно англійська є в списку
    // мов телефону хоч другою: киянин із телефоном «російська + англійська»
    // отримував англійський інтерфейс і не розумів, як його перемкнути.
    let system = Locale.preferredLanguages.first ?? "uk"
    if system.hasPrefix("en") { return .en }
    // Соседним языкам понятнее украинский.
    if ["uk", "ru", "be", "pl"].contains(where: system.hasPrefix) { return .uk }
    // Остальному миру — то, что iOS сама выберет из наших двух локализаций.
    let preferred = Bundle.main.preferredLocalizations.first ?? "en"
    return preferred.hasPrefix("uk") ? .uk : .en
}

// Единственный способ получить текст: обе версии всегда на виду рядом.
func tr(_ uk: String, _ en: String) -> String {
    appLanguage == .uk ? uk : en
}
