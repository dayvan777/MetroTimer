import SwiftUI

// Главный экран: линия → станція відправлення → станція призначення → «Поїхали».
struct SelectionView: View {
    @EnvironmentObject private var engine: TripEngine
    @ObservedObject private var alertService = AlertService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Карточка «Як це працює» — один раз на установку: момент старта решает всё.
    @AppStorage("onboardingShown") private var onboardingShown = false

    @State private var selectedLineId = "m1"
    @State private var fromId: String?
    @State private var toId: String?
    @State private var showRouteError = false
    @State private var showNotifExplain = false
    @State private var showCalibration = false
    @State private var showJournal = false
    @State private var showAbout = false
    @State private var showOnboarding = false
    // Направление слайда списка станций при переключении линии.
    @State private var slideEdge: Edge = .trailing

    private var repo: MetroRepository { engine.repo }
    private var selectedLine: Line? { repo.line(id: selectedLineId) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if alertService.state == .alert {
                    AirAlertBanner(text: L10n.alertsActive)
                } else if alertService.state == .unavailable {
                    // Мовчання читалося б як «тривоги немає» — кажемо прямо.
                    AirAlertBanner(text: L10n.alertsUnavailable, muted: true)
                }
                lineTabs
                stationList
            }
            .background(Color(hex: "#101114").ignoresSafeArea())
            .navigationTitle(L10n.appTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Банер тривоги стоїть одразу під панеллю — фіксуємо її фон,
            // інакше панель фарбується червоним разом із банером.
            .toolbarBackground(Color(hex: "#101114"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Служебные экраны — в одном меню: заголовок не прыгает, для
                    // пассажира на первом уровне остаётся только выбор маршрута.
                    Menu {
                        Button { showJournal = true } label: {
                            Label(L10n.journal, systemImage: "list.bullet.rectangle")
                        }
                        Button { showCalibration = true } label: {
                            Label(L10n.calibration, systemImage: "stopwatch")
                        }
                        Button { showAbout = true } label: {
                            Label(L10n.about, systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L10n.aboutMenu)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if fromId != nil || toId != nil {
                        Button(L10n.reset) {
                            animated {
                                fromId = nil
                                toId = nil
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .sheet(isPresented: $showCalibration) { CalibrationView() }
            .sheet(isPresented: $showJournal) { TripLogView() }
            .sheet(isPresented: $showAbout) { AboutView() }
            .sheet(isPresented: $showOnboarding) { OnboardingView() }
            .alert(L10n.routeError, isPresented: $showRouteError) {
                Button("OK", role: .cancel) {}
            } message: {
                // Причина одна на весь nil от планировщика, но пассажиру важна
                // именно эта: «маршрут не будується» без объяснения выглядит
                // как поломка приложения, а не как закрытая ділянка.
                if isRouteSuspended { Text(L10n.routeSuspended) }
            }
            // Ни одна ветка не оставляет пользователя без поездки: отказ от
            // сповіщень — тоже валидный выбор, а не тупик.
            .alert(L10n.notifExplainTitle, isPresented: $showNotifExplain) {
                Button(L10n.notifContinue) { startTrip() }
                Button(L10n.notifSkip) { startTrip(askForNotifications: false) }
            } message: {
                Text(L10n.notifExplainBody)
            }
            .onAppear {
                if !onboardingShown {
                    onboardingShown = true
                    showOnboarding = true
                }
                #if DEBUG
                // Предвыбор станций для скриншотов: -MTPreselectFrom <id> -MTPreselectTo <id>
                let defaults = UserDefaults.standard
                if let from = defaults.string(forKey: "MTPreselectFrom") {
                    defaults.removeObject(forKey: "MTPreselectFrom")
                    fromId = from
                    if let line = repo.line(ofStation: from) { selectedLineId = line.id }
                }
                if let to = defaults.string(forKey: "MTPreselectTo") {
                    defaults.removeObject(forKey: "MTPreselectTo")
                    toId = to
                }
                if defaults.string(forKey: "MTSkipOnboarding") != nil {
                    defaults.removeObject(forKey: "MTSkipOnboarding")
                    showOnboarding = false
                }
                #endif
            }
        }
    }

    // Уважает «Зменшення руху»: переходы остаются, пружины и слайды — нет.
    private func animated(_ body: () -> Void) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                   : .spring(response: 0.3, dampingFraction: 0.7), body)
    }

    // MARK: - Линии

    private var lineTabs: some View {
        HStack(spacing: 8) {
            ForEach(repo.lines) { line in
                let isSelected = selectedLineId == line.id
                Button {
                    if let oldIndex = repo.lines.firstIndex(where: { $0.id == selectedLineId }),
                       let newIndex = repo.lines.firstIndex(where: { $0.id == line.id }) {
                        slideEdge = newIndex >= oldIndex ? .trailing : .leading
                    }
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                               : .spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedLineId = line.id
                    }
                } label: {
                    Text(line.id.uppercased())
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: line.colorHex)
                                    .opacity(isSelected ? 1 : 0.22))
                        )
                        .foregroundColor(.white)
                        .scaleEffect(isSelected && !reduceMotion ? 1 : 0.94)
                        .shadow(color: isSelected ? Color(hex: line.colorHex).opacity(0.5) : .clear,
                                radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.a11yLine(line.id))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Станции

    private var stationList: some View {
        List {
            Section(sectionTitle) {
                if let line = selectedLine {
                    ForEach(repo.stations(of: line)) { station in
                        stationRow(station, line: line)
                            .listRowBackground(Color(hex: "#1A1C21"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Смена линии — новый список: въезжает со стороны нажатой вкладки.
        .id(selectedLineId)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: slideEdge).combined(with: .opacity),
            removal: .opacity))
    }

    // Заголовок не должен «застревать» на шаге, который уже пройден.
    private var sectionTitle: String {
        if fromId == nil { return L10n.pickOrigin }
        if toId == nil { return L10n.pickDestination }
        return L10n.pickReady
    }

    private func stationRow(_ station: Station, line: Line) -> some View {
        let marker: String? = fromId == station.id ? "A" : (toId == station.id ? "B" : nil)
        return Button {
            tapStation(station)
        } label: {
            HStack {
                Circle()
                    .fill(Color(hex: line.colorHex))
                    .frame(width: 10, height: 10)
                Text(station.localizedName)
                    .foregroundColor(station.isClosed ? .secondary : .primary)
                if station.isClosed {
                    Text(L10n.closedStation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let marker {
                    Text(marker)
                        .font(.headline)
                        .foregroundColor(.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .disabled(station.isClosed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(station.localizedName)
        .accessibilityValue(marker == "A" ? L10n.a11yOrigin
                            : marker == "B" ? L10n.a11yDestination
                            : (station.isClosed ? L10n.closedStation : ""))
    }

    private func tapStation(_ station: Station) {
        animated {
            if fromId == nil {
                fromId = station.id
            } else if fromId == station.id {
                fromId = nil
                toId = nil
            } else {
                // Станция другой линии — тоже валидная цель: планировщик построит пересадку.
                toId = station.id
            }
        }
    }

    // MARK: - Нижняя панель

    private var bottomPanel: some View {
        let canStart = fromId != nil && toId != nil
        return VStack(spacing: 10) {
            if canStart {
                routeSummary
                    .transition(.opacity)
            } else if !engine.recents.isEmpty {
                recentsRow
                    .transition(.opacity)
            }
            Button {
                requestStart()
            } label: {
                VStack(spacing: 2) {
                    Text(L10n.go)
                        .font(.title2.bold())
                    // Момент нажатия — единственная точка привязки всей модели.
                    if canStart {
                        Text(L10n.startHint)
                            .font(.caption)
                            .opacity(0.9)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)
            .scaleEffect(canStart || reduceMotion ? 1 : 0.97)
            .shadow(color: canStart ? Color.accentColor.opacity(0.45) : .clear,
                    radius: 14, y: 4)
            .accessibilityHint(canStart ? L10n.startHint : "")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.25), value: canStart)
        .animation(.easeInOut(duration: 0.25), value: engine.recents)
    }

    // Резюме маршрута: что именно построится и сколько ехать — до нажатия.
    private var routeSummary: some View {
        let plan = plannedPreview()
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.routePreview(repo.station(id: fromId ?? "")?.localizedName ?? "",
                                       to: repo.station(id: toId ?? "")?.localizedName ?? ""))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if plan == nil, isRouteSuspended {
                    Label(L10n.routeSuspended, systemImage: "exclamationmark.octagon")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let plan {
                    Text([L10n.routeMinutes(plan.minutes), plan.transfer.map(L10n.routeTransfer)]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let issue = plan.serviceIssue {
                        Label(Self.serviceText(issue), systemImage: Self.serviceIcon(issue))
                            .font(.caption2)
                            .foregroundColor(Self.serviceColor(issue))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if plan.hasSurface {
                        Label(L10n.surfaceAlertWarning, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer()
            Button {
                animated { swap(&fromId, &toId) }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.swapStations)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isRouteSuspended: Bool {
        guard let from = fromId, let to = toId else { return false }
        return TripPlanner.hasSuspendedSection(fromId: from, toId: to, repo: repo)
    }

    // Тот же планировщик, что и при старте: превью не расходится с фактом.
    private func plannedPreview() -> (minutes: Int, transfer: String?, hasSurface: Bool,
                                      serviceIssue: ServiceIssue?)? {
        #if DEBUG
        // Сдвиг «зараз» для проверки часов работы: -MTPreviewOffset <секунды>.
        let now = Date().addingTimeInterval(
            TimeInterval(UserDefaults.standard.integer(forKey: "MTPreviewOffset")))
        #else
        let now = Date()
        #endif
        guard let from = fromId, let to = toId,
              let trip = TripPlanner.plan(fromId: from, toId: to, start: now, repo: repo)
        else { return nil }
        let minutes = max(1, Int((trip.initialArrival.timeIntervalSince(trip.startDate) / 60).rounded()))
        let hasSurface = trip.events.contains { repo.station(id: $0.stationId)?.isSurface == true }
        return (minutes, trip.events.first(where: \.isTransfer)?.displayName, hasSurface,
                TripPlanner.serviceIssue(for: trip, repo: repo))
    }

    // Часы работы: предупреждаем, но не запрещаем — расписание может измениться,
    // а пассажир на перроне видит табло, которого у нас нет.
    private static func serviceText(_ issue: ServiceIssue) -> String {
        switch issue {
        case let .beforeFirst(station, time):
            return L10n.serviceFirstTrain(station, time: timeFormatter.string(from: time))
        case let .afterLast(station, time):
            return L10n.serviceMissedLast(station, time: timeFormatter.string(from: time))
        case let .lastSoon(station, time):
            return L10n.serviceLastSoon(station, time: timeFormatter.string(from: time))
        }
    }

    private static func serviceColor(_ issue: ServiceIssue) -> Color {
        if case .lastSoon = issue { return .secondary }
        return .orange
    }

    private static func serviceIcon(_ issue: ServiceIssue) -> String {
        if case .lastSoon = issue { return "clock" }
        return "exclamationmark.triangle"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = MetroRepository.kyivCalendar.timeZone
        return formatter
    }()

    private var recentsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.recents)
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(engine.recents, id: \.self) { recent in
                        recentChip(recent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Чип только подставляет станции: старт поездки — всегда осознанный тап «Поїхали».
    private func recentChip(_ recent: RecentTrip) -> some View {
        Button {
            animated {
                fromId = recent.fromId
                toId = recent.toId
                selectedLineId = recent.lineId
            }
        } label: {
            HStack(spacing: 4) {
                if let line = repo.line(id: recent.lineId) {
                    Circle().fill(Color(hex: line.colorHex)).frame(width: 8, height: 8)
                }
                Text("\(repo.station(id: recent.fromId)?.localizedName ?? "?") → \(repo.station(id: recent.toId)?.localizedName ?? "?")")
                    .font(.footnote)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.a11yRecentHint)
    }

    // MARK: - Старт

    // Перед первым запросом системного разрешения показываем объяснение зачем.
    private func requestStart() {
        Task {
            let status = await NotificationScheduler.shared.authorizationStatus()
            if status == .notDetermined {
                showNotifExplain = true
            } else {
                startTrip()
            }
        }
    }

    private func startTrip(askForNotifications: Bool = true) {
        guard let from = fromId, let to = toId else { return }
        Task {
            let started = await engine.start(fromId: from, toId: to,
                                             askForNotifications: askForNotifications)
            if !started {
                showRouteError = true
            }
        }
    }
}

// Одноразовая карточка первого запуска: три шага, главный — момент нажатия.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text(L10n.onboardingTitle)
                .font(.largeTitle.bold())
                .padding(.top, 40)
            VStack(alignment: .leading, spacing: 20) {
                step(1, L10n.onboardingStep1)
                step(2, L10n.onboardingStep2)
                step(3, L10n.onboardingStep3)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text(L10n.onboardingGotIt)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(Color(hex: "#101114").ignoresSafeArea())
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
