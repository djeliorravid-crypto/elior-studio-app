// Service Worker — ללא caching, תמיד טוען מהרשת
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => {
  // מחק את כל הcaches הישנים
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.map(k => caches.delete(k))))
  );
  self.clients.claim();
});
// לא מטפל בfetch — הדפדפן טוען ישירות מהרשת תמיד
