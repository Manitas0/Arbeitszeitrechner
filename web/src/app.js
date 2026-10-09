// Arbeitszeitrechner – Web-App: Start, Navigation, Wochenübersicht, Stempeln und Sicherung.

import {
  BackupFormatError, applyBackup, backupFileName, breakHintText, clockButtonText, createBackup, dayDetail, dayTitle,
  dayValueText, daysBetween, defaultSettings, entryFor, formatDuration, formatShortDate, initialExportMonth, isLimitExceeded,
  minutesExcluding, nowLocalDateTime, parseBackup, parseLocalDateTime, plusDays, restoreSummaryText,
  summarizeWeek, toggleClock, weekBalanceStat, weekNumber, weekProgress, weekRange, weekShareSubject,
  weekShareText, weekStartOf,
} from './core.js';
import * as store from './store.js';
import { demoEntries } from './demo.js';
import { openDayEdit } from './day-edit.js';
import { openMonthExport } from './month-export.js';
import { settingsScreen } from './settings.js';
import {
  confirmDialog, focusByKey, focusKeyOf, h, icon, isIOS, isSafari, isStandalone, prefersReducedMotion, toast, topDialog,
} from './dom.js';
import { saveFile, shareText } from './files.js';

const REFRESH_MS = 15_000;
const SETTINGS_HASH = '#einstellungen';
/** Safari löscht die Daten einer Seite nach 7 Tagen ohne Besuch – so oft an ein Backup erinnern. */
const BACKUP_REMINDER_DAYS = 7;

// Nur über die URL wirksam (für Tests und Vorführungen): ?now=2026-09-30T15:00 und ?demo=1.
// Beide nutzen einen eigenen Speicher, die echten Daten bleiben unberührt.
const params = new URLSearchParams(window.location.search);
const fixedNow = parseLocalDateTime(params.get('now'));
const demo = params.get('demo') === '1';

const root = document.getElementById('app');
const announcer = document.getElementById('announcer');

const state = {
  entries: {},
  settings: defaultSettings(),
  weekStart: '',
  view: null,
  /** Die aktuelle Woche wird angezeigt – nach Mitternacht am Sonntag mitwandern. */
  followToday: true,
};

let lastWeekKey = '';
let weekScrollY = 0;
let settingsView = null;
let pointerDown = false;
let updateReady = false;
let lastUpdateCheck = 0;

function now() {
  return fixedNow ?? nowLocalDateTime();
}

function reload() {
  state.entries = store.loadEntries();
  state.settings = store.loadSettings();
}

function announce(text) {
  announcer.textContent = '';
  setTimeout(() => {
    announcer.textContent = text;
  }, 50);
}

/** Führt eine Änderung am Speicher aus und zeichnet neu. */
function persist(change) {
  try {
    change();
    store.requestPersistence();
  } catch (error) {
    toast(error instanceof store.StorageError ? error.message : 'Daten konnten nicht gespeichert werden');
  }
  reload();
  if (state.view === 'week') renderWeek();
}

// --- Wochenübersicht ---

function iconButton(name, label, onclick, focusKey) {
  return h('button', {
    type: 'button',
    class: 'icon-button',
    'aria-label': label,
    title: label,
    dataset: { focusKey },
    onclick,
  }, icon(name));
}

function appBar() {
  return h('header', { class: 'appbar' },
    h('div', { class: 'appbar-inner' },
      h('h1', { class: 'appbar-title', text: 'Arbeitszeitrechner' }),
      h('div', { class: 'appbar-actions' },
        iconButton('calendar', 'Stundenzettel exportieren', openExport, 'export'),
        iconButton('share', 'Woche teilen', shareWeek, 'share'),
        iconButton('settings', 'Einstellungen', openSettings, 'settings'))));
}

