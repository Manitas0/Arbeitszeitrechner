// End-to-End-Test der Web-App mit Playwright (Chromium, iPhone-Größe 390 × 844).
//
// Aufruf im Ordner web/:   NODE_PATH=$(npm root -g) node test/e2e.cjs
//
// Startet selbst einen lokalen Server (python3 -m http.server), prüft Texte und Abläufe gegen
// src/core.js und legt Screenshots in test/screenshots/ ab. Nicht Teil von "node --test".

'use strict';

if (process.env.NODE_TEST_CONTEXT) {
  // Von "node --test" gefunden (Standardmuster test/**): läuft nur ausdrücklich, auch ohne Playwright.
  process.exit(0);
}

const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

process.env.TZ = 'Europe/Berlin'; // wie im Browser (timezoneId)

const WEB = path.resolve(__dirname, '..');
const SHOTS = path.join(__dirname, 'screenshots');
const NOW = '2026-09-30T15:00';
const TODAY = NOW.slice(0, 10);
const IPHONE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';
// ?demo und ?now nutzen eigene Schlüssel; die echten Daten liegen unter "arbeitszeitrechner.".
const DEMO = 'arbeitszeitrechner-demo.';
const REAL = 'arbeitszeitrechner.';
const UNSAVED = 'Speichern nicht möglich – Änderungen gehen beim Schließen verloren. Bitte jetzt ein Backup speichern.';
const REMINDER_IOS = 'Safari löscht die Daten, wenn die Seite 7 Tage lang nicht geöffnet wird. Speichere regelmäßig ' +
  'ein Backup – oder nutze die App vom Home-Bildschirm und stelle das Backup dort wieder her.';

let core;
let demo;
let base;
let passed = 0;

// --- Hilfen ---

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
    server.on('error', reject);
  });
}

async function startServer() {
  const port = await freePort();
  const child = spawn('python3', ['-m', 'http.server', String(port), '--bind', '127.0.0.1'], {
    cwd: WEB,
    stdio: 'ignore',
  });
  const url = `http://127.0.0.1:${port}/`;
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      const response = await fetch(url);
      if (response.ok) return { child, url };
    } catch {
      // Server startet noch
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  child.kill();
  throw new Error('Lokaler Server startet nicht');
}

async function step(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.log(`FEHLER - ${name}`);
    throw error;
  }
}

function clean(text) {
  return text.replace(/ /g, ' ').trim();
}

async function textOf(locator) {
  return clean(await locator.innerText());
}

async function newContext(browser, options = {}) {
  return browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
    locale: 'de-DE',
    timezoneId: 'Europe/Berlin',
    colorScheme: 'light',
    acceptDownloads: true,
    ...options,
  });
}

/** Sammelt Konsolenfehler, Skriptfehler und fehlgeschlagene Anfragen einer Seite. */
function watch(page) {
  const problems = [];
  page.on('console', (message) => {
    if (message.type() === 'error') problems.push(`Konsole: ${message.text()}`);
  });
  page.on('pageerror', (error) => problems.push(`Skriptfehler: ${error.message}`));
  page.on('response', (response) => {
    if (response.status() >= 400) problems.push(`HTTP ${response.status()}: ${response.url()}`);
  });
  return problems;
}

/** Ohne Speichern-Dialog des Browsers (wie in Firefox und Safari): Dateien kommen als Download. */
async function withoutSavePicker(context) {
  await context.addInitScript(() => {
    delete Window.prototype.showSaveFilePicker;
    delete window.showSaveFilePicker;
  });
}

/** Gespeicherte Daten der Seite (Vorführ-Speicher) im Modell von core.js. */
async function stored(page) {
  const raw = await page.evaluate((prefix) => ({
    entries: localStorage.getItem(`${prefix}entries`),
    settings: localStorage.getItem(`${prefix}settings`),
  }), DEMO);
  const json = raw.entries ? JSON.parse(raw.entries) : {};
  const entries = {};
  for (const date of Object.keys(json)) entries[date] = core.decodeEntry(date, json[date]);
  const settings = raw.settings ? core.decodeSettings(JSON.parse(raw.settings)) : core.defaultSettings();
  return { entries, settings, entriesJson: json };
}

async function shot(page, name, options = {}) {
  await page.locator('.toast.is-visible').waitFor({ state: 'detached', timeout: 5000 }).catch(() => {});
  await page.waitForTimeout(400); // Animationen abwarten
  await page.screenshot({ path: path.join(SHOTS, `${name}.png`), ...options });
}

async function waitForToast(page, text) {
  await page.locator('.toast.is-visible', { hasText: text }).waitFor({ timeout: 5000 });
}

async function closeSheet(page) {
  await page.locator('dialog[open]').waitFor({ state: 'detached', timeout: 5000 });
}

/** Prüft die Wochenansicht Zeichen für Zeichen gegen core.js. */
async function expectWeek(page, weekStart, entries, settings) {
  const now = core.parseLocalDateTime(NOW);
  const summary = core.summarizeWeek(weekStart, entries, settings, now);
  const isLimit = settings.weeklyHoursAreLimit;
  assert.equal(await textOf(page.locator('.week-number')), `KW ${core.weekNumber(weekStart)}`);
  assert.equal(await textOf(page.locator('.week-range')), core.weekRange(weekStart));
  assert.equal(await textOf(page.locator('.summary-actual')), core.formatDuration(summary.actualMinutes));
  assert.equal(await textOf(page.locator('.summary-target')), `/ ${core.formatDuration(summary.targetMinutes)} h`);
  const balance = core.weekBalanceStat(summary, isLimit);
  const stats = page.locator('.stat');
  assert.equal(await textOf(stats.nth(0).locator('.stat-label')), balance.label);
  assert.equal(await textOf(stats.nth(0).locator('.stat-value')), balance.value);
  assert.equal(await textOf(stats.nth(1).locator('.stat-value')), `${core.formatDuration(summary.breakMinutes)} h`);
  const progress = Number(await page.locator('.progress').getAttribute('aria-valuenow'));
  assert.equal(progress, Math.round(core.weekProgress(summary) * 100));

  const cards = page.locator('.day');
  assert.equal(await cards.count(), 7);
  const weekReached = summary.actualMinutes >= settings.weeklyTargetMinutes;
  for (let i = 0; i < 7; i++) {
    const day = summary.days[i];
    const date = day.entry.date;
    const card = cards.nth(i);
    const detail = core.dayDetail(day, settings, core.minutesExcluding(summary, date), weekReached);
    assert.equal(await textOf(card.locator('.day-title')), core.dayTitle(date, date === TODAY), date);
    assert.equal(await textOf(card.locator('.day-date')), core.formatShortDate(date), date);
    assert.equal(await textOf(card.locator('.day-value')), core.dayValueText(day), date);
    assert.equal(await textOf(card.locator('.day-detail')), detail.text, date);
    assert.ok(await card.locator('.day-detail').evaluate((el, tone) => el.classList.contains(`tone-${tone}`), detail.tone));
    const warning = card.locator('.day-warning');
    if (detail.dailyMaxWarning) assert.equal(await textOf(warning), detail.dailyMaxWarning, date);
    else assert.equal(await warning.count(), 0, date);
    const clock = core.clockButtonText(day.entry, date === TODAY);
    const button = card.locator('.clock-button');
    if (clock) assert.equal(await textOf(button), clock, date);
    else assert.equal(await button.count(), 0, date);
  }
  assert.equal(await textOf(page.locator('.footnote')), core.breakHintText(settings));
  return summary;
}

