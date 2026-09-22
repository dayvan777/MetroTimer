import SwiftUI

// «Мій рік у метро»: картка року в стилі сайту «Табло» (LED-цифри, рядки як
// табло відправлень) і кнопка «Поділитися» — готова картинка 1080×1920 для
// сторіс. Усе рахується на телефоні з журналу; назовні йде лише картинка,
// яку людина відправляє сама.
struct YearView: View {
    @Environment(\.dismiss) private var dismiss

    private let stats: YearStats
    @State private var shareImage: Image?

    init(now: Date = Date()) {
        let year = MetroRepository.kyivCalendar.component(.year, from: now)
        stats = YearStats.compute(entries: TripLogStore.shared.entries, year: year)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if stats.isEnough {
                        YearCard(stats: stats)
                            .frame(width: YearCard.size.width, height: YearCard.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .overlay(RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.white.opacity(0.08)))
                            .accessibilityElement(children: .combine)
                        if let shareImage {
                            ShareLink(item: shareImage,
                                      preview: SharePreview(L10n.yearTitle(stats.year),
                                                            image: shareImage)) {
                                Label(L10n.yearShare, systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(YearCard.amber)
                            .foregroundColor(.black)
                        }
                    } else {
                        Text(L10n.yearEmpty)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                    }
                    Text(L10n.yearFooter)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .background(Color(hex: "#101114").ignoresSafeArea())
            .navigationTitle(L10n.yearMenu)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
            .task { renderShareImage() }
        }
    }

    // Картинка для сторіс: 360×640 точок × 3 = 1080×1920 пікселів.
    @MainActor
    private func renderShareImage() {
        guard stats.isEnough else { return }
        let renderer = ImageRenderer(content: YearCard(stats: stats)
            .frame(width: YearCard.size.width, height: YearCard.size.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        if let image = renderer.uiImage {
            shareImage = Image(uiImage: image)
        }
    }
}

// Сама картка. Кольори — ті самі, що на metrotimer.app: картинка в сторіс має
// впізнаватися як «той застосунок із табло».
struct YearCard: View {
    let stats: YearStats

    static let size = CGSize(width: 360, height: 640)
    static let amber = Color(hex: "#FFB627")
    private static let background = Color(hex: "#060607")
    private static let text = Color(hex: "#ECEBE6")
    private static let dim = Color(hex: "#9B9A94")
    private static let hairline = Color(hex: "#232326")

    private var repo: MetroRepository { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.yearTitle(stats.year).uppercased())
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(Self.amber)
                .padding(.bottom, 26)
            LEDNumber(value: "\(stats.trips)", size: 104)
            Text(L10n.yearTrips(stats.trips).uppercased())
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundColor(Self.dim)
                .padding(.bottom, 26)
            row(stats.minutes >= 120 ? L10n.yearHoursUnit : L10n.yearMinutesUnit,
                value: stats.minutes >= 120 ? "\(stats.minutes / 60)" : "\(stats.minutes)")
            row(L10n.yearStationsPassed, value: stats.stationsPassed.formatted())
            if let favorite = stats.favoriteStationId.flatMap(repo.station(id:)) {
                row(L10n.yearFavorite, value: favorite.localizedName)
            }
            if let longest = stats.longest,
               let from = repo.station(id: longest.fromId), let to = repo.station(id: longest.toId) {
                row(L10n.yearLongest,
                    value: "\(from.localizedName) → \(to.localizedName) · \(L10n.routeMinutes(longest.minutes))")
            }
            Spacer(minLength: 16)
            lineBar
                .padding(.bottom, 18)
            HStack {
                Text(L10n.appTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Self.text)
                Spacer()
                Text("metrotimer.app")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(Self.amber)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Self.background)
    }

    // Рядок як на табло відправлень: підпис зліва, значення справа, тонка лінія.
    private func row(_ label: String, value: String) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Self.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(Self.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Self.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 11)
        }
    }

    // Частки ліній кольорами ліній: червона, синя, зелена — як на схемі.
    private var lineBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.yearLines.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(Self.dim)
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(repo.lines) { line in
                        let share = stats.lineShares[line.id] ?? 0
                        if share > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: line.colorHex))
                                .frame(width: max(6, (proxy.size.width - 6) * share))
                        }
                    }
                }
            }
            .frame(height: 12)
            HStack(spacing: 14) {
                ForEach(repo.lines) { line in
                    let share = stats.lineShares[line.id] ?? 0
                    if share > 0 {
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: line.colorHex)).frame(width: 8, height: 8)
                            Text("\(line.id.uppercased()) \(Int((share * 100).rounded()))%")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Self.text)
                        }
                    }
                }
            }
        }
    }
}

// LED-цифри, як годинник над тунелем на сайті: тьмяна «підкладка» і яскраві
// точки поверх — маска з сітки кружечків перетворює шрифт на точкову матрицю.
private struct LEDNumber: View {
    let value: String
    let size: CGFloat

    var body: some View {
        let digits = Text(value)
            .font(.system(size: size, weight: .black, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        ZStack(alignment: .leading) {
            digits.foregroundColor(YearCard.amber.opacity(0.12))
            digits
                .foregroundColor(YearCard.amber)
                .mask(DotGrid(pitch: size / 14))
                .shadow(color: YearCard.amber.opacity(0.55), radius: 10)
        }
        .accessibilityLabel(value)
    }
}

private struct DotGrid: View {
    let pitch: CGFloat

    var body: some View {
        Canvas { context, size in
            let radius = pitch * 0.42
            var y = pitch / 2
            while y < size.height {
                var x = pitch / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                        width: radius * 2, height: radius * 2)),
                                 with: .color(.white))
                    x += pitch
                }
                y += pitch
            }
        }
    }
}
