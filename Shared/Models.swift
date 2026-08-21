import Foundation

struct Line: Codable, Identifiable, Hashable {
    let id: String                      // "m1", "m2", "m3"
    let nameUk: String
    let colorHex: String
    let stationIds: [String]            // в порядке следования
}

struct Station: Codable, Identifiable, Hashable {
    let id: String
    let nameUk: String
    let nameEn: String
    let isClosed: Bool                  // поезд проезжает без остановки
    let isSurface: Bool                 // наземная — GPS работает (см. GPS.md)
    let lat: Double
    let lon: Double

    var localizedName: String { appLanguage == .uk ? nameUk : nameEn }
}

struct Segment: Codable, Hashable {     // перегон между соседними станциями
    let fromId: String
    let toId: String
    let travelSeconds: Int              // ход
    let dwellSeconds: Int               // стоянка на toId
    // Рух ділянкою припинено (ремонт тунелю, пошкодження): маршрут через такий
    // перегін не будуємо. Опційне поле — старі дані декодуються без змін.
    let isSuspended: Bool?

    // Единый ключ направленного перегона для сид-данных и калибровки.
    static func key(_ from: String, _ to: String) -> String { "\(from)>\(to)" }
}

// Пересадочный узел: пеший переход между станциями разных линий.
struct Transfer: Codable, Hashable {
    let fromId: String
    let toId: String
    let walkSeconds: Int                // только ходьба; ожидание — по интервалу движения
}

// Интервал движения по официальному расписанию: на линию, час и тип дня.
// В источнике интервал задан диапазоном («7:30-5:30») — он плавно меняется
// внутри часа, поэтому храним оба конца и интерполируем.
struct Headway: Codable, Hashable {
    let lineId: String
    let hour: Int                       // 6…22, киевское время
    let isHoliday: Bool
    let forwardStart: Int               // сек; прямое направление = порядок stationIds
    let forwardEnd: Int
    let backwardStart: Int
    let backwardEnd: Int
}

// Перший/останній поїзд со станции в каждом направлении, сек от полуночи.
// nil — конечная: в эту сторону поезда отсюда не отправляются.
struct ServiceHours: Codable, Hashable {
    let stationId: String
    let forwardFirst: Int?
    let forwardLast: Int?
    let backwardFirst: Int?
    let backwardLast: Int?
}

struct MetroData: Codable {
    let lines: [Line]
    let stations: [Station]
    let segments: [Segment]
    let transfers: [Transfer]
    let headways: [Headway]
    let serviceHours: [ServiceHours]
}

// Одна станция маршрута с расчётными временами.
struct StopEvent: Codable, Hashable {
    let stationId: String
    let nameUk: String
    // Опциональное поле: поездка, сохранённая прошлой версией, декодируется как есть.
    let nameEn: String?
    let lineId: String                  // линия этапа — для цвета и акцента
    let arrival: Date
    let departure: Date
    let isStop: Bool                    // false для закрытых станций
    let isTransfer: Bool                // пеший переход на другую линию

    // Имена вшиты в событие, а не берутся из репозитория: виджет живёт
    // в своём бандле, где данных метро нет.
    var displayName: String { appLanguage == .uk ? nameUk : (nameEn ?? nameUk) }
}

struct ActiveTrip: Codable {
    let lineId: String                  // линия отправления
    let fromId: String
    let toId: String
    let startDate: Date
    let initialArrival: Date            // план на момент старта — для журнала
    var manualCorrections: Int
    // Из ручных коррекций — те, что «+1 зупинка»: поезд отстаёт от расчёта.
    // Опциональное поле: поездка, сохранённая прошлой версией, декодируется
    // без него, а не теряется целиком вместе с активной поездкой пассажира.
    var lateCorrections: Int?
    var gpsCorrections: Int
    var events: [StopEvent]             // [0] — станция отправления

    var destinationName: String { events.last?.displayName ?? "" }
    var arrivalDate: Date { events.last?.arrival ?? startDate }

    // Расчёт может опаздывать от реальности: после модельного прибытия поездка
    // живёт ещё 10 минут «на дотяг» — юзер продолжает ехать и жмёт +1,
    // остров и уведомления не убиваются по неуверенной модели.
    var expiryDate: Date { arrivalDate.addingTimeInterval(600) }

    // Момент остановки на последней промежуточной станции: «наступна — ваша».
    // Пересадка тоже считается: если она предпоследняя, поезд на новой линии
    // отходит именно оттуда — предупреждать на станции выхода было бы слишком рано.
    var alertDate: Date {
        events.dropLast().last(where: { $0.isStop || $0.isTransfer })?.arrival ?? startDate
    }

    var transferIndex: Int? { events.firstIndex(where: { $0.isTransfer }) }

    // Пассажир вышел на пересадочной станции и ещё не доехал до следующей.
    // Именно здесь расчёт наименее уверен: ожидание поезда известно только
    // в среднем — от 1.5 мин в час пик до 5.5 мин вечером. Окно намеренно
    // держится до следующей станции: повторный тап «Поїзд рушив» — такая же
    // законная поправка, как «+1 зупинка», и спасает того, кто шёл дольше плана.
    func isChangingLines(at now: Date) -> Bool {
        guard let index = transferIndex, index >= 1, index + 1 < events.count else { return false }
        return now >= events[index - 1].arrival && now < events[index + 1].arrival
    }

    // Модель считает, что посадка уже позади: подсказку надо менять с
    // «чекаєте поїзд?» на «ще не рушив? натисніть ще раз».
    func hasBoardedByModel(at now: Date) -> Bool {
        guard let index = transferIndex else { return false }
        return now >= events[index].arrival
    }

    func nextEventIndex(at now: Date) -> Int? {
        events.firstIndex(where: { $0.arrival > now })
    }

    // Станция, у которой поезд сейчас по модели (последняя достигнутая).
    func currentAnchorIndex(at now: Date) -> Int {
        (nextEventIndex(at: now) ?? events.count) - 1
    }

    func stopsRemaining(at now: Date) -> Int {
        events.filter { $0.isStop && $0.arrival > now }.count
    }

    func nextStop(at now: Date) -> StopEvent? {
        events.first(where: { $0.isStop && $0.arrival > now })
    }
}

struct RecentTrip: Codable, Hashable {
    let lineId: String
    let fromId: String
    let toId: String
}
