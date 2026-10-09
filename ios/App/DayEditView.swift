import SwiftUI
import ArbeitszeitKit

/// Tag bearbeiten (wie DayEditDialog in Android): Art, Beginn, Ende, tatsächliche Pause
/// und die Rechnung Anwesenheit − Pause = Arbeitszeit.
struct DayEditView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let original: DayEntry
    let settings: AppSettings

    @State private var type: DayType
    @State private var start: LocalTime?
    @State private var end: LocalTime?
    @State private var breakText: String
    @FocusState private var breakFocused: Bool

    init(entry: DayEntry, settings: AppSettings) {
        self.original = entry
        self.settings = settings
        _type = State(initialValue: entry.type)
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end)
        _breakText = State(initialValue: DayEditing.breakText(for: entry))
    }

    private var draft: DayEntry {
        return DayEditing.draft(date: original.date, type: type, start: start, end: end, breakText: breakText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $type) {
                        ForEach(DayType.allCases) { option in
                            Text(verbatim: option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("day-type-picker")
                }

                if type == .work {
                    Section {
                        TimeRow(label: "Beginn", time: $start, identifier: "start-time") {
                            DayEditing.defaultStart(date: original.date, now: AppTime.now())
                        }
                        TimeRow(label: "Ende", time: $end, identifier: "end-time") {
                            DayEditing.defaultEnd(
                                date: original.date,
                                start: start,
                                manualBreakMinutes: draft.manualBreakMinutes,
                                settings: settings,
                                now: AppTime.now()
                            )
                        }
                    }

                    Section {
                        LabeledContent("Tatsächliche Pause (Min.)") {
                            TextField("optional", text: $breakText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($breakFocused)
                                .frame(maxWidth: 110)
                                .accessibilityIdentifier("break-field")
                        }
                    } footer: {
                        Text(verbatim: DayEditing.breakHint(settings: settings))
                    }

                    if start != nil && end != nil {
                        CalculationSection(result: WorkCalculator.evaluate(entry: draft, settings: settings))
                    }
                } else {
                    Section {
                        Text(verbatim: DayEditing.absenceText(type: type, settings: settings))
                    }
                }

                if !original.isEmpty {
                    Section {
                        Button("Löschen", role: .destructive) {
                            model.delete(original.date)
                            dismiss()
                        }
                        .accessibilityIdentifier("day-edit-delete")
                    }
                }
            }
            .navigationTitle(DayEditing.title(date: original.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .accessibilityIdentifier("day-edit-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        model.save(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("day-edit-save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") {
                        breakFocused = false
                    }
                }
            }
            .onChange(of: breakText) { _, newValue in
                let filtered = filterDigits(newValue, maxLength: 3)
                if filtered != newValue {
                    breakText = filtered
                }
            }
        }
    }
}

/// Beginn bzw. Ende: "--:--" zum Setzen, danach Zeitauswahl mit Knopf zum Entfernen.
private struct TimeRow: View {
    let label: String
    @Binding var time: LocalTime?
    let identifier: String
    let suggestion: () -> LocalTime

    var body: some View {
        if let value = time {
            HStack(spacing: 12) {
                DatePicker(
                    label,
                    selection: Binding(
                        get: { PickerTime.date(time ?? value) },
                        set: { time = PickerTime.time($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .environment(\.locale, Locale(identifier: "de_DE"))
                .accessibilityIdentifier(identifier)

                Button {
                    time = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(verbatim: label + " löschen"))
            }
        } else {
            Button {
                time = suggestion()
            } label: {
                HStack {
                    Text(verbatim: label)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text(verbatim: "--:--")
                        .foregroundStyle(.secondary)
                }
            }
            // Sonst liest VoiceOver "Minus Minus Doppelpunkt Minus Minus" vor.
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text("nicht gesetzt"))
            .accessibilityHint(Text("Tippen, um eine Uhrzeit einzutragen"))
            .accessibilityIdentifier(identifier)
        }
    }
}

/// Rechnung wie in Android: Anwesenheit − Pause = Arbeitszeit.
private struct CalculationSection: View {
    let result: DayResult

    var body: some View {
        let breakLabel = result.autoBreakApplied ? "\u{2212} Pause (automatisch)" : "\u{2212} Pause"
        Section {
            LabeledContent {
                Text(verbatim: formatDuration(result.attendanceMinutes) + " h")
            } label: {
                Text("Anwesenheit")
            }
            LabeledContent {
                Text(verbatim: formatDuration(result.breakMinutes) + " h")
            } label: {
                Text(verbatim: breakLabel)
            }
            LabeledContent {
                Text(verbatim: formatDuration(result.creditedMinutes) + " h")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
            } label: {
                Text("= Arbeitszeit")
                    .fontWeight(.semibold)
            }
            if result.exceedsDailyMax {
                Text("Mehr als 10 h Arbeitszeit – gesetzliche Tageshöchstgrenze (§ 3 ArbZG)")
                    .font(.footnote)
                    .foregroundStyle(Palette.negative)
            }
        }
    }
}

/// Umrechnung zwischen LocalTime und Date für den DatePicker. Gerechnet wird an einem festen Tag
/// ohne Zeitumstellung in der Zeitzone des Geräts (wie der DatePicker selbst).
enum PickerTime {
    private static let referenceDay = LocalDate(year: 2001, month: 1, day: 15)

    static func date(_ time: LocalTime) -> Date {
        return LocalDateTime(date: referenceDay, time: time).foundationDate ?? Date()
    }

    static func time(_ date: Date) -> LocalTime {
        return LocalDateTime(foundationDate: date).time
    }
}
