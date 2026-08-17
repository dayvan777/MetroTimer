import Foundation

final class MetroRepository {
    static let shared = MetroRepository()

    let data: MetroData
    private let stationById: [String: Station]
    private let lineByStationId: [String: Line]
    private let seedSegments: [String: Segment]   // ключ "from>to", только прямое направление
    private let headwayByKey: [String: Headway]   // ключ "line|hour|holiday"
    private let serviceByStation: [String: ServiceHours]

    // Расписание метро задано в киевском времени — считаем в нём, где бы ни был телефон.
    static let kyivCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv") ?? .current
        return calendar
    }()

    private init() {
        guard let url = Bundle.main.url(forResource: "kyiv_metro", withExtension: "json") else {
            fatalError("kyiv_metro.json відсутній у бандлі")
        }
        do {
            data = try JSONDecoder().decode(MetroData.self, from: Data(contentsOf: url))
        } catch {
            fatalError("kyiv_metro.json не читається: \(error)")
        }
        stationById = Dictionary(uniqueKeysWithValues: data.stations.map { ($0.id, $0) })
        var byStation: [String: Line] = [:]
        for line in data.lines {
            for id in line.stationIds { byStation[id] = line }
        }
        lineByStationId = byStation
        seedSegments = Dictionary(uniqueKeysWithValues: data.segments.map { (Segment.key($0.fromId, $0.toId), $0) })
        headwayByKey = Dictionary(uniqueKeysWithValues: data.headways.map {
            (Self.headwayKey(lineId: $0.lineId, hour: $0.hour, isHoliday: $0.isHoliday), $0)
        })
        serviceByStation = Dictionary(uniqueKeysWithValues: data.serviceHours.map { ($0.stationId, $0) })
    }

    var lines: [Line] { data.lines }

    func line(id: String) -> Line? {
        data.lines.first(where: { $0.id == id })
    }

    func line(ofStation stationId: String) -> Line? {
        lineByStationId[stationId]
    }

    func station(id: String) -> Station? {
        stationById[id]
    }

    func stations(of line: Line) -> [Station] {
        line.stationIds.compactMap { stationById[$0] }
    }

    // Пересадочный узел между двумя линиями: (станция линии a, станция линии b).
    // В Киеве каждая пара линий связана ровно одним узлом.
    func transfer(from lineA: String, to lineB: String) -> (exitAt: String, boardAt: String)? {
        for transfer in data.transfers {
            let lineOfFrom = line(ofStation: transfer.fromId)?.id
            let lineOfTo = line(ofStation: transfer.toId)?.id
            if lineOfFrom == lineA, lineOfTo == lineB {
                return (transfer.fromId, transfer.toId)
            }
            if lineOfTo == lineA, lineOfFrom == lineB {
                return (transfer.toId, transfer.fromId)
            }
        }
        return nil
    }

    // Движение по перегону приостановлено (в обе стороны — путь один).
    func isSuspended(from: String, to: String) -> Bool {
        let seed = seedSegments[Segment.key(from, to)] ?? seedSegments[Segment.key(to, from)]
        return seed?.isSuspended == true
    }

    // Сид-времена перегона (без калибровки): прямое направление → зеркальное → дефолт.
    func seedTiming(from: String, to: String) -> (travel: Int, dwell: Int) {
        let seed = seedSegments[Segment.key(from, to)] ?? seedSegments[Segment.key(to, from)]
        return (seed?.travelSeconds ?? 115, seed?.dwellSeconds ?? 25)
    }

    // Времена перегона from→to; направление имеет значение.
    // Каждое поле независимо: калибровка → сид (замер только хода не трогает сид стоянки).
    func timing(from: String, to: String) -> (travel: Int, dwell: Int) {
        let seed = seedTiming(from: from, to: to)
        let calibrated = CalibrationStore.shared.record(from: from, to: to)
        let travel = calibrated?.travelSeconds.map { Int($0.rounded()) } ?? seed.travel
        let dwell = calibrated?.dwellSeconds.map { Int($0.rounded()) } ?? seed.dwell
        return (travel, dwell)
    }

    // MARK: - Режим работы (официальное расписание)

    // Направление «прямое» = порядок stationIds на линии (как в источнике «Прямий»).
    func isForward(lineId: String, from: String, to: String) -> Bool? {
        guard let line = line(id: lineId),
              let a = line.stationIds.firstIndex(of: from),
              let b = line.stationIds.firstIndex(of: to), a != b else { return nil }
        return b > a
    }

    private static func headwayKey(lineId: String, hour: Int, isHoliday: Bool) -> String {
        "\(lineId)|\(hour)|\(isHoliday)"
    }

    // Интервал движения на момент date, сек. Внутри часа интервал меняется
    // линейно между табличными значениями на его начало и конец.
    // За пределами расписания берём ближайший известный час.
    func headwaySeconds(lineId: String, forward: Bool, at date: Date) -> Int? {
        guard let hours = headwayHourRange(lineId: lineId) else { return nil }
        let calendar = Self.kyivCalendar
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard let hour = parts.hour, let minute = parts.minute,
              let weekday = parts.weekday else { return nil }
        let isHoliday = weekday == 1 || weekday == 7      // неділя / субота
        let clamped = min(max(hour, hours.lowerBound), hours.upperBound)
        guard let row = headwayByKey[Self.headwayKey(lineId: lineId, hour: clamped,
                                                     isHoliday: isHoliday)] else { return nil }
        let start = forward ? row.forwardStart : row.backwardStart
        let end = forward ? row.forwardEnd : row.backwardEnd
        // До открытия — интервал на начало первого часа, после закрытия — на конец последнего.
        let fraction: Double = hour < clamped ? 0 : (hour > clamped ? 1 : Double(minute) / 60)
        return Int((Double(start) + (Double(end) - Double(start)) * fraction).rounded())
    }

    private func headwayHourRange(lineId: String) -> ClosedRange<Int>? {
        let hours = data.headways.filter { $0.lineId == lineId }.map(\.hour)
        guard let low = hours.min(), let high = hours.max() else { return nil }
        return low...high
    }

    // Среднее ожидание поезда: пассажир выходит на платформу в случайный момент
    // между поездами, поэтому ждёт в среднем половину интервала.
    func expectedWaitSeconds(lineId: String, forward: Bool, at date: Date) -> Int? {
        headwaySeconds(lineId: lineId, forward: forward, at: date).map { $0 / 2 }
    }

    // Перший/останній поїзд зі станції в бік станции toward, на календарный день date.
    func serviceWindow(fromId: String, towardId: String,
                       on date: Date = Date()) -> (first: Date, last: Date)? {
        guard let lineId = line(ofStation: fromId)?.id,
              let forward = isForward(lineId: lineId, from: fromId, to: towardId),
              let hours = serviceByStation[fromId] else { return nil }
        let first = forward ? hours.forwardFirst : hours.backwardFirst
        let last = forward ? hours.forwardLast : hours.backwardLast
        guard let first, let last,
              let firstDate = Self.kyivTime(secondsFromMidnight: first, on: date),
              let lastDate = Self.kyivTime(secondsFromMidnight: last, on: date)
        else { return nil }
        return (firstDate, lastDate)
    }

    private static func kyivTime(secondsFromMidnight seconds: Int, on date: Date) -> Date? {
        kyivCalendar.startOfDay(for: date).addingTimeInterval(TimeInterval(seconds))
    }
}
