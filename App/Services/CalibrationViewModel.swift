import Foundation
import SwiftUI

// Сессия калибровки: пользователь отмечает моменты «зупинився» / «рушив»,
// замеры усредняются в CalibrationStore, параллельно пишется акселерометр.
@MainActor
final class CalibrationViewModel: ObservableObject {

    @Published var lineId = "m1" {
        didSet { clampStartStation() }
    }
    @Published var directionForward = true {
        didSet { clampStartStation() }
    }
    @Published var startStationId = ""

    @Published private(set) var running = false
    @Published private(set) var awaitingDeparture = false   // поезд стоит, ждём «рушив»
    @Published private(set) var log: [String] = []
    @Published var exportPayload: ExportPayload?
    @Published private(set) var exportItems: [ExportItem] = []
    @Published var selectedExports: Set<String> = []

    struct ExportPayload: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    private let repo = MetroRepository.shared
    private let motion = MotionRecorder()
    private let location = LocationRecorder()
    private var eventsHandle: FileHandle?

    // Полная последовательность станций по направлению (включая закрытые).
    private var sequence: [Station] = []
    private var nextIndex = 1            // индекс станции, к которой едем
    private var lastDepartureAt = Date()
    private var stoppedAt = Date()
    private var lastStopIndex = 0        // индекс последней станции с остановкой

    init() {
        clampStartStation()
    }

    var line: Line? { repo.line(id: lineId) }

    var orderedStations: [Station] {
        guard let line else { return [] }
        let stations = repo.stations(of: line)
        return directionForward ? stations : stations.reversed()
    }

    // Стартовать можно с любой станции, кроме конечной по направлению.
    var startCandidates: [Station] {
        Array(orderedStations.dropLast())
    }

    var directionTitle: (forward: String, backward: String) {
        guard let line, let first = repo.station(id: line.stationIds.first ?? ""),
              let last = repo.station(id: line.stationIds.last ?? "") else {
            return ("→", "←")
        }
        return ("→ \(last.localizedName)", "→ \(first.localizedName)")
    }

    var nextStationName: String {
        guard running, nextIndex < sequence.count else { return "" }
        return sequence[nextIndex].localizedName
    }

    private func clampStartStation() {
        if !startCandidates.contains(where: { $0.id == startStationId }) {
            startStationId = startCandidates.first?.id ?? ""
        }
    }

    // MARK: - Сессия

