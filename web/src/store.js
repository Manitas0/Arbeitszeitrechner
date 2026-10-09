// Lokale Speicherung im Browser (localStorage). Alle GitHub-Pages-Projekte eines Kontos teilen sich
// denselben Speicher, darum tragen die Schlüssel den eindeutigen Präfix "arbeitszeitrechner.":
//
//   arbeitszeitrechner.entries   { "YYYY-MM-DD": { type, start?, end?, break } } – je Tag dasselbe JSON wie in der Android-App
//   arbeitszeitrechner.settings  Einstellungen im Format der Sicherungsdatei
//   arbeitszeitrechner.lastBackup, arbeitszeitrechner.installHintDismissed
//
// Vorführungen (?demo=1, ?now=…) nutzen den Präfix "arbeitszeitrechner-demo." und lassen die echten Daten unberührt.
// Jede Änderung liest den aktuellen Stand neu ein, damit sich mehrere offene Tabs nicht überschreiben.

import {
  decodeEntry, decodeSettings, defaultSettings, encodeEntry, encodeSettings, formatLocalDateTime, isEmptyEntry,
  parseLocalDateTime,
} from './core.js';

let prefix = 'arbeitszeitrechner.';

/** Für Vorführungen und Tests: eigene Schlüssel statt der echten Daten. Vor dem ersten Zugriff aufrufen. */
export function useDemoStorage() {
  prefix = 'arbeitszeitrechner-demo.';
}

const keyEntries = () => prefix + 'entries';
const keySettings = () => prefix + 'settings';
const keyLastBackup = () => prefix + 'lastBackup';
const keyInstallHint = () => prefix + 'installHintDismissed';

/** Der Browser hat das Speichern verweigert (z. B. Speicher voll oder gesperrt). */
export class StorageError extends Error {
  constructor() {
    super('Daten konnten nicht gespeichert werden');
    this.name = 'StorageError';
  }
}

// Ersatz, falls localStorage nicht nutzbar ist: Die Daten gelten dann nur bis zum Schließen.
const memory = new Map();

/** Text des Hinweises, solange Einträge oder Einstellungen nur im Arbeitsspeicher liegen. */
export const UNSAVED_MESSAGE = 'Speichern nicht möglich – Änderungen gehen beim Schließen verloren. ' +
  'Bitte jetzt ein Backup speichern.';

/** Liegen Einträge oder Einstellungen nur im Arbeitsspeicher, weil der Browser das Speichern verweigert hat? */
export function hasUnsavedData() {
  return memory.has(keyEntries()) || memory.has(keySettings());
}

function read(key) {
  if (memory.has(key)) return memory.get(key);
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key, value) {
  try {
    if (value == null) window.localStorage.removeItem(key);
    else window.localStorage.setItem(key, value);
    memory.delete(key);
  } catch {
    memory.set(key, value);
    throw new StorageError();
  }
}

function readJson(key) {
  const text = read(key);
  if (text == null) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function readEntriesJson() {
  const json = readJson(keyEntries());
  return json !== null && typeof json === 'object' && !Array.isArray(json) ? json : {};
}

function writeEntriesJson(json) {
  const sorted = {};
  for (const date of Object.keys(json).sort()) sorted[date] = json[date];
  write(keyEntries(), JSON.stringify(sorted));
}

// --- Einträge ---

/** Alle gespeicherten Einträge als { Datum: Eintrag }; ungültige werden übersprungen. */
export function loadEntries() {
  const json = readEntriesJson();
  const entries = {};
  for (const date of Object.keys(json)) {
    const entry = decodeEntry(date, json[date]);
    if (entry && !isEmptyEntry(entry)) entries[date] = entry;
  }
  return entries;
}

export function hasEntries() {
  return Object.keys(loadEntries()).length > 0;
}

/** Speichert einen Eintrag; ein leerer Eintrag löscht den Tag. */
export function saveEntry(entry) {
  const json = readEntriesJson();
  if (isEmptyEntry(entry)) delete json[entry.date];
  else json[entry.date] = encodeEntry(entry);
  writeEntriesJson(json);
}

export function deleteEntry(date) {
  const json = readEntriesJson();
  delete json[date];
  writeEntriesJson(json);
}

/** Ersetzt alle Einträge (z. B. nach dem Wiederherstellen einer Sicherung). */
export function replaceEntries(entries) {
  const json = {};
  for (const entry of Object.values(entries)) {
    if (!isEmptyEntry(entry)) json[entry.date] = encodeEntry(entry);
  }
  writeEntriesJson(json);
}

// --- Einstellungen ---

export function loadSettings() {
  const json = readJson(keySettings());
  return json === null ? defaultSettings() : decodeSettings(json);
}

export function saveSettings(settings) {
  write(keySettings(), JSON.stringify(encodeSettings(settings)));
}

// --- Sonstiges ---

/** Zeitpunkt der letzten gespeicherten Sicherung oder null. */
export function lastBackup() {
  return parseLocalDateTime(read(keyLastBackup()));
}

export function setLastBackup(dateTime) {
  try {
    write(keyLastBackup(), formatLocalDateTime(dateTime));
  } catch {
    // Nur eine Anzeige – kein Grund für eine Fehlermeldung.
  }
}

export function installHintDismissed() {
  return read(keyInstallHint()) === '1';
}

export function dismissInstallHint() {
  try {
    write(keyInstallHint(), '1');
  } catch {
    // Ohne Speicher erscheint der Hinweis beim nächsten Start eben wieder.
  }
}

let persistRequested = false;

/**
 * Bittet den Browser, die Daten nicht automatisch zu löschen (z. B. bei Speicherknappheit).
 * Wird erst beim ersten Speichern aufgerufen, weil manche Browser dafür nachfragen.
 */
export function requestPersistence() {
  if (persistRequested) return;
  persistRequested = true;
  try {
    navigator.storage?.persist?.().catch(() => {});
  } catch {
    // Nicht unterstützt
  }
}

/** Ruft [onChange] auf, wenn ein anderer Tab die Daten geändert hat. */
export function onExternalChange(onChange) {
  window.addEventListener('storage', (event) => {
    if (event.key === null || event.key.startsWith(prefix)) onChange();
  });
}
