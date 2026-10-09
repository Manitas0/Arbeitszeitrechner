// Dialog „Tag bearbeiten“: Art des Tages, Beginn und Ende, tatsächliche Pause und die Rechnung dazu.

import {
  DAY_TYPES, DayType, absenceCreditText, breakFieldHint, dayEditTitle, dayTypeLabel, defaultEndTime,
  defaultStartTime, draftEntry, evaluate, filterBreakInput, formatDuration, formatTime, isEmptyEntry, parseTime,
  toIntOrNull,
} from './core.js';
import { closeModal, h, icon, openModal, uid } from './dom.js';

/**
 * Feld für eine Uhrzeit mit Löschen-Knopf. Ein leeres Feld startet beim Antippen mit [suggest]()
 * – wie der Zeitwähler der Android-App.
 */
function timeField(label, initial, suggest, onChange) {
  const id = uid('time');
  const input = h('input', {
    type: 'time',
    id,
    class: 'time-input',
    value: initial == null ? '' : formatTime(initial),
  });
  const clear = h('button', {
    type: 'button',
    class: 'clear-button',
    'aria-label': `${label} löschen`,
    title: `${label} löschen`,
  }, icon('close'));
  const row = h('div', { class: 'form-row time-row' },
    h('label', { class: 'row-label', for: id, text: label, onclick: suggestIfEmpty }),
    h('span', { class: 'time-box' },
      input,
      h('span', { class: 'time-placeholder', 'aria-hidden': 'true', text: '--:--' })),
    clear);

  function value() {
    return input.value === '' ? null : parseTime(input.value);
  }

  function sync() {
    const empty = value() == null;
    row.classList.toggle('is-empty', empty);
    clear.classList.toggle('is-hidden', empty);
  }

  function changed() {
    sync();
    onChange(value());
  }

  function suggestIfEmpty() {
    if (input.value === '') {
      input.value = formatTime(suggest());
      changed();
    }
  }

  input.addEventListener('pointerdown', suggestIfEmpty);
  input.addEventListener('input', changed);
  input.addEventListener('change', changed);
  clear.addEventListener('click', (event) => {
    input.value = '';
    changed();
    // Per Tastatur ausgelöst: Fokus ins Feld, damit er nicht verloren geht.
    if (event.detail === 0) input.focus();
  });
  sync();
  return row;
}

function previewRow(label, value, strong = false) {
  return h('div', { class: `preview-row${strong ? ' is-strong' : ''}` },
    h('span', { text: label }),
    h('span', { class: 'preview-value', text: value }));
}

/**
 * Öffnet den Dialog für [entry].
 * now(): aktueller Zeitpunkt; onSave(Eintrag) und onDelete() speichern bzw. löschen.
 */
export function openDayEdit({ entry, settings, now, onSave, onDelete }) {
  const date = entry.date;
  let type = entry.type;
  let start = entry.start;
  let end = entry.end;
  let breakText = entry.manualBreakMinutes > 0 ? String(entry.manualBreakMinutes) : '';

  const draft = () => draftEntry(date, type, start, end, breakText);
  const manualBreak = () => toIntOrNull(breakText) ?? 0;

  const titleId = uid('day-title');
  const typeName = uid('day-type');
  const breakId = uid('break');
  const breakHintId = uid('break-hint');

  const segmented = h('fieldset', { class: 'segmented' },
    h('legend', { class: 'sr-only', text: 'Art des Tages' }),
    DAY_TYPES.map((option) => h('label', { class: 'segment' },
      h('input', {
        type: 'radio',
        name: typeName,
        value: option,
        checked: option === type,
        onchange: () => {
          type = option;
          update();
        },
      }),
      h('span', { text: dayTypeLabel(option) }))));

  const startField = timeField('Beginn', start, () => defaultStartTime(date, now()), (value) => {
    start = value;
    update();
  });
  const endField = timeField('Ende', end, () => defaultEndTime(date, start, manualBreak(), settings, now()), (value) => {
    end = value;
    update();
  });

  const breakInput = h('input', {
    type: 'text',
    id: breakId,
    class: 'text-input',
    inputmode: 'numeric',
    pattern: '[0-9]*',
    autocomplete: 'off',
    enterkeyhint: 'done',
    placeholder: 'optional',
    value: breakText,
    'aria-describedby': breakHintId,
    oninput: () => {
      const filtered = filterBreakInput(breakInput.value);
      if (filtered !== breakInput.value) breakInput.value = filtered;
      breakText = filtered;
      update();
    },
    onkeydown: (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        save();
      }
    },
  });

  const preview = h('div', { class: 'preview', 'aria-live': 'polite' });
  const workSection = h('div', { class: 'work-section' },
    h('div', { class: 'group' }, startField, endField),
    h('div', { class: 'group' },
      h('div', { class: 'form-row' },
        h('label', { class: 'row-label', for: breakId, text: 'Tatsächliche Pause (Min.)' }),
        breakInput)),
    h('p', { class: 'group-footer', id: breakHintId, text: breakFieldHint(settings) }),
    preview);
  const absenceNote = h('p', { class: 'absence-note' });

  const dialog = h('dialog', { class: 'sheet', 'aria-labelledby': titleId },
    h('div', { class: 'sheet-grabber', 'aria-hidden': 'true' }),
    h('div', { class: 'sheet-bar' },
      h('button', { type: 'button', class: 'bar-button', onclick: () => closeModal(dialog) }, 'Abbrechen'),
      h('button', { type: 'button', class: 'bar-button is-strong', onclick: save }, 'Speichern')),
    h('div', { class: 'sheet-content' },
      h('h2', { class: 'sheet-title', id: titleId, tabindex: '-1', autofocus: true, text: dayEditTitle(date) }),
      segmented,
      workSection,
      absenceNote,
      !isEmptyEntry(entry) && h('div', { class: 'group' },
        h('button', {
          type: 'button',
          class: 'row-button is-destructive',
          onclick: () => {
            onDelete();
            closeModal(dialog);
          },
        }, 'Löschen'))));

  function update() {
    const isWork = type === DayType.WORK;
    workSection.hidden = !isWork;
    absenceNote.hidden = isWork;
    if (!isWork) absenceNote.textContent = absenceCreditText(type, settings);
    if (isWork && start != null && end != null) {
      const result = evaluate(draft(), settings);
      preview.hidden = false;
      preview.replaceChildren(
        previewRow('Anwesenheit', `${formatDuration(result.attendanceMinutes)} h`),
        previewRow(result.autoBreakApplied ? '− Pause (automatisch)' : '− Pause', `${formatDuration(result.breakMinutes)} h`),
        previewRow('= Arbeitszeit', `${formatDuration(result.creditedMinutes)} h`, true),
      );
    } else {
      preview.hidden = true;
      preview.replaceChildren();
    }
  }

  function save() {
    onSave(draft());
    closeModal(dialog);
  }

  update();
  openModal(dialog);
}
