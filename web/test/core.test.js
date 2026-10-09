// Prüft die Web-Logik gegen die gemeinsamen Testfälle aus der Kotlin-Implementierung
// (shared/test-vectors.json) und mit einigen eigenen Tests.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { isDeepStrictEqual } from 'node:util';

import * as core from '../src/core.js';
import {
  applyBackup, applyClockAction, attendanceMinutes, breakRulesText, createBackup, createEntry, dailyTargetMinutes,
  dayDetail, dayValueText, decodeEntry, decodeSettings, deductedBreak, defaultEndTime, defaultSettings,
  defaultStartTime, draftEntry, encodeEntry, encodeSettings, endTimeForTarget, entryFromJson, entryToJson, evaluate,
  formatBalance, formatDecimalHours, formatDuration, formatHoursInput, formatLocalDateTime, formatTime,
  fromEpochDay, germanDayName, germanMonthName, goalText, isoWeek, lengthOfMonth, mergeBackup, minutesExcluding,
  monthCsv, monthFileName, monthSummary, monthSummaryText, nextClockAction, nowLocalDateTime, parseBackup,
  parseDate, parseHours, parseLocalDateTime, parseTime, plusDays, plusMonths, requiredBreak, restoreSummaryText,
  summarizeWeek, toEpochDay, todayGoal, todayStatusText, toggleClock, validateSettingsForm, weekBalanceStat,
  weekProgress, weekRange, weekShareText, weekStartOf, weekStatusText, yearMonthOf, settingsForm,
  BACKUP_ERROR_MESSAGE, BackupFormatError, DAILY_MAX_WARNING, MonthExport,
} from '../src/core.js';

const vectors = JSON.parse(readFileSync(new URL('../../shared/test-vectors.json', import.meta.url), 'utf8'));

// --- Umwandlung der Testfälle (bewusst ohne die zu prüfenden Lesefunktionen) ---

function time(text) {
  const minutes = parseTime(text);
  assert.notEqual(minutes, null, `Ungültige Uhrzeit im Testfall: ${text}`);
  return minutes;
}

function entryFromVector(json) {
  return {
    date: json.date,
    type: json.type,
    start: json.start === undefined ? null : time(json.start),
    end: json.end === undefined ? null : time(json.end),
    manualBreakMinutes: json.break,
  };
}

function settingsFromVector(json) {
  return {
    weeklyTargetMinutes: json.weeklyTargetMinutes,
    workDaysPerWeek: json.workDaysPerWeek,
    weeklyHoursAreLimit: json.weeklyHoursAreLimit,
    autoBreak: json.autoBreak,
    gradualDeduction: json.gradualDeduction,
    breakRules: json.breakRules.map((rule) => ({ afterMinutes: rule.after, breakMinutes: rule.break })),
  };
}

function nowFromVector(text) {
  if (text === undefined) return null;
  const now = parseLocalDateTime(text);
  assert.notEqual(now, null, `Ungültiger Zeitpunkt im Testfall: ${text}`);
  return now;
}

function entriesFromVector(list) {
  const entries = {};
  for (const json of list) entries[json.date] = entryFromVector(json);
  return entries;
}

function resultToVector(result) {
  return {
    attendanceMinutes: result.attendanceMinutes,
    breakMinutes: result.breakMinutes,
    autoBreakApplied: result.autoBreakApplied,
    creditedMinutes: result.creditedMinutes,
    running: result.running,
    exceedsDailyMax: result.exceedsDailyMax,
  };
}

function goalToVector(goal) {
  if (goal == null) return null;
  return goal.at === undefined ? { kind: goal.kind } : { kind: goal.kind, at: formatTime(goal.at) };
}

const SETTINGS = {};
for (const name of Object.keys(vectors.settings)) SETTINGS[name] = settingsFromVector(vectors.settings[name]);

function settingsNamed(name) {
  assert.ok(SETTINGS[name], `Unbekannte Einstellungen im Testfall: ${name}`);
  return SETTINGS[name];
}

/** Sammelt alle Abweichungen eines Abschnitts und meldet sie gemeinsam. */
function checker(section) {
  const failures = [];
  let count = 0;
  return {
    check(label, actual, expected) {
      count++;
      if (!isDeepStrictEqual(actual, expected)) {
        failures.push(`${section} ${label}\n    erwartet: ${JSON.stringify(expected)}\n    erhalten: ${JSON.stringify(actual)}`);
      }
    },
    done(minimum = 1) {
      assert.ok(count >= minimum, `${section}: nur ${count} Prüfungen`);
      assert.equal(failures.length, 0, `${failures.length} von ${count} Prüfungen fehlgeschlagen:\n` +
        failures.slice(0, 25).join('\n'));
    },
  };
}

// ---------------------------------------------------------------------------------------------
// Gemeinsame Testfälle
// ---------------------------------------------------------------------------------------------

