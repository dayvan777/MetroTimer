import Foundation

// Чем закончилась поездка. Раньше это был один Bool, и он врал в обе стороны:
// «Я на місці» писалось как «не доехал», а поездка, которую никто не трогал
// десять минут после расчётного прибытия, — как «доехал».
enum TripOutcome: String, Codable {
    case arrived    // пассажир сам подтвердил прибытие — единственная надёжная точка
    case stopped    // остановил, не доехав
    case expired    // модель доехала, приложение никто не открыл
}

// Запись о завершённой поездке — метрики точности для полевого теста.
// Поля после finished опциональны: журнал, написанный прошлой версией,
// должен читаться как есть, а не теряться целиком.
struct TripLogEntry: Codable, Identifiable {
    let id: UUID
    let date: Date                      // старт поездки
    let fromName: String
    let toName: String
    let plannedSeconds: Int             // план на момент старта
    let finalSeconds: Int               // план после всех коррекций
    let manualCorrections: Int
    // Из них «+1 зупинка» — то есть «поезд отстаёт от расчёта». Без разделения
    // счётчик отвечал на вопрос «часто ли пассажир поправлял», а нужен ответ
    // на «в какую сторону мы врём».
    let lateCorrections: Int?
    let gpsCorrections: Int
    let transfers: Int
    let finished: Bool                  // доехал vs остановил вручную
    let outcome: TripOutcome?
    // Секунды от старта до момента, когда пассажир подтвердил прибытие.
    // Главная метрика полевого теста: всё остальное — план против плана,
    // и если пассажир ничего не нажимал, оно не говорит вообще ничего.
    let confirmedSeconds: Int?
    // Прибытие подтверждено кнопкой «Я вийшов» на карточке экрана блокировки.
    // Её жмут уже на эскалаторе, так что момент нажатия — не момент прибытия:
    // сам факт «доехал» засчитываем, а ошибку расчёта по такой поездке — нет.
    let confirmedOnCard: Bool?
    // Станции идентификаторами, а не только именами: имена зависят от языка,
    // а «Мій рік у метро» считает любимую станцию и пройденные линии.
    let fromId: String?
    let toId: String?

    // Насколько модель разошлась с реальностью, секунды.
    // Плюс — пассажир доехал позже расчёта (отсчёт спешил).
    // Минус — раньше (отсчёт отставал; это опасная сторона: предупреждение
    // приходит после нужной станции).
    var errorSeconds: Int? {
        guard outcome == .arrived, confirmedOnCard != true, let confirmedSeconds else { return nil }
        return confirmedSeconds - finalSeconds
    }

    // Вся логика записи — здесь, отдельно от файла на диске: проверить её
    // тестом можно, не трогая журнал устройства.
    init(trip: ActiveTrip, outcome: TripOutcome, endedAt: Date, id: UUID = UUID(),
         confirmedOnCard: Bool = false) {
        self.id = id
        self.date = trip.startDate
        self.fromName = trip.events.first?.displayName ?? trip.fromId
        self.toName = trip.destinationName
        self.plannedSeconds = Int(trip.initialArrival.timeIntervalSince(trip.startDate))
        self.finalSeconds = Int(trip.arrivalDate.timeIntervalSince(trip.startDate))
        self.manualCorrections = trip.manualCorrections
        self.lateCorrections = trip.lateCorrections ?? 0
        self.gpsCorrections = trip.gpsCorrections
        self.transfers = trip.events.filter(\.isTransfer).count
        // «Доехал» — это подтверждённое прибытие и истёкшая по модели поездка;
        // брошенная на полпути таковой не считается.
        self.finished = outcome != .stopped
        self.outcome = outcome
        // Реальное время прибытия известно только когда пассажир его подтвердил.
        self.confirmedSeconds = outcome == .arrived
            ? Int(endedAt.timeIntervalSince(trip.startDate)) : nil
        self.confirmedOnCard = outcome == .arrived && confirmedOnCard ? true : nil
        self.fromId = trip.fromId
        self.toId = trip.toId
    }
}

final class TripLogStore {
    static let shared = TripLogStore()

    private(set) var entries: [TripLogEntry]

    // Журнал кормит метрики точности и «Мій рік у метро»: у ежедневного
    // пассажира за год набегает 500–700 поездок, 2000 — с запасом (~1 МБ).
    // Совсем без предела файл рос бы вечно. Обрезаем и при чтении.
    static let maxEntries = 2000

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip_log.json")
    }

    private let fileURL: URL
    // Файл закрыт защитой (телефон заблокирован): журнал в памяти пустой, на диск не
    // пишем. Записи, добавленные в это время, дождутся разблокировки в `entries`.
    private(set) var isLocked = false

    init(fileURL: URL = TripLogStore.fileURL) {
        self.fileURL = fileURL
        entries = []
        let read = FileManager.default.readProtected(fileURL)
        if case .locked = read { isLocked = true } else { entries = Self.decode(read) }
    }

    // Телефон разблокирован: к тому, что лежит на диске, добавляем записанное вслепую.
    func reloadIfLocked() {
        guard isLocked else { return }
        let read = FileManager.default.readProtected(fileURL)
        if case .locked = read { return }
        isLocked = false
        let pending = entries
        entries = Array((pending + Self.decode(read)).prefix(Self.maxEntries))
        if !pending.isEmpty { save() }
    }

    private static func decode(_ read: ProtectedRead) -> [TripLogEntry] {
        guard case .data(let data) = read else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([TripLogEntry].self, from: data)) ?? []
        return Array(decoded.prefix(maxEntries))
    }

    func append(trip: ActiveTrip, outcome: TripOutcome, at endedAt: Date = Date(),
                confirmedOnCard: Bool = false) {
        let entry = TripLogEntry(trip: trip, outcome: outcome, endedAt: endedAt,
                                 confirmedOnCard: confirmedOnCard)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    // Медиана ошибки по поездкам с подтверждённым прибытием — та самая цифра,
    // ради которой ведётся журнал. nil, пока подтверждённых поездок нет.
    var medianErrorSeconds: Int? { Self.medianError(of: entries) }

    var measuredTripCount: Int { entries.compactMap(\.errorSeconds).count }

    // Момент, коли просити оцінку не соромно: застосунок ДОВІВ саме цій людині,
    // що працює — кілька підтверджених прибуттів і медіана в межах порога.
    // Просити в усіх підряд — швидкий спосіб зібрати одну зірку від тих,
    // у кого відлік розійшовся.
    //
    // С 1.4 прибытие подтверждают и с карточки экрана блокировки — там ошибка не
    // измеряется (см. confirmedOnCard). Поэтому условие — три подтверждённых
    // прибытия, а медиана, если она есть, должна быть в пределах порога.
    var deservesReviewPrompt: Bool { Self.deservesReviewPrompt(entries) }

    static func deservesReviewPrompt(_ entries: [TripLogEntry]) -> Bool {
        guard entries.filter({ $0.outcome == .arrived }).count >= 3 else { return false }
        guard let median = medianError(of: entries) else { return true }
        return abs(median) <= 30
    }

    // Статикой, а не только свойством: так медиану проверяют тесты, не трогая
    // общий журнал устройства (ровно та ошибка, на которой уже обжигались).
    static func medianError(of entries: [TripLogEntry]) -> Int? {
        let errors = entries.compactMap(\.errorSeconds).sorted()
        guard !errors.isEmpty else { return nil }
        return errors[errors.count / 2]
    }

    // Удаление по требованию пользователя (экран «Про застосунок»).
    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard !isLocked else { return }
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
            FileManager.default.protectAsLocalOnly(fileURL)
        }
    }
}
