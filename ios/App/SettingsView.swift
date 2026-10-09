import SwiftUI
import UniformTypeIdentifiers
import ArbeitszeitKit

/// Einstellungen (wie SettingsScreen in Android) mit Sicherung und Wiederherstellung.
struct SettingsView: View {
    private enum Field: Hashable {
        case weekly, days, rule1After, rule1Break, rule2After, rule2Break
    }

    @EnvironmentObject private var model: AppModel
    /// Zurück zur Wochenansicht (nach Speichern und Wiederherstellen).
    let onDone: () -> Void

    @State private var form: SettingsForm
    @FocusState private var focus: Field?

    @State private var backupDocument: ExportDocument? = nil
    @State private var exportingBackup = false
    @State private var importingBackup = false
    @State private var pendingRestore: PendingRestore? = nil
    @State private var autoBackupFile: URL? = nil
    @State private var choosingAutoBackupFile = false

    init(settings: AppSettings, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _form = State(initialValue: SettingsForm(settings: settings))
    }

    var body: some View {
        Form {
            workSection
            breakSection
            if form.autoBreak {
                ruleSection(
                    title: "Stufe 1",
                    after: $form.rule1AfterText,
                    afterValid: form.rule1After != nil,
                    afterField: .rule1After,
                    breakText: $form.rule1BreakText,
                    breakValid: form.rule1Break != nil,
                    breakField: .rule1Break
                )
                ruleSection(
                    title: "Stufe 2",
                    after: $form.rule2AfterText,
                    afterValid: form.rule2After != nil,
                    afterField: .rule2After,
                    breakText: $form.rule2BreakText,
                    breakValid: form.rule2Break != nil,
                    breakField: .rule2Break
                )
                gradualSection
            }

            Section {
                Button(action: save) {
                    Text("Speichern")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!form.isValid)
                .accessibilityIdentifier("settings-save")
            }

            backupSection
            if !model.storage.isShared {
                Section {
                    Text("Die App-Gruppe ist nicht verfügbar (z. B. nach der Installation mit Sideloadly). Die App funktioniert normal, aber Widgets und Kontrollzentrum sehen die Daten der App nicht.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Widgets")
                }
            }
            noticeSection
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern", action: save)
                    .disabled(!form.isValid)
                    .accessibilityIdentifier("settings-save-toolbar")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    focus = nil
                }
            }
        }
        .onChange(of: form.daysText) { _, newValue in
            let filtered = filterDigits(newValue, maxLength: 1)
            if filtered != newValue {
                form.daysText = filtered
            }
        }
        .onChange(of: form.rule1BreakText) { _, newValue in
            let filtered = filterDigits(newValue, maxLength: 3)
            if filtered != newValue {
                form.rule1BreakText = filtered
            }
        }
        .onChange(of: form.rule2BreakText) { _, newValue in
            let filtered = filterDigits(newValue, maxLength: 3)
            if filtered != newValue {
                form.rule2BreakText = filtered
            }
        }
        .sheet(item: $pendingRestore) { pending in
            RestoreConfirmView(
                message: SettingsView.restoreMessage(pending.data),
                offerAutoBackup: !model.autoBackupStatus.enabled,
                onCancel: { pendingRestore = nil },
                onConfirm: { useForAutoBackup in
                    restore(pending, useForAutoBackup: useForAutoBackup)
                }
            )
        }
    }

    // MARK: Abschnitte

    private var workSection: some View {
        Section {
            LabeledContent("Wochenarbeitszeit (Std.)") {
                TextField("20", text: $form.weeklyText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(form.weeklyMinutes == nil ? Palette.error : Color.primary)
                    .focused($focus, equals: .weekly)
                    .accessibilityIdentifier("weekly-hours")
            }
            LabeledContent("Arbeitstage pro Woche") {
                TextField("2", text: $form.daysText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(form.workDays == nil ? Palette.error : Color.primary)
                    .focused($focus, equals: .days)
                    .accessibilityIdentifier("work-days")
            }
            Toggle(isOn: $form.weeklyHoursAreLimit) {
                TitleWithDescription(
                    title: "Wochenstunden sind Obergrenze",
                    description: "Zum Beispiel die 20-Stunden-Grenze für Werkstudenten. Die App zeigt, wie viel bis zur Grenze fehlt, und warnt, wenn sie überschritten ist. Aus: Mehrarbeit wird als Überstunden angezeigt."
                )
            }
        } header: {
            Text("Arbeitszeit")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: form.weeklyHint)
                    .foregroundStyle(form.weeklyMinutes == nil ? Palette.error : Color.secondary)
                if form.workDays == nil {
                    Text("Arbeitstage: bitte 1 bis 7 eingeben")
                        .foregroundStyle(Palette.error)
                }
                Text("Urlaub, Krankheit und Feiertage werden mit dem Tagessoll gutgeschrieben.")
            }
        }
    }

    private var breakSection: some View {
        Section {
            Toggle(isOn: $form.autoBreak) {
                TitleWithDescription(
                    title: "Pausen automatisch abziehen",
                    description: "Die gesetzliche Mindestpause wird abgezogen, auch wenn keine oder eine kürzere Pause eingetragen ist."
                )
            }
        } header: {
            Text("Pausen")
        }
    }

    private func ruleSection(
        title: String,
        after: Binding<String>,
        afterValid: Bool,
        afterField: Field,
        breakText: Binding<String>,
        breakValid: Bool,
        breakField: Field
    ) -> some View {
        Section {
            LabeledContent("Ab mehr als (Std.)") {
                TextField("6", text: after)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(afterValid ? Color.primary : Palette.error)
                    .focused($focus, equals: afterField)
            }
            LabeledContent("Pause (Min.)") {
                TextField("30", text: breakText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(breakValid ? Color.primary : Palette.error)
                    .focused($focus, equals: breakField)
            }
        } header: {
            Text(verbatim: title)
        }
    }

    private var gradualSection: some View {
        Section {
            Toggle(isOn: $form.gradualDeduction) {
                TitleWithDescription(
                    title: "Gestaffelt abziehen",
                    description: "Es wird nur so viel Pause abgezogen, dass die Arbeitszeit nicht unter die Schwelle fällt (z. B. 6:15 h anwesend → 6:00 h Arbeitszeit), wie es das Arbeitszeitgesetz vorsieht. Aus: Die volle Pause wird abgezogen, sobald die Anwesenheit die Schwelle überschreitet."
                )
            }
            Button("Gesetzliche Werte wiederherstellen (§ 4 ArbZG)") {
                form.restoreLegalBreakRules()
            }
        }
    }

    private var backupSection: some View {
        let status = model.autoBackupStatus
        return Section {
            Toggle(isOn: Binding(
                get: { model.autoBackupStatus.enabled },
                set: { on in
                    if on {
                        chooseAutoBackupFile()
                    } else {
                        model.disableAutoBackup()
                    }
                }
            )) {
                TitleWithDescription(
                    title: "Automatische Sicherung",
                    description: "Nach jeder Änderung wird eine Sicherungsdatei aktualisiert, z. B. in „Dateien“ oder iCloud Drive. Nach einer Neuinstallation einfach wiederherstellen."
                )
            }
            .accessibilityIdentifier("auto-backup")
            // Verschieben statt Exportieren: Nur dann behält die App den Zugriff auf die Datei.
            .fileMover(isPresented: $choosingAutoBackupFile, file: autoBackupFile) { result in
                switch result {
                case .success(let url):
                    if !model.enableAutoBackup(url) {
                        model.banner = AutoBackup.unreachableMessage
                    }
                case .failure(let error):
                    if !isUserCancellation(error) {
                        model.banner = "Backup konnte nicht gespeichert werden"
                    }
                }
            }

            if status.enabled {
                Text(verbatim: SettingsView.autoBackupText(status))
                    .font(.footnote)
                    .foregroundStyle(status.error != nil ? Palette.error : Palette.accent)
                    .accessibilityIdentifier("auto-backup-status")
                if status.error != nil {
                    Button("Neue Sicherungsdatei wählen", action: chooseAutoBackupFile)
                }
            }

            Button {
                backupDocument = ExportDocument(text: model.backupText())
                exportingBackup = true
            } label: {
                Label("Backup jetzt speichern", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("backup-save")
            .fileExporter(
                isPresented: $exportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: model.backupFileBaseName
            ) { result in
                switch result {
                case .success:
                    model.banner = "Backup gespeichert"
                case .failure(let error):
                    if !isUserCancellation(error) {
                        model.banner = "Backup konnte nicht gespeichert werden"
                    }
                }
            }

            Button {
                importingBackup = true
            } label: {
                Label("Backup wiederherstellen", systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier("backup-restore")
            .fileImporter(
                isPresented: $importingBackup,
                allowedContentTypes: [.json, .plainText, .data]
            ) { result in
                switch result {
                case .success(let url):
                    readBackup(from: url)
                case .failure(let error):
                    if !isUserCancellation(error) {
                        model.banner = "Datei konnte nicht gelesen werden"
                    }
                }
            }
        } header: {
            Text("Daten sichern")
        } footer: {
            Text("Deine Einträge bleiben bei Updates erhalten, solange die App nicht gelöscht wird. Speichere vor dem Löschen der App ein Backup, z. B. in „Dateien“ oder iCloud Drive. Änderungen über Widgets, Kontrollzentrum und Siri sichert die automatische Sicherung beim nächsten Öffnen der App. Sicherungen der Android-App lassen sich hier wiederherstellen und umgekehrt.")
        }
    }

    private var noticeSection: some View {
        Section {
            Text("Die App ist ein privates Hilfsmittel zum Erfassen der eigenen Arbeitszeit und keine Rechtsberatung. Pausenregeln (§ 4 ArbZG), Tageshöchstgrenze (§ 3 ArbZG) und 20-Stunden-Grenze sind vereinfacht umgesetzt. Verbindlich sind Arbeitsvertrag und Arbeitgeber. Alle Angaben ohne Gewähr.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            LabeledContent("Version", value: SettingsView.versionText)
        } header: {
            Text("Hinweis")
        }
    }

    // MARK: Aktionen

    private func save() {
        guard let newSettings = form.makeSettings(currentBreakRules: model.settings.breakRules) else { return }
        focus = nil
        model.updateSettings(newSettings)
        model.banner = "Einstellungen gespeichert"
        onDone()
    }

    /// Legt die Sicherungsdatei an und lässt den Nutzer ihren Platz wählen.
    private func chooseAutoBackupFile() {
        guard let file = model.prepareAutoBackupFile() else {
            model.banner = "Backup konnte nicht gespeichert werden"
            return
        }
        autoBackupFile = file
        choosingAutoBackupFile = true
    }

    private func readBackup(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let backup = try BackupFormat.parse(String(decoding: data, as: UTF8.self))
            // Erst fragen, wenn die Dateiauswahl ganz geschlossen ist.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                pendingRestore = PendingRestore(data: backup, url: url)
            }
        } catch let error as BackupError {
            model.banner = error.message
        } catch {
            model.banner = "Datei konnte nicht gelesen werden"
        }
    }

    private func restore(_ pending: PendingRestore, useForAutoBackup: Bool) {
        model.restore(pending.data)
        pendingRestore = nil
        if useForAutoBackup && !model.enableAutoBackup(pending.url) {
            model.banner = "Backup wiederhergestellt\n" + AutoBackup.unreachableMessage
        } else {
            model.banner = "Backup wiederhergestellt"
        }
        // Zurück zur Wochenansicht, damit keine alten Formularwerte stehen bleiben.
        onDone()
    }

    /// "Sicherung vom 30.09.2026, 14:55 mit 12 Einträgen. …" (wie Android)
    static func restoreMessage(_ data: BackupData) -> String {
        var created = ""
        if let createdAt = data.createdAt {
            created = " vom " + formatDateTime(createdAt)
        }
        return "Sicherung\(created) mit \(data.entries.count) Einträgen. Einträge für dieselben Tage werden "
            + "überschrieben, alle anderen bleiben erhalten. Die Einstellungen werden übernommen."
    }

    /// "Zuletzt gesichert: 30.09.2026, 14:55", die Fehlermeldung oder "Wird gesichert …" (wie Android).
    static func autoBackupText(_ status: AutoBackupStatus) -> String {
        if let error = status.error {
            return error
        }
        if let lastSuccess = status.lastSuccess {
            return "Zuletzt gesichert: " + formatDateTime(lastSuccess)
        }
        return "Wird gesichert \u{2026}"
    }

    /// "30.09.2026, 14:55"
    private static func formatDateTime(_ dateTime: LocalDateTime) -> String {
        return formatLongDate(dateTime.date) + ", " + formatTime(dateTime.time)
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

/// Gelesene Sicherung, die noch bestätigt werden muss, mit der Datei, aus der sie stammt.
private struct PendingRestore: Identifiable {
    let id = UUID()
    let data: BackupData
    let url: URL
}

/// Rückfrage vor dem Wiederherstellen (wie RestoreDialog in Android). Ist die automatische Sicherung
/// noch aus, kann die gewählte Datei gleich dafür verwendet werden.
private struct RestoreConfirmView: View {
    let message: String
    let offerAutoBackup: Bool
    let onCancel: () -> Void
    let onConfirm: (_ useForAutoBackup: Bool) -> Void

    @State private var useForAutoBackup = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: message)
                        .fixedSize(horizontal: false, vertical: true)
                    if offerAutoBackup {
                        Toggle("Diese Datei für die automatische Sicherung verwenden", isOn: $useForAutoBackup)
                            .accessibilityIdentifier("restore-auto-backup")
                    }
                }
            }
            .navigationTitle("Backup wiederherstellen?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Wiederherstellen") {
                        onConfirm(offerAutoBackup && useForAutoBackup)
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("restore-confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
