// Einstellungen: Arbeitszeit, Pausenregeln, Daten sichern und Hinweis.

import {
  filterDaysInput, filterBreakInput, formatDateTime, resetBreakRulesForm, settingsForm, validateSettingsForm,
} from './core.js';
import { h, icon, uid } from './dom.js';
import { UNSAVED_MESSAGE } from './store.js';

function textInput({ value, inputmode, onInput, label }) {
  const input = h('input', {
    type: 'text',
    id: uid('field'),
    class: 'text-input',
    inputmode,
    autocomplete: 'off',
    enterkeyhint: 'done',
    spellcheck: 'false',
    value,
  });
  input.addEventListener('input', () => onInput(input));
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') input.blur();
  });
  const row = h('div', { class: 'form-row field-row' },
    h('div', { class: 'field-line' },
      h('label', { class: 'row-label', for: input.id, text: label }),
      input));
  return { input, row };
}

function withHint(field, text) {
  const hint = h('p', { class: 'row-hint', id: uid('hint'), text });
  field.input.setAttribute('aria-describedby', hint.id);
  field.row.append(hint);
  return hint;
}

function switchRow({ title, description, checked, onChange }) {
  const id = uid('switch');
  const titleId = uid('switch-title');
  const descriptionId = uid('switch-description');
  const input = h('input', {
    type: 'checkbox',
    role: 'switch',
    id,
    class: 'switch',
    checked,
    'aria-labelledby': titleId,
    'aria-describedby': descriptionId,
  });
  input.addEventListener('change', () => onChange(input.checked));
  const row = h('div', { class: 'form-row switch-row' },
    h('label', { class: 'switch-text', for: id },
      h('span', { class: 'row-title', id: titleId, text: title }),
      h('span', { class: 'row-description', id: descriptionId, text: description })),
    input);
  return { input, row };
}

function setInvalid(input, invalid) {
  input.classList.toggle('is-invalid', invalid);
  if (invalid) input.setAttribute('aria-invalid', 'true');
  else input.removeAttribute('aria-invalid');
}

function digitFilter(filter, assign) {
  return (input) => {
    const filtered = filter(input.value);
    if (filtered !== input.value) input.value = filtered;
    assign(filtered);
  };
}

/**
 * Baut die Einstellungen. Liefert { element, focusTitle(), setLastBackup(zeitpunkt) }.
 * unsaved: Daten liegen nur im Arbeitsspeicher. onSave(neue Einstellungen), onBack(), onBackup(), onRestore().
 */
