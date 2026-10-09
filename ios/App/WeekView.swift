import SwiftUI
import ArbeitszeitKit

/// Wochenübersicht (Startseite), wie WeekScreen in Android.
struct WeekView: View {
    @EnvironmentObject private var model: AppModel
    let openSettings: () -> Void
    @State private var editing: DayEntry? = nil
    @State private var showExport = false

    var body: some View {
        let summary = model.weekSummary
        let settings = model.settings
        let weekReached = summary.actualMinutes >= settings.weeklyTargetMinutes

        ScrollView {
            VStack(spacing: 12) {
                WeekNavigator(
                    weekStart: summary.weekStart,
                    isCurrentWeek: model.isCurrentWeek,
                    onPrevious: { model.previousWeek() },
                    onNext: { model.nextWeek() },
                    onToday: { model.currentWeek() }
                )
                SummaryCard(summary: summary, isLimit: settings.weeklyHoursAreLimit)
                if model.entries.isEmpty {
                    RestoreHint(onRestore: openSettings)
                }
                ForEach(summary.days, id: \.entry.date) { day in
                    DayCard(
                        day: day,
                        isToday: day.entry.date == model.today,
                        settings: settings,
                        otherDaysMinutes: summary.minutesExcluding(day.entry.date),
                        weekReached: weekReached,
                        onEdit: { editing = model.entry(for: day.entry.date) },
                        onClock: { model.stampClock() }
                    )
                }
                Text(verbatim: breakInfoText(settings))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Arbeitszeitrechner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showExport = true
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Stundenzettel exportieren")
                .accessibilityIdentifier("export-button")

                ShareLink(
                    item: weekShareText(summary, isLimit: settings.weeklyHoursAreLimit),
                    subject: Text(verbatim: "Arbeitszeit KW \(weekNumber(summary.weekStart))")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Woche teilen")
                .accessibilityIdentifier("share-button")

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Einstellungen")
                .accessibilityIdentifier("settings-button")
            }
        }
        .sheet(item: $editing) { entry in
            DayEditView(entry: entry, settings: settings)
                .environmentObject(model)
        }
        .sheet(isPresented: $showExport) {
            MonthExportView(initialMonth: model.isCurrentWeek ? YearMonth(model.today) : YearMonth(model.weekStart))
                .environmentObject(model)
        }
        .task {
            // Laufende Arbeitszeit von heute regelmäßig aktualisieren.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                model.tick()
            }
        }
    }
}

/// "KW 40" mit Datumsbereich und Pfeilen zum Blättern.
struct WeekNavigator: View {
    let weekStart: LocalDate
    let isCurrentWeek: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Vorherige Woche")
            .accessibilityIdentifier("previous-week")

            VStack(spacing: 2) {
                Text(verbatim: "KW \(weekNumber(weekStart))")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("week-title")
                Text(verbatim: weekRange(weekStart))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !isCurrentWeek {
                    Button("Zur aktuellen Woche", action: onToday)
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 2)
                        .accessibilityIdentifier("current-week")
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Nächste Woche")
            .accessibilityIdentifier("next-week")
        }
        .padding(.top, 4)
    }
}

/// Karte mit Wochenstunden, Fortschritt, Abstand zur Grenze bzw. Überstunden und abgezogenen Pausen.
struct SummaryCard: View {
    let summary: WeekSummary
    let isLimit: Bool
    /// Wächst mit der Schriftgröße des Systems (Dynamic Type).
    @ScaledMetric(relativeTo: .largeTitle) private var hoursFontSize: CGFloat = 44

