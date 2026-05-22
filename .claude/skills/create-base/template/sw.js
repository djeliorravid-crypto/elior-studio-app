// Service Worker — offline support + always-fresh code.
// Network-first for HTML (so new versions ship instantly), cache-first for assets.
const CACHE_NAME = 'app-base-v1';
const APP_SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(APP_SHELL).catch(() => {})));
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
  if (url.origin !== self.location.origin) return;
  if (e.request.mode === 'navigate' || e.request.destination === 'document') {
    e.respondWith((async () => {
      try { const fresh = await fetch(e.request); const c = await caches.open(CACHE_NAME); c.put(e.request, fresh.clone()); return fresh; }
      catch (err) { const cached = await caches.match(e.request) || await caches.match('./'); if (cached) return cached; throw err; }
    })());
    return;
  }
  e.respondWith((async () => {
    const cached = await caches.match(e.request);
    if (cached) return cached;
    try { const fresh = await fetch(e.request); const c = await caches.open(CACHE_NAME); c.put(e.request, fresh.clone()); return fresh; }
    catch (err) { return cached || new Response('', { status: 504 }); }
  })());
});
