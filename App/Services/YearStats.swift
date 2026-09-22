import Foundation

// «Мій рік у метро»: підсумок року з журналу поїздок. Рахується лише на
// телефоні і нікуди не йде, доки людина сама не поділиться карткою, тож
// «нічого не збираємо» лишається правдою.
struct YearStats: Equatable {
    struct Trip: Equatable {
        let fromId: String
        let toId: String
        let minutes: Int
    }

    let year: Int
    let trips: Int
    let minutes: Int                    // сумарно в дорозі
    let stationsPassed: Int             // станцій за вікном, з проміжними
    let favoriteStationId: String?      // найчастіша станція призначення
    let longest: Trip?
    let lineShares: [String: Double]    // лінія → частка пройдених станцій
    let firstTrip: Date?

    // Картка з однієї-двох поїздок виглядала б як насмішка, а не підсумок.
    static let minimumTrips = 3

    var isEnough: Bool { trips >= Self.minimumTrips }

    static func compute(entries: [TripLogEntry], year: Int,
                        repo: MetroRepository = .shared) -> YearStats {
        let calendar = MetroRepository.kyivCalendar
        // Кинута поїздка — не поїздка. Доїхав за моделлю чи підтвердив — так.
        let rides = entries.filter {
            $0.finished && calendar.component(.year, from: $0.date) == year
        }
        var seconds = 0
        var passed = 0
        var perLine: [String: Int] = [:]
        var destinations: [String: Int] = [:]
        var longest: Trip?
        for ride in rides {
            // Записи до 1.4 знають лише назви (мовою того дня) — шукаємо за ними.
            guard let fromId = ride.fromId ?? repo.stationId(named: ride.fromName),
                  let toId = ride.toId ?? repo.stationId(named: ride.toName) else { continue }
            // Реальний час, де людина його підтвердила в застосунку; інакше — план.
            let rideSeconds = ride.errorSeconds != nil ? (ride.confirmedSeconds ?? ride.finalSeconds)
                                                       : ride.finalSeconds
            seconds += max(0, rideSeconds)
            destinations[toId, default: 0] += 1
            if let plan = TripPlanner.plan(fromId: fromId, toId: toId, start: ride.date, repo: repo) {
                for event in plan.events.dropFirst() where !event.isTransfer {
                    passed += 1
                    perLine[event.lineId, default: 0] += 1
                }
            }
            let minutes = Int((Double(rideSeconds) / 60).rounded())
            if minutes > (longest?.minutes ?? -1) {
                longest = Trip(fromId: fromId, toId: toId, minutes: minutes)
            }
        }
        let totalLine = perLine.values.reduce(0, +)
        // Нічия — за назвою: картка не має мінятися від перезапуску.
        let favorite = destinations.max {
            $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key
        }?.key
        return YearStats(
            year: year,
            trips: rides.count,
            minutes: Int((Double(seconds) / 60).rounded()),
            stationsPassed: passed,
            favoriteStationId: favorite,
            longest: longest,
            lineShares: totalLine > 0
                ? perLine.mapValues { Double($0) / Double(totalLine) } : [:],
            firstTrip: rides.map(\.date).min())
    }
}

extension MetroRepository {
    // Станція за назвою будь-якою з двох мов — для журналу, записаного до 1.4.
    func stationId(named name: String) -> String? {
        data.stations.first { $0.nameUk == name || $0.nameEn == name }?.id
    }
}
