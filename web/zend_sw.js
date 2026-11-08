// Zend web offline cache: lets app.usezend.app open with no signal, showing what this browser
// last loaded. Paying without signal still needs the tab to have stayed open since it was online
// (the signing key lives only in memory), the same as the phone app.
//
// Why it's shaped this way (Flutter's own service worker was removed for these reasons, see
// .github/workflows/web.yml):
//  - Network first, always. Online, every request goes to the network, so a deploy and its
//    headers (including the CSP) are picked up immediately. The cache answers only when the
//    network actually fails, never on a slow network, so a cached page is never mixed with
//    newer files while online.
//  - One cache per build (`__ZEND_BUILD__`, replaced by the git SHA in CI). Activating deletes
//    every other cache on this origin, including Flutter's old ones.
//  - It caches only what this browser fetched: the page asks it to keep the files it loaded.
//    Large engine files come from the HTTP cache (immutable), so this costs almost no data.
//  - Kill switch: build with `__ZEND_SW__` set to `off` and this worker unregisters itself and
//    clears its caches on the next visit.
const BUILD = '__ZEND_BUILD__';
const ENABLED = '__ZEND_SW__' !== 'off';
const CACHE = `zend-web-${BUILD}`;
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'zxing-0.21.3.min.js',
  'zend_sw_register.js',
];
// OAuth callbacks must always be fresh and never come from a cache.
const NEVER = ['/auth.html', '/auth.js', '/zend_sw.js'];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    if (!ENABLED) return self.skipWaiting();
    const cache = await caches.open(CACHE);
    await Promise.all(SHELL.map((u) => cache.add(new Request(u, { cache: 'no-cache' })).catch(() => {})));
    // Engine and asset files rarely change between builds: carry over what the last build's
    // cache had (re-fetched, so from the HTTP cache or fresh), so offline keeps working.
    for (const name of await caches.keys()) {
      if (name === CACHE || !name.startsWith('zend-web-')) continue;
      const old = await caches.open(name);
      for (const req of await old.keys()) {
        const path = new URL(req.url).pathname;
        if (path.startsWith('/canvaskit/') || path.startsWith('/assets/')) {
          await cache.add(req.url).catch(() => {});
        }
      }
    }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (!ENABLED || name !== CACHE) await caches.delete(name);
    }
    if (!ENABLED) {
      await self.registration.unregister();
      return;
    }
    await self.clients.claim();
  })());
});

// The page sends the files it loaded (performance entries), once Flutter has started.
self.addEventListener('message', (event) => {
  const d = event.data || {};
  if (!ENABLED || d.type !== 'zend-cache-urls' || !Array.isArray(d.urls)) return;
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    for (const u of d.urls.slice(0, 400)) {
      if (!cacheable(new URL(u, self.location.origin))) continue;
      if (await cache.match(u)) continue;
      await cache.add(u).catch(() => {});
    }
  })());
});

function cacheable(url) {
  return url.origin === self.location.origin && !NEVER.includes(url.pathname);
}

self.addEventListener('fetch', (event) => {
  if (!ENABLED) return;
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (!cacheable(url)) return;
  const navigation = req.mode === 'navigate';
  event.respondWith((async () => {
    try {
      const res = await fetch(req);
      if (res.ok && res.type === 'basic') {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(navigation ? 'index.html' : req, copy)).catch(() => {});
      }
      return res;
    } catch (err) {
      // Offline: the last copy this browser had.
      const cached = navigation ? await caches.match('index.html') : await caches.match(req);
      if (cached) return cached;
      throw err;
    }
  })());
});
