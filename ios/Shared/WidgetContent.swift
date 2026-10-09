import SwiftUI
import WidgetKit
import AppIntents
import ArbeitszeitKit

/// Daten, die die Widgets anzeigen (wie WidgetSnapshot in Android).
struct WidgetSnapshot: Sendable {
    let settings: AppSettings
    /// Woche ohne die gerade laufende Zeit – so stimmt die Summe auch zwischen zwei Aktualisierungen.
    let summary: WeekSummary
    /// Heute ohne laufende Zeit.
    let today: DayResult
    let action: ClockAction?
    /// Die Wochenstunden sind inklusive der laufenden Zeit erreicht.
    let weekReached: Bool
    /// false: Das Widget sieht die Daten der App nicht (keine App Group).
    let hasData: Bool

    init(entries: [LocalDate: DayEntry], settings: AppSettings, now: LocalDateTime, hasData: Bool = true) {
        let date = now.date
        let weekStart = WorkCalculator.weekStartOf(date)
        let todayEntry = entries[date] ?? DayEntry(date: date)
        let withRunning = WorkCalculator.summarizeWeek(
            weekStart: weekStart,
            entries: entries,
            settings: settings,
            now: now
        )
        self.settings = settings
        self.summary = WorkCalculator.summarizeWeek(weekStart: weekStart, entries: entries, settings: settings)
        self.today = WorkCalculator.evaluate(entry: todayEntry, settings: settings)
        self.action = nextClockAction(todayEntry)
        self.weekReached = withRunning.actualMinutes >= settings.weeklyTargetMinutes
        self.hasData = hasData
    }

    /// Aktuelle Daten aus dem gemeinsamen Speicher.
    static func load(now: LocalDateTime) -> WidgetSnapshot {
        let storage = WorkStorage()
        return WidgetSnapshot(
            entries: storage.loadEntries(),
            settings: storage.loadSettings(),
            now: now,
            hasData: storage.isShared || !WorkStorage.isAppExtension
        )
    }

    /// Beispiel für die Widget-Galerie.
    static func sample(now: LocalDateTime) -> WidgetSnapshot {
        let sampleNow = LocalDateTime(date: now.date, time: LocalTime(hour: 15, minute: 0))
        return WidgetSnapshot(entries: DemoData.entries(today: now.date), settings: AppSettings(), now: sampleNow)
    }

    var isClockedIn: Bool {
        let entry = today.entry
        return !entry.type.isAbsence && entry.start != nil && entry.end == nil
    }

    /// Angerechnete Minuten der anderen Tage dieser Woche.
    var otherDaysMinutes: Int {
        return summary.minutesExcluding(today.entry.date)
    }

    /// Ziel von heute, solange eingestempelt ist.
    var goal: TodayGoal? {
        guard isClockedIn else { return nil }
        return WorkCalculator.todayGoal(entry: today.entry, otherDaysMinutes: otherDaysMinutes, settings: settings)
    }

    /// Werkstudenten-Grenze erreicht: rot warnen (wie die Tageskarte der App).
    var goalWarns: Bool {
        guard settings.weeklyHoursAreLimit, let goal = goal else { return false }
        switch goal {
        case .weekAlreadyFull:
            return true
        case .weekFull:
            return weekReached
        case .dailyTarget:
            return false
        }
    }

    var limitExceeded: Bool {
        return settings.weeklyHoursAreLimit && summary.balanceMinutes > 0
    }

    var progress: Double {
        guard summary.targetMinutes > 0 else { return 1 }
        let value = Double(summary.actualMinutes) / Double(summary.targetMinutes)
        return min(max(value, 0), 1)
    }

    var weekTitle: String {
        return "KW \(weekNumber(summary.weekStart)) \u{00B7} Arbeitszeit"
    }

    var hoursText: String {
        return formatDuration(summary.actualMinutes) + " h"
    }

    var targetText: String {
        return " / " + formatDuration(summary.targetMinutes) + " h"
    }

    /// "Woche 10:30 / 20:00 h"
    var weekLine: String {
        return "Woche \(formatDuration(summary.actualMinutes)) / \(formatDuration(summary.targetMinutes)) h"
    }

