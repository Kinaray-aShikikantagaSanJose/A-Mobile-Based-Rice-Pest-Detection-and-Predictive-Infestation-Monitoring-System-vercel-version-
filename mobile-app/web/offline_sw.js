// Palay Patrol web app: offline app shell (registered by flutter_bootstrap.js).
//
// Lets the app open without signal after it was opened once with signal.
// Only this site's own files are cached; calls to the API (another origin)
// and map tiles pass through untouched, and the app itself keeps unsent
// observations in the browser until signal is back.
//
//   page navigations, main.dart.js, flutter_bootstrap.js, version.json:
//       network first (a new deploy shows up at once), cache when offline
//   everything else on this site (CanvasKit, assets, icons, sqlite3.wasm),
//   and Flutter's fallback text font from fonts.gstatic.com:
//       cache first, refreshed in the background
//
// Bump VERSION to drop old caches after changing this file.
const VERSION = 'v1';
const CACHE = `palay-shell-${VERSION}`;
const CORE = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'version.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'sqflite_sw.js',
  'sqlite3.wasm',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/assets/geo/antique_barangays.geojson',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
];
const NETWORK_FIRST = /(?:^|\/)(?:index\.html|main\.dart\.js|flutter_bootstrap\.js|version\.json|manifest\.json)$/;
const NETWORK_TIMEOUT_MS = 4000;

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      // One failing file (e.g. a renderer this build doesn't have) must not
      // stop the rest from being cached.
      await Promise.all(CORE.map((path) => cache.add(new Request(path, { cache: 'reload' })).catch(() => {})));
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key.startsWith('palay-shell-') && key !== CACHE) await caches.delete(key);
      }
      await self.clients.claim();
    })(),
  );
});

function timeout(ms) {
  return new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), ms));
}

async function networkFirst(request, cacheKey) {
  const cache = await caches.open(CACHE);
  try {
    const response = await Promise.race([fetch(request), timeout(NETWORK_TIMEOUT_MS)]);
    if (response && response.ok) cache.put(cacheKey || request, response.clone());
    return response;
  } catch (e) {
    const cached = await cache.match(cacheKey || request, { ignoreSearch: true });
    if (cached) return cached;
    throw e;
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(request, { ignoreSearch: true });
  const refresh = fetch(request)
    .then((response) => {
      if (response && response.ok && (response.type === 'basic' || response.type === 'cors')) {
        cache.put(request, response.clone());
      }
      return response;
    })
    .catch(() => null);
  if (cached) return cached;
  const response = await refresh;
  if (response) return response;
  return Response.error();
}

// The page sends the font URLs it loaded before this worker took over.
self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type !== 'cache-urls' || !Array.isArray(data.urls)) return;
  const urls = data.urls.filter((u) => typeof u === 'string' && u.startsWith('https://fonts.gstatic.com/'));
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.all(
        urls.map((u) =>
          cache.match(u).then((hit) => hit || cache.add(new Request(u, { mode: 'cors' })).catch(() => {})),
        ),
      ),
    ),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  // Flutter draws text with a fallback font (Roboto) from Google Fonts; keep
  // it so text still shows offline.
  if (url.hostname === 'fonts.gstatic.com') {
    event.respondWith(cacheFirst(request));
    return;
  }
  if (url.origin !== self.location.origin) return; // API and map tiles: not ours to cache
  if (request.mode === 'navigate') {
    // Any path of the single-page app opens index.html (as Vercel's rewrite does).
    event.respondWith(networkFirst(request, new URL('index.html', self.registration.scope).href));
    return;
  }
  if (NETWORK_FIRST.test(url.pathname)) {
    event.respondWith(networkFirst(request));
    return;
  }
  event.respondWith(cacheFirst(request));
});
