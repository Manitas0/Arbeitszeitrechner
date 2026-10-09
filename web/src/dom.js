// Kleine DOM-Hilfen: Elemente bauen, Symbole, Dialoge, kurze Hinweise (Toasts) und Plattform-Erkennung.

const SVG_NS = 'http://www.w3.org/2000/svg';
const PROPERTY_KEYS = new Set(['value', 'checked', 'disabled', 'hidden', 'readOnly']);

function appendChildren(parent, children) {
  for (const child of children) {
    if (child == null || child === false) continue;
    if (Array.isArray(child)) appendChildren(parent, child);
    else parent.append(child instanceof Node ? child : String(child));
  }
}

/**
 * Baut ein Element: h('button', { class: 'btn', onclick: fn }, 'Text', kind, …).
 * Attribute mit null/false werden weggelassen, "on…" registriert einen Event-Listener.
 */
export function h(tag, props = null, ...children) {
  const element = document.createElement(tag);
  if (props) {
    for (const [key, value] of Object.entries(props)) {
      if (value == null || value === false) continue;
      if (key === 'class') element.className = value;
      else if (key === 'text') element.textContent = value;
      else if (key === 'dataset') Object.assign(element.dataset, value);
      else if (key.startsWith('on') && typeof value === 'function') element.addEventListener(key.slice(2), value);
      else if (PROPERTY_KEYS.has(key)) element[key] = value;
      else element.setAttribute(key, value === true ? '' : String(value));
    }
  }
  appendChildren(element, children);
  return element;
}

let idCounter = 0;

/** Eindeutige ID für label/aria-Verknüpfungen. */
export function uid(prefix) {
  idCounter += 1;
  return `${prefix}-${idCounter}`;
}

// --- Symbole (eigene Zeichnungen, 24 × 24, Linienstärke über CSS) ---

function gear() {
  const teeth = 8;
  let path = '';
  for (let i = 0; i < teeth; i++) {
    const angle = (i * 2 * Math.PI) / teeth;
    const points = [[-0.27, 7.6], [-0.15, 10], [0.15, 10], [0.27, 7.6]];
    for (const [offset, radius] of points) {
      const x = 12 + radius * Math.cos(angle + offset);
      const y = 12 + radius * Math.sin(angle + offset);
      path += `${path ? 'L' : 'M'}${x.toFixed(2)} ${y.toFixed(2)}`;
    }
  }
  return `<path d="${path}Z"/><circle cx="12" cy="12" r="3"/>`;
}

const ICONS = {
  calendar: '<rect x="3.5" y="5" width="17" height="15.5" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/>' +
    '<path d="M7.5 14h2M11 14h2M14.5 14h2M7.5 17h2M11 17h2"/>',
  share: '<path d="M12 14.5V3.5M8 7.5l4-4 4 4"/>' +
    '<path d="M8.5 10.5H7a2 2 0 0 0-2 2v6.5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6.5a2 2 0 0 0-2-2h-1.5"/>',
  settings: gear(),
  chevronLeft: '<path d="M14.5 5.5 8 12l6.5 6.5"/>',
  chevronRight: '<path d="M9.5 5.5 16 12l-6.5 6.5"/>',
  play: '<path d="M8 5.8v12.4a.8.8 0 0 0 1.2.7l10-6.2a.8.8 0 0 0 0-1.4l-10-6.2a.8.8 0 0 0-1.2.7z" class="fill"/>',
  stop: '<rect x="6.5" y="6.5" width="11" height="11" rx="2.5" class="fill"/>',
  close: '<path d="M7 7l10 10M17 7 7 17"/>',
  warning: '<path d="M10.3 4.6 2.9 17.6A2 2 0 0 0 4.6 20.6h14.8a2 2 0 0 0 1.7-3L13.7 4.6a2 2 0 0 0-3.4 0z"/>' +
    '<path d="M12 9.5v4.5M12 17.3v.2"/>',
  download: '<path d="M12 3.5v11M7.5 10l4.5 4.5 4.5-4.5M4.5 16.5v1.5a2.5 2.5 0 0 0 2.5 2.5h10a2.5 2.5 0 0 0 2.5-2.5v-1.5"/>',
  upload: '<path d="M12 15V4M7.5 8.5 12 4l4.5 4.5M4.5 16.5v1.5a2.5 2.5 0 0 0 2.5 2.5h10a2.5 2.5 0 0 0 2.5-2.5v-1.5"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.6v.2"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3.5 2"/>',
};

/** SVG-Symbol, für Screenreader ausgeblendet (die Beschriftung trägt der Knopf). */
export function icon(name, className = '') {
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('focusable', 'false');
  svg.setAttribute('class', `icon ${className}`.trim());
  svg.innerHTML = ICONS[name];
  return svg;
}

// --- Plattform ---

/** iPhone oder iPad (iPadOS meldet sich als Mac mit Touchscreen). */
export function isIOS() {
  const ua = navigator.userAgent;
  return /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
}

