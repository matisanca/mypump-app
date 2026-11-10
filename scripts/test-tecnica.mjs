#!/usr/bin/env node
/* =============================================================
 * test-tecnica.mjs — reglas y cola de «Técnica por video» contra un doble del
 * servidor (tecnica/CONTRATO_APP.md), con el almacén en memoria.
 * IndexedDB real y la subida por XHR se prueban en el navegador.
 * USO:  node scripts/test-tecnica.mjs
 * ============================================================= */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const Tec = require('../public/js/tecnica.js');
const { ModeloTecnica, almacenMemoria, MAX_FALLOS, MAX_FALLOS_BARATOS } = require('../public/js/tecnica-cola.js');
const T = Tec.T;

const TOK = 'token-de-prueba-0123456789';
const SID = '22222222-2222-4222-8222-222222222222';
let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }

const EJ = { slug: 'sentadilla', nombre: 'Sentadilla' };
const video = (n = 1000) => new Blob([new Uint8Array(n)], { type: 'video/mp4' });
const base = (extra = {}) => ({ ejercicio: EJ, nota: '', archivo: video(), duracion: 30, contenedorOk: true, ...extra });

function doble(ini = {}) {
  const d = { habilitado: true, aceptado: false, sinRed: false, sinFuncion: false, tokenCaido: false, envios: [], llamadas: [], proximasNuevo: [], proximasSubida: [], cancelados: [], ultimoNuevo: null, subidas: [], ...ini };
  d.rpc = async (fn, p) => {
    d.llamadas.push(fn);
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    if (d.tokenCaido) return { ok: true, data: null };
    switch (fn) {
      case 'mypump_tecnica_get':
        return { ok: true, data: d.habilitado ? { habilitado: true, consentimiento_version: 'v1', consentimiento_aceptado: d.aceptado, topes: { duracion_min_s: 4, duracion_max_s: 75, bytes_max: 5000, por_semana: 3 }, envios: d.envios } : { habilitado: false } };
      case 'mypump_tecnica_nuevo': {
        d.ultimoNuevo = p;
        if (d.proximasNuevo.length) return { ok: true, data: d.proximasNuevo.shift() };
        if (!d.envios.some((e) => e.id === SID)) d.envios.unshift({ id: SID, estado: 'borrador', ejercicio_nombre: p.p_ejercicio_nombre });
        return { ok: true, data: { ok: true, id: SID } };
      }
      case 'mypump_tecnica_cancelar': d.cancelados.push(p.p_id); return { ok: true, data: { ok: true } };
      default: return { ok: true, data: null };
    }
  };
  d.subir = async (q) => {
    d.subidas.push(q.id);
    if (d.sinRed) return null;
    const s = d.proximasSubida.length ? d.proximasSubida.shift() : 200;
    if (s === 'apagaRed') { d.sinRed = true; return null; }
    if (s === 0) return null;
    if (s === 'caro') { q.alProgreso(q.cuerpo.size / 2, q.cuerpo.size); return null; }
    if (s === 'llegoYCorte') { d.envios[0].estado = 'enviado'; return null; }
    if (typeof s === 'object') return s;
    if (s === 200) { const e = d.envios.find((x) => x.id === q.id); if (e) e.estado = 'enviado'; q.alProgreso(q.cuerpo.size, q.cuerpo.size); return { status: 200, json: { ok: true } }; }
    return { status: s, json: { ok: false, error: 'forzado' } };
  };
  return d;
}

