import SwiftUI

extension Color {
    // Акцент поездки: цвет линии, предупреждающий — когда осталась одна остановка.
    static func tripAccent(stopsRemaining: Int, lineColorHex: String) -> Color {
        stopsRemaining <= 1 ? .orange : Color(hex: lineColorHex)
    }

    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