// --- Tests ---

async function mainFlow(browser) {
  const context = await newContext(browser);
  await withoutSavePicker(context);
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: base.replace(/\/$/, '') });
  const page = await context.newPage();
  const problems = watch(page);
  const now = core.parseLocalDateTime(NOW);
  const weekStart = core.weekStartOf(TODAY);
  let backupPath = null;
  let backupText = null;

  await step('Start mit Beispieldaten und fester Uhrzeit', async () => {
    await page.goto(`${base}?demo=1&now=${NOW}`);
    await page.locator('.day').first().waitFor();
    const data = await stored(page);
    assert.deepEqual(data.entries, demo.demoEntries(TODAY));
    await expectWeek(page, weekStart, data.entries, data.settings);
    assert.equal(await textOf(page.locator('.week-number')), 'KW 40');
    assert.equal(await textOf(page.locator('.week-range')), '28.09. – 04.10.2026');
    assert.equal(await textOf(page.locator('.summary-actual')), '16:15');
    const today = page.locator('.day.is-today');
    assert.equal(await textOf(today.locator('.detail-goal')), '20 h voll um 19:00');
    assert.equal(await textOf(today.locator('.clock-button')), 'Gehen – jetzt ausstempeln');
    assert.equal(await page.locator('.notice').count(), 0);
    assert.equal(await page.locator('.install-hint').count(), 0);
    assert.equal(await page.title(), 'Arbeitszeitrechner');
    await shot(page, 'week-light');
    await shot(page, 'week-light-full', { fullPage: true });
  });

  await step('Ohne ?now läuft die echte Uhr, ?demo füllt keinen vollen Speicher', async () => {
    const other = await context.newPage();
    const otherProblems = watch(other);
    await other.goto(`${base}?demo=1`);
    await other.locator('.day').first().waitFor();
    const realWeek = core.weekStartOf(core.today());
    assert.equal(await textOf(other.locator('.week-range')), core.weekRange(realWeek));
    const data = await stored(other);
    assert.deepEqual(data.entries, demo.demoEntries(TODAY)); // nicht erneut befüllt
    assert.deepEqual(otherProblems, []);
    await other.close();
  });

  await step('Ohne Parameter: echte Daten, von ?demo und ?now unberührt', async () => {
    const other = await context.newPage();
    const otherProblems = watch(other);
    await other.goto(base);
    await other.locator('.day').first().waitFor();
    assert.deepEqual(await other.evaluate((demoPrefix) =>
      Object.keys(localStorage).filter((key) => !key.startsWith(demoPrefix)), DEMO), []);
    assert.ok(clean(await other.locator('.notice').innerText()).startsWith('Noch keine Einträge.'));
    await other.locator('.day.is-today').getByRole('button', { name: 'Kommen – jetzt einstempeln' }).click();
    await other.locator('.day.is-today .clock-button', { hasText: 'Gehen' }).waitFor();
    const real = await other.evaluate((key) => JSON.parse(localStorage.getItem(key)), `${REAL}entries`);
    assert.deepEqual(Object.keys(real), [core.today()]);
    assert.deepEqual((await stored(page)).entries, demo.demoEntries(TODAY));
    await other.evaluate((key) => localStorage.removeItem(key), `${REAL}entries`);
    assert.deepEqual(otherProblems, []);
    await other.close();
  });

  await step('Wochen blättern, Markierung über 10 h, „Zur aktuellen Woche“', async () => {
    const data = await stored(page);
    await page.getByRole('button', { name: 'Nächste Woche' }).click();
    await expectWeek(page, core.plusDays(weekStart, 7), data.entries, data.settings);
    assert.equal(await textOf(page.locator('.pill-button')), 'Zur aktuellen Woche');
    await page.getByRole('button', { name: 'Zur aktuellen Woche' }).click();
    await expectWeek(page, weekStart, data.entries, data.settings);
    assert.equal(await page.locator('.pill-button').count(), 0);
    await page.getByRole('button', { name: 'Vorherige Woche' }).click();
    await expectWeek(page, core.plusDays(weekStart, -7), data.entries, data.settings);
    const warning = page.locator('.day.is-over .day-warning');
    assert.equal(await warning.count(), 1);
    assert.equal(await textOf(warning), core.DAILY_MAX_WARNING);
    await page.keyboard.press('ArrowRight');
    await expectWeek(page, weekStart, data.entries, data.settings);
  });

  await step('Tag bearbeiten: Zeiten ändern, Pause, Live-Rechnung, Speichern', async () => {
    await page.locator('.day-main').nth(0).click();
    const dialog = page.locator('dialog.sheet[open]');
    await dialog.waitFor();
    assert.equal(await textOf(dialog.locator('.sheet-title')), 'Montag, 28.09.2026');
    const start = dialog.getByLabel('Beginn', { exact: true });
    const end = dialog.getByLabel('Ende', { exact: true });
    assert.equal(await start.inputValue(), '08:00');
    assert.equal(await end.inputValue(), '18:45');
    assert.ok(await dialog.getByRole('radio', { name: 'Arbeit' }).isChecked());
    await end.fill('17:00');
    const rows = async () => (await dialog.locator('.preview-row').allInnerTexts()).map((row) => clean(row).replace(/\s+/g, ' '));
    assert.deepEqual(await rows(), ['Anwesenheit 9:00 h', '− Pause (automatisch) 0:30 h', '= Arbeitszeit 8:30 h']);
    const pause = dialog.getByLabel('Tatsächliche Pause (Min.)');
    assert.equal(await pause.getAttribute('placeholder'), 'optional');
    await pause.fill('4a5');
    assert.equal(await pause.inputValue(), '45');
    assert.deepEqual(await rows(), ['Anwesenheit 9:00 h', '− Pause 0:45 h', '= Arbeitszeit 8:15 h']);
    assert.equal(await textOf(dialog.locator('.group-footer')), core.breakFieldHint(core.defaultSettings()));
    await shot(page, 'day-edit');
    await dialog.getByRole('button', { name: 'Speichern' }).click();
    await closeSheet(page);
    const data = await stored(page);
    assert.deepEqual(data.entriesJson['2026-09-28'], { type: 'WORK', start: '08:00', end: '17:00', break: 45 });
    await expectWeek(page, weekStart, data.entries, data.settings);
    assert.equal(await textOf(page.locator('.day-value').nth(0)), '8:15 h');
  });

  await step('Tag bearbeiten: Vorschlag beim Antippen, Urlaub, Abbrechen, Löschen', async () => {
    const friday = page.locator('.day-main').nth(4);
    await friday.click();
    let dialog = page.locator('dialog.sheet[open]');
    await dialog.waitFor();
    assert.equal(await dialog.getByRole('button', { name: 'Löschen', exact: true }).count(), 0);
    const start = dialog.getByLabel('Beginn', { exact: true });
    const end = dialog.getByLabel('Ende', { exact: true });
    assert.equal(await start.inputValue(), '');
    await start.click();
    assert.equal(await start.inputValue(), '08:00');
    await end.click();
    assert.equal(await end.inputValue(), core.formatTime(core.defaultEndTime('2026-10-02', 480, 0, core.defaultSettings(), null)));
    assert.equal(await end.inputValue(), '18:45');
    await dialog.getByRole('button', { name: 'Ende löschen' }).click();
    assert.equal(await end.inputValue(), '');
    assert.ok(await dialog.locator('.preview').isHidden());
    await dialog.locator('.segment', { hasText: 'Urlaub' }).click();
    assert.ok(await dialog.locator('.work-section').isHidden());
    assert.equal(await textOf(dialog.locator('.absence-note')), 'Urlaub: Es werden 10:00 h (Tagessoll) gutgeschrieben.');
    await dialog.getByRole('button', { name: 'Speichern' }).click();
    await closeSheet(page);
    let data = await stored(page);
    assert.deepEqual(data.entriesJson['2026-10-02'], { type: 'VACATION', break: 0 });
    assert.equal(await textOf(page.locator('.day-detail').nth(4)), 'Urlaub · Tagessoll gutgeschrieben');
    await expectWeek(page, weekStart, data.entries, data.settings);

    // Abbrechen ändert nichts
    await page.locator('.day-main').nth(0).click();
    dialog = page.locator('dialog.sheet[open]');
    await dialog.waitFor();
    await dialog.getByLabel('Beginn', { exact: true }).fill('06:00');
    await dialog.getByRole('button', { name: 'Abbrechen' }).click();
    await closeSheet(page);
    assert.deepEqual((await stored(page)).entriesJson['2026-09-28'], { type: 'WORK', start: '08:00', end: '17:00', break: 45 });

    // Escape schließt ebenfalls
    await page.locator('.day-main').nth(0).click();
    await page.locator('dialog.sheet[open]').waitFor();
    await page.keyboard.press('Escape');
    await closeSheet(page);

    await page.locator('.day-main').nth(4).click();
    dialog = page.locator('dialog.sheet[open]');
    await dialog.waitFor();
    assert.ok(await dialog.getByRole('radio', { name: 'Urlaub' }).isChecked());
    await dialog.getByRole('button', { name: 'Löschen', exact: true }).click();
    await closeSheet(page);
    data = await stored(page);
    assert.equal(data.entriesJson['2026-10-02'], undefined);
    assert.equal(await textOf(page.locator('.day-detail').nth(4)), 'Kein Eintrag – tippen zum Erfassen');
  });

  await step('Stempeln: Gehen und Kommen auf der Karte von heute', async () => {
    const today = page.locator('.day.is-today');
    await today.getByRole('button', { name: 'Gehen – jetzt ausstempeln' }).click();
    await today.locator('.clock-button').waitFor({ state: 'detached' });
    let data = await stored(page);
    assert.deepEqual(data.entriesJson[TODAY], { type: 'WORK', start: '08:15', end: '15:00', break: 0 });
    assert.equal(await textOf(today.locator('.day-detail')), '08:15 – 15:00 · Pause 0:30 h (auto)');
    await expectWeek(page, weekStart, data.entries, data.settings);

    // Eintrag löschen, dann neu einstempeln
    await today.locator('.day-main').click();
    await page.locator('dialog.sheet[open]').getByRole('button', { name: 'Löschen', exact: true }).click();
    await closeSheet(page);
    await today.getByRole('button', { name: 'Kommen – jetzt einstempeln' }).click();
    await page.locator('.day.is-today .clock-button', { hasText: 'Gehen' }).waitFor();
    data = await stored(page);
    assert.deepEqual(data.entriesJson[TODAY], { type: 'WORK', start: '15:00', break: 0 });
    await expectWeek(page, weekStart, data.entries, data.settings);
    // Für die weiteren Schritte wieder wie in den Beispieldaten (08:15 bis 15:00)
    await today.locator('.day-main').click();
    const dialog = page.locator('dialog.sheet[open]');
    await dialog.getByLabel('Beginn', { exact: true }).fill('08:15');
    await dialog.getByLabel('Ende', { exact: true }).fill('15:00');
    await dialog.getByRole('button', { name: 'Speichern' }).click();
    await closeSheet(page);
  });

  await step('Woche teilen (ohne Teilen-Menü: Zwischenablage)', async () => {
    await page.getByRole('button', { name: 'Woche teilen' }).click();
    await waitForToast(page, 'Woche in die Zwischenablage kopiert');
    const data = await stored(page);
    const summary = core.summarizeWeek(weekStart, data.entries, data.settings, now);
    const clipboard = await page.evaluate(() => navigator.clipboard.readText());
    assert.equal(clipboard, core.weekShareText(summary, data.settings.weeklyHoursAreLimit));
    assert.ok(clipboard.startsWith('Arbeitszeit KW 40 (28.09. – 04.10.2026)'));
  });

  await step('Einstellungen: Felder, Prüfung, gesetzliche Werte, Speichern', async () => {
    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.locator('.screen-settings').waitFor();
    assert.ok(page.url().endsWith('#einstellungen'));
    assert.equal(await page.title(), 'Einstellungen – Arbeitszeitrechner');
    const weekly = page.getByLabel('Wochenarbeitszeit (Std.)');
    const days = page.getByLabel('Arbeitstage pro Woche');
    const save = page.getByRole('button', { name: 'Speichern', exact: true });
    const hint = page.locator('.row-hint').first();
    assert.equal(await weekly.inputValue(), '20');
    assert.equal(await days.inputValue(), '2');
    assert.equal(await textOf(hint), 'Tagessoll: 10:00 h');
    await shot(page, 'settings');
    await shot(page, 'settings-full', { fullPage: true });

    await weekly.fill('abc');
    assert.equal(await textOf(hint), 'Bitte z. B. 40, 38,5 oder 38:30 eingeben');
    assert.equal(await weekly.getAttribute('aria-invalid'), 'true');
    assert.ok(await save.isDisabled());
    await weekly.fill('38,5');
    assert.equal(await textOf(hint), 'Tagessoll: 19:15 h');
    assert.ok(await save.isEnabled());
    await days.fill('5x9');
    assert.equal(await days.inputValue(), '5');
    assert.equal(await textOf(hint), 'Tagessoll: 7:42 h');
    await days.fill('');
    assert.ok(await save.isDisabled());
    await days.fill('5');

    await page.getByRole('switch', { name: 'Wochenstunden sind Obergrenze' }).click();
    assert.equal(await page.getByRole('switch', { name: 'Wochenstunden sind Obergrenze' }).isChecked(), false);

    const ruleAfter = page.getByLabel('Ab mehr als (Std.)').first();
    const ruleBreak = page.getByLabel('Pause (Min.)').first();
    await ruleAfter.fill('x');
    assert.ok(await save.isDisabled());
    await page.getByRole('switch', { name: 'Pausen automatisch abziehen' }).click();
    assert.ok(await page.locator('.rule-section').isHidden());
    assert.ok(await save.isEnabled()); // ohne automatischen Abzug zählen die Regeln nicht
    await page.getByRole('switch', { name: 'Pausen automatisch abziehen' }).click();
    assert.ok(await save.isDisabled());
    await ruleBreak.fill('20');
    await page.getByRole('switch', { name: 'Gestaffelt abziehen' }).click();
    await page.getByRole('button', { name: /Gesetzliche Werte wiederherstellen/ }).click();
    assert.equal(await ruleAfter.inputValue(), '6');
    assert.equal(await ruleBreak.inputValue(), '30');
    assert.ok(await page.getByRole('switch', { name: 'Gestaffelt abziehen' }).isChecked());
    assert.ok(await save.isEnabled());

    // Eingaben mit mindestens 16 px – sonst zoomt Safari beim Antippen.
    const sizes = await page.locator('input.text-input').evaluateAll((inputs) =>
      inputs.map((input) => parseFloat(getComputedStyle(input).fontSize)));
    assert.ok(sizes.length >= 6 && sizes.every((size) => size >= 16), String(sizes));

    await save.click();
    await page.locator('.screen-week').waitFor();
    assert.ok(!page.url().includes('#einstellungen'));
    const expected = core.validateSettingsForm({
      weeklyText: '38,5', daysText: '5', isLimit: false, autoBreak: true, gradual: true,
      rule1After: '6', rule1Break: '30', rule2After: '9', rule2Break: '45',
    }, core.defaultSettings()).settings;
    const data = await stored(page);
    assert.deepEqual(data.settings, expected);
    const summary = await expectWeek(page, weekStart, data.entries, data.settings);
    assert.equal(await textOf(page.locator('.summary-target')), '/ 38:30 h');
    assert.equal(await textOf(page.locator('.stat-label').first()), summary.balanceMinutes < 0 ? 'Noch offen' : 'Überstunden');

    // Zurück-Knopf des Browsers verlässt die Einstellungen ohne Speichern
    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.locator('.screen-settings').waitFor();
    await page.getByLabel('Wochenarbeitszeit (Std.)').fill('20');
    await page.goBack();
    await page.locator('.screen-week').waitFor();
    assert.deepEqual((await stored(page)).settings, expected);
  });

  await step('Stundenzettel: Zusammenfassung und CSV byte-genau wie core.js', async () => {
    await page.getByRole('button', { name: 'Stundenzettel exportieren' }).click();
    const dialog = page.locator('dialog.sheet[open]');
    await dialog.waitFor();
    const data = await stored(page);
    const month = core.initialExportMonth(weekStart, TODAY);
    assert.equal(month, '2026-09');
    assert.equal(await textOf(dialog.locator('.month-label')), 'September 2026');
    const summary = core.monthSummary(month, data.entries, data.settings);
    assert.equal(await textOf(dialog.locator('.month-summary')), core.monthSummaryText(summary));
    assert.equal(await dialog.getByRole('button', { name: 'Teilen' }).count(), 0); // kein Teilen-Menü in Chromium/Linux
    await shot(page, 'month-export');
    const [download] = await Promise.all([
      page.waitForEvent('download'),
      dialog.getByRole('button', { name: 'Speichern' }).click(),
    ]);
    assert.equal(download.suggestedFilename(), 'Arbeitszeit-2026-09.csv');
    const bytes = fs.readFileSync(await download.path());
    assert.deepEqual([...bytes.subarray(0, 3)], [0xef, 0xbb, 0xbf]);
    assert.ok(bytes.equals(Buffer.from(core.monthCsv(month, data.entries, data.settings), 'utf8')));
    await waitForToast(page, 'Stundenzettel gespeichert');

    await dialog.getByRole('button', { name: 'Vorheriger Monat' }).click();
    assert.equal(await textOf(dialog.locator('.month-label')), 'August 2026');
    assert.equal(await textOf(dialog.locator('.month-summary')), 'Keine Einträge in diesem Monat.');
    assert.ok(await dialog.getByRole('button', { name: 'Speichern' }).isDisabled());
    await dialog.getByRole('button', { name: 'Nächster Monat' }).click();
    await dialog.getByRole('button', { name: 'Nächster Monat' }).click();
    assert.equal(await textOf(dialog.locator('.month-label')), 'Oktober 2026');
    await dialog.getByRole('button', { name: 'Schließen' }).click();
    await closeSheet(page);
  });

  await step('Backup speichern (Download, Format wie Android)', async () => {
    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.locator('.screen-settings').waitFor();
    const [download] = await Promise.all([
      page.waitForEvent('download'),
      page.getByRole('button', { name: 'Backup jetzt speichern' }).click(),
    ]);
    assert.equal(download.suggestedFilename(), `Arbeitszeit-Backup-${TODAY}.json`);
    backupPath = await download.path();
    backupText = fs.readFileSync(backupPath, 'utf8');
    const data = await stored(page);
    assert.equal(backupText, core.createBackup(data.entries, data.settings, now));
    assert.ok(backupText.startsWith('{\n  "app": "Arbeitszeitrechner",\n  "version": 1,\n  "createdAt": "2026-09-30T15:00"'));
    const parsed = core.parseBackup(backupText);
    assert.deepEqual(parsed.settings, data.settings);
    assert.deepEqual(core.mergeBackup({}, parsed), data.entries);
    await waitForToast(page, 'Backup gespeichert');
    assert.equal(await textOf(page.locator('.group-footer.is-accent')), 'Zuletzt gesichert: 30.09.2026, 15:00');
  });

  await step('Backup wiederherstellen: ungültige Datei wird abgelehnt', async () => {
    const before = await stored(page);
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.getByRole('button', { name: 'Backup wiederherstellen' }).click(),
    ]);
    await chooser.setFiles({ name: 'kaputt.json', mimeType: 'application/json', buffer: Buffer.from('{"foo": 1}') });
    await waitForToast(page, core.BACKUP_ERROR_MESSAGE);
    assert.equal(await page.locator('dialog[open]').count(), 0);
    assert.deepEqual(await stored(page), before);
  });

  await step('Backup wiederherstellen in leeren Speicher (Hinweis-Karte, Bestätigung)', async () => {
    const expected = await stored(page);
    await page.evaluate(() => localStorage.clear());
    await page.goto(`${base}?now=${NOW}`);
    await page.locator('.day').first().waitFor();
    const notice = page.locator('.notice');
    assert.ok(clean(await notice.innerText()).startsWith('Noch keine Einträge. Tippe auf einen Tag, um loszulegen.'));
    await shot(page, 'week-empty');
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      notice.getByRole('button', { name: 'Backup wiederherstellen' }).click(),
    ]);
    await chooser.setFiles(backupPath);
    const alert = page.locator('dialog.alert[open]');
    await alert.waitFor();
    assert.equal(await textOf(alert.locator('.alert-title')), 'Backup wiederherstellen?');
    assert.equal(await textOf(alert.locator('.alert-message')), core.restoreSummaryText(core.parseBackup(backupText)));
    await shot(page, 'restore-dialog');
    await alert.getByRole('button', { name: 'Wiederherstellen' }).click();
    await waitForToast(page, 'Backup wiederhergestellt');
    const data = await stored(page);
    assert.deepEqual(data.entries, expected.entries);
    assert.deepEqual(data.settings, expected.settings);
    assert.equal(await page.locator('.notice').count(), 0);
    await expectWeek(page, weekStart, data.entries, data.settings);
  });

  await step('Backup der Android-App wiederherstellen (Zusammenführen wie Android)', async () => {
    const vectors = JSON.parse(fs.readFileSync(path.join(WEB, '..', 'shared', 'test-vectors.json'), 'utf8'));
    // Sicherung aus der Android-App (Kotlin), ergänzt um einen leeren Eintrag: Der löscht den Tag.
    const androidJson = JSON.parse(vectors.backup.create.text);
    androidJson.entries.push({ date: '2026-09-24', break: 0, type: 'WORK' });
    const androidText = JSON.stringify(androidJson, null, 2);
    const before = await stored(page);
    assert.ok('2026-09-24' in before.entriesJson && '2026-09-03' in before.entriesJson);
    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.locator('.screen-settings').waitFor();
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.getByRole('button', { name: 'Backup wiederherstellen' }).click(),
    ]);
    await chooser.setFiles({ name: 'Arbeitszeit-Backup.json', mimeType: 'application/json', buffer: Buffer.from(androidText) });
    const alert = page.locator('dialog.alert[open]');
    await alert.waitFor();
    const parsed = core.parseBackup(androidText);
    assert.equal(await textOf(alert.locator('.alert-message')), core.restoreSummaryText(parsed));
    assert.ok((await textOf(alert.locator('.alert-message'))).startsWith('Sicherung vom 30.09.2026, 14:55 mit 8 Einträgen.'));
    await alert.getByRole('button', { name: 'Wiederherstellen' }).click();
    await waitForToast(page, 'Backup wiederhergestellt');
    await page.locator('.screen-week').waitFor(); // wie Android: zurück zur Woche
    const data = await stored(page);
    const expected = core.applyBackup(before.entries, before.settings, parsed);
    assert.deepEqual(data.entries, expected.entries);
    assert.deepEqual(data.settings, expected.settings);
    assert.ok(!('2026-09-24' in data.entriesJson));
    assert.deepEqual(data.entriesJson['2026-09-03'], { type: 'WORK', start: '09:00', end: '14:30', break: 0 });
    assert.deepEqual(data.entriesJson['2026-09-04'], before.entriesJson['2026-09-04']); // bleibt erhalten
    await expectWeek(page, weekStart, data.entries, data.settings);
  });

  await step('Service Worker: registriert, alle Dateien vorgehalten, offline nutzbar', async () => {
    const registration = await page.evaluate(async () => {
      const ready = await navigator.serviceWorker.ready;
      return { scope: ready.scope, active: ready.active !== null };
    });
    assert.equal(registration.scope, base);
    assert.ok(registration.active);
    await page.reload();
    await page.locator('.day').first().waitFor();
    assert.ok(await page.evaluate(() => navigator.serviceWorker.controller !== null));

    const cached = await page.evaluate(async () => {
      const urls = [];
      for (const key of await caches.keys()) {
        for (const request of await (await caches.open(key)).keys()) urls.push(request.url);
      }
      return urls;
    });
    const files = [];
    const walk = (dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        const relative = path.relative(WEB, full).split(path.sep).join('/');
        if (entry.isDirectory()) {
          if (relative !== 'test' && relative !== 'node_modules') walk(full);
        } else if (!['package.json', '.gitignore', 'sw.js'].includes(relative)) {
          files.push(relative);
        }
      }
    };
    walk(WEB);
    for (const file of files) assert.ok(cached.includes(base + file), `Nicht im Cache: ${file}`);
    assert.ok(cached.includes(base));

    const data = await stored(page);
    await context.setOffline(true);
    await page.goto(`${base}?now=${NOW}`);
    await page.locator('.day').first().waitFor();
    await expectWeek(page, weekStart, data.entries, data.settings);
    await context.setOffline(false);
  });

  await step('Keine Konsolenfehler', async () => {
    assert.deepEqual(problems, []);
  });
  await context.close();
}

