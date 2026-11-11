#!/usr/bin/env node
/* =============================================================
 * test-estudios.mjs — «Estudios y órdenes» de la web: las reglas con los MISMOS
 * vectores de iOS y Android (scripts/vectores-app/estudios.json, copia exacta de
 * apps/shared/vectores/estudios.json), la cola de subida contra un doble del
 * servidor (estudios/CONTRATO_APP.md) y lo que no puede pasar con datos médicos:
 * nada al service worker, nada a localStorage, el token nunca en una URL.
 * No toca la red. Nombres y datos inventados.
 * USO:  node scripts/test-estudios.mjs
 * ============================================================= */
import fs from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const E = require('../public/js/estudios.js');
const { ModeloEstudios, MAX_VUELTAS, urlSegura } = require('../public/js/estudios-cola.js');
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/estudios.json', import.meta.url), 'utf8'));
const T = E.T;

const TOK = 'token-de-prueba-0123456789';
let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }
const hasta = async (f) => { for (let i = 0; i < 400 && !f(); i++) await new Promise((r) => setTimeout(r, 1)); assert.ok(f(), 'no se cumplió: ' + f); };

// ── Reglas, con los vectores de la app ──
await caso('constantes y textos', () => {
  assert.equal(E.MAX_PX, V.maxPx); assert.equal(E.CALIDAD, V.calidad); assert.equal(E.TOPE_ARCHIVOS, V.topeArchivos); assert.equal(E.TOPE_MB, V.topeMB);
  for (const [k, v] of Object.entries(V.textos)) assert.equal(T[k], v, k);
  for (const c of V.subtituloEntrada) assert.equal(T.subtituloEntrada(c.n), c.texto);
  for (const c of V.enviarArchivos) assert.equal(T.enviarArchivos(c.n), c.texto);
  for (const c of V.hojas) assert.equal(E.hojas(c.n), c.texto);
  assert.equal(T.topeArchivos(V.topeArchivos), V.topes.archivos); assert.equal(T.archivoMuyGrande(V.topeMB), V.topes.peso);
  for (const c of V.progreso) assert.equal(E.progreso(c.subidos, c.total), c.texto);
});
await caso('fechas', () => {
  for (const c of V.fechas) { const d = E.dia(c.fecha); assert.equal(d ? E.corta(d) : null, c.corta, c.fecha); assert.equal(d ? E.conDia(d) : null, c.conDia, c.fecha); }
  for (const c of V.fechaPendiente) {
    const r = E.fechaPendiente(E.dia(c.desde), E.dia(c.hasta), E.dia(c.hoy));
    assert.equal(r ? r.texto : null, c.texto, JSON.stringify(c)); if (r) assert.equal(r.pasada, c.pasada, JSON.stringify(c));
  }
  for (const c of V.fechaControl) assert.equal(E.fechaControl(E.dia(c.desde), E.dia(c.hasta)), c.texto, JSON.stringify(c));
  for (const c of V.hecho) assert.equal(E.hecho(E.dia(c.fecha)), c.texto);
  for (const c of V.orden) assert.equal(E.detalleOrden({ emitida: E.dia(c.emitida), vence: E.dia(c.vence) }), c.texto);
  for (const c of V.estudio) assert.equal(E.detalleEstudio({ fecha: E.dia(c.fecha), hojas: c.hojas }), c.texto);
  for (const c of V.envio) assert.equal(E.lineaEnvio({ enviado: E.diaDeInstante(c.enviado_en, c.zona), archivos: c.archivos }), c.texto);
  assert.equal(E.iso(E.dia('2026-01-02T10:00:00Z')), '2026-01-02');
});
await caso('preparación y dónde: textos fijos por tipo', () => {
  for (const [tipo, l] of Object.entries(V.preparacion)) assert.deepEqual(E.preparacion(tipo), l, tipo);
  for (const [tipo, l] of Object.entries(V.donde)) assert.deepEqual(E.donde(tipo), l, tipo);
  assert.deepEqual(E.preparacion(null), V.preparacion.tipo_que_no_existe);
  assert.deepEqual(E.preparacion('constructor'), V.preparacion.tipo_que_no_existe);
});
await caso('subida: clasificación y formato', () => {
  for (const c of V.subida) assert.equal(E.clasificarSubida(c.status, c.ok), c.accion, JSON.stringify(c));
  assert.equal(E.formato(new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31])), 'pdf');
  assert.equal(E.formato(new Uint8Array([0xff, 0xd8, 0xff, 0xe0])), 'jpeg');
  assert.equal(E.formato(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d])), null);
  assert.equal(E.formato(new Uint8Array([0x25, 0x50, 0x44, 0x46])), null);
  assert.equal(E.puedeAgregar({ bytes: 10, formato: 'pdf', yaHay: 20 }), 'tope');
  assert.equal(E.puedeAgregar({ bytes: 20 * 1024 * 1024 + 1, formato: 'pdf', yaHay: 0 }), 'muyGrande');
  assert.equal(E.puedeAgregar({ bytes: 20 * 1024 * 1024, formato: 'pdf', yaHay: 0 }), 'ok');
  assert.equal(E.puedeAgregar({ bytes: 10, formato: null, yaHay: 0 }), 'ilegible');
  assert.equal(E.puedeAgregar({ bytes: 0, formato: 'jpeg', yaHay: 0 }), 'ilegible');
});
await caso('get: campos opcionales, estados desconocidos y lo que no se muestra', () => {
  const e = E.decodificarEstado(V.get.respuesta, 'America/Argentina/Buenos_Aires'), x = V.get.espera;
  assert.equal(e.pendientes.length, x.pendientes); assert.equal(e.pendientes.filter((p) => p.hecho).length, x.pendientesHechos);
  assert.equal(e.ordenes.length, x.ordenes); assert.equal(e.ordenes.filter((o) => o.vigente).length, x.ordenesVigentes);
  assert.equal(e.estudios.length, x.estudios); assert.equal(e.estudios.filter((s) => s.visto).length, x.estudiosVistos);
  assert.equal(e.estudios.filter((s) => s.sePuedeAbrir).length, x.estudiosQueSeAbren);
  assert.equal(E.enviosVisibles(e).length, x.enviosVisibles);
  assert.equal(T.subtituloEntrada(e.pendientes.length), x.subtitulo);
  assert.equal(e.estudios[2].titulo, x.tituloSinTitulo);
  assert.deepEqual(E.bloques(e), x.bloques);
  for (const j of V.get.noHabilitado) assert.equal(E.decodificarEstado(j), null, JSON.stringify(j));
  const v = E.decodificarEstado(V.get.vacia);
  assert.equal(E.bloques(v).vacio, true); assert.equal(v.topeArchivos, 20); assert.equal(v.topeMB, 20);
});
await caso('«Mati lo vio» sale solo del estado del servidor', () => {
  const e = E.decodificarEstado({ habilitado: true, estudios: [
    { id: 'a', estado: 'recibido', visto: true, visto_en: '2026-11-01', se_puede_abrir: true },
    { id: 'b', estado: 'visto' }, { estado: 'visto', se_puede_abrir: true }] });
  assert.deepEqual(e.estudios.map((s) => s.visto), [false, true, true]);
  assert.deepEqual(e.estudios.map((s) => s.sePuedeAbrir), [true, false, false]);   // sin id no se abre
});
await caso('ningún texto habla de IA ni de análisis automático', () => {
  const todos = [];
  const junta = (o) => { for (const v of Object.values(o)) todos.push(typeof v === 'function' ? v(2, 3) : v); };
  junta(T);
  for (const t of ['laboratorio', 'ecografia', 'mapa', 'ergometria', 'x']) todos.push(...E.preparacion(t), ...E.donde(t));
  for (const t of todos) assert.ok(!/\bIA\b|inteligencia artificial|autom[aá]tic|algoritmo|\bbot\b/i.test(t), t);
});

