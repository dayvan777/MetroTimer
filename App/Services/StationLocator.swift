import CoreLocation

// «Ви біля станції»: один фікс локації при відкритому головному екрані, снап
// до найближчої станції — і чип, що підставляє станцію відправлення одним
// тапом. Прибирає перший крок сценарію: людина на підході до метро відкриває
// застосунок, а станція вже вгадана.
//
// Межі свідомо вузькі: жодного фону; дозвіл просить картка після першої
// поїздки або нагадування на станції (поїздка сама більше не питає, 1.4);
// фікс не зберігається і нікуди не йде.
// Автостарту поїздки тут немає і не буде: вхід у метро ≠ намір їхати (GPS.md).
@MainActor
final class StationLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = StationLocator()

    // Найближча станція останнього фікса; nil — нема дозволу, фікса або станції поруч.
    @Published private(set) var nearbyStation: Station?

    enum Tuning {
        // Радіус снапу — станційний крок, трохи ширший за GPS-коридор (400 м):
        // чип — підказка, а не факт, ціна помилки — один зайвий погляд.
        static let snapMeters: CLLocationDistance = 450
        // Фікси гірші за це — це вже сота, а не місце: в центрі станції стоять
        // за 300–700 м, і «сота» радісно підкаже сусідню. Краще промовчати.
        static let accuracyMeters: CLLocationDistance = 300
    }

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // Дозволу ще не питали — можна запропонувати (після першої поїздки, 1.4).
    var canAskPermission: Bool { manager.authorizationStatus == .notDetermined }

    // Людина сама натиснула «Дозволити» в картці на головному екрані.
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // Викликати з появою головного екрана. Без дозволу — мовчить.
    func refresh() {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.requestLocation()
    }

    // Чиста частина: найближча станція в радіусі снапу. Закриті станції не
    // пропонуються — сісти на поїзд там не можна.
    nonisolated static func snap(lat: Double, lon: Double, repo: MetroRepository) -> Station? {
        let here = CLLocation(latitude: lat, longitude: lon)
        var best: (station: Station, meters: CLLocationDistance)?
        for line in repo.lines {
            for id in line.stationIds {
                guard let station = repo.station(id: id), !station.isClosed else { continue }
                let meters = here.distance(from: CLLocation(latitude: station.lat,
                                                            longitude: station.lon))
                if meters <= Tuning.snapMeters, meters < (best?.meters ?? .infinity) {
                    best = (station, meters)
                }
            }
        }
        return best?.station
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last,
              fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= Tuning.accuracyMeters else { return }
        let lat = fix.coordinate.latitude
        let lon = fix.coordinate.longitude
        Task { @MainActor in
            nearbyStation = Self.snap(lat: lat, lon: lon, repo: MetroRepository.shared)
        }
    }

    // Відповідь на запит із картки: одразу шукаємо станцію, щоб людина
    // побачила, навіщо дала дозвіл.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Тиша: підказка опційна, головний екран працює і без неї.
    }
}
