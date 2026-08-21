import SwiftUI

// Журнал поездок: план против итога и счётчики коррекций — метрики полевого теста.
struct TripLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exportPayload: ExportPayload?

    private let entries = TripLogStore.shared.entries

    struct ExportPayload: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    Text(L10n.journalEmpty)
                        .foregroundColor(.secondary)
                } else {
                    List {
                        // Главная цифра журнала — сверху: ради неё он и ведётся.
                        Section {
                            if let median = TripLogStore.shared.medianErrorSeconds {
                                Text(L10n.journalAccuracy(
                                    median, trips: TripLogStore.shared.measuredTripCount))
                                    .font(.subheadline.weight(.semibold))
                            } else {
                                Text(L10n.journalAccuracyHint)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        ForEach(entries) { entry in
                            entryRow(entry)
                        }
                        Section {
                            Button(L10n.journalExport) {
                                exportPayload = ExportPayload(urls: [TripLogStore.fileURL])
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.journal)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
            .sheet(item: $exportPayload) { payload in
                ShareSheet(items: payload.urls)
            }
        }
    }

    private func entryRow(_ entry: TripLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(entry.fromName) → \(entry.toName)")
                    .font(.subheadline.bold())
                Spacer()
                Text(Self.outcomeLabel(entry))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(entry.finished
                        ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
            }
            Text(Self.dateFormatter.string(from: entry.date))
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Text("\(L10n.journalPlanned) \(Self.mmss(entry.plannedSeconds))")
                Text("\(L10n.journalActual) \(Self.mmss(entry.finalSeconds))")
                if entry.transfers > 0 {
                    Label("\(entry.transfers)", systemImage: "figure.walk")
                }
                if entry.manualCorrections + entry.gpsCorrections > 0 {
                    Text("±\(entry.manualCorrections) · GPS \(entry.gpsCorrections)")
                }
                // Ошибка известна только там, где пассажир подтвердил прибытие.
                if let error = entry.errorSeconds {
                    Text(L10n.signedSeconds(error))
                        .fontWeight(.semibold)
                        .foregroundColor(abs(error) <= 30 ? .green : .orange)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    // Старые записи знают только finished — для них подпись прежняя.
    private static func outcomeLabel(_ entry: TripLogEntry) -> String {
        switch entry.outcome {
        case .arrived: return L10n.journalArrived
        case .stopped: return L10n.journalStopped
        case .expired: return L10n.journalFinished
        case nil: return entry.finished ? L10n.journalFinished : L10n.journalStopped
        }
    }

    private static func mmss(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter
    }()
}