    /// "Noch 9:30 h bis zur Grenze"
    var statusLine: String {
        return weekStatusText(summary, isLimit: settings.weeklyHoursAreLimit)
    }

    /// "Seit 08:00 · 20 h voll um 18:15", ab dem Zielzeitpunkt "Seit 08:00 · 20 h voll – jetzt ausstempeln".
    var todayLine: String {
        if isClockedIn, weekReached, let start = today.entry.start, let goal = goal {
            return "Seit \(formatTime(start)) \u{00B7} " + goalText(goal, settings: settings, weekReached: true)
        }
        return todayStatusText(today, otherDaysMinutes: otherDaysMinutes, settings: settings)
    }

    /// Hauptzeile des kleinen Widgets.
    var clockHeadline: String {
        let entry = today.entry
        if entry.type.isAbsence {
            return "Heute: " + entry.type.label
        }
        if let start = entry.start, entry.end == nil {
            return "seit " + formatTime(start)
        }
        if entry.start != nil && entry.end != nil {
            return "Heute " + formatDuration(today.creditedMinutes) + " h"
        }
        return "Noch nicht eingestempelt"
    }

    /// Zweite Zeile des kleinen Widgets: Tagesziel oder Wochenstand.
    var clockDetail: String {
        if let goal = goal {
            return goalText(goal, settings: settings, weekReached: weekReached)
        }
        return weekLine
    }

    /// Zeitpunkte, an denen sich die Anzeige ändert: Wochenziel erreicht und Mitternacht.
    func changeTimes(after now: LocalDateTime) -> [LocalDateTime] {
        var times: [LocalDateTime] = []
        if !weekReached, let start = today.entry.start, case .weekFull(let at)? = goal, at > start, at > now.time {
            times.append(LocalDateTime(date: now.date, time: at))
        }
        times.append(LocalDateTime(date: now.date.plusDays(1), time: LocalTime(minutesOfDay: 0)))
        return times
    }
}

// MARK: - Ansichten

/// Kleines Widget "Stempeln": Status von heute und Kommen/Gehen-Knopf.
struct ClockWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if snapshot.hasData {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Arbeitszeit \u{00B7} KW \(weekNumber(snapshot.summary.weekStart))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(verbatim: snapshot.clockHeadline)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(verbatim: snapshot.clockDetail)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
                Spacer(minLength: 4)
                WidgetClockButton(action: snapshot.action, fullWidth: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetMissingDataView()
        }
    }

    private var detailColor: Color {
        if snapshot.goalWarns {
            return Palette.negative
        }
        return snapshot.goal != nil ? Palette.accent : Color.secondary
    }
}

/// Mittleres Widget "Woche": Stunden, Grenze, Fortschritt, Status von heute und Kommen/Gehen-Knopf.
struct WeekWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if snapshot.hasData {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 8) {
                    Text(verbatim: snapshot.weekTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    WidgetClockButton(action: snapshot.action, fullWidth: false)
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: snapshot.hoursText)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(verbatim: snapshot.targetText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: snapshot.progress)
                    .tint(snapshot.limitExceeded ? Palette.negative : Palette.accent)
                Text(verbatim: snapshot.statusLine)
                    .font(.caption)
                    .foregroundStyle(snapshot.limitExceeded ? Palette.negative : Color.secondary)
                    .lineLimit(1)
                Text(verbatim: snapshot.todayLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.goalWarns ? Palette.negative : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetMissingDataView()
        }
    }
}

/// Kommen/Gehen-Knopf der Widgets; ausgeblendet, wenn heute nichts zu stempeln ist.
struct WidgetClockButton: View {
    let action: ClockAction?
    var fullWidth: Bool = false

    var body: some View {
        if let action = action {
            Button(intent: ToggleClockIntent()) {
                Label(action.label, systemImage: action.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(maxWidth: fullWidth ? .infinity : nil)
                    .foregroundStyle(Palette.onAccent)
                    .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Hinweis, wenn die Widget-Erweiterung die Daten der App nicht lesen kann (keine App Group).
struct WidgetMissingDataView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arbeitszeit")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Keine Daten")
                .font(.headline)
            Text("Widgets brauchen die App-Gruppe. Bitte in der App stempeln.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