async function darkMode(browser) {
  const context = await newContext(browser, { colorScheme: 'dark' });
  const page = await context.newPage();
  const problems = watch(page);
  await step('Dunkles Design', async () => {
    await page.goto(`${base}?demo=1&now=${NOW}`);
    await page.locator('.day').first().waitFor();
    const background = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    assert.equal(background, 'rgb(0, 0, 0)');
    await shot(page, 'week-dark');
    await shot(page, 'week-dark-full', { fullPage: true });
    await page.locator('.day-main').nth(2).click();
    await page.locator('dialog.sheet[open]').waitFor();
    await shot(page, 'day-edit-dark');
    await page.keyboard.press('Escape');
    await closeSheet(page);
    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.locator('.screen-settings').waitFor();
    await shot(page, 'settings-dark');
    assert.deepEqual(problems, []);
  });
  await context.close();
}

async function limitWarning(browser) {
  const context = await newContext(browser);
  const page = await context.newPage();
  const problems = watch(page);
  await step('Grenze erreicht: rote Warnung „jetzt ausstempeln“ und Markierung über 10 h', async () => {
    const late = '2026-09-30T20:00';
    await page.goto(`${base}?demo=1&now=${late}`);
    await page.locator('.day').first().waitFor();
    const data = await stored(page);
    const summary = core.summarizeWeek(core.weekStartOf(TODAY), data.entries, data.settings, core.parseLocalDateTime(late));
    assert.equal(summary.actualMinutes, 21 * 60);
    const today = page.locator('.day.is-today');
    assert.equal(await textOf(today.locator('.detail-goal')), '20 h voll – jetzt ausstempeln');
    assert.ok(await today.locator('.day-detail.tone-warning').count() === 1);
    assert.equal(await textOf(today.locator('.day-warning')), core.DAILY_MAX_WARNING);
    assert.ok(await today.locator('.clock-button.is-warning').count() === 1);
    assert.ok(await page.locator('.summary.is-over').count() === 1);
    assert.equal(await textOf(page.locator('.stat-label').first()), 'Grenze überschritten');
    assert.equal(await textOf(page.locator('.stat-value').first()), '+1:00 h');
    await shot(page, 'week-warning');
    assert.deepEqual(problems, []);
  });
  await context.close();
}

