import SwiftUI
import UniformTypeIdentifiers
import ArbeitszeitKit

/// Stundenzettel eines Monats als CSV teilen oder speichern (wie MonthExportDialog in Android).
struct MonthExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var month: YearMonth
    @State private var shareURL: URL? = nil
    @State private var csvDocument: ExportDocument? = nil
    @State private var exporting = false
    @State private var message: String? = nil

    init(initialMonth: YearMonth) {
        _month = State(initialValue: initialMonth)
    }

    var body: some View {
        let summary = model.monthSummary(month)
        let hasData = summary.totalMinutes > 0

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Button {
                            month = month.minusMonths(1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline)
                                .frame(width: 40, height: 32)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Vorheriger Monat")

                        Text(verbatim: germanMonthName(month))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("export-month")

                        Button {
                            month = month.plusMonths(1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.headline)
                                .frame(width: 40, height: 32)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Nächster Monat")
                    }
                    Text(verbatim: MonthExportView.summaryText(summary))
                        .accessibilityIdentifier("export-summary")
                } footer: {
                    Text("CSV-Datei für Excel, Numbers oder Google Tabellen – mit Kalenderwoche, Beginn, Ende, Pause und Stunden pro Tag sowie der Monatssumme.")
                }

                Section {
                    if hasData, let url = shareURL {
                        ShareLink(item: url, subject: Text(verbatim: MonthExport.title(month: month))) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("export-share")
                    } else {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        csvDocument = ExportDocument(text: model.monthCSV(month))
                        exporting = true
                    } label: {
                        Label("Speichern", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!hasData)
                    .accessibilityIdentifier("export-save")
                }
            }
            .navigationTitle("Stundenzettel exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                    .accessibilityIdentifier("export-close")
                }
            }
            .task(id: month) {
                shareURL = model.exportFile(for: month)
            }
            .fileExporter(
                isPresented: $exporting,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: MonthExportView.baseName(month)
            ) { result in
                switch result {
                case .success:
                    message = "Stundenzettel gespeichert"
                case .failure(let error):
                    if !isUserCancellation(error) {
                        message = "Stundenzettel konnte nicht gespeichert werden"
                    }
                }
            }
            .messageBanner($message)
        }
        .presentationDetents([.medium, .large])
    }

    /// Zusammenfassung wie in Android, z. B. "67:30 h an 7 Arbeitstagen, dazu 20:00 h Urlaub/Krank/Feiertag (gesamt 87:30 h)".
    static func summaryText(_ summary: MonthExport.Summary) -> String {
        if summary.totalMinutes == 0 {
            return "Keine Einträge in diesem Monat."
        }
        let worked = "\(formatDuration(summary.workedMinutes)) h an \(summary.workDays) Arbeitstagen"
        if summary.absenceMinutes == 0 {
            return worked
        }
        return worked + ", dazu \(formatDuration(summary.absenceMinutes)) h Urlaub/Krank/Feiertag "
            + "(gesamt \(formatDuration(summary.totalMinutes)) h)"
    }

    /// Dateiname ohne ".csv" – die Endung ergänzt der Dateidialog.
    static func baseName(_ month: YearMonth) -> String {
        let name = MonthExport.fileName(month: month)
        return name.hasSuffix(".csv") ? String(name.dropLast(4)) : name
    }
}
