import SwiftUI

// Экран калибровки: реальные замеры ходов и стоянок + запись акселерометра.
struct CalibrationView: View {
    @StateObject private var model = CalibrationViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !model.running {
                    setupSection
                } else {
                    runningSection
                }
                logSection
                exportSection
            }
            .navigationTitle(L10n.calibration)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.done) {
                        model.finish()
                        dismiss()
                    }
                }
            }
            .sheet(item: $model.exportPayload) { payload in
                ShareSheet(items: payload.urls)
            }
        }
    }

    private var setupSection: some View {
        Section {
            Picker(L10n.calibLine, selection: $model.lineId) {
                ForEach(MetroRepository.shared.lines) { line in
                    Text(line.id.uppercased()).tag(line.id)
                }
            }
            .pickerStyle(.segmented)
            Picker(L10n.calibDirection, selection: $model.directionForward) {
                Text(model.directionTitle.forward).tag(true)
                Text(model.directionTitle.backward).tag(false)
            }
            Picker(L10n.calibFrom, selection: $model.startStationId) {
                ForEach(model.startCandidates) { station in
                    Text(station.localizedName).tag(station.id)
                }
            }
            Button {
                model.start()
            } label: {
                Text(L10n.calibStart)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } footer: {
            Text(L10n.calibHint)
        }
    }

    private var runningSection: some View {
        Section {
            VStack(spacing: 12) {
                if !model.nextStationName.isEmpty {
                    Text(L10n.nextStationPrefix + model.nextStationName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Button {
                    model.pressStation()
                } label: {
                    Text(model.awaitingDeparture ? L10n.calibDeparted : L10n.calibStopped)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.awaitingDeparture ? .green : .blue)
                Button(L10n.calibFinish, role: .destructive) {
                    model.finish()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var logSection: some View {
        Section {
            ForEach(Array(model.log.enumerated()), id: \.offset) { _, entry in
                Text(entry).font(.footnote.monospacedDigit())
            }
        }
    }

    // Экспорт отдаёт трек поездки с координатами — что именно уходит с телефона
    // и сколько это весит, должно быть видно до нажатия, а не после.
    private var exportSection: some View {
        Section(L10n.calibExportTitle) {
            if model.exportItems.isEmpty {
                Text(L10n.calibExportEmpty)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.exportItems) { item in
                    Button {
                        if model.selectedExports.contains(item.id) {
                            model.selectedExports.remove(item.id)
                        } else {
                            model.selectedExports.insert(item.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: model.selectedExports.contains(item.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundColor(.primary)
                                Text(item.sizeText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityAddTraits(model.selectedExports.contains(item.id) ? [.isSelected] : [])
                }
                Button(L10n.calibExportSelected(model.selectedExportBytes)) { model.export() }
                    .disabled(model.running || model.selectedExports.isEmpty)
            }
        }
        .onAppear { model.refreshExportItems() }
        .onChange(of: model.running) { _ in model.refreshExportItems() }
    }
}

// Спека требует UIActivityViewController — оборачиваем для SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