async function modelo(d, extra = {}) {
  const esperas = [];
  const m = new ModeloTecnica({
    rpc: d.rpc, subir: d.subir, almacen: extra.almacen || almacenMemoria(), token: TOK, visionUrl: 'https://x',
    esperar: (ms) => { esperas.push(ms); return new Promise(() => {}); },        // los reintentos no corren solos: los dispara cada test
    ahora: extra.ahora || (() => Date.parse('2026-11-10T12:00:00Z')), visible: () => true, nuevoId: () => 'aaaaaaaa-0000-4000-8000-000000000001',
  });
  m.esperas = esperas;
  await m.cargar();
  await m.refrescar();
  return m;
}
const destrabar = (m) => { m._reintentoProgramado = false; };
const reintentarYa = async (m) => { destrabar(m); await m.drenar(); };
const hasta = async (f) => { for (let i = 0; i < 400 && !f(); i++) await new Promise((r) => setTimeout(r, 1)); assert.ok(f(), 'no se cumplió: ' + f); };

// ── Reglas ──
await caso('decodificar: apagado, token caído y raro no muestran nada', () => {
  assert.equal(Tec.decodificarEstado(null), null);
  assert.equal(Tec.decodificarEstado({ habilitado: false }), null);
  assert.equal(Tec.decodificarEstado({ habilitado: true }), null);
});
await caso('decodificar: estados desconocidos afuera; topes por defecto', () => {
  const e = Tec.decodificarEstado({ habilitado: true, consentimiento_version: 'v', envios: [{ id: 'A', estado: 'procesando' }, { id: 'B', estado: 'enviado' }, 3] });
  assert.deepEqual(e.envios.map((x) => x.id), ['b']);
  assert.equal(e.topes.duracionMax, 75);
  assert.equal(e.topes.bytesMax, 62914560);
});
await caso('decodificar: la devolución no deja pasar confianza, códigos ni mediciones', () => {
  const d = Tec.decodificarDevolucion({ bien: ['Buena bajada', 7], confianza: 0.9, correcciones: [
    { prioridad: 2, titulo: 'Rodillas', que_se_ve: 'x', por_que: 'y', como_corregir: 'z', momento_s: 12.4, codigo: 'E7', angulo: 91 },
    { prioridad: 1, titulo: 'Espalda', momento_s: 'no' }, { sin: 'titulo' }],
    no_evaluable: [{ que: 'Pies', motivo: 'no se ven', confianza: 0.2 }], pedir_otro_video: { necesario: false, como: 'de frente' } });
  assert.deepEqual(d.bien, ['Buena bajada']);
  assert.deepEqual(d.correcciones.map((c) => c.titulo), ['Espalda', 'Rodillas']);
  assert.equal(d.correcciones[0].momento, null);
  assert.equal(d.correcciones[1].momento, 12.4);
  assert.deepEqual(Object.keys(d.correcciones[1]).sort(), ['como', 'momento', 'orden', 'porQue', 'queSeVe', 'titulo']);
  assert.deepEqual(d.noEvaluable, [{ que: 'Pies', motivo: 'no se ven' }]);
  assert.equal(d.pedirOtro, null);
});
await caso('publicado sin devolución legible no es «devolución»', () => {
  const e = Tec.decodificarEnvio({ id: 'x', estado: 'publicado', devolucion: null });
  assert.equal(Tec.conDevolucion(e), false);
});
await caso('rechazo: solo textos aprobados', () => {
  assert.equal(Tec.textoRechazo(T.rechazos.oscuro), T.rechazos.oscuro);
  assert.equal(Tec.textoRechazo('sin_persona'), T.rechazos.ilegible);
  assert.equal(Tec.textoRechazo(null), T.rechazos.ilegible);
});
await caso('validar: topes, contenedor y duración desconocida', () => {
  const t = Tec.TOPES_BASE;
  assert.equal(Tec.validarVideo({ bytes: 100, duracion: 30, contenedorOk: true }, t), null);
  assert.equal(Tec.validarVideo({ bytes: 0, duracion: 30, contenedorOk: true }, t), 'ilegible');
  assert.equal(Tec.validarVideo({ bytes: 100, duracion: 30, contenedorOk: false }, t), 'ilegible');
  assert.equal(Tec.validarVideo({ bytes: t.bytesMax + 1, duracion: 30, contenedorOk: true }, t), 'pesado');
  assert.equal(Tec.validarVideo({ bytes: t.bytesMax, duracion: 75, contenedorOk: true }, t), null);
  assert.equal(Tec.validarVideo({ bytes: 100, duracion: 75.5, contenedorOk: true }, t), 'largo');
  assert.equal(Tec.validarVideo({ bytes: 100, duracion: 3.9, contenedorOk: true }, t), 'corto');
  assert.equal(Tec.validarVideo({ bytes: 100, duracion: null, contenedorOk: true }, t), null);
});
await caso('contenedor: ftyp', () => {
  assert.equal(Tec.esMp4OMov(new Uint8Array([0, 0, 0, 20, 0x66, 0x74, 0x79, 0x70, 0, 0, 0, 0])), true);
  assert.equal(Tec.esMp4OMov(new Uint8Array([0x1a, 0x45, 0xdf, 0xa3, 0, 0, 0, 0, 0])), false);
});
await caso('clasificar: 4xx definitivo, 429 y 5xx reintentan, textos', () => {
  const c = Tec.clasificarSubida;
  assert.equal(c(200, { ok: true }).accion, 'ok');
  assert.equal(c(200, { ok: true, ya: true }).accion, 'ok');
  assert.equal(c(200, null).accion, 'reintentar');
  for (const s of [429, 500, 502, 503]) assert.equal(c(s, null).accion, 'reintentar', s);
  for (const s of [400, 403, 404, 409, 411, 413]) assert.equal(c(s, { error: 'x' }).accion, 'descartar', s);
  assert.equal(c(400, { error: 'video muy corto' }).aviso, T.rechazos.corto);
  assert.equal(c(400, { error: 'video muy largo' }).aviso, T.rechazos.largo);
  assert.equal(c(400, { error: 'el video no se puede leer' }).aviso, T.rechazos.ilegible);
  assert.equal(c(400, { error: 'el archivo debe ser un video MP4 o MOV' }).aviso, T.rechazos.ilegible);
  assert.equal(c(400, { error: 'largo incorrecto' }).aviso, T.rechazos.ilegible);
  assert.equal(c(413, { error: 'video muy pesado' }).aviso, T.rechazos.pesado);
});
await caso('bloqueo: en revisión y tope semanal; rechazados no cuentan', () => {
  const ahora = Date.parse('2026-11-10T12:00:00Z');
  const est = (envios) => ({ topes: { porSemana: 3 }, envios });
  const pub = (d) => ({ estado: 'publicado', enviadoEn: `2026-11-${d}T10:00:00Z` });
  assert.equal(Tec.bloqueo(est([]), 0, ahora), null);
  assert.equal(Tec.bloqueo(est([]), 1, ahora), 'enRevision');
  assert.equal(Tec.bloqueo(est([{ estado: 'enviado' }]), 0, ahora), 'enRevision');
  assert.equal(Tec.bloqueo(est([pub('09'), pub('08'), pub('07')]), 0, ahora), 'tope');
  assert.equal(Tec.bloqueo(est([pub('09'), pub('08'), pub('01')]), 0, ahora), null);
  assert.equal(Tec.bloqueo(est([pub('09'), pub('08'), { estado: 'rechazado', enviadoEn: '2026-11-09T10:00:00Z' }]), 0, ahora), null);
});
await caso('ejercicios: sin repetir, sin cardio, con el sustituto aplicado', () => {
  const dias = [{ bloques: [{ ejercicios: [{ nombre: 'Sentadilla', catalogo_slug: 'Squat' }, { nombre: 'Cinta', tipo: 'cardio' }] }] }, { bloques: [{ ejercicios: [{ nombre: 'sentadilla' }, { nombre: 'Remo', id: 'r' }] }] }];
  const l = Tec.ejerciciosDeRutina(dias, (x) => (x.id === 'r' ? { ...x, nombre: 'Remo T', _swapSlug: 'T-Bar' } : x), (x) => x.tipo === 'cardio');
  assert.deepEqual(l, [{ slug: 'Squat', nombre: 'Sentadilla' }, { slug: 'T-Bar', nombre: 'Remo T' }]);
  assert.equal(Tec.slugDe('Press Inclinado 30°'), 'press-inclinado-30');
});
await caso('textos: solo el aviso de terceros menciona la IA; nunca RIR ni reserva', () => {
  const planos = [];
  const juntar = (o) => { for (const v of Object.values(o)) { if (typeof v === 'string') planos.push(v); else if (typeof v === 'function') planos.push(v('X')); else if (v && typeof v === 'object') juntar(v); } };
  juntar(T);
  const ia = planos.filter((s) => /inteligencia artificial|\bIA\b|autom[aá]tic|modelo|algoritmo/i.test(s));
  assert.deepEqual(ia, [T.avisoTerceros]);
  assert.deepEqual(planos.filter((s) => /\bRIR\b|en reserva|exacto a las|a las \d/i.test(s)), []);
  assert.match(T.recibido, /1 a 2 días/);
});

