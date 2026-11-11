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
    estudios: [], urlsRespuesta: null, bajadas: [], bajadaRespuesta: null, ordenes: [], novedades: null, vistas: [], proximasVistas: [], ...ini,
  };
  const sinVer = () => d.pendientes.concat(d.ordenes.filter((o) => o.vigente !== false)).filter((x) => x.nuevo === true).length;
  const vista = () => ({
    habilitado: true, hoy: '2026-11-10', topes: { archivos_por_envio: 20, mb_por_archivo: 20 }, pendientes: d.pendientes, ordenes: d.ordenes, estudios: d.estudios,
    ...(d.sinNovedades ? {} : { novedades: d.novedades === null ? sinVer() : d.novedades }),
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
      case 'mypump_estudios_novedades_vistas': {
        d.vistas.push(p.p_ids.slice());
        if (d.proximasVistas.length) return d.proximasVistas.shift();
        let n = 0;
        for (const x of d.pendientes.concat(d.ordenes)) if (x.nuevo === true && p.p_ids.includes(x.id)) { x.nuevo = false; n++; }   // los que no son suyos, ni se enteran
        return { ok: true, data: { ok: true, marcadas: n } };
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
    if (!String(url).endsWith('/estudios/urls')) {         // un archivo firmado
      d.bajadas.push({ url, op });
      const [status, cuerpo] = d.bajadaRespuesta || [200, new Blob([new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 1])], { type: 'text/html' })];
      if (status === 0) throw new Error('sin red');
      return { status, blob: async () => cuerpo };
    }
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

await caso('bajar: a memoria, sin caché ni credenciales, y con el tipo fijado por la clase del archivo', async () => {
  const d = doble(), m = await modelo(d);
  const firmada = 'https://firmado.ejemplo.test/a.pdf?sig=x';
  const b = await m.bajar({ url: firmada, pdf: true });
  assert.equal(b.type, 'application/pdf'); assert.equal(b.size, 6);      // el servidor dijo text/html: no se le cree
  const op = d.bajadas[0].op;
  assert.equal(d.bajadas[0].url, firmada); assert.equal(op.cache, 'no-store'); assert.equal(op.credentials, 'omit'); assert.equal(op.referrerPolicy, 'no-referrer');
  assert.ok(op.signal); assert.equal(op.method, undefined); assert.equal(op.headers, undefined);      // un GET pelado: el token no viaja
  assert.equal((await m.bajar({ url: firmada, pdf: false })).type, 'image/jpeg');
  d.bajadaRespuesta = [200, new Blob([new Uint8Array(4)], { type: 'image/png' })]; assert.equal((await m.bajar({ url: firmada, pdf: false })).type, 'image/png');
  d.bajadaRespuesta = [200, new Blob([new Uint8Array(4)], { type: 'image/svg+xml' })]; assert.equal((await m.bajar({ url: firmada, pdf: false })).type, 'image/jpeg');
  for (const r of [[0, null], [403, new Blob(['x'])], [404, new Blob(['x'])], [200, new Blob([])]]) { d.bajadaRespuesta = r; assert.equal(await m.bajar({ url: firmada, pdf: true }), null, String(r[0])); }
  d.bajadaRespuesta = null; const antes = d.bajadas.length;
  for (const url of ['http://otro.ejemplo.test/a.pdf', 'javascript:alert(1)', 'blob:x', '']) assert.equal(await m.bajar({ url, pdf: true }), null, url);
  assert.equal(d.bajadas.length, antes);                  // una URL que no es segura ni se pide
});

// ── La pantalla, contra un DOM de mentira: lo justo para tocar botones y mirar qué sale ──
function pantalla(ini = {}) {
  const d = doble({ estudios: [{ id: 'e-1', tipo: 'ecografia', titulo: 'Ecografía', fecha: '2026-10-12', hojas: 2, estado: 'visto', se_puede_abrir: true }], ...ini });
  const x = { d, reloj: { t: 1800000000000 }, activa: false, oyentes: {}, deVentana: {}, guardado: new Map(), creadas: [], soltadas: [], relojes: [], ventanas: [], selectores: [], hojas: [], observadores: [], pedidos: [], sinVentana: false };
  Object.assign(x, { lugar: {}, llevadas: [], escena: 'misdatos', idas: [], entrada: 0, arriba: { firstChild: null, insertBefore(h) { this.firstChild = h; } } });
  const FUERA = { top: 2000, bottom: 2200, left: 0, right: 390, height: 200 }, DENTRO = { top: 200, bottom: 400, left: 0, right: 390, height: 200 };
  x.DENTRO = DENTRO; x.FUERA = FUERA;
  // Las tarjetas salen de lo pintado: `data-tarjeta` y, si es nueva, `data-nueva`. Por defecto están a la vista.
  const tarjetas = (sel) => [...root.innerHTML.matchAll(/data-tarjeta="([^"]+)"( data-nueva="1")?/g)].filter((m) => sel === '[data-tarjeta]' || m[2]).map((m) => ({
    getAttribute: (k) => (k === 'data-tarjeta' ? m[1] : null), getBoundingClientRect: () => x.lugar[m[1]] || DENTRO, scrollIntoView() { x.llevadas.push(m[1]); x.lugar[m[1]] = DENTRO; }, focus() {} }));
  const root = {
    innerHTML: '', classList: { contains: (c) => c === 'is-active' && x.activa }, contains: () => false,
    querySelectorAll: (sel) => (sel === '[data-nueva]' || sel === '[data-tarjeta]' ? tarjetas(sel) : []),
    addEventListener: (t, f) => { x.oyentes[t] = f; },
  };
  x.root = root;
  const hijo = () => ({ on: {}, value: '', disabled: false, textContent: '', addEventListener(t, f) { this.on[t] = f; }, focus() {} });
  const ctx = {
    document: {
      getElementById: (id) => (id === 'scene-estudios' ? root : null), activeElement: null, visibilityState: 'visible', contains: () => false,
      addEventListener() {}, removeEventListener() {}, querySelector: (sel) => { x.selectores.push(sel); return null; }, body: { appendChild() {} },
      createElement: () => { const h = { hijos: {}, on: {}, dataset: {}, innerHTML: '', quitada: false, addEventListener(t, f) { this.on[t] = f; }, remove() { this.quitada = true; }, querySelector(s) { return (this.hijos[s] = this.hijos[s] || hijo()); } }; x.hojas.push(h); return h; },
    },
    localStorage: { getItem: (k) => (x.guardado.has(k) ? x.guardado.get(k) : null), setItem: (k, v) => x.guardado.set(k, String(v)), removeItem: (k) => x.guardado.delete(k) },
    addEventListener: (t, f) => { x.deVentana[t] = f; }, scrollTo() {}, scrollY: 0, innerHeight: 800, innerWidth: 390,
    open: () => { if (x.sinVentana) return null; const w = { closed: false, opener: {}, fue: [], close() { this.closed = true; } }; w.location = { replace: (u) => w.fue.push(u) }; x.ventanas.push(w); return w; },
    MutationObserver: class { constructor(f) { x.observadores.push(f); } observe() {} },
    URL: class extends URL { static createObjectURL(b) { const u = `blob:https://app.ejemplo.test/${x.creadas.length + 1}`; x.creadas.push({ u, tipo: b.type }); return u; } static revokeObjectURL(u) { x.soltadas.push(u); } },
    CSS: { escape: (t) => `«${t}»` },
    Date: class extends Date { static now() { return x.reloj.t; } },
    // El segundo de «la miró» (1000 ms) pasa rápido.
    setTimeout: (f, ms) => { if (ms >= 60000) { x.relojes.push({ f, ms }); return 0; } return setTimeout(f, ms === 1000 ? 8 : ms); }, clearTimeout: (t) => { if (t) clearTimeout(t); },
    fetch: async (url, op) => {
      x.pedidos.push(String(url));
      if (!String(url).endsWith('/estudios/upload')) return d.fetch(url, op);
      const h = op.headers, r = await d.subir({ url, token: h['x-estudios-token'], envio: h['x-estudios-envio'], archivo: h['x-estudios-archivo'], mime: h['Content-Type'], cuerpo: op.body });
      if (!r) throw new Error('sin red');
      return { status: r.status, json: async () => r.json };
    },
    Blob, Response, AbortController, crypto: globalThis.crypto, TextEncoder, Uint8Array,
  };
  ctx.window = ctx; vm.createContext(ctx);
  for (const f of ['estudios.js', 'estudios-cola.js', 'estudios-ui.js']) vm.runInContext(fs.readFileSync(new URL(`../public/js/${f}`, import.meta.url), 'utf8'), ctx, { filename: f });
  x.ui = ctx.EstudiosUI;
  x.ui.configurar({ token: TOK, visionUrl: 'https://vision.ejemplo.test', rpc: d.rpc, alCambiarEntrada() { x.entrada++; }, escena: () => x.escena, irA: (e) => { x.escena = e; x.idas.push(e); x.activa = e === 'estudios'; if (x.activa) x.ui.renderEscena(); } });
  x.respiro = (ms = 40) => new Promise((r) => setTimeout(r, ms));
  x.pausa = (ms = 400) => { x.reloj.t += ms; };
  x.tocar = async (est, id) => { x.oyentes.click({ target: { closest: () => ({ dataset: { est, id }, disabled: false }) } }); for (let i = 0; i < 12; i++) await new Promise((r) => setTimeout(r, 0)); };
  x.entrar = async () => { await x.ui.aplicarPalanca(true); x.ui.abrir(); await hasta(() => cuenta(d, 'mypump_estudios_get') >= 2); x.pausa(); };
  return x;
}
const FIRMA = /firmado|sig=/;

