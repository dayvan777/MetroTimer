import Foundation

// Попадает ли поездка в часы работы метро. Считается по каждой посадке
// маршрута: отправление и (если есть) поезд после пересадки — успеть на первый
// и не успеть на второй вполне реально поздно вечером.
enum ServiceIssue: Equatable {
    case beforeFirst(station: String, time: Date)   // метро ещё не работает
    case afterLast(station: String, time: Date)     // последний поезд уже ушёл
    case lastSoon(station: String, time: Date)      // успеваете, но поезд из последних
}

enum TripPlanner {

    // Порог «поезд из последних»: раньше предупреждать не о чем, позже — поздно.
    private static let lastTrainWarning: TimeInterval = 3600

    // Первая по маршруту проблема с расписанием; nil — всё в рабочих часах.
    static func serviceIssue(for trip: ActiveTrip, repo: MetroRepository = .shared) -> ServiceIssue? {
        var soon: ServiceIssue?
        for (index, event) in trip.events.enumerated() where index == 0 || event.isTransfer {
            guard index + 1 < trip.events.count else { continue }
            // Посадка: на старте — момент нажатия, после пересадки — расчётная посадка.
            let boarding = index == 0 ? trip.startDate : event.arrival
            guard let window = repo.serviceWindow(fromId: event.stationId,
                                                  towardId: trip.events[index + 1].stationId,
                                                  on: boarding) else { continue }
            if boarding > window.last {
                return .afterLast(station: event.displayName, time: window.last)
            }
            if boarding < window.first {
                return .beforeFirst(station: event.displayName, time: window.first)
            }
            if soon == nil, window.last.timeIntervalSince(boarding) < lastTrainWarning {
                soon = .lastSoon(station: event.displayName, time: window.last)
            }
        }
        return soon
    }


    // Маршрут по одной линии или с одной пересадкой (в Киеве любая пара линий
    // связана ровно одним узлом); nil — невалидная пара станций.
    static func plan(fromId: String, toId: String, start: Date,
                     repo: MetroRepository = .shared) -> ActiveTrip? {
        guard fromId != toId,
              let fromLine = repo.line(ofStation: fromId),
              let toLine = repo.line(ofStation: toId),
              repo.station(id: fromId)?.isClosed == false,
              repo.station(id: toId)?.isClosed == false
        else { return nil }

        var events: [StopEvent]
        if fromLine.id == toLine.id {
            guard let leg = legEvents(line: fromLine, from: fromId, to: toId,
                                      placeholder: start, repo: repo) else { return nil }
            events = leg
        } else {
            guard let node = repo.transfer(from: fromLine.id, to: toLine.id),
                  let boardStation = repo.station(id: node.boardAt) else { return nil }
            // Этап 1 до станции выхода (может состоять из одной станции,
            // если отправление — сам пересадочный узел).
            guard let leg1 = legEvents(line: fromLine, from: fromId, to: node.exitAt,
                                       placeholder: start, repo: repo) else { return nil }
            events = leg1
            // Пеший переход; если он же и есть пункт назначения — это остановка.
            let walkIsDestination = node.boardAt == toId
            events.append(StopEvent(stationId: boardStation.id, nameUk: boardStation.nameUk,
                                    nameEn: boardStation.nameEn, lineId: toLine.id,
                                    arrival: start, departure: start,
                                    isStop: walkIsDestination, isTransfer: true))
            if !walkIsDestination {
                guard let leg2 = legEvents(line: toLine, from: node.boardAt, to: toId,
                                           placeholder: start, repo: repo) else { return nil }
                events.append(contentsOf: leg2.dropFirst())   // узел уже добавлен как переход
            }
        }

        fill(events: &events, from: 1, cursor: start, repo: repo)
        return ActiveTrip(lineId: fromLine.id, fromId: fromId, toId: toId,
                          startDate: start, initialArrival: events.last?.arrival ?? start,
                          manualCorrections: 0, gpsCorrections: 0, events: events)
    }

    // События одного этапа по линии, времена — заглушки до fill().
    private static func legEvents(line: Line, from: String, to: String,
                                  placeholder: Date, repo: MetroRepository) -> [StopEvent]? {
        guard let fromIndex = line.stationIds.firstIndex(of: from),
              let toIndex = line.stationIds.firstIndex(of: to) else { return nil }
        let step = toIndex >= fromIndex ? 1 : -1
        var events: [StopEvent] = []
        var index = fromIndex
        while true {
            guard let station = repo.station(id: line.stationIds[index]) else { return nil }
            // Ділянка без руху розриває маршрут: краще чесно відмовити, ніж
            // рахувати час поїзда, якого немає.
            if let previous = events.last,
               repo.isSuspended(from: previous.stationId, to: station.id) {
                return nil
            }
            events.append(StopEvent(stationId: station.id, nameUk: station.nameUk,
                                    nameEn: station.nameEn, lineId: line.id,
                                    arrival: placeholder, departure: placeholder,
                                    isStop: !station.isClosed, isTransfer: false))
            if index == toIndex { break }
            index += step
        }
        return events
    }

