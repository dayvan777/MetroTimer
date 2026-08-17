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
    // preferredLocalizations учитывает и язык системы, и выбор языка
    // конкретного приложения в Параметрах iOS.
    let preferred = Bundle.main.preferredLocalizations.first ?? "uk"
    if preferred.hasPrefix("en") { return .en }
    if preferred.hasPrefix("uk") { return .uk }
    // Язык, которого в приложении нет, iOS сводит к языку разработки.
    // Соседним языкам понятнее украинский, остальному миру — английский.
    let system = Locale.preferredLanguages.first ?? "uk"
    return ["uk", "ru", "be", "pl"].contains(where: system.hasPrefix) ? .uk : .en
}

// Единственный способ получить текст: обе версии всегда на виду рядом.
func tr(_ uk: String, _ en: String) -> String {
    appLanguage == .uk ? uk : en
}