// ── El doble del servidor ──
const pdf = (n = 100, sal = 0) => { const b = new Uint8Array(n); b.set([0x25, 0x50, 0x44, 0x46, 0x2d]); b[n - 1] = sal; return new Blob([b], { type: 'application/pdf' }); };
const jpg = (n = 100, sal = 0) => { const b = new Uint8Array(n); b.set([0xff, 0xd8, 0xff, 0xe0]); b[n - 1] = sal; return new Blob([b], { type: 'image/jpeg' }); };
const PEDIDO = '00000001-0000-4000-8000-000000000000';

function doble(ini = {}) {
  const d = {
    habilitado: true, sinRed: false, sinFuncion: false, tokenCaido: false, transitorio: false, llamadas: [], envios: new Map(), subidas: [], urls: [],
    proximasSubida: [], proximasNuevo: [], proximasEnviar: [], hechos: [], pendientes: [{ id: PEDIDO, tipo: 'laboratorio', titulo: 'Análisis de laboratorio', hasta: '2026-11-19', estado: 'pedido' }],
    estudios: [], urlsRespuesta: null, ...ini,
  };
  const vista = () => ({
    habilitado: true, hoy: '2026-11-10', topes: { archivos_por_envio: 20, mb_por_archivo: 20 }, pendientes: d.pendientes, ordenes: [], estudios: d.estudios,
    envios: [...d.envios.values()].map((e) => ({ id: e.id, estado: e.estado, archivos: e.archivos.size, pedido_id: e.pedido, enviado_en: e.estado === 'enviado' ? '2026-11-10T12:00:00Z' : null })),
  });
  d.rpc = async (fn, p) => {
    d.llamadas.push(fn);
    assert.equal(p.p_token, TOK);
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.transitorio) return { ok: false, status: 503, codigo: '503', clase: 'transitorio' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    if (d.tokenCaido) return { ok: true, data: null };
    switch (fn) {
      case 'mypump_estudios_get': return { ok: true, data: d.habilitado ? vista() : { habilitado: false } };
      case 'mypump_estudios_envio_nuevo': {
        if (d.proximasNuevo.length) return { ok: true, data: d.proximasNuevo.shift() };
        const ya = d.envios.get(p.p_id);
        if (ya) return { ok: true, data: { ok: true, ya: true, id: ya.id, estado: ya.estado } };
        d.envios.set(p.p_id, { id: p.p_id, estado: 'borrador', pedido: p.p_pedido_id, archivos: new Map() });
        return { ok: true, data: { ok: true, ya: false, id: p.p_id, estado: 'borrador' } };
      }
      case 'mypump_estudios_enviar': {
        if (d.proximasEnviar.length) return { ok: true, data: d.proximasEnviar.shift() };
        const e = d.envios.get(p.p_id);
        if (!e) return { ok: true, data: { ok: false, error: 'no_encontrado' } };
        if (e.estado === 'enviado') return { ok: true, data: { ok: true, ya: true, estado: 'enviado' } };
        if (!e.archivos.size) return { ok: true, data: { ok: false, error: 'sin_archivos' } };
        if (e.archivos.size < p.p_archivos) return { ok: true, data: { ok: false, error: 'faltan_archivos' } };
        e.estado = 'enviado'; e.dijo = p.p_archivos;
        return { ok: true, data: { ok: true, ya: false, estado: 'enviado' } };
      }
      case 'mypump_estudios_hecho': {
        d.hechos.push([p.p_pedido_id, p.p_fecha]);
        const q = d.pendientes.find((x) => x.id === p.p_pedido_id);
        if (!q) return { ok: true, data: { ok: false, error: 'no_encontrado' } };
        if (p.p_fecha && p.p_fecha > '2026-11-10') return { ok: true, data: { ok: false, error: 'fecha' } };
        q.estado = p.p_fecha ? 'hecho' : 'pedido'; q.hecho_fecha = p.p_fecha;
        return { ok: true, data: { ok: true, estado: q.estado } };
      }
      default: throw new Error('RPC inesperada: ' + fn);
    }
  };
  d.subir = async (q) => {
    d.subidas.push({ envio: q.envio, archivo: q.archivo, mime: q.mime, bytes: q.cuerpo.size, token: q.token, url: q.url });
    if (d.sinRed) return null;
    const s = d.proximasSubida.length ? d.proximasSubida.shift() : 200;
    if (s === 0) return null;
    if (s === 401 && d.caeAl401) d.tokenCaido = true;      // el link se regeneró: el `get` que sigue ya no lo reconoce
    if (s !== 200) return { status: s, json: { ok: false, error: 'forzado' } };
    if (q.token !== TOK) return { status: 401, json: { ok: false } };
    const e = d.envios.get(q.envio);
    if (!e) return { status: 404, json: { ok: false } };
    if (e.estado !== 'borrador') return { status: 409, json: { ok: false } };
    if (e.archivos.has(q.archivo)) return { status: 200, json: { ok: true, ya: true } };
    e.archivos.set(q.archivo, q.cuerpo.size);
    return { status: 200, json: { ok: true } };
  };
  d.fetch = async (url, op) => {
    d.urls.push({ url, op });
    const [status, json] = d.urlsRespuesta || [200, { ok: true, archivos: [{ url: 'https://firmado.ejemplo.test/a.pdf?sig=x', mime: 'application/pdf' }], expira_en: 600 }];
    if (status === 0) throw new Error('sin red');
    return { status, json: async () => json };
  };
  return d;
}

