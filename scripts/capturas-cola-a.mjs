// Prueba de punta a punta y capturas de la «cola A» de la 2.3.0 en la web: récords y logros (`wins_app`), la lista previa
// a la videollamada (`lista_previa`) y la demo sin cuenta con historia.
//
// Sin producción y sin red de afuera: sirve public/ en 127.0.0.1 con un config.js que apunta Supabase a ESTE servidor, y
// un doble contesta cada RPC (plan y cuenta inventados). Maneja Chrome headless por CDP con un viewport de teléfono.
//
// USO:  node scripts/capturas-cola-a.mjs [carpeta de salida]
// Sale con código 1 si algo no da (una llamada que no debía salir, un texto que falta, scroll horizontal).
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, mkdirSync, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { join, extname, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { dieta } from './lib/plan-sintetico.mjs';

const raiz = dirname(dirname(fileURLToPath(import.meta.url)));
const SALIDA = process.argv[2] || join(raiz, 'capturas-cola-a');
mkdirSync(SALIDA, { recursive: true });
const CH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const ANCHO = 390, ALTO = 844;
const TOKEN = 'tok_prueba_cola_a_0001';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const V = JSON.parse(readFileSync(join(raiz, 'scripts/fixtures/wins.json'), 'utf8'));
const VL = JSON.parse(readFileSync(join(raiz, 'scripts/fixtures/lista_previa.json'), 'utf8'));
const F = V.fijos;

// ───────────────────────── El doble del servidor ─────────────────────────
const dos = (n) => String(n).padStart(2, '0');
const fechaLocal = (d) => `${d.getFullYear()}-${dos(d.getMonth() + 1)}-${dos(d.getDate())}`;
const diasAtras = (n) => { const d = new Date(); d.setDate(d.getDate() - n); return d; };
const RUTINA = {
  nombre_plan: 'Plan de prueba', split: 'Tirón', semanas_total: 12,
  dias: [{ id: 'lun', n: 1, nombre: 'Tirón', bloques: [{ titulo: 'BLOQUE 1', subtitulo: 'Espalda y bíceps', ejercicios: [
    { id: 'e1', nombre: 'Remo con barra', tipo: 'compuesto', series: 2, reps: '8-10', rir_objetivo: '0', descanso_segundos: 120 },
    { id: 'e2', nombre: 'Curl con barra Z', tipo: 'aislamiento', series: 2, reps: '10-12', rir_objetivo: '0', descanso_segundos: 90 },
  ] }] }],
};
const D = { };
function reiniciar(o = {}) {
  Object.assign(D, {
    config: {}, permiso: false, filas: [], llamadas: [], cortar: new Set(), sinFuncion: new Set(),
    lista: VL.casos[0].respuesta, reserva: null, metaPasos: null, pasos: null, sinRutina: false,
  }, o);
}
reiniciar();
const isoArt = (t) => { const d = new Date(t - 3 * 3600000); return `${d.getUTCFullYear()}-${dos(d.getUTCMonth() + 1)}-${dos(d.getUTCDate())}T${dos(d.getUTCHours())}:${dos(d.getUTCMinutes())}:00-03:00`; };
function reservaDe(tipo) {
  const i = Date.now() + 3 * 86400000;
  return { id: 'r1', inicio: isoArt(i), fin: isoArt(i + 3600000), estado: 'confirmada', tipo, meet_url: 'https://meet.google.com/abc-defg-hij', sala_abierta_en: null };
}
function responder(fn, p) {
  D.llamadas.push({ fn, ...p });
  if (D.cortar.has(fn)) return 'cortar';
  if (D.sinFuncion.has(fn)) return { status: 404, json: { code: 'PGRST202', message: `Could not find the function public.${fn} in the schema cache`, details: null, hint: null } };
  const palanca = D.config.wins_app === true;
  switch (fn) {
    case 'mypump_get_cliente_info': return { json: [{ cliente_id: 'cli_prueba', nombre: 'Alumno De Prueba', perfil: 'natural' }] };
    case 'mypump_get_rutina_activa': if (D.sinRutina) return { json: [] }; return { json: [{ id: 'rut_prueba', version: 1, estructura: RUTINA, semana_actual: 2 }] };
    case 'mypump_get_dieta_activa': { const e = dieta({ seed: 3 }); if (D.metaPasos) e.meta_pasos_dia = D.metaPasos; return { json: [{ id: 'die_prueba', version: 1, estructura: e }] }; }
    case 'mypump_get_app_config': return { json: D.config };
    case 'mypump_get_historico_por_clave': {
      // Dos sesiones anteriores por ejercicio, 50 kg × 8 y × 8.
      const filas = [];
      if (D.sinRutina) return { json: [] };   // esta cuenta todavía no entrenó
      for (const clave of p.p_claves || []) for (const dias of [7, 14]) for (const serie of [1, 2]) {
        const t = diasAtras(dias); t.setHours(18, 30 + serie * 3, 0, 0);
        filas.push({ clave, serie_numero: serie, peso_kg: 50, reps_realizadas: 8, rir_real: 0, notas: null, registrado_en: t.toISOString() });
      }
      return { json: filas };
    }
    case 'mypump_iniciar_sesion': return { json: '11111111-2222-4333-8444-555555555555' };
    case 'mypump_finalizar_sesion': return { json: true };
    case 'mypump_get_salud': {
      if (!D.pasos) return { json: [] };
      return { json: D.pasos.map((v, i) => ({ fecha: fechaLocal(diasAtras(D.pasos.length - 1 - i)), tipo: 'pasos', valor: v, fuente: 'apple_health' })) };
    }
    case 'mypump_wins_estado': return { json: { ok: true, activa: palanca, permiso: D.permiso } };
    case 'mypump_wins_permiso':
      if (p.p_otorga) { if (!palanca) return { json: { ok: false, motivo: 'apagada' } }; D.permiso = true; return { json: { ok: true, permiso: true } }; }
      { D.permiso = false; const n = D.filas.length; D.filas = []; return { json: { ok: true, permiso: false, retirados: n } }; }
    case 'mypump_wins_registrar': {
      if (!palanca) return { json: { ok: true, guardado: false, motivo: 'apagada' } };
      if (!D.permiso) return { json: { ok: true, guardado: false, motivo: 'sin_permiso' } };
      const ya = D.filas.some((f) => f.p_id === p.p_id);
      if (!ya) D.filas.push(p);
      return { json: { ok: true, guardado: true, ya } };
    }
    case 'mypump_lista_previa': return { json: D.config.lista_previa === true ? D.lista : { ok: true, activa: false, items: [] } };
    case 'entregas_app_resumen': return { json: { ok: true, total: 13, vistos: 11, minutos_restantes: 9, fecha_entrega: null, mostrar_tarjeta: true, reserva: D.reserva } };
    case 'entregas_app_agenda': return { json: { ok: true, autorizada: true, habilitada: true, faltan: 0, zona: 'America/Argentina/Buenos_Aires', tipo: D.reserva ? D.reserva.tipo : 'comienzo',
      entrar_desde_min: 10, aviso_min: 30, textos: {}, franjas: [], reserva: D.reserva, cambio: null } };
    default: return { json: null };
  }
}
const de = (fn) => D.llamadas.filter((l) => l.fn === fn);
const nuevas = () => D.llamadas.filter((l) => /^mypump_wins_|^mypump_lista_previa$/.test(l.fn));

// ───────────────────────── El servidor local ─────────────────────────
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.json': 'application/json', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png' };
const pedidosDemo = [];
const servidor = createServer((req, res) => {
  const ruta = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (ruta.startsWith('/sb/')) {
    const m = /^\/sb\/rest\/v1\/rpc\/([a-z0-9_]+)$/.exec(ruta);
    let cuerpo = '';
    req.on('data', (c) => { cuerpo += c; });
    req.on('end', () => {
      if (!m) { D.llamadas.push({ fn: `(otra) ${req.method} ${ruta}` }); res.writeHead(404, { 'content-type': 'application/json' }); res.end('{}'); return; }
      let p = {}; try { p = JSON.parse(cuerpo || '{}'); } catch { /* vacío */ }
      const r = responder(m[1], p);
      if (r === 'cortar') { req.socket.destroy(); return; }
      res.writeHead(r.status || 200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(r.json));
    });
    return;
  }
  if (ruta === '/js/config.js') {
    res.writeHead(200, { 'content-type': TIPOS['.js'], 'cache-control': 'no-store' });
    res.end(`window.MYPUMP_CONFIG = { SUPABASE_URL: location.origin + '/sb', SUPABASE_ANON_KEY: 'clave-de-prueba', VISION_URL: '', APP_URL: location.origin, VAPID_PUBLIC_KEY: '' };`);
    return;
  }
  // Sin service worker en la prueba: cada escenario carga el código tal cual está en disco.
  if (ruta === '/sw.js') { res.writeHead(404); res.end(); return; }
  if (ruta.startsWith('/demo/')) pedidosDemo.push(ruta);
  const archivo = join(raiz, 'public', normalize(ruta === '/cliente' ? '/cliente.html' : ruta).replace(/^(\.\.[/\\])+/, ''));
  if (!archivo.startsWith(join(raiz, 'public')) || !existsSync(archivo) || !extname(archivo)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': TIPOS[extname(archivo)] || 'application/octet-stream', 'cache-control': 'no-store' });
  res.end(readFileSync(archivo));
});
await new Promise((r) => servidor.listen(0, '127.0.0.1', r));
const BASE = `http://127.0.0.1:${servidor.address().port}`;

const perfil = mkdtempSync(join(tmpdir(), 'cola-a-chrome-'));
const chrome = spawn(CH, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--no-default-browser-check',
  '--remote-debugging-port=0', `--user-data-dir=${perfil}`], { stdio: 'ignore' });

