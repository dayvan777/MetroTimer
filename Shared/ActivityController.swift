import ActivityKit
import Foundation

@MainActor
final class ActivityController {
    static let shared = ActivityController()

    private var activity: Activity<MetroActivityAttributes>?
    private var lastPushedState: MetroActivityAttributes.ContentState?

    private init() {}

    // Момент, после которого наши цифры перестают быть достоверными.
    //
    // Пока приложение свёрнуто, iOS его усыпляет — обновлять активность
    // некому (для этого существуют пуши ActivityKit, а сервера у нас нет).
    // Значит счётчик зупинок и название следующей станции в острове живут
    // ровно до расчётного прибытия: дальше модель кончилась.
    //
    // Побочный и главный эффект: система гарантированно перерисовывает
    // карточку в этот момент — единственный шанс показать «Прибули»
    // вместо застывшего «Ще 3 зупинки · 0:00» у пассажира, который так
    // и не открыл приложение.
    private func staleDate(for trip: ActiveTrip) -> Date {
        trip.arrivalDate
    }

    // «Живі активності» можно выключить в Параметрах iOS одним тумблером.
    // Тогда ни острова, ни карточки на экране блокировки не будет вообще —
    // и без слов это читается как «приложение сломалось».
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // Возвращает false, если карточку создать не удалось: вызывающий обязан
    // сказать об этом пассажиру, а не молча остаться без главного экрана.
    @discardableResult
    func start(trip: ActiveTrip, line: Line) -> Bool {
        guard areActivitiesEnabled else { return false }
        endAllImmediately()

        let attributes = MetroActivityAttributes(destinationName: trip.destinationName,
                                                 lineColorHex: line.colorHex,
                                                 totalStops: trip.stopsRemaining(at: trip.startDate))
        let state = MetroActivityAttributes.ContentState(trip: trip, now: Date())
        lastPushedState = state
        if #available(iOS 16.2, *) {
            let content = ActivityContent(state: state, staleDate: staleDate(for: trip),
                                          relevanceScore: 100)
            activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        } else {
            activity = try? Activity.request(attributes: attributes, contentState: state, pushType: nil)
        }
        return activity != nil
    }

    // После перезапуска приложения подхватываем живую активность.
    func attachIfNeeded() {
        if activity == nil {
            activity = Activity<MetroActivityAttributes>.activities.first
        }
    }

    func update(trip: ActiveTrip, now: Date = Date()) async {
        attachIfNeeded()
        guard let activity else { return }
        let state = MetroActivityAttributes.ContentState(trip: trip, now: now)
        lastPushedState = state
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: staleDate(for: trip),
                                                  relevanceScore: 100))
        } else {
            await activity.update(using: state)
        }
    }

    // Тикер зовёт ежесекундно; пуш уходит только при смене состояния (прошли станцию).
    func updateIfChanged(trip: ActiveTrip, now: Date = Date()) {
        let state = MetroActivityAttributes.ContentState(trip: trip, now: now)
        guard state != lastPushedState else { return }
        Task { await update(trip: trip, now: now) }
    }

    // Штатное завершение — только по истечении грейса (модель + 10 минут),
    // карточка к этому моменту и так пережила прибытие: убираем сразу.
    func end(trip: ActiveTrip) async {
        attachIfNeeded()
        guard let activity else { return }
        let state = MetroActivityAttributes.ContentState(trip: trip, now: Date())
        let dismissal = ActivityUIDismissalPolicy.immediate
        if #available(iOS 16.2, *) {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: dismissal)
        } else {
            await activity.end(using: state, dismissalPolicy: dismissal)
        }
        self.activity = nil
    }

    func endAllImmediately() {
        let existing = Activity<MetroActivityAttributes>.activities
        guard !existing.isEmpty else { return }
        Task {
            for activity in existing {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
                }
            }
        }
        activity = nil
    }
}