async function modelo(d) {
  let n = 0;
  const esperas = [];
  const m = new ModeloEstudios({
    rpc: d.rpc, subir: d.subir, fetch: d.fetch, token: TOK, visionUrl: 'https://vision.ejemplo.test/', zona: 'America/Argentina/Buenos_Aires',
    nuevoId: () => `aaaaaaaa-0000-4000-8000-${String(++n).padStart(12, '0')}`,
    // Las esperas cortas pasan en el acto; la pasada sola del minuto no corre: la dispara cada prueba.
    esperar: (s) => { esperas.push(s); return s >= 60 ? new Promise(() => {}) : Promise.resolve(); },
  });
  m.esperas = esperas;
  await m.refrescar();
  return m;
}
const destrabar = (m) => { m._reintento = false; };
async function conArchivos(m, n = 3) {
  for (let i = 0; i < n; i++) assert.equal(await m.elegir(i % 2 ? pdf(100, i + 1) : jpg(100, i + 1), i % 2 ? 'pdf' : 'jpeg'), 'ok');
}
const cuenta = (d, fn) => d.llamadas.filter((x) => x === fn).length;

// ── Palanca y habilitación ──
await caso('no habilitado, sin la función o token caído: la sección no existe', async () => {
  for (const ini of [{ habilitado: false }, { sinFuncion: true }, { tokenCaido: true }]) {
    const m = await modelo(doble(ini));
    assert.equal(m.estado, null); assert.equal(m.habilitado, false); assert.equal(m.errorDeCarga, false); assert.equal(m.sinRespuesta, false);
  }
});
await caso('sin red: al arrancar no se ve nada; después se queda con lo que había y avisa', async () => {
  const d = doble({ sinRed: true });
  const m = await modelo(d);
  assert.equal(m.estado, null); assert.equal(m.errorDeCarga, false); assert.equal(m.sinRespuesta, true);
  d.sinRed = false; await m.refrescar();
  assert.equal(m.pendientes, 1); assert.equal(m.errorDeCarga, false); assert.equal(m.sinRespuesta, false);
  d.sinRed = true; await m.refrescar();
  assert.equal(m.pendientes, 1); assert.equal(m.errorDeCarga, true);
  d.sinRed = false; d.habilitado = false; await m.refrescar();
  assert.equal(m.estado, null); assert.equal(m.errorDeCarga, false);
});

