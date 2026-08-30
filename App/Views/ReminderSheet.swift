import SwiftUI
import UserNotifications

// sheet(item:) вимагає Identifiable; ідентичність маршруту — його пара станцій.
extension RecentTrip: Identifiable {
    public var id: String { "\(fromId)>\(toId)" }
}

// Налаштування нагадування для закріпленого маршруту: дні тижня + час.
// Живе на чипі (довгий тап → «Нагадування…»), а не в окремих налаштуваннях:
// річ має бути там, де про неї згадують.
struct ReminderSheet: View {
    let route: RecentTrip
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var engine: TripEngine

    @State private var weekdays: Set<Int>
    @State private var time: Date
    @State private var hadReminder: Bool
    @State private var permissionDenied = false

    init(route: RecentTrip) {
        self.route = route
        let existing = RouteStore.shared.book.reminder(for: route)
        _hadReminder = State(initialValue: existing != nil)
        // Пн–Пт як розумний старт: типовий сценарій — щоденна дорога на роботу.
        _weekdays = State(initialValue: existing?.weekdays ?? [2, 3, 4, 5, 6])
        var components = DateComponents()
        components.hour = existing?.hour ?? 8
        components.minute = existing?.minute ?? 15
        _time = State(initialValue: Calendar.current.date(from: components) ?? Date())
    }

    // Дні в порядку календаря користувача (в Україні тиждень від понеділка).
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func dayLabel(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 6) {
                        ForEach(orderedWeekdays, id: \.self) { day in
                            let isOn = weekdays.contains(day)
                            Button {
                                if isOn { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                Text(dayLabel(day))
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(
                                        Capsule().fill(isOn ? Color.accentColor
                                                            : Color.white.opacity(0.12)))
                                    .foregroundColor(isOn ? .black : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    DatePicker(L10n.reminderTime, selection: $time,
                               displayedComponents: .hourAndMinute)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.reminderFooter)
                        if permissionDenied {
                            Text(L10n.reminderNeedsPermission).foregroundColor(.orange)
                        }
                    }
                }

                if hadReminder {
                    Section {
                        Button(role: .destructive) {
                            RouteStore.shared.setReminder(nil, for: route)
                            ReminderService.shared.resync()
                            dismiss()
                        } label: {
                            Text(L10n.reminderRemove)
                        }
                    }
                }
            }
            .navigationTitle(routeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.reminderSave) { save() }
                        .disabled(weekdays.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var routeTitle: String {
        let repo = engine.repo
        let from = repo.station(id: route.fromId)?.localizedName ?? "?"
        let to = repo.station(id: route.toId)?.localizedName ?? "?"
        return "\(from) → \(to)"
    }

    private func save() {
        Task { @MainActor in
            // Без дозволу на сповіщення нагадування — порожня обіцянка;
            // просимо тим самим шляхом, що й сповіщення поїздки.
            guard await NotificationScheduler.shared.requestAuthorization() else {
                permissionDenied = true
                return
            }
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            let reminder = RouteReminder(weekdays: weekdays,
                                         hour: components.hour ?? 8,
                                         minute: components.minute ?? 15)
            RouteStore.shared.setReminder(reminder, for: route)
            ReminderService.shared.resync()
            dismiss()
        }
    }
}
