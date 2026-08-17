import CoreMotion
import Foundation

// Пишет сырой поток акселерометра 50 Гц в CSV. В MVP данные не используются —
// это размеченный датасет для будущей модели распознавания перегонов.
final class MotionRecorder {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var handle: FileHandle?
    private var buffer: [String] = []

    func start(fileURL: URL) {
        stop()
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
        write(line: "wall_ts,boot_ts,ax,ay,az")

        guard manager.isAccelerometerAvailable else { return }
        manager.accelerometerUpdateInterval = 1.0 / 50.0
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let wall = Date().timeIntervalSince1970
            let a = data.acceleration
            self.write(line: String(format: "%.4f,%.4f,%.5f,%.5f,%.5f",
                                    wall, data.timestamp, a.x, a.y, a.z))
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        queue.addOperation { [weak self] in
            self?.flush()
            try? self?.handle?.close()
            self?.handle = nil
        }
        queue.waitUntilAllOperationsAreFinished()
    }

    // Вызывается только на своей последовательной очереди либо до старта апдейтов.
    private func write(line: String) {
        buffer.append(line)
        if buffer.count >= 100 { flush() }
    }

    private func flush() {
        guard let handle, !buffer.isEmpty else { return }
        let chunk = buffer.joined(separator: "\n") + "\n"
        buffer.removeAll()
        try? handle.write(contentsOf: Data(chunk.utf8))
    }
}