describe('shared/test-vectors.json', () => {
  test('alle Abschnitte werden geprüft', () => {
    assert.deepEqual(Object.keys(vectors).sort(), [
      '_info', 'backup', 'breakRulesText', 'breaks', 'clock', 'csv', 'dates', 'days', 'endTimes', 'format', 'goals',
      'settings', 'weeks',
    ]);
    assert.deepEqual(Object.keys(vectors.format).sort(),
      ['balance', 'decimalHours', 'duration', 'hoursInput', 'parseHours', 'time']);
    assert.deepEqual(Object.keys(vectors.backup).sort(), ['create', 'parse']);
  });

  test('settings', () => {
    const c = checker('settings');
    for (const name of Object.keys(vectors.settings)) {
      const json = vectors.settings[name];
      c.check(`[${name}] decodeSettings`, decodeSettings(json), SETTINGS[name]);
      c.check(`[${name}] encodeSettings`, encodeSettings(SETTINGS[name]), json);
    }
    c.check('defaultSettings = werkstudent', defaultSettings(), SETTINGS.werkstudent);
    c.done(11);
  });

  test('breaks', () => {
    const c = checker('breaks');
    vectors.breaks.forEach((v, i) => {
      const s = settingsNamed(v.settings);
      const label = `#${i} (${v.settings}, Anwesenheit ${v.attendance}, Pause ${v.manual})`;
      c.check(`${label} requiredBreak`, requiredBreak(v.attendance, s), v.required);
      c.check(`${label} deductedBreak`, deductedBreak(v.attendance, v.manual, s), v.deducted);
    });
    c.done(vectors.breaks.length * 2);
  });

  test('days', () => {
    const c = checker('days');
    vectors.days.forEach((v, i) => {
      const entry = entryFromVector(v.entry);
      const result = evaluate(entry, settingsNamed(v.settings), nowFromVector(v.now));
      const label = `#${i} (${v.settings}, ${JSON.stringify(v.entry)}, now ${v.now ?? 'null'})`;
      c.check(label, resultToVector(result), v.result);
      c.check(`${label} entry`, result.entry, entry);
    });
    c.done(vectors.days.length);
  });

  test('weeks', () => {
    const c = checker('weeks');
    vectors.weeks.forEach((v, i) => {
      const s = settingsNamed(v.settings);
      const summary = summarizeWeek(v.weekStart, entriesFromVector(v.entries), s, nowFromVector(v.now));
      const label = `#${i} (${v.settings}, Fall ${v.case}, now ${v.now ?? 'null'})`;
      c.check(`${label} weekStart`, summary.weekStart, v.weekStart);
      c.check(`${label} days`, summary.days.map(resultToVector), v.days);
      c.check(`${label} dates`, summary.days.map((d) => d.entry.date),
        [0, 1, 2, 3, 4, 5, 6].map((n) => plusDays(v.weekStart, n)));
      c.check(`${label} actualMinutes`, summary.actualMinutes, v.actualMinutes);
      c.check(`${label} targetMinutes`, summary.targetMinutes, v.targetMinutes);
      c.check(`${label} breakMinutes`, summary.breakMinutes, v.breakMinutes);
      c.check(`${label} balanceMinutes`, summary.balanceMinutes, v.balanceMinutes);
      c.check(`${label} minutesExcluding(Di)`, minutesExcluding(summary, plusDays(v.weekStart, 1)),
        v.minutesExcludingTuesday);
      c.check(`${label} weekStatusText(Grenze)`, weekStatusText(summary, true), v.weekStatusLimit);
      c.check(`${label} weekStatusText(Soll)`, weekStatusText(summary, false), v.weekStatusNoLimit);
      c.check(`${label} weekShareText(Grenze)`, weekShareText(summary, true), v.shareTextLimit);
      c.check(`${label} weekShareText(Soll)`, weekShareText(summary, false), v.shareTextNoLimit);
    });
    c.done(vectors.weeks.length);
  });

  test('goals', () => {
    const c = checker('goals');
    vectors.goals.forEach((v, i) => {
      const s = settingsNamed(v.settings);
      const entry = entryFromVector(v.entry);
      const goal = todayGoal(entry, v.otherDaysMinutes, s);
      const label = `#${i} (${v.settings}, ${JSON.stringify(v.entry)}, andere Tage ${v.otherDaysMinutes})`;
      c.check(`${label} todayGoal`, goalToVector(goal), v.goal);
      if (v.goal !== null && goal != null) {
        c.check(`${label} goalText`, goalText(goal, s), v.text);
        c.check(`${label} goalText(erreicht)`, goalText(goal, s, true), v.textReached);
      } else {
        c.check(`${label} ohne Text`, [v.text, v.textReached], [undefined, undefined]);
      }
      c.check(`${label} todayStatusText`, todayStatusText(evaluate(entry, s), v.otherDaysMinutes, s), v.todayStatus);
    });
    c.done(vectors.goals.length);
  });

  test('endTimes', () => {
    const c = checker('endTimes');
    vectors.endTimes.forEach((v, i) => {
      const end = endTimeForTarget(time(v.start), v.manual, v.target, settingsNamed(v.settings));
      c.check(`#${i} (${v.settings}, Beginn ${v.start}, Pause ${v.manual}, Ziel ${v.target})`, formatTime(end), v.end);
    });
    c.done(vectors.endTimes.length);
  });

  test('format', () => {
    const c = checker('format');
    const f = vectors.format;
    f.duration.forEach(([minutes, text], i) => c.check(`duration #${i} (${minutes})`, formatDuration(minutes), text));
    f.balance.forEach(([minutes, text], i) => c.check(`balance #${i} (${minutes})`, formatBalance(minutes), text));
    f.hoursInput.forEach(([minutes, text], i) =>
      c.check(`hoursInput #${i} (${minutes})`, formatHoursInput(minutes), text));
    f.decimalHours.forEach(([minutes, text], i) =>
      c.check(`decimalHours #${i} (${minutes})`, formatDecimalHours(minutes), text));
    f.parseHours.forEach(([input, minutes], i) =>
      c.check(`parseHours #${i} (${JSON.stringify(input)})`, parseHours(input), minutes));
    f.time.forEach(([iso, text], i) => c.check(`time #${i} (${iso})`, formatTime(parseTime(iso)), text));
    c.done(f.duration.length + f.balance.length + f.hoursInput.length + f.decimalHours.length +
      f.parseHours.length + f.time.length);
  });

  test('dates', () => {
    const c = checker('dates');
    vectors.dates.forEach((v, i) => {
      const label = `#${i} (${v.date})`;
      c.check(`${label} parseDate`, parseDate(v.date), v.date);
      c.check(`${label} weekStartOf`, weekStartOf(v.date), v.weekStart);
      c.check(`${label} isoWeek`, isoWeek(v.date), v.isoWeek);
      c.check(`${label} weekRange`, weekRange(weekStartOf(v.date)), v.weekRange);
      c.check(`${label} germanDayName`, germanDayName(v.date), v.dayName);
      c.check(`${label} germanMonthName`, germanMonthName(yearMonthOf(v.date)), v.monthName);
    });
    c.done(vectors.dates.length);
  });

  test('breakRulesText', () => {
    const c = checker('breakRulesText');
    vectors.breakRulesText.forEach(([name, text], i) =>
      c.check(`#${i} (${name})`, breakRulesText(settingsNamed(name)), text));
    c.done(vectors.breakRulesText.length);
  });

  test('clock', () => {
    const c = checker('clock');
    vectors.clock.forEach((v, i) => {
      const entry = entryFromVector(v.entry);
      const next = nextClockAction(entry);
      const label = `#${i} (${JSON.stringify(v.entry)})`;
      c.check(`${label} nextClockAction`, next, v.next);
      if (v.next !== null && next != null) {
        c.check(`${label} applyClockAction`, entryToJson(applyClockAction(entry, next, 12 * 60 + 34)), v.applied);
      }
    });
    c.done(vectors.clock.length);
  });

  test('csv', () => {
    const c = checker('csv');
    vectors.csv.forEach((v, i) => {
      const s = settingsNamed(v.settings);
      const entries = entriesFromVector(v.entries);
      const label = `#${i} (${v.settings}, ${v.month})`;
      c.check(`${label} fileName`, monthFileName(v.month), v.fileName);
      c.check(`${label} monthName`, germanMonthName(v.month), v.monthName);
      c.check(`${label} csv`, monthCsv(v.month, entries, s), v.csv);
      c.check(`${label} summary`, monthSummary(v.month, entries, s), v.summary);
      c.check(`${label} MonthExport`, MonthExport.csv(v.month, entries, s), v.csv);
    });
    c.done(vectors.csv.length * 5);
  });

  test('backup.create', () => {
    const v = vectors.backup.create;
    const entries = v.entries.map(entryFromVector);
    const text = createBackup(entries, settingsNamed(v.settings), nowFromVector(v.createdAt));
    // org.json auf dem JVM ordnet die Schlüssel anders als Android; verglichen wird der Inhalt.
    assert.deepStrictEqual(JSON.parse(text), JSON.parse(v.text));
    // Gleiche Einrückung wie toString(2) von org.json.
    assert.equal(JSON.stringify(JSON.parse(v.text), null, 2), v.text);
    assert.equal(JSON.stringify(JSON.parse(text), null, 2), text);
  });

  test('backup.parse', () => {
    const c = checker('backup.parse');
    vectors.backup.parse.forEach((v, i) => {
      const label = `#${i} (${JSON.stringify(v.text).slice(0, 80)})`;
      let data = null;
      let error = null;
      try {
        data = parseBackup(v.text);
      } catch (e) {
        error = e;
      }
      if (v.error) {
        c.check(`${label} Fehler`, error instanceof BackupFormatError ? error.message : String(error), v.message);
        return;
      }
      c.check(`${label} kein Fehler`, error === null ? null : String(error), null);
      if (!data) return;
      c.check(`${label} createdAt`, data.createdAt ? formatLocalDateTime(data.createdAt) : null, v.createdAt);
      c.check(`${label} settings`, data.settings ? encodeSettings(data.settings) : null, v.settings);
      c.check(`${label} entries`, data.entries.map(entryToJson), v.entries);
    });
    c.done(vectors.backup.parse.length);
  });
});

