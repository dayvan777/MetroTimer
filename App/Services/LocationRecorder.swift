import CoreLocation
import Foundation

// Пишет все фиксы CoreLocation в CSV во время калибровочной поездки — включая
// подземные (по вышкам 4G и Wi-Fi-точкам, без спутников). Нужен, чтобы по
// реальным данным понять, какую точность даёт позиционирование в тоннелях
// и можно ли снапить план к подземным станциям. Только foreground.
final class LocationRecorder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var handle: FileHandle?

    override init() {
        super.init()
        manager.delegate = self
        // Максимум фиксов любого качества: важна статистика, не экономия батареи.
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func start(fileURL: URL) {
        stop()
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
        write("wall_ts,lat,lon,h_acc,v_acc,speed,course,fix_age")
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        try? handle?.close()
        handle = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            let coordinate = location.coordinate
            write(String(format: "%.3f,%.6f,%.6f,%.1f,%.1f,%.2f,%.1f,%.2f",
                         Date().timeIntervalSince1970, coordinate.latitude, coordinate.longitude,
                         location.horizontalAccuracy, location.verticalAccuracy,
                         location.speed, location.course,
                         Date().timeIntervalSince(location.timestamp)))
        }
    }

    // Актуальный колбэк: didChangeAuthorization(status:) объявлен устаревшим
    // с iOS 14, и статус берётся у менеджера, а не приходит параметром.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard handle != nil else { return }   // сессия уже закрыта — не будим GPS
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    private func write(_ line: String) {
        try? handle?.write(contentsOf: Data((line + "\n").utf8))
    }
}
