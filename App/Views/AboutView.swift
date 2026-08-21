import SwiftUI

// «Про застосунок»: как пользоваться, дисклеймер, источники данных, приватность
// (полный текст политики офлайн), удаление локальных данных, контакт.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alerts = AlertService.shared
    @AppStorage(AlertService.enabledKey) private var alertsEnabled = false
    @State private var pendingDeletion: Deletion?
    @State private var journalCount = TripLogStore.shared.entries.count
    @State private var calibrationCount = CalibrationStore.shared.calibratedSegmentCount

    // Состояние проверки словами: «тривоги немає» и «не змогли перевірити» —
    // это разные вещи, и пассажир должен видеть разницу.
    private var alertsStatus: String {
        let time = alerts.updatedAt.map { Self.timeFormatter.string(from: $0) }
        switch alerts.state {
        case .alert: return L10n.alertsActive
        case .quiet: return time.map { "\(L10n.alertsQuiet) · \(L10n.alertsUpdated($0))" } ?? L10n.alertsQuiet
        case .unavailable: return L10n.alertsUnavailable
        case .unknown: return L10n.alertsUnknown
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private enum Deletion: Identifiable {
        case journal, calibration
        var id: Int { hashValue }
    }

    private static let contactEmail = "vladdomotsky@gmail.com"
    private static let osmCopyright = URL(string: "https://www.openstreetmap.org/copyright")!

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image("AboutIcon")
                            .resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.appTitle).font(.headline)
                            Text("\(L10n.aboutVersion) \(version)")
                                .font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    Text(L10n.aboutDisclaimer)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // fixedSize обязателен: List сам решает, сколько строк уместить,
                // и самый длинный из этих текстов (о приватности) обрывался
                // многоточием прямо посреди обещания «дані не покидають пристрій».
                Section(L10n.aboutHowTitle) {
                    Text(L10n.aboutHowBody)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(L10n.aboutDataTitle) {
                    Text(L10n.aboutDataBody)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(L10n.aboutOSMLink, destination: Self.osmCopyright)
                        .font(.subheadline)
                }

                Section {
                    Toggle(L10n.alertsToggle, isOn: Binding(
                        get: { alertsEnabled },
                        set: { alertsEnabled = $0; alerts.setEnabled($0) }))
                    if alertsEnabled {
                        Text(alertsStatus)
                            .font(.footnote)
                            .foregroundColor(alerts.state == .unavailable ? .orange : .secondary)
                    }
                } header: {
                    Text(L10n.alertsTitle)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.alertsToggleNote)
                        // Джерело неофіційне — на ньому не можна будувати рішення
                        // про безпеку, і сказати про це треба до вмикання.
                        Text(L10n.alertsSourceWarning)
                    }
                    .font(.footnote)
                }

                Section(L10n.aboutPrivacyTitle) {
                    Text(L10n.aboutPrivacyBody)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(L10n.aboutPrivacyFull) {
                        PrivacyPolicyView()
                    }
                }

                Section {
                    Button(role: .destructive) {
                        pendingDeletion = .journal
                    } label: {
                        Label("\(L10n.aboutDeleteJournal) (\(journalCount))", systemImage: "trash")
                    }
                    .disabled(journalCount == 0)
                    Button(role: .destructive) {
                        pendingDeletion = .calibration
                    } label: {
                        Label("\(L10n.aboutDeleteCalibration) (\(calibrationCount))", systemImage: "trash")
                    }
                    .disabled(calibrationCount == 0)
                }

                Section {
                    if let url = URL(string: "mailto:\(Self.contactEmail)") {
                        Link(destination: url) {
                            Label(L10n.aboutContact, systemImage: "envelope")
                        }
                    }
                }
            }
            .navigationTitle(L10n.about)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
            .confirmationDialog(L10n.aboutDeleteConfirm, isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ), titleVisibility: .visible) {
                Button(L10n.aboutDelete, role: .destructive) { performDeletion() }
                Button(L10n.cancel, role: .cancel) {}
            }
        }
    }

    private func performDeletion() {
        switch pendingDeletion {
        case .journal:
            TripLogStore.shared.clear()
            journalCount = 0
        case .calibration:
            CalibrationStore.shared.clearAll()
            calibrationCount = 0
        case nil:
            break
        }
        pendingDeletion = nil
    }
}

// Полный текст политики — офлайн, тот же, что опубликован по URL из App Store Connect.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(L10n.privacyPolicySections.enumerated()), id: \.offset) { _, section in
                    if !section.title.isEmpty {
                        Text(section.title).font(.headline)
                    }
                    Text(section.body).font(.subheadline)
                }
            }
            .padding()
        }
        .navigationTitle(L10n.aboutPrivacyFull)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Плашка тревоги — одинаковая на экране выбора и в поездке. Второй вид,
// приглушённый: источник не ответил, и мы честно не знаем, есть тревога или нет.
struct AirAlertBanner: View {
    let text: String
    var muted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: muted ? "wifi.exclamationmark" : "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(muted ? Color.gray.opacity(0.45) : Color.red.opacity(0.85))
    }
}