await caso('palanca: sin una lectura fresca en esta carga no se llama a nada, aunque antes estuviera prendida', async () => {
  const x = pantalla(); x.guardado.set('mypump_palanca_estudios_app', '1');
  await x.ui.aplicarPalanca(null);
  assert.equal(x.d.llamadas.length, 0); assert.equal(x.pedidos.length, 0); assert.equal(x.ui.entradaVisible(), false); assert.equal(x.ui._modelo, null);
  assert.equal(x.guardado.size, 0);                       // lo recordado por la versión anterior se borra
  await x.ui.aplicarPalanca(true);
  assert.equal(x.ui.entradaVisible(), true); assert.equal(x.guardado.size, 0);      // prendida: tampoco se guarda
  // Con una subida en curso en memoria, una lectura que falla no la corta; un «no» del servidor, sí.
  const m = x.ui._modelo; await conArchivos(m, 1); m.enviar(null);
  await x.ui.aplicarPalanca(null); assert.equal(x.ui._modelo, m); assert.equal(m.cola.length, 1);
  await x.ui.aplicarPalanca(false); assert.equal(x.ui._modelo, null); assert.equal(x.ui.entradaVisible(), false);
  const y = pantalla(); await y.ui.aplicarPalanca(false); await y.ui.aplicarPalanca(undefined);
  assert.equal(y.d.llamadas.length, 0);
});
await caso('ver la orden: la pestaña recibe un blob, nunca la URL firmada, y se suelta', async () => {
  const x = pantalla(); await x.entrar();
  await x.tocar('verOrden', 'o-1');
  const w = x.ventanas[0];
  assert.equal(x.d.bajadas.length, 1); assert.match(x.d.bajadas[0].url, FIRMA); assert.equal(x.d.bajadas[0].op.cache, 'no-store');
  assert.deepEqual([...w.fue], ['blob:https://app.ejemplo.test/1']); assert.equal(w.opener, null); assert.equal(w.closed, false);
  assert.equal(x.creadas[0].tipo, 'application/pdf');
  assert.ok(!FIRMA.test(x.root.innerHTML)); assert.ok(!x.root.innerHTML.includes('blob:'));      // con pestaña no hay visor
  assert.equal(x.relojes.filter((r) => r.ms === 9 * 60 * 1000).length, 1);
  // Otro toque: URL nueva, blob nuevo, y el anterior se suelta.
  await x.tocar('verOrden', 'o-1');
  assert.equal(x.d.urls.length, 2); assert.deepEqual([...x.soltadas], ['blob:https://app.ejemplo.test/1']); assert.deepEqual([...x.ventanas[1].fue], ['blob:https://app.ejemplo.test/2']);
  // A los 9 minutos se suelta.
  x.relojes[x.relojes.length - 1].f();
  assert.deepEqual([...x.soltadas], ['blob:https://app.ejemplo.test/1', 'blob:https://app.ejemplo.test/2']);
  // No se pudo bajar: se cierra la pestaña y avisa; nada de la URL en la pantalla.
  x.d.bajadaRespuesta = [403, new Blob(['x'])];
  await x.tocar('verOrden', 'o-1');
  assert.equal(x.ventanas[2].closed, true); assert.deepEqual([...x.ventanas[2].fue], []); assert.ok(x.root.innerHTML.includes(T.noSePudoAbrir)); assert.ok(!FIRMA.test(x.root.innerHTML));
  assert.equal(x.creadas.length, 2);
});
await caso('visor: enlaces e imágenes son blob y se sueltan al volver, al salir de la sección y al irse la página', async () => {
  const x = pantalla(); await x.entrar();
  // El navegador no dejó abrir la pestaña: la orden queda como un enlace que el alumno toca.
  x.sinVentana = true;
  await x.tocar('verOrden', 'o-1');
  assert.match(x.root.innerHTML, /<a class="btn-primary est-enlace" href="blob:https:\/\/app\.ejemplo\.test\/1" target="_blank" rel="noopener">/);
  assert.ok(!FIRMA.test(x.root.innerHTML));
  x.pausa(); await x.tocar('volver');
  assert.deepEqual([...x.soltadas], ['blob:https://app.ejemplo.test/1']); assert.ok(!x.root.innerHTML.includes('blob:'));
  // Un estudio con dos fotos.
  x.d.urlsRespuesta = [200, { ok: true, archivos: [{ url: 'https://firmado.ejemplo.test/1.jpg?sig=a', mime: 'image/jpeg' }, { url: 'https://firmado.ejemplo.test/2.jpg?sig=b', mime: 'image/jpeg' }] }];
  x.d.bajadaRespuesta = [200, new Blob([new Uint8Array([0xff, 0xd8, 0xff, 0xe0])], { type: 'image/jpeg' })];
  x.pausa(); await x.tocar('verEstudio', 'e-1');
  assert.equal((x.root.innerHTML.match(/<img class="est-hoja" src="blob:/g) || []).length, 2); assert.ok(!FIRMA.test(x.root.innerHTML));
  // Sale de la sección por la barra de abajo.
  x.activa = false; x.observadores[0]();
  assert.equal(x.soltadas.length, 3); assert.ok(!x.root.innerHTML.includes('blob:'));
  // Vuelve, abre de nuevo y la página se va.
  x.ui.abrir(); x.pausa(); await x.tocar('verEstudio', 'e-1');
  assert.equal(x.creadas.length, 5); x.deVentana.pagehide();
  assert.equal(x.soltadas.length, 5); assert.ok(!x.root.innerHTML.includes('blob:'));
  // Se fue de la sección mientras bajaba: no se crea nada.
  x.ui.abrir(); x.pausa();
  const lenta = x.d.fetch; let seguir; x.d.fetch = async (u, op) => { if (!String(u).endsWith('/estudios/urls')) await new Promise((r) => { seguir = r; }); return lenta(u, op); };
  const toque = x.tocar('verEstudio', 'e-1'); await hasta(() => !!seguir); x.activa = false; seguir(); await toque; await hasta(() => x.d.bajadas.length >= 6);
  for (let i = 0; i < 12; i++) await new Promise((r) => setTimeout(r, 0));
  assert.equal(x.creadas.length, 5); assert.ok(!x.root.innerHTML.includes('blob:'));
});
await caso('doble toque: ni al entrar ni en la hoja de «Ya me lo hice» el segundo toque hace algo', async () => {
  const x = pantalla(); await x.ui.aplicarPalanca(true); x.ui.abrir(); await hasta(() => cuenta(x.d, 'mypump_estudios_get') >= 2);
  // El segundo toque del que abrió la sección cae sobre un botón de acá: no pasa nada.
  await x.tocar('hecho', PEDIDO); assert.equal(x.hojas.length, 0);
  x.pausa(); await x.tocar('hecho', PEDIDO); assert.equal(x.hojas.length, 1);
  const h = x.hojas[0], guardar = h.hijos['#estFechaGuardar'], fecha = h.hijos['#estFecha'];
  fecha.value = '2026-11-10';
  // El segundo toque cae en «Guardar», en «Cancelar» o afuera: ni guarda ni cierra.
  x.pausa(200); await guardar.on.click(); h.on.click({ target: h }); h.on.click({ target: { id: 'estFechaCancelar' } });
  assert.deepEqual(x.d.hechos, []); assert.equal(h.quitada, false);
  x.pausa(200); fecha.value = '2026-11-08'; await guardar.on.click();
  assert.deepEqual(x.d.hechos, [[PEDIDO, '2026-11-08']]); assert.equal(h.quitada, true);
  // Al cerrarse, el toque que sobra no cae en el botón de abajo.
  await x.tocar('deshacer', PEDIDO); assert.equal(x.d.hechos.length, 1);
  x.pausa(); await x.tocar('deshacer', PEDIDO); assert.deepEqual(x.d.hechos[1], [PEDIDO, null]);
});
await caso('un id del servidor dentro de un selector va escapado', async () => {
  const raro = 'x"],[data-est="enviar';
  const x = pantalla({ pendientes: [{ id: raro, tipo: 'laboratorio', titulo: 'Análisis de laboratorio', hasta: '2026-11-19', estado: 'pedido' }] }); await x.entrar();
  await x.tocar('hecho', raro);
  x.pausa(); x.hojas[0].on.click({ target: x.hojas[0] });      // cierra tocando afuera: busca el botón para devolverle el foco
  assert.deepEqual(x.selectores, [`#scene-estudios [data-id="«${raro}»"]`]);
});
await caso('mientras hay algo sin subir, la pantalla pide no cerrar la página', async () => {
  assert.equal(T.noCierres, 'No cierres esta página.');
  const x = pantalla(); await x.entrar();
  assert.ok(!x.root.innerHTML.includes(T.noCierres));
  x.d.sinRed = true;
  const m = x.ui._modelo; await conArchivos(m, 2); m.enviar(null); await m.drenar(); x.ui.renderEscena();
  assert.equal(m.cola.length, 1); assert.match(x.root.innerHTML, /id="estCola"[^>]*>.*<small class="est-banda-nota" id="estNoCierres">No cierres esta página\.<\/small>/);
  x.d.sinRed = false; destrabar(m); await m.drenar(); await hasta(() => m.cola.length === 0); x.ui.renderEscena();
  assert.ok(!x.root.innerHTML.includes(T.noCierres));
});

// ── Lo que no puede pasar con datos médicos ──
await caso('nada de estudios en localStorage, IndexedDB, cachés ni registros', () => {
  const leer = (f) => fs.readFileSync(new URL(`../public/js/${f}`, import.meta.url), 'utf8');
  for (const f of ['estudios.js', 'estudios-cola.js']) assert.ok(!/localStorage|sessionStorage|indexedDB|caches\.|console\./.test(leer(f)), f);
  const uiSrc = leer('estudios-ui.js');
  assert.ok(!/sessionStorage|indexedDB|caches\.|console\./.test(uiSrc));
  // Lo único que la pantalla guarda es si la palanca estaba prendida.
  const usos = uiSrc.match(/localStorage\.\w+\([^)]*\)/g) || [];
  assert.deepEqual(usos, ['localStorage.removeItem(FLAG)']);      // ni la palanca se recuerda: solo se borra la de versiones anteriores
  // Una URL firmada no se navega ni se pinta: lo único que llega a `location.replace`, a un href o a un src es un blob:.
  assert.ok(!/location\.replace\(r\.|r\.archivos\[0\]\.url/.test(uiSrc));
  assert.ok(!/querySelector(All)?\(`[^`]*\$\{(?!escCss\()/.test(uiSrc), 'un valor dentro de un selector va escapado');
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
await caso('cliente.html: la escena existe, ?scene=estudios nunca la prende a ciegas y los puntos dicen «Novedad»', () => {
  const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
  assert.ok(html.includes('id="scene-estudios"'));
  assert.ok(/cfg\.estudios_app === true : null/.test(html));
  // El destino en frío: cae a Mis datos y le deja a EstudiosUI el paso a Estudios. La escena no se prende desde la URL.
  const fn = /function _aplicarSceneDeURL\(\)[\s\S]*?\n\}/.exec(html)[0];
  assert.ok(/if \(s === 'estudios'\) \{[\s\S]*?window\.EstudiosUI\.destino\(caida\);\s*return;/.test(fn));
  assert.ok(fn.includes("'misdatos'")); assert.ok(!/setScene\('estudios'\)/.test(html));
  assert.ok(fn.indexOf("s === 'estudios'") < fn.indexOf('setScene(s)'));
  for (const id of ['estPuntoTab', 'estPuntoMisDatos']) assert.ok(new RegExp(`id="${id}" role="img" aria-label="Novedad" hidden`).test(html), id);
  assert.ok(html.includes("escena: () => STATE.scene"));
  // El clic del aviso: el service worker traduce `destino` a `?scene=` sin lista propia, así que `estudios` llega tal cual.
  const sw = fs.readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
  assert.ok(sw.includes('`/cliente?scene=${encodeURIComponent(destino)}`'));
  for (const a of ['/js/estudios.js', '/js/estudios-cola.js', '/js/estudios-ui.js', '/css/estudios.css']) assert.ok(html.includes(`"${a}"`), a);
});

// ── Novedades, aviso y camino evidente ──
const ORDEN = '00000002-0000-4000-8000-000000000000', ORDEN2 = '00000003-0000-4000-8000-000000000000', PEDIDO2 = '00000004-0000-4000-8000-000000000000';
const pedido = (id, nuevo) => ({ id, tipo: 'laboratorio', titulo: 'Análisis de laboratorio', hasta: '2026-11-19', estado: 'pedido', ...(nuevo === undefined ? {} : { nuevo }) });
const orden = (id, nuevo, vigente = true) => ({ id, tipo: 'laboratorio', titulo: 'Orden de laboratorio', emitida: '2026-11-03', vence: '2027-01-02', vigente, ...(nuevo === undefined ? {} : { nuevo }) });
const est = (o) => E.decodificarEstado({ habilitado: true, ...o });

await caso('novedades: `novedades` y `nuevo` se leen campo por campo; un servidor que no los manda es «nada nuevo»', () => {
  const e = est({ novedades: 2, pendientes: [pedido('p1', true), pedido('p2', false), pedido('p3')], ordenes: [orden('o1', true), orden('o2', 'true'), orden('o3', 1)] });
  assert.equal(e.novedades, 2);
  assert.deepEqual(e.pendientes.map((p) => p.nuevo), [true, false, false]);
  assert.deepEqual(e.ordenes.map((o) => o.nuevo), [true, false, false]);      // solo un `true` de verdad
  for (const n of [undefined, null, 0, -1, '3', 2.5, NaN, {}]) assert.equal(est({ novedades: n, pendientes: [pedido('p1')] }).novedades, 0, String(n));
  const viejo = est({ pendientes: [pedido('p1')], ordenes: [orden('o1')] });
  assert.equal(viejo.novedades, 0); assert.equal(E.novedadDeEstudios(viejo), null); assert.equal(E.primeraNueva(viejo), null);
});
await caso('novedadDeEstudios: un único punto de entrada con título y destino, y los textos del contrato tal cual', () => {
  assert.equal(T.estudioNuevo, 'Tenés un estudio nuevo para hacer'); assert.equal(T.ordenNueva, 'Tenés una orden nueva');
  assert.equal(T.estudioParaHacer, 'Tenés un estudio para hacer'); assert.equal(T.nuevo, 'Nuevo'); assert.equal(T.novedad, 'Novedad');
  assert.equal(T.ver, 'Ver'); assert.equal(T.subirResultado, 'Subir resultado'); assert.equal(E.DESTINO, 'estudios');
  // Hay pedido nuevo → el estudio, aunque también haya una orden nueva.
  assert.deepEqual(E.novedadDeEstudios(est({ novedades: 2, pendientes: [pedido('p1', true)], ordenes: [orden('o1', true)] })), { titulo: T.estudioNuevo, destino: 'estudios' });
  // Solo órdenes nuevas → la orden.
  assert.deepEqual(E.novedadDeEstudios(est({ novedades: 1, pendientes: [pedido('p1', false)], ordenes: [orden('o1', true)] })), { titulo: T.ordenNueva, destino: 'estudios' });
  // Sin novedades no hay nada, aunque quede una marca suelta; una orden vencida no es novedad.
  assert.equal(E.novedadDeEstudios(est({ novedades: 0, pendientes: [pedido('p1', true)] })), null);
  assert.equal(E.novedadDeEstudios(est({ novedades: 1, ordenes: [orden('o1', true, false)] })), null);
  assert.equal(E.novedadDeEstudios(null), null); assert.equal(E.tarjetaInicio(null), null);
  // El servidor cuenta y no marca cuál: se mira qué hay.
  assert.equal(E.novedadDeEstudios(est({ novedades: 1, pendientes: [pedido('p1')] })).titulo, T.estudioNuevo);
  assert.equal(E.novedadDeEstudios(est({ novedades: 1, ordenes: [orden('o1')] })).titulo, T.ordenNueva);
  assert.equal(E.novedadDeEstudios(est({ novedades: 3 })), null);
});
await caso('tarjeta de arriba: novedad con «Ver»; sin novedad y con pendientes, «Subir resultado»; sin nada, no va', () => {
  assert.deepEqual(E.tarjetaInicio(est({ novedades: 1, pendientes: [pedido('p1', true)] })), { titulo: T.estudioNuevo, boton: 'Ver', destino: 'estudios', novedad: true });
  assert.deepEqual(E.tarjetaInicio(est({ novedades: 1, ordenes: [orden('o1', true)] })), { titulo: T.ordenNueva, boton: 'Ver', destino: 'estudios', novedad: true });
  assert.deepEqual(E.tarjetaInicio(est({ novedades: 0, pendientes: [pedido('p1', false)], ordenes: [orden('o1', false)] })), { titulo: T.estudioParaHacer, boton: 'Subir resultado', destino: 'estudios', novedad: false });
  assert.equal(E.tarjetaInicio(est({ ordenes: [orden('o1', false)], estudios: [{ id: 'e', estado: 'visto' }] })), null);
  assert.equal(E.tarjetaInicio(est({})), null);
  // La que queda a la vista al llegar: la primera nueva en el orden de la pantalla (pedido antes que orden); si no, el primer pendiente.
  assert.deepEqual(E.primeraNueva(est({ novedades: 2, pendientes: [pedido('p1', false), pedido('p2', true)], ordenes: [orden('o1', true)] })), { clase: 'pedido', id: 'p2' });
  assert.deepEqual(E.primeraNueva(est({ novedades: 1, pendientes: [pedido('p1', false)], ordenes: [orden('o0', true, false), orden('o1', true)] })), { clase: 'orden', id: 'o1' });
  assert.deepEqual(E.tarjetaDeLlegada(est({ pendientes: [pedido('p1', false), pedido('p2', false)] })), { clase: 'pedido', id: 'p1' });
  assert.equal(E.tarjetaDeLlegada(est({ ordenes: [orden('o1', false)] })), null);
});
await caso('marcar vistas: ids de pedidos y órdenes mezclados, solo los nuevos; apaga el «Nuevo» y el pendiente sigue', async () => {
  const d = doble({ pendientes: [pedido(PEDIDO, true), pedido(PEDIDO2, false)], ordenes: [orden(ORDEN, true), orden(ORDEN2, true)] });
  const m = await modelo(d);
  let cambios = 0; m.alCambiar = () => { cambios++; };
  assert.equal(m.estado.novedades, 3); assert.equal(m.novedad.titulo, T.estudioNuevo); assert.equal(cuenta(d, 'mypump_estudios_novedades_vistas'), 0);      // cargar la lista no marca nada
  assert.equal(await m.marcarVistas([PEDIDO, ORDEN, PEDIDO2, 'no-es-de-nadie', PEDIDO]), 2);
  assert.deepEqual(d.vistas, [[PEDIDO, ORDEN]]);                 // sin repetidos, sin los que no son nuevos
  assert.equal(m.pendientes, 2);                                 // sigue en pendientes
  assert.deepEqual(m.estado.pendientes.map((p) => p.nuevo), [false, false]); assert.deepEqual(m.estado.ordenes.map((o) => o.nuevo), [false, true]);
  assert.equal(m.estado.novedades, 1); assert.equal(m.novedad.titulo, T.ordenNueva); assert.ok(cambios >= 1);
  assert.equal(m.tarjetaInicio.boton, 'Ver');
  // Lo ya marcado no se vuelve a mandar; la última apaga el punto y la tarjeta pasa a «Subir resultado».
  assert.equal(await m.marcarVistas([PEDIDO, ORDEN]), 0); assert.equal(d.vistas.length, 1);
  assert.equal(await m.marcarVistas([ORDEN2]), 1);
  assert.equal(m.novedad, null); assert.equal(m.estado.novedades, 0); assert.deepEqual(m.tarjetaInicio, { titulo: T.estudioParaHacer, boton: 'Subir resultado', destino: 'estudios', novedad: false });
  await m.refrescar(); assert.equal(m.novedad, null);            // y el servidor dice lo mismo
  // No pasa por la cola de subida ni guarda nada.
  assert.equal(m.cola.length, 0); assert.equal(d.subidas.length, 0);
});
await caso('marcar vistas: si falla no se apaga nada y sale de nuevo la próxima vez; dos a la vez no duplican', async () => {
  const d = doble({ pendientes: [pedido(PEDIDO, true)] });
  const m = await modelo(d);
  d.sinRed = true;
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.equal(m.estado.pendientes[0].nuevo, true); assert.ok(m.novedad);
  d.sinRed = false; d.transitorio = true;
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.ok(m.novedad);
  d.transitorio = false;
  d.proximasVistas.push({ ok: true, data: { ok: false, error: 'algo_raro' } }, { ok: true, data: 'texto' });
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.ok(m.novedad);
  const antes = d.vistas.length;
  const [a, b] = await Promise.all([m.marcarVistas([PEDIDO]), m.marcarVistas([PEDIDO])]);
  assert.equal(a + b, 1); assert.equal(d.vistas.length, antes + 1); assert.equal(m.novedad, null);
  assert.equal(m.cola.length, 0);
});
await caso('marcar vistas: token caído, no_habilitado y servidor sin la función', async () => {
  let d = doble({ pendientes: [pedido(PEDIDO, true)] }), m = await modelo(d);
  d.tokenCaido = true;
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.equal(m.estado, null);                 // null = link caído: la sección deja de verse
  d = doble({ pendientes: [pedido(PEDIDO, true)] }); m = await modelo(d);
  d.proximasVistas.push({ ok: true, data: { ok: false, error: 'no_habilitado' } });
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.equal(m.estado, null);
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.equal(d.vistas.length, 1);              // apagada: no se llama más
  d = doble({ pendientes: [pedido(PEDIDO, true)] }); m = await modelo(d);
  d.proximasVistas.push({ ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' });
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.ok(m.estado); assert.ok(m.novedad);      // la sección sigue; solo no se insiste
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.equal(d.vistas.length, 1);
});
await caso('marcar vistas: nunca con la palanca apagada', async () => {
  const d = doble({ pendientes: [pedido(PEDIDO, true)] });
  const m = await modelo(d);
  m.cerrar();
  assert.equal(await m.marcarVistas([PEDIDO]), 0); assert.equal(d.vistas.length, 0);
  // Y la respuesta que llega después de apagarla no toca nada.
  const d2 = doble({ pendientes: [pedido(PEDIDO, true)] }), m2 = await modelo(d2);
  const p = m2.marcarVistas([PEDIDO]); m2.cerrar();
  assert.equal(await p, 0); assert.equal(m2.estado, null);
  // En la pantalla: apagada o sin lectura no existe ni el modelo, así que no hay quien marque, ni aviso, ni punto.
  for (const v of [false, null]) {
    const x = pantalla({ pendientes: [pedido(PEDIDO, true)] });
    await x.ui.aplicarPalanca(v); x.ui.abrir(); x.ui.montarTarjeta(x.arriba); await x.respiro();
    assert.equal(x.d.llamadas.length, 0); assert.equal(x.ui.novedad(), false); assert.equal(x.arriba.firstChild, null); assert.deepEqual(x.idas, []);
  }
});
await caso('pantalla: la tarjeta nueva dice «Nuevo» y se marca vista recién cuando estuvo en pantalla, no al cargar', async () => {
  const x = pantalla({ pendientes: [pedido(PEDIDO, true), pedido(PEDIDO2, false)], ordenes: [orden(ORDEN, true)] });
  await x.ui.aplicarPalanca(true); await x.respiro();
  assert.equal(x.d.vistas.length, 0); assert.equal(x.ui.novedad(), true);        // cargó la lista, con Estudios cerrado: nada
  x.lugar[PEDIDO] = x.FUERA; x.lugar[ORDEN] = x.FUERA;                           // entra, pero las nuevas quedaron fuera de la pantalla
  x.ui.abrir(); await hasta(() => cuenta(x.d, 'mypump_estudios_get') >= 2); await x.respiro();
  assert.equal(x.d.vistas.length, 0);
  const html = x.root.innerHTML;
  assert.equal((html.match(/is-nuevo/g) || []).length, 2); assert.ok(html.includes('<span>Nuevo</span>'));
  assert.ok(html.includes(`data-tarjeta="${PEDIDO}" data-nueva="1"`)); assert.ok(html.includes(`data-tarjeta="${PEDIDO2}">`));      // la que no es nueva no se mira
  // El pendiente nuevo queda a la vista: pasa el rato y se avisa solo de ese.
  x.lugar[PEDIDO] = x.DENTRO; x.deVentana.scroll(); await new Promise((r) => setTimeout(r, 260));
  await hasta(() => x.d.vistas.length === 1); assert.deepEqual([...x.d.vistas[0]], [PEDIDO]);
  await x.respiro(150);
  assert.equal(x.d.vistas.length, 1); assert.equal(x.ui.novedad(), true);        // queda la orden sin ver
  assert.equal((x.root.innerHTML.match(/is-nuevo/g) || []).length, 2);           // la etiqueta no se le va mientras mira
  assert.ok(x.root.innerHTML.includes(`data-tarjeta="${PEDIDO}">`));             // pero ya no se la vigila
  // Media tarjeta a la vista alcanza; un borde, no.
  x.lugar[ORDEN] = { top: 760, bottom: 960, left: 0, right: 390, height: 200 }; x.deVentana.scroll(); await new Promise((r) => setTimeout(r, 260)); await x.respiro(150);
  assert.equal(x.d.vistas.length, 1);
  x.lugar[ORDEN] = { top: 690, bottom: 890, left: 0, right: 390, height: 200 }; x.deVentana.scroll(); await new Promise((r) => setTimeout(r, 260));
  await hasta(() => x.d.vistas.length === 2); assert.deepEqual([...x.d.vistas[1]], [ORDEN]);
  await hasta(() => x.ui.novedad() === false);
  // Al volver a entrar, la etiqueta ya no está.
  x.pausa(); x.ui.abrir(); await x.respiro();
  assert.ok(!x.root.innerHTML.includes('is-nuevo')); assert.equal(x.ui._modelo.pendientes, 2);
});
await caso('pantalla: dentro de una orden, con la página oculta o si se va antes de tiempo, no se marca', async () => {
  const x = pantalla({ pendientes: [pedido(PEDIDO, true)], ordenes: [orden(ORDEN, false)] });
  await x.ui.aplicarPalanca(true);
  x.lugar[PEDIDO] = x.FUERA; x.ui.abrir(); await hasta(() => cuenta(x.d, 'mypump_estudios_get') >= 2); x.pausa();
  await x.tocar('orden', ORDEN);                               // otra pantalla encima de la lista
  x.lugar[PEDIDO] = x.DENTRO; x.deVentana.scroll(); await new Promise((r) => setTimeout(r, 260)); await x.respiro(150);
  assert.equal(x.d.vistas.length, 0);
  x.lugar[PEDIDO] = x.FUERA; x.pausa(); await x.tocar('volver');
  // De vuelta en la lista la tarjeta queda a la vista, pero ya se fue de la sección: no cuenta.
  x.lugar[PEDIDO] = x.DENTRO; x.activa = false; x.deVentana.scroll(); await new Promise((r) => setTimeout(r, 260)); await x.respiro(150);
  assert.equal(x.d.vistas.length, 0);
  x.activa = true; x.ui.renderEscena(); await hasta(() => x.d.vistas.length === 1);
});
await caso('destino `estudios` en frío: de Mis datos pasa a Estudios con la tarjeta nueva a la vista, con un solo get', async () => {
  const x = pantalla({ pendientes: [pedido(PEDIDO2, false), pedido(PEDIDO, true)], ordenes: [orden(ORDEN, true)] });
  x.lugar[PEDIDO] = x.FUERA;                                   // la nueva está más abajo de lo que entra en la pantalla
  x.ui.destino('misdatos');                                    // llega antes que la palanca: todavía no hay nada
  assert.deepEqual(x.idas, []); assert.equal(x.root.innerHTML, '');
  await x.ui.aplicarPalanca(true);
  assert.deepEqual(x.idas, ['estudios']); assert.equal(x.ui.origen, 'misdatos');
  assert.equal(x.llevadas[0], PEDIDO);                         // la primera NUEVA, no la primera de la lista
  assert.ok(x.root.innerHTML.includes('Te falta hacer'));
  await x.respiro();
  assert.equal(cuenta(x.d, 'mypump_estudios_get'), 1);         // el get recién llegado no se repite
  await hasta(() => x.d.vistas.length === 1);                  // y al quedar a la vista, se marcan juntas, en una sola llamada
  assert.deepEqual([...x.d.vistas[0]].sort(), [PEDIDO, ORDEN].sort());
  // «Cerrar» vuelve a Mis datos.
  x.pausa(); await x.tocar('volver'); assert.equal(x.idas[x.idas.length - 1], 'misdatos');
  // Con la app ya abierta: mismo destino, abre en el acto. Sin nada nuevo, queda a la vista el primer pendiente.
  const y = pantalla({ pendientes: [pedido(PEDIDO2, false), pedido(PEDIDO, false)] });
  await y.ui.aplicarPalanca(true); y.ui.destino('misdatos');
  assert.deepEqual(y.idas, ['estudios']); assert.deepEqual(y.llevadas, []);      // ya se ve entera: no se le mueve la pantalla
  y.pausa(); await y.tocar('volver'); y.lugar[PEDIDO2] = y.FUERA; y.pausa(); y.ui.destino('misdatos');
  assert.deepEqual(y.llevadas, [PEDIDO2]);
  // Desde la fila de Mis datos, sin nada nuevo, no se le mueve la pantalla.
  const z = pantalla({ pendientes: [pedido(PEDIDO2, false)] });
  await z.ui.aplicarPalanca(true); z.ui.abrir({ desde: 'misdatos' }); await z.respiro();
  assert.deepEqual(z.llevadas, []);
});
await caso('destino `estudios`, caída segura: palanca apagada, cuenta sin la sección o get que falla → se queda en Mis datos', async () => {
  const casos = [
    ['palanca apagada', {}, false], ['sin lectura de la palanca', {}, null], ['cuenta sin la sección', { habilitado: false }, true],
    ['sin la función', { sinFuncion: true }, true], ['link caído', { tokenCaido: true }, true], ['sin red', { sinRed: true }, true], ['servicio caído', { transitorio: true }, true],
  ];
  for (const [nombre, ini, palanca] of casos) {
    const x = pantalla({ pendientes: [pedido(PEDIDO, true)], ...ini });
    x.ui.destino('misdatos');
    await x.ui.aplicarPalanca(palanca); await x.respiro();
    assert.deepEqual(x.idas, [], nombre); assert.equal(x.escena, 'misdatos', nombre);      // nadie lo sacó de Mis datos
    assert.equal(x.root.innerHTML, '', nombre); assert.equal(x.ui.entradaVisible(), false, nombre);
    assert.equal(x.d.vistas.length, 0, nombre);
  }
  // Si mientras tanto se fue a otra pantalla, no se lo trae de vuelta.
  const x = pantalla({ pendientes: [pedido(PEDIDO, true)] });
  x.ui.destino('misdatos'); x.escena = 'chat';
  await x.ui.aplicarPalanca(true); await x.respiro();
  assert.deepEqual(x.idas, []); assert.equal(x.ui.entradaVisible(), true);
  x.escena = 'misdatos'; x.ui._modelo.refrescar(); await x.respiro();
  assert.deepEqual(x.idas, []);                                // el destino ya se soltó: volver a Mis datos no lo dispara
  // Si el servidor tarda más de la cuenta, tampoco: se queda donde está.
  const y = pantalla({ pendientes: [pedido(PEDIDO, true)] });
  y.ui.destino('misdatos'); y.pausa(13000);
  await y.ui.aplicarPalanca(true); await y.respiro();
  assert.deepEqual(y.idas, []);
});
await caso('aviso de arriba: título y botón del contrato, un toque lleva a Estudios en esa tarjeta y vuelve a Entreno', async () => {
  const x = pantalla({ pendientes: [pedido(PEDIDO2, false), pedido(PEDIDO, true)] });
  await x.ui.aplicarPalanca(true);
  x.ui.montarTarjeta(x.arriba);
  const h = x.arriba.firstChild;
  assert.ok(h.innerHTML.includes('Tenés un estudio nuevo para hacer')); assert.ok(/<button type="button" class="est-aviso-btn" id="estAvisoBtn">Ver<\/button>/.test(h.innerHTML));
  assert.ok(h.innerHTML.includes('aria-label="Novedad"'));
  assert.ok(x.entrada >= 1);                                   // avisó para que se pinten los puntos
  x.lugar[PEDIDO] = x.FUERA; h.on.click();
  assert.deepEqual(x.idas, ['estudios']); assert.equal(x.ui.origen, 'train'); assert.equal(x.llevadas[0], PEDIDO);
  await hasta(() => x.d.vistas.length === 1);
  x.pausa(); await x.tocar('volver'); assert.equal(x.idas[x.idas.length - 1], 'train');
  // Vista la novedad, el aviso queda como recordatorio con «Subir resultado»; a un toque de Estudios y dos de la hoja de subida.
  await hasta(() => x.ui.novedad() === false);
  x.ui.montarTarjeta(x.arriba);
  const h2 = x.arriba.firstChild;
  assert.ok(h2.innerHTML.includes('Tenés un estudio para hacer')); assert.ok(h2.innerHTML.includes('>Subir resultado</button>')); assert.ok(!h2.innerHTML.includes('aria-label="Novedad"'));
  x.lugar[PEDIDO2] = x.FUERA; x.pausa(); h2.on.click(); assert.equal(x.idas[x.idas.length - 1], 'estudios'); assert.equal(x.llevadas[x.llevadas.length - 1], PEDIDO2);
  x.pausa(); await x.tocar('subirResultado', PEDIDO2);
  for (const t of ['Sacar fotos', 'Elegir fotos', 'Elegir PDF']) assert.ok(x.root.innerHTML.includes(`<span>${t}</span></button>`), t);
  // Sin pendientes ni novedades, o con la sección apagada, el aviso se va.
  const y = pantalla({ pendientes: [] }); await y.ui.aplicarPalanca(true); y.ui.montarTarjeta(y.arriba); assert.equal(y.arriba.firstChild, null);
});
await caso('subir es lo principal: «Subir resultado» primero y con texto en cada pendiente, y «Enviar N archivos» en la hoja', async () => {
  const x = pantalla({ pendientes: [pedido(PEDIDO, true)] }); await x.entrar();
  const h = x.root.innerHTML;
  assert.ok(/class="btn-primary" data-est="subirResultado"[^>]*>.*?<span>Subir resultado<\/span><\/button>\s*<div class="est-botones">.*?Ya me lo hice/s.test(h));
  await x.tocar('subirResultado', PEDIDO);
  await conArchivos(x.ui._modelo, 2); x.ui.renderEscena();
  assert.ok(/class="btn-primary est-principal" data-est="enviar" id="estEnviar">Enviar 2 archivos<\/button>/.test(x.root.innerHTML));
});

await hasta(() => true);
console.log(`${process.exitCode ? '✗' : '✓'} estudios: ${ok} casos`);
