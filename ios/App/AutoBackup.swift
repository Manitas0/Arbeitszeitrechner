import Foundation
import ArbeitszeitKit

/// Stand der automatischen Sicherung für die Anzeige (wie AutoBackupStatus in Android).
struct AutoBackupStatus: Equatable {
    var enabled = false
    var lastSuccess: LocalDateTime? = nil
    var error: String? = nil
}

/// Automatische Sicherung wie in der Android-App: Nach jeder Änderung wird eine selbst gewählte
/// Sicherungsdatei (z. B. in „Dateien“ oder iCloud Drive) neu geschrieben. Den Zugriff auf die Datei
/// hält ein Lesezeichen (Security-Scoped Bookmark) auch über Neustarts hinweg.
///
/// Geschrieben wird nur in der App. Änderungen aus Widgets, Kontrollzentrum und Siri merkt sich
/// WorkStorage; sie werden gesichert, sobald die App wieder aktiv ist.
final class AutoBackup {
    /// Vorgeschlagener Dateiname (wie in Android).
    static let fileName = "Arbeitszeit-Backup.json"
    static let unreachableMessage = "Sicherungsdatei nicht erreichbar \u{2013} bitte neu auswählen."

    /// Eine Warteschlange für alle Schreibvorgänge, damit sich Sicherungen nicht überholen.
    private static let queue = DispatchQueue(label: "de.arbeitszeitrechner.autobackup")

    private let storage: WorkStorage

    init(storage: WorkStorage) {
        self.storage = storage
    }

    var status: AutoBackupStatus {
        return AutoBackupStatus(
            enabled: storage.backupBookmark != nil,
            lastSuccess: storage.backupLastSuccess,
            error: storage.backupError
        )
    }

    /// Schaltet die automatische Sicherung in die Datei `url` aus der Dateiauswahl ein.
    /// false, wenn sich kein dauerhafter Zugriff auf die Datei einrichten lässt.
    func enable(url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let bookmark = try? AutoBackup.bookmark(for: url) else { return false }
        storage.backupBookmark = bookmark
        storage.backupError = nil
        storage.markBackupPending()
        return true
    }

    func disable() {
        storage.backupBookmark = nil
        storage.backupLastSuccess = nil
        storage.backupError = nil
    }

    /// Schreibt die Sicherungsdatei im Hintergrund neu, falls die automatische Sicherung an ist und sich
    /// seit der letzten Sicherung etwas geändert hat. `completion` läuft danach auf dem Main-Thread.
    func backupIfNeeded(completion: @escaping () -> Void) {
        guard let bookmark = storage.backupBookmark, storage.takeBackupPending() else { return }
        let text = BackupFormat.create(
            entries: storage.loadEntries().values,
            settings: storage.loadSettings(),
            createdAt: AppTime.now()
        )
        AutoBackup.queue.async {
            let result = AutoBackup.write(text, bookmark: bookmark)
            DispatchQueue.main.async {
                self.finish(result, bookmark: bookmark)
                completion()
            }
        }
    }

    private func finish(_ result: Result<Data?, Error>, bookmark: Data) {
        // Inzwischen ausgeschaltet oder eine andere Datei gewählt: Ergebnis verwerfen.
        guard storage.backupBookmark == bookmark else { return }
        switch result {
        case .success(let refreshedBookmark):
            if let refreshedBookmark = refreshedBookmark {
                storage.backupBookmark = refreshedBookmark
            }
            storage.backupLastSuccess = AppTime.now()
            storage.backupError = nil
        case .failure:
            storage.backupError = AutoBackup.unreachableMessage
            // Bei der nächsten Gelegenheit erneut versuchen.
            storage.markBackupPending()
        }
    }

    /// Schreibt `text` in die Datei des Lesezeichens. Liefert ein neues Lesezeichen, wenn das alte
    /// veraltet ist (z. B. weil die Datei verschoben wurde).
    private static func write(_ text: String, bookmark: Data) -> Result<Data?, Error> {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try coordinatedWrite(Data(text.utf8), to: url)
            var refreshed: Data? = nil
            if isStale {
                refreshed = try? AutoBackup.bookmark(for: url)
            }
            return .success(refreshed)
        } catch {
            return .failure(error)
        }
    }

    /// Überschreibt die Datei an Ort und Stelle. Nicht atomar über eine Hilfsdatei: Freigegeben ist nur
    /// die gewählte Datei, nicht ihr Ordner. Der Dateianbieter (z. B. iCloud Drive) wird über den
    /// NSFileCoordinator benachrichtigt.
    private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                try data.write(to: target)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError {
            throw error
        }
        if let error = writeError {
            throw error
        }
    }

    private static func bookmark(for url: URL) throws -> Data {
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
