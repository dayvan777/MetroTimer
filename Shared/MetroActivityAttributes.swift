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
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(arrivalDate)
            hasher.combine(alertDate)
            hasher.combine(stopsRemaining)
            hasher.combine(nextStationName)
            hasher.combine(lineColorHex)
            hasher.combine(isChangingLines)
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
        self.init(arrivalDate: trip.arrivalDate,
                  alertDate: trip.alertDate,
                  stopsRemaining: trip.stopsRemaining(at: now),
                  nextStationName: trip.nextStop(at: now)?.displayName ?? trip.destinationName,
                  lineColorHex: repo.line(id: legLine)?.colorHex,
                  isChangingLines: trip.isChangingLines(at: now),
                  updatedAt: now)
    }
}
