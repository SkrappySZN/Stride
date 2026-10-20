// Stride's service worker: lets the home-screen app open with no signal.
// The page itself is network-first, so a push to main still reaches everyone
// on their next open; the last copy is only the fallback. Versioned library
// and font files are cache-first. Data (Supabase, intervals.icu, weather) is
// never touched here — it always goes straight to the network.
const CACHE = 'stride-v1';
const SHELL = ['./', './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png'];
const LIBS = ['cdn.jsdelivr.net', 'fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

// Give the network a few seconds before falling back, so a weak signal
// doesn't leave the app on a blank screen.
async function networkFirst(req){
  const cache = await caches.open(CACHE);
  try {
    // no-cache: always ask the server (a cheap 304 when nothing changed) instead of a stale HTTP-cache copy.
    const res = await Promise.race([fetch(req, { cache:'no-cache' }), new Promise((_, rej) => setTimeout(() => rej(new Error('slow')), 4000))]);
    if (res.ok) cache.put(req.mode === 'navigate' ? './' : req, res.clone());
    return res;
  } catch {
    return (await cache.match(req.mode === 'navigate' ? './' : req, { ignoreSearch:true })) ?? Response.error();
  }
}
async function cacheFirst(req){
  const cache = await caches.open(CACHE), hit = await cache.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok || res.type === 'opaque') cache.put(req, res.clone());
  return res;
}
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin === location.origin) e.respondWith(networkFirst(req));
  else if (LIBS.includes(url.hostname)) e.respondWith(cacheFirst(req));
});
