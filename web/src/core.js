// Arbeitszeitrechner – plattformunabhängige Logik der Web-App.
//
// Portierung der Android-Implementierung (app/src/main/java/de/arbeitszeitrechner). Ergebnisse und
// Texte müssen Zeichen für Zeichen übereinstimmen; geprüft wird gegen shared/test-vectors.json.
//
// Datenmodell:
//   Datum          "YYYY-MM-DD", Monat "YYYY-MM"
//   Uhrzeit        Minuten seit Mitternacht (0..1439) oder null
//   Zeitpunkt      { date, minutes, seconds } – entspricht java.time.LocalDateTime
//   Eintrag        { date, type, start, end, manualBreakMinutes }
//   Einstellungen  { weeklyTargetMinutes, workDaysPerWeek, weeklyHoursAreLimit, autoBreak,
//                    gradualDeduction, breakRules: [{ afterMinutes, breakMinutes }] }
//   Einträge       Objekt { "YYYY-MM-DD": Eintrag }, Map oder Array von Einträgen
//
// Datumsrechnung nur mit Ganzzahlen (ohne Date), damit Zeitzonen und Sommerzeit keine Rolle spielen.

const INT_MAX = 2147483647;
const INT_MIN = -2147483648;
const MINUTES_PER_DAY = 24 * 60;