/** Safari bzw. WebKit: jeder Browser auf iPhone und iPad, auf dem Mac nur Safari selbst. */
export function isSafari() {
  const ua = navigator.userAgent;
  return isIOS() || (/Version\/[\d.]+.*Safari\//.test(ua) && !/Chrome|Chromium|Edg|OPR|Firefox/.test(ua));
}

/** Als App vom Home-Bildschirm gestartet (nicht im Browser-Tab). */
export function isStandalone() {
  return navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches;
}

export function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

// --- Fokus ---

/** Merkt sich das fokussierte Element über data-focus-key, damit es ein Neuzeichnen übersteht. */
export function focusKeyOf(element) {
  return element?.closest?.('[data-focus-key]')?.dataset.focusKey ?? null;
}

export function focusByKey(root, key) {
  if (!key) return false;
  const target = root.querySelector(`[data-focus-key="${CSS.escape(key)}"]`);
  if (!target) return false;
  target.focus({ preventScroll: true });
  return true;
}

// --- Dialoge ---

const CLOSE_ANIMATION_MS = 180;

export function topDialog() {
  const open = document.querySelectorAll('dialog[open]');
  return open.length ? open[open.length - 1] : null;
}

/**
 * Hält ein Sheet über der Bildschirmtastatur: Safari verkleinert beim Tippen nur den sichtbaren
 * Bereich (visualViewport), feste Elemente blieben sonst unter der Tastatur.
 */
function followKeyboard(dialog) {
  const viewport = window.visualViewport;
  if (!viewport || !dialog.classList.contains('sheet')) return () => {};
  const update = () => {
    const covered = Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop);
    dialog.style.setProperty('--keyboard-inset', `${Math.round(covered)}px`);
  };
  viewport.addEventListener('resize', update);
  viewport.addEventListener('scroll', update);
  update();
  return () => {
    viewport.removeEventListener('resize', update);
    viewport.removeEventListener('scroll', update);
  };
}

/**
 * Öffnet [dialog] modal. Tipp auf den Hintergrund oder Escape schließt ihn; danach wird er
 * entfernt und der Fokus kehrt zum auslösenden Element zurück.
 */
export function openModal(dialog, { onClose } = {}) {
  const opener = document.activeElement;
  const openerKey = focusKeyOf(opener);
  let pressedOnBackdrop = false;

  dialog.addEventListener('pointerdown', (event) => {
    pressedOnBackdrop = event.target === dialog;
  });
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog && pressedOnBackdrop) closeModal(dialog);
  });
  dialog.addEventListener('cancel', (event) => {
    event.preventDefault();
    closeModal(dialog);
  });
  let stopFollowing = () => {};
  dialog.addEventListener('close', () => {
    stopFollowing();
    dialog.remove();
    document.documentElement.classList.toggle('has-modal', topDialog() !== null);
    if (opener && opener.isConnected) opener.focus({ preventScroll: true });
    else focusByKey(document, openerKey);
    onClose?.();
  }, { once: true });

  document.body.append(dialog);
  dialog.showModal();
  stopFollowing = followKeyboard(dialog);
  document.documentElement.classList.add('has-modal');
}

/** Schließt [dialog] mit kurzer Animation. */
export function closeModal(dialog) {
  if (!dialog.open || dialog.classList.contains('is-closing')) return;
  if (prefersReducedMotion()) {
    dialog.close();
    return;
  }
  dialog.classList.add('is-closing');
  setTimeout(() => dialog.close(), CLOSE_ANIMATION_MS);
}

/** Rückfrage im Stil einer iOS-Meldung. Liefert true, wenn bestätigt wurde. */
export function confirmDialog({ title, message, confirmLabel, cancelLabel = 'Abbrechen' }) {
  return new Promise((resolve) => {
    let confirmed = false;
    const titleId = uid('alert-title');
    const messageId = uid('alert-message');
    const dialog = h('dialog', {
      class: 'alert',
      role: 'alertdialog',
      'aria-labelledby': titleId,
      'aria-describedby': messageId,
    },
    h('div', { class: 'alert-body' },
      h('h2', { class: 'alert-title', id: titleId, text: title }),
      h('p', { class: 'alert-message', id: messageId, text: message })),
    h('div', { class: 'alert-actions' },
      h('button', { type: 'button', class: 'alert-button', onclick: () => closeModal(dialog) }, cancelLabel),
      h('button', {
        type: 'button',
        class: 'alert-button is-strong',
        onclick: () => {
          confirmed = true;
          closeModal(dialog);
        },
      }, confirmLabel)));
    openModal(dialog, { onClose: () => resolve(confirmed) });
  });
}

// --- Toast ---

let toastElement = null;
let toastTimer = 0;

/** Kurzer Hinweis am unteren Rand (wie ein Toast unter Android). */
export function toast(message) {
  if (!toastElement) {
    toastElement = h('div', { class: 'toast', role: 'status', 'aria-live': 'polite' });
    // Als Popover liegt der Hinweis auch über offenen Dialogen.
    if (typeof toastElement.showPopover === 'function') toastElement.setAttribute('popover', 'manual');
  }
  const usePopover = toastElement.hasAttribute('popover');
  const host = usePopover ? document.body : (topDialog() ?? document.body);
  if (toastElement.parentNode !== host) host.append(toastElement);
  toastElement.textContent = message;
  if (usePopover) {
    if (toastElement.matches(':popover-open')) toastElement.hidePopover();
    toastElement.showPopover();
  }
  toastElement.classList.remove('is-visible');
  void toastElement.offsetWidth; // Animation neu starten
  toastElement.classList.add('is-visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toastElement.classList.remove('is-visible');
    toastTimer = setTimeout(() => {
      if (usePopover && toastElement.matches(':popover-open')) toastElement.hidePopover();
    }, 250);
  }, 2800);
}