async function desktop(browser) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 860 }, locale: 'de-DE', timezoneId: 'Europe/Berlin' });
  const page = await context.newPage();
  const problems = watch(page);
  await step('Großer Bildschirm: Inhalt mittig, Dialog zentriert', async () => {
    await page.goto(`${base}?demo=1&now=${NOW}`);
    await page.locator('.day').first().waitFor();
    const box = await page.locator('.content').boundingBox();
    assert.ok(box.width <= 672 && Math.abs(box.x + box.width / 2 - 640) < 2, JSON.stringify(box));
    await shot(page, 'week-desktop');
    await page.locator('.day-main').nth(0).click();
    const dialog = page.locator('dialog.sheet[open]');
    await dialog.waitFor();
    const sheet = await dialog.boundingBox();
    assert.ok(Math.abs(sheet.x + sheet.width / 2 - 640) < 2 && sheet.y > 20, JSON.stringify(sheet));
    await shot(page, 'day-edit-desktop');
    await page.keyboard.press('Escape');
    await closeSheet(page);
    assert.deepEqual(problems, []);
  });

  await step('Großer Bildschirm: Speichern-Dialog des Browsers, Abbrechen gilt nicht als gesichert', async () => {
    // Speichern-Dialog (showSaveFilePicker) nachbilden: erst abbrechen, dann speichern
    await page.evaluate(() => {
      window.__saved = [];
      window.__cancel = true;
      window.showSaveFilePicker = async (options) => {
        if (window.__cancel) throw new DOMException('Abgebrochen', 'AbortError');
        const parts = [];
        return {
          createWritable: async () => ({
            write: async (data) => parts.push(await data.text()),
            close: async () => window.__saved.push({ options, text: parts.join('') }),
          }),
        };
      };
    });
    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.locator('.screen-settings').waitFor();
    const button = page.getByRole('button', { name: 'Backup jetzt speichern' });
    await button.click();
    await page.waitForTimeout(300);
    assert.ok(await page.locator('.group-footer.is-accent').isHidden());
    assert.equal(await page.locator('.toast.is-visible').count(), 0);
    assert.equal(await page.evaluate((key) => localStorage.getItem(key), `${DEMO}lastBackup`), null);

    await page.evaluate(() => {
      window.__cancel = false;
    });
    await button.click();
    await waitForToast(page, 'Backup gespeichert');
    const saved = await page.evaluate(() => window.__saved);
    assert.equal(saved.length, 1);
    assert.equal(saved[0].options.suggestedName, `Arbeitszeit-Backup-${TODAY}.json`);
    assert.deepEqual(saved[0].options.types, [{ accept: { 'application/json': ['.json'] } }]);
    const data = await stored(page);
    assert.equal(saved[0].text, core.createBackup(data.entries, data.settings, core.parseLocalDateTime(NOW)));
    assert.equal(await textOf(page.locator('.group-footer.is-accent')), 'Zuletzt gesichert: 30.09.2026, 15:00');
    assert.deepEqual(problems, []);
  });
  await context.close();
}