// ---------------------------------------------------------------------------------------------
// Eigene Tests
// ---------------------------------------------------------------------------------------------

const monday = '2026-09-28';
const t = (h, m = 0) => h * 60 + m;

describe('Datum und Uhrzeit', () => {
  test('Tage zählen ohne Zeitzonen (Sommerzeit, Schaltjahre)', () => {
    assert.equal(plusDays('2026-03-28', 1), '2026-03-29');
    assert.equal(plusDays('2026-03-28', 2), '2026-03-30');
    assert.equal(plusDays('2026-10-24', 1), '2026-10-25');
    assert.equal(plusDays('2026-10-25', 1), '2026-10-26');
    assert.equal(plusDays('2028-02-28', 1), '2028-02-29');
    assert.equal(plusDays('2100-02-28', 1), '2100-03-01');
    assert.equal(plusDays('2000-02-28', 1), '2000-02-29');
    assert.equal(plusDays('2026-01-01', -1), '2025-12-31');
    assert.equal(fromEpochDay(0), '1970-01-01');
    assert.equal(toEpochDay('1969-12-31'), -1);
  });

  test('Tageszählung stimmt mit dem gregorianischen Kalender überein', () => {
    for (let day = -800000; day <= 800000; day += 997) {
      const date = new Date(day * 86400000);
      const expected = `${String(date.getUTCFullYear()).padStart(4, '0')}-` +
        `${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')}`;
      if (date.getUTCFullYear() < 0 || date.getUTCFullYear() > 9999) continue;
      assert.equal(fromEpochDay(day), expected);
      assert.equal(toEpochDay(expected), day);
      assert.equal(core.dayOfWeek(expected), ((date.getUTCDay() + 6) % 7) + 1);
    }
  });

  test('parseDate ist streng wie LocalDate.parse', () => {
    assert.equal(parseDate('2028-02-29'), '2028-02-29');
    for (const text of ['2026-02-29', '2026-13-01', '2026-00-10', '2026-04-31', '26-01-01', '2026-1-01', ' 2026-01-01', '', null]) {
      assert.equal(parseDate(text), null, String(text));
    }
  });

  test('Monate', () => {
    assert.equal(plusMonths('2026-12', 1), '2027-01');
    assert.equal(plusMonths('2026-01', -1), '2025-12');
    assert.equal(plusMonths('2026-09', -21), '2024-12');
    assert.equal(lengthOfMonth('2028-02'), 29);
    assert.equal(lengthOfMonth('2026-02'), 28);
    assert.equal(germanMonthName('2026-03'), 'März 2026');
    assert.equal(core.parseYearMonth('2026-13'), null);
    assert.deepEqual(core.datesOfMonth('2026-02').length, 28);
  });

  test('parseTime ist streng wie LocalTime.parse', () => {
    assert.equal(parseTime('08:00'), 480);
    assert.equal(parseTime('23:59'), 1439);
    assert.equal(parseTime('08:00:59'), 480);
    assert.equal(parseTime('08:00:00.123'), 480);
    for (const text of ['8:00', '24:00', '23:60', '08:00:60', ' 08:00', '08:00Z', '0800', '', 480, null]) {
      assert.equal(parseTime(text), null, String(text));
    }
    assert.equal(formatTime(-1), '23:59');
    assert.equal(formatTime(1440 + 65), '01:05');
  });

  test('Zeitpunkte wie LocalDateTime', () => {
    assert.deepEqual(parseLocalDateTime('2026-09-30T14:55:12'), { date: '2026-09-30', minutes: t(14, 55), seconds: 12 });
    assert.equal(formatLocalDateTime(parseLocalDateTime('2026-09-30T14:55:12')), '2026-09-30T14:55:12');
    assert.equal(formatLocalDateTime(parseLocalDateTime('2026-09-30T14:55:00')), '2026-09-30T14:55');
    assert.equal(formatLocalDateTime(parseLocalDateTime('2026-09-30t08:05')), '2026-09-30T08:05');
    assert.equal(parseLocalDateTime('2026-02-30T10:00'), null);
    assert.equal(parseLocalDateTime('2026-09-30 10:00'), null);
    assert.equal(parseLocalDateTime('gestern'), null);
    assert.deepEqual(nowLocalDateTime(new Date(2026, 8, 30, 14, 55, 12)),
      { date: '2026-09-30', minutes: t(14, 55), seconds: 12 });
    assert.equal(core.today(new Date(2026, 0, 1, 0, 0, 0)), '2026-01-01');
    assert.equal(core.currentTime(new Date(2026, 0, 1, 23, 59, 59)), t(23, 59));
  });

  test('Kalenderwochen am Jahreswechsel', () => {
    assert.equal(isoWeek('2026-12-31'), 53);
    assert.equal(isoWeek('2027-01-03'), 53);
    assert.equal(isoWeek('2027-01-04'), 1);
    assert.equal(isoWeek('2024-12-30'), 1);
    assert.equal(core.weekNumber(weekStartOf('2025-01-01')), 1);
  });
});

