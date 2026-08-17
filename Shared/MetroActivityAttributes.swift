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
    }

    let destinationName: String
    let lineColorHex: String
    let totalStops: Int                 // для сегментной полосы прогресса
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
                  isChangingLines: trip.isChangingLines(at: now))
    }
}
