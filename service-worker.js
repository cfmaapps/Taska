const TASKA_CACHE = 'cfma-taska-static-2026-06-19-2';
const STATIC_ASSETS = [
  './',
  './index.html',
  './surveyors-toolbox.html',
  './cfma-public-config.js',
  './gmail-analysis-core.js',
  './manifest.webmanifest',
  './version.json',
  './assets/cfma-taska-icon.svg',
  './assets/cfma-taska-icon.png',
  './assets/cfma-taska-icon-192.png',
  './assets/cfma-taska-icon.ico'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(TASKA_CACHE)
      .then(cache => cache.addAll(STATIC_ASSETS))
      .catch(() => null)
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys
        .filter(key => key.startsWith('cfma-taska-static-') && key !== TASKA_CACHE)
        .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const isFreshFile = /(?:surveyors-toolbox|index)\.html$/.test(url.pathname)
    || /(?:cfma-public-config\.js|version\.json)$/.test(url.pathname)
    || url.pathname.endsWith('/');

  if (isFreshFile) {
    event.respondWith(
      fetch(request)
        .then(response => {
          const copy = response.clone();
          caches.open(TASKA_CACHE).then(cache => cache.put(request, copy));
          return response;
        })
        .catch(() => caches.match(request))
    );
    return;
  }

  event.respondWith(
    caches.match(request).then(cached => cached || fetch(request).then(response => {
      const copy = response.clone();
      caches.open(TASKA_CACHE).then(cache => cache.put(request, copy));
      return response;
    }))
  );
});
