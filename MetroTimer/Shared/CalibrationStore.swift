import Foundation

extension FileManager {
    // nil — файла нет или размер недоступен; вызывающему это одно и то же.
    func fileSize(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
    }
}

// Усреднённые замеры по направленному перегону, ключ Segment.key.
struct CalibrationRecord: Codable {
    var travelSeconds: Double?
    var travelSamples: Int = 0
    var dwellSeconds: Double?
    var dwellSamples: Int = 0
}

final class CalibrationStore {
    static let shared = CalibrationStore()

    private(set) var records: [String: CalibrationRecord]

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("calibration.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([String: CalibrationRecord].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func record(from: String, to: String) -> CalibrationRecord? {
        records[Segment.key(from, to)]
    }

    // Замеры не сохраняются на диск сами — вызывающий делает save() раз на действие.
    func recordTravel(from: String, to: String, seconds: TimeInterval) {
        var record = records[Segment.key(from, to)] ?? CalibrationRecord()
        Self.addSample(seconds, to: &record.travelSeconds, count: &record.travelSamples)
        records[Segment.key(from, to)] = record
    }

    func recordDwell(from: String, to: String, seconds: TimeInterval) {
        var record = records[Segment.key(from, to)] ?? CalibrationRecord()
        Self.addSample(seconds, to: &record.dwellSeconds, count: &record.dwellSamples)
        records[Segment.key(from, to)] = record
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
        }
    }
}