// ── La hoja de subida ──
await caso('elegir: topes, repetidos y la hoja que se cerró', async () => {
  const m = await modelo(doble());
  assert.equal(await m.elegir(pdf(), 'pdf'), 'ok');
  assert.equal(await m.elegir(pdf(), 'pdf'), 'ok');                       // los mismos bytes: no suma
  assert.equal(m.borrador.length, 1);
  assert.equal(await m.elegir(new Blob([new Uint8Array(10)]), null), 'ilegible');
  assert.equal(await m.elegir(new Blob([]), 'jpeg'), 'ilegible');
  assert.equal(await m.elegir({ size: 20 * 1024 * 1024 + 1 }, 'pdf'), 'muyGrande');
  for (let i = 0; i < 19; i++) assert.equal(await m.elegir(jpg(50, i + 1), 'jpeg'), 'ok');
  assert.equal(m.borrador.length, 20); assert.equal(m.puedeAgregar, false);
  assert.equal(await m.elegir(jpg(50, 99), 'jpeg'), 'tope');
  assert.equal(new Set(m.borrador.map((x) => x.id)).size, 20);
  const id = m.borrador[0].id; m.quitar(id);
  assert.equal(m.borrador.length, 19); assert.ok(!m.borrador.some((x) => x.id === id));
  const tarde = m.elegir(jpg(50, 77), 'jpeg');
  m.descartarBorrador();
  assert.equal(await tarde, 'ok'); assert.equal(m.borrador.length, 0);    // lo que llegó tarde no entra en la hoja siguiente
});