function floorMod(value, divisor) {
  return ((value % divisor) + divisor) % divisor;
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function pad(value, width) {
  // Wie "%0Nd" in Java: das Minuszeichen zählt zur Breite.
  const digits = String(Math.abs(value));
  return value < 0 ? '-' + digits.padStart(width - 1, '0') : digits.padStart(width, '0');
}

// ---------------------------------------------------------------------------------------------
// Verhalten von Kotlin/Java nachgebildet (Eingaben prüfen wie in der Android-App)
// ---------------------------------------------------------------------------------------------

const KOTLIN_WHITESPACE = /[\t\n\v\f\r\x1C-\x1F\p{Zs}\p{Zl}\p{Zp}]/u;
const DECIMAL_DIGIT = /\p{Nd}/u;

/** String.trim() aus Kotlin – kennt andere Leerzeichen als String.prototype.trim(). */
export function ktTrim(text) {
  let start = 0;
  let end = text.length;
  while (start < end && KOTLIN_WHITESPACE.test(text[start])) start++;
  while (end > start && KOTLIN_WHITESPACE.test(text[end - 1])) end--;
  return text.slice(start, end);
}

/** Char.isDigit() aus Kotlin: jede Unicode-Dezimalziffer. */
export function isDigitChar(char) {
  return DECIMAL_DIGIT.test(char);
}

/** Behält nur Ziffern, höchstens [maxLength] (wie text.filter(Char::isDigit).take(n)). */
export function digitsOnly(text, maxLength = Infinity) {
  let result = '';
  for (let i = 0; i < text.length && result.length < maxLength; i++) {
    if (isDigitChar(text[i])) result += text[i];
  }
  return result;
}

function digitValue(char) {
  const code = char.charCodeAt(0);
  if (code >= 48 && code <= 57) return code - 48;
  if (!DECIMAL_DIGIT.test(char)) return -1;
  // Unicode-Ziffern liegen in Blöcken 0..9 hintereinander.
  let first = code;
  while (DECIMAL_DIGIT.test(String.fromCharCode(first - 1))) first--;
  return (code - first) % 10;
}

/** String.toIntOrNull() aus Kotlin: optionales Vorzeichen, nur Ziffern, null bei Überlauf. */
export function toIntOrNull(text) {
  const length = text.length;
  if (length === 0) return null;
  let index = 0;
  let negative = false;
  if (text.charCodeAt(0) < 48) {
    if (length === 1) return null;
    if (text[0] === '-') negative = true;
    else if (text[0] !== '+') return null;
    index = 1;
  }
  const limit = negative ? -INT_MIN : INT_MAX;
  let value = 0;
  for (; index < length; index++) {
    const digit = digitValue(text[index]);
    if (digit < 0) return null;
    value = value * 10 + digit;
    if (value > limit) return null;
  }
  return negative ? 0 - value : value;
}

// Muster aus der Javadoc von Double.valueOf, das Kotlin für toDoubleOrNull() verwendet.
const FLOAT_PATTERN =
  /^[\x00-\x20]*[+-]?(?:NaN|Infinity|(?:\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?|0[xX](?:[0-9a-fA-F]+\.?|[0-9a-fA-F]*\.[0-9a-fA-F]+)[pP][+-]?\d+)[fFdD]?)[\x00-\x20]*$/;

/** String.toDoubleOrNull() aus Kotlin. */
export function toDoubleOrNull(text) {
  if (!FLOAT_PATTERN.test(text)) return null;
  let value = text.replace(/^[\x00-\x20]+|[\x00-\x20]+$/g, '');
  let sign = 1;
  if (value[0] === '+' || value[0] === '-') {
    if (value[0] === '-') sign = -1;
    value = value.slice(1);
  }
  if (value === 'NaN') return NaN;
  if (value === 'Infinity') return sign * Infinity;
  value = value.replace(/[fFdD]$/, '');
  const hex = /^0[xX]([0-9a-fA-F]*)\.?([0-9a-fA-F]*)[pP]([+-]?\d+)$/.exec(value);
  if (hex) {
    return sign * parseInt(hex[1] + hex[2], 16) * Math.pow(2, Number(hex[3]) - 4 * hex[2].length);
  }
  return sign * Number(value);
}

/** Double.roundToInt() aus Kotlin (kaufmännisch, begrenzt auf den Int-Bereich). */
function roundToInt(value) {
  if (value > INT_MAX) return INT_MAX;
  if (value < INT_MIN) return INT_MIN;
  return Math.round(value) + 0;
}

// ---------------------------------------------------------------------------------------------
// Datum und Uhrzeit
// ---------------------------------------------------------------------------------------------

/** Tage seit 1970-01-01 (Algorithmus "days from civil" von H. Hinnant). */
function daysFromCivil(year, month, day) {
  const y = month <= 2 ? year - 1 : year;
  const era = Math.floor(y / 400);
  const yearOfEra = y - era * 400;
  const dayOfYear = Math.floor((153 * ((month + 9) % 12) + 2) / 5) + day - 1;
  const dayOfEra = yearOfEra * 365 + Math.floor(yearOfEra / 4) - Math.floor(yearOfEra / 100) + dayOfYear;
  return era * 146097 + dayOfEra - 719468;
}

function civilFromDays(epochDay) {
  const z = epochDay + 719468;
  const era = Math.floor(z / 146097);
  const dayOfEra = z - era * 146097;
  const yearOfEra = Math.floor(
    (dayOfEra - Math.floor(dayOfEra / 1460) + Math.floor(dayOfEra / 36524) - Math.floor(dayOfEra / 146096)) / 365,
  );
  const dayOfYear = dayOfEra - (365 * yearOfEra + Math.floor(yearOfEra / 4) - Math.floor(yearOfEra / 100));
  const mp = Math.floor((5 * dayOfYear + 2) / 153);
  const day = dayOfYear - Math.floor((153 * mp + 2) / 5) + 1;
  const month = mp < 10 ? mp + 3 : mp - 9;
  return { year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day };
}

function isLeapYear(year) {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

function daysInMonth(year, month) {
  if (month === 2) return isLeapYear(year) ? 29 : 28;
  return month === 4 || month === 6 || month === 9 || month === 11 ? 30 : 31;
}

function formatDate(year, month, day) {
  return `${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}`;
}

function dateParts(date) {
  return { year: Number(date.slice(0, 4)), month: Number(date.slice(5, 7)), day: Number(date.slice(8, 10)) };
}

/** Prüft ein Datum streng wie LocalDate.parse ("YYYY-MM-DD"). Liefert das Datum oder null. */
export function parseDate(text) {
  if (typeof text !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
  return text;
}

export function toEpochDay(date) {
  const { year, month, day } = dateParts(date);
  return daysFromCivil(year, month, day);
}

export function fromEpochDay(epochDay) {
  const { year, month, day } = civilFromDays(epochDay);
  return formatDate(year, month, day);
}

export function plusDays(date, days) {
  return fromEpochDay(toEpochDay(date) + days);
}

/** Tage von [from] bis [to] (positiv, wenn [to] später ist). */
export function daysBetween(from, to) {
  return toEpochDay(to) - toEpochDay(from);
}

/** 1 = Montag … 7 = Sonntag */
export function dayOfWeek(date) {
  return floorMod(toEpochDay(date) + 3, 7) + 1;
}

export function weekStartOf(date) {
  return plusDays(date, -(dayOfWeek(date) - 1));
}

/** Kalenderwoche nach ISO 8601 (wie IsoFields.WEEK_OF_WEEK_BASED_YEAR). */
export function isoWeek(date) {
  const epochDay = toEpochDay(date);
  const thursday = epochDay - dayOfWeek(date) + 4;
  const { year } = civilFromDays(thursday);
  return Math.floor((thursday - daysFromCivil(year, 1, 1)) / 7) + 1;
}

/** Kalenderwoche einer Woche (wie weekNumber in Texts.kt). */
export function weekNumber(weekStart) {
  return isoWeek(weekStart);
}

/** Prüft einen Monat "YYYY-MM" (wie YearMonth.parse). Liefert den Monat oder null. */
export function parseYearMonth(text) {
  if (typeof text !== 'string') return null;
  const match = /^(\d{4})-(\d{2})$/.exec(text);
  if (!match || Number(match[2]) < 1 || Number(match[2]) > 12) return null;
  return text;
}

/** Monat "YYYY-MM" eines Datums (oder eines Monats). */
export function yearMonthOf(date) {
  return date.slice(0, 7);
}

export function plusMonths(month, months) {
  const total = Number(month.slice(0, 4)) * 12 + Number(month.slice(5, 7)) - 1 + months;
  return `${pad(Math.floor(total / 12), 4)}-${pad(floorMod(total, 12) + 1, 2)}`;
}

export function lengthOfMonth(month) {
  return daysInMonth(Number(month.slice(0, 4)), Number(month.slice(5, 7)));
}

/** Alle Tage eines Monats "YYYY-MM" als Datum. */
export function datesOfMonth(month) {
  const year = Number(month.slice(0, 4));
  const monthValue = Number(month.slice(5, 7));
  const dates = [];
  for (let day = 1; day <= daysInMonth(year, monthValue); day++) dates.push(formatDate(year, monthValue, day));
  return dates;
}

const TIME_PATTERN = /^(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{0,9})?)?$/;

function parseTimeParts(text) {
  const match = TIME_PATTERN.exec(text);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  const second = match[3] === undefined ? 0 : Number(match[3]);
  if (hour > 23 || minute > 59 || second > 59) return null;
  return { minutes: hour * 60 + minute, seconds: second };
}

/**
 * Uhrzeit streng wie LocalTime.parse ("HH:mm", "HH:mm:ss" oder mit Sekundenbruchteil).
 * Liefert Minuten seit Mitternacht (Sekunden werden abgeschnitten) oder null.
 */
export function parseTime(text) {
  if (typeof text !== 'string') return null;
  const parts = parseTimeParts(text);
  return parts ? parts.minutes : null;
}

/** 545 -> "09:05" */
export function formatTime(minutes) {
  const value = floorMod(minutes, MINUTES_PER_DAY);
  return `${pad(Math.floor(value / 60), 2)}:${pad(value % 60, 2)}`;
}

/** Zeitpunkt wie LocalDateTime.parse ("YYYY-MM-DDTHH:mm[:ss]"). Liefert { date, minutes, seconds } oder null. */
export function parseLocalDateTime(text) {
  if (typeof text !== 'string') return null;
  const match = /^(\d{4}-\d{2}-\d{2})[Tt](.+)$/.exec(text);
  if (!match || parseDate(match[1]) == null) return null;
  const time = parseTimeParts(match[2]);
  return time ? { date: match[1], minutes: time.minutes, seconds: time.seconds } : null;
}

/** Wie LocalDateTime.toString(): "2026-09-30T14:55", mit Sekunden nur wenn nicht 0. */
export function formatLocalDateTime(dateTime) {
  const seconds = dateTime.seconds || 0;
  return `${dateTime.date}T${formatTime(dateTime.minutes)}` + (seconds !== 0 ? `:${pad(seconds, 2)}` : '');
}

/** Aktueller Zeitpunkt in lokaler Zeit. */
export function nowLocalDateTime(now = new Date()) {
  return {
    date: formatDate(now.getFullYear(), now.getMonth() + 1, now.getDate()),
    minutes: now.getHours() * 60 + now.getMinutes(),
    seconds: now.getSeconds(),
  };
}

/** Heutiges Datum in lokaler Zeit. */
export function today(now = new Date()) {
  return nowLocalDateTime(now).date;
}

/** Aktuelle Uhrzeit auf Minuten abgeschnitten (zum Stempeln). */
export function currentTime(now = new Date()) {
  return nowLocalDateTime(now).minutes;
}

// ---------------------------------------------------------------------------------------------
// Datenmodell
// ---------------------------------------------------------------------------------------------

export const DayType = Object.freeze({ WORK: 'WORK', VACATION: 'VACATION', SICK: 'SICK', HOLIDAY: 'HOLIDAY' });

/** Reihenfolge wie in der Android-App (Auswahl im Tag-Dialog). */
export const DAY_TYPES = Object.freeze([DayType.WORK, DayType.VACATION, DayType.SICK, DayType.HOLIDAY]);

export const DAY_TYPE_LABELS = Object.freeze({ WORK: 'Arbeit', VACATION: 'Urlaub', SICK: 'Krank', HOLIDAY: 'Feiertag' });

export function dayTypeLabel(type) {
  return DAY_TYPE_LABELS[type];
}

/** Abwesenheitstage werden mit der täglichen Sollzeit gutgeschrieben. */
export function isAbsence(type) {
  return type !== DayType.WORK;
}

export function createEntry(date, fields = {}) {
  return {
    date,
    type: fields.type ?? DayType.WORK,
    start: fields.start ?? null,
    end: fields.end ?? null,
    manualBreakMinutes: fields.manualBreakMinutes ?? 0,
  };
}

export function isEmptyEntry(entry) {
  return entry.type === DayType.WORK && entry.start == null && entry.end == null && entry.manualBreakMinutes === 0;
}

/** § 4 Arbeitszeitgesetz: > 6 h -> 30 min, > 9 h -> 45 min. */
export const DEFAULT_BREAK_RULES = Object.freeze([
  Object.freeze({ afterMinutes: 6 * 60, breakMinutes: 30 }),
  Object.freeze({ afterMinutes: 9 * 60, breakMinutes: 45 }),
]);

/** Standard: Werkstudent mit 20 h an 2 Tagen pro Woche, 20 h als Obergrenze. */
export function defaultSettings() {
  return {
    weeklyTargetMinutes: 20 * 60,
    workDaysPerWeek: 2,
    weeklyHoursAreLimit: true,
    autoBreak: true,
    gradualDeduction: true,
    breakRules: DEFAULT_BREAK_RULES.map((rule) => ({ afterMinutes: rule.afterMinutes, breakMinutes: rule.breakMinutes })),
  };
}

export function dailyTargetMinutes(settings) {
  return Math.trunc(settings.weeklyTargetMinutes / clamp(settings.workDaysPerWeek, 1, 7));
}

function entryLookup(entries) {
  if (entries == null) return () => undefined;
  if (entries instanceof Map) return (date) => entries.get(date);
  if (Array.isArray(entries)) {
    const byDate = new Map();
    for (const entry of entries) byDate.set(entry.date, entry);
    return (date) => byDate.get(date);
  }
  return (date) => (Object.prototype.hasOwnProperty.call(entries, date) ? entries[date] : undefined);
}

function entryList(entries) {
  if (entries == null) return [];
  if (entries instanceof Map) return Array.from(entries.values());
  if (Array.isArray(entries)) return entries.slice();
  return Object.keys(entries).map((key) => entries[key]);
}

/** Eintrag für [date] aus [entries] oder ein leerer Eintrag. */
export function entryFor(entries, date) {
  return entryLookup(entries)(date) ?? createEntry(date);
}

// ---------------------------------------------------------------------------------------------
// Pausen
// ---------------------------------------------------------------------------------------------

/** Mindestpause in Minuten für eine Anwesenheit von [attendanceMinutes]. */
export function requiredBreak(attendanceMinutes, settings) {
  if (!settings.autoBreak || attendanceMinutes <= 0) return 0;
  let result = 0;
  for (const rule of settings.breakRules) {
    if (rule.breakMinutes <= 0) continue;
    if (settings.gradualDeduction) {
      // Jede Regel ist erfüllt, wenn entweder die volle Pause gemacht wurde oder die
      // Arbeitszeit (Anwesenheit - Pause) die Schwelle nicht überschreitet.
      result = Math.max(result, Math.min(rule.breakMinutes, Math.max(attendanceMinutes - rule.afterMinutes, 0)));
    } else if (attendanceMinutes > rule.afterMinutes) {
      result = Math.max(result, rule.breakMinutes);
    }
  }
  return result;
}

/** Tatsächlich abgezogene Pause: die eingetragene Pause, aber mindestens die gesetzliche. */
export function deductedBreak(attendanceMinutes, manualBreakMinutes, settings) {
  const manual = Math.max(manualBreakMinutes, 0);
  return Math.min(Math.max(manual, requiredBreak(attendanceMinutes, settings)), Math.max(attendanceMinutes, 0));
}

// ---------------------------------------------------------------------------------------------
// Tages- und Wochenberechnung
// ---------------------------------------------------------------------------------------------

/** § 3 ArbZG: höchstens 10 Stunden Arbeitszeit pro Tag. */
export const MAX_DAILY_WORK_MINUTES = 10 * 60;

/** Minuten von [start] bis [end]; liegt das Ende vor dem Beginn, geht die Schicht über Mitternacht. */
export function attendanceMinutes(start, end) {
  const minutes = end - start;
  return minutes < 0 ? minutes + MINUTES_PER_DAY : minutes;
}

function dayResult(entry, values) {
  const result = {
    entry,
    attendanceMinutes: 0,
    breakMinutes: 0,
    autoBreakApplied: false,
    creditedMinutes: 0,
    running: false,
    ...values,
  };
  result.exceedsDailyMax = !isAbsence(entry.type) && result.creditedMinutes > MAX_DAILY_WORK_MINUTES;
  return result;
}

/**
 * Ergebnis eines Tages. [now] ({ date, minutes, seconds } oder null): Ist heute nur der Beginn
 * eingetragen, zählt die Zeit bis jetzt (running = true).
 */
export function evaluate(entry, settings, now = null) {
  if (isAbsence(entry.type)) return dayResult(entry, { creditedMinutes: dailyTargetMinutes(settings) });
  const start = entry.start;
  if (start == null) return dayResult(entry);
  const running = entry.end == null && now != null && now.date === entry.date;
  if (entry.end == null && !running) return dayResult(entry);
  const attendance = running ? Math.max(now.minutes - start, 0) : attendanceMinutes(start, entry.end);
  const breakMinutes = deductedBreak(attendance, entry.manualBreakMinutes, settings);
  return dayResult(entry, {
    attendanceMinutes: attendance,
    breakMinutes,
    autoBreakApplied: breakMinutes > entry.manualBreakMinutes,
    creditedMinutes: attendance - breakMinutes,
    running,
  });
}

/** Woche ab [weekStart] (Montag): days enthält die Ergebnisse Mo..So. */
export function summarizeWeek(weekStart, entries, settings, now = null) {
  const lookup = entryLookup(entries);
  const days = [];
  for (let offset = 0; offset < 7; offset++) {
    const date = plusDays(weekStart, offset);
    days.push(evaluate(lookup(date) ?? createEntry(date), settings, now));
  }
  let actualMinutes = 0;
  let breakMinutes = 0;
  for (const day of days) {
    actualMinutes += day.creditedMinutes;
    breakMinutes += day.breakMinutes;
  }
  return {
    weekStart,
    days,
    actualMinutes,
    targetMinutes: settings.weeklyTargetMinutes,
    breakMinutes,
    balanceMinutes: actualMinutes - settings.weeklyTargetMinutes,
  };
}

/** Angerechnete Minuten aller anderen Tage der Woche (ohne [date]). */
export function minutesExcluding(summary, date) {
  let sum = 0;
  for (const day of summary.days) if (day.entry.date !== date) sum += day.creditedMinutes;
  return sum;
}

export const GoalKind = Object.freeze({
  /** Die Wochenstunden sind heute um `at` voll. */
  WEEK_FULL: 'weekFull',
  /** Die Wochenstunden sind schon durch die anderen Tage voll. */
  WEEK_ALREADY_FULL: 'weekAlreadyFull',
  /** Die Woche wird heute nicht voll (höchstens 10 h pro Tag); um `at` ist das Tagessoll erreicht. */
  DAILY_TARGET: 'dailyTarget',
});

/**
 * Bis wann heute gearbeitet werden muss (bzw. darf): Lassen sich die restlichen Wochenstunden heute
 * schaffen, zählt der Zeitpunkt, an dem die Woche voll ist – sonst das Tagessoll.
 * [otherDaysMinutes] sind die angerechneten Minuten der übrigen Tage dieser Woche.
 * Liefert null (kein Beginn), { kind: 'weekAlreadyFull' } oder { kind: 'weekFull' | 'dailyTarget', at }.
 */
export function todayGoal(entry, otherDaysMinutes, settings) {
  const start = entry.start;
  if (start == null) return null;
  const remaining = settings.weeklyTargetMinutes - otherDaysMinutes;
  if (remaining <= 0) return { kind: GoalKind.WEEK_ALREADY_FULL };
  if (remaining <= MAX_DAILY_WORK_MINUTES) {
    return { kind: GoalKind.WEEK_FULL, at: endTimeForTarget(start, entry.manualBreakMinutes, remaining, settings) };
  }
  return {
    kind: GoalKind.DAILY_TARGET,
    at: endTimeForTarget(start, entry.manualBreakMinutes, dailyTargetMinutes(settings), settings),
  };
}

/**
 * Uhrzeit, zu der bei Beginn um [start] die Sollzeit [targetMinutes] netto erreicht ist,
 * inklusive der automatisch abgezogenen Pause.
 */
export function endTimeForTarget(start, manualBreakMinutes, targetMinutes, settings) {
  let attendance = Math.max(targetMinutes, 0);
  while (
    attendance - deductedBreak(attendance, manualBreakMinutes, settings) < targetMinutes &&
    attendance < targetMinutes + MINUTES_PER_DAY
  ) {
    attendance++;
  }
  return floorMod(start + attendance, MINUTES_PER_DAY);
}

// ---------------------------------------------------------------------------------------------
// Formatierung
// ---------------------------------------------------------------------------------------------

/** 510 -> "8:30", -90 -> "−1:30" (mit echtem Minuszeichen U+2212) */
export function formatDuration(minutes) {
  const sign = minutes < 0 ? '\u2212' : '';
  const value = Math.abs(minutes);
  return `${sign}${Math.floor(value / 60)}:${pad(value % 60, 2)}`;
}

/** Wie formatDuration, aber mit "+" bei positiven Werten. */
export function formatBalance(minutes) {
  return minutes > 0 ? '+' + formatDuration(minutes) : formatDuration(minutes);
}

/** Akzeptiert "40", "38,5", "38.5" und "38:30". Liefert Minuten oder null. */
export function parseHours(text) {
  const trimmed = ktTrim(text);
  if (trimmed === '') return null;
  if (trimmed.indexOf(':') >= 0) {
    const parts = trimmed.split(':');
    if (parts.length !== 2) return null;
    const hours = toIntOrNull(ktTrim(parts[0]));
    const minutes = toIntOrNull(ktTrim(parts[1]));
    if (hours == null || minutes == null) return null;
    if (hours < 0 || minutes < 0 || minutes > 59) return null;
    return (Math.imul(hours, 60) + minutes) | 0;
  }
  const value = toDoubleOrNull(trimmed.split(',').join('.'));
  if (value == null || value < 0 || !Number.isFinite(value)) return null;
  return roundToInt(value * 60);
}

/** 480 -> "8", 510 -> "8,5", 505 -> "8:25" */
export function formatHoursInput(minutes) {
  const hours = Math.trunc(minutes / 60);
  if (minutes % 60 === 0) return String(hours + 0);
  if (minutes % 30 === 0) return `${hours + 0},5`;
  return `${hours + 0}:${pad(minutes % 60, 2)}`;
}

/** 615 -> "10,25" (Dezimalstunden, z. B. für die Lohnabrechnung) */
export function formatDecimalHours(minutes) {
  // Minuten / 60 liegt nie genau auf einer Rundungsgrenze, daher entspricht toFixed dem HALF_UP von Java.
  return (minutes / 60).toFixed(2).replace('.', ',');
}

const DAY_NAMES = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const MONTH_NAMES = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
  'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

export function germanDayName(date) {
  return DAY_NAMES[dayOfWeek(date) - 1];
}

/** "Mo", "Di", … */
export function shortDayName(date) {
  return germanDayName(date).slice(0, 2);
}

/** "September 2026" – für einen Monat "YYYY-MM" oder ein Datum "YYYY-MM-DD". */
export function germanMonthName(month) {
  return `${MONTH_NAMES[Number(month.slice(5, 7)) - 1]} ${Number(month.slice(0, 4))}`;
}

/** "28.09." */
export function formatShortDate(date) {
  return `${date.slice(8, 10)}.${date.slice(5, 7)}.`;
}

/** "28.09.2026" */
export function formatLongDate(date) {
  return `${date.slice(8, 10)}.${date.slice(5, 7)}.${date.slice(0, 4)}`;
}

/** "30.09.2026, 14:55" */
export function formatDateTime(dateTime) {
  return `${formatLongDate(dateTime.date)}, ${formatTime(dateTime.minutes)}`;
}

/** "28.09. – 04.10.2026" */
export function weekRange(weekStart) {
  return `${formatShortDate(weekStart)} – ${formatLongDate(plusDays(weekStart, 6))}`;
}

/** Kurzbeschreibung der Pausenregeln, z. B. "mehr als 6 h → 30 min, mehr als 9 h → 45 min". */
export function breakRulesText(settings) {
  return settings.breakRules
    .filter((rule) => rule.breakMinutes > 0)
    .sort((a, b) => a.afterMinutes - b.afterMinutes)
    .map((rule) => `mehr als ${formatHoursInput(rule.afterMinutes)} h → ${rule.breakMinutes} min`)
    .join(', ');
}

// ---------------------------------------------------------------------------------------------
// Statustexte
// ---------------------------------------------------------------------------------------------

/** Kurzer Wochenstatus, z. B. "Noch 7:30 h bis zur Grenze". */
export function weekStatusText(summary, isLimit) {
  const balance = summary.balanceMinutes;
  if (isLimit && balance > 0) return `Grenze um ${formatDuration(balance)} h überschritten`;
  if (isLimit) return `Noch ${formatDuration(-balance)} h bis zur Grenze`;
  if (balance < 0) return `Noch ${formatDuration(-balance)} h offen`;
  return `+${formatDuration(balance)} h Überstunden`;
}

/**
 * Text zum Tagesziel, z. B. "20 h voll um 18:45" oder "Tagessoll um 18:45".
 * [weekReached]: Die Wochenstunden sind inklusive der laufenden Zeit bereits erreicht.
 */
export function goalText(goal, settings, weekReached = false) {
  const week = `${formatHoursInput(settings.weeklyTargetMinutes)} h`;
  switch (goal.kind) {
    case GoalKind.WEEK_FULL:
      if (!weekReached) return `${week} voll um ${formatTime(goal.at)}`;
      return settings.weeklyHoursAreLimit ? `${week} voll – jetzt ausstempeln` : `${week} voll`;
    case GoalKind.WEEK_ALREADY_FULL:
      return settings.weeklyHoursAreLimit ? `${week} sind schon voll – nicht weiterarbeiten` : `${week} sind schon voll`;
    default:
      return `Tagessoll um ${formatTime(goal.at)}`;
  }
}

/**
 * Status von heute, z. B. "Seit 08:00 · 20 h voll um 18:45".
 * [otherDaysMinutes] sind die angerechneten Minuten der übrigen Tage dieser Woche.
 */
export function todayStatusText(today, otherDaysMinutes, settings) {
  const entry = today.entry;
  const start = entry.start;
  const end = entry.end;
  if (isAbsence(entry.type)) return `Heute: ${dayTypeLabel(entry.type)}`;
  if (start != null && end == null) {
    const goal = todayGoal(entry, otherDaysMinutes, settings);
    return `Seit ${formatTime(start)}` + (goal ? ' · ' + goalText(goal, settings) : '');
  }
  if (start != null && end != null) {
    return `Heute ${formatTime(start)}–${formatTime(end)} · ${formatDuration(today.creditedMinutes)} h`;
  }
  return 'Heute noch nicht eingestempelt';
}

function shareDayLine(day) {
  const entry = day.entry;
  if (isAbsence(entry.type)) return `${dayTypeLabel(entry.type)} → ${formatDuration(day.creditedMinutes)} h`;
  if (entry.start != null && entry.end != null) {
    return `${formatTime(entry.start)}–${formatTime(entry.end)}, Pause ${formatDuration(day.breakMinutes)} → ` +
      `${formatDuration(day.creditedMinutes)} h`;
  }
  if (day.running) return `seit ${formatTime(entry.start)} (läuft) → ${formatDuration(day.creditedMinutes)} h`;
  return null;
}

/** Text zum Teilen einer Woche (z. B. per Mail oder Messenger). */
export function weekShareText(summary, isLimit) {
  const lines = [`Arbeitszeit KW ${weekNumber(summary.weekStart)} (${weekRange(summary.weekStart)})`, ''];
  for (const day of summary.days) {
    const line = shareDayLine(day);
    if (line != null) lines.push(`${shortDayName(day.entry.date)} ${formatShortDate(day.entry.date)}: ${line}`);
  }
  lines.push('', `Summe: ${formatDuration(summary.actualMinutes)} h`);
  if (isLimit) {
    const balance = summary.balanceMinutes;
    lines.push(`Grenze: ${formatDuration(summary.targetMinutes)} h`);
    lines.push(balance > 0
      ? `Grenze überschritten um: ${formatDuration(balance)} h`
      : `Bis zur Grenze: ${formatDuration(-balance)} h`);
  } else {
    lines.push(`Soll: ${formatDuration(summary.targetMinutes)} h`);
    lines.push(`Saldo: ${formatBalance(summary.balanceMinutes)} h`);
  }
  lines.push(`Abgezogene Pausen: ${formatDuration(summary.breakMinutes)} h`);
  return lines.join('\n');
}

/** Betreff beim Teilen einer Woche. */
export function weekShareSubject(summary) {
  return `Arbeitszeit KW ${weekNumber(summary.weekStart)}`;
}

// ---------------------------------------------------------------------------------------------
// Stempeln
// ---------------------------------------------------------------------------------------------

export const ClockAction = Object.freeze({ CLOCK_IN: 'CLOCK_IN', CLOCK_OUT: 'CLOCK_OUT' });

export const CLOCK_ACTION_LABELS = Object.freeze({ CLOCK_IN: 'Kommen', CLOCK_OUT: 'Gehen' });

/** null: Heute ist schon fertig gestempelt oder ein Abwesenheitstag. */
export function nextClockAction(entry) {
  if (isAbsence(entry.type)) return null;
  if (entry.start == null) return ClockAction.CLOCK_IN;
  if (entry.end == null) return ClockAction.CLOCK_OUT;
  return null;
}

export function applyClockAction(entry, action, time) {
  if (action === ClockAction.CLOCK_IN) return { ...entry, type: DayType.WORK, start: time, end: null };
  return { ...entry, end: time };
}

/**
 * Führt die nächste Stempel-Aktion aus (wie TimeClock.toggle). [time]: Minuten seit Mitternacht.
 * Liefert { action, entry } oder null, wenn nichts zu tun war.
 */
export function toggleClock(entry, time) {
  const action = nextClockAction(entry);
  return action ? { action, entry: applyClockAction(entry, action, time) } : null;
}

// ---------------------------------------------------------------------------------------------
// Stundenzettel (CSV für Excel, Numbers, Google Tabellen)
// ---------------------------------------------------------------------------------------------

/** Byte-Order-Mark, damit Excel die Datei als UTF-8 (Umlaute) erkennt. */
const BOM = '\uFEFF';
const CSV_SEPARATOR = ';';
const CSV_LINE_END = '\r\n';

/** "Arbeitszeit-2026-09.csv" */
export function monthFileName(month) {
  return `Arbeitszeit-${month.slice(0, 4)}-${month.slice(5, 7)}.csv`;
}

function monthDayEntries(month, entries) {
  const lookup = entryLookup(entries);
  const result = [];
  for (const date of datesOfMonth(month)) {
    const entry = lookup(date);
    if (entry && !isEmptyEntry(entry)) result.push(entry);
  }
  return result;
}

/** { workedMinutes, absenceMinutes, workDays, absenceDays, totalMinutes } eines Monats "YYYY-MM". */
export function monthSummary(month, entries, settings) {
  let workedMinutes = 0;
  let absenceMinutes = 0;
  let workDays = 0;
  let absenceDays = 0;
  for (const entry of monthDayEntries(month, entries)) {
    const result = evaluate(entry, settings);
    if (isAbsence(entry.type)) {
      absenceMinutes += result.creditedMinutes;
      absenceDays++;
    } else {
      workedMinutes += result.creditedMinutes;
      if (result.creditedMinutes > 0) workDays++;
    }
  }
  return { workedMinutes, absenceMinutes, workDays, absenceDays, totalMinutes: workedMinutes + absenceMinutes };
}

function sumLine(label, minutes) {
  return [label, '', '', '', '', '', '', formatDuration(minutes), formatDecimalHours(minutes)];
}

/** Stundenzettel eines Monats "YYYY-MM" als CSV-Text (mit BOM, Zeilenende CRLF). */
export function monthCsv(month, entries, settings) {
  const lines = [
    [`Stundenzettel ${germanMonthName(month)}`],
    [],
    ['KW', 'Datum', 'Wochentag', 'Art', 'Beginn', 'Ende', 'Pause (Min.)', 'Stunden (h:mm)', 'Stunden (dezimal)'],
  ];
  for (const entry of monthDayEntries(month, entries)) {
    const result = evaluate(entry, settings);
    const isWork = !isAbsence(entry.type);
    lines.push([
      String(isoWeek(entry.date)),
      formatLongDate(entry.date),
      germanDayName(entry.date),
      dayTypeLabel(entry.type),
      isWork && entry.start != null ? formatTime(entry.start) : '',
      isWork && entry.end != null ? formatTime(entry.end) : '',
      isWork ? String(result.breakMinutes) : '',
      formatDuration(result.creditedMinutes),
      formatDecimalHours(result.creditedMinutes),
    ]);
  }
  const summary = monthSummary(month, entries, settings);
  lines.push([]);
  lines.push(sumLine('Summe gearbeitet', summary.workedMinutes));
  if (summary.absenceMinutes > 0) {
    lines.push(sumLine('Gutschrift Urlaub/Krank/Feiertag', summary.absenceMinutes));
    lines.push(sumLine('Gesamt', summary.totalMinutes));
  }
  return BOM + lines.map((line) => line.join(CSV_SEPARATOR)).join(CSV_LINE_END) + CSV_LINE_END;
}

/** Wie das Objekt MonthExport in Kotlin. */
export const MonthExport = Object.freeze({ fileName: monthFileName, summary: monthSummary, csv: monthCsv });

// ---------------------------------------------------------------------------------------------
// Sicherung (JSON-Format, kompatibel mit Android)
// ---------------------------------------------------------------------------------------------

const APP_ID = 'Arbeitszeitrechner';
const BACKUP_VERSION = 1;

export const BACKUP_ERROR_MESSAGE = 'Das ist keine Sicherungsdatei des Arbeitszeitrechners.';

export class BackupFormatError extends Error {
  constructor(message = BACKUP_ERROR_MESSAGE) {
    super(message);
    this.name = 'BackupFormatError';
  }
}

// Lesen wie org.json (optString, optInt, …): fehlende oder unpassende Werte ergeben den Standardwert.

function isJsonObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function optValue(json, key) {
  return Object.prototype.hasOwnProperty.call(json, key) ? json[key] : null;
}

function optString(json, key) {
  const value = optValue(json, key);
  if (value == null) return '';
  if (typeof value === 'string') return value;
  return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

/** Zahl in einem Text wie org.json (stringToNumber) und davon intValue(); null, wenn keine Zahl. */
function javaIntValue(text) {
  const first = text.charAt(0);
  if (!(first >= '0' && first <= '9') && first !== '-') return null;
  if (/[.eE]/.test(text) || text === '-0') {
    // BigDecimal: Nachkommastellen abschneiden, bei Überlauf nur die unteren 32 Bit.
    if (/^-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/.test(text)) return Number(text) | 0;
    // Ersatzweise Double.valueOf (z. B. "1.5d"); Double.intValue() begrenzt auf den Int-Bereich.
    const value = toDoubleOrNull(text);
    return value != null && Number.isFinite(value) ? clamp(Math.trunc(value), INT_MIN, INT_MAX) + 0 : null;
  }
  // Ganze Zahl (BigInteger); führende Nullen lehnt org.json ab.
  if (!/^-?\d+$/.test(text) || /^-?0\d/.test(text)) return null;
  return Number(BigInt.asIntN(32, BigInt(text)));
}

function optInt(json, key, fallback) {
  const value = optValue(json, key);
  if (typeof value === 'number') return value | 0;
  if (typeof value === 'string') return javaIntValue(value) ?? fallback;
  return fallback;
}

function optBoolean(json, key, fallback) {
  const value = optValue(json, key);
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const lower = value.toLowerCase();
    if (lower === 'true') return true;
    if (lower === 'false') return false;
  }
  return fallback;
}

/** Eintrag als JSON-Objekt (ohne Datum), wie es Android speichert: { type, start?, end?, break }. */
export function encodeEntry(entry) {
  const json = { type: entry.type };
  if (entry.start != null) json.start = formatTime(entry.start);
  if (entry.end != null) json.end = formatTime(entry.end);
  json.break = entry.manualBreakMinutes;
  return json;
}

/** Liest einen Eintrag für [date]. Liefert null bei ungültigem Datum oder ungültiger Uhrzeit. */
export function decodeEntry(date, json) {
  if (parseDate(date) == null || !isJsonObject(json)) return null;
  const typeName = optString(json, 'type');
  const startText = optString(json, 'start');
  const endText = optString(json, 'end');
  const start = startText !== '' ? parseTime(startText) : null;
  const end = endText !== '' ? parseTime(endText) : null;
  if ((startText !== '' && start == null) || (endText !== '' && end == null)) return null;
  return {
    date,
    type: DAY_TYPES.indexOf(typeName) >= 0 ? typeName : DayType.WORK,
    start,
    end,
    manualBreakMinutes: Math.max(optInt(json, 'break', 0), 0),
  };
}

/** Eintrag mit Datum, wie in der Sicherungsdatei: { type, start?, end?, break, date }. */
export function entryToJson(entry) {
  const json = encodeEntry(entry);
  json.date = entry.date;
  return json;
}

/** Gegenstück zu entryToJson. Liefert null, wenn der Eintrag ungültig ist. */
export function entryFromJson(json) {
  return isJsonObject(json) ? decodeEntry(optString(json, 'date'), json) : null;
}

/** Einstellungen im JSON-Format der Sicherung (Pausenregeln als { after, break }). */
export function encodeSettings(settings) {
  return {
    weeklyTargetMinutes: settings.weeklyTargetMinutes,
    workDaysPerWeek: settings.workDaysPerWeek,
    weeklyHoursAreLimit: settings.weeklyHoursAreLimit,
    autoBreak: settings.autoBreak,
    gradualDeduction: settings.gradualDeduction,
    breakRules: settings.breakRules.map((rule) => ({ after: rule.afterMinutes, break: rule.breakMinutes })),
  };
}

/** Liest Einstellungen nachsichtig: Fehlendes wird durch Standardwerte ersetzt, Werte werden begrenzt. */
export function decodeSettings(json) {
  const source = isJsonObject(json) ? json : {};
  const defaults = defaultSettings();
  const rulesJson = optValue(source, 'breakRules');
  const breakRules = DEFAULT_BREAK_RULES.map((rule, index) => {
    const ruleJson = Array.isArray(rulesJson) && isJsonObject(rulesJson[index]) ? rulesJson[index] : null;
    return {
      afterMinutes: ruleJson ? optInt(ruleJson, 'after', rule.afterMinutes) : rule.afterMinutes,
      breakMinutes: ruleJson ? optInt(ruleJson, 'break', rule.breakMinutes) : rule.breakMinutes,
    };
  });
  return {
    weeklyTargetMinutes: clamp(optInt(source, 'weeklyTargetMinutes', defaults.weeklyTargetMinutes), 1, 7 * MINUTES_PER_DAY),
    workDaysPerWeek: clamp(optInt(source, 'workDaysPerWeek', defaults.workDaysPerWeek), 1, 7),
    weeklyHoursAreLimit: optBoolean(source, 'weeklyHoursAreLimit', defaults.weeklyHoursAreLimit),
    autoBreak: optBoolean(source, 'autoBreak', defaults.autoBreak),
    gradualDeduction: optBoolean(source, 'gradualDeduction', defaults.gradualDeduction),
    breakRules,
  };
}

/**
 * Sicherungsdatei als Text (JSON, 2 Leerzeichen eingerückt, Schlüssel in der Reihenfolge der
 * Android-App). Leere Einträge werden weggelassen, die übrigen nach Datum sortiert.
 */
export function createBackup(entries, settings, createdAt = nowLocalDateTime()) {
  const list = entryList(entries)
    .filter((entry) => !isEmptyEntry(entry))
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  return JSON.stringify({
    app: APP_ID,
    version: BACKUP_VERSION,
    createdAt: formatLocalDateTime(createdAt),
    settings: encodeSettings(settings),
    entries: list.map(entryToJson),
  }, null, 2);
}

/**
 * Liest eine Sicherungsdatei: { createdAt (Zeitpunkt oder null), settings (oder null), entries }.
 * Ungültige Einträge werden übersprungen. Wirft BackupFormatError, wenn es keine Sicherung ist.
 */
export function parseBackup(text) {
  let json = null;
  try {
    const source = String(text);
    json = JSON.parse(ktTrim(source.charCodeAt(0) === 0xfeff ? source.slice(1) : source));
  } catch (error) {
    json = null;
  }
  if (!isJsonObject(json) || optString(json, 'app') !== APP_ID) throw new BackupFormatError();
  const entriesJson = optValue(json, 'entries');
  const entries = [];
  if (Array.isArray(entriesJson)) {
    for (const item of entriesJson) {
      const entry = entryFromJson(item);
      if (entry) entries.push(entry);
    }
  }
  const settingsJson = optValue(json, 'settings');
  return {
    createdAt: parseLocalDateTime(optString(json, 'createdAt')),
    settings: isJsonObject(settingsJson) ? decodeSettings(settingsJson) : null,
    entries,
  };
}

/**
 * Übernimmt die Einträge einer Sicherung: Einträge aus der Sicherung ersetzen die Einträge derselben
 * Tage (leere löschen sie), alle anderen Tage bleiben erhalten. Liefert ein neues Objekt { Datum: Eintrag }.
 */
export function mergeBackup(entries, data) {
  const result = {};
  for (const entry of entryList(entries)) result[entry.date] = entry;
  for (const entry of data.entries) {
    if (isEmptyEntry(entry)) delete result[entry.date];
    else result[entry.date] = entry;
  }
  return result;
}

/** Wie Repository.importBackup: Einträge zusammenführen, Einstellungen übernehmen (falls enthalten). */
export function applyBackup(entries, settings, data) {
  return { entries: mergeBackup(entries, data), settings: data.settings ?? settings };
}

/** Dateiname für "Backup jetzt speichern". */
export function backupFileName(date) {
  return `Arbeitszeit-Backup-${date}.json`;
}

/** Dateiname für die automatische Sicherung. */
export const AUTO_BACKUP_FILE_NAME = 'Arbeitszeit-Backup.json';

// ---------------------------------------------------------------------------------------------
// Texte und Zustände der Oberfläche (wortgleich mit der Android-App)
// ---------------------------------------------------------------------------------------------

export const DAILY_MAX_WARNING = 'Mehr als 10 h Arbeitszeit – gesetzliche Tageshöchstgrenze (§ 3 ArbZG)';

/** Titel einer Tageskarte: "Montag" bzw. "Montag · Heute". */
export function dayTitle(date, isToday) {
  return isToday ? `${germanDayName(date)} · Heute` : germanDayName(date);
}

/** Stunden rechts auf der Tageskarte: "8:00 h" oder "–". */
export function dayValueText(day) {
  const entry = day.entry;
  const hasValue = day.creditedMinutes > 0 || (entry.start != null && entry.end != null);
  return hasValue || day.running ? `${formatDuration(day.creditedMinutes)} h` : '–';
}

/**
 * Detailzeile einer Tageskarte. tone: 'absence' | 'running' | 'warning' | 'normal' | 'error'.
 * dailyMaxWarning: Hinweistext bei mehr als 10 h oder null.
 */
export function dayDetail(day, settings, otherDaysMinutes, weekReached) {
  const entry = day.entry;
  const start = entry.start;
  const end = entry.end;
  const breakText = `Pause ${formatDuration(day.breakMinutes)} h` + (day.autoBreakApplied ? ' (auto)' : '');
  let text;
  let tone;
  if (isAbsence(entry.type)) {
    text = `${dayTypeLabel(entry.type)} · Tagessoll gutgeschrieben`;
    tone = 'absence';
  } else if (day.running && start != null) {
    const goal = todayGoal(entry, otherDaysMinutes, settings);
    // Werkstudenten-Grenze erreicht: deutlich warnen.
    const warn = settings.weeklyHoursAreLimit && goal != null &&
      (goal.kind === GoalKind.WEEK_ALREADY_FULL || (goal.kind === GoalKind.WEEK_FULL && weekReached));
    text = `seit ${formatTime(start)} · ${breakText}` + (goal ? '\n' + goalText(goal, settings, weekReached) : '');
    tone = warn ? 'warning' : 'running';
  } else if (start != null && end != null) {
    text = `${formatTime(start)} – ${formatTime(end)} · ${breakText}`;
    tone = 'normal';
  } else if (start != null) {
    text = `Beginn ${formatTime(start)} · Ende fehlt`;
    tone = 'error';
  } else if (end != null) {
    text = `Ende ${formatTime(end)} · Beginn fehlt`;
    tone = 'error';
  } else {
    text = 'Kein Eintrag – tippen zum Erfassen';
    tone = 'normal';
  }
  return { text, tone, dailyMaxWarning: day.exceedsDailyMax ? DAILY_MAX_WARNING : null };
}

/** Text des Stempel-Knopfs auf der Karte von heute oder null, wenn keiner angezeigt wird. */
export function clockButtonText(entry, isToday) {
  if (!isToday || entry.type !== DayType.WORK) return null;
  if (entry.start == null) return 'Kommen – jetzt einstempeln';
  if (entry.end == null) return 'Gehen – jetzt ausstempeln';
  return null;
}

/** Die Wochenstunden sind Obergrenze und überschritten. */
export function isLimitExceeded(summary, isLimit) {
  return isLimit && summary.balanceMinutes > 0;
}

/** Fortschritt der Woche zwischen 0 und 1. */
export function weekProgress(summary) {
  return summary.targetMinutes > 0 ? clamp(summary.actualMinutes / summary.targetMinutes, 0, 1) : 1;
}

/** Linke Kennzahl der Wochenkarte. tone: 'negative' | 'positive' | 'neutral'. */
export function weekBalanceStat(summary, isLimit) {
  const balance = summary.balanceMinutes;
  if (isLimit && balance > 0) {
    return { label: 'Grenze überschritten', value: `+${formatDuration(balance)} h`, tone: 'negative' };
  }
  if (isLimit) return { label: 'Bis zur Grenze', value: `${formatDuration(-balance)} h`, tone: 'neutral' };
  if (balance < 0) return { label: 'Noch offen', value: `${formatDuration(-balance)} h`, tone: 'neutral' };
  return { label: 'Überstunden', value: `+${formatDuration(balance)} h`, tone: 'positive' };
}

/** Hinweis unter der Wochenübersicht. */
export function breakHintText(settings) {
  return settings.autoBreak
    ? `Pausen werden automatisch abgezogen (${breakRulesText(settings)}). Eine längere eingetragene Pause hat Vorrang.`
    : 'Automatischer Pausenabzug ist ausgeschaltet. Es wird nur die eingetragene Pause abgezogen.';
}

/** Monat, mit dem der Export-Dialog startet: in der aktuellen Woche der heutige, sonst der des Wochenbeginns. */
export function initialExportMonth(weekStart, todayDate) {
  return weekStart === weekStartOf(todayDate) ? yearMonthOf(todayDate) : yearMonthOf(weekStart);
}

/** Zusammenfassung im Export-Dialog. */
export function monthSummaryText(summary) {
  if (summary.totalMinutes === 0) return 'Keine Einträge in diesem Monat.';
  const worked = `${formatDuration(summary.workedMinutes)} h an ${summary.workDays} Arbeitstagen`;
  if (summary.absenceMinutes === 0) return worked;
  return `${worked}, dazu ${formatDuration(summary.absenceMinutes)} h Urlaub/Krank/Feiertag ` +
    `(gesamt ${formatDuration(summary.totalMinutes)} h)`;
}

/** Text im Dialog "Backup wiederherstellen?". */
export function restoreSummaryText(data) {
  const created = data.createdAt ? ` vom ${formatDateTime(data.createdAt)}` : '';
  return `Sicherung${created} mit ${data.entries.length} Einträgen. Einträge für dieselben Tage ` +
    'werden überschrieben, alle anderen bleiben erhalten. Die Einstellungen werden übernommen.';
}

// --- Tag bearbeiten ---

/** Titel des Dialogs: "Montag, 28.09.2026". */
export function dayEditTitle(date) {
  return `${germanDayName(date)}, ${formatLongDate(date)}`;
}

/** Eingabe im Pausenfeld: nur Ziffern, höchstens 3. */
export function filterBreakInput(text) {
  return digitsOnly(text, 3);
}

/** Eintrag aus den Feldern des Dialogs; bei Abwesenheit zählen Zeiten und Pause nicht. */
export function draftEntry(date, type, start, end, breakText) {
  if (type !== DayType.WORK) return createEntry(date, { type });
  return createEntry(date, { type, start, end, manualBreakMinutes: toIntOrNull(breakText) ?? 0 });
}

/** Erklärung unter dem Pausenfeld. */
export function breakFieldHint(settings) {
  return settings.autoBreak
    ? 'Mindestens die gesetzliche Pause wird automatisch abgezogen.'
    : 'Automatischer Pausenabzug ist ausgeschaltet.';
}

/** Hinweis bei Urlaub, Krank oder Feiertag. */
export function absenceCreditText(type, settings) {
  return `${dayTypeLabel(type)}: Es werden ${formatDuration(dailyTargetMinutes(settings))} h (Tagessoll) gutgeschrieben.`;
}

/** Vorschlag für den Beginn: heute die aktuelle Uhrzeit, sonst 08:00. [now]: Zeitpunkt. */
export function defaultStartTime(date, now) {
  return now && now.date === date ? now.minutes : 8 * 60;
}

/** Vorschlag für das Ende: heute die aktuelle Uhrzeit, sonst wann das Tagessoll erreicht ist. */
export function defaultEndTime(date, start, manualBreakMinutes, settings, now) {
  if (now && now.date === date) return now.minutes;
  return endTimeForTarget(start ?? 8 * 60, manualBreakMinutes, dailyTargetMinutes(settings), settings);
}

// --- Einstellungen ---

/** Startwerte der Eingabefelder in den Einstellungen. */
export function settingsForm(settings) {
  const rules = settings.breakRules;
  return {
    weeklyText: formatHoursInput(settings.weeklyTargetMinutes),
    daysText: String(settings.workDaysPerWeek),
    isLimit: settings.weeklyHoursAreLimit,
    autoBreak: settings.autoBreak,
    gradual: settings.gradualDeduction,
    rule1After: formatHoursInput(rules[0].afterMinutes),
    rule1Break: String(rules[0].breakMinutes),
    rule2After: formatHoursInput(rules[1].afterMinutes),
    rule2Break: String(rules[1].breakMinutes),
  };
}

/** Felder der Pausenregeln auf die gesetzlichen Werte zurücksetzen (gestaffelter Abzug an). */
export function resetBreakRulesForm(form) {
  const defaults = settingsForm(defaultSettings());
  return {
    ...form,
    rule1After: defaults.rule1After,
    rule1Break: defaults.rule1Break,
    rule2After: defaults.rule2After,
    rule2Break: defaults.rule2Break,
    gradual: true,
  };
}

/** Eingabe für Arbeitstage: nur eine Ziffer. */
export function filterDaysInput(text) {
  return digitsOnly(text, 1);
}

function inRange(value, min, max) {
  return value != null && value >= min && value <= max ? value : null;
}

/**
 * Prüft die Eingaben der Einstellungen wie die Android-App. Liefert die geprüften Werte (null bei
 * Fehler), valid, den Hinweis unter der Wochenarbeitszeit und – wenn gültig – die neuen Einstellungen.
 * Bei ausgeschaltetem Pausenabzug und ungültigen Regeln bleiben die bisherigen Regeln erhalten.
 */
export function validateSettingsForm(form, currentSettings) {
  const weekly = inRange(parseHours(form.weeklyText), 1, 7 * MINUTES_PER_DAY);
  const days = inRange(toIntOrNull(form.daysText), 1, 7);
  const rule1After = inRange(parseHours(form.rule1After), 0, MINUTES_PER_DAY);
  const rule1Break = inRange(toIntOrNull(form.rule1Break), 0, 600);
  const rule2After = inRange(parseHours(form.rule2After), 0, MINUTES_PER_DAY);
  const rule2Break = inRange(toIntOrNull(form.rule2Break), 0, 600);
  const rulesValid = rule1After != null && rule1Break != null && rule2After != null && rule2Break != null;
  const valid = weekly != null && days != null && (!form.autoBreak || rulesValid);
  const weeklyHint = weekly == null
    ? 'Bitte z. B. 40, 38,5 oder 38:30 eingeben'
    : `Tagessoll: ${formatDuration(Math.trunc(weekly / (days ?? 5)))} h`;
  const settings = valid
    ? {
      weeklyTargetMinutes: weekly,
      workDaysPerWeek: days,
      weeklyHoursAreLimit: form.isLimit,
      autoBreak: form.autoBreak,
      gradualDeduction: form.gradual,
      breakRules: rulesValid
        ? [{ afterMinutes: rule1After, breakMinutes: rule1Break }, { afterMinutes: rule2After, breakMinutes: rule2Break }]
        : currentSettings.breakRules.map((rule) => ({ ...rule })),
    }
    : null;
  return { weekly, days, rule1After, rule1Break, rule2After, rule2Break, rulesValid, valid, weeklyHint, settings };
}