function hero(summary, isCurrentWeek) {
  return h('section', { class: 'hero', 'aria-label': 'Woche' },
    h('div', { class: 'week-nav' },
      h('button', {
        type: 'button',
        class: 'round-button',
        'aria-label': 'Vorherige Woche',
        title: 'Vorherige Woche',
        dataset: { focusKey: 'previous-week' },
        onclick: () => changeWeek(-1),
      }, icon('chevronLeft')),
      h('div', { class: 'week-heading' },
        h('h2', {
          class: 'week-number',
          tabindex: '-1',
          dataset: { focusKey: 'week-title' },
          text: `KW ${weekNumber(summary.weekStart)}`,
        }),
        h('p', { class: 'week-range', text: weekRange(summary.weekStart) }),
        !isCurrentWeek && h('button', {
          type: 'button',
          class: 'pill-button',
          dataset: { focusKey: 'current-week' },
          onclick: goToCurrentWeek,
        }, 'Zur aktuellen Woche')),
      h('button', {
        type: 'button',
        class: 'round-button',
        'aria-label': 'Nächste Woche',
        title: 'Nächste Woche',
        dataset: { focusKey: 'next-week' },
        onclick: () => changeWeek(1),
      }, icon('chevronRight'))));
}

function stat(label, value, tone) {
  return h('div', { class: `stat tone-${tone}` },
    h('span', { class: 'stat-label', text: label }),
    h('span', { class: 'stat-value', text: value }));
}

function summaryCard(summary, isLimit) {
  const balance = weekBalanceStat(summary, isLimit);
  const percent = Math.round(weekProgress(summary) * 100);
  return h('section', {
    class: `card summary${isLimitExceeded(summary, isLimit) ? ' is-over' : ''}`,
    'aria-labelledby': 'summary-title',
  },
  h('h2', { class: 'summary-label', id: 'summary-title', text: 'Arbeitszeit diese Woche' }),
  h('p', { class: 'summary-hours' },
    h('span', { class: 'summary-actual', text: formatDuration(summary.actualMinutes) }),
    h('span', { class: 'summary-target', text: ` / ${formatDuration(summary.targetMinutes)} h` })),
  h('div', {
    class: 'progress',
    role: 'progressbar',
    'aria-label': 'Fortschritt der Woche',
    'aria-valuemin': 0,
    'aria-valuemax': 100,
    'aria-valuenow': percent,
  }, h('div', { class: 'progress-bar', style: `width: ${percent}%` })),
  h('div', { class: 'stats' },
    stat(balance.label, balance.value, balance.tone),
    stat('Pausen abgezogen', `${formatDuration(summary.breakMinutes)} h`, 'neutral')));
}

/**
 * Höchstens ein Hinweis zum Schutz der Daten, der dringendste: Speichern unmöglich, Backup fällig (nur im
 * Safari-Tab – bei der Home-Bildschirm-App löscht WebKit nichts) oder auf iPhone/iPad „Als App installieren“.
 */
function storageNotice(hasEntries, current) {
  if (store.hasUnsavedData()) return 'unsaved';
  const safariTab = isSafari() && !isStandalone();
  if (safariTab && hasEntries) {
    const last = store.lastBackup();
    if (last == null || daysBetween(last.date, current.date) >= BACKUP_REMINDER_DAYS) return 'backup';
  }
  if (isIOS() && !isStandalone() && !store.installHintDismissed()) return 'install';
  return null;
}

function backupButton() {
  return h('button', {
    type: 'button',
    class: 'text-button',
    dataset: { focusKey: 'backup-hint' },
    onclick: saveBackup,
  }, 'Backup speichern');
}

function unsavedNotice() {
  return h('section', { class: 'card notice is-warning' },
    h('p', { text: store.UNSAVED_MESSAGE }),
    h('div', { class: 'notice-actions' }, backupButton()));
}