describe('Berechnung', () => {
  const settings = defaultSettings();

  test('Werkstudent: 6:15 h anwesend -> 6:00 h Arbeit (gestaffelt)', () => {
    const day = evaluate(createEntry(monday, { start: t(8), end: t(14, 15) }), settings);
    assert.equal(day.breakMinutes, 15);
    assert.equal(day.creditedMinutes, 360);
    assert.equal(day.autoBreakApplied, true);
    assert.equal(dailyTargetMinutes(settings), 600);
  });

  test('Nachtschicht über Mitternacht', () => {
    assert.equal(attendanceMinutes(t(22), t(6)), 480);
    assert.equal(attendanceMinutes(t(8), t(8)), 0);
  });

  test('laufender Tag zählt bis jetzt', () => {
    const entry = createEntry(monday, { start: t(8) });
    const day = evaluate(entry, settings, { date: monday, minutes: t(14, 30), seconds: 59 });
    assert.equal(day.running, true);
    assert.equal(day.attendanceMinutes, 390);
    assert.equal(day.creditedMinutes, 360);
    assert.equal(evaluate(entry, settings, { date: plusDays(monday, 1), minutes: t(10), seconds: 0 }).running, false);
  });

  test('README-Beispiel: Montag 10:30 h, Donnerstag ab 8:00 -> 20 h voll um 18:15', () => {
    const goal = todayGoal(createEntry(plusDays(monday, 3), { start: t(8) }), 630, settings);
    assert.deepEqual(goal, { kind: 'weekFull', at: t(18, 15) });
    assert.equal(goalText(goal, settings), '20 h voll um 18:15');
    assert.equal(goalText(goal, settings, true), '20 h voll – jetzt ausstempeln');
  });

  test('Einträge als Objekt, Map oder Array ergeben dieselbe Woche', () => {
    const list = [
      createEntry(monday, { start: t(8), end: t(18, 45) }),
      createEntry(plusDays(monday, 2), { type: 'VACATION' }),
    ];
    const asObject = summarizeWeek(monday, { [list[0].date]: list[0], [list[1].date]: list[1] }, settings);
    const asMap = summarizeWeek(monday, new Map(list.map((e) => [e.date, e])), settings);
    const asArray = summarizeWeek(monday, list, settings);
    assert.deepEqual(asMap, asObject);
    assert.deepEqual(asArray, asObject);
    assert.equal(asObject.actualMinutes, 1200);
    assert.equal(weekProgress(asObject), 1);
    assert.equal(core.entryFor(list, monday), list[0]);
    assert.deepEqual(core.entryFor(list, plusDays(monday, 1)), createEntry(plusDays(monday, 1)));
  });

  test('Tageshöchstgrenze', () => {
    const day = evaluate(createEntry(monday, { start: t(7), end: t(18) }), settings);
    assert.equal(day.creditedMinutes, 615);
    assert.equal(day.exceedsDailyMax, true);
    assert.equal(dayDetail(day, settings, 0, false).dailyMaxWarning, DAILY_MAX_WARNING);
  });
});

