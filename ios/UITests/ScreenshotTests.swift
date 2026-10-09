import XCTest

/// Startet die App mit Beispieldaten und fester Uhrzeit und macht Bildschirmfotos der wichtigsten Seiten.
/// Die Bilder landen als PNG in $SIMULATOR_HOST_HOME/az-screenshots (auf dem Mac) und als Anhang im Testergebnis.
final class ScreenshotTests: XCTestCase {

    /// Mittwoch, 30.09.2026, 15:00 – seit 08:00 eingestempelt, Montag 10:30 h.
    private let baseArguments = [
        "-AZDemoData", "YES",
        "-AZFixedNow", "2026-09-30T15:00",
        "-AppleLanguages", "(de)",
        "-AppleLocale", "de_DE",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testScreenshots() throws {
        // 1. Wochenübersicht
        var app = launch()
        XCTAssertTrue(app.staticTexts["week-title"].waitForExistence(timeout: 20), "Wochenansicht fehlt")
        settle()
        saveScreenshot("01-woche")

        // 2. Tag bearbeiten (Tippen auf die Karte von Montag)
        let monday = app.buttons["day-2026-09-28"]
        if monday.waitForExistence(timeout: 5) {
            monday.tap()
            XCTAssertTrue(app.buttons["day-edit-save"].waitForExistence(timeout: 5), "Dialog Tag bearbeiten fehlt")
            settle()
            saveScreenshot("02-tag-bearbeiten")
        } else {
            XCTFail("Tageskarte Montag nicht gefunden")
        }

        // 3. Einstellungen
        app = launch()
        let settingsButton = app.buttons["settings-button"]
        if settingsButton.waitForExistence(timeout: 10) {
            settingsButton.tap()
            XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5), "Einstellungen fehlen")
            settle()
            saveScreenshot("03-einstellungen")
        } else {
            XCTFail("Knopf Einstellungen nicht gefunden")
        }

        // 4. Monatsexport
        app = launch()
        let exportButton = app.buttons["export-button"]
        if exportButton.waitForExistence(timeout: 10) {
            exportButton.tap()
            XCTAssertTrue(app.staticTexts["export-month"].waitForExistence(timeout: 5), "Monatsexport fehlt")
            settle()
            saveScreenshot("04-monatsexport")
        } else {
            XCTFail("Knopf Stundenzettel nicht gefunden")
        }

        // 5. Widget-Vorschau
        app = launch(extraArguments: ["-AZWidgetPreview", "YES"])
        XCTAssertTrue(app.staticTexts["widget-preview-title"].waitForExistence(timeout: 20), "Widget-Vorschau fehlt")
        settle()
        saveScreenshot("05-widgets")
        app.terminate()
    }

    // MARK: Hilfen

    /// Startet die App neu (launch() beendet eine laufende Instanz vorher).
    @MainActor
    private func launch(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseArguments + extraArguments
        app.launch()
        return app
    }

    /// Kurz warten, bis Animationen (Sheets, Navigation) fertig sind.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private func saveScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let base: String
        if let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"], !hostHome.isEmpty {
            base = hostHome
        } else {
            base = NSTemporaryDirectory()
        }
        let directory = URL(fileURLWithPath: base).appendingPathComponent("az-screenshots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        } catch {
            XCTFail("Bildschirmfoto \(name) konnte nicht gespeichert werden: \(error)")
        }
    }
}