function backupNotice() {
  return h('section', { class: 'card notice' },
    h('p', {
      text: 'Safari löscht die Daten, wenn die Seite 7 Tage lang nicht geöffnet wird. Speichere regelmäßig ' +
        (isIOS() ? 'ein Backup – oder nutze die App vom Home-Bildschirm und stelle das Backup dort wieder her.'
          : 'ein Backup.'),
    }),
    h('div', { class: 'notice-actions' }, backupButton()));
}

function installHint(hasEntries) {
  return h('aside', { class: 'card install-hint', 'aria-label': 'Als App installieren' },
    h('img', { class: 'install-icon', src: 'icons/apple-touch-icon.png', alt: '', width: 40, height: 40 }),
    h('div', { class: 'install-text' },
      h('p', { class: 'install-title', text: 'Als App installieren' }),
      h('p', null, 'Zum Home-Bildschirm hinzufügen: ',
        h('span', { class: 'nowrap' }, 'Teilen-Symbol', icon('share', 'inline-icon')), ' ',
        h('span', { class: 'nowrap' }, '→ Zum Home-Bildschirm')),
      // Die Home-Bildschirm-App hat einen eigenen Speicher und startet sonst leer.
      hasEntries && h('p', {
        class: 'install-note',
        text: 'Die App hat einen eigenen Speicher: Speichere vorher ein Backup und stelle es in der App wieder her.',
      }),
      hasEntries && h('div', { class: 'install-actions' }, backupButton())),
    h('button', {
      type: 'button',
      class: 'icon-button is-small',
      'aria-label': 'Hinweis ausblenden',
      title: 'Hinweis ausblenden',
      onclick: () => {
        store.dismissInstallHint();
        renderWeek();
      },
    }, icon('close')));
}

function restoreHint() {
  return h('section', { class: 'card notice' },
    h('p', {
      text: 'Noch keine Einträge. Tippe auf einen Tag, um loszulegen. Hast du ein Backup, kannst du es in den ' +
        'Einstellungen wiederherstellen.',
    }),
    h('div', { class: 'notice-actions' },
      h('button', {
        type: 'button',
        class: 'text-button',
        dataset: { focusKey: 'restore-hint' },
        onclick: startRestore,
      }, 'Backup wiederherstellen')));
}

function dayCard(day, { today, summary, weekReached }) {
  const settings = state.settings;
  const entry = day.entry;
  const isToday = entry.date === today;
  const detail = dayDetail(day, settings, minutesExcluding(summary, entry.date), weekReached);
  const [firstLine, ...goalLines] = detail.text.split('\n');
  const value = dayValueText(day);
  const clockText = clockButtonText(entry, isToday);
  const classes = ['day'];
  if (isToday) classes.push('is-today');
  if (day.exceedsDailyMax) classes.push('is-over');
  if (detail.tone === 'warning') classes.push('is-warning');

  return h('li', { class: classes.join(' '), 'aria-current': isToday ? 'date' : null },
    h('button', {
      type: 'button',
      class: 'day-main',
      dataset: { focusKey: `day-${entry.date}` },
      onclick: () => editDay(entry.date),
    },
    h('span', { class: 'day-head' },
      h('span', { class: 'day-names' },
        h('span', { class: 'day-title', text: dayTitle(entry.date, isToday) }),
        h('span', { class: 'day-date', text: formatShortDate(entry.date) })),
      h('span', { class: `day-value${value === '–' ? ' is-empty' : ''}`, text: value })),
    h('span', { class: `day-detail tone-${detail.tone}` },
      h('span', { class: 'detail-line', text: firstLine }),
      goalLines.map((line) => h('span', { class: 'detail-goal', text: line }))),
    detail.dailyMaxWarning && h('span', { class: 'day-warning' },
      icon('warning'),
      h('span', { text: detail.dailyMaxWarning }))),
    clockText && h('div', { class: 'clock-row' },
      h('button', {
        type: 'button',
        class: `clock-button${detail.tone === 'warning' ? ' is-warning' : ''}`,
        dataset: { focusKey: 'clock' },
        onclick: clock,
      }, icon(entry.start == null ? 'play' : 'stop'), h('span', { text: clockText }))));
}