describe('Formatierung und Eingaben', () => {
  test('parseHours verhält sich wie Kotlin', () => {
    assert.equal(parseHours('٨:٣٠'), 510); // toIntOrNull akzeptiert Unicode-Ziffern
    assert.equal(parseHours('+8:30'), 510);
    assert.equal(parseHours('8 : 30'), 510);
    assert.equal(parseHours('38.5d'), 2310);
    assert.equal(parseHours('0x1p3'), 480);
    assert.equal(parseHours('\u00A020\u00A0'), 1200);
    assert.equal(parseHours('1,5,5'), null);
    assert.equal(parseHours('NaN'), null);
    assert.equal(parseHours('Infinity'), null);
    assert.equal(parseHours('1:60'), null);
    assert.equal(parseHours('99999999999'), 2147483647);
    assert.ok(Object.is(parseHours('-0'), 0));
  });

  test('toIntOrNull', () => {
    assert.equal(core.toIntOrNull('2147483647'), 2147483647);
    assert.equal(core.toIntOrNull('2147483648'), null);
    assert.equal(core.toIntOrNull('-2147483648'), -2147483648);
    assert.equal(core.toIntOrNull('-'), null);
    assert.equal(core.toIntOrNull('1 '), null);
    assert.ok(Object.is(core.toIntOrNull('-0'), 0));
  });

  test('Datumstexte', () => {
    assert.equal(core.formatShortDate(monday), '28.09.');
    assert.equal(core.formatLongDate(monday), '28.09.2026');
    assert.equal(core.formatDateTime({ date: monday, minutes: t(9, 5), seconds: 30 }), '28.09.2026, 09:05');
    assert.equal(core.shortDayName(monday), 'Mo');
    assert.equal(core.dayEditTitle(monday), 'Montag, 28.09.2026');
  });
});

describe('Stempeln', () => {
  test('Kommen, Gehen, fertig', () => {
    const first = toggleClock(createEntry(monday), t(8, 1));
    assert.equal(first.action, 'CLOCK_IN');
    assert.deepEqual(first.entry, createEntry(monday, { start: t(8, 1) }));
    const second = toggleClock(first.entry, t(16, 30));
    assert.equal(second.action, 'CLOCK_OUT');
    assert.equal(second.entry.end, t(16, 30));
    assert.equal(toggleClock(second.entry, t(17)), null);
    assert.equal(toggleClock(createEntry(monday, { type: 'SICK' }), t(8)), null);
    assert.equal(core.CLOCK_ACTION_LABELS[first.action], 'Kommen');
  });
});

