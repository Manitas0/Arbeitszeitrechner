import Foundation
import Combine
import ArbeitszeitKit

/// Zustand der App: Einträge, Einstellungen und die angezeigte Woche (wie MainViewModel in Android).
/// Alle Änderungen gehen sofort in den gemeinsamen Speicher, damit Widgets und Kontrollzentrum
/// denselben Stand sehen.
final class AppModel: ObservableObject {
    @Published private(set) var entries: [LocalDate: DayEntry] = [:]
    @Published private(set) var settings = AppSettings()
    /// "Jetzt" für die laufende Zeit von heute; wird regelmäßig aktualisiert.
    @Published private(set) var now: LocalDateTime
    @Published private(set) var weekStart: LocalDate
    /// Kurze Meldung unten am Bildschirmrand (wie ein Toast unter Android).
    @Published var banner: String? = nil
    @Published private(set) var autoBackupStatus = AutoBackupStatus()

    let storage: WorkStorage
    private let autoBackup: AutoBackup

    init(storage: WorkStorage = WorkStorage()) {
        let current = AppTime.now()
        if storage.isDemo {
            DemoData.install(storage: storage, today: current.date, withEntries: LaunchOptions.demoData)
        }
        self.storage = storage
        self.autoBackup = AutoBackup(storage: storage)
        self.now = current
        self.weekStart = WorkCalculator.weekStartOf(current.date)
        self.entries = storage.loadEntries()
        self.settings = storage.loadSettings()
        // Änderungen aus Widgets oder Siri, während die App nicht lief.
        runAutoBackup()
    }

    var today: LocalDate {
        return now.date
    }

    var isCurrentWeek: Bool {
        return weekStart == WorkCalculator.weekStartOf(today)
    }

    /// Die angezeigte Woche inklusive der laufenden Zeit von heute.
    var weekSummary: WeekSummary {
        return WorkCalculator.summarizeWeek(weekStart: weekStart, entries: entries, settings: settings, now: now)
    }

    func entry(for date: LocalDate) -> DayEntry {
        return entries[date] ?? DayEntry(date: date)
    }

    /// Daten neu laden, z. B. nachdem per Widget, Kontrollzentrum oder Siri gestempelt wurde.
    func reload() {
        entries = storage.loadEntries()
        settings = storage.loadSettings()
        updateNow(AppTime.now())
        runAutoBackup()
    }

    func tick() {
        updateNow(AppTime.now())
    }

    /// Neue Uhrzeit. Zeigte die App die bis dahin aktuelle Woche, springt sie nach einem Wochenwechsel
    /// (z. B. am Montag aus dem Hintergrund geholt) mit; bewusst geblätterte Wochen bleiben stehen.
    private func updateNow(_ newNow: LocalDateTime) {
        let newWeekStart = WorkCalculator.weekStartOf(newNow.date)
        if weekStart == WorkCalculator.weekStartOf(now.date) && weekStart != newWeekStart {
            weekStart = newWeekStart
        }
        now = newNow
    }

    func save(_ entry: DayEntry) {
        storage.saveEntry(entry)
        entries = storage.loadEntries()
        runAutoBackup()
    }

    func delete(_ date: LocalDate) {
        storage.deleteEntry(date)
        entries = storage.loadEntries()
        runAutoBackup()
    }

    func updateSettings(_ newSettings: AppSettings) {
        storage.saveSettings(newSettings)
        settings = newSettings
        runAutoBackup()
    }

    // MARK: Wochen blättern

    func previousWeek() {
        weekStart = weekStart.minusWeeks(1)
    }

    func nextWeek() {
        weekStart = weekStart.plusWeeks(1)
    }

    func currentWeek() {
        now = AppTime.now()
        weekStart = WorkCalculator.weekStartOf(now.date)
    }

    /// Kommen bzw. Gehen für heute auf die aktuelle Uhrzeit stempeln.
    func stampClock() {
        let current = AppTime.now()
        storage.stampClock(at: current)
        updateNow(current)
        entries = storage.loadEntries()
        runAutoBackup()
    }

    // MARK: Sicherung

    func backupText() -> String {
        return BackupFormat.create(
            entries: storage.loadEntries().values,
            settings: storage.loadSettings(),
            createdAt: AppTime.now()
        )
    }

    /// Dateiname ohne Endung, z. B. "Arbeitszeit-Backup-2026-09-30" (".json" ergänzt das System).
    var backupFileBaseName: String {
        return "Arbeitszeit-Backup-" + AppTime.now().date.iso
    }

    /// Übernimmt eine Sicherung wie Android: Einträge derselben Tage werden ersetzt,
    /// alle anderen bleiben erhalten, die Einstellungen werden übernommen.
    func restore(_ data: BackupData) {
        let restored = data.restore(into: storage.loadEntries(), settings: storage.loadSettings())
        storage.replaceEntries(restored.entries)
        storage.saveSettings(restored.settings)
        reload()
    }

    // MARK: Automatische Sicherung

    /// Schaltet die automatische Sicherung in die gewählte Datei ein und sichert sofort.
    /// false, wenn kein dauerhafter Zugriff auf die Datei möglich ist.
    func enableAutoBackup(_ url: URL) -> Bool {
        let enabled = autoBackup.enable(url: url)
        runAutoBackup()
        return enabled
    }

    func disableAutoBackup() {
        autoBackup.disable()
        refreshAutoBackupStatus()
    }

    /// Legt eine Sicherungsdatei mit dem aktuellen Stand an. Der Nutzer verschiebt sie an ihren Platz
    /// (z. B. iCloud Drive); dort schreibt die automatische Sicherung sie danach immer neu.
    func prepareAutoBackupFile() -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutoBackup", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(AutoBackup.fileName)
            try Data(backupText().utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Schreibt die Sicherungsdatei neu, falls sich seit der letzten Sicherung etwas geändert hat.
    private func runAutoBackup() {
        autoBackup.backupIfNeeded { [weak self] in
            self?.refreshAutoBackupStatus()
        }
        refreshAutoBackupStatus()
    }

    private func refreshAutoBackupStatus() {
        let status = autoBackup.status
        if status != autoBackupStatus {
            autoBackupStatus = status
        }
    }

    // MARK: Monatsexport

    func monthSummary(_ month: YearMonth) -> MonthExport.Summary {
        return MonthExport.summary(month: month, entries: entries, settings: settings)
    }

    func monthCSV(_ month: YearMonth) -> String {
        return MonthExport.csv(month: month, entries: entries, settings: settings)
    }

    /// Schreibt den Stundenzettel in eine temporäre Datei mit dem richtigen Namen (zum Teilen).
    func exportFile(for month: YearMonth) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(MonthExport.fileName(month: month))
            try Data(monthCSV(month).utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