// ── La cola ──
await caso('envío completo: envio_nuevo → un upload por archivo → enviar con la cantidad', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 3);
  const ids = m.borrador.map((x) => x.id);
  d.llamadas.length = 0;
  assert.equal(m.enviar(PEDIDO), true);
  const envioId = m.cola[0].id;
  await m.drenar();
  assert.deepEqual(d.llamadas, ['mypump_estudios_envio_nuevo', 'mypump_estudios_enviar', 'mypump_estudios_get']);
  assert.deepEqual(d.subidas.map((s) => s.archivo), ids);
  assert.ok(d.subidas.every((s) => s.envio === envioId && s.token === TOK && s.url === 'https://vision.ejemplo.test/estudios/upload'));
  assert.deepEqual(d.subidas.map((s) => s.mime), ['image/jpeg', 'application/pdf', 'image/jpeg']);
  assert.ok(!d.subidas.some((s) => s.url.includes(TOK)));
  const e = d.envios.get(envioId);
  assert.equal(e.estado, 'enviado'); assert.equal(e.dijo, 3); assert.equal(e.pedido, PEDIDO);
  assert.equal(m.cola.length, 0); assert.equal(m.aviso, 'recibido'); assert.equal(m.subiendo, false); assert.equal(m.detenido, false);
  assert.equal(E.enviosVisibles(m.estado).length, 1);
});
await caso('doble toque en «Enviar»: un solo envío', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 2);
  assert.equal(m.enviar(null), true);
  assert.equal(m.enviar(null), false);
  await Promise.all([m.drenar(), m.drenar(), m.drenar()]);
  assert.equal(cuenta(d, 'mypump_estudios_envio_nuevo'), 1); assert.equal(cuenta(d, 'mypump_estudios_enviar'), 1);
  assert.equal(d.envios.size, 1); assert.equal(d.subidas.length, 2);
});
await caso('progreso: «Subiendo 2 de 3» mientras sale', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 3);
  const vistos = [];
  m.alCambiar = () => { if (m.subiendo && m.cola[0] && m.cola[0].abierto) vistos.push(m.progreso); };
  m.enviar(null); await m.drenar();
  for (const t of ['Subiendo 1 de 3', 'Subiendo 2 de 3', 'Subiendo 3 de 3']) assert.ok(vistos.includes(t), t);
});
await caso('401: link caído, no se pierde lo elegido y sale con los mismos ids', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 3);
  m.enviar(null);
  const ids = m.cola[0].archivos.map((a) => a.id), envioId = m.cola[0].id;
  d.proximasSubida = [200, 401];
  d.caeAl401 = true;
  await m.drenar();
  assert.equal(m.estado, null);                         // la sección deja de verse…
  assert.equal(m.cola.length, 1);                       // …pero el envío sigue en memoria, entero
  assert.deepEqual(m.cola[0].archivos.map((a) => a.id), ids);
  assert.ok(m.cola[0].archivos.every((a) => a.cuerpo && a.cuerpo.size === 100));
  assert.deepEqual(m.cola[0].archivos.map((a) => a.subido), [true, false, false]);
  assert.equal(m.aviso, null); assert.equal(cuenta(d, 'mypump_estudios_enviar'), 0);
  d.tokenCaido = false;
  await m.refrescar(); await m.reanudar();
  assert.equal(m.cola.length, 0); assert.equal(m.aviso, 'recibido');
  assert.deepEqual(d.subidas.map((s) => s.archivo), [ids[0], ids[1], ids[1], ids[2]]);
  assert.equal(d.envios.get(envioId).dijo, 3); assert.equal(d.envios.size, 1);
});
await caso('4xx de un archivo: definitivo para ese, el resto sigue', async () => {
  for (const s of [400, 411, 413]) {
    const d = doble();
    const m = await modelo(d);
    await conArchivos(m, 3);
    m.enviar(null);
    const ids = m.cola[0].archivos.map((a) => a.id);
    d.proximasSubida = [200, s];
    await m.drenar();
    assert.deepEqual(d.subidas.map((x) => x.archivo), ids, String(s));      // el rechazado no se reintenta
    assert.equal([...d.envios.values()][0].dijo, 2);
    assert.equal(m.aviso, 'recibidoConRechazo'); assert.equal(m.cola.length, 0);
  }
});
await caso('todos rechazados: el envío se descarta sin cerrar y se le dice que pruebe de otra forma', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 2);
  m.enviar(null);
  d.proximasSubida = [400, 413];
  await m.drenar();
  assert.equal(m.aviso, 'rechazado'); assert.equal(m.cola.length, 0); assert.equal(cuenta(d, 'mypump_estudios_enviar'), 0);
});
await caso('429 y 5xx: se reintenta con el mismo id de archivo', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 2);
  m.enviar(null);
  const ids = m.cola[0].archivos.map((a) => a.id);
  d.proximasSubida = [429, 503, 200, 500, 200];
  await m.drenar();
  assert.deepEqual(d.subidas.map((s) => s.archivo), [ids[0], ids[0], ids[0], ids[1], ids[1]]);
  assert.deepEqual(m.esperas, [2, 4, 2]);
  assert.equal(m.aviso, 'recibido'); assert.equal([...d.envios.values()][0].dijo, 2);
});
await caso('tres errores seguidos: corta, queda en la cola y prueba sola más tarde', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 2);
  m.enviar(null);
  const ids = m.cola[0].archivos.map((a) => a.id);
  d.proximasSubida = [500, 500, 500];
  await m.drenar();
  assert.equal(m.cola.length, 1); assert.equal(m.detenido, true); assert.equal(m.sinSenal, false); assert.equal(m.aviso, null);
  assert.ok(m.esperas.includes(60));
  destrabar(m); await m.reanudar();
  assert.equal(m.cola.length, 0); assert.equal(m.aviso, 'recibido');
  assert.deepEqual(d.subidas.map((s) => s.archivo), [ids[0], ids[0], ids[0], ids[0], ids[1]]);
});
await caso('sin señal: no gasta nada, avisa y sale cuando vuelve', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 2);
  m.enviar(null);
  const ids = m.cola[0].archivos.map((a) => a.id);
  d.proximasSubida = [200, 0];
  await m.drenar();
  assert.equal(m.sinSenal, true); assert.equal(m.detenido, false); assert.equal(m.cola.length, 1);
  destrabar(m); await m.reanudar();
  assert.equal(m.sinSenal, false); assert.equal(m.aviso, 'recibido');
  assert.deepEqual(d.subidas.map((s) => s.archivo), [ids[0], ids[1], ids[1]]);
  // Sin red desde el principio: ni siquiera se abre el envío, y no se pierde.
  const d2 = doble();
  const m2 = await modelo(d2);
  await conArchivos(m2, 1); m2.enviar(null);
  d2.sinRed = true; await m2.drenar();
  assert.equal(m2.sinSenal, true); assert.equal(m2.cola.length, 1); assert.equal(d2.subidas.length, 0);
  d2.sinRed = false; destrabar(m2); await m2.reanudar();
  assert.equal(m2.aviso, 'recibido');
});
await caso('faltan_archivos: se sube de nuevo y se cierra', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 2);
  m.enviar(null);
  d.proximasEnviar = [{ ok: false, error: 'faltan_archivos' }];
  await m.drenar();
  assert.equal(d.subidas.length, 4); assert.equal(m.aviso, 'recibido'); assert.equal(cuenta(d, 'mypump_estudios_enviar'), 2);
});
await caso('un servidor que siempre dice faltan_archivos no hace subir sin fin', async () => {
  const d = doble();
  const m = await modelo(d);
  await conArchivos(m, 1);
  m.enviar(null);
  d.proximasEnviar = Array.from({ length: 20 }, () => ({ ok: false, error: 'faltan_archivos' }));
  await m.drenar();
  assert.equal(d.subidas.length, 1 + MAX_VUELTAS); assert.equal(m.cola.length, 1); assert.equal(m.detenido, true);
});
await caso('tope_dia, id_repetido y errores que no se entienden', async () => {
  let d = doble(), m = await modelo(d);
  await conArchivos(m, 1); m.enviar(null);
  d.proximasNuevo = [{ ok: false, error: 'tope_dia' }];
  await m.drenar();
  assert.equal(m.aviso, 'topeDia'); assert.equal(m.cola.length, 0); assert.equal(d.subidas.length, 0);

  d = doble(); m = await modelo(d);
  await conArchivos(m, 1); m.enviar(null);
  const primero = m.cola[0].id;
  d.proximasNuevo = [{ ok: false, error: 'id_repetido' }];
  await m.drenar();
  assert.equal(m.aviso, 'recibido'); assert.equal(d.envios.size, 1); assert.ok(!d.envios.has(primero));

  d = doble(); m = await modelo(d);
  await conArchivos(m, 1); m.enviar(null);
  d.proximasNuevo = [{ ok: false, error: 'otra_cosa' }];
  await m.drenar();
  assert.equal(m.aviso, 'error'); assert.equal(m.cola.length, 0);
});
await caso('404 del upload: se abre de nuevo; 409: ya estaba enviado', async () => {
  let d = doble(), m = await modelo(d);
  await conArchivos(m, 2); m.enviar(null);
  d.proximasSubida = [200, 404];
  await m.drenar();
  assert.equal(m.aviso, 'recibido'); assert.equal(cuenta(d, 'mypump_estudios_envio_nuevo'), 2); assert.equal([...d.envios.values()][0].dijo, 2);

  d = doble(); m = await modelo(d);
  await conArchivos(m, 2); m.enviar(null);
  const id = m.cola[0].id;
  d.envios.set(id, { id, estado: 'enviado', pedido: null, archivos: new Map([['x', 1], ['y', 1]]) });   // la respuesta de `enviar` se perdió
  m.cola[0].abierto = true;
  await m.drenar();
  assert.equal(m.aviso, 'recibido'); assert.equal(m.cola.length, 0); assert.equal(d.subidas.length, 1);
});
await caso('envio_nuevo contesta «enviado»: no se sube nada otra vez', async () => {
  const d = doble(), m = await modelo(d);
  await conArchivos(m, 2); m.enviar(null);
  const id = m.cola[0].id;
  d.envios.set(id, { id, estado: 'enviado', pedido: null, archivos: new Map([['x', 1]]) });
  await m.drenar();
  assert.equal(m.aviso, 'recibido'); assert.equal(d.subidas.length, 0);
});
await caso('la sección se apaga a mitad de un envío: la cola queda', async () => {
  const d = doble(), m = await modelo(d);
  await conArchivos(m, 1); m.enviar(null);
  d.proximasNuevo = [{ ok: false, error: 'no_habilitado' }];
  await m.drenar();
  assert.equal(m.estado, null); assert.equal(m.cola.length, 1);
  m.cerrar();                                            // palanca apagada: ahí sí no queda nada
  assert.equal(m.cola.length, 0); await m.drenar(); assert.equal(d.subidas.length, 0);
});

