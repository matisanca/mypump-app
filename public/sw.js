/* =============================================================
   sw.js — Service Worker de MyPump (offline real para el gym, R3)

   Estrategia (pensada para una app que deploya seguido por git push):
   · CÓDIGO de la app (HTML/JS/CSS del mismo origen) → NETWORK-FIRST.
     Online SIEMPRE trae la última versión (un deploy nunca queda tapado por
     el cache — evita el clásico "cache poisoning" de PWAs). Offline cae al
     último cacheado. Consistente con el no-cache que ya hace _headers.
   · Lib de Supabase (CDN, versión fija @2) e ESTÁTICOS (iconos, imágenes) →
     CACHE-FIRST: rápidos y disponibles sin conexión.
   · Llamadas a Supabase (RPC, otro origen, o método != GET) → NO se tocan:
     pasan directo al navegador (nunca cacheamos datos ni rompemos las RPC).

   El VERSION se bumpea en cada cambio del set de assets para invalidar caches
   viejos en 'activate'.
   ============================================================= */
const VERSION       = 'v3-20260720';
const SHELL_CACHE   = `mypump-shell-${VERSION}`;
const RUNTIME_CACHE = `mypump-runtime-${VERSION}`;
const SUPABASE_LIB  = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';

const SHELL = [
  '/cliente.html',
  '/css/tokens.css',
  '/js/config.js',
  '/js/supabase-client.js',
  '/js/food-db.js',
  '/js/healthkit-bridge.js',
  '/js/app.js',
  '/js/theme.js',
  '/manifest.json',
  SUPABASE_LIB,
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(SHELL_CACHE)
      // allSettled + add individual: si un asset 404ea, no aborta todo el precache.
      .then((c) => Promise.allSettled(SHELL.map((u) => c.add(u))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k !== SHELL_CACHE && k !== RUNTIME_CACHE).map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;                       // POST/RPC → sin tocar

  // Lib de Supabase (CDN, versión fija) → cache-first (offline la necesita).
  if (req.url.startsWith(SUPABASE_LIB)) {
    e.respondWith(cacheFirst(req, RUNTIME_CACHE));
    return;
  }

  const url = new URL(req.url);
  if (url.origin !== location.origin) return;             // otro origen (RPC a supabase.co, etc.) → directo

  // Código de la app → network-first.
  const isCode = req.mode === 'navigate'
    || url.pathname === '/'
    || url.pathname === '/cliente'
    || /\.(html|js|css)$/.test(url.pathname);
  if (isCode) { e.respondWith(networkFirst(req)); return; }

  // Estáticos del mismo origen (iconos, imágenes de ejercicios) → cache-first.
  e.respondWith(cacheFirst(req, RUNTIME_CACHE));
});

async function networkFirst(req) {
  try {
    const res = await fetch(req);
    if (res && res.ok) {
      const copy = res.clone();
      caches.open(SHELL_CACHE).then((c) => c.put(req, copy)).catch(() => {});
    }
    return res;
  } catch (err) {
    const cached = await caches.match(req, { ignoreSearch: true });
    if (cached) return cached;
    // Navegación offline sin match exacto (ej: /cliente?t=…) → servir el shell.
    if (req.mode === 'navigate') {
      const shell = await caches.match('/cliente.html');
      if (shell) return shell;
    }
    throw err;
  }
}

async function cacheFirst(req, cacheName) {
  const cached = await caches.match(req, { ignoreSearch: true });
  if (cached) return cached;
  try {
    const res = await fetch(req);
    if (res && (res.ok || res.type === 'opaque')) {
      const copy = res.clone();
      caches.open(cacheName).then((c) => c.put(req, copy)).catch(() => {});
    }
    return res;
  } catch (err) {
    if (cached) return cached;
    throw err;
  }
}
