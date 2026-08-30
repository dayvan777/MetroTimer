import Foundation

// Виходи зі станцій: дані © OpenStreetMap contributors (ODbL), збірка —
// Scripts/build_exits.py. Все офлайн: вулиці геокодовано на етапі збірки,
// застосунок лише читає готовий JSON із бандла.
struct StationExit: Codable, Hashable {
    let ref: String?            // офіційний номер виходу з табличок (як в OSM)
    let street: String?         // найближча іменована вулиця
    let alongM: Int             // метри вздовж осі платформи у «forward»-напрямку лінії
    let wheelchair: String?     // yes / no / limited — як в OSM
    let poi: String?            // орієнтир міського масштабу (вокзал, ринок, стадіон)

    // Далі за ~60 м від центру платформи — це вже перехід або окремий
    // вестибюль: підказка про вагони там радше збреше, ніж допоможе.
    static let carHintLimitM = 60
}

// Порада «в які вагони сідати», розгорнута відносно напрямку ЦІЄЇ поїздки.
enum CarPosition: Equatable {
    case first, middle, last

    init?(alongM: Int, travellingForward: Bool) {
        let along = travellingForward ? alongM : -alongM
        guard abs(along) <= StationExit.carHintLimitM else { return nil }
        // Голова поїзда — куди він їде: додатний along у напрямку руху.
        if along > 20 { self = .first }
        else if along < -20 { self = .last }
        else { self = .middle }
    }
}

// Рядок картки: кілька виходів з однаковою підказкою складаються в один —
// «Виходи 2–4 · проспект Бажана» замість трьох однакових рядків.
struct ExitRow: Equatable {
    let refs: [String]
    let label: String?          // орієнтир (якщо є) або вулиця
    let cars: CarPosition?
    let wheelchair: Bool

    static func build(from exits: [StationExit],
                      hintsAllowed: Bool,
                      travellingForward: Bool?) -> [ExitRow] {
        var rows: [ExitRow] = []
        for exit in exits {
            let cars: CarPosition? = {
                guard hintsAllowed, let forward = travellingForward else { return nil }
                return CarPosition(alongM: exit.alongM, travellingForward: forward)
            }()
            let label = exit.poi ?? exit.street
            let accessible = exit.wheelchair == "yes"
            if let i = rows.lastIndex(where: { $0.label == label && $0.cars == cars }) {
                let merged = rows[i]
                rows[i] = ExitRow(refs: merged.refs + [exit.ref].compactMap { $0 },
                                  label: label, cars: cars,
                                  wheelchair: merged.wheelchair || accessible)
            } else {
                rows.append(ExitRow(refs: [exit.ref].compactMap { $0 },
                                    label: label, cars: cars, wheelchair: accessible))
            }
        }
        return rows
    }
}

final class ExitStore {
    static let shared = ExitStore()

    private let byStation: [String: [StationExit]]

    private init() {
        guard let url = Bundle.main.url(forResource: "kyiv_exits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [StationExit]].self, from: data)
        else {
            // Відсутність довідника не має валити поїздку: функція просто зникає.
            byStation = [:]
            return
        }
        byStation = decoded
    }

    // Напрямок «попереду/у хвості» можна показувати, лише коли виходи станції
    // лежать ПО ОБИДВА боки від центру осі. Це доказ, що точки стоять над
    // платформою (мілке закладення). У глибоких станцій один наземний
    // вестибюль: усі виходи купкою з одного боку, і їхні знаки кажуть про
    // місце ескалатора на поверхні, а не про торець платформи під землею —
    // «Арсенальна» показала б «посередині», хоча вихід у неї в одному торці.
    func directionalHintsAllowed(for stationId: String) -> Bool {
        let along = (byStation[stationId] ?? []).map(\.alongM)
        guard let minA = along.min(), let maxA = along.max() else { return false }
        return minA <= -25 && maxA >= 25
    }

    // Виходи станції без дублів: у великих вестибюлів по кілька дверей одного
    // виходу — пасажиру потрібен список виходів, а не список дверей.
    func exits(for stationId: String) -> [StationExit] {
        var seen = Set<String>()
        return (byStation[stationId] ?? []).filter { exit in
            let key = "\(exit.ref ?? "?")|\(exit.street ?? "?")"
            return seen.insert(key).inserted
        }
    }
}