async function storageFull(browser) {
  const context = await newContext(browser);
  await withoutSavePicker(context);
  const page = await context.newPage();
  const problems = watch(page);
  await step('Speicher voll: Hinweis bleibt sichtbar, Backup enthält die Änderung', async () => {
    await page.goto(`${base}?demo=1&now=${NOW}`);
    await page.locator('.day').first().waitFor();
    await page.evaluate(() => {
      Storage.prototype.setItem = () => {
        throw new DOMException('Speicher voll', 'QuotaExceededError');
      };
    });
    const today = page.locator('.day.is-today');
    await today.getByRole('button', { name: 'Gehen – jetzt ausstempeln' }).click();
    await waitForToast(page, 'Daten konnten nicht gespeichert werden');
    const notice = page.locator('.notice.is-warning');
    assert.equal(await textOf(notice.locator('p')), UNSAVED);
    assert.equal(await textOf(today.locator('.detail-line')), '08:15 – 15:00 · Pause 0:30 h (auto)');
    assert.deepEqual((await stored(page)).entriesJson[TODAY], { type: 'WORK', start: '08:15', break: 0 });
    await shot(page, 'storage-full');

    // Bleibt nach dem Blättern und steht auch in den Einstellungen
    await page.getByRole('button', { name: 'Nächste Woche' }).click();
    await page.getByRole('button', { name: 'Vorherige Woche' }).click();
    assert.equal(await notice.count(), 1);
    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.locator('.screen-settings').waitFor();
    assert.equal(await textOf(page.locator('.group-footer.is-error')), UNSAVED);
    await page.getByRole('button', { name: 'Zurück' }).click();
    await page.locator('.screen-week').waitFor();

    const [download] = await Promise.all([
      page.waitForEvent('download'),
      notice.getByRole('button', { name: 'Backup speichern' }).click(),
    ]);
    const backup = core.parseBackup(fs.readFileSync(await download.path(), 'utf8'));
    assert.deepEqual(core.mergeBackup({}, backup)[TODAY], core.createEntry(TODAY, { start: 495, end: 900 }));
    await waitForToast(page, 'Backup gespeichert');
    assert.equal(await notice.count(), 1); // die Änderung ist weiterhin nicht gespeichert
    assert.deepEqual(problems, []);
  });
  await context.close();
}

