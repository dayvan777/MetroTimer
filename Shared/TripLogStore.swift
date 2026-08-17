import Foundation

// Запись о завершённой поездке — метрики точности для полевого теста.
struct TripLogEntry: Codable, Identifiable {
    let id: UUID
    let date: Date                      // старт поездки
    let fromName: String
    let toName: String
    let plannedSeconds: Int             // план на момент старта
    let finalSeconds: Int               // план после всех коррекций
    let manualCorrections: Int
    let gpsCorrections: Int
    let transfers: Int
    let finished: Bool                  // доехал vs остановил вручную
}

final class TripLogStore {
    static let shared = TripLogStore()

    private(set) var entries: [TripLogEntry]

    // Журнал ведётся ради метрик точности: хвост старше пары сотен поездок
    // никому не нужен, а файл рос бы вечно. Обрезаем и при чтении — файл
    // мог распухнуть в предыдущей версии.
    static let maxEntries = 200

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trip_log.json")
    }

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? decoder.decode([TripLogEntry].self, from: data) {
            entries = Array(decoded.prefix(Self.maxEntries))
        } else {
            entries = []
        }
    }

    func append(trip: ActiveTrip, finished: Bool) {
        let entry = TripLogEntry(
            id: UUID(),
            date: trip.startDate,
            fromName: trip.events.first?.displayName ?? trip.fromId,
            toName: trip.destinationName,
            plannedSeconds: Int(trip.initialArrival.timeIntervalSince(trip.startDate)),
            finalSeconds: Int(trip.arrivalDate.timeIntervalSince(trip.startDate)),
            manualCorrections: trip.manualCorrections,
            gpsCorrections: trip.gpsCorrections,
            transfers: trip.events.filter(\.isTransfer).count,
            finished: finished)
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    // Удаление по требованию пользователя (экран «Про застосунок»).
    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: Self.fileURL, options: .atomic)
            FileManager.default.protectAsLocalOnly(Self.fileURL)
        }
    }
}
