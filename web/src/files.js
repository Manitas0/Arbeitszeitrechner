// Dateien speichern und teilen (Sicherung, Stundenzettel) sowie Text teilen (Woche).

import { h, isIOS } from './dom.js';

/** Kann das Teilen-Menü diese Datei verschicken? */
export function canShareFiles(file) {
  try {
    return typeof navigator.share === 'function' && typeof navigator.canShare === 'function' &&
      navigator.canShare({ files: [file] });
  } catch {
    return false;
  }
}

/**
 * Öffnet das Teilen-Menü mit einer Datei. Muss direkt im Klick-Handler aufgerufen werden (Safari).
 * Liefert false, wenn der Nutzer abbricht; andere Fehler werden weitergereicht.
 */
export async function shareFile(file, title) {
  try {
    await navigator.share({ files: [file], title });
    return true;
  } catch (error) {
    if (error?.name === 'AbortError') return false;
    throw error;
  }
}

/** Lädt eine Datei herunter. */
export function downloadFile(file) {
  const url = URL.createObjectURL(file);
  const link = h('a', { href: url, download: file.name, hidden: true });
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

/** Speichern-Dialog des Browsers (Chrome, Edge): Erst nach dem Schreiben steht fest, dass die Datei gespeichert ist. */
async function saveWithPicker(file) {
  let handle;
  try {
    handle = await window.showSaveFilePicker({
      suggestedName: file.name,
      types: [{ accept: { [file.type]: [file.name.slice(file.name.lastIndexOf('.'))] } }],
    });
  } catch (error) {
    if (error?.name === 'AbortError') return false;
    throw error;
  }
  const writable = await handle.createWritable();
  await writable.write(file);
  await writable.close();
  return true;
}

/**
 * Speichert eine Datei: auf iPhone und iPad über das Teilen-Menü („In Dateien sichern“),
 * weil Downloads in der Home-Bildschirm-App unzuverlässig sind, sonst über den Speichern-Dialog
 * des Browsers oder als Download. Liefert false, wenn der Nutzer abbricht. Ob ein Download
 * ankommt, lässt sich nicht prüfen; Firefox und Safari speichern ihn in der Grundeinstellung ohne Rückfrage.
 */
export function saveFile(file, title) {
  if (isIOS() && canShareFiles(file)) return shareFile(file, title);
  if (typeof window.showSaveFilePicker === 'function') return saveWithPicker(file);
  downloadFile(file);
  return Promise.resolve(true);
}

/**
 * Teilt einen Text über das Teilen-Menü, sonst über die Zwischenablage.
 * Liefert 'shared', 'copied' oder 'aborted'; wirft, wenn beides nicht geht.
 */
export async function shareText(title, text) {
  if (typeof navigator.share === 'function') {
    try {
      await navigator.share({ title, text });
      return 'shared';
    } catch (error) {
      if (error?.name === 'AbortError') return 'aborted';
      // Sonst über die Zwischenablage versuchen.
    }
  }
  await navigator.clipboard.writeText(text);
  return 'copied';
}
