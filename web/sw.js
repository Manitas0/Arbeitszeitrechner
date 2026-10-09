// Service Worker: hält alle Dateien der App vor, damit sie offline startet (Cache-first).
// Nur wenn sich sw.js ändert, laden installierte Geräte die App neu. Darum ist VERSION eine Prüfsumme
// über FILES: Nach einer Änderung schlägt der Test „Service Worker“ (test/core.test.js) fehl und nennt
// die neue Prüfsumme.

const VERSION = '7389f84fcf3e';
const CACHE_PREFIX = 'arbeitszeitrechner-';
const CACHE = `${CACHE_PREFIX}${VERSION}`;

const FILES = [
  './',
  './index.html',
  './styles.css',
  './manifest.webmanifest',
  './src/app.js',
  './src/core.js',
  './src/day-edit.js',
  './src/demo.js',
  './src/dom.js',
  './src/files.js',
  './src/month-export.js',
  './src/settings.js',
  './src/store.js',
  './icons/apple-touch-icon.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      // cache: 'reload' umgeht den HTTP-Cache, damit keine veralteten Dateien vorgehalten werden.
      .then((cache) => cache.addAll(FILES.map((url) => new Request(url, { cache: 'reload' }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE).map((key) => caches.delete(key)),
      ))
      .then(() => self.clients.claim()),
  );
});

const scopePath = new URL(self.registration.scope).pathname;

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Aufruf der App (auch mit ?demo=1 usw.): immer die vorgehaltene Startseite.
  const isAppPage = request.mode === 'navigate' &&
    (url.pathname === scopePath || url.pathname === `${scopePath}index.html`);

  event.respondWith(
    caches.open(CACHE)
      .then((cache) => cache.match(isAppPage ? './index.html' : request, { ignoreSearch: true }))
      .then((cached) => cached ?? fetch(request)),
  );
});
