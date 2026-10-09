import WidgetKit
import SwiftUI
import AppIntents
import ArbeitszeitKit

@main
struct ArbeitszeitWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClockWidget()
        WeekWidget()
        if #available(iOS 18.0, *) {
            ClockControl()
        }
    }
}

// MARK: - Zeitleiste

struct WorkWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Ein Eintrag für jetzt, einer zum Zeitpunkt, an dem die Woche voll ist ("20 h voll – jetzt ausstempeln"),
/// und einer um Mitternacht. Nach jeder Änderung in der App wird die Zeitleiste ohnehin neu geladen.
struct WorkTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> WorkWidgetEntry {
        return WorkWidgetEntry(date: Date(), snapshot: WidgetSnapshot.sample(now: AppTime.now()))
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkWidgetEntry) -> Void) {
        let now = AppTime.now()
        let snapshot = context.isPreview ? WidgetSnapshot.sample(now: now) : WidgetSnapshot.load(now: now)
        completion(WorkWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkWidgetEntry>) -> Void) {
        let storage = WorkStorage()
        let entries = storage.loadEntries()
        let settings = storage.loadSettings()
        let hasData = storage.isShared || !WorkStorage.isAppExtension
        let now = AppTime.now()
        let current = WidgetSnapshot(entries: entries, settings: settings, now: now, hasData: hasData)

        var timelineEntries = [WorkWidgetEntry(date: Date(), snapshot: current)]
        for change in current.changeTimes(after: now) {
            guard let date = change.foundationDate, date > Date() else { continue }
            let snapshot = WidgetSnapshot(entries: entries, settings: settings, now: change, hasData: hasData)
            timelineEntries.append(WorkWidgetEntry(date: date, snapshot: snapshot))
        }
        completion(Timeline(entries: timelineEntries, policy: .atEnd))
    }
}

// MARK: - Widgets

/// Kleines Widget: Status von heute und ein Knopf zum Ein- oder Ausstempeln.
struct ClockWidget: Widget {
    let kind = "ClockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkTimelineProvider()) { entry in
            ClockWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    Palette.widgetBackground
                }
        }
        .configurationDisplayName("Stempeln")
        .description("Mit einem Tipp ein- oder ausstempeln")
        .supportedFamilies([.systemSmall])
    }
}

/// Mittleres Widget: Wochenstunden, Grenze und Kommen/Gehen auf einen Blick.
struct WeekWidget: Widget {
    let kind = "WeekWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkTimelineProvider()) { entry in
            WeekWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    Palette.widgetBackground
                }
        }
        .configurationDisplayName("Woche")
        .description("Wochenstunden, Grenze und Kommen/Gehen auf einen Blick")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Kontrollzentrum (iOS 18)

/// Knopf "Stempeln" im Kontrollzentrum und auf dem Sperrbildschirm.
@available(iOS 18.0, *)
struct ClockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ClockControl", provider: ClockControlProvider()) { title in
            if ClockControlProvider.isClockAction(title) {
                ControlWidgetButton(action: ToggleClockIntent()) {
                    Label(title, systemImage: ClockControlProvider.symbolName(for: title))
                }
            } else {
                // Nichts zu stempeln (Feierabend, Urlaub …): App öffnen wie die Android-Kachel.
                ControlWidgetButton(action: OpenAppIntent()) {
                    Label(title, systemImage: ClockControlProvider.symbolName(for: title))
                }
            }
        }
        .displayName("Stempeln")
        .description("Kommen oder Gehen für heute stempeln")
    }
}

/// Beschriftung des Knopfs: "Kommen", "Gehen" oder der Stand von heute.
@available(iOS 18.0, *)
struct ClockControlProvider: ControlValueProvider {
    var previewValue: String {
        return ClockAction.clockIn.label
    }

    func currentValue() async throws -> String {
        let storage = WorkStorage()
        if WorkStorage.isAppExtension && !storage.isShared {
            return "Stempeln"
        }
        let entry = storage.loadEntry(AppTime.now().date)
        if let action = nextClockAction(entry) {
            return action.label
        }
        return entry.type.isAbsence ? entry.type.label : "Feierabend"
    }

    /// "Kommen" oder "Gehen": Der Knopf stempelt, sonst öffnet er die App.
    static func isClockAction(_ title: String) -> Bool {
        return ClockAction.allCases.contains { $0.label == title }
    }

    static func symbolName(for title: String) -> String {
        if title == ClockAction.clockIn.label {
            return ClockAction.clockIn.symbolName
        }
        if title == ClockAction.clockOut.label {
            return ClockAction.clockOut.symbolName
        }
        return "clock"
    }
}