function weekScreen(summary, today, { hasEntries, notice, slide }) {
  const settings = state.settings;
  const weekReached = summary.actualMinutes >= settings.weeklyTargetMinutes;
  const context = { today, summary, weekReached };
  return h('div', { class: 'screen screen-week' },
    appBar(),
    hero(summary, summary.weekStart === weekStartOf(today)),
    h('main', { class: 'content', 'aria-label': 'Wochenübersicht' },
      summaryCard(summary, settings.weeklyHoursAreLimit),
      notice === 'unsaved' && unsavedNotice(),
      notice === 'backup' && backupNotice(),
      notice === 'install' && installHint(hasEntries),
      !hasEntries && restoreHint(),
      h('ol', { class: `days${slide ? ` slide-${slide}` : ''}`, 'aria-label': 'Tage der Woche' },
        summary.days.map((day) => dayCard(day, context))),
      h('p', { class: 'footnote', text: breakHintText(settings) })));
}

/** Zeichnet die Woche neu, aber nur, wenn sich etwas Sichtbares geändert hat (außer mit force). */
function renderWeek({ force = false, slide = null } = {}) {
  const current = now();
  const summary = summarizeWeek(state.weekStart, state.entries, state.settings, current);
  const hasEntries = Object.keys(state.entries).length > 0;
  const notice = storageNotice(hasEntries, current);
  const key = JSON.stringify([summary, state.settings, current.date, hasEntries, notice]);
  if (!force && !slide && key === lastWeekKey) return;
  lastWeekKey = key;

  const focusKey = focusKeyOf(document.activeElement);
  root.replaceChildren(weekScreen(summary, current.date, { hasEntries, notice, slide }));
  if (focusKey && !focusByKey(root, focusKey)) focusByKey(root, 'week-title');
}

function changeWeek(delta) {
  state.weekStart = plusDays(state.weekStart, 7 * delta);
  state.followToday = state.weekStart === weekStartOf(now().date);
  renderWeek({ slide: prefersReducedMotion() ? null : delta < 0 ? 'right' : 'left' });
  announce(`KW ${weekNumber(state.weekStart)}, ${weekRange(state.weekStart)}`);
}

function goToCurrentWeek() {
  const target = weekStartOf(now().date);
  const delta = target < state.weekStart ? -1 : 1;
  state.weekStart = target;
  state.followToday = true;
  renderWeek({ slide: prefersReducedMotion() ? null : delta < 0 ? 'right' : 'left' });
  announce(`KW ${weekNumber(state.weekStart)}, ${weekRange(state.weekStart)}`);
}

/** Wurde die aktuelle Woche angezeigt und ist inzwischen eine neue Woche, dorthin wechseln. */
function followToday() {
  const currentWeek = weekStartOf(now().date);
  if (state.followToday && state.weekStart !== currentWeek) state.weekStart = currentWeek;
}

function editDay(date) {
  reload();
  openDayEdit({
    entry: entryFor(state.entries, date),
    settings: state.settings,
    now,
    onSave: (entry) => persist(() => store.saveEntry(entry)),
    onDelete: () => persist(() => store.deleteEntry(date)),
  });
}

/** Kommen bzw. Gehen für heute auf die aktuelle Uhrzeit stempeln. */
function clock() {
  reload();
  const current = now();
  const result = toggleClock(entryFor(state.entries, current.date), current.minutes);
  if (result) persist(() => store.saveEntry(result.entry));
}

function shareWeek() {
  reload();
  const summary = summarizeWeek(state.weekStart, state.entries, state.settings, now());
  shareText(weekShareSubject(summary), weekShareText(summary, state.settings.weeklyHoursAreLimit))
    .then((result) => {
      if (result === 'copied') toast('Woche in die Zwischenablage kopiert');
    })
    .catch(() => toast('Teilen nicht möglich'));
}