async function largeText(browser) {
  const context = await newContext(browser);
  const page = await context.newPage();
  const problems = watch(page);
  const size = (selector) => page.locator(selector).first().evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
  const overflow = () => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);

  await step('Größere Schrift (Dynamic Type): Texte wachsen mit, Kopfleiste fest, nichts ragt heraus', async () => {
    await page.goto(`${base}?demo=1&now=${NOW}`);
    await page.locator('.day').first().waitFor();
    assert.equal(await size('body'), 17);
    assert.equal(await size('.footnote'), 13);
    // Unter iOS setzt "font: -apple-system-body" die Grundschrift; hier wie bei „Größerer Text“ in Stufe XXXL.
    await page.addStyleTag({ content: 'html { font-size: 23px !important; }' });
    assert.equal(await size('.day-title'), 23);
    assert.ok(Math.abs(await size('.footnote') - (13 * 23) / 17) < 0.01);
    assert.equal(await size('.appbar-title'), 20);
    assert.ok(await overflow() <= 0);
    await shot(page, 'week-large-text', { fullPage: true });
    await page.locator('.day-main').nth(0).click();
    await page.locator('dialog.sheet[open]').waitFor();
    await shot(page, 'day-edit-large-text');
    await page.keyboard.press('Escape');
    await closeSheet(page);
    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.locator('.screen-settings').waitFor();
    assert.ok(await overflow() <= 0);
    await shot(page, 'settings-large-text', { fullPage: true });

    // Kleinste Stufe: Eingabefelder bleiben bei 16 px, sonst zoomt Safari beim Antippen
    await page.addStyleTag({ content: 'html { font-size: 14px !important; }' });
    const sizes = await page.locator('input.text-input').evaluateAll((inputs) =>
      inputs.map((input) => parseFloat(getComputedStyle(input).fontSize)));
    assert.ok(sizes.length >= 6 && sizes.every((value) => value >= 16), String(sizes));
    assert.deepEqual(problems, []);
  });
  await context.close();
}

