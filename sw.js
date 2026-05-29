// Service Worker — אפליקציה אמיתית עם תמיכה offline
const CACHE_NAME = 'elior-app-v4';
const APP_SHELL = [
  '/elior-studio-app/',
  '/elior-studio-app/index.html',
  '/elior-studio-app/workshop.html',
  '/elior-studio-app/manifest.json',
  '/elior-studio-app/icon-192.png',
  '/elior-studio-app/icon-512.png'
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

// Strategy: Network-first for HTML (fresh code), cache-first for assets, fallback to cache offline
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;

  // External assets (Firebase, fonts, etc.) — go to network, ignore cache
  if (url.origin !== self.location.origin) return;

  // HTML/JS/CSS — network first, fallback to cache
  if (e.request.mode === 'navigate' || e.request.destination === 'document') {
    e.respondWith((async () => {
      try {
        const fresh = await fetch(e.request);
        const cache = await caches.open(CACHE_NAME);
        cache.put(e.request, fresh.clone());
        return fresh;
      } catch (err) {
        const cached = await caches.match(e.request) || await caches.match('/elior-studio-app/');
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