function openExport() {
  reload();
  openMonthExport({
    initialMonth: initialExportMonth(state.weekStart, now().date),
    entries: state.entries,
    settings: state.settings,
  });
}

// --- Sicherung ---

const fileInput = h('input', {
  type: 'file',
  accept: '.json,application/json,text/plain',
  class: 'sr-only',
  tabindex: '-1',
  'aria-hidden': 'true',
  onchange: () => {
    const file = fileInput.files?.[0];
    if (file) restoreFrom(file);
  },
});

function startRestore() {
  fileInput.value = '';
  fileInput.click();
}

async function restoreFrom(file) {
  let data;
  try {
    data = parseBackup(await file.text());
  } catch (error) {
    toast(error instanceof BackupFormatError ? error.message : 'Datei konnte nicht gelesen werden');
    return;
  }
  const confirmed = await confirmDialog({
    title: 'Backup wiederherstellen?',
    message: restoreSummaryText(data),
    confirmLabel: 'Wiederherstellen',
  });
  if (!confirmed) return;
  try {
    const result = applyBackup(store.loadEntries(), store.loadSettings(), data);
    store.replaceEntries(result.entries);
    store.saveSettings(result.settings);
    store.requestPersistence();
  } catch {
    toast('Daten konnten nicht gespeichert werden');
    return;
  }
  reload();
  toast('Backup wiederhergestellt');
  // Wie unter Android: danach zurück zur Wochenübersicht.
  if (state.view === 'settings') closeSettings();
  else renderWeek({ force: true });
}

function saveBackup() {
  reload();
  const current = now();
  const file = new File([createBackup(state.entries, state.settings, current)], backupFileName(current.date), {
    type: 'application/json',
  });
  saveFile(file, 'Arbeitszeit-Backup')
    .then((saved) => {
      if (!saved) return;
      store.setLastBackup(current);
      settingsView?.setLastBackup(current);
      if (state.view === 'week') renderWeek();
      toast('Backup gespeichert');
    })
    .catch(() => toast('Backup konnte nicht gespeichert werden'));
}

// --- Navigation zwischen Woche und Einstellungen ---

function showWeek(fromSettings) {
  state.view = 'week';
  settingsView = null;
  document.title = 'Arbeitszeitrechner';
  followToday();
  renderWeek({ force: true });
  window.scrollTo(0, weekScrollY);
  if (fromSettings) focusByKey(root, 'settings');
}

function showSettings() {
  state.view = 'settings';
  lastWeekKey = '';
  document.title = 'Einstellungen – Arbeitszeitrechner';
  settingsView = settingsScreen({
    settings: state.settings,
    lastBackup: store.lastBackup(),
    unsaved: store.hasUnsavedData(),
    onBack: closeSettings,
    onSave: (settings) => {
      persist(() => store.saveSettings(settings));
      closeSettings();
    },
    onBackup: saveBackup,
    onRestore: startRestore,
  });
  root.replaceChildren(settingsView.element);
  window.scrollTo(0, 0);
  settingsView.focusTitle();
}

function route() {
  const view = window.location.hash === SETTINGS_HASH ? 'settings' : 'week';
  if (view === state.view) return;
  const fromSettings = state.view === 'settings';
  if (state.view === 'week') weekScrollY = window.scrollY;
  if (view === 'settings') showSettings();
  else showWeek(fromSettings);
}

function openSettings() {
  window.history.pushState({ view: 'settings' }, '', SETTINGS_HASH);
  route();
}

function closeSettings() {
  if (window.history.state?.view === 'settings') {
    window.history.back();
  } else {
    window.history.replaceState(null, '', window.location.pathname + window.location.search);
    route();
  }
}

// --- Gesten und Tastatur ---

