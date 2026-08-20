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
                    HStack(spacing: 5) {
                        if hasArrived(context) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(accent)
                                .accessibilityHidden(true)
                        } else {
                            Circle().fill(accent).frame(width: 9, height: 9)
                            stopsText(context)
                                .font(.title3.bold())
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // После прибытия отсчёт застыл бы на 0:00 — вместо этого молчим.
                    if !hasArrived(context) {
                        timerText(context)
                            .font(.title3.bold())
                            .foregroundColor(accent)
                            .frame(maxWidth: 64)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.destinationName)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(hasArrived(context)
                             ? L10n.activityArrived
                             : L10n.nextStationPrefix + context.state.nextStationName)
                            .font(.caption2)
                            .foregroundColor(hasArrived(context) ? accent : .secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        stopsProgress(context, tint: accent)
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
                                HStack(spacing: 24) {
                                    Button(intent: AdjustTripIntent(delta: -1)) {
                                        Text(L10n.islandMinus).font(.subheadline.bold())
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(accent)
                                    .accessibilityLabel(L10n.minusStop)
                                    .accessibilityHint(L10n.a11yMinusHint)
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
                HStack(spacing: 4) {
                    Image(systemName: hasArrived(context) ? "checkmark.circle.fill" : "tram.fill")
                        .font(.caption2)
                        .foregroundColor(accent)
                        .accessibilityHidden(true)
                    if !hasArrived(context) {
                        stopsText(context)
                            .font(.subheadline.bold())
                    }
                }
            } compactTrailing: {
                if !hasArrived(context) {
                    timerText(context)
                        .font(.subheadline.bold())
                        .foregroundColor(accent)
                        .frame(maxWidth: 46)
                }
            } minimal: {
                if hasArrived(context) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(accent)
                        .accessibilityLabel(L10n.activityArrived)
                } else {
                    stopsText(context)
                        .font(.subheadline.bold())
                        .foregroundColor(accent)
                }
            }
            .widgetURL(URL(string: "metrotimer://trip"))
            .keylineTint(accent)
        }
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

// Перекат цифр вниз при обновлении состояния — единый вид счётчиков.
private struct RollingDigits: ViewModifier {
    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
    }
}

private extension View {
    func rollingDigits() -> some View { modifier(RollingDigits()) }
}

private func stopsText(_ context: ActivityViewContext<MetroActivityAttributes>) -> some View {
    Text("\(context.state.stopsRemaining)")
        .rollingDigits()
        .accessibilityLabel(L10n.a11yStopsLeft(context.state.stopsRemaining))
}

// SwiftUI сам ведёт отсчёт — обновления от приложения не нужны.
private func timerText(_ context: ActivityViewContext<MetroActivityAttributes>) -> Text {
    let arrival = context.state.arrivalDate
    let start = min(Date(), arrival)
    return Text(timerInterval: start...arrival, pauseTime: nil, countsDown: true)
        .monospacedDigit()
}

// Сегментная полоса «схемы маршрута»: капсула = остановка, пройденные — в цвете
// линии. Обновляется вместе с состоянием (перекат numericText рядом).
private func stopsProgress(_ context: ActivityViewContext<MetroActivityAttributes>,
                           tint: Color) -> some View {
    let total = max(context.attributes.totalStops, 1)
    let passed = max(0, total - context.state.stopsRemaining)
    return HStack(spacing: 3) {
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

// Локскрин / баннер: та же информация в одну-две строки.
private struct LockScreenView: View {
    let context: ActivityViewContext<MetroActivityAttributes>

    var body: some View {
        let accent = lineTint(context)
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 10, height: 10)
                    Text(context.attributes.destinationName)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                if hasArrived(context) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(accent)
                        .accessibilityHidden(true)
                } else {
                    timerText(context)
                        .font(.title2.bold())
                        .foregroundColor(accent)
                        .frame(maxWidth: 96, alignment: .trailing)
                }
            }
            HStack {
                // «0 зупинок» і «0:00» читалися як поломка, а не як прибуття.
                Text(hasArrived(context)
                     ? L10n.activityArrived
                     : L10n.stopsRemaining(context.state.stopsRemaining))
                    .font(.subheadline)
                    .foregroundColor(hasArrived(context) ? accent : .secondary)
                    .rollingDigits()
                Spacer()
                if !hasArrived(context) {
                    Text(L10n.nextStationPrefix + context.state.nextStationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            stopsProgress(context, tint: accent)
            if #available(iOS 17.0, *), isChangingLines(context) {
                Button(intent: BoardedTransferIntent()) {
                    Text(L10n.transferBoarded)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .padding(14)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }
}
