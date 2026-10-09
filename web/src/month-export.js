// Dialog „Stundenzettel exportieren“: ein Monat als CSV-Datei teilen oder speichern.

import { germanMonthName, monthCsv, monthFileName, monthSummary, monthSummaryText, plusMonths } from './core.js';
import { closeModal, h, icon, openModal, toast, uid } from './dom.js';
import { canShareFiles, saveFile, shareFile } from './files.js';

const CSV_TYPE = 'text/csv';

/** Öffnet den Dialog mit [initialMonth] ("YYYY-MM"). */
export function openMonthExport({ initialMonth, entries, settings }) {
  let month = initialMonth;
  const titleId = uid('export-title');
  const canShare = canShareFiles(new File([''], monthFileName(month), { type: CSV_TYPE }));

  const csvFile = () => new File([monthCsv(month, entries, settings)], monthFileName(month), { type: CSV_TYPE });
  const fileTitle = () => `Stundenzettel ${germanMonthName(month)}`;

  const monthLabel = h('p', { class: 'month-label', 'aria-live': 'polite' });
  const summaryText = h('p', { class: 'month-summary' });
  const shareButton = h('button', {
    type: 'button',
    class: 'button is-primary',
    onclick: () => {
      shareFile(csvFile(), fileTitle()).catch(() => toast('Teilen nicht möglich'));
    },
  }, icon('share'), 'Teilen');
  const saveButton = h('button', {
    type: 'button',
    class: `button ${canShare ? 'is-secondary' : 'is-primary'}`,
    onclick: () => {
      saveFile(csvFile(), fileTitle())
        .then((saved) => {
          if (saved) toast('Stundenzettel gespeichert');
        })
        .catch(() => toast('Stundenzettel konnte nicht gespeichert werden'));
    },
  }, icon('download'), 'Speichern');

  const dialog = h('dialog', { class: 'sheet', 'aria-labelledby': titleId },
    h('div', { class: 'sheet-grabber', 'aria-hidden': 'true' }),
    h('div', { class: 'sheet-bar' },
      h('span'),
      h('button', { type: 'button', class: 'bar-button is-strong', onclick: () => closeModal(dialog) }, 'Schließen')),
    h('div', { class: 'sheet-content' },
      h('h2', { class: 'sheet-title', id: titleId, tabindex: '-1', autofocus: true, text: 'Stundenzettel exportieren' }),
      h('div', { class: 'card month-card' },
        h('div', { class: 'month-nav' },
          h('button', {
            type: 'button',
            class: 'round-button is-tinted',
            'aria-label': 'Vorheriger Monat',
            title: 'Vorheriger Monat',
            onclick: () => changeMonth(-1),
          }, icon('chevronLeft')),
          monthLabel,
          h('button', {
            type: 'button',
            class: 'round-button is-tinted',
            'aria-label': 'Nächster Monat',
            title: 'Nächster Monat',
            onclick: () => changeMonth(1),
          }, icon('chevronRight'))),
        summaryText),
      h('p', {
        class: 'group-footer',
        text: 'CSV-Datei für Excel, Numbers oder Google Tabellen – mit Kalenderwoche, Beginn, Ende, ' +
          'Pause und Stunden pro Tag sowie der Monatssumme.',
      }),
      h('div', { class: 'button-row' }, canShare && shareButton, saveButton)));

  function changeMonth(delta) {
    month = plusMonths(month, delta);
    update();
  }

  function update() {
    const summary = monthSummary(month, entries, settings);
    monthLabel.textContent = germanMonthName(month);
    summaryText.textContent = monthSummaryText(summary);
    summaryText.classList.toggle('is-empty', summary.totalMinutes === 0);
    shareButton.disabled = summary.totalMinutes === 0;
    saveButton.disabled = summary.totalMinutes === 0;
  }

  update();
  openModal(dialog);
}
