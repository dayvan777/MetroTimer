import CoreGraphics

// Авторська схема київського метро в каноні Бека: кути лише 45°/90°.
// Координати НЕ географічні і навмисно нічиї: ні схему КМДА, ні «Агентів
// змін» не копіюємо — розкладка зроблена з топології ліній заново.
// Правда даних лишається в kyiv_metro.json; тут — тільки де малювати.
enum MetroMapLayout {
    static let canvasSize = CGSize(width: 1040, height: 1180)

    // Куди тікає підпис від точки станції.
    enum LabelSide {
        case diag       // під 45° вгору-праворуч — для горизонтальних променів
        case right
        case left
        case below      // по центру під точкою — для тісного центрального вузла
        case above      // по центру над точкою
    }

    struct Spot {
        let x: CGFloat
        let y: CGFloat
        let label: LabelSide
    }

    static let spots: [String: Spot] = [
        // ── М1, захід → центр (горизонталь y=428, крок 44) ──
        "akademmistechko":          Spot(x: 80,  y: 428, label: .diag),
        "zhytomyrska":              Spot(x: 124, y: 428, label: .diag),
        "sviatoshyn":               Spot(x: 168, y: 428, label: .diag),
        "nyvky":                    Spot(x: 212, y: 428, label: .diag),
        "beresteiska":              Spot(x: 256, y: 428, label: .diag),
        "shuliavska":               Spot(x: 300, y: 428, label: .diag),
        "politekhnichnyi-instytut": Spot(x: 344, y: 428, label: .diag),
        "vokzalna":                 Spot(x: 388, y: 428, label: .diag),
        "universytet":              Spot(x: 432, y: 428, label: .diag),
        "teatralna":                Spot(x: 508, y: 428, label: .below),
        "khreshchatyk":             Spot(x: 628, y: 428, label: .above),
        // ── М1, міст через Дніпро (діагональ 45°, крок 48) і лівий берег ──
        "arsenalna":                Spot(x: 676, y: 476, label: .diag),
        "dnipro":                   Spot(x: 724, y: 524, label: .diag),
        "hidropark":                Spot(x: 772, y: 572, label: .diag),
        "livoberezhna":             Spot(x: 820, y: 620, label: .diag),
        "darnytsia":                Spot(x: 868, y: 620, label: .diag),
        "chernihivska":             Spot(x: 916, y: 620, label: .diag),
        "lisova":                   Spot(x: 964, y: 620, label: .diag),

        // ── М2, північна вертикаль (x=584, крок 48) ──
        "heroiv-dnipra":            Spot(x: 584, y: 48,  label: .right),
        "minska":                   Spot(x: 584, y: 96,  label: .right),
        "obolon":                   Spot(x: 584, y: 144, label: .right),
        "pochaina":                 Spot(x: 584, y: 192, label: .right),
        "tarasa-shevchenka":        Spot(x: 584, y: 240, label: .right),
        "kontraktova-ploshcha":     Spot(x: 584, y: 288, label: .right),
        "poshtova-ploshcha":        Spot(x: 584, y: 336, label: .right),
        "maidan-nezalezhnosti":     Spot(x: 584, y: 384, label: .right),
        "ploshcha-ukrainskykh-heroiv": Spot(x: 584, y: 456, label: .below),
        // ── М2, південна вертикаль (крок 48) ──
        "olimpiiska":               Spot(x: 584, y: 504, label: .left),
        "palats-ukraina":           Spot(x: 584, y: 552, label: .left),
        "lybidska":                 Spot(x: 584, y: 600, label: .left),
        "demiivska":                Spot(x: 584, y: 648, label: .left),
        "holosiivska":              Spot(x: 584, y: 696, label: .left),
        "vasylkivska":              Spot(x: 584, y: 744, label: .left),
        "vystavkovyi-tsentr":       Spot(x: 584, y: 792, label: .left),
        "ipodrom":                  Spot(x: 584, y: 840, label: .left),
        "teremky":                  Spot(x: 584, y: 888, label: .left),

        // ── М3, північно-західна діагональ 45° (крок 48) ──
        "syrets":                   Spot(x: 360, y: 192, label: .left),
        "dorohozhychi":             Spot(x: 408, y: 240, label: .left),
        "lukianivska":              Spot(x: 456, y: 288, label: .left),
        "zoloti-vorota":            Spot(x: 552, y: 384, label: .left),
        "palats-sportu":            Spot(x: 624, y: 456, label: .right),
        // ── М3, південно-східна діагональ (крок 48) і лівобережний хвіст ──
        "klovska":                  Spot(x: 672, y: 504, label: .left),
        "pecherska":                Spot(x: 720, y: 552, label: .left),
        "zvirynetska":              Spot(x: 768, y: 600, label: .left),
        "vydubychi":                Spot(x: 816, y: 648, label: .left),
        "slavutych":                Spot(x: 864, y: 696, label: .left),
        "osokorky":                 Spot(x: 912, y: 744, label: .right),
        "pozniaky":                 Spot(x: 912, y: 792, label: .right),
        "kharkivska":               Spot(x: 912, y: 840, label: .right),
        "vyrlytsia":                Spot(x: 912, y: 888, label: .right),
        "boryspilska":              Spot(x: 912, y: 936, label: .right),
        "chervonyi-khutir":         Spot(x: 912, y: 984, label: .right),
    ]

    static func point(_ id: String) -> CGPoint? {
        spots[id].map { CGPoint(x: $0.x, y: $0.y) }
    }

    // Дніпро: декоративна стрічка, що відділяє лівий берег. Проходить між
    // «Дніпро»–«Гідропарк» (міст М1) і «Славутич»–«Осокорки» (міст М3).
    static let riverStart = CGPoint(x: 752, y: 30)
    static let riverControl1 = CGPoint(x: 736, y: 430)
    static let riverControl2 = CGPoint(x: 905, y: 830)
    static let riverEnd = CGPoint(x: 800, y: 1160)
    static let riverWidth: CGFloat = 34
}