export function settingsScreen({ settings, lastBackup, unsaved, onSave, onBack, onBackup, onRestore }) {
  let form = settingsForm(settings);

  const weekly = textInput({
    label: 'Wochenarbeitszeit (Std.)',
    value: form.weeklyText,
    inputmode: 'decimal',
    onInput: (input) => {
      form.weeklyText = input.value;
      validate();
    },
  });
  const weeklyHint = withHint(weekly, '');

  const days = textInput({
    label: 'Arbeitstage pro Woche',
    value: form.daysText,
    inputmode: 'numeric',
    onInput: digitFilter(filterDaysInput, (text) => {
      form.daysText = text;
      validate();
    }),
  });
  const daysHint = withHint(days, 'Urlaub, Krankheit und Feiertage werden mit dem Tagessoll gutgeschrieben.');

  const limit = switchRow({
    title: 'Wochenstunden sind Obergrenze',
    description: 'Zum Beispiel die 20-Stunden-Grenze für Werkstudenten. Die App zeigt, wie viel bis zur Grenze ' +
      'fehlt, und warnt, wenn sie überschritten ist. Aus: Mehrarbeit wird als Überstunden angezeigt.',
    checked: form.isLimit,
    onChange: (checked) => {
      form.isLimit = checked;
      validate();
    },
  });

  const autoBreak = switchRow({
    title: 'Pausen automatisch abziehen',
    description: 'Die gesetzliche Mindestpause wird abgezogen, auch wenn keine oder eine kürzere Pause ' +
      'eingetragen ist.',
    checked: form.autoBreak,
    onChange: (checked) => {
      form.autoBreak = checked;
      validate();
    },
  });

  const ruleFields = [1, 2].map((stage) => {
    const afterKey = `rule${stage}After`;
    const breakKey = `rule${stage}Break`;
    const after = textInput({
      label: 'Ab mehr als (Std.)',
      value: form[afterKey],
      inputmode: 'decimal',
      onInput: (input) => {
        form[afterKey] = input.value;
        validate();
      },
    });
    const pause = textInput({
      label: 'Pause (Min.)',
      value: form[breakKey],
      inputmode: 'numeric',
      onInput: digitFilter(filterBreakInput, (text) => {
        form[breakKey] = text;
        validate();
      }),
    });
    return { stage, after, pause, afterKey, breakKey };
  });

  const gradual = switchRow({
    title: 'Gestaffelt abziehen',
    description: 'Es wird nur so viel Pause abgezogen, dass die Arbeitszeit nicht unter die Schwelle fällt ' +
      '(z. B. 6:15 h anwesend → 6:00 h Arbeitszeit), wie es das Arbeitszeitgesetz vorsieht. Aus: Die volle ' +
      'Pause wird abgezogen, sobald die Anwesenheit die Schwelle überschreitet.',
    checked: form.gradual,
    onChange: (checked) => {
      form.gradual = checked;
      validate();
    },
  });

  const resetButton = h('button', {
    type: 'button',
    class: 'row-button',
    onclick: () => {
      form = resetBreakRulesForm(form);
      for (const field of ruleFields) {
        field.after.input.value = form[field.afterKey];
        field.pause.input.value = form[field.breakKey];
      }
      gradual.input.checked = form.gradual;
      validate();
    },
  }, 'Gesetzliche Werte wiederherstellen (§\u00a04\u00a0ArbZG)');

  const ruleSection = h('div', { class: 'rule-section' },
    ruleFields.map((field) => [
      h('h3', { class: 'group-header', text: `Stufe ${field.stage}` }),
      h('div', { class: 'group' }, field.after.row, field.pause.row),
    ]),
    h('div', { class: 'group' }, gradual.row),
    h('div', { class: 'group' }, resetButton));

  const saveButton = h('button', {
    type: 'button',
    class: 'button is-primary is-wide',
    onclick: () => {
      const result = validate();
      if (result.valid) onSave(result.settings);
    },
  }, 'Speichern');

  const lastBackupText = h('p', { class: 'group-footer is-accent' });
  const titleId = uid('settings-title');
  const title = h('h1', { class: 'appbar-title is-centered', id: titleId, tabindex: '-1', text: 'Einstellungen' });

  const element = h('div', { class: 'screen screen-settings' },
    h('header', { class: 'appbar' },
      h('div', { class: 'appbar-inner' },
        h('button', {
          type: 'button',
          class: 'back-button',
          'aria-label': 'Zurück',
          dataset: { focusKey: 'back' },
          onclick: onBack,
        }, icon('chevronLeft'), h('span', { 'aria-hidden': 'true', text: 'Zurück' })),
        title,
        h('span', { class: 'appbar-spacer', 'aria-hidden': 'true' }))),
    h('main', { class: 'content settings', 'aria-labelledby': titleId },
      h('h2', { class: 'section-title', text: 'Arbeitszeit' }),
      h('div', { class: 'group' }, weekly.row, days.row),
      h('div', { class: 'group' }, limit.row),

      h('h2', { class: 'section-title', text: 'Pausen' }),
      h('div', { class: 'group' }, autoBreak.row),
      ruleSection,
      saveButton,

      h('h2', { class: 'section-title', text: 'Daten sichern' }),
      h('div', { class: 'group' },
        h('button', { type: 'button', class: 'row-button has-icon', onclick: onBackup },
          icon('download'), h('span', { text: 'Backup jetzt speichern' })),
        h('button', { type: 'button', class: 'row-button has-icon', onclick: onRestore },
          icon('upload'), h('span', { text: 'Backup wiederherstellen' }))),
      unsaved && h('p', { class: 'group-footer is-error', text: UNSAVED_MESSAGE }),
      lastBackupText,
      h('p', {
        class: 'group-footer',
        text: 'Die Daten liegen nur auf diesem Gerät. Speichere regelmäßig ein Backup, z. B. in iCloud Drive ' +
          'oder „Dateien“, um sie nach einem Gerätewechsel wiederherzustellen. Im Safari-Tab ist das besonders ' +
          'wichtig: Safari löscht die Daten, wenn die Seite 7 Tage lang nicht geöffnet wird. Die App vom ' +
          'Home-Bildschirm hat einen eigenen Speicher; Daten aus Safari übernimmst du mit einem Backup. ' +
          'Sicherungen der Android-App lassen sich hier wiederherstellen und umgekehrt.',
      }),

      h('h2', { class: 'section-title', text: 'Hinweis' }),
      h('div', { class: 'group' },
        h('p', {
          class: 'group-text',
          text: 'Die App ist ein privates Hilfsmittel zum Erfassen der eigenen Arbeitszeit und keine ' +
            'Rechtsberatung. Die Pausenregeln (§\u00a04 ArbZG), die Tageshöchstgrenze von 10 Stunden (§\u00a03 ArbZG) und ' +
            'die 20-Stunden-Grenze für Werkstudenten sind vereinfacht umgesetzt. Ausnahmen, etwa durch ' +
            'Tarifverträge oder Betriebsvereinbarungen, berücksichtigt die App nicht. Verbindlich sind der ' +
            'Arbeitsvertrag, die Angaben des Arbeitgebers und bei Fragen zur Sozialversicherung die ' +
            'Krankenkasse. Alle Angaben ohne Gewähr.',
        })),
      h('p', { class: 'app-info', text: 'Arbeitszeitrechner · Alle Daten bleiben lokal auf dem Gerät.' })));

  function validate() {
    const result = validateSettingsForm(form, settings);
    weeklyHint.textContent = result.weeklyHint;
    weeklyHint.classList.toggle('is-error', result.weekly == null);
    setInvalid(weekly.input, result.weekly == null);
    daysHint.classList.toggle('is-error', result.days == null);
    setInvalid(days.input, result.days == null);
    for (const field of ruleFields) {
      setInvalid(field.after.input, result[field.afterKey] == null);
      setInvalid(field.pause.input, result[field.breakKey] == null);
    }
    ruleSection.hidden = !form.autoBreak;
    saveButton.disabled = !result.valid;
    return result;
  }

  function setLastBackup(dateTime) {
    lastBackupText.hidden = dateTime == null;
    lastBackupText.textContent = dateTime ? `Zuletzt gesichert: ${formatDateTime(dateTime)}` : '';
  }

  validate();
  setLastBackup(lastBackup);
  return {
    element,
    focusTitle: () => title.focus({ preventScroll: true }),
    setLastBackup,
  };
}
