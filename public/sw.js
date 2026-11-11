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
const VERSION       = 'v58-20261110-230';
const SHELL_CACHE   = `mypump-shell-${VERSION}`;
const RUNTIME_CACHE = `mypump-runtime-${VERSION}`;
const SUPABASE_LIB  = '/js/vendor/supabase-js.min.js';   // vendorizada el 20-sep-2026 (antes CDN)

const SHELL = [
  // '/cliente' ANTES que '/cliente.html': en Cloudflare Pages, '/cliente.html'
  // es un 308 a '/cliente', y cache.add() guarda la respuesta REDIRIGIDA. Una
  // respuesta redirigida no sirve para una navegación (el navegador la
  // rechaza), así que la PWA abierta sin señal desde el ícono no cargaba.
  // En dev local (npx serve) '/cliente' puede no existir: allSettled lo tolera.
  '/cliente',
  '/cliente.html',
  '/css/tokens.css',
  // La fuente de marca. Va en el SHELL para que offline se vea IGUAL que
  // online: sin esto, el cliente en el gimnasio sin senal cae al fallback del
  // sistema y la app cambia de cara justo cuando mas se usa.
  '/fonts/archivo-var-latin.woff2',
  '/js/config.js',
  '/js/supabase-client.js',
  '/js/food-db.js',
  '/js/ajustes-dieta.js',
  '/js/dias-dieta.js',
  '/js/codigo-barras.js',
  '/js/reglas-guia.js',
  '/js/guia.js',
  '/js/reglas-entreno.js',
  '/js/carga-simple.js',
  '/js/gimnasio.js',
  '/js/gimnasio-cola.js',
  '/js/gimnasio-ui.js',
  '/js/metas.js',
  '/css/gimnasio.css',
  '/js/tecnica.js',
  '/js/tecnica-cola.js',
  '/js/tecnica-ui.js',
  '/js/chat-adjuntos.js',
  '/js/documentos.js',
  '/css/tecnica.css',
  '/js/novedades-plan.js',
  '/js/novedades-ui.js',
  '/css/novedades.css',
  '/js/devolucion.js',
  '/css/devolucion.css',
  '/js/feedback.js',
  '/js/feedback-ui.js',
  '/css/feedback.css',
  '/js/estudios.js',
  '/js/estudios-cola.js',
  '/js/estudios-ui.js',
  '/css/estudios.css',
  '/js/healthkit-bridge.js',
  '/js/notificaciones.js',
  '/js/app.js',
  '/js/theme.js',
  '/js/deeplink.js',
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

  const url = new URL(req.url);
  // Gimnasio por fotos: ni las fotos ni sus llamadas pasan por un cache, tampoco si algún día se sirven del mismo origen.
  // (Hoy ya no llegan acá: las subidas son POST y las URLs firmadas, de otro origen.)
  if (url.pathname.startsWith('/gimnasio/')) return;
  // Técnica por video: lo mismo. La subida es POST y el video firmado es de otro origen.
  if (url.pathname.startsWith('/tecnica/')) return;
  // Fotos y audios del chat: privados, nunca en un cache (la subida es POST y lo firmado vence en una hora).
  if (url.pathname.startsWith('/chat/') || url.pathname.includes('/storage/v1/object/sign/chat-adjuntos/')) return;
  // Estudios y órdenes: datos médicos. Sus llamadas son POST y los archivos firmados, de otro origen; nada de eso se guarda.
  if (url.pathname.startsWith('/estudios/')) return;
  // Lib de Supabase (vendorizada, mismo origen) → cache-first: cambia solo
  // cuando se reemplaza el archivo (y con él, VERSION).
  if (url.origin === location.origin && url.pathname === SUPABASE_LIB) {
    e.respondWith(cacheFirst(req, RUNTIME_CACHE));
    return;
  }

  if (url.origin !== location.origin) return;             // otro origen (RPC a supabase.co, etc.) → directo

  // Código de la app → network-first.
  const isCode = req.mode === 'navigate'
    || url.pathname === '/'
    || url.pathname === '/cliente'
    || /\.(html|js|css)$/.test(url.pathname);
  if (isCode) { e.respondWith(networkFirst(req, e)); return; }

  // Estáticos del mismo origen (iconos, imágenes de ejercicios) → cache-first.
  e.respondWith(cacheFirst(req, RUNTIME_CACHE));
});

/* Auditoría 10/11, F2: con la señal «colgada» (ni responde ni corta) el fetch
 * del código esperaba sin tope y la app no abría. Pasado este tope, si hay copia
 * se sirve la copia; la red sigue por detrás y actualiza el caché para la próxima. */
