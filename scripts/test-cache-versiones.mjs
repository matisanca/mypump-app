#!/usr/bin/env node
/* =============================================================
 * test-cache-versiones.mjs — Que el HTML y el JS de la web nunca se mezclen (incidente del 19/11).
 *
 * La 2.3.3 (sw v74) dejó alumnos en «Cargando tu plan…»: Cloudflare sirve los .js con max-age=14400 aunque _headers pida
 * no-cache, el teléfono juntó el cliente.html nuevo con el carga-simple.js viejo de su caché, `new CS.EsperaTrasTeclado`
 * tiró TypeError, se cortó el script e init() nunca corrió.
 *
 *  1. cliente.html pide cada .js y .css propio con `?v=<ASSET_V>` y ASSET_V sale de la VERSION de sw.js.
 *  2. El service worker precachea esas mismas URLs con cache:'reload', y la página (navegación) la pide revalidada
 *     (no-cache), con el pedido de siempre de respaldo.
 *  3. Nada de lo que cliente.html arma al cargar hace `new CS.Algo` sin mirar que exista.
 *  4. En Chrome headless (si está instalado): el HTML nuevo con un carga-simple.js SIN EsperaTrasTeclado arranca igual
 *     (init corre y la demo se ve, sin excepciones), y con el carga-simple.js de hoy también.
 *
 * USO:  node scripts/test-cache-versiones.mjs
 * ============================================================= */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join, extname, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = dirname(dirname(fileURLToPath(import.meta.url)));
const HTML = fs.readFileSync(join(raiz, 'public/cliente.html'), 'utf8');
const SW = fs.readFileSync(join(raiz, 'public/sw.js'), 'utf8');
const CARGA = fs.readFileSync(join(raiz, 'public/js/carga-simple.js'), 'utf8');

let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }

const VERSION = /^const VERSION\s*=\s*'([^']+)';$/m.exec(SW)[1];
const ASSET_V = VERSION.split('-')[0];

// ── 1. Las URL versionadas en cliente.html ──
await caso('cliente.html: cada .js y .css propio lleva ?v=<versión del sw>', () => {
  const refs = [...HTML.matchAll(/(?:src|href)=\\?"(\/(?:js|css)\/[^"\\]+)\\?"/g)].map((m) => m[1]);
  assert.ok(refs.length >= 60, `pocas referencias (${refs.length})`);
  const mal = refs.filter((u) => !u.endsWith(`?v=${ASSET_V}`));
  assert.deepEqual(mal, [], `sin ?v=${ASSET_V}`);
  assert.ok(refs.includes(`/js/carga-simple.js?v=${ASSET_V}`));
  assert.match(ASSET_V, /^v\d+$/);
});

// ── 2. El service worker, en una caja con dobles ──
function cargarSW({ RequestImpl, fetchImpl } = {}) {
  const oyentes = {};
  const guardados = [];
  const cache = { add: async (r) => { guardados.push(r); }, put: async () => {}, match: async () => undefined };
  const ctx = {
    self: { addEventListener: (n, f) => { oyentes[n] = f; }, skipWaiting: () => {}, clients: { claim: () => {} } },
    location: new URL('https://app.ejemplo.test/'), URL, console, setTimeout, clearTimeout, Date, Promise,
    caches: { open: async () => cache, match: async () => undefined, keys: async () => [] },
    fetch: fetchImpl || (async () => { throw new Error('sin red'); }),
  };
  if (RequestImpl) ctx.Request = RequestImpl;
  vm.createContext(ctx);
  vm.runInContext(SW, ctx);
  return { oyentes, guardados };
}
class RequestDoble {
  constructor(entrada, init = {}) {
    if (typeof entrada === 'string') { this.url = new URL(entrada, 'https://app.ejemplo.test/').href; this.mode = 'cors'; }
    else { Object.assign(this, entrada); }
    this.cache = init.cache || 'default';
  }
}