// ── Cola ──
await caso('apagado o sin servidor: sin estado y sin subir', async () => {
  for (const ini of [{ habilitado: false }, { sinFuncion: true }, { tokenCaido: true }]) {
    const d = doble(ini);
    const m = await modelo(d);
    assert.equal(m.visibleEntrada, false);
    assert.equal(await m.enviar(base()), 'invalido');
    assert.deepEqual(d.subidas, []);
  }
});
await caso('envío completo: consentimiento, un nuevo, una subida, cola vacía, sin borrador a la vista', async () => {
  const d = doble();
  const m = await modelo(d);
  assert.equal(m.necesitaAviso, true);
  assert.equal(await m.enviar(base({ nota: '  mirá la bajada ' })), 'ok');
  await hasta(() => d.subidas.length === 1 && !m.cola.length);
  assert.deepEqual(d.ultimoNuevo, { p_token: TOK, p_ejercicio_slug: 'sentadilla', p_ejercicio_nombre: 'Sentadilla', p_nota: 'mirá la bajada', p_consentimiento: 'v1' });
  assert.equal(d.subidas[0], SID);
  await hasta(() => m.envios.length === 1);
  assert.equal(m.envios[0].estado, 'enviado');
  assert.equal(m.necesitaAviso, false);
  assert.equal(m.bloqueo, 'enRevision');
});
await caso('el aviso va una sola vez aunque el servidor todavía no lo sepa', async () => {
  const d = doble({ proximasSubida: [{ status: 400, json: { error: 'video muy corto' } }] });
  const alm = almacenMemoria();
  const m = await modelo(d, { almacen: alm });
  await m.enviar(base());
  await hasta(() => !m.cola.length && m.aviso);
  const m2 = await modelo(d, { almacen: alm });
  assert.equal(m2.necesitaAviso, false);
});
await caso('los topes frenan antes de guardar', async () => {
  const d = doble();
  const m = await modelo(d);
  assert.equal(await m.enviar(base({ archivo: video(5001) })), 'pesado');
  assert.equal(await m.enviar(base({ duracion: 90 })), 'largo');
  assert.equal(await m.enviar(base({ duracion: 2 })), 'corto');
  assert.equal(await m.enviar(base({ contenedorOk: false })), 'ilegible');
  assert.equal(m.cola.length, 0);
  assert.deepEqual(d.llamadas.filter((x) => x === 'mypump_tecnica_nuevo'), []);
});
await caso('un solo video a la vez', async () => {
  const d = doble({ proximasSubida: [0], sinRed: false });
  const m = await modelo(d);
  await m.enviar(base());
  assert.equal(await m.enviar(base()), 'enRevision');
});
await caso('4xx: se descarta con su texto, se cierra el borrador y no se reintenta', async () => {
  for (const [res, txt] of [[{ status: 400, json: { error: 'video muy largo' } }, T.rechazos.largo], [{ status: 413, json: { error: 'x' } }, T.rechazos.pesado], [{ status: 403, json: {} }, T.errorGenerico]]) {
    const d = doble({ proximasSubida: [res] });
    const m = await modelo(d);
    await m.enviar(base());
    await hasta(() => !m.cola.length && m.aviso);
    assert.equal(m.aviso, txt);
    assert.equal(d.subidas.length, 1);
    assert.deepEqual(d.cancelados, [SID]);
  }
});
await caso('errores de nuevo: en_curso, tope, no_habilitado', async () => {
  let d = doble({ proximasNuevo: [{ ok: false, error: 'en_curso', id: 'z' }] });
  let m = await modelo(d);
  await m.enviar(base());
  await hasta(() => m.aviso === T.enRevision && !m.cola.length);
  assert.deepEqual(d.subidas, []);
  d = doble({ proximasNuevo: [{ ok: false, error: 'tope_semanal' }] });
  m = await modelo(d);
  await m.enviar(base());
  await hasta(() => m.aviso === T.topeSemana(3) && !m.cola.length);
  d = doble({ proximasNuevo: [{ ok: false, error: 'no_habilitado' }] });
  m = await modelo(d);
  await m.enviar(base());
  await hasta(() => m.estado === null);
  assert.deepEqual(d.subidas, []);
});
await caso('nuevo con «reintentar»: una vez más y sale', async () => {
  const d = doble({ proximasNuevo: [{ ok: false, error: 'reintentar' }] });
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => d.subidas.length === 1 && !m.cola.length);
});
await caso('sin señal en nuevo: queda y sigue después, sin duplicar', async () => {
  const d = doble();
  const m = await modelo(d);
  d.sinRed = true;
  await m.enviar(base());
  await hasta(() => m.esperas.length === 1);
  assert.equal(m.cola.length, 1);
  assert.equal(m.cola[0].servidorId, null);
  d.sinRed = false;
  await reintentarYa(m);
  assert.equal(m.cola.length, 0);
  assert.deepEqual(d.subidas, [SID]);
});
await caso('corte sin señal: no gasta intentos', async () => {
  const d = doble({ proximasSubida: ['apagaRed'] });
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => m.esperas.length >= 1);
  for (let i = 0; i < 6; i++) await reintentarYa(m);
  assert.equal(d.subidas.length, 7);
  assert.equal(m.cola.length, 1);
  assert.equal(m.cola[0].fallos, 0);
  assert.equal(m.cola[0].pausado, false);
  d.sinRed = false;
  await reintentarYa(m);
  assert.equal(m.cola.length, 0);
});
await caso('corte con datos mandados y el servidor al alcance: a los 4 queda en pausa y no sigue gastando', async () => {
  const d = doble({ proximasSubida: Array(10).fill('caro') });
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallos === 1);
  for (let i = 1; i < 8; i++) await reintentarYa(m);
  assert.equal(d.subidas.length, MAX_FALLOS);
  assert.equal(m.cola[0].pausado, true);
  m.reanudar();
  await new Promise((r) => setTimeout(r, 5));
  assert.equal(d.subidas.length, MAX_FALLOS, 'volver a la pestaña no reanuda lo pausado');
  d.proximasSubida = [];
  await m.reintentar(m.cola[0].id);
  await hasta(() => !m.cola.length);
  assert.equal(d.subidas.length, MAX_FALLOS + 1);
});
await caso('rechazo apenas arranca (corte sin avance o 429): cupo largo, espera de un minuto, y al final pausa', async () => {
  const d = doble({ proximasSubida: [...Array(6).fill(0), ...Array(20).fill(429)] });
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallosBaratos === 1);
  assert.equal(m.esperas[0], 60000);
  for (let i = 1; i < 30; i++) await reintentarYa(m);
  assert.equal(d.subidas.length, MAX_FALLOS_BARATOS);
  assert.equal(m.cola[0].fallos, 0);
  assert.equal(m.cola[0].pausado, true);
});
await caso('corte sin señal pero con datos mandados: cuenta, una señal intermitente tiene tope', async () => {
  const d = doble({ proximasSubida: Array(10).fill('caro') });
  const m = await modelo(d);
  const rpcOriginal = d.rpc;
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallos === 1);
  d.rpc = async () => ({ ok: false, status: 0, codigo: 'NETWORK', clase: 'red' });
  m.rpc = d.rpc;
  for (let i = 1; i < 8; i++) await reintentarYa(m);
  assert.equal(d.subidas.length, MAX_FALLOS);
  assert.equal(m.cola[0].pausado, true);
  m.rpc = rpcOriginal;
});
await caso('envío que ya no existe en el servidor: se saca, no se reintenta', async () => {
  const d = doble({ proximasSubida: [0] });
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => d.subidas.length === 1 && m.cola.length <= 1);
  await hasta(() => m.cola[0] ? m.cola[0].fallosBaratos === 1 : true);
  d.envios.length = 0;
  d.proximasSubida = [0];
  await reintentarYa(m);
  assert.equal(m.cola.length, 0);
  assert.equal(m.aviso, T.noSubio);
  assert.equal(d.subidas.length, 2);
});
await caso('subió y el refresco falla: queda como recibido y sigue bloqueado', async () => {
  const d = doble();
  d.subir = async (q) => { d.sinRed = true; return { status: 200, json: { ok: true } }; };
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => !m.cola.length && m.envios.length === 1);
  assert.equal(m.envios[0].estado, 'enviado');
  assert.equal(m.bloqueo, 'enRevision');
});
await caso('cancelar mientras viaja `nuevo`: no resucita y el borrador se cierra', async () => {
  const d = doble();
  const alm = almacenMemoria();
  const m = await modelo(d, { almacen: alm });
  const orig = d.rpc;
  let soltar;
  m.rpc = async (fn, p) => { if (fn === 'mypump_tecnica_nuevo') { await new Promise((r) => { soltar = r; }); } return orig(fn, p); };
  await m.enviar(base());
  await hasta(() => !!soltar);
  await m.cancelar(m.cola[0].id);
  soltar();
  await hasta(() => d.cancelados.length === 1);
  assert.deepEqual(d.cancelados, [SID]);
  assert.deepEqual(d.subidas, []);
  assert.equal((await alm.listar()).length, 0);
  assert.equal(m.cola.length, 0);
});
await caso('llegó y se cortó la respuesta: se da por enviado sin volver a subir', async () => {
  const d = doble({ proximasSubida: ['llegoYCorte'] });
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => !m.cola.length);
  assert.equal(d.subidas.length, 1);
  assert.equal(m.envios[0].estado, 'enviado');
});
await caso('5xx: reintenta con espera; a los 4 queda en pausa', async () => {
  const d = doble({ proximasSubida: [503, 503, 500, 502, 200] });
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallos === 1);
  for (let i = 1; i < 5; i++) await reintentarYa(m);
  assert.equal(d.subidas.length, 4);
  assert.equal(m.cola[0].pausado, true);
});
await caso('recargar a mitad: el mismo id, no un envío nuevo', async () => {
  const d = doble({ proximasSubida: ['caro'] });
  const alm = almacenMemoria();
  const m = await modelo(d, { almacen: alm });
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallos === 1);
  const nuevos = d.llamadas.filter((x) => x === 'mypump_tecnica_nuevo').length;
  const m2 = await modelo(d, { almacen: alm });
  assert.equal(m2.cola.length, 1);
  await m2.drenar();
  assert.equal(m2.cola.length, 0);
  assert.deepEqual(d.subidas, [SID, SID]);
  assert.equal(d.llamadas.filter((x) => x === 'mypump_tecnica_nuevo').length, nuevos);
});
await caso('al recargar, lo que el servidor ya tomó sale de la cola sin subir', async () => {
  const d = doble({ proximasSubida: ['caro'] });
  const alm = almacenMemoria();
  const m = await modelo(d, { almacen: alm });
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallos === 1);
  d.envios[0].estado = 'enviado';
  const m2 = await modelo(d, { almacen: alm });
  assert.equal(m2.cola.length, 0);
  assert.equal(d.subidas.length, 1);
});
await caso('cancelar: sale de la cola y del servidor', async () => {
  const d = doble({ proximasSubida: ['caro'] });
  const m = await modelo(d);
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallos === 1);
  await m.cancelar(m.cola[0].id);
  assert.equal(m.cola.length, 0);
  assert.deepEqual(d.cancelados, [SID]);
  await reintentarYa(m);
  assert.equal(d.subidas.length, 1);
});
await caso('otra cuenta en el mismo teléfono no ve la cola', async () => {
  const d = doble({ proximasSubida: ['caro'] });
  const alm = almacenMemoria();
  const m = await modelo(d, { almacen: alm });
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallos === 1);
  const otro = new ModeloTecnica({ rpc: d.rpc, subir: d.subir, almacen: alm, token: 'otro-token-9876543210', visionUrl: 'https://x' });
  await otro.cargar();
  assert.equal(otro.cola.length, 0);
});
await caso('vencidos: a los 7 días se limpian', async () => {
  const d = doble({ proximasSubida: ['caro'] });
  const alm = almacenMemoria();
  let t = Date.parse('2026-11-01T12:00:00Z');
  const m = await modelo(d, { almacen: alm, ahora: () => t });
  await m.enviar(base());
  await hasta(() => m.cola[0] && m.cola[0].fallos === 1);
  t += 8 * 24 * 3600 * 1000;
  const m2 = await modelo(d, { almacen: alm, ahora: () => t });
  assert.equal(m2.cola.length, 0);
  assert.equal((await alm.listar()).length, 0);
});
await caso('sin lugar en el teléfono: sigue en memoria y sube igual', async () => {
  const d = doble();
  const alm = almacenMemoria();
  alm.agregarVideo = async () => { throw new Error('QuotaExceededError'); };
  const m = await modelo(d, { almacen: alm });
  assert.equal(await m.enviar(base()), 'ok');
  await hasta(() => d.subidas.length === 1 && !m.cola.length);
});
await caso('borrar: ok, en análisis, sin señal', async () => {
  const d = doble();
  const salidas = [{ status: 200, j: { ok: true } }, { status: 409, j: { ok: false } }];
  const m = new ModeloTecnica({ rpc: d.rpc, subir: d.subir, almacen: almacenMemoria(), token: TOK, visionUrl: 'https://x', fetch: async () => { const s = salidas.shift(); if (!s) throw new Error('red'); return { status: s.status, json: async () => s.j }; } });
  await m.cargar(); await m.refrescar();
  assert.equal(await m.borrarVideo(SID), 'ok');
  assert.equal(await m.borrarVideo(SID), 'enAnalisis');
  assert.equal(await m.borrarVideo(SID), 'sinSenal');
});
await caso('url firmada: se reusa', async () => {
  const d = doble();
  let n = 0;
  const m = new ModeloTecnica({ rpc: d.rpc, subir: d.subir, almacen: almacenMemoria(), token: TOK, visionUrl: 'https://x', fetch: async () => { n++; return { status: 200, json: async () => ({ ok: true, url: 'https://firmada' }) }; } });
  await m.cargar(); await m.refrescar();
  assert.equal(await m.urlVideo(SID), 'https://firmada');
  assert.equal(await m.urlVideo(SID), 'https://firmada');
  assert.equal(n, 1);
});

if (!process.exitCode) console.log(`test-tecnica: ${ok} casos ok`);