    // Ручная коррекция ±1: считаем, что прямо сейчас поезд остановился
    // на станции перед «правильной следующей».
    static func replan(trip: ActiveTrip, nextStopShift delta: Int, now: Date,
                       repo: MetroRepository = .shared) -> ActiveTrip? {
        // После модельного прибытия «следующей» нет — считаем её за концом списка,
        // чтобы «+1» (поезд ещё едет) снова ставил якорь на предпоследнюю станцию.
        let modelNext = trip.nextEventIndex(at: now) ?? trip.events.count
        // delta = +1 — «на самом деле я на одну станцию раньше», т.е. следующая — предыдущая по модели.
        let correctedNext = modelNext - delta
        guard correctedNext < trip.events.count else { return nil }
        // «+1» на первой станции = «поїзд ще не рушив» (натиснули на пероні):
        // ставим якорь на станцию отправления — отсчёт начинается заново от «зараз».
        guard correctedNext >= 1 else {
            return correctedNext == 0 ? replan(trip: trip, anchoredAt: 0, now: now, repo: repo) : nil
        }
        return replan(trip: trip, anchoredAt: correctedNext - 1, now: now, repo: repo)
    }

    // Общий якорный вариант (ручная коррекция и GPS): поезд прямо сейчас
    // у станции anchor — стоит на ней, а закрытую проезжает.
    static func replan(trip: ActiveTrip, anchoredAt anchor: Int, now: Date,
                       repo: MetroRepository = .shared) -> ActiveTrip? {
        guard anchor >= 0, anchor < trip.events.count else { return nil }
        var events = trip.events
        // Пройденным станциям — синтетические времена в прошлом (для приглушения в UI).
        for i in 0...anchor {
            let t = now.addingTimeInterval(TimeInterval(-(anchor - i)))
            events[i] = StopEvent(stationId: events[i].stationId, nameUk: events[i].nameUk,
                                  nameEn: events[i].nameEn, lineId: events[i].lineId,
                                  arrival: t, departure: t,
                                  isStop: events[i].isStop, isTransfer: events[i].isTransfer)
        }
        // Стоянка на якорной станции ещё впереди: поезд стоит там прямо сейчас.
        var cursor = now
        if anchor >= 1, events[anchor].isStop, !events[anchor].isTransfer {
            let dwell = repo.timing(from: events[anchor - 1].stationId,
                                    to: events[anchor].stationId).dwell
            cursor = cursor.addingTimeInterval(TimeInterval(dwell))
        }
        fill(events: &events, from: anchor + 1, cursor: cursor, repo: repo)

        var replanned = trip
        replanned.events = events
        return replanned
    }

    // Единое правило хода: arrival = cursor + travel; стоянка — только на промежуточных
    // открытых станциях, dwell принадлежит сегменту прибытия. Пеший переход — сегмент
    // без стоянки (его время задано в segments узла).
    private static func fill(events: inout [StopEvent], from startIndex: Int,
                             cursor: Date, repo: MetroRepository) {
        var cursor = cursor
        for i in startIndex..<events.count {
            let prev = events[i - 1]
            let timing = repo.timing(from: prev.stationId, to: events[i].stationId)
            let travel = timing.travel + transferWait(events: events, index: i,
                                                      platformAt: cursor.addingTimeInterval(
                                                        TimeInterval(timing.travel)),
                                                      repo: repo)
            let arrival = cursor.addingTimeInterval(TimeInterval(travel))
            let isDestination = i == events.count - 1
            let dwells = events[i].isStop && !events[i].isTransfer && !isDestination
            let departure = dwells
                ? arrival.addingTimeInterval(TimeInterval(timing.dwell))
                : arrival
            events[i] = StopEvent(stationId: events[i].stationId, nameUk: events[i].nameUk,
                                  nameEn: events[i].nameEn, lineId: events[i].lineId,
                                  arrival: arrival, departure: departure,
                                  isStop: events[i].isStop, isTransfer: events[i].isTransfer)
            cursor = departure
        }
    }

    // Ожидание поезда после пешего перехода: в среднем половина интервала движения
    // на новой линии в момент выхода на платформу. В час пик это ~1.5 мин,
    // около 22:00 — до 5.5 мин; фиксированная надбавка врала бы и там, и там.
    // 0, если пересадка — сам пункт назначения (садиться уже не нужно) или
    // расписание неизвестно.
    private static func transferWait(events: [StopEvent], index: Int,
                                     platformAt: Date, repo: MetroRepository) -> Int {
        guard events[index].isTransfer, index + 1 < events.count,
              let forward = repo.isForward(lineId: events[index].lineId,
                                           from: events[index].stationId,
                                           to: events[index + 1].stationId),
              let wait = repo.expectedWaitSeconds(lineId: events[index].lineId,
                                                  forward: forward, at: platformAt)
        else { return 0 }
        return wait
    }
}
