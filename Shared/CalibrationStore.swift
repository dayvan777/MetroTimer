import Foundation

extension FileManager {
    // nil — файла нет или размер недоступен; вызывающему это одно и то же.
    func fileSize(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
    }

    // Всё, что пишет приложение, — это данные о поездках и трек с координатами.
    // Политика обещает, что они не покидают устройство, поэтому:
    // 1) шифруем строже стандартного (доступ только пока устройство разблокировано
    //    или файл уже открыт) — украденный выключенный телефон их не отдаст;
    // 2) исключаем из резервных копий iCloud/iTunes, иначе «залишається на вашому
    //    пристрої» было бы неправдой.
    func protectAsLocalOnly(_ url: URL) {
        try? setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen],
                           ofItemAtPath: url.path)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

// Усреднённые замеры по направленному перегону, ключ Segment.key.
struct CalibrationRecord: Codable, Equatable {
    var travelSeconds: Double?
    var travelSamples: Int = 0
    var dwellSeconds: Double?
    var dwellSamples: Int = 0

    var isEmpty: Bool { travelSeconds == nil && dwellSeconds == nil }

    // Замер за пределами правдоподобия — не замер, а мусор: выкидываем поле
    // целиком вместе со счётчиком проб, иначе среднее так и останется битым.
    func sanitized() -> CalibrationRecord {
        var record = self
        if let travel = travelSeconds, !CalibrationStore.plausibleTravel.contains(travel) {
            record.travelSeconds = nil
            record.travelSamples = 0
        }
        if let dwell = dwellSeconds, !CalibrationStore.plausibleDwell.contains(dwell) {
            record.dwellSeconds = nil
            record.dwellSamples = 0
        }
        return record
    }
}

final class CalibrationStore {
    static let shared = CalibrationStore()

    private(set) var records: [String: CalibrationRecord]

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("calibration.json")
    }

    // Границы правдоподобия замера перегона. Единственный источник истины:
    // ими проверяются и ручная калибровка, и пассивное обучение по GPS, и то,
    // что уже лежит на диске. Самый короткий реальный перегон в Киеве — 70 с,
    // самый длинный — 287 с; запас взят с обеих сторон.
    static let plausibleTravel: ClosedRange<TimeInterval> = 30...900
    static let plausibleDwell: ClosedRange<TimeInterval> = 3...600

    private init() {
        let decoded = (try? Data(contentsOf: Self.fileURL)).flatMap {
            try? JSONDecoder().decode([String: CalibrationRecord].self, from: $0)
        } ?? [:]
        // Файл писала в том числе предыдущая версия приложения, у которой этих
        // проверок не было. Доверять ему нельзя: перегон с ходом 0.2 с
        // (реальная находка в отладочном контейнере) навсегда съедает станцию
        // из отсчёта — молча, и пользователю нечем это заметить.
        records = decoded.compactMapValues { record in
            let clean = record.sanitized()
            return clean.isEmpty ? nil : clean
        }
        // Чистим файл сразу, а не только память: иначе мусор переживёт запуск.
        if records != decoded { save() }
    }

    func record(from: String, to: String) -> CalibrationRecord? {
        records[Segment.key(from, to)]
    }

    // Замеры не сохраняются на диск сами — вызывающий делает save() раз на действие.
    // Возвращает false, если замер отброшен как неправдоподобный: вызывающий
    // показывает это в журнале калибровки, а не молчит.
    @discardableResult
    func recordTravel(from: String, to: String, seconds: TimeInterval) -> Bool {
        guard Self.plausibleTravel.contains(seconds) else { return false }
        var record = records[Segment.key(from, to)] ?? CalibrationRecord()
        Self.addSample(seconds, to: &record.travelSeconds, count: &record.travelSamples)
        records[Segment.key(from, to)] = record
        return true
    }

    @discardableResult
    func recordDwell(from: String, to: String, seconds: TimeInterval) -> Bool {
        guard Self.plausibleDwell.contains(seconds) else { return false }
        var record = records[Segment.key(from, to)] ?? CalibrationRecord()
        Self.addSample(seconds, to: &record.dwellSeconds, count: &record.dwellSamples)
        records[Segment.key(from, to)] = record
        return true
    }

    private static func addSample(_ seconds: TimeInterval, to value: inout Double?, count: inout Int) {
        let sum = (value ?? 0) * Double(count) + seconds
        count += 1
        value = sum / Double(count)
    }

    var calibratedSegmentCount: Int { records.count }

    // Сырые сессии калибровки (events/motion/location CSV) лежат отдельно.
    static var sessionsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Calibration", isDirectory: true)
    }

    // Удаление по требованию пользователя: и усреднённые замеры, и сырые сессии.
    func clearAll() {
        records = [:]
        try? FileManager.default.removeItem(at: Self.fileURL)
        try? FileManager.default.removeItem(at: Self.sessionsDir)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: Self.fileURL, options: .atomic)
            FileManager.default.protectAsLocalOnly(Self.fileURL)
        }
    }
}
