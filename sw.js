// Service worker de MD Pro Training.
// Estrategia: primero la red; si no hay conexión, lo último guardado. Así la app abre aunque no haya señal.
// Si se agregan archivos, sumarlos a ASSETS y subir la versión de CACHE_NAME.
const CACHE_NAME = 'md-pro-training-v6';
const ASSETS = [
  '/app.html',
  '/manifest.json',
  '/icon-192.png',
  '/icon-512.png'
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Se guarda una copia de: archivos propios de la app y tipografías de Google.
// Nunca se guardan respuestas de Supabase (datos y login van siempre por la red).
function cacheable(url) {
  return url.origin === self.location.origin ||
         url.hostname === 'fonts.googleapis.com' ||
         url.hostname === 'fonts.gstatic.com';
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (!cacheable(url)) return;
  e.respondWith(
    fetch(req).then(res => {
      if (res && (res.ok || res.type === 'opaque')) {
        const copy = res.clone();
        caches.open(CACHE_NAME).then(c => c.put(req, copy)).catch(() => {});
      }
      return res;
    }).catch(() => caches.match(req).then(r => r || (req.mode === 'navigate' ? caches.match('/app.html') : undefined)))
  );
});
