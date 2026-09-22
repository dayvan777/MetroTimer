import ActivityKit
import Foundation

struct MetroActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var arrivalDate: Date          // расчётное время прибытия
        var alertDate: Date            // время «наступна — ваша»
        var stopsRemaining: Int
        var nextStationName: String
        // Цвет текущего этапа: после пересадки остров перекрашивается в новую линию.
        var lineColorHex: String?
        // Пассажир на пересадке и ещё не подтвердил посадку. Опциональное поле:
        // активность, созданная прошлой версией, декодируется без него.
        var isChangingLines: Bool?
        // Коли застосунок востаннє оновив лічильник зупинок. Поки застосунок
        // спить, оновити його нікому (фонових режимів немає), і карточка чесно
        // показує «станом на HH:MM» замість того, щоб видавати старе за свіже.
        var updatedAt: Date?
        // Позначки станцій на смузі прогресу: частки шляху від старту до
        // прибуття. Смуга рухається сама (ProgressView(timerInterval:)), а
        // позначки стоять — пасажир бачить, скільки станцій лишилось, навіть
        // коли застосунок спить. Лічильник «Ще N зупинок» у цей час застигав.
        var stationMarks: [Double]?
        // Станція перед виходом: факт із розкладу, який не старіє (1.4).
        var penultimateName: String?

        // Час оновлення — не частина стану. Інакше кожен тік давав би «новий»
        // стан, і острів отримував би пуш щосекунди; стан має змінюватись лише
        // тоді, коли змінилось щось по суті (зупинка, станція, лінія).
        static func == (lhs: ContentState, rhs: ContentState) -> Bool {
            lhs.arrivalDate == rhs.arrivalDate
                && lhs.alertDate == rhs.alertDate
                && lhs.stopsRemaining == rhs.stopsRemaining
                && lhs.nextStationName == rhs.nextStationName
                && lhs.lineColorHex == rhs.lineColorHex
                && lhs.isChangingLines == rhs.isChangingLines
                && lhs.penultimateName == rhs.penultimateName
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(arrivalDate)
            hasher.combine(alertDate)
            hasher.combine(stopsRemaining)
            hasher.combine(nextStationName)
            hasher.combine(lineColorHex)
            hasher.combine(isChangingLines)
            hasher.combine(penultimateName)
        }
    }

    let destinationName: String
    let lineColorHex: String
    let totalStops: Int                 // для сегментной полосы прогресса
    // Початок поїздки: прогрес на карточці веде сам SwiftUI за часом, без
    // оновлень від застосунку. Опційне поле — старі активності без нього.
    var startDate: Date?
}

// Единственное место, где состояние Live Activity выводится из поездки.
extension MetroActivityAttributes.ContentState {
    init(trip: ActiveTrip, now: Date) {
        let repo = MetroRepository.shared
        let nextIndex = trip.nextEventIndex(at: now) ?? trip.events.count
        let legLine = trip.events[min(nextIndex, trip.events.count - 1)].lineId
        let penultimate = trip.events.dropLast().last(where: { $0.isStop || $0.isTransfer })
        self.init(arrivalDate: trip.arrivalDate,
                  alertDate: trip.alertDate,
                  stopsRemaining: trip.stopsRemaining(at: now),
                  nextStationName: trip.nextStop(at: now)?.displayName ?? trip.destinationName,
                  lineColorHex: repo.line(id: legLine)?.colorHex,
                  isChangingLines: trip.isChangingLines(at: now),
                  updatedAt: now,
                  stationMarks: Self.stationMarks(trip: trip, now: now),
                  // Маршрут в одну зупинку: перед виходом — станція посадки, казати нічого.
                  penultimateName: penultimate.flatMap {
                      $0.stationId == trip.events.first?.stationId ? nil : $0.displayName
                  })
    }

    // Проміжні зупинки й пересадки як частки смуги «старт → прибуття».
    // Після поправки пройдені станції мають штучні часи «щойно» (див. replan):
    // на смузі вони злиплися б в одну риску, тому їх розкладаємо рівно до «зараз».
    static func stationMarks(trip: ActiveTrip, now: Date) -> [Double] {
        let total = trip.arrivalDate.timeIntervalSince(trip.startDate)
        guard total > 0, trip.events.count > 2 else { return [] }
        let inner = trip.events.dropFirst().dropLast().filter { $0.isStop || $0.isTransfer }
        let clamp: (Double) -> Double = { min(max($0, 0), 1) }
        let nowFraction = clamp(now.timeIntervalSince(trip.startDate) / total)
        let passed = inner.filter { $0.arrival <= now }.count
        var marks = (0..<passed).map { nowFraction * Double($0 + 1) / Double(passed + 1) }
        marks += inner.filter { $0.arrival > now }
            .map { clamp($0.arrival.timeIntervalSince(trip.startDate) / total) }
        return marks
    }
}