await caso('sw: la instalación precachea las URL versionadas con cache:reload', async () => {
  const { oyentes, guardados } = cargarSW({ RequestImpl: RequestDoble });
  let espera;
  oyentes.install({ waitUntil: (p) => { espera = p; } });
  await espera;
  const urls = guardados.map((r) => new URL(r.url).pathname + new URL(r.url).search);
  assert.ok(urls.includes(`/js/carga-simple.js?v=${ASSET_V}`), 'carga-simple versionado');
  assert.ok(urls.includes(`/css/tokens.css?v=${ASSET_V}`), 'tokens.css versionado');
  assert.ok(urls.includes('/cliente') && urls.includes('/manifest.json'), 'lo que no es .js ni .css va sin versión');
  for (const u of urls) if (/^\/(js|css)\//.test(u)) assert.ok(u.endsWith(`?v=${ASSET_V}`), u);
  assert.ok(guardados.every((r) => r.cache === 'reload'), 'todo con cache:reload');
  // Cada .js/.css que precachea el sw y pide cliente.html es la MISMA URL.
  const delHtml = new Set([...HTML.matchAll(/(?:src|href)="(\/(?:js|css)\/[^"]+)"/g)].map((m) => m[1]));
  for (const u of urls) if (/^\/(js|css)\//.test(u) && delHtml.has(u.split('?')[0] + `?v=${ASSET_V}`)) assert.ok(delHtml.has(u), u);
});

await caso('sw: sin Request (navegador viejo) la instalación no se corta', async () => {
  const { oyentes, guardados } = cargarSW();
  let espera;
  oyentes.install({ waitUntil: (p) => { espera = p; } });
  await espera;
  assert.ok(guardados.includes(`/js/carga-simple.js?v=${ASSET_V}`));
});

const navegacion = { url: 'https://app.ejemplo.test/cliente?t=abc', method: 'GET', mode: 'navigate' };
const respuesta = () => ({ ok: true, redirected: false, clone() { return this; } });
async function responderNavegacion(opc) {
  const { oyentes } = cargarSW(opc);
  let promesa;
  oyentes.fetch({ request: navegacion, respondWith: (p) => { promesa = p; }, waitUntil: () => {} });
  return promesa;
}

await caso('sw: la página se pide revalidada (no-cache)', async () => {
  const pedidos = [];
  const res = await responderNavegacion({ RequestImpl: RequestDoble, fetchImpl: async (r) => { pedidos.push(r); return respuesta(); } });
  assert.ok(res.ok);
  assert.equal(pedidos.length, 1);
  assert.equal(pedidos[0].cache, 'no-cache');
  assert.equal(pedidos[0].url, navegacion.url);
});

await caso('sw: si el pedido revalidado falla, va el de siempre', async () => {
  const pedidos = [];
  const res = await responderNavegacion({ RequestImpl: RequestDoble, fetchImpl: async (r) => {
    pedidos.push(r); if (r.cache === 'no-cache') throw new TypeError('no'); return respuesta();
  } });
  assert.ok(res.ok);
  assert.equal(pedidos.length, 2);
  assert.equal(pedidos[1], navegacion);
});

await caso('sw: si el navegador no deja armar el pedido, va el de siempre', async () => {
  const pedidos = [];
  class RequestQueTira { constructor() { throw new TypeError('mode navigate'); } }
  const res = await responderNavegacion({ RequestImpl: RequestQueTira, fetchImpl: async (r) => { pedidos.push(r); return respuesta(); } });
  assert.ok(res.ok);
  assert.deepEqual(pedidos, [navegacion]);
});

await caso('sw: los .js versionados se piden tal cual (sin tocar el pedido)', async () => {
  const pedidos = [];
  const { oyentes } = cargarSW({ RequestImpl: RequestDoble, fetchImpl: async (r) => { pedidos.push(r); return respuesta(); } });
  const req = { url: `https://app.ejemplo.test/js/carga-simple.js?v=${ASSET_V}`, method: 'GET', mode: 'no-cors' };
  let promesa;
  oyentes.fetch({ request: req, respondWith: (p) => { promesa = p; }, waitUntil: () => {} });
  await promesa;
  assert.deepEqual(pedidos, [req]);
});

// ── 3. Lo que cliente.html arma al cargar mira que la pieza exista ──
await caso('cliente.html: ningún `new CS.Algo` al cargar sin chequeo', () => {
  const sueltos = HTML.split('\n').filter((l) => /^(const|let|var)\b/.test(l) && /new CS\.\w+/.test(l) && !/typeof CS\.\w+ === 'function'/.test(l));
  assert.deepEqual(sueltos, []);
  assert.ok(!/new CS\.EsperaTrasTeclado/.test(HTML), 'la espera se arma con el respaldo');
  assert.match(HTML, /const _CsEspera = \(CS && typeof CS\.EsperaTrasTeclado === 'function'\) \? CS\.EsperaTrasTeclado : _CsEsperaRespaldo;/);
});

await caso('el respaldo de la espera se porta igual que EsperaTrasTeclado', () => {
  const i = HTML.indexOf('class _CsEsperaRespaldo {');
  const j = HTML.indexOf('\n}\n', i) + 2;
  const R = new Function(`${HTML.slice(i, j)}\nreturn _CsEsperaRespaldo;`)();
  const C = new Function('module', `${CARGA}\nreturn module.exports;`)({ exports: {} });
  for (const Clase of [R, C.EsperaTrasTeclado]) {
    const r = { t: 1000 }, e = new Clase(() => r.t);
    assert.equal(e.ms, 500);
    e.ver(false); assert.ok(e.admite());
    e.ver(true); assert.ok(!e.admite());
    r.t = 5000; e.ver(false); assert.ok(!e.admite()); assert.ok(e.recienVuelve());
    r.t = 5499; assert.ok(!e.admite());
    r.t = 5500; assert.ok(e.admite()); assert.ok(!e.recienVuelve());
  }
});

// ── 4. En el navegador de verdad ──
const CH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const sinEspera = CARGA.replace('EsperaTrasTeclado, ESPERA_TECLADO_MS,', '').replace(/class EsperaTrasTeclado \{[\s\S]*?\n  \}\n/, '');
await caso('carga-simple.js viejo armado para la prueba: sin EsperaTrasTeclado', () => {
  assert.ok(!/class EsperaTrasTeclado|EsperaTrasTeclado,/.test(sinEspera));
  const C = new Function('module', `${sinEspera}\nreturn module.exports;`)({ exports: {} });
  assert.equal(typeof C.EsperaTrasTeclado, 'undefined');
  assert.equal(typeof C.GuardiaOK, 'function');
});

async function abrirEnChrome(cargaSimple) {
  const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png' };
  const servidor = createServer((req, res) => {
    const ruta = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (ruta === '/js/config.js') {
      res.writeHead(200, { 'content-type': TIPOS['.js'], 'cache-control': 'no-store' });
      res.end(`window.MYPUMP_CONFIG = { SUPABASE_URL: location.origin + '/sb', SUPABASE_ANON_KEY: 'clave-de-prueba', VISION_URL: '', APP_URL: location.origin, VAPID_PUBLIC_KEY: '' };`);
      return;
    }
    if (ruta === '/js/carga-simple.js') { res.writeHead(200, { 'content-type': TIPOS['.js'], 'cache-control': 'no-store' }); res.end(cargaSimple); return; }
    if (ruta === '/sw.js' || ruta.startsWith('/sb/')) { res.writeHead(404); res.end(); return; }
    const archivo = join(raiz, 'public', normalize(ruta === '/cliente' ? '/cliente.html' : ruta).replace(/^(\.\.[/\\])+/, ''));
    if (!archivo.startsWith(join(raiz, 'public')) || !fs.existsSync(archivo) || !extname(archivo)) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': TIPOS[extname(archivo)] || 'application/octet-stream', 'cache-control': 'no-store' });
    res.end(fs.readFileSync(archivo));
  });
  await new Promise((r) => servidor.listen(0, '127.0.0.1', r));
  const BASE = `http://127.0.0.1:${servidor.address().port}`;
  const perfil = fs.mkdtempSync(join(tmpdir(), 'cache-versiones-chrome-'));
  const chrome = spawn(CH, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', `--user-data-dir=${perfil}`], { stdio: 'ignore' });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let ws, id = 0;
  const pend = new Map(), errores = [];
  const cmd = (method, params = {}) => new Promise((res, rej) => { const i = ++id; pend.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params })); });
  const evaluar = async (expr) => { const r = await cmd('Runtime.evaluate', { expression: expr, returnByValue: true }); return r.exceptionDetails ? undefined : r.result.value; };
  try {
    let lista = [];
    for (let i = 0; i < 160 && !lista.length; i++) {
      try {
        const puerto = fs.readFileSync(join(perfil, 'DevToolsActivePort'), 'utf8').split('\n')[0].trim();
        lista = (await (await fetch(`http://127.0.0.1:${puerto}/json`)).json()).filter((t) => t.type === 'page');
      } catch { /* arrancando */ }
      if (!lista.length) await sleep(250);
    }
    ws = new WebSocket(lista[0].webSocketDebuggerUrl);
    await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
    ws.onmessage = (e) => {
      const m = JSON.parse(e.data);
      if (m.id && pend.has(m.id)) { const p = pend.get(m.id); pend.delete(m.id); m.error ? p.rej(new Error(m.error.message)) : p.res(m.result); }
      else if (m.method === 'Runtime.exceptionThrown') errores.push(m.params.exceptionDetails.exception ? m.params.exceptionDetails.exception.description : m.params.exceptionDetails.text);
    };
    await cmd('Page.enable'); await cmd('Runtime.enable');
    await cmd('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
    await cmd('Page.navigate', { url: `${BASE}/cliente?demo=1` });
    let arranco = false;
    for (const fin = Date.now() + 15000; Date.now() < fin && !arranco;) {
      arranco = !!(await evaluar('typeof DATA !== "undefined" && !!DATA && DATA._isDemo === true && document.querySelector("#appRoot").hidden === false && document.querySelector("#loadScreen").hidden === true'));
      if (!arranco) await sleep(200);
    }
    const espera = await evaluar('typeof _csEspera !== "undefined" && _csEspera ? _csEspera.constructor.name : null');
    const pidio = await evaluar('[...document.scripts].map((s) => s.getAttribute("src")).filter(Boolean).find((s) => s.startsWith("/js/carga-simple.js"))');
    return { arranco, errores, espera, pidio };
  } finally {
    try { ws && ws.close(); } catch { /* nada */ }
    chrome.kill('SIGKILL');
    servidor.close();
    try { fs.rmSync(perfil, { recursive: true, force: true }); } catch { /* nada */ }
  }
}

if (!fs.existsSync(CH) || typeof WebSocket === 'undefined') {
  console.log('test-cache-versiones: sin Chrome (o sin WebSocket en Node), se saltea la prueba en el navegador');
} else {
  await caso('navegador: HTML nuevo + carga-simple.js SIN EsperaTrasTeclado → init corre y la demo se ve', async () => {
    const r = await abrirEnChrome(sinEspera);
    assert.deepEqual(r.errores, [], 'excepciones en la página');
    assert.ok(r.arranco, 'init no terminó (quedó en «Cargando tu plan…»)');
    assert.equal(r.espera, '_CsEsperaRespaldo', 'la espera sale del respaldo');
    assert.equal(r.pidio, `/js/carga-simple.js?v=${ASSET_V}`);
  });
  await caso('navegador: HTML nuevo + carga-simple.js de hoy → arranca con la espera de carga-simple.js', async () => {
    const r = await abrirEnChrome(CARGA);
    assert.deepEqual(r.errores, [], 'excepciones en la página');
    assert.ok(r.arranco, 'init no terminó');
    assert.equal(r.espera, 'EsperaTrasTeclado');
  });
}

if (!process.exitCode) console.log(`test-cache-versiones: ${ok} casos ok`);