    var body: some View {
        let balance = summary.balanceMinutes
        let limitExceeded = isLimit && balance > 0

        VStack(alignment: .leading, spacing: 10) {
            Text("Arbeitszeit diese Woche")
                .font(.subheadline.weight(.medium))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: formatDuration(summary.actualMinutes))
                    .font(.system(size: hoursFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("week-hours")
                Text(verbatim: "/ \(formatDuration(summary.targetMinutes)) h")
                    .font(.title3)
            }
            ProgressView(value: progress)
                .tint(limitExceeded ? Palette.negative : Palette.accent)
            HStack(alignment: .top, spacing: 12) {
                balanceStat(balance: balance, limitExceeded: limitExceeded)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatView(label: "Pausen abgezogen", value: "\(formatDuration(summary.breakMinutes)) h", color: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Palette.onSummary)
        .background(Palette.summaryBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var progress: Double {
        guard summary.targetMinutes > 0 else { return 1 }
        let value = Double(summary.actualMinutes) / Double(summary.targetMinutes)
        return min(max(value, 0), 1)
    }

    @ViewBuilder
    private func balanceStat(balance: Int, limitExceeded: Bool) -> some View {
        if isLimit {
            if limitExceeded {
                StatView(label: "Grenze überschritten", value: "+\(formatDuration(balance)) h", color: Palette.negative)
            } else {
                StatView(label: "Bis zur Grenze", value: "\(formatDuration(-balance)) h", color: nil)
            }
        } else if balance < 0 {
            StatView(label: "Noch offen", value: "\(formatDuration(-balance)) h", color: nil)
        } else {
            StatView(label: "Überstunden", value: "+\(formatDuration(balance)) h", color: Palette.positive)
        }
    }
}

struct StatView: View {
    let label: String
    let value: String
    let color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.caption.weight(.medium))
            Text(verbatim: value)
                .font(.headline)
                .foregroundStyle(color ?? Palette.onSummary)
        }
    }
}

/// Hinweis nach einer (Neu-)Installation, dass sich ein Backup wiederherstellen lässt.
struct RestoreHint: View {
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noch keine Einträge. Tippe auf einen Tag, um loszulegen. Hast du ein Backup, kannst du es in den Einstellungen wiederherstellen.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Backup wiederherstellen", action: onRestore)
                    .font(.subheadline.weight(.semibold))
                    .tint(Palette.onHint)
                    .accessibilityIdentifier("restore-hint")
            }
        }
        .padding(16)
        .foregroundStyle(Palette.onHint)
        .background(Palette.hintBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Karte eines Tages mit Stunden, Status und auf der Karte von heute dem Kommen/Gehen-Knopf.
struct DayCard: View {
    let day: DayResult
    let isToday: Bool
    let settings: AppSettings
    let otherDaysMinutes: Int
    let weekReached: Bool
    let onEdit: () -> Void
    let onClock: () -> Void

    var body: some View {
        let entry = day.entry
        let detail = dayDetail(day, settings: settings, otherDaysMinutes: otherDaysMinutes, weekReached: weekReached)
        let showClock = isToday && entry.type == .work && (entry.start == nil || entry.end == nil)
        let title = isToday ? germanDayName(entry.date) + " \u{00B7} Heute" : germanDayName(entry.date)

        VStack(alignment: .leading, spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: title)
                                .font(.headline)
                            Text(verbatim: formatShortDate(entry.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(verbatim: dayValueText(day))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                    }
                    Text(verbatim: detail.text)
                        .font(.subheadline)
                        .foregroundStyle(DayCard.color(for: detail.tone))
                        .fixedSize(horizontal: false, vertical: true)
                    if day.exceedsDailyMax {
                        Text("Mehr als 10 h Arbeitszeit – gesetzliche Tageshöchstgrenze (§ 3 ArbZG)")
                            .font(.caption)
                            .foregroundStyle(Palette.negative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("day-" + entry.date.iso)

            if showClock {
                ClockButton(clockIn: entry.start == nil, action: onClock)
            }
        }
        .padding(16)
        .background(
            isToday ? Palette.todayBackground : Palette.cardBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    static func color(for tone: DayDetail.Tone) -> Color {
        switch tone {
        case .absence:
            return Palette.absence
        case .running:
            return Palette.accent
        case .warning:
            return Palette.negative
        case .normal:
            return Color.secondary
        case .error:
            return Palette.error
        }
    }
}

/// "Kommen – jetzt einstempeln" bzw. "Gehen – jetzt ausstempeln".
struct ClockButton: View {
    let clockIn: Bool
    let action: () -> Void

    var body: some View {
        let title = clockIn ? "Kommen \u{2013} jetzt einstempeln" : "Gehen \u{2013} jetzt ausstempeln"
        let symbol = clockIn ? ClockAction.clockIn.symbolName : ClockAction.clockOut.symbolName
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                // Wie onPrimary in Android: Im Dunkelmodus ist die Tönung hell, weiße Schrift wäre kaum lesbar.
                .foregroundStyle(Palette.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.accent)
        .controlSize(.large)
        .accessibilityIdentifier("clock-button")
    }
}