let ws, id = 0, fallas = 0, hechas = 0;
const pend = new Map();
const erroresPagina = [];
const cmd = (method, params = {}) => new Promise((res, rej) => { const i = ++id; pend.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params })); });
const evaluar = async (expr) => {
  const r = await cmd('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(`${expr.slice(0, 120)}: ${JSON.stringify(r.exceptionDetails.exception && r.exceptionDetails.exception.description)}`);
  return r.result.value;
};
const comprobar = (c, m) => { hechas++; console.log(`${c ? '  ✓' : '  ✗'} ${m}`); if (!c) fallas++; };
const hay = (sel) => evaluar(`!!document.querySelector(${JSON.stringify(sel)})`);
const visible = (sel) => evaluar(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); if (!e) return false; const r = e.getBoundingClientRect(); return !e.closest('[hidden]') && r.width > 0 && r.height > 0; })()`);
const texto = (sel) => evaluar(`((document.querySelector(${JSON.stringify(sel)}) || {}).textContent || '').replace(/\\s+/g, ' ').trim()`);
const clic = async (sel) => comprobar(await evaluar(`(() => { const b = document.querySelector(${JSON.stringify(sel)}); if (!b || b.disabled) return false; b.click(); return true; })()`), `clic en ${sel}`);
async function esperar(expr, ms = 8000) {
  const fin = Date.now() + ms;
  while (Date.now() < fin) { try { if (await evaluar(expr)) return true; } catch { /* cargando */ } await sleep(150); }
  return false;
}
async function abrir(consulta, tema = 'light') {
  await cmd('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: tema }] });
  await cmd('Page.navigate', { url: `${BASE}/blanco.html` }).catch(() => {});
  await cmd('Page.navigate', { url: `${BASE}/cliente.html?${consulta}` });
  await esperar('typeof DATA !== "undefined" && !!DATA && !!document.querySelector("#scene-train .block")', 15000);
  await evaluar(`(() => { try { localStorage.setItem('mypump-theme', ${JSON.stringify(tema)}); } catch (_) {} document.documentElement.setAttribute('data-theme', ${JSON.stringify(tema)}); document.body.setAttribute('data-theme', ${JSON.stringify(tema)}); })()`);
  await sleep(900);
}
const limpiar = () => evaluar('(() => { try { localStorage.clear(); sessionStorage.clear(); localStorage.setItem("mypump_a2hs_v1", "dismissed"); } catch (_) {} return true; })()');   // sin el cartel de «Instalá la app», que tapa
const letra = (pct) => evaluar(`document.documentElement.style.fontSize = ${JSON.stringify(pct || '')}`);
async function capturar(nombre, sel) {
  // Sin scroll horizontal y nada cortado: lo que se mira (o toda la página) entra en el ancho.
  const ok = await evaluar(`(() => {
    if (document.documentElement.scrollWidth > innerWidth + 1) return 'scroll horizontal en la página';
    const raiz = ${sel ? `document.querySelector(${JSON.stringify(sel)})` : 'null'};
    if (${sel ? 'true' : 'false'} && !raiz) return 'no está ${sel || ''}';
    for (const e of (raiz ? [raiz, ...raiz.querySelectorAll('*')] : [])) {
      const r = e.getBoundingClientRect();
      if (e.ownerSVGElement) continue;
      if (r.width && (r.left < -1 || r.right > innerWidth + 1)) return 'se sale del ancho: ' + e.tagName + '.' + (e.getAttribute('class') || '');
      if (e.tagName === 'BUTTON' && e.scrollWidth > e.clientWidth + 1) return 'texto cortado en el botón: ' + e.textContent.trim().slice(0, 30);
    }
    return '';
  })()`);
  comprobar(!ok, `${nombre}: entra en ${ANCHO} px sin texto cortado${ok ? ` (${ok})` : ''}`);
  const { data } = await cmd('Page.captureScreenshot', { format: 'png' });
  writeFileSync(join(SALIDA, `${nombre}.png`), Buffer.from(data, 'base64'));
  console.log(`  → ${join(SALIDA, `${nombre}.png`)}`);
}
// Los botones del pie de una hoja tienen que quedar a la vista (no tapados ni fuera de pantalla).
const botonesALaVista = (sel) => evaluar(`[...document.querySelectorAll(${JSON.stringify(sel)})].every((b) => { const r = b.getBoundingClientRect(); const e = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return r.top >= 0 && r.bottom <= innerHeight + 1 && (e === b || b.contains(e)); })`);

// Dos récords: remo 52,5 × 8 (más kg) y curl 50 × 9 (una rep más), y «Confirmar y cerrar».
async function cerrarConRecords() {
  await evaluar(`(() => { const s = STATE.session;
    Object.assign(s.e1.sets[0], { kg: '52.5', reps: '8', confirmed: true }); Object.assign(s.e2.sets[0], { kg: '50', reps: '9', confirmed: true });
    renderTrain(); return true; })()`);
  await evaluar('openEarlyFinishModal().then(() => true)');
  await esperar('!!document.querySelector("#finConfirm")');
  await clic('#finConfirm');
  await esperar('_diaFinalizado === true', 6000);
  await sleep(700);
}

try {
  let lista;
  for (let i = 0; i < 160; i++) {
    try {
      const puerto = readFileSync(join(perfil, 'DevToolsActivePort'), 'utf8').split('\n')[0].trim();
      lista = await (await fetch(`http://127.0.0.1:${puerto}/json`)).json(); if (lista.length) break;
    } catch { /* arrancando */ }
    await sleep(250);
  }
  const pagina = lista.find((t) => t.type === 'page');
  ws = new WebSocket(pagina.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pend.has(m.id)) { const p = pend.get(m.id); pend.delete(m.id); m.error ? p.rej(new Error(m.error.message)) : p.res(m.result); }
    else if (m.method === 'Runtime.exceptionThrown') erroresPagina.push(m.params.exceptionDetails.exception ? m.params.exceptionDetails.exception.description : m.params.exceptionDetails.text);
  };
  await cmd('Page.enable'); await cmd('Runtime.enable');
  await cmd('Emulation.setDeviceMetricsOverride', { width: ANCHO, height: ALTO, deviceScaleFactor: 2, mobile: true });
  await cmd('Emulation.setTouchEmulationEnabled', { enabled: true });
  await cmd('Page.navigate', { url: `${BASE}/blanco.html` });
  const Q = `t=${TOKEN}`;

  // ── 1. Palancas apagadas: nada nuevo se ve ni se llama ──
  console.log('\n▸ palancas apagadas');
  reiniciar({ reserva: reservaDe('comienzo') });
  await limpiar(); await abrir(Q);
  await cerrarConRecords();
  comprobar(!(await hay('.wn-capa')), 'cerrar con récords: sin festejo');
  comprobar(!(await hay('[data-test="lista-previa"]')), 'sin lista previa (ni sola ni en la tarjeta)');
  comprobar(await hay('.vl-tarjeta'), 'la tarjeta de la videollamada sigue estando');
  await evaluar('(setScene("misdatos"), renderMisDatos(), true)');
  comprobar(!(await hay('[data-test="wins-ajuste"]')), 'Mis datos sin la sección Logros');
  comprobar(nuevas().length === 0, `cero llamadas nuevas (${nuevas().map((l) => l.fn).join(', ') || 'ninguna'})`);
  comprobar(de('mypump_finalizar_sesion').length === 1, 'el cierre de la sesión salió igual');

  // ── 2. Récords: festejo sin permiso → hoja de permiso → con permiso ──
  for (const tema of ['light', 'dark']) {
    console.log(`\n▸ festejo y permiso (${tema})`);
    reiniciar({ config: { wins_app: true } });
    await limpiar(); await abrir(Q, tema);
    comprobar(de('mypump_wins_estado').length === 1, 'al abrir: mypump_wins_estado una vez');
    await cerrarConRecords();
    comprobar(await visible('[data-test="wins-festejo"]'), 'después de «Confirmar y cerrar»: el festejo se abre solo');
    comprobar((await texto('#wnTit')) === '2 récords hoy' && (await texto('#wnSub')) === 'Superaste 2 de tus mejores marcas.', `título y subtítulo: «${await texto('#wnTit')}» / «${await texto('#wnSub')}»`);
    const filas = await evaluar('[...document.querySelectorAll("[data-test=wins-fila]")].map((f) => [...f.querySelectorAll(".wn-ej,.wn-antes,.wn-marca,.wn-chip")].map((x) => x.textContent.trim()).join(" "))');
    comprobar(filas.length === 2 && filas[0] === 'Remo con barra Antes: 50 kg × 8 52,5 kg × 8 +2,5 kg' && filas[1] === 'Curl con barra Z Antes: 50 kg × 8 50 kg × 9 +1 rep', `filas: ${JSON.stringify(filas)}`);
    comprobar((await texto('[data-test="wins-contarle"]')) === F.contarle && (await texto('[data-test="wins-seguir"]')) === F.seguir, 'botones «Contarle a Mati» y «Seguir»');
    comprobar(de('mypump_wins_registrar').length === 0, 'sin permiso no se registra nada');
    comprobar(await botonesALaVista('.wn-festejo .wn-boton'), 'los dos botones a la vista');
    await capturar(`web-festejo-sin-permiso-${tema}`, '.wn-festejo .wn-caja');

    await clic('[data-test="wins-contarle"]');
    await sleep(350);
    comprobar((await texto('#wnPerTit')) === F.permiso_titulo, `hoja de permiso: «${await texto('#wnPerTit')}»`);
    comprobar(JSON.stringify(await evaluar('[...document.querySelectorAll(".wn-parrafo")].map((p) => p.textContent)')) === JSON.stringify(F.permiso_cuerpo), 'los 3 párrafos del permiso');
    comprobar(await botonesALaVista('.wn-permiso .wn-boton'), '«Sí, compartir» y «Ahora no» a la vista');
    await capturar(`web-permiso-${tema}`, '.wn-permiso .wn-caja');

    if (tema === 'light') {
      // «Ahora no» cierra y no queda dado; el botón sigue en el festejo.
      await clic('[data-test="wins-permiso-no"]');
      comprobar(!(await hay('.wn-permiso')) && (await hay('[data-test="wins-contarle"]')) && de('mypump_wins_permiso').length === 0, '«Ahora no»: cierra, sin llamada, y el botón sigue en el festejo');
      await clic('[data-test="wins-contarle"]');
      // Sin red: avisa y no queda dado.
      D.cortar.add('mypump_wins_permiso');
      await clic('[data-test="wins-permiso-si"]');
      await esperar('!document.querySelector("[data-test=wins-sin-red]").hidden', 6000);
      comprobar((await texto('[data-test="wins-sin-red"]')) === F.sin_red && !D.permiso && (await evaluar('window.Wins.permiso')) !== true, `sin red: «${await texto('[data-test="wins-sin-red"]')}» y no queda dado`);
      D.cortar.clear();
    }
    await clic('[data-test="wins-permiso-si"]');
    await esperar('!!document.querySelector("[data-test=wins-con-permiso]")', 6000);
    comprobar(!(await hay('.wn-permiso')) && (await texto('[data-test="wins-con-permiso"]')) === 'Mati se va a enterar de estos logros.', `con permiso: «${await texto('[data-test="wins-con-permiso"]')}»`);
    const per = de('mypump_wins_permiso').pop();
    comprobar(per && per.p_otorga === true && per.p_version === 1 && per.p_plataforma === 'web' && per.p_token === TOKEN, 'mypump_wins_permiso(token, true, 1, web)');
    await esperar('window.Wins.cola.length === 0', 6000);
    const reg = de('mypump_wins_registrar');
    comprobar(reg.length === 2 && reg[0].p_tipo === 'record_kg' && reg[0].p_clave === 'remo con barra' && reg[1].p_tipo === 'record_reps' && reg[1].p_clave === 'curl con barra z'
      && reg.every((r) => /^[0-9a-f-]{36}$/.test(r.p_id) && r.p_dia === fechaLocal(new Date())), `dos mypump_wins_registrar (${reg.map((r) => r.p_tipo).join(', ')}) con id y día de hoy`);
    comprobar(JSON.stringify(reg[0] && reg[0].p_datos) === JSON.stringify({ ejercicio: 'Remo con barra', kg: 52.5, reps: 8, antes_kg: 50, antes_reps: 8 }), `datos del récord: ${JSON.stringify(reg[0] && reg[0].p_datos)}`);
    await capturar(`web-festejo-con-permiso-${tema}`, '.wn-festejo .wn-caja');
    await clic('[data-test="wins-seguir"]');
    await sleep(400);
    comprobar(!(await hay('.wn-capa')), '«Seguir» cierra el festejo');
  }

  // ── 3. Con el permiso ya dado: la cola con reintento ──
  console.log('\n▸ cola local con reintento');
  reiniciar({ config: { wins_app: true }, permiso: true });
  await limpiar(); await abrir(Q);
  D.cortar.add('mypump_wins_registrar');
  await cerrarConRecords();
  comprobar((await hay('[data-test="wins-con-permiso"]')) && !(await hay('[data-test="wins-contarle"]')), 'festejo con la línea, sin botón de permiso');
  await sleep(600);
  const enCola = await evaluar('window.Wins.cola.map((x) => x.id)');
  comprobar(enCola.length === 2 && D.filas.length === 0, `sin red: los 2 quedan en la cola local (${enCola.length})`);
  comprobar(await evaluar('Object.keys(localStorage).some((k) => k.startsWith("mypump-wins-") && JSON.parse(localStorage.getItem(k)).cola.length === 2)'), 'y en el disco de este navegador');
  await clic('[data-test="wins-seguir"]');
  D.cortar.clear();
  await evaluar('(document.dispatchEvent(new Event("visibilitychange")), true)');
  await esperar('window.Wins.cola.length === 0', 6000);
  comprobar(D.filas.length === 2 && D.filas.every((f) => enCola.includes(f.p_id)), 'al volver al frente salen los 2, con los mismos id');
  // Al abrir de nuevo: lo que quedó en disco sale después de leer el estado.
  D.cortar.add('mypump_wins_registrar'); D.filas = [];
  await evaluar('(window.Wins.encolar({ tipo: "record_kg", clave: "remo con barra", dia: hoyLocal(), datos: { ejercicio: "Remo con barra", kg: 55, reps: 8, antes_kg: 52.5, antes_reps: 8 } }), true)');
  await sleep(500);
  D.cortar.clear();
  await abrir(Q);
  await esperar('window.Wins.cola.length === 0', 6000);
  comprobar(D.filas.length === 1 && D.filas[0].p_datos.kg === 55, 'al abrir la app sale lo que había quedado');
  // La función desaparece (PGRST202): se vacía la cola y no se festeja.
  reiniciar({ config: { wins_app: true }, permiso: true }); D.sinFuncion.add('mypump_wins_estado'); D.sinFuncion.add('mypump_wins_registrar');
  await limpiar(); await abrir(Q);
  await cerrarConRecords();
  comprobar(!(await hay('.wn-capa')) && (await evaluar('window.Wins.cola.length')) === 0, 'sin la función del servidor (PGRST202): ni festejo ni cola, y nada se rompe');

  // ── 4. Mis datos → Logros ──
  for (const tema of ['light', 'dark']) {
    console.log(`\n▸ Mis datos → Logros (${tema})`);
    reiniciar({ config: { wins_app: true }, permiso: true });
    await limpiar(); await abrir(Q, tema);
    await evaluar('(setScene("revision"), true)');
    await clic('#misDatosBtn');
    await sleep(400);
    comprobar((await texto('[data-test="wins-ajuste"]')) === F.ajuste_seccion && (await texto('.md-wins-fila > span')) === F.ajuste_interruptor, `sección «${await texto('[data-test="wins-ajuste"]')}» con «${await texto('.md-wins-fila > span')}»`);
    comprobar(await evaluar(`[...document.querySelectorAll('.md-pie')].some((p) => p.textContent === ${JSON.stringify(F.ajuste_pie)})`), 'el pie del ajuste');
    comprobar(await evaluar('document.querySelector("#mdWins").checked'), 'prendido (tiene el permiso dado)');
    await evaluar('(document.querySelector(".md-wins-fila").scrollIntoView({ block: "center" }), true)');
    await capturar(`web-ajuste-${tema}`, '#scene-misdatos');
    if (tema === 'dark') continue;
    // Apagar sin red: avisa y vuelve a como estaba.
    D.cortar.add('mypump_wins_permiso');
    await clic('#mdWins');
    await esperar('!!document.querySelector("[data-test=wins-ajuste-msg]")', 6000);
    comprobar((await texto('[data-test="wins-ajuste-msg"]')) === F.sin_red && (await evaluar('document.querySelector("#mdWins").checked')) && D.permiso, 'apagar sin red: avisa y el interruptor vuelve a prendido');
    D.cortar.clear();
    // Apagar: revoca.
    await clic('#mdWins');
    await esperar('document.querySelector("#mdWins") && !document.querySelector("#mdWins").checked && !!document.querySelector("[data-test=wins-ajuste-msg]:not(.is-error)")', 6000);
    const rev = de('mypump_wins_permiso').pop();
    comprobar(rev && rev.p_otorga === false && !('p_version' in rev) && !D.permiso, 'apagar: mypump_wins_permiso(token, false)');
    comprobar((await texto('[data-test="wins-ajuste-msg"]')) === F.desactivado, `«${await texto('[data-test="wins-ajuste-msg"]')}»`);
    // Prender: la misma hoja de permiso.
    await clic('#mdWins');
    await sleep(300);
    comprobar((await hay('[data-test="wins-permiso"]')) && !(await evaluar('document.querySelector("#mdWins").checked')), 'prender abre la hoja de permiso y queda apagado hasta confirmar');
    await clic('[data-test="wins-permiso-si"]');
    await esperar('!document.querySelector(".wn-permiso") && document.querySelector("#mdWins").checked', 6000);
    comprobar(D.permiso && (await evaluar('document.querySelector("#mdWins").checked')), '«Sí, compartir»: queda prendido');
  }
  // Palanca apagada con el permiso dado de antes: el interruptor se sigue viendo, para apagarlo.
  reiniciar({ config: { wins_app: true }, permiso: true });
  await limpiar(); await abrir(Q);
  D.config = {}; D.llamadas.length = 0;
  await abrir(Q);
  await evaluar('(setScene("misdatos"), renderMisDatos(), true)');
  comprobar((await hay('#mdWins')) && de('mypump_wins_estado').length === 0, 'palanca apagada y permiso dado: el interruptor se ve, sin llamar a nada');
  await clic('#mdWins');
  await esperar('!!document.querySelector("[data-test=wins-ajuste-msg]")', 6000);
  comprobar(de('mypump_wins_permiso').length === 1 && de('mypump_wins_permiso')[0].p_otorga === false, 'y apagarlo revoca');

  // ── 5. La racha de pasos en la celebración del Pump del día ──
  console.log('\n▸ racha de pasos');
  reiniciar({ config: { wins_app: true, metas_pasos: true }, permiso: true, metaPasos: 9000, pasos: [9500, 9800, 10200, 9100, 9900, 11000, 9300] });
  await limpiar(); await abrir(Q);
  await esperar('!!document.querySelector("[data-test=pump-celebracion]")', 9000);
  comprobar((await texto('[data-test="pump-racha-wins"]')) === F.racha_con_permiso, `racha de 7 con permiso: «${await texto('[data-test="pump-racha-wins"]')}»`);
  await esperar('window.Wins.cola.length === 0', 6000);
  const racha = de('mypump_wins_registrar').find((r) => r.p_tipo === 'racha_pasos');
  comprobar(racha && racha.p_clave === 'pasos' && JSON.stringify(racha.p_datos) === JSON.stringify({ dias: 7, meta: 9000 }), `racha_pasos {dias: 7, meta: 9000}: ${JSON.stringify(racha && racha.p_datos)}`);
  await sleep(1500);
  await capturar('web-pump-racha-light', '.pump-cel .pc-centro');
  reiniciar({ config: { wins_app: true, metas_pasos: true }, permiso: false, metaPasos: 9000, pasos: [9500, 9800, 10200, 9100, 9900, 11000, 9300] });
  await limpiar(); await abrir(Q);
  await esperar('!!document.querySelector("[data-test=pump-celebracion]")', 9000);
  comprobar(!(await hay('[data-test="pump-racha-wins"]')) && !(await hay('.wn-capa')) && de('mypump_wins_registrar').length === 0, 'sin permiso: no se agrega nada ni se pide el permiso ahí');
  reiniciar({ config: { wins_app: true, metas_pasos: true }, permiso: true, metaPasos: 9000, pasos: [9800, 10200, 9100, 9900, 11000, 9300] });
  await limpiar(); await abrir(Q);
  await esperar('!!document.querySelector("[data-test=pump-celebracion]")', 9000);
  comprobar(!(await hay('[data-test="pump-racha-wins"]')) && de('mypump_wins_registrar').length === 0, 'una racha de 6 no es un hito: nada');

  // ── 6. La lista previa, sola ──
  for (const tema of ['light', 'dark']) {
    console.log(`\n▸ lista previa sola (${tema})`);
    reiniciar({ config: { lista_previa: true } });
    await limpiar(); await abrir(Q, tema);
    await esperar('!!document.querySelector("#listaPreviaHost [data-test=lista-previa]")', 8000);
    comprobar(await evaluar('document.querySelector("#scene-train").firstElementChild.id === "listaPreviaHost" && !!document.querySelector("#listaPreviaHost .lp-sola")'), 'tarjeta propia, arriba de todo en Entreno');
    comprobar((await texto('.lp-titulo')) === VL.textos.titulo && (await texto('[data-test="lista-previa-resumen"]')) === 'Llevás 1 de 3' && (await texto('.lp-consejo')) === VL.textos.consejo, `«${await texto('.lp-titulo')}» · «${await texto('[data-test="lista-previa-resumen"]')}»`);
    const filas = await evaluar('[...document.querySelectorAll(".lp-fila")].map((f) => [f.tagName, f.getAttribute("aria-label"), f.querySelector(".lp-tit").textContent, (f.querySelector(".lp-det") || {}).textContent || null])');
    const esperadas = VL.casos[0].salida.items.map((i) => [i.destino ? 'BUTTON' : 'DIV', i.accesible, i.titulo, i.detalle]);
    comprobar(JSON.stringify(filas) === JSON.stringify(esperadas), 'las 4 filas del vector, con botón solo donde hay destino y su etiqueta accesible');
    comprobar(await evaluar('[...document.querySelectorAll(".lp-boton")].every((b) => b.getBoundingClientRect().height >= 48)'), 'filas-botón de 48 px o más');
    comprobar(de('mypump_lista_previa').length === 1, 'un solo pedido de la lista');
    await capturar(`web-lista-previa-sola-${tema}`, '#listaPreviaHost');
    if (tema === 'dark') continue;
    await clic('[data-test="lista-previa-fotos"]');
    await sleep(400);
    comprobar((await evaluar('STATE.scene')) === 'revision' && (await hay('#myday-fotos')), 'la fila de las fotos lleva directo a Revisión, a las fotos');
    await evaluar('(setScene("train"), true)');
    await clic('[data-test="lista-previa-guia"]');
    await esperar('window.MyPumpGuia.abierta()', 5000);
    comprobar(await evaluar('window.MyPumpGuia.abierta()'), 'la fila de la guía abre la guía');
    await evaluar('(window.MyPumpGuia.cerrar(), true)');
  }

  // ── 7. La lista previa, dentro de la tarjeta de la videollamada ──
  for (const tema of ['light', 'dark']) {
    console.log(`\n▸ lista previa en la tarjeta (${tema})`);
    reiniciar({ config: { lista_previa: true }, reserva: reservaDe('comienzo') });
    await limpiar(); await abrir(Q, tema);
    await esperar('!!document.querySelector(".vl-tarjeta [data-test=lista-previa]")', 8000);
    comprobar((await hay('.vl-tarjeta .lp-dentro')) && !(await hay('#listaPreviaHost [data-test="lista-previa"]')), 'con la videollamada de comienzo: la lista va dentro de la tarjeta, y no hay tarjeta suelta');
    comprobar(await evaluar('(() => { const t = document.querySelector(".vl-tarjeta"); return t.lastElementChild.matches(".lp-lista") && !!t.querySelector(".vl-entrar-zona") && (t.querySelector(".vl-entrar-zona").compareDocumentPosition(t.querySelector(".lp-lista")) & 4) > 0; })()'), 'debajo de lo que ya tiene («Entrar» no se mueve)');
    await evaluar('(document.querySelector(".vl-tarjeta .lp-lista").scrollIntoView({ block: "end" }), scrollBy(0, 110), true)');
    await sleep(200);
    await capturar(`web-lista-previa-en-tarjeta-${tema}`, '#guiaHost .vl-tarjeta');
  }
  reiniciar({ config: { lista_previa: true }, reserva: reservaDe('revision') });
  await limpiar(); await abrir(Q);
  await esperar('!!document.querySelector(".vl-tarjeta")', 8000);
  await sleep(600);
  comprobar((await hay('.vl-tarjeta')) && !(await hay('[data-test="lista-previa"]')), 'con una videollamada de revisión: no se muestra');
  reiniciar({ config: { lista_previa: true } }); D.sinFuncion.add('mypump_lista_previa');
  await limpiar(); await abrir(Q);
  comprobar(!(await hay('[data-test="lista-previa"]')) && de('mypump_lista_previa').length === 1, 'sin la función (PGRST202): nada, y la página sigue');
  reiniciar({ config: { lista_previa: true } }); D.cortar.add('mypump_lista_previa');
  await limpiar(); await abrir(Q);
  comprobar(!(await hay('[data-test="lista-previa"]')) && (await hay('#scene-train .block')), 'sin red en la lista: nada, y Entreno sigue');
  reiniciar({ config: { lista_previa: true }, lista: { ok: true, activa: false, items: [] } });
  await limpiar(); await abrir(Q);
  comprobar(!(await hay('[data-test="lista-previa"]')), 'inactiva (la videollamada ya pasó): nada');

  // ── 8. La demo sin cuenta, con historia ──
  for (const tema of ['light', 'dark']) {
    console.log(`\n▸ demo con historia (${tema})`);
    reiniciar();
    await limpiar(); pedidosDemo.length = 0;
    await abrir('demo=1', tema);
    comprobar(pedidosDemo.includes('/demo/historial.json'), 'la historia sale del archivo que viaja con la app');
    comprobar(await hay('.demo-banner'), 'el cartel de la demo sigue');
    comprobar((await hay('#listaPreviaHost .lp-sola')) && (await texto('[data-test="lista-previa-resumen"]')) === 'Llevás 1 de 3', 'lista previa de ejemplo, como tarjeta propia');
    comprobar(await evaluar('document.querySelector("[data-test=lista-previa-guia]").tagName === "DIV" && document.querySelector("[data-test=lista-previa-fotos]").tagName === "BUTTON"'), 'en la demo la guía no es un botón (no hay guía); las fotos sí');
    comprobar((await texto('#pumpDelDia .pump-num')) === '6.240 de 9.000 pasos' && /días seguidos$/.test(await texto('[data-test="pump-racha"]')), `Pump del día: «${await texto('#pumpDelDia .pump-num')}», «${await texto('[data-test="pump-racha"]')}»`);
    await capturar(`web-demo-entreno-${tema}`);
    await evaluar('(document.querySelector("#pumpDelDia").scrollIntoView({ block: "start" }), scrollBy(0, -80), true)');
    await sleep(200);
    await capturar(`web-demo-pump-del-dia-${tema}`, '#pumpDelDia');
    const hist = await evaluar('[...document.querySelectorAll("#scene-train .ex-head")].filter((e) => e.querySelector(".ex-historic") && !e.querySelector(".chip.warm")).map((e) => e.querySelector(".ex-name").textContent.trim() + " → " + e.querySelector(".ex-historic").textContent.replace(/\\s+/g, " ").trim())');
    const sinHistoria = hist.filter((h) => /Primera vez/.test(h));
    comprobar(hist.some((h) => /Récord: ?\d/.test(h)) && sinHistoria.length === 0, `Entreno con el récord a superar en ${hist.length - sinHistoria.length} de ${hist.length} ejercicios${sinHistoria.length ? ' · sin historia: ' + sinHistoria.join(' | ') : ''}`);
    await evaluar('(setScene("progress"), true)');
    await esperar('document.querySelectorAll("#scene-progress .exer-row").length > 0', 6000);
    const prog = await evaluar('({ filas: document.querySelectorAll("#scene-progress .exer-row").length, records: document.querySelectorAll("#scene-progress .pr-badge").length })');
    comprobar(prog.filas >= 5 && prog.records >= 1, `Progreso: ${prog.filas} ejercicios con historia y ${prog.records} con «Récord»`);
    comprobar((await evaluar('document.querySelectorAll("#scene-progress .vm-card").length')) === 1, 'una sola tarjeta de «Series por músculo»');
    await evaluar('(document.querySelector("#scene-progress .prog-section-title").scrollIntoView({ block: "start" }), scrollBy(0, -110), true)');
    await sleep(200);
    await capturar(`web-demo-progreso-${tema}`);
    await clic('#scene-progress .exer-row');
    await sleep(500);
    comprobar(await hay('#modalHost .modal-sheet'), 'el detalle del ejercicio abre con su historial');
    await capturar(`web-demo-progreso-detalle-${tema}`);
    await evaluar('(closeModal(), true)');

    await evaluar('(setScene("cuerpo"), true)');
    await sleep(500);
    comprobar((await hay('#myday-peso svg')) && /media 7d/.test(await texto('#myday-peso')) && (await hay('[data-test="ritmo-peso"]')), `Peso: gráfico, media de 7 días y el ritmo («${await texto('[data-test="ritmo-peso"] .rp-meta')}»)`);
    await capturar(`web-demo-peso-${tema}`);

    await evaluar('(setScene("chat"), true)');
    await sleep(400);
    const chat = await evaluar('({ n: document.querySelectorAll("#scene-chat .chat-msg").length, autores: [...new Set([...document.querySelectorAll("#scene-chat .ex-com-autor")].map((a) => a.textContent))] })');
    comprobar(chat.n === 10 && chat.autores.includes('Mati') && chat.autores.includes('Vos') && chat.autores.length === 2, `Chat: ${chat.n} mensajes de ${chat.autores.join(' y ')}`);
    await evaluar('(document.querySelector("#scene-chat .chat-msg:last-of-type").scrollIntoView({ block: "end" }), true)');
    await capturar(`web-demo-chat-${tema}`);
    await evaluar('(() => { const i = document.querySelector("#chatInput"); i.value = "hola"; i.dispatchEvent(new Event("input")); document.querySelector("#chatSend").click(); return true; })()');
    await sleep(300);
    comprobar((await evaluar('document.querySelectorAll("#scene-chat .chat-msg").length')) === 10, 'en la demo el mensaje no se envía');

    await evaluar('(setScene("revision"), scrollTo(0, 0), true)');
    await sleep(500);
    comprobar((await texto('#dv-titulo')) === 'Devolución de Mati' && /^Semana del \d+ de /.test(await texto('.dv-titulos p')) && (await evaluar('document.querySelectorAll(".dv-anterior").length')) === 2, `Devolución de Mati: «${await texto('.dv-titulos p')}» y 2 semanas anteriores`);
    await capturar(`web-demo-devolucion-${tema}`);

    if (tema === 'light') {
      // Hoy no hay sesión: si carga más kg, ve el festejo; «Contarle a Mati» no manda nada.
      await evaluar('(setScene("train"), true)');
      await evaluar(`(() => { const ex = DATA.dia.bloques.flatMap((b) => b.ejercicios).find((e) => e.nombre === 'Remo con barra');
        const tope = Math.max(...DATA.historico_por_ejercicio[ex.id].map((r) => r.peso_kg));
        Object.assign(STATE.session[ex.id].sets[0], { kg: String(tope + 2.5), reps: '8', confirmed: true }); renderTrain(); return true; })()`);
      await evaluar('openEarlyFinishModal().then(() => true)');
      await esperar('!!document.querySelector("#finConfirm")');
      await clic('#finConfirm');
      await esperar('!!document.querySelector("[data-test=wins-festejo]")', 5000);
      comprobar((await texto('#wnTit')) === 'Récord nuevo' && (await texto('.wn-chip')) === '+2,5 kg', `demo: festejo «${await texto('#wnTit')}» ${await texto('.wn-chip')}`);
      await clic('[data-test="wins-contarle"]');
      await sleep(250);
      comprobar((await texto('[data-test="wins-demo"]')) === F.demo && !(await hay('.wn-permiso')), `«Contarle a Mati» en la demo: «${await texto('[data-test="wins-demo"]')}»`);
      await capturar('web-demo-festejo-light', '.wn-festejo .wn-caja');
      await clic('[data-test="wins-seguir"]');
    }
    comprobar(D.llamadas.length === 0, `la demo no llama al servidor (${D.llamadas.map((l) => l.fn).join(', ') || 'cero llamadas'})`);
    comprobar(await evaluar('!Object.keys(localStorage).some((k) => /^mypump-wins-|^mypump_outbox/.test(k) && /cola|\\[\\{/.test(localStorage.getItem(k)) && JSON.stringify(localStorage.getItem(k)).includes("record"))'), 'y no deja nada en cola');
  }

  // ── 8 bis. Una cuenta REAL sin rutina publicada (ve el plan de ejemplo): lista previa y Logros sí; historia inventada no ──
  console.log('\n▸ cuenta real sin rutina publicada');
  reiniciar({ config: { wins_app: true, lista_previa: true }, permiso: true, sinRutina: true });
  await limpiar(); pedidosDemo.length = 0; await abrir(Q);
  comprobar(await evaluar('DATA._isDemo === true && !DEMO'), 'cae al plan de ejemplo (sin ser la demo sin cuenta)');
  await esperar('!!document.querySelector("#listaPreviaHost [data-test=lista-previa]")', 8000);
  comprobar((await hay('#listaPreviaHost .lp-sola')) && de('mypump_lista_previa').length === 1, 've la lista previa (pedida al servidor con su token)');
  comprobar(de('mypump_wins_estado').length === 1, 'y se lee el estado de sus logros');
  comprobar(!pedidosDemo.includes('/demo/historial.json') && (await evaluar('_demoHist === null && STATE.chat.msgs.length === 0 && !(STATE.salud || []).length')), 'no ve la historia inventada de la demo (ni chat, ni peso, ni pasos)');
  comprobar(!(await evaluar('[...document.querySelectorAll("#scene-train .ex-historic")].some((e) => /Récord/.test(e.textContent))')), 'ni récords inventados en Entreno');
  await clic('[data-test="lista-previa-guia"]');
  await sleep(800);
  console.log('  la fila de la guía abre la guía: ' + await evaluar('!!(window.MyPumpGuia && window.MyPumpGuia.abierta())'));
  await evaluar('(window.MyPumpGuia && window.MyPumpGuia.cerrar && window.MyPumpGuia.cerrar(), true)');
  await evaluar('(setScene("misdatos"), renderMisDatos(), true)');
  comprobar((await hay('#mdWins')) && (await evaluar('document.querySelector("#mdWins").checked')), 'Mis datos: el interruptor de Logros se ve, prendido');
  await clic('#mdWins');
  await esperar('!!document.querySelector("[data-test=wins-ajuste-msg]:not(.is-error)")', 6000);
  comprobar(!D.permiso && (await hay('#mdWins')) && (await texto('[data-test="wins-ajuste-msg"]')) === F.desactivado, 'lo apaga, y la sección sigue a la vista con «' + F.desactivado + '»');
  await evaluar('(setScene("train"), true)');
  await cerrarConRecords().catch(() => {});
  comprobar(!(await hay('.wn-capa')), 'con el plan de ejemplo no hay festejo');

  // ── 8 ter. La demo con una cuenta guardada en este navegador: no manda ni trae nada de esa cuenta ──
  console.log('\n▸ demo con un token guardado');
  reiniciar({ config: { wins_app: true, lista_previa: true }, permiso: true });
  await limpiar(); await evaluar(`(localStorage.setItem('mypump_token', ${JSON.stringify(TOKEN)}), true)`);
  await cmd('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] });
  await cmd('Page.navigate', { url: `${BASE}/cliente.html?demo=1` });
  await esperar('typeof DATA !== "undefined" && !!DATA && !!document.querySelector("#scene-train .block")', 15000);
  await sleep(1200);
  await evaluar('(setScene("revision"), true)'); await sleep(600);
  const res = await evaluar('_subirFoto("frente", "data:image/jpeg;base64,AAAA", hoyLocal())');
  comprobar(res && res.ok === false && res.fatal === true, 'subir una foto en la demo no manda nada');
  comprobar(nuevas().length === 0 && !D.llamadas.some((l) => /salud|checkin|foto|chat|habito/.test(l.fn)), `ni pide logros, lista, salud, check o chat de esa cuenta (${[...new Set(D.llamadas.map((l) => l.fn))].join(', ') || 'cero llamadas'})`);
  await limpiar();

  // ── El foco: entra al festejo, Tab no sale de él, Escape cierra y vuelve ──
  console.log('\n▸ foco y teclado');
  reiniciar({ config: { wins_app: true } });
  await limpiar(); await abrir(Q);
  await cerrarConRecords();
  comprobar(await evaluar('document.activeElement === document.querySelector("[data-test=wins-seguir]")'), 'al abrir, el foco está en «Seguir»');
  const tab = (shift) => cmd('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9, modifiers: shift ? 8 : 0 }).then(() => cmd('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 }));
  const dentro = () => evaluar('!!document.activeElement.closest(".wn-festejo")');
  await tab(); const a1 = await dentro(); await tab(); const a2 = await dentro(); await tab(true); const a3 = await dentro();
  comprobar(a1 && a2 && a3, 'Tab y Mayús+Tab dan la vuelta adentro del festejo');
  await clic('[data-test="wins-contarle"]'); await sleep(300);
  await tab(); await tab(); await tab();
  comprobar(await evaluar('!!document.activeElement.closest(".wn-permiso")'), 'con la hoja de permiso arriba, el foco queda en ella');
  await cmd('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 }); await sleep(200);
  comprobar(!(await hay('.wn-permiso')) && (await hay('.wn-festejo')), 'Escape cierra la hoja de permiso y deja el festejo');
  await cmd('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 }); await sleep(400);
  comprobar(!(await hay('.wn-capa')), 'Escape cierra el festejo');

  // ── 9. Letra grande (el navegador al 200 %) ──
  console.log('\n▸ letra grande (200 %)');
  reiniciar({ config: { wins_app: true, lista_previa: true } });
  await limpiar(); await abrir(Q);
  await letra('200%'); await sleep(300);
  await evaluar('(scrollTo(0, 0), true)');
  console.log('  flecha con letra grande: ' + await evaluar('getComputedStyle(document.querySelector(".lp-flecha")).display'));
  comprobar(await evaluar('[...document.querySelectorAll(".lp-tit")].every((t) => t.getBoundingClientRect().width >= 150)'), 'lista con letra grande: el texto de cada fila tiene 150 px o más de ancho');
  await capturar('web-lista-previa-sola-letra-grande', '#listaPreviaHost');
  await cerrarConRecords();
  comprobar(await botonesALaVista('.wn-festejo .wn-boton'), 'festejo con letra grande: los dos botones siguen a la vista (la lista hace scroll adentro)');
  await capturar('web-festejo-letra-grande', '.wn-festejo .wn-caja');
  await clic('[data-test="wins-contarle"]');
  await sleep(350);
  comprobar(await botonesALaVista('.wn-permiso .wn-boton'), 'permiso con letra grande: «Sí, compartir» y «Ahora no» a la vista');
  await capturar('web-permiso-letra-grande', '.wn-permiso .wn-caja');
  await clic('[data-test="wins-permiso-si"]');
  await esperar('!!document.querySelector("[data-test=wins-con-permiso]")', 6000);
  await clic('[data-test="wins-seguir"]');
  await sleep(300);
  // Mis datos está en px (como el resto de la app vieja): ahí la letra grande es el ajuste de texto del teléfono.
  await letra('');
  await evaluar('(setScene("misdatos"), renderMisDatos(), document.documentElement.style.textSizeAdjust = "200%", document.documentElement.style.webkitTextSizeAdjust = "200%", true)');
  await sleep(300);
  await evaluar('(document.querySelector(".md-wins-fila").scrollIntoView({ block: "center" }), true)');
  console.log('  tamaño de la letra del interruptor: ' + await evaluar('getComputedStyle(document.querySelector(".md-wins-fila > span")).fontSize + " / alto " + Math.round(document.querySelector(".md-wins-fila > span").getBoundingClientRect().height)'));
  await capturar('web-ajuste-letra-grande', '#scene-misdatos');
  await evaluar('(document.documentElement.style.textSizeAdjust = "", document.documentElement.style.webkitTextSizeAdjust = "", true)');
  reiniciar({ config: { lista_previa: true }, reserva: reservaDe('comienzo') });
  await limpiar(); await abrir(Q);
  await esperar('!!document.querySelector(".vl-tarjeta [data-test=lista-previa]")', 8000);
  await letra('200%'); await sleep(300);
  await evaluar('(document.querySelector(".vl-tarjeta .lp-lista").scrollIntoView({ block: "start" }), scrollBy(0, -70), true)');
  comprobar(await evaluar('[...document.querySelectorAll(".vl-tarjeta .lp-tit")].every((t) => t.getBoundingClientRect().width >= 150)'), 'lista en la tarjeta con letra grande: el texto de cada fila tiene 150 px o más de ancho');
  await capturar('web-lista-previa-en-tarjeta-letra-grande', '#guiaHost .vl-tarjeta');
  await letra('');

  comprobar(erroresPagina.length === 0, `sin errores de JavaScript en la página${erroresPagina.length ? ': ' + erroresPagina.slice(0, 3).join(' | ') : ''}`);
} catch (e) {
  fallas++;
  console.error('\n✗ la prueba se cortó:', e && e.stack || e);
} finally {
  try { ws && ws.close(); } catch { /* ya cerrado */ }
  chrome.kill();
  servidor.close();
  await sleep(300);
  try { rmSync(perfil, { recursive: true, force: true }); } catch { /* el perfil temporal */ }
}
console.log(fallas ? `\n✗ ${fallas} de ${hechas} comprobaciones fallaron` : `\n✓ capturas-cola-a: ${hechas} comprobaciones OK`);
process.exit(fallas ? 1 : 0);