/** Wischen nach links/rechts blättert die Woche (nicht am Bildschirmrand, dort liegen System-Gesten). */
function enableSwipe() {
  let origin = null;
  root.addEventListener('touchstart', (event) => {
    const touch = event.touches[0];
    const edge = 24;
    origin = event.touches.length === 1 && touch.clientX > edge && touch.clientX < window.innerWidth - edge
      ? { x: touch.clientX, y: touch.clientY, time: event.timeStamp }
      : null;
  }, { passive: true });
  root.addEventListener('touchend', (event) => {
    if (!origin || state.view !== 'week' || topDialog()) return;
    const touch = event.changedTouches[0];
    const dx = touch.clientX - origin.x;
    const dy = touch.clientY - origin.y;
    const fast = event.timeStamp - origin.time < 600;
    origin = null;
    if (fast && Math.abs(dx) > 70 && Math.abs(dy) < Math.abs(dx) * 0.5) changeWeek(dx < 0 ? 1 : -1);
  }, { passive: true });
}

function enableKeyboard() {
  document.addEventListener('keydown', (event) => {
    if (state.view !== 'week' || topDialog() || event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.target.closest?.('input, textarea, select')) return;
    if (event.key === 'ArrowLeft') changeWeek(-1);
    else if (event.key === 'ArrowRight') changeWeek(1);
  });
}

/** Beim Überziehen oben die Farbe der Kopfleiste zeigen, unten die des Hintergrunds. */
function trackScroll() {
  const update = () => document.documentElement.classList.toggle('is-scrolled', window.scrollY > 120);
  window.addEventListener('scroll', update, { passive: true });
  update();
}

// --- Service Worker (offline) ---

function registerServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  const hadController = navigator.serviceWorker.controller !== null;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (hadController) updateReady = true;
  });
  const register = () => {
    navigator.serviceWorker.register('./sw.js', { updateViaCache: 'none' }).catch(() => {});
  };
  if (document.readyState === 'complete') register();
  else window.addEventListener('load', register);
}

function checkForUpdate() {
  if (!('serviceWorker' in navigator) || Date.now() - lastUpdateCheck < 60 * 60 * 1000) return;
  lastUpdateCheck = Date.now();
  navigator.serviceWorker.getRegistration().then((registration) => registration?.update()).catch(() => {});
}

/** Eine neue Version erst laden, wenn die App im Hintergrund ist und nichts offen ist. */
function applyUpdateIfIdle() {
  if (updateReady && state.view === 'week' && !topDialog()) window.location.reload();
}

// --- Start ---

function start() {
  if (demo || fixedNow) store.useDemoStorage();
  if (demo && !store.hasEntries()) {
    try {
      store.replaceEntries(demoEntries(now().date));
    } catch {
      toast('Beispieldaten konnten nicht gespeichert werden');
    }
  }
  reload();
  state.weekStart = weekStartOf(now().date);
  window.history.scrollRestoration = 'manual';
  document.body.append(fileInput);

  window.addEventListener('popstate', route);
  window.addEventListener('pointerdown', () => {
    pointerDown = true;
  }, true);
  for (const type of ['pointerup', 'pointercancel']) {
    window.addEventListener(type, () => {
      pointerDown = false;
    }, true);
  }
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      reload();
      if (state.view === 'week') {
        followToday();
        renderWeek();
      }
      checkForUpdate();
    } else {
      applyUpdateIfIdle();
    }
  });
  store.onExternalChange(() => {
    reload();
    if (state.view === 'week') renderWeek();
  });
  // Laufende Arbeitszeit von heute regelmäßig aktualisieren (nicht mitten in einem Tipp).
  setInterval(() => {
    if (state.view !== 'week' || document.visibilityState !== 'visible' || pointerDown) return;
    followToday();
    renderWeek();
  }, REFRESH_MS);

  enableSwipe();
  enableKeyboard();
  trackScroll();
  route();
  registerServiceWorker();
}

start();
