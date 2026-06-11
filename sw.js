// Soirée d'été — CSE IQVIA — Service Worker
const CACHE_STATIC = 'soiree-ete-static-v3';
const CACHE_PHOTOS = 'soiree-ete-photos-v3';
const MAX_PHOTO_ENTRIES = 200; // purge des plus anciennes au-delà (évite un cache illimité sur la soirée)

const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  'https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;1,400&family=Jost:wght@300;400;500&display=swap'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_STATIC)
      .then((cache) => cache.addAll(STATIC_ASSETS.map(url => new Request(url, { mode: 'no-cors' }))))
      .then(() => self.skipWaiting())
      .catch(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) =>
      Promise.all(cacheNames
        .filter(name => name !== CACHE_STATIC && name !== CACHE_PHOTOS)
        .map(name => caches.delete(name))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (url.hostname.includes('supabase.co') && url.pathname.includes('/storage/')) {
    // Les URLs de photos sont immuables (nom unique horodaté) → cache-first SANS timeout :
    // sur le wifi/4G saturé de la salle, un network-first à 5 s faisait disparaître des photos.
    event.respondWith(cacheFirstWithNetwork(request, CACHE_PHOTOS, MAX_PHOTO_ENTRIES));
    return;
  }
  if (url.hostname.includes('supabase.co') && url.pathname.includes('/rest/')) {
    return;
  }
  if (url.hostname.includes('fonts.googleapis.com') || url.hostname.includes('fonts.gstatic.com')) {
    event.respondWith(cacheFirstWithNetwork(request, CACHE_STATIC));
    return;
  }
  const isHTML = url.hostname === self.location.hostname
              && (url.pathname === '/' || url.pathname.endsWith('.html') || request.mode === 'navigate');
  if (isHTML) {
    event.respondWith(networkFirstWithCache(request, CACHE_STATIC, 4000));
    return;
  }
  if (url.hostname === self.location.hostname) {
    event.respondWith(cacheFirstWithNetwork(request, CACHE_STATIC));
  }
});

async function networkFirstWithCache(request, cacheName, timeoutMs) {
  const cache = await caches.open(cacheName);
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    const response = await fetch(request, { signal: controller.signal });
    clearTimeout(timeout);
    if (response && response.status === 200) cache.put(request, response.clone());
    return response;
  } catch {
    const cached = await cache.match(request);
    return cached || new Response('', { status: 503 });
  }
}

async function cacheFirstWithNetwork(request, cacheName, maxEntries) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  if (cached) return cached;
  try {
    const response = await fetch(request);
    if (response && response.status === 200) {
      await cache.put(request, response.clone());
      if (maxEntries) trimCache(cache, maxEntries); // purge en arrière-plan, sans bloquer la réponse
    }
    return response;
  } catch {
    return new Response('', { status: 503 });
  }
}

async function trimCache(cache, maxEntries) {
  try {
    const keys = await cache.keys();
    if (keys.length <= maxEntries) return;
    // keys() est ordonné par insertion → on retire les plus anciennes
    const excess = keys.slice(0, keys.length - maxEntries);
    await Promise.all(excess.map(k => cache.delete(k)));
  } catch (_) {}
}