// ── «Ya me lo hice» ──
await caso('hecho: guarda la fecha, la deshace con null y distingue fecha mala de sin señal', async () => {
  const d = doble(), m = await modelo(d);
  assert.equal(await m.marcarHecho(PEDIDO, '2026-11-09'), 'ok');
  assert.equal(m.estado.pendientes[0].hecho, true); assert.equal(E.hecho(m.estado.pendientes[0].hechoFecha), 'Hecho el 9/11. Falta subir el resultado.');
  assert.equal(await m.marcarHecho(PEDIDO, '2026-12-01'), 'fecha');
  assert.equal(await m.marcarHecho(PEDIDO, null), 'ok');
  assert.deepEqual(d.hechos[2], [PEDIDO, null]); assert.equal(m.estado.pendientes[0].hecho, false);
  assert.equal(await m.marcarHecho('no-existe', '2026-11-09'), 'ok');     // ya lo cerraron: vale lo del servidor
  d.sinRed = true; assert.equal(await m.marcarHecho(PEDIDO, '2026-11-09'), 'sinSenal');
  d.sinRed = false; d.tokenCaido = true; assert.equal(await m.marcarHecho(PEDIDO, '2026-11-09'), 'error');
});

// ── Abrir un archivo ──
await caso('urls: se piden en el momento, con el token en el cuerpo y nunca en la URL', async () => {
  const d = doble(), m = await modelo(d);
  const r = await m.urls('orden', 'o-1');
  assert.deepEqual(r, { archivos: [{ url: 'https://firmado.ejemplo.test/a.pdf?sig=x', pdf: true }] });
  const p = d.urls[0];
  assert.equal(p.url, 'https://vision.ejemplo.test/estudios/urls'); assert.equal(p.op.method, 'POST'); assert.equal(p.op.cache, 'no-store');
  assert.deepEqual(JSON.parse(p.op.body), { token: TOK, clase: 'orden', id: 'o-1' });
  await m.urls('orden', 'o-1');
  assert.equal(d.urls.length, 2);                        // cada toque pregunta de nuevo: nada queda guardado
  assert.ok(!JSON.stringify(m.estado).includes('firmado'));
});
await caso('urls: todavia_no, link caído y respuestas que no se abren', async () => {
  const d = doble(), m = await modelo(d);
  d.urlsRespuesta = [409, { ok: false, error: 'todavia_no' }]; assert.equal(await m.urls('estudio', 'e'), 'todaviaNo');
  for (const r of [[404, { ok: false }], [403, { ok: false }], [500, {}], [0, null], [200, { ok: true, archivos: [] }], [200, { ok: false }],
    [200, { ok: true, archivos: [{ url: 'http://otro.ejemplo.test/a.pdf', mime: 'application/pdf' }] }],
    [200, { ok: true, archivos: [{ url: 'javascript:alert(1)', mime: 'application/pdf' }] }]]) {
    d.urlsRespuesta = r; assert.equal(await m.urls('estudio', 'e'), 'error', JSON.stringify(r));
  }
  assert.equal(urlSegura('http://localhost:5731/x.pdf'), true); assert.equal(urlSegura('https://a.ejemplo.test/x'), true); assert.equal(urlSegura('data:text/html,x'), false);
  d.urlsRespuesta = [401, { ok: false }]; d.tokenCaido = true;
  assert.equal(await m.urls('estudio', 'e'), 'error'); assert.equal(m.estado, null);
});