const TOPE_RED_CODIGO_MS = 6000;

async function copiaDelCodigo(req) {
  const cached = await caches.match(req, { ignoreSearch: true });
  if (cached && !(req.mode === 'navigate' && cached.redirected)) return cached;
  // Navegación offline sin match exacto (ej: /cliente?t=…) → servir el shell.
  if (req.mode === 'navigate') {
    const candidatos = ['/cliente', '/cliente.html'];
    for (const u of candidatos) {
      const shell = await caches.match(u);
      if (shell && !shell.redirected) return shell;
    }
  }
  return null;
}

// Si la página salió de la copia por el tope, lo que pide enseguida (sus .js y .css) también sale de la copia: si no, una
// página vieja podía cargar código nuevo de la red (revisión 10/11).
let paginaDeLaCopiaHasta = 0;

async function networkFirst(req, e) {
  if (req.mode !== 'navigate' && Date.now() < paginaDeLaCopiaHasta) {
    const cached = await copiaDelCodigo(req);
    if (cached) return cached;
  }
  let guardado = Promise.resolve();
  const red = fetch(req).then((res) => {
    if (res && res.ok && !res.redirected) {
      const copy = res.clone();
      guardado = caches.open(SHELL_CACHE).then((c) => c.put(req, copy)).catch(() => {});
    }
    return res;
  });
  // La red sigue por detrás aunque se sirva la copia: que el navegador no corte el service worker antes de guardarla.
  if (e && e.waitUntil) e.waitUntil(red.then(() => guardado).catch(() => {}));
  let reloj = null;
  const tope = new Promise((ok) => { reloj = setTimeout(() => ok(null), TOPE_RED_CODIGO_MS); });
  try {
    const res = await Promise.race([red, tope]);
    if (res) return res;
    // Tardó de más: con copia, la copia; sin copia no hay otra que esperar a la red.
    const cached = await copiaDelCodigo(req);
    if (cached) {
      if (req.mode === 'navigate') paginaDeLaCopiaHasta = Date.now() + 30000;
      return cached;
    }
    return await red;
  } catch (err) {
    const cached = await copiaDelCodigo(req);
    if (cached) return cached;
    throw err;
  } finally {
    clearTimeout(reloj);
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

/* ═══ WEB PUSH ═════════════════════════════════════════════════════════════
 *
 * Sin estos dos handlers no hay Web Push posible: el navegador entrega el
 * mensaje al service worker y, si nadie lo escucha, Chrome muestra una
 * notificación genérica de "este sitio se actualizó en segundo plano" y
 * Safari directamente no muestra nada.
 *
 * Esto es lo que le da timbre a los 62 clientes que usan la app como link del
 * navegador — y a Android entero, sin Firebase y sin esperar a Google.
 */

self.addEventListener('push', (e) => {
  let d = {};
  // El payload puede venir vacío o no ser JSON: un push sin datos igual tiene
  // que mostrar algo, porque el sistema operativo YA despertó al worker y si
  // no se muestra ninguna notificación Chrome muestra la suya, que dice algo
  // como "actualizado en segundo plano" y no significa nada para el cliente.
  try { d = e.data ? e.data.json() : {}; } catch (_) {
    try { d = { body: e.data.text() }; } catch (__) { d = {}; }
  }

  const titulo = d.title || 'MyPump';
  const opciones = {
    body: d.body || '',
    icon: '/icons/icon-192.png?v=3',
    badge: '/icons/icon-192.png?v=3',
    // Un tag por destino: si llegan tres mensajes seguidos del chat, se
    // reemplazan en vez de apilarse. Tres notificaciones para una conversación
    // es lo que hace que se apague todo el permiso.
    tag: d.destino ? `mypump-${d.destino}` : 'mypump',
    renotify: true,
    data: { destino: d.destino || 'chat' },
  };
  e.waitUntil(self.registration.showNotification(titulo, opciones));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const destino = (e.notification.data && e.notification.data.destino) || 'chat';
  const url = `/cliente?scene=${encodeURIComponent(destino)}`;

  e.waitUntil((async () => {
    const abiertas = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    // Si la app ya está abierta, se la enfoca y se navega ahí mismo. Abrir una
    // segunda pestaña de la misma app deja al cliente con dos, y la vieja con
    // datos de hace rato.
    for (const c of abiertas) {
      if (c.url.includes('/cliente')) {
        await c.focus();
        if ('navigate' in c) { try { await c.navigate(url); } catch (_) {} }
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
