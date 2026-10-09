import AppIntents

/// Siri und Kurzbefehle: "Stempeln in Arbeitszeit". Nur im App-Target, nicht in den Widgets.
struct ArbeitszeitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleClockIntent(),
            phrases: [
                "Stempeln in \(.applicationName)",
                "\(.applicationName) stempeln",
                "Kommen oder Gehen in \(.applicationName)",
            ],
            shortTitle: "Stempeln",
            systemImageName: "clock.badge.checkmark"
        )
    }
}
