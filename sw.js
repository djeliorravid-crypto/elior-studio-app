// Service Worker — אפליקציה אמיתית עם תמיכה offline
const CACHE_NAME = 'elior-app-v124';
const APP_SHELL = [
  '/elior-studio-app/',
  '/elior-studio-app/index.html',
  '/elior-studio-app/workshop.html',
  '/elior-studio-app/contract.html',
  '/elior-studio-app/proposal.html',
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
    // Force every open client (browser tab / installed PWA window) to
    // reload immediately so the user sees the fresh content without
    // having to close-and-reopen the app. Two channels are used so we
    // survive iOS / older client mixes:
    //   • client.navigate(url) — hard server-side reload
    //   • postMessage('reload') — picked up by the message listener
    //                             in index.html as a backup
    try {
      const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const win of wins) {
        try { win.postMessage({ type: 'sw-activated', cache: CACHE_NAME }); } catch (_) {}
        try { if (typeof win.navigate === 'function') await win.navigate(win.url); } catch (_) {}
      }
    } catch (_) {}
  })());
});

// Strategy: Network-first for HTML (fresh code), cache-first for assets, fallback to cache offline
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;

  // External assets (Firebase, fonts, etc.) — go to network, ignore cache
  if (url.origin !== self.location.origin) return;

  // HTML/JS/CSS — network first (with no-store so iOS doesn't return a stale
  // HTTP-cached copy), fallback to cache offline
  if (e.request.mode === 'navigate' || e.request.destination === 'document') {
    e.respondWith((async () => {
      try {
        const fresh = await fetch(e.request, { cache: 'no-store' });
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
