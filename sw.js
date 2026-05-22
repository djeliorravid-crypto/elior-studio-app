// Service Worker — offline support + always-fresh code.
// Network-first for HTML (so new versions ship instantly), cache-first for assets.
const CACHE_NAME = 'fit-app-v1';
const APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL).catch(() => {}))
  );
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;

  // External (Firebase, fonts, etc.) — go straight to network
  if (url.origin !== self.location.origin) return;

  // HTML — network first, fall back to cache offline
  if (e.request.mode === 'navigate' || e.request.destination === 'document') {
    e.respondWith((async () => {
      try {
        const fresh = await fetch(e.request);
        const cache = await caches.open(CACHE_NAME);
        cache.put(e.request, fresh.clone());
        return fresh;
      } catch (err) {
        const cached = await caches.match(e.request) || await caches.match('./');
        if (cached) return cached;
        throw err;
      }
    })());
    return;
  }

  // Static assets — cache first, network fallback
  e.respondWith((async () => {
    const cached = await caches.match(e.request);
    if (cached) return cached;
    try {
      const fresh = await fetch(e.request);
      const cache = await caches.open(CACHE_NAME);
      cache.put(e.request, fresh.clone());
      return fresh;
    } catch (err) {
      return cached || new Response('', { status: 504 });
    }
  })());
});