describe('Sicherung', () => {
  const entries = [
    createEntry(monday, { start: t(8), end: t(18, 45), manualBreakMinutes: 50 }),
    createEntry(plusDays(monday, 1), { type: 'VACATION' }),
    createEntry(plusDays(monday, 3), { start: t(22, 15) }),
  ];
  const settings = {
    weeklyTargetMinutes: 38 * 60 + 30,
    workDaysPerWeek: 5,
    weeklyHoursAreLimit: false,
    autoBreak: true,
    gradualDeduction: false,
    breakRules: [{ afterMinutes: 300, breakMinutes: 20 }, { afterMinutes: 600, breakMinutes: 60 }],
  };
  const createdAt = { date: '2026-09-30', minutes: t(14, 55), seconds: 12 };

  test('Sichern und Wiederherstellen ergibt dieselben Daten', () => {
    const data = parseBackup(createBackup(entries, settings, createdAt));
    assert.deepEqual(data.entries, entries);
    assert.deepEqual(data.settings, settings);
    assert.deepEqual(data.createdAt, createdAt);
  });

  test('Schlüssel in derselben Reihenfolge wie auf Android, leere Einträge fehlen, sortiert nach Datum', () => {
    const text = createBackup([entries[2], createEntry('2026-09-20'), entries[0]], settings, createdAt);
    const json = JSON.parse(text);
    assert.deepEqual(Object.keys(json), ['app', 'version', 'createdAt', 'settings', 'entries']);
    assert.deepEqual(Object.keys(json.settings),
      ['weeklyTargetMinutes', 'workDaysPerWeek', 'weeklyHoursAreLimit', 'autoBreak', 'gradualDeduction', 'breakRules']);
    assert.deepEqual(Object.keys(json.entries[0]), ['type', 'start', 'end', 'break', 'date']);
    assert.deepEqual(json.entries.map((e) => e.date), [monday, plusDays(monday, 3)]);
    assert.equal(json.createdAt, '2026-09-30T14:55:12');
    assert.ok(text.startsWith('{\n  "app": "Arbeitszeitrechner",\n  "version": 1,\n'));
  });

  test('Sicherung von Android (mit \\/ und Leerraum) lässt sich lesen', () => {
    const text = '\uFEFF\n{"app":"Arbeitszeitrechner","version":1,"createdAt":"2026-09-30T08:00",' +
      '"note":"a\\/b","entries":[{"type":"WORK","start":"08:00","end":"16:30","break":0,"date":"2026-09-28"}]}\n ';
    const data = parseBackup(text);
    assert.deepEqual(data.entries, [createEntry(monday, { start: t(8), end: t(16, 30) })]);
    assert.equal(data.settings, null);
  });

  test('nachsichtig wie org.json', () => {
    const data = parseBackup(JSON.stringify({
      app: 'Arbeitszeitrechner',
      settings: {
        weeklyTargetMinutes: '600', workDaysPerWeek: 0, weeklyHoursAreLimit: 'FALSE', autoBreak: 1,
        breakRules: [null, { after: 480.9, break: '15' }],
      },
      entries: [
        { date: monday, start: '25:00' },
        { date: plusDays(monday, 1), type: 'work', break: '30' },
        { date: plusDays(monday, 2), type: 'SICK', start: '08:00' },
        'kein Objekt',
        { date: plusDays(monday, 4), start: null, end: '', break: 7.9 },
      ],
    }));
    assert.deepEqual(data.settings, {
      weeklyTargetMinutes: 600,
      workDaysPerWeek: 1,
      weeklyHoursAreLimit: false,
      autoBreak: true,
      gradualDeduction: true,
      breakRules: [{ afterMinutes: 360, breakMinutes: 30 }, { afterMinutes: 480, breakMinutes: 15 }],
    });
    assert.deepEqual(data.entries, [
      createEntry(plusDays(monday, 1), { manualBreakMinutes: 30 }),
      createEntry(plusDays(monday, 2), { type: 'SICK', start: t(8) }),
      createEntry(plusDays(monday, 4), { manualBreakMinutes: 7 }),
    ]);
    assert.equal(data.createdAt, null);
    assert.deepEqual(parseBackup('{"app":"Arbeitszeitrechner","entries":{},"settings":[]}'),
      { createdAt: null, settings: null, entries: [] });
  });

  test('fremde Dateien werden abgelehnt', () => {
    for (const text of ['[]', 'null', '"Arbeitszeitrechner"', '{"app":"Andere"}', '{"app":1}', '{', undefined]) {
      assert.throws(() => parseBackup(text), (error) => {
        assert.ok(error instanceof BackupFormatError);
        assert.equal(error.message, BACKUP_ERROR_MESSAGE);
        return true;
      }, String(text));
    }
  });

  test('Einträge einzeln speichern und lesen', () => {
    assert.deepEqual(encodeEntry(entries[0]), { type: 'WORK', start: '08:00', end: '18:45', break: 50 });
    assert.deepEqual(encodeEntry(entries[1]), { type: 'VACATION', break: 0 });
    assert.deepEqual(decodeEntry(monday, encodeEntry(entries[0])), entries[0]);
    assert.equal(decodeEntry('2026-02-30', { type: 'WORK' }), null);
    assert.equal(decodeEntry(monday, { start: 'abc' }), null);
    assert.deepEqual(entryFromJson(entryToJson(entries[2])), entries[2]);
    assert.equal(entryFromJson({ date: 'kaputt' }), null);
  });

  test('Wiederherstellen: gleiche Tage ersetzen, leere löschen, Rest bleibt', () => {
    const existing = {
      [monday]: createEntry(monday, { start: t(9), end: t(17) }),
      [plusDays(monday, 1)]: createEntry(plusDays(monday, 1), { start: t(9), end: t(12) }),
      [plusDays(monday, 2)]: createEntry(plusDays(monday, 2), { type: 'HOLIDAY' }),
    };
    const data = {
      createdAt: null,
      settings: null,
      entries: [
        createEntry(monday, { start: t(8), end: t(16) }),
        createEntry(plusDays(monday, 1)),
        createEntry(plusDays(monday, 5), { type: 'SICK' }),
      ],
    };
    const expected = {
      [monday]: data.entries[0],
      [plusDays(monday, 2)]: existing[plusDays(monday, 2)],
      [plusDays(monday, 5)]: data.entries[2],
    };
    assert.deepEqual(mergeBackup(existing, data), expected);
    assert.deepEqual(mergeBackup(new Map(Object.entries(existing)), data), expected);
    assert.ok(existing[plusDays(monday, 1)], 'Eingabe bleibt unverändert');
    assert.deepEqual(applyBackup(existing, settings, data).settings, settings);
    assert.deepEqual(applyBackup(existing, settings, { ...data, settings: defaultSettings() }).settings, defaultSettings());
  });

  test('Monatsexport über MonthExport', () => {
    assert.equal(MonthExport.fileName('2026-09'), 'Arbeitszeit-2026-09.csv');
    assert.deepEqual(MonthExport.summary('2026-09', entries, settings), monthSummary('2026-09', entries, settings));
    assert.equal(monthSummaryText(monthSummary('2026-02', entries, settings)), 'Keine Einträge in diesem Monat.');
    const summary = monthSummary('2026-09', entries, defaultSettings());
    assert.equal(monthSummaryText(summary),
      '9:55 h an 1 Arbeitstagen, dazu 10:00 h Urlaub/Krank/Feiertag (gesamt 19:55 h)');
  });
});