async function narrowScreen(browser) {
  const context = await newContext(browser, { viewport: { width: 320, height: 640 } });
  const page = await context.newPage();
  await step('320 px breit (iPhone SE 1. Generation): Titel ungekürzt, nichts ragt heraus', async () => {
    await page.goto(`${base}?demo=1&now=${NOW}`);
    await page.locator('.day').first().waitFor();
    const title = await page.locator('.appbar-title').evaluate((el) => el.scrollWidth - el.clientWidth);
    assert.ok(title <= 0, `Titel um ${title} px gekürzt`);
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await shot(page, 'week-320');
  });
  await context.close();
}

async function iosFlow(browser) {
  const context = await newContext(browser, { userAgent: IPHONE_UA });
  // Teilen-Menü wie in Safari nachbilden und Aufrufe mitschneiden.
  await context.addInitScript(() => {
    window.__shares = [];
    Object.defineProperty(navigator, 'canShare', { configurable: true, value: () => true });
    Object.defineProperty(navigator, 'share', {
      configurable: true,
      value: async (data) => {
        const files = [];
        for (const file of data.files ?? []) {
          files.push({ name: file.name, type: file.type, bytes: Array.from(new Uint8Array(await file.arrayBuffer())) });
        }
        window.__shares.push({ title: data.title ?? null, text: data.text ?? null, files });
      },
    });
  });
  const page = await context.newPage();
  const problems = watch(page);
  const now = core.parseLocalDateTime(NOW);
  const shares = () => page.evaluate(() => window.__shares);

  await step('iPhone: Installationshinweis im Browser, ohne Einträge', async () => {
    await page.goto(`${base}?now=${NOW}`);
    const hint = page.locator('.install-hint');
    await hint.waitFor();
    assert.ok((await textOf(hint)).includes('Zum Home-Bildschirm hinzufügen: Teilen-Symbol → Zum Home-Bildschirm'));
    assert.equal(await hint.locator('.install-note').count(), 0);
    assert.equal(await hint.getByRole('button', { name: 'Backup speichern' }).count(), 0);
  });

  await step('iPhone: Safari-Tab ohne Backup – Erinnerung, nicht ausblendbar; danach Installationshinweis', async () => {
    await page.goto(`${base}?demo=1&now=${NOW}`);
    const notice = page.locator('.notice');
    await notice.waitFor();
    assert.equal(await textOf(notice.locator('p')), REMINDER_IOS);
    assert.equal(await page.getByRole('button', { name: 'Hinweis ausblenden' }).count(), 0);
    assert.equal(await page.locator('.install-hint').count(), 0);
    await shot(page, 'ios-backup-reminder');

    const data = await stored(page);
    await notice.getByRole('button', { name: 'Backup speichern' }).click();
    await page.waitForFunction(() => window.__shares.length === 1);
    const backup = (await shares())[0].files[0];
    assert.equal(backup.name, `Arbeitszeit-Backup-${TODAY}.json`);
    assert.equal(Buffer.from(backup.bytes).toString('utf8'), core.createBackup(data.entries, data.settings, now));
    await waitForToast(page, 'Backup gespeichert');
    assert.equal(await page.locator('.notice').count(), 0);

    // Mit Einträgen: Hinweis auf den eigenen Speicher der App
    const hint = page.locator('.install-hint');
    assert.ok((await textOf(hint)).includes('Zum Home-Bildschirm hinzufügen: Teilen-Symbol → Zum Home-Bildschirm'));
    assert.equal(await textOf(hint.locator('.install-note')),
      'Die App hat einen eigenen Speicher: Speichere vorher ein Backup und stelle es in der App wieder her.');
    assert.equal(await hint.getByRole('button', { name: 'Backup speichern' }).count(), 1);
    await shot(page, 'ios-install-hint');
  });

  await step('iPhone: Erinnerung kommt nach 7 Tagen ohne Backup wieder', async () => {
    const setLastBackup = (value) => page.evaluate(([key, text]) => localStorage.setItem(key, text), [`${DEMO}lastBackup`, value]);
    await setLastBackup('2026-09-24T18:00'); // vor 6 Tagen
    await page.goto(`${base}?now=${NOW}`);
    await page.locator('.day').first().waitFor();
    assert.equal(await page.locator('.notice').count(), 0);
    await setLastBackup('2026-09-23T09:00'); // vor 7 Tagen
    await page.reload();
    await page.locator('.notice').waitFor();
    assert.equal(await textOf(page.locator('.notice p')), REMINDER_IOS);
    await setLastBackup(NOW);
  });

  await step('iPhone: Woche, Backup und Stundenzettel über das Teilen-Menü', async () => {
    await page.goto(`${base}?now=${NOW}`);
    await page.locator('.day').first().waitFor();
    const data = await stored(page);
    // window.__shares beginnt nach jedem Seitenaufruf leer
    await page.getByRole('button', { name: 'Woche teilen' }).click();
    await page.waitForFunction(() => window.__shares.length === 1);
    const summary = core.summarizeWeek(core.weekStartOf(TODAY), data.entries, data.settings, now);
    assert.deepEqual(await shares(), [{
      title: core.weekShareSubject(summary),
      text: core.weekShareText(summary, data.settings.weeklyHoursAreLimit),
      files: [],
    }]);

    await page.getByRole('button', { name: 'Stundenzettel exportieren' }).click();
    const dialog = page.locator('dialog.sheet[open]');
    await dialog.waitFor();
    await shot(page, 'ios-month-export');
    await dialog.getByRole('button', { name: 'Teilen' }).click();
    await page.waitForFunction(() => window.__shares.length === 2);
    const csvShare = (await shares())[1];
    assert.equal(csvShare.title, 'Stundenzettel September 2026');
    assert.equal(csvShare.files[0].name, 'Arbeitszeit-2026-09.csv');
    assert.equal(csvShare.files[0].type, 'text/csv');
    assert.ok(Buffer.from(csvShare.files[0].bytes).equals(Buffer.from(core.monthCsv('2026-09', data.entries, data.settings), 'utf8')));
    await dialog.getByRole('button', { name: 'Speichern' }).click(); // auf iOS ebenfalls über das Teilen-Menü
    await page.waitForFunction(() => window.__shares.length === 3);
    await waitForToast(page, 'Stundenzettel gespeichert');
    await dialog.getByRole('button', { name: 'Schließen' }).click();
    await closeSheet(page);

    await page.getByRole('button', { name: 'Einstellungen' }).click();
    await page.getByRole('button', { name: 'Backup jetzt speichern' }).click();
    await page.waitForFunction(() => window.__shares.length === 4);
    const backup = (await shares())[3].files[0];
    assert.equal(backup.name, `Arbeitszeit-Backup-${TODAY}.json`);
    assert.equal(backup.type, 'application/json');
    assert.equal(Buffer.from(backup.bytes).toString('utf8'), core.createBackup(data.entries, data.settings, now));
    await waitForToast(page, 'Backup gespeichert');
  });

  await step('iPhone: Hinweis ausblenden bleibt gespeichert, Erinnerung nicht; als App kein Hinweis', async () => {
    await page.goto(`${base}?now=${NOW}`);
    await page.getByRole('button', { name: 'Hinweis ausblenden' }).click();
    assert.equal(await page.locator('.install-hint').count(), 0);
    await page.reload();
    await page.locator('.day').first().waitFor();
    assert.equal(await page.locator('.install-hint').count(), 0);
    await page.evaluate((key) => localStorage.removeItem(key), `${DEMO}lastBackup`);
    await page.reload();
    await page.locator('.notice').waitFor(); // die Erinnerung lässt sich nicht ausblenden

    const standalone = await context.newPage();
    await standalone.addInitScript((prefix) => {
      localStorage.removeItem(`${prefix}installHintDismissed`);
      Object.defineProperty(navigator, 'standalone', { configurable: true, value: true });
    }, DEMO);
    await standalone.goto(`${base}?now=${NOW}`);
    await standalone.locator('.day').first().waitFor();
    assert.equal(await standalone.locator('.install-hint').count(), 0);
    assert.equal(await standalone.locator('.notice').count(), 0); // als App löscht Safari nichts
    await standalone.close();
    assert.deepEqual(problems, []);
  });
  await context.close();
}

