import SwiftUI
import UIKit

// Экран активной поездки: крупный отсчёт, остановки, коррекция ±1, «Зупинити».
struct TripView: View {
    @EnvironmentObject private var engine: TripEngine
    @ObservedObject private var alertService = AlertService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Одноразовый каскад появления списка станций при открытии экрана.
    @State private var appeared = false
    @State private var showStopConfirm = false
    // Таймер растёт вместе с системным шрифтом, но не съедает экран.
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let trip = engine.trip {
                content(trip: trip, now: context.date)
            }
        }
    }

    private func content(trip: ActiveTrip, now: Date) -> some View {
        let stopsLeft = trip.stopsRemaining(at: now)
        let nextIndex = trip.nextEventIndex(at: now) ?? trip.events.count
        // Акцент — линия текущего этапа: до пересадки одна, после — другая.
        let currentLegLine = trip.events[min(nextIndex, trip.events.count - 1)].lineId
        let accent = Color.tripAccent(
            stopsRemaining: stopsLeft,
            lineColorHex: engine.repo.line(id: currentLegLine)?.colorHex ?? "#888888")

        return VStack(spacing: 0) {
            if alertService.state == .alert {
                AirAlertBanner(text: L10n.alertsActiveTrip)
            }
            if engine.notificationsDenied {
                notificationsBanner
            }
            header(trip: trip, now: now, stopsLeft: stopsLeft, accent: accent)
            if now < trip.arrivalDate {
                // Системный самоведущийся прогресс поездки — как таймер, без тикеров.
                ProgressView(timerInterval: min(trip.startDate, trip.arrivalDate)...trip.arrivalDate,
                             countsDown: false, label: {}, currentValueLabel: {})
                    .tint(accent)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
            stationList(trip: trip, nextIndex: nextIndex, accent: accent)
            controls(trip: trip, now: now, stopsLeft: stopsLeft, accent: accent)
        }
        .background(Color(hex: "#101114").ignoresSafeArea())
        // Коррекция ±1/GPS перестраивает events — плавно перекатываем времена и таймер;
        // смена nextIndex анимирует приглушение пройденной станции.
        .animation(.easeInOut(duration: 0.35), value: trip.events)
        .animation(.easeInOut(duration: 0.35), value: nextIndex)
        // Переход «едем ↔ мали прибути» — одним мягким кроссфейдом.
        .animation(.easeInOut(duration: 0.4), value: now < trip.arrivalDate)
        .animation(.easeInOut(duration: 0.3), value: engine.notificationsDenied)
        .animation(.easeInOut(duration: 0.3), value: trip.isChangingLines(at: now))
    }

    // Занимает своё место в потоке — заголовок поездки не перекрывается.
    private var notificationsBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.notifDenied)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(L10n.openSettings, destination: url)
                    .font(.caption.bold())
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.25)))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func header(trip: ActiveTrip, now: Date, stopsLeft: Int, accent: Color) -> some View {
        VStack(spacing: 6) {
            Text(trip.destinationName)
                .font(.title2.bold())
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            if now < trip.arrivalDate {
                Text(timerInterval: min(trip.startDate, trip.arrivalDate)...trip.arrivalDate,
                     pauseTime: nil, countsDown: true)
                    .font(.system(size: min(timerSize, 96), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(accent)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                // «Одна зупинка» — не только цветом: состояние названо словами.
                Text(stopsLeft == 1 ? L10n.lastStopAhead : L10n.stopsRemaining(stopsLeft))
                    .font(.headline)
                    .foregroundColor(stopsLeft == 1 ? .orange : .secondary)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(L10n.a11yStopsLeft(stopsLeft))
                if let next = trip.nextStop(at: now) {
                    Text(L10n.nextStationPrefix + next.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                }
            } else {
                // Модель считает, что приехали, — но модель может опаздывать.
                Text(L10n.arrived)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                Text(L10n.overdue(Self.timeFormatter.string(from: trip.arrivalDate)))
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(L10n.overdueHint)
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .modifier(BreathingOpacity())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private func stationList(trip: ActiveTrip, nextIndex: Int, accent: Color) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(trip.events.enumerated()), id: \.element.stationId) { index, event in
                        stationRow(
                            event: event, index: index, nextIndex: nextIndex, accent: accent,
                            walkMinutes: event.isTransfer && index > 0
                                ? max(1, Int(event.arrival.timeIntervalSince(trip.events[index - 1].departure) / 60))
                                : nil)
                            .id(event.stationId)
                    }
                }
                .padding(.horizontal)
            }
            .onAppear { appeared = true }
            .onChange(of: nextIndex) { newIndex in
                guard trip.events.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(trip.events[newIndex].stationId, anchor: .center)
                }
            }
        }
    }

    private func stationRow(event: StopEvent, index: Int, nextIndex: Int, accent: Color,
                            walkMinutes: Int?) -> some View {
        let passed = index < nextIndex
        let isNext = index == nextIndex
        let lineColor = Color(hex: engine.repo.line(id: event.lineId)?.colorHex ?? "#888888")
        return HStack {
            if isNext {
                PulsingDot(color: accent)
            } else {
                Circle()
                    .fill(passed ? Color.gray.opacity(0.4) : lineColor)
                    .frame(width: 10, height: 10)
            }
            if event.isTransfer {
                WalkIcon(active: isNext, color: passed ? .gray : lineColor)
                Text(L10n.transferRow(event.displayName, minutes: walkMinutes ?? 0))
                    .foregroundColor(passed ? .gray : .white)
                    .fontWeight(isNext ? .bold : .regular)
            } else {
                Text(event.displayName)
                    .foregroundColor(passed ? .gray : .white)
                    .fontWeight(isNext ? .bold : .regular)
                if !event.isStop {
                    Text(L10n.closedStation)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            Text(Self.timeFormatter.string(from: event.arrival))
                .font(.footnote.monospacedDigit())
                .foregroundColor(passed ? .gray : .secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.isTransfer
            ? L10n.transferRow(event.displayName, minutes: walkMinutes ?? 0) : event.displayName)
        .accessibilityValue(passed ? L10n.a11yPassed : (isNext ? L10n.a11yNext : ""))
        .opacity(appeared ? (passed ? 0.7 : 1) : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        // Каскад: строки въезжают одна за другой, хвост длинных маршрутов — разом.
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(min(Double(index) * 0.045, 0.5)), value: appeared)
    }

    // Коррекция читается как счётчик у самого числа зупинок — «−1/+1» без
    // подписи непонятны. «Зупинити» больше не самая крупная кнопка экрана.
    private func controls(trip: ActiveTrip, now: Date, stopsLeft: Int, accent: Color) -> some View {
        let arrived = now >= trip.arrivalDate
        return VStack(spacing: 14) {
            if trip.isChangingLines(at: now) {
                transferBoarding(accent: accent, boardedByModel: trip.hasBoardedByModel(at: now))
            }
            VStack(spacing: 6) {
                Text(L10n.correctionTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    stepperButton(systemName: "minus", delta: -1,
                                  hint: L10n.a11yMinusHint, disabled: arrived)
                    Text(arrived ? trip.destinationName : L10n.stopsRemaining(stopsLeft))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityHidden(true)
                    stepperButton(systemName: "plus", delta: 1,
                                  hint: L10n.a11yPlusHint, disabled: false)
                }
                .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            if arrived {
                // Прибытие — позитивное завершение, а не «деструктив».
                primaryButton(L10n.arrivedAction) { engine.stopByUser() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            } else {
                primaryButton(L10n.stopTrip) { showStopConfirm = true }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .padding()
        .confirmationDialog(L10n.stopConfirmTitle, isPresented: $showStopConfirm,
                            titleVisibility: .visible) {
            Button(L10n.stopConfirmAction, role: .destructive) { engine.stopByUser() }
            Button(L10n.stopConfirmKeep, role: .cancel) {}
        } message: {
            Text(L10n.stopConfirmBody)
        }
    }

    // Ожидание поезда после перехода известно только в среднем по расписанию
    // (1.5 мин у пік, до 5.5 хв ввечері). Тап у момент відправлення прибирає
    // цю невизначеність — той самий контракт, що й «Поїхали» на старті.
    private func transferBoarding(accent: Color, boardedByModel: Bool) -> some View {
        VStack(spacing: 6) {
            Text(boardedByModel ? L10n.transferWaitLate : L10n.transferWaitHint)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            primaryButton(L10n.transferBoarded) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await engine.boardedAfterTransfer() }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    private func stepperButton(systemName: String, delta: Int,
                               hint: String, disabled: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await engine.adjust(by: delta) }
        } label: {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 56, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(delta > 0 ? L10n.plusStop : L10n.minusStop)
        .accessibilityHint(hint)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// Иконка пересадки: шагает (пульсирует), пока переход — следующий этап.
private struct WalkIcon: View {
    let active: Bool
    let color: Color

    var body: some View {
        let icon = Image(systemName: "figure.walk")
            .font(.footnote)
            .foregroundColor(color)
        if #available(iOS 17.0, *), active {
            icon.symbolEffect(.pulse, options: .repeating)
        } else {
            icon
        }
    }
}

// Мягкое «дыхание» подсказки про опоздание модели.
private struct BreathingOpacity: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

// «Сонар» у следующей станции: расходящееся кольцо поверх точки.
private struct PulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.7), lineWidth: 2)
                .scaleEffect(pulsing ? 2.4 : 1)
                .opacity(pulsing ? 0 : 0.8)
            Circle()
                .fill(color)
        }
        .frame(width: 10, height: 10)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}
