import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct MetroTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        MetroActivityWidget()
    }
}

struct MetroActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MetroActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            let accent = lineTint(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // Кільце замість лічильника зупинок: воно заповнюється саме,
                    // за часом, а цифра застигала, поки застосунок спить (1.4).
                    if hasArrived(context) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(accent)
                            .padding(.leading, 4)
                            .accessibilityHidden(true)
                    } else {
                        TripRing(context: context, tint: accent, size: 34, lineWidth: 4)
                            .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // После прибытия отсчёт застыл бы на 0:00 — вместо этого молчим.
                    if !hasArrived(context) {
                        // Правий край острова вузький: «9:51» переносилося на два
                        // рядки. Один рядок, при потребі трохи дрібніше.
                        timerText(context)
                            .font(.title3.bold())
                            .foregroundColor(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.destinationName)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if hasArrived(context) {
                            Text(L10n.activityArrived)
                                .font(.caption2)
                                .foregroundColor(accent)
                        } else {
                            factsText(context)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        StationBar(context: context, tint: accent)
                        if #available(iOS 17.0, *) {
                            if isChangingLines(context) {
                                // Момент посадки — єдине, чого модель не знає.
                                // Один тап тут прибирає всю невизначеність.
                                Button(intent: BoardedTransferIntent()) {
                                    Text(L10n.transferBoarded)
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(accent)
                            } else {
                                HStack(spacing: 16) {
                                    // Після прибуття головна дія — «Я вийшов»; «+1»
                                    // лишається для тих, хто ще їде.
                                    if hasArrived(context) {
                                        Button(intent: ArrivedIntent()) {
                                            Text(L10n.activityGotOff).font(.subheadline.bold())
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(accent)
                                    } else {
                                        Button(intent: AdjustTripIntent(delta: -1)) {
                                            Text(L10n.islandMinus).font(.subheadline.bold())
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(accent)
                                        .accessibilityLabel(L10n.minusStop)
                                        .accessibilityHint(L10n.a11yMinusHint)
                                    }
                                    Button(intent: AdjustTripIntent(delta: 1)) {
                                        Text(L10n.islandPlus).font(.subheadline.bold())
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(accent)
                                    .accessibilityLabel(L10n.plusStop)
                                    .accessibilityHint(L10n.a11yPlusHint)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                if hasArrived(context) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(accent)
                        .accessibilityLabel(L10n.activityArrived)
                } else {
                    TripRing(context: context, tint: accent, size: 22, lineWidth: 3)
                }
            } compactTrailing: {
                if !hasArrived(context) {
                    timerText(context)
                        .font(.subheadline.bold())
                        .foregroundColor(accent)
                        .frame(maxWidth: 46)
                }
            } minimal: {
                // Коли грає музика, острів ділиться, і від нас лишається кружечок.
                // Раніше в ньому стояла цифра зупинок, яка застигала на весь шлях.
                if hasArrived(context) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(accent)
                        .accessibilityLabel(L10n.activityArrived)
                } else {
                    TripRing(context: context, tint: accent, size: 22, lineWidth: 3)
                }
            }
            .widgetURL(URL(string: "metrotimer://trip"))
            .keylineTint(accent)
        }
    }
}

// Кільце поїздки: заповнюється від старту до прибуття саме, як і відлік, —
// без жодного оновлення від застосунку. Усередині — поїзд кольору лінії.
private struct TripRing: View {
    let context: ActivityViewContext<MetroActivityAttributes>
    let tint: Color
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            if let start = context.attributes.startDate, start < context.state.arrivalDate {
                ProgressView(timerInterval: start...context.state.arrivalDate, countsDown: false,
                             label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.circular)
                    .tint(tint)
            } else {
                Circle().stroke(tint, lineWidth: lineWidth)
            }
            Image(systemName: "tram.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(tint)
        }
        .frame(width: size, height: size)
        // Назва станції виходу не старіє; число зупинок у фоні застигало б.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.attributes.destinationName)
    }
}

// Пасажир на пересадці й ще не підтвердив посадку.
private func isChangingLines(_ context: ActivityViewContext<MetroActivityAttributes>) -> Bool {
    context.state.isChangingLines == true
}

// Поездка доехала по модели: отсчёт и счётчик зупинок больше не несут смысла.
//
// Считаем по времени, а не только по пришедшему счётчику: пока приложение
// усыплено, обновить состояние некому, и stopsRemaining остаётся тем, каким
// его отправили при последнем взгляде на экран. arrivalDate же лежит в
// состоянии и сравнивается с «сейчас» прямо при отрисовке — поэтому в момент
// staleDate (то самое прибытие) система перерисует карточку, и она скажет
// «Прибули», а не застынет на «Ще 3 зупинки · 0:00».
private func hasArrived(_ context: ActivityViewContext<MetroActivityAttributes>) -> Bool {
    context.state.stopsRemaining == 0 || Date() >= context.state.arrivalDate
}

// Линия текущего этапа приходит в состоянии; attributes — запасной вариант
// (активности, созданные предыдущей версией приложения).
private func lineTint(_ context: ActivityViewContext<MetroActivityAttributes>) -> Color {
    Color.tripAccent(stopsRemaining: context.state.stopsRemaining,
                     lineColorHex: context.state.lineColorHex ?? context.attributes.lineColorHex)
}

// SwiftUI сам ведёт отсчёт — обновления от приложения не нужны.
private func timerText(_ context: ActivityViewContext<MetroActivityAttributes>) -> Text {
    let arrival = context.state.arrivalDate
    let start = min(Date(), arrival)
    return Text(timerInterval: start...arrival, pauseTime: nil, countsDown: true)
        .monospacedDigit()
}

// «Перед вашою: Хрещатик» — лише факти з розкладу. Раніше тут стояло
// «Наступна: X · станом на 11:53»: назву станції присилає застосунок, а він
// у фоні спить, і рядок показував минуле (головна скарга у відгуках). Назва
// передостанньої станції і час прибуття не старіють ніколи. Центр острова
// вузький, тож одне з двох: станція перед вашою, а без неї — прибуття.
private func factsText(_ context: ActivityViewContext<MetroActivityAttributes>) -> Text {
    guard let before = context.state.penultimateName else { return arrivalText(context) }
    return Text(L10n.activityBeforeYours(before))
}

// «прибуття 12:14» — факт із розкладу, який не старіє без оновлень.
private func arrivalText(_ context: ActivityViewContext<MetroActivityAttributes>) -> Text {
    Text(L10n.activityArrivesPrefix) + Text(context.state.arrivalDate, style: .time)
}

// Полоса прогресса ведётся ВРЕМЕНЕМ, а не счётчиком: SwiftUI сам двигает её
// от старта до прибытия без единого обновления от приложения — так же, как
// ведёт отсчёт. Поверх — риски станций (1.4): полоса наползает на них сама,
// и видно, сколько станций позади, даже когда приложение спит.
// Активности, созданные прошлой версией (без startDate), получают прежние капсулы.
private struct StationBar: View {
    let context: ActivityViewContext<MetroActivityAttributes>
    let tint: Color

    var body: some View {
        if let start = context.attributes.startDate, start < context.state.arrivalDate {
            ProgressView(timerInterval: start...context.state.arrivalDate, countsDown: false,
                         label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .tint(tint)
                .overlay(marks)
                .accessibilityHidden(true)
        } else {
            let total = max(context.attributes.totalStops, 1)
            let passed = max(0, total - context.state.stopsRemaining)
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < passed ? tint : Color.white.opacity(0.38))
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                }
            }
            // Декор: то же самое уже сказано счётчиком зупинок. Без этого VoiceOver
            // перечисляет два десятка безымянных фигур перед полезным текстом.
            .accessibilityHidden(true)
        }
    }

    // Риска — просвет цвета фона карточки: на заполненной части он читается
    // как граница перегона, на пустой — как станция впереди.
    private var marks: some View {
        GeometryReader { proxy in
            ForEach(Array((context.state.stationMarks ?? []).enumerated()), id: \.offset) { _, mark in
                Rectangle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 2, height: proxy.size.height + 2)
                    .position(x: proxy.size.width * mark, y: proxy.size.height / 2)
            }
        }
    }
}