async function installability() {
  await step('Manifest, Icons, iOS-Meta-Tags und nur relative Pfade', async () => {
    const manifest = await (await fetch(`${base}manifest.webmanifest`)).json();
    assert.equal(manifest.name, 'Arbeitszeitrechner');
    assert.equal(manifest.short_name, 'Arbeitszeit');
    assert.equal(manifest.display, 'standalone');
    assert.equal(manifest.start_url, './');
    assert.equal(manifest.scope, './');
    assert.ok(manifest.icons.some((item) => item.purpose === 'maskable' && item.sizes === '512x512'));
    for (const item of manifest.icons) {
      const response = await fetch(new URL(item.src, `${base}manifest.webmanifest`));
      assert.equal(response.status, 200, item.src);
      assert.equal(response.headers.get('content-type'), 'image/png');
    }
    const html = fs.readFileSync(path.join(WEB, 'index.html'), 'utf8');
    for (const tag of [
      '<meta name="apple-mobile-web-app-capable" content="yes">',
      '<meta name="apple-mobile-web-app-title" content="Arbeitszeit">',
      '<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">',
      '<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">',
      '<link rel="manifest" href="manifest.webmanifest">',
      'viewport-fit=cover',
    ]) {
      assert.ok(html.includes(tag), tag);
    }
    // GitHub Pages liegt unter /Arbeitszeitrechner/ – absolute Pfade würden ins Leere zeigen.
    const sources = [html, fs.readFileSync(path.join(WEB, 'sw.js'), 'utf8'),
      fs.readFileSync(path.join(WEB, 'manifest.webmanifest'), 'utf8')];
    for (const file of fs.readdirSync(path.join(WEB, 'src'))) sources.push(fs.readFileSync(path.join(WEB, 'src', file), 'utf8'));
    for (const source of sources) {
      assert.ok(!/(?:href|src)=["']\/|["']\/(?:src|icons|sw\.js|index\.html|styles\.css)/.test(source));
      assert.ok(!/https?:\/\/(?!127\.0\.0\.1)/.test(source.replace(/http:\/\/www\.w3\.org\/2000\/svg/g, '')),
        'Keine externen Adressen (offline)');
    }
  });
}

async function main() {
  core = await import(pathToFileURL(path.join(WEB, 'src', 'core.js')).href);
  demo = await import(pathToFileURL(path.join(WEB, 'src', 'demo.js')).href);
  fs.mkdirSync(SHOTS, { recursive: true });
  const server = await startServer();
  base = server.url;
  // LANG sorgt für die deutsche 24-Stunden-Anzeige in den Uhrzeit-Feldern.
  const browser = await chromium.launch({
    args: ['--lang=de-DE'],
    env: { ...process.env, LANG: 'de_DE.UTF-8', LANGUAGE: 'de' },
  });
  try {
    await mainFlow(browser);
    await limitWarning(browser);
    await darkMode(browser);
    await desktop(browser);
    await storageFull(browser);
    await largeText(browser);
    await narrowScreen(browser);
    await iosFlow(browser);
    await installability();
    console.log(`\n${passed} Schritte bestanden. Screenshots: ${path.relative(process.cwd(), SHOTS) || SHOTS}`);
  } finally {
    await browser.close();
    server.child.kill();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
