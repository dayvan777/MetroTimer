import SwiftUI

// «Про застосунок»: как пользоваться, дисклеймер, источники данных, приватность
// (полный текст политики офлайн), удаление локальных данных, контакт.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: Deletion?
    @State private var journalCount = TripLogStore.shared.entries.count
    @State private var calibrationCount = CalibrationStore.shared.calibratedSegmentCount

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
                }

                Section(L10n.aboutHowTitle) {
                    Text(L10n.aboutHowBody).font(.subheadline)
                }

                Section(L10n.aboutDataTitle) {
                    Text(L10n.aboutDataBody).font(.subheadline)
                    Link(L10n.aboutOSMLink, destination: Self.osmCopyright)
                        .font(.subheadline)
                }

                Section(L10n.aboutPrivacyTitle) {
                    Text(L10n.aboutPrivacyBody).font(.subheadline)
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

// Плашка активной тревоги — одинаковая на экране выбора и в поездке.
struct AirAlertBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.85))
    }
}