describe('Texte der Oberfläche', () => {
  const settings = defaultSettings();

  test('Tageskarten', () => {
    const empty = evaluate(createEntry(monday), settings);
    assert.equal(dayValueText(empty), '–');
    assert.deepEqual(dayDetail(empty, settings, 0, false),
      { text: 'Kein Eintrag – tippen zum Erfassen', tone: 'normal', dailyMaxWarning: null });

    const done = evaluate(createEntry(monday, { start: t(8), end: t(16, 30) }), settings);
    assert.equal(dayValueText(done), '8:00 h');
    assert.equal(dayDetail(done, settings, 0, false).text, '08:00 – 16:30 · Pause 0:30 h (auto)');

    const running = evaluate(createEntry(monday, { start: t(8) }), settings, { date: monday, minutes: t(9), seconds: 0 });
    assert.deepEqual(dayDetail(running, settings, 600, false),
      { text: 'seit 08:00 · Pause 0:00 h\n20 h voll um 18:45', tone: 'running', dailyMaxWarning: null });
    assert.equal(dayDetail(running, settings, 600, true).tone, 'warning');
    assert.equal(dayDetail(running, settings, 1200, false).text, 'seit 08:00 · Pause 0:00 h\n20 h sind schon voll – nicht weiterarbeiten');

    assert.equal(dayDetail(evaluate(createEntry(monday, { end: t(16) }), settings), settings, 0, false).text,
      'Ende 16:00 · Beginn fehlt');
    assert.equal(dayDetail(evaluate(createEntry(monday, { type: 'SICK' }), settings), settings, 0, false).text,
      'Krank · Tagessoll gutgeschrieben');
    assert.equal(core.dayTitle(monday, true), 'Montag · Heute');
    assert.equal(core.clockButtonText(createEntry(monday), true), 'Kommen – jetzt einstempeln');
    assert.equal(core.clockButtonText(createEntry(monday, { start: t(8) }), true), 'Gehen – jetzt ausstempeln');
    assert.equal(core.clockButtonText(createEntry(monday), false), null);
  });

  test('Wochenkarte', () => {
    const over = summarizeWeek(monday, [
      createEntry(monday, { start: t(8), end: t(18, 45) }),
      createEntry(plusDays(monday, 1), { start: t(8), end: t(9) }),
      createEntry(plusDays(monday, 3), { start: t(8), end: t(18, 45) }),
    ], settings);
    assert.deepEqual(weekBalanceStat(over, true), { label: 'Grenze überschritten', value: '+1:00 h', tone: 'negative' });
    assert.deepEqual(weekBalanceStat(over, false), { label: 'Überstunden', value: '+1:00 h', tone: 'positive' });
    assert.equal(core.isLimitExceeded(over, true), true);
    const open = summarizeWeek(monday, {}, settings);
    assert.deepEqual(weekBalanceStat(open, true), { label: 'Bis zur Grenze', value: '20:00 h', tone: 'neutral' });
    assert.deepEqual(weekBalanceStat(open, false), { label: 'Noch offen', value: '20:00 h', tone: 'neutral' });
    assert.equal(weekProgress(open), 0);
    assert.equal(core.weekShareSubject(open), 'Arbeitszeit KW 40');
    assert.equal(core.breakHintText(settings),
      'Pausen werden automatisch abgezogen (mehr als 6 h → 30 min, mehr als 9 h → 45 min). ' +
      'Eine längere eingetragene Pause hat Vorrang.');
    assert.equal(core.initialExportMonth(monday, '2026-10-02'), '2026-10');
    assert.equal(core.initialExportMonth(monday, '2026-10-12'), '2026-09');
  });

  test('Tag bearbeiten', () => {
    assert.equal(core.filterBreakInput('4a5١٢'), '45١');
    assert.deepEqual(draftEntry(monday, 'WORK', t(8), t(16), '45'),
      createEntry(monday, { start: t(8), end: t(16), manualBreakMinutes: 45 }));
    assert.deepEqual(draftEntry(monday, 'WORK', t(8), null, ''), createEntry(monday, { start: t(8) }));
    assert.deepEqual(draftEntry(monday, 'HOLIDAY', t(8), t(16), '45'), createEntry(monday, { type: 'HOLIDAY' }));
    assert.equal(core.absenceCreditText('VACATION', settings), 'Urlaub: Es werden 10:00 h (Tagessoll) gutgeschrieben.');
    const now = { date: monday, minutes: t(9, 12), seconds: 40 };
    assert.equal(defaultStartTime(monday, now), t(9, 12));
    assert.equal(defaultStartTime(plusDays(monday, 1), now), t(8));
    assert.equal(defaultEndTime(plusDays(monday, 1), null, 0, settings, now), t(18, 45));
    assert.equal(defaultEndTime(monday, t(7), 0, settings, now), t(9, 12));
  });

  test('Einstellungen prüfen', () => {
    const form = settingsForm(settings);
    assert.deepEqual(form, {
      weeklyText: '20', daysText: '2', isLimit: true, autoBreak: true, gradual: true,
      rule1After: '6', rule1Break: '30', rule2After: '9', rule2Break: '45',
    });
    const valid = validateSettingsForm({ ...form, weeklyText: '38:30', daysText: '5', isLimit: false }, settings);
    assert.equal(valid.valid, true);
    assert.equal(valid.weeklyHint, 'Tagessoll: 7:42 h');
    assert.deepEqual(valid.settings, { ...settings, weeklyTargetMinutes: 2310, workDaysPerWeek: 5, weeklyHoursAreLimit: false });

    const invalid = validateSettingsForm({ ...form, weeklyText: 'abc' }, settings);
    assert.equal(invalid.valid, false);
    assert.equal(invalid.settings, null);
    assert.equal(invalid.weeklyHint, 'Bitte z. B. 40, 38,5 oder 38:30 eingeben');
    assert.equal(validateSettingsForm({ ...form, daysText: '8' }, settings).valid, false);
    assert.equal(validateSettingsForm({ ...form, rule1Break: '601' }, settings).valid, false);

    const noBreaks = validateSettingsForm({ ...form, autoBreak: false, rule1After: 'x' }, settings);
    assert.equal(noBreaks.valid, true);
    assert.deepEqual(noBreaks.settings.breakRules, settings.breakRules);
    assert.deepEqual(core.resetBreakRulesForm({ ...form, rule1After: '5', gradual: false }), form);
  });

  test('Backup-Dialog', () => {
    assert.equal(restoreSummaryText({ createdAt: { date: '2026-09-30', minutes: t(14, 55), seconds: 12 }, entries: [1, 2] }),
      'Sicherung vom 30.09.2026, 14:55 mit 2 Einträgen. Einträge für dieselben Tage werden überschrieben, ' +
      'alle anderen bleiben erhalten. Die Einstellungen werden übernommen.');
    assert.ok(restoreSummaryText({ createdAt: null, entries: [] }).startsWith('Sicherung mit 0 Einträgen.'));
    assert.equal(core.backupFileName('2026-10-09'), 'Arbeitszeit-Backup-2026-10-09.json');
  });
});