// Локскрин / баннер. Усе, що тут рухається, рухає сама система (відлік, кільце,
// смуга): застосунок у фоні спить, і будь-яка цифра від нього застигла б.
// Тому текстом — лише факти з розкладу, що не старіють: станція перед вашою
// і час прибуття (1.4, головна скарга у відгуках — «застиглий» екран).
private struct LockScreenView: View {
    let context: ActivityViewContext<MetroActivityAttributes>

    var body: some View {
        let accent = lineTint(context)
        let arrived = hasArrived(context)
        VStack(spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                if arrived {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(accent)
                        .accessibilityHidden(true)
                } else {
                    TripRing(context: context, tint: accent, size: 32, lineWidth: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.destinationName)
                        .font(.headline)
                        .lineLimit(1)
                    if arrived {
                        // «0 зупинок» і «0:00» читалися як поломка, а не як прибуття.
                        Text(L10n.activityArrived)
                            .font(.caption)
                            .foregroundColor(accent)
                    } else if let before = context.state.penultimateName {
                        // Без часу: у вузькій колонці він обрізався до «21:…», а
                        // прибуття й так стоїть праворуч під відліком.
                        Text(L10n.activityBeforeYours(before))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 4)
                if !arrived {
                    VStack(alignment: .trailing, spacing: 1) {
                        timerText(context)
                            .font(.title2.bold())
                            .foregroundColor(accent)
                            .frame(maxWidth: 96, alignment: .trailing)
                        arrivalText(context)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            StationBar(context: context, tint: accent)
            if #available(iOS 17.0, *) {
                if isChangingLines(context) {
                    Button(intent: BoardedTransferIntent()) {
                        Text(L10n.transferBoarded)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                } else if arrived {
                    // Без цієї кнопки «Прибули» висіло годинами: «Я на місці»
                    // було тільки в застосунку, а телефон уже в кишені.
                    HStack(spacing: 10) {
                        Button(intent: ArrivedIntent()) {
                            Text(L10n.activityGotOff)
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        Button(intent: AdjustTripIntent(delta: 1)) {
                            Text(L10n.islandPlus).font(.subheadline.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(accent)
                        .accessibilityLabel(L10n.plusStop)
                        .accessibilityHint(L10n.a11yPlusHint)
                    }
                }
            }
        }
        .padding(14)
        // Фон карточки тёмный всегда, а экран блокировки следует теме системы: в светлой
        // .primary стал бы чёрным по чёрному. Тёмная схема приложения до виджета не доходит.
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }
}