// ── Lo que no puede pasar con datos médicos ──
await caso('nada de estudios en localStorage, IndexedDB, cachés ni registros', () => {
  const leer = (f) => fs.readFileSync(new URL(`../public/js/${f}`, import.meta.url), 'utf8');
  for (const f of ['estudios.js', 'estudios-cola.js']) assert.ok(!/localStorage|sessionStorage|indexedDB|caches\.|console\./.test(leer(f)), f);
  const uiSrc = leer('estudios-ui.js');
  assert.ok(!/sessionStorage|indexedDB|caches\.|console\./.test(uiSrc));
  // Lo único que la pantalla guarda es si la palanca estaba prendida.
  const usos = uiSrc.match(/localStorage\.\w+\([^)]*\)/g) || [];
  assert.ok(usos.length > 0 && usos.every((u) => /^localStorage\.(getItem|setItem|removeItem)\(FLAG(, '1')?\)$/.test(u)), usos.join(' | '));
  // El token viaja en un encabezado o en el cuerpo, nunca pegado a una URL.
  for (const f of ['estudios-cola.js', 'estudios-ui.js']) assert.ok(!/[?&](token|t)=|\$\{[^}]*token[^}]*\}/.test(leer(f).replace(/`\$\{this\.visionUrl\}[^`]*`/g, '')), f);
});
await caso('el service worker no guarda nada de esta sección', () => {
  const fuente = fs.readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
  assert.ok(Number(/const VERSION\s*=\s*'v(\d+)/.exec(fuente)[1]) >= 57);
  for (const a of ['/js/estudios.js', '/js/estudios-cola.js', '/js/estudios-ui.js', '/css/estudios.css']) assert.ok(fuente.includes(`'${a}'`), a);
  const oyentes = {};
  const ctx = { self: { addEventListener: (n, f) => { oyentes[n] = f; } }, location: new URL('https://app.ejemplo.test/'), URL, caches: { match: async () => null, open: async () => ({ match: async () => null, put: async () => {} }) }, fetch: async () => new Response('doble'), console };
  vm.createContext(ctx); vm.runInContext(fuente, ctx);
  const responde = (url, method = 'GET', mode = 'cors') => { let usado = false; oyentes.fetch({ request: { url, method, mode }, respondWith() { usado = true; } }); return usado; };
  assert.ok(!responde('https://vision.ejemplo.test/estudios/upload', 'POST'));
  assert.ok(!responde('https://vision.ejemplo.test/estudios/urls', 'POST'));
  assert.ok(!responde('https://x.supabase.co/rest/v1/rpc/mypump_estudios_get', 'POST'));
  assert.ok(!responde('https://x.supabase.co/storage/v1/object/sign/estudios/a.pdf?token=x'));
  assert.ok(!responde('https://app.ejemplo.test/estudios/a.pdf'));
  assert.ok(responde('https://app.ejemplo.test/js/estudios.js'));
});
await caso('cliente.html: la escena existe y solo se entra por Mis datos', () => {
  const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
  assert.ok(html.includes('id="scene-estudios"'));
  assert.ok(/cfg\.estudios_app === true : null/.test(html));
  assert.ok(html.includes("s !== 'estudios') setScene(s)"));
  for (const a of ['/js/estudios.js', '/js/estudios-cola.js', '/js/estudios-ui.js', '/css/estudios.css']) assert.ok(html.includes(`"${a}"`), a);
});

await hasta(() => true);
console.log(`${process.exitCode ? '✗' : '✓'} estudios: ${ok} casos`);