describe('Service Worker', () => {
  const web = new URL('../', import.meta.url);
  const source = readFileSync(new URL('sw.js', web), 'utf8');
  const files = [.../const FILES = \[([^\]]*)\]/.exec(source)[1].matchAll(/'\.\/([^']+)'/g)].map((match) => match[1]);

  /** Alle Dateien, die veröffentlicht werden (wie im Workflow ohne test/, package.json und .gitignore). */
  function appFiles(dir = '') {
    const result = [];
    for (const entry of readdirSync(new URL(dir || '.', web), { withFileTypes: true })) {
      const path = dir + entry.name;
      if (entry.isDirectory()) {
        if (!['test', 'node_modules'].includes(path)) result.push(...appFiles(`${path}/`));
      } else if (!['package.json', '.gitignore', 'sw.js'].includes(path)) {
        result.push(path);
      }
    }
    return result;
  }

  test('FILES enthält alle Dateien der App', () => {
    assert.deepEqual([...files].sort(), appFiles().sort());
  });

  test('VERSION passt zu den Dateien – sonst laden installierte Geräte die Änderung nie', () => {
    const hash = createHash('sha256');
    for (const file of files) {
      const bytes = readFileSync(new URL(file, web));
      // Zeilenenden wie im Repository, damit die Prüfsumme auch unter Windows stimmt
      hash.update(`${file}\n`).update(file.endsWith('.png') ? bytes : bytes.toString('utf8').replace(/\r\n/g, '\n'));
    }
    const expected = hash.digest('hex').slice(0, 12);
    assert.equal(/^const VERSION = '([^']*)';$/m.exec(source)?.[1], expected, `In sw.js eintragen: const VERSION = '${expected}';`);
  });
});