    func start() {
        guard !running,
              let startIdx = orderedStations.firstIndex(where: { $0.id == startStationId })
        else { return }
        sequence = Array(orderedStations[startIdx...])
        guard sequence.count >= 2 else { return }

        let stamp = Self.sessionFormatter.string(from: Date())
        let dir = Self.calibrationDir.appendingPathComponent("session_\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Сессия — это трек поездки с координатами и временем. Ни в резервную
        // копию, ни в руки тому, кто нашёл выключенный телефон, он попадать не должен.
        FileManager.default.protectAsLocalOnly(Self.calibrationDir)
        FileManager.default.protectAsLocalOnly(dir)

        FileManager.default.createFile(atPath: dir.appendingPathComponent("events.csv").path, contents: nil)
        eventsHandle = try? FileHandle(forWritingTo: dir.appendingPathComponent("events.csv"))
        try? eventsHandle?.write(contentsOf: Data("wall_ts,event,from_id,to_id\n".utf8))

        motion.start(fileURL: dir.appendingPathComponent("motion.csv"))
        location.start(fileURL: dir.appendingPathComponent("location.csv"))
        for name in ["events.csv", "motion.csv", "location.csv"] {
            FileManager.default.protectAsLocalOnly(dir.appendingPathComponent(name))
        }

        nextIndex = 1
        lastStopIndex = 0
        lastDepartureAt = Date()
        running = true
        awaitingDeparture = false
        log = []
        writeEvent("start,\(sequence[0].id),\(sequence[1].id)")
        appendLog("\(L10n.calibStart): \(sequence[0].localizedName)")
    }

    // Большая кнопка: чередует «зупинився» → «рушив».
    func pressStation() {
        guard running else { return }
        awaitingDeparture ? markDeparted() : markStopped()
    }

    // Границы правдоподобия: дребезг кнопки не должен попадать в базу.
    private static let plausibleTravel: ClosedRange<TimeInterval> = 20...900
    private static let plausibleDwell: ClosedRange<TimeInterval> = 3...600

    private func markStopped() {
        // Закрытые станции поезд проезжает — фиксируем остановку на следующей открытой.
        while nextIndex < sequence.count, sequence[nextIndex].isClosed {
            nextIndex += 1
        }
        guard nextIndex < sequence.count else { finish(); return }

        let now = Date()
        let travel = now.timeIntervalSince(lastDepartureAt)
        if Self.plausibleTravel.contains(travel) {
            distributeTravel(travel, fromIndex: lastStopIndex, toIndex: nextIndex)
            CalibrationStore.shared.save()
            appendLog(L10n.calibLogTravel(sequence[nextIndex].localizedName, seconds: Int(travel), skipped: false))
        } else {
            appendLog(L10n.calibLogTravel(sequence[nextIndex].localizedName, seconds: Int(travel), skipped: true))
        }
        stoppedAt = now
        awaitingDeparture = true
        writeEvent("stop,\(sequence[lastStopIndex].id),\(sequence[nextIndex].id)")
    }

    private func markDeparted() {
        let now = Date()
        let dwell = now.timeIntervalSince(stoppedAt)
        let prev = sequence[nextIndex - 1]
        let current = sequence[nextIndex]
        if Self.plausibleDwell.contains(dwell) {
            CalibrationStore.shared.recordDwell(from: prev.id, to: current.id, seconds: dwell)
            CalibrationStore.shared.save()
            appendLog(L10n.calibLogDwell(current.localizedName, seconds: Int(dwell), skipped: false))
        } else {
            appendLog(L10n.calibLogDwell(current.localizedName, seconds: Int(dwell), skipped: true))
        }
        writeEvent("depart,\(prev.id),\(current.id)")

        lastStopIndex = nextIndex
        lastDepartureAt = now
        nextIndex += 1
        awaitingDeparture = false
        if nextIndex >= sequence.count { finish() }
    }

    // Ход между остановками может накрывать закрытую станцию (2 перегона):
    // делим замер пропорционально сид-временам, чтобы прежняя калибровка не влияла на делёж.
    private func distributeTravel(_ total: TimeInterval, fromIndex: Int, toIndex: Int) {
        let pairs = (fromIndex..<toIndex).map { (sequence[$0].id, sequence[$0 + 1].id) }
        guard !pairs.isEmpty else { return }
        let seeds = pairs.map { Double(repo.seedTiming(from: $0.0, to: $0.1).travel) }
        let seedTotal = seeds.reduce(0, +)
        for (pair, seed) in zip(pairs, seeds) {
            let share = seedTotal > 0 ? total * seed / seedTotal : total / Double(pairs.count)
            CalibrationStore.shared.recordTravel(from: pair.0, to: pair.1, seconds: share)
        }
    }

    func finish() {
        guard running else { return }
        writeEvent("end,,")
        motion.stop()
        location.stop()
        try? eventsHandle?.close()
        eventsHandle = nil
        running = false
        awaitingDeparture = false
        appendLog("Сесію збережено (перегонів у базі: \(CalibrationStore.shared.calibratedSegmentCount))")
    }

    // MARK: - Экспорт

    // Сессии калибровки — это трек поездки с координатами и акселерометром.
    // Отдавать их «все скопом и вслепую» неправильно: пользователь должен
    // видеть, что именно и какого размера покидает телефон.
    struct ExportItem: Identifiable, Hashable {
        let id: String
        let title: String
        let urls: [URL]
        let bytes: Int64

        var sizeText: String {
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
    }

    func refreshExportItems() {
        var items: [ExportItem] = []
        let manager = FileManager.default

        if let size = manager.fileSize(at: CalibrationStore.fileURL) {
            items.append(ExportItem(id: "store", title: L10n.calibExportTimes,
                                    urls: [CalibrationStore.fileURL], bytes: size))
        }
        let sessions = (try? manager.contentsOfDirectory(at: Self.calibrationDir,
                                                         includingPropertiesForKeys: nil)) ?? []
        for session in sessions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let files = (try? manager.contentsOfDirectory(at: session,
                                                          includingPropertiesForKeys: nil)) ?? []
            guard !files.isEmpty else { continue }
            let bytes = files.reduce(Int64(0)) { $0 + (manager.fileSize(at: $1) ?? 0) }
            items.append(ExportItem(id: session.lastPathComponent,
                                    title: Self.sessionTitle(session.lastPathComponent),
                                    urls: files.sorted(by: { $0.path < $1.path }), bytes: bytes))
        }

        exportItems = items
        // По умолчанию выбрано всё — прежнее поведение, но теперь видимое.
        selectedExports = Set(items.map(\.id))
    }

    var selectedExportBytes: Int64 {
        exportItems.filter { selectedExports.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    func export() {
        let urls = exportItems.filter { selectedExports.contains($0.id) }.flatMap(\.urls)
        guard !urls.isEmpty else { return }
        exportPayload = ExportPayload(urls: urls)
    }

    // "session_20260816_104233" → "16.08.2026, 10:42"
    private static func sessionTitle(_ folder: String) -> String {
        let stamp = folder.replacingOccurrences(of: "session_", with: "")
        guard let date = sessionFormatter.date(from: stamp) else { return folder }
        return sessionTitleFormatter.string(from: date)
    }

    private static let sessionTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Вспомогательное

    private func writeEvent(_ line: String) {
        let text = String(format: "%.3f,", Date().timeIntervalSince1970) + line
        try? eventsHandle?.write(contentsOf: Data((text + "\n").utf8))
    }

    private func appendLog(_ entry: String) {
        log.insert(entry, at: 0)
    }

    private static var calibrationDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Calibration", isDirectory: true)
    }

    private static let sessionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
