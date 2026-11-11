#!/usr/bin/env node
/* =============================================================
 * test-presion.mjs — «Presión arterial» en la web.
 *  1. TODO scripts/vectores-app/presion.json contra public/js/presion.js: lo mismo que
 *     tienen que dar el kit de iOS, el de Android y el servidor.
 *  2. El modelo y la cola (public/js/presion-cola.js) contra un doble del servidor en
 *     memoria (presion/CONTRATO_APP.md), con el almacén en memoria.
 * IndexedDB real y las pantallas se prueban en el navegador.
 * USO:  node scripts/test-presion.mjs
 * ============================================================= */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import fs from 'node:fs';
const require = createRequire(import.meta.url);
const P = require('../public/js/presion.js');
const { ModeloPresion, arrancar, almacenMemoria, decodificarEstado, fechaLocal, leerMedida } = require('../public/js/presion-cola.js');
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/presion.json', import.meta.url), 'utf8'));
const { T, N } = P;

let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }
const plano = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
const igual = (sale, espera, nombre) => assert.deepEqual(plano(sale), plano(espera), nombre);

// ── 1. Vectores ──
await caso('vectores: no falta ni sobra ninguna clave', () => {
  assert.deepEqual(Object.keys(V).sort(), ['_', 'alarma', 'calza', 'espera_repeticion_s', 'limites', 'metodo', 'momento', 'nivel', 'otros', 'pasos', 'propios',
    'recordatorio_min', 'reposo_s', 'serie', 'sesion', 'sin_repetir_min', 'sintomas', 'textos', 'tramo', 'validar'].sort());
  for (const k of ['validar', 'nivel', 'tramo', 'calza', 'metodo', 'momento', 'pasos', 'sesion', 'serie']) assert.ok(V[k].length > 0, k);
});
await caso('vectores: constantes y listas de síntomas', () => {
  igual(P.LIM, V.limites);
  assert.equal(P.ESPERA_REPETICION_S, V.espera_repeticion_s);
  assert.equal(P.REPOSO_S, V.reposo_s);
  assert.equal(P.RECORDATORIO_MIN, V.recordatorio_min);
  assert.equal(P.SIN_REPETIR_MIN, V.sin_repetir_min);
  igual(P.ALARMA, V.alarma);
  igual(P.OTROS, V.otros);
  igual(P.SINTOMAS, V.sintomas);
});
await caso(`vectores: validar (${V.validar.length})`, () => { for (const v of V.validar) assert.equal(P.validarToma(v.toma), v.sale, JSON.stringify(v.toma)); });
await caso(`vectores: nivel (${V.nivel.length})`, () => { for (const v of V.nivel) assert.equal(P.nivelToma(v.toma), v.sale, JSON.stringify(v.toma)); });
await caso(`vectores: tramo (${V.tramo.length})`, () => { for (const v of V.tramo) assert.equal(P.tramoBrazo(v.cm), v.sale, String(v.cm)); });
await caso(`vectores: calza (${V.calza.length})`, () => { for (const v of V.calza) assert.equal(P.manguitoCalza(v.cm, v.aparato), v.sale, `${v.cm} ${JSON.stringify(v.aparato)}`); });
await caso(`vectores: metodo (${V.metodo.length})`, () => { for (const v of V.metodo) igual(P.metodo(v.cm, v.aparato), v.sale, `${v.cm} ${v.aparato.tipo}`); });
await caso(`vectores: momento (${V.momento.length})`, () => { for (const v of V.momento) assert.equal(P.momento(v.hora), v.sale, String(v.hora)); });
await caso(`vectores: pasos (${V.pasos.length})`, () => { for (const v of V.pasos) igual(P.pasos(v.tipo, v.variante), v.sale, v.tipo); });
await caso(`vectores: sesion (${V.sesion.length})`, () => { for (const v of V.sesion) igual(P.evaluarSesion(v.entrada), v.sale, v.nombre); });
await caso(`vectores: serie (${V.serie.length})`, () => { for (const v of V.serie) igual(P.resumenSerie(v.entrada), v.sale, v.nombre); });
await caso('vectores: textos del protocolo, uno por uno y sin que falte ninguno', () => {
  const mios = {
    ...Object.fromEntries(Object.entries(T).filter(([, v]) => typeof v !== 'function')),
    comoIzq: T.como('izq'), comoDer: T.como('der'), ortostaticaAcostado: T.ortostatica(false), ortostaticaSentado: T.ortostatica(true),
    g6Acostado: T.g6(false), g6Sentado: T.g6(true), faltan1: T.faltan(1), faltan2: T.faltan(2), avanceAlt2: T.avanceAlt(2, 3),
  };
  assert.deepEqual(Object.keys(mios).sort(), Object.keys(V.textos).sort());
  for (const k of Object.keys(V.textos)) igual(mios[k], V.textos[k], `T.${k}`);
});
await caso('vectores: textos propios, uno por uno y sin que falte ninguno', () => {
  const mios = { ...Object.fromEntries(Object.entries(N).filter(([, v]) => typeof v !== 'function')), minutoParado1: N.minutoParado(1), minutoParado3: N.minutoParado(3), graficoAlt3: N.graficoAlt(3) };
  assert.deepEqual(Object.keys(mios).sort(), Object.keys(V.propios).sort());
  for (const k of Object.keys(V.propios)) igual(mios[k], V.propios[k], `N.${k}`);
});
await caso('textos: nada de lo que el alumno no ve, ni signos prohibidos', () => {
  const hojas = [];
  const juntar = (x) => { if (typeof x === 'string') hojas.push(x); else if (x && typeof x === 'object') Object.values(x).forEach(juntar); };
  juntar(V.textos); juntar(V.propios);
  for (const s of hojas) {
    for (const mal of [/\bIA\b/, /inteligencia artificial/i, /tu coach/i, /tu entrenador/i, /hipertensi/i, /\bnormal\b/i, /riesgo/i, /no entren/i, /ya me llegó/i]) assert.ok(!mal.test(s), `${mal} en «${s}»`);
    assert.ok(!/[:;]|\s-\s|—|–/.test(s), `signo prohibido en «${s}»`);
  }
});

// ── 2. El modelo y la cola ──
const TOK = 'token-de-prueba-0123456789';
const HOY = '2026-11-10';
const T0 = Date.parse('2026-11-10T12:00:00Z');
const ZONA = 'America/Argentina/Buenos_Aires';
const APARATO = { id: 'a1', tipo: 'brazo', marca: 'Genérico', modelo: 'M1', modelo_codigo: 'X-1', manguito_min_cm: 22, manguito_max_cm: 42, manguito_validado_min_cm: null, manguito_validado_max_cm: null, validado: 'si' };
const SERIE = { id: 'serie-1', motivo: 'inicio', tipo: 'estandar', estado: 'en_curso', tomas_objetivo: 3, fecha_inicio: '2026-11-08', fecha_limite: '2026-11-14', brazo: 'izq', ortostatica: null, comparar_brazos: false, medida_pedida: false, dias: ['2026-11-08'], faltan: 2 };

/* El servidor en memoria: guarda sesiones por id (las tomas por orden no se pisan) y síntomas por id. */
function doble(ini = {}) {
  const d = {
    habilitado: true, sinRed: false, sinFuncion: false, tokenCaido: false, estadoHttp: null, okFalse: null, sinEstadoEnRespuesta: false,
    aparato: APARATO, cm: 35, serie: copia(SERIE), pendiente: null, tensiometros: null,
    sesiones: new Map(), sintomas: new Map(), llamadas: [], recibidas: [], ...ini,
  };
  d.estado = () => (d.habilitado ? {
    habilitado: true, fotos: false, hoy: HOY, aparato: d.aparato, circunferencia_brazo_cm: d.cm, serie: d.serie, pendiente: d.pendiente, tensiometros: d.tensiometros,
    sesiones: [...d.sesiones.values()].map((s) => ({ id: s.id, serie_id: s.serie_id, fecha: HOY, tipo: s.tipo, cuenta: false, tomas: s.tomas })).reverse(), campo_nuevo: 1,
  } : { habilitado: false });
  d.rpc = async (fn, p) => {
    d.llamadas.push(fn);
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    if (d.estadoHttp) { const s = d.estadoHttp; return { ok: false, status: s, codigo: '', clase: s === 429 || s >= 500 ? 'transitorio' : 'permanente' }; }
    if (d.tokenCaido) return { ok: true, data: null };
    const conEstado = (x) => (d.sinEstadoEnRespuesta ? x : { ...x, estado: d.estado() });
    switch (fn) {
      case 'mypump_presion_get': assert.equal(p.p_zona, ZONA); return { ok: true, data: d.estado() };
      case 'mypump_presion_aparato': d.aparato = { ...APARATO, ...p.p_aparato, id: 'a2', validado: 'sin_revisar' }; return { ok: true, data: conEstado({ ok: true }) };
      case 'mypump_presion_medida': if (!(p.p_cm >= 20 && p.p_cm <= 70)) return { ok: true, data: { ok: false, error: 'datos' } }; d.cm = p.p_cm; return { ok: true, data: conEstado({ ok: true }) };
      case 'mypump_presion_sesion': {
        const s = copia(p.p_sesion);
        d.recibidas.push(s);
        if (d.okFalse) return { ok: true, data: { ok: false, error: d.okFalse } };
        const prev = d.sesiones.get(s.id);
        if (prev) { for (const t of s.tomas) if (!prev.tomas.some((x) => x.orden === t.orden)) prev.tomas.push(t); Object.assign(prev, { ...s, tomas: prev.tomas }); }
        else d.sesiones.set(s.id, s);
        return { ok: true, data: conEstado({ ok: true }) };
      }
      case 'mypump_presion_sintoma': d.sintomas.set(p.p_sintoma.id, copia(p.p_sintoma)); return { ok: true, data: { ok: true } };
      default: return { ok: true, data: null };
    }
  };
  return d;
}
function copia(x) { return JSON.parse(JSON.stringify(x)); }

async function modelo(d, extra = {}) {
  const reloj = extra.reloj || { t: T0 };
  let n = extra.desdeId || 0;
  const m = new ModeloPresion({
    rpc: d.rpc, almacen: extra.almacen || almacenMemoria(), token: TOK, zona: ZONA, appVersion: 'prueba',
    esperar: () => new Promise(() => {}),          // los reintentos no corren solos: los dispara cada test
    ahora: () => reloj.t, visible: () => true, nuevoId: () => `aaaaaaaa-0000-4000-8000-${String(++n).padStart(12, '0')}`,
  });
  m.reloj = reloj;
  await m.refrescar();
  await m.cargar();
  return m;
}
const reintentarYa = async (m) => { m._reintentoProgramado = false; await m.drenar(); };
const quieto = async (m) => { for (let i = 0; i < 200 && m._drenando; i++) await new Promise((r) => setTimeout(r, 1)); };
const NO = { cafeina: false, fumo: false, comida: false, ejercicio: false };
const toma = (sis, dia, pulso = 62, irregular = false) => ({ sis, dia, pulso, latido_irregular: irregular });
/* Una toma sentado completa: preguntas en No, reposo entero y el número. */
async function hastaAnotar(m, tipo = 'estandar', previo = NO) {
  assert.equal(await m.empezar(tipo), true);
  await m.responderPrevias(previo);
  assert.equal(m.curso.etapa, 'reposo');
  assert.equal(m.restante(), 300);
  m.reloj.t += 300000;
  assert.equal(await m.tiempoCumplido(), true);
  assert.equal(m.curso.etapa, 'anotar');
}

await caso('decodificar: apagado, token caído y raro no muestran nada; lo desconocido se ignora', () => {
  assert.equal(decodificarEstado(null), null);
  assert.equal(decodificarEstado({ habilitado: false }), null);
  assert.equal(decodificarEstado({ habilitado: 'si' }), null);
  const e = decodificarEstado({ habilitado: true, raro: 1, aparato: { tipo: 'tobillo' }, serie: { id: 's', dias: ['2026-11-08', 3], tomas_objetivo: 3 },
    sesiones: [{ id: 'A', tomas: [{ orden: 2, sis: 130, dia: 80, pulso: 60 }, { orden: 1, sis: 'x' }, null] }, { sin: 'id' }], pendiente: { sesion_id: 'B', nivel: 'rara' }, tensiometros: { version: 1 } });
  assert.equal(e.aparato, null);
  assert.equal(e.fotos, false);
  assert.deepEqual(e.serie.dias, ['2026-11-08']);
  assert.equal(e.serie.faltan, 2);
  assert.equal(e.serie.brazo, 'izq');
  assert.equal(e.sesiones.length, 1);
  assert.equal(e.sesiones[0].id, 'a');
  assert.equal(e.sesiones[0].tomas.length, 1);
  assert.deepEqual(e.pendiente, { sesion_id: 'b', nivel: 'alta', desde: null });
  assert.equal(e.tensiometros, null);
});
await caso('fecha local y medida', () => {
  assert.equal(fechaLocal(Date.parse('2026-11-10T02:30:00Z'), ZONA), '2026-11-09');
  assert.equal(fechaLocal(Date.parse('2026-11-10T03:00:00Z'), ZONA), '2026-11-10');
  assert.equal(leerMedida('38,5'), 38.5);
  assert.equal(leerMedida(' 41.26 '), 41.3);
  assert.equal(leerMedida(''), null);
  assert.equal(leerMedida('abc'), null);
});

await caso('palanca apagada: no se llama a nada ni se abre el almacén', async () => {
  for (const palanca of [false, null, undefined, 'true']) {
    const d = doble();
    let abiertos = 0;
    const m = await arrancar({ palanca, rpc: d.rpc, token: TOK, zona: ZONA, abrirAlmacen: async () => { abiertos++; return almacenMemoria(); } });
    assert.equal(m, null);
    assert.deepEqual(d.llamadas, []);
    assert.equal(abiertos, 0);
  }
});
await caso('prendida pero no le toca, sin el servidor nuevo o con el token caído: una sola llamada y nada más', async () => {
  for (const ini of [{ habilitado: false }, { sinFuncion: true }, { tokenCaido: true }, { estadoHttp: 400 }]) {
    const d = doble(ini);
    let abiertos = 0;
    const m = await arrancar({ palanca: true, rpc: d.rpc, token: TOK, zona: ZONA, abrirAlmacen: async () => { abiertos++; return almacenMemoria(); } });
    assert.equal(m, null, JSON.stringify(ini));
    assert.deepEqual(d.llamadas, ['mypump_presion_get']);
    assert.equal(abiertos, 0);
  }
});
await caso('prendida y habilitada: arranca con el estado, sin más llamadas', async () => {
  const d = doble();
  const m = await arrancar({ palanca: true, rpc: d.rpc, token: TOK, zona: ZONA, abrirAlmacen: async () => almacenMemoria() });
  assert.ok(m && m.visibleEntrada);
  assert.deepEqual(d.llamadas, ['mypump_presion_get']);
  assert.equal(m.serie.faltan, 2);
  assert.equal(m.hoy, HOY);
});
await caso('sin red al abrir: solo sigue quien ya tenía un estado guardado', async () => {
  const almacen = almacenMemoria();
  const d = doble({ sinRed: true });
  assert.equal(await arrancar({ palanca: true, rpc: d.rpc, token: TOK, zona: ZONA, abrirAlmacen: async () => almacen }), null);
  d.sinRed = false;
  assert.ok(await arrancar({ palanca: true, rpc: d.rpc, token: TOK, zona: ZONA, abrirAlmacen: async () => almacen }));
  d.sinRed = true;
  const m = await arrancar({ palanca: true, rpc: d.rpc, token: TOK, zona: ZONA, abrirAlmacen: async () => almacen });
  assert.ok(m && m.estado.serie.id === 'serie-1');
});
await caso('el servidor desaparece después (404): se apaga y deja de llamar', async () => {
  const d = doble();
  const m = await modelo(d);
  d.sinFuncion = true;
  await m.refrescar();
  assert.equal(m.estado, null);
  const antes = d.llamadas.length;
  await m.drenar();
  assert.equal(d.llamadas.length, antes);
  assert.equal(await m.empezar('estandar'), false);
});

await caso('aparato y medida: ok, sin señal y error; no van a la cola', async () => {
  const d = doble({ aparato: null, cm: null });
  const m = await modelo(d);
  assert.equal(m.estado.aparato, null);
  assert.equal(await m.guardarMedida(38.5), 'ok');
  assert.equal(m.estado.circunferencia_brazo_cm, 38.5);
  assert.equal(await m.guardarMedida(19), 'error');
  assert.equal(await m.guardarMedida(NaN), 'error');
  assert.equal(await m.guardarAparato({ tipo: 'brazo', marca: ' Genérico ', modelo: 'M2', modelo_codigo: '', manguito_min_cm: 22, manguito_max_cm: 42 }), 'ok');
  assert.equal(m.estado.aparato.marca, 'Genérico');
  assert.equal(m.estado.aparato.modelo_codigo, null);
  assert.equal(await m.guardarAparato({ tipo: 'tobillo' }), 'error');
  d.sinRed = true;
  assert.equal(await m.guardarMedida(40), 'sinSenal');
  d.sinRed = false; d.estadoHttp = 503;
  assert.equal(await m.guardarMedida(40), 'sinSenal');
  d.estadoHttp = 400;
  assert.equal(await m.guardarMedida(40), 'error');
  d.estadoHttp = null; d.tokenCaido = true;
  assert.equal(await m.guardarMedida(40), 'sinSenal');
  assert.equal(m.enCola, 0);
  assert.equal(m.estado.circunferencia_brazo_cm, 38.5);
});
await caso('el reloj no sirve: no se puede empezar una toma', async () => {
  const d = doble({ aparato: { ...APARATO, tipo: 'reloj_anillo_otro' } });
  const m = await modelo(d);
  assert.equal(m.metodo.admite_tomas, false);
  assert.equal(await m.empezar('suelta'), false);
  assert.equal(m.curso, null);
});

await caso('toma común: se guarda, se manda entera y suma el día', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m);
  assert.equal(await m.anotar(toma(124, 78)), 'listo');
  await quieto(m);
  assert.equal(m.enCola, 0);
  const s = d.recibidas[0];
  assert.equal(s.tipo, 'estandar');
  assert.equal(s.serie_id, 'serie-1');
  assert.equal(s.zona_horaria, ZONA);
  assert.equal(s.plataforma, 'web');
  assert.equal(s.reposo_cumplido, true);
  assert.equal(s.temporizador_salteado, false);
  assert.deepEqual(s.previo, NO);
  assert.equal(s.texto_alumno, 'ninguno');
  assert.equal(s.lista_espera, null);
  assert.deepEqual(s.tomas.map((t) => [t.orden, t.posicion, t.brazo, t.sis, t.dia, t.pulso, t.latido_irregular, t.confirmada_por_alumno]), [[1, 'sentado', 'izq', 124, 78, 62, false, false]]);
  assert.deepEqual(m.curso.cierre, { noCuenta: false, agua: false, mareo: false, irregular: false, completa: false });
  await m.cerrar();
  assert.equal(m.curso, null);
  assert.equal(m.sesiones[0].tomas[0].sis, 124);
});
await caso('la tercera toma válida completa la serie', async () => {
  const d = doble({ serie: { ...SERIE, dias: ['2026-11-08', '2026-11-09'], faltan: 1 } });
  const m = await modelo(d);
  await hastaAnotar(m);
  await m.anotar(toma(118, 76, 60, true));
  assert.equal(m.curso.cierre.completa, true);
  assert.equal(m.curso.cierre.irregular, true);
});
await caso('con un Sí en las preguntas o salteando el reposo, la toma no cuenta', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m, 'estandar', { ...NO, cafeina: true });
  assert.equal(await m.anotar(toma(124, 78)), 'listo');
  assert.equal(m.curso.cierre.noCuenta, true);
  assert.equal(m.curso.sesion.texto_alumno, 'toma_no_cuenta');
  await m.cerrar();
  await m.empezar('estandar');
  await m.responderPrevias(NO);
  await m.saltearReposo();
  assert.equal(m.curso.etapa, 'anotar');
  await m.anotar(toma(124, 78));
  assert.equal(m.curso.sesion.temporizador_salteado, true);
  assert.equal(m.curso.sesion.reposo_cumplido, false);
  assert.equal(m.curso.cierre.noCuenta, true);
  assert.equal(m.curso.cierre.completa, false);
});
await caso('«Esperar» en las preguntas: no queda ni se manda nada', async () => {
  const d = doble();
  const m = await modelo(d);
  await m.empezar('estandar');
  const antes = d.llamadas.length;
  await m.descartar();
  assert.equal(m.curso, null);
  assert.equal(m.enCola, 0);
  assert.equal(d.llamadas.length, antes);
});
await caso('número imposible no entra; el de alta pide confirmar y queda marcado', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m, 'suelta');
  assert.equal(await m.anotar(toma(300, 80)), 'imposible');
  assert.equal(await m.anotar(toma(100, 95)), 'imposible');
  assert.equal(await m.anotar({ sis: 120.5, dia: 80, pulso: 60 }), 'imposible');
  assert.equal(m.curso.sesion.tomas.length, 0);
  assert.equal(await m.anotar(toma(165, 95)), 'confirmar');
  assert.equal(m.curso.sesion.tomas.length, 0);
  assert.equal(m.enCola, 0);
  assert.equal(await m.anotar(toma(165, 95), true), 'espera');
  assert.equal(m.curso.sesion.tomas[0].confirmada_por_alumno, true);
  assert.equal(m.curso.lista, false);
  assert.equal(m.curso.sesion.texto_alumno, 'quedate_sentado_5min');
  assert.equal(m.curso.sesion.serie_id, null);
});
await caso('160/100: espera de 5 minutos y otra toma; la sesión viaja dos veces con el mismo id y no se duplica', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m);
  await m.anotar(toma(165, 95), true);
  await quieto(m);
  assert.equal(m.restante(), 300);
  assert.equal(await m.repetir(), false);          // todavía corre el reloj
  m.reloj.t += 299000;
  assert.equal(m.restante(), 1);
  m.reloj.t += 1000;
  assert.equal(await m.repetir(), true);
  assert.equal(await m.anotar(toma(150, 92)), 'listo');
  await quieto(m);
  assert.equal(d.sesiones.size, 1);
  assert.equal(d.recibidas.length, 2);
  assert.equal(d.recibidas[0].id, d.recibidas[1].id);
  assert.deepEqual([...d.sesiones.values()][0].tomas.map((t) => t.orden), [1, 2]);
  assert.equal(m.enCola, 0);
});
await caso('180/120: espera con la lista; todos en No sigue, y si la repetición sigue alta es guardia por presión', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m);
  assert.equal(await m.anotar(toma(185, 110), true), 'espera');
  assert.equal(m.curso.lista, true);
  assert.equal(m.curso.sesion.texto_alumno, 'lista_sintomas_espera');
  assert.equal(m.pendiente.conLista, true);
  for (const k of P.ALARMA.slice(0, 7)) assert.equal(await m.responderLista(k, false), 'espera');
  assert.equal(m.curso.sesion.lista_espera, null);          // sin contestar todo no cuenta como «no»
  await m.responderLista(P.ALARMA[7], false);
  assert.equal(m.curso.sesion.lista_espera, 'no');
  await quieto(m);
  assert.equal(d.recibidas[d.recibidas.length - 1].lista_espera, 'no');
  m.reloj.t += 300000;
  await m.repetir();
  assert.equal(await m.anotar(toma(182, 112), true), 'guardia');
  assert.equal(m.curso.guardia, 'presion');
  assert.equal(m.curso.sesion.texto_alumno, 'guardia_presion');
});
await caso('180/120 con un Sí en la lista: guardia por síntomas en el acto, también sin red', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m);
  d.sinRed = true;
  await m.anotar(toma(190, 100), true);
  assert.equal(await m.responderLista('dolor_pecho', true), 'guardia');
  assert.equal(m.curso.guardia, 'sintomas');
  assert.equal(m.curso.sesion.lista_espera, 'si');
  assert.deepEqual(m.curso.sesion.sintomas, ['dolor_pecho']);
  await quieto(m);
  assert.equal(m.enCola, 1);                        // quedó guardada
  d.sinRed = false;
  await reintentarYa(m);
  assert.equal(m.enCola, 0);
  assert.equal([...d.sesiones.values()][0].texto_alumno, 'guardia_sintomas');
});
await caso('pulso de 120 o más, de 40 o menos, o alta menor de 90: primero la hoja de síntomas', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m, 'suelta');
  assert.equal(await m.anotar(toma(120, 80, 125), true), 'sintomas');
  assert.equal(m.curso.etapa, 'sintomas');
  await quieto(m);
  assert.equal(d.recibidas.length, 1);              // el número ya viajó
  assert.equal(await m.responderSintomas(['palpitaciones'], '  me late fuerte  '), 'guardia');
  assert.equal(m.curso.guardia, 'sintomas');
  assert.equal(m.curso.sesion.nota, 'me late fuerte');
  await m.cerrar();
  await hastaAnotar(m, 'suelta');
  assert.equal(await m.anotar(toma(88, 58, 70)), 'sintomas');
  assert.equal(await m.responderSintomas(['mareo_al_pararse'], ''), 'listo');
  assert.equal(m.curso.cierre.agua, true);
  await m.cerrar();
  await hastaAnotar(m, 'suelta');
  assert.equal(await m.anotar(toma(110, 70, 38), true), 'sintomas');
  assert.equal(await m.responderSintomas([], ''), 'listo');
  assert.equal(m.curso.cierre.agua, false);
});

await caso('sin red: queda en la cola, se ve en «Tus tomas» y sale al volver la señal', async () => {
  const d = doble();
  const almacen = almacenMemoria();
  const m = await modelo(d, { almacen });
  d.sinRed = true;
  await hastaAnotar(m);
  assert.equal(await m.anotar(toma(124, 78)), 'listo');
  await quieto(m);
  assert.equal(m.enCola, 1);
  assert.equal((await almacen.listar()).length, 1);
  assert.equal(m.sesiones[0].tomas[0].sis, 124);
  assert.equal(m.serie.faltan, 1);                  // la toma en cola ya suma su día
  assert.equal(m.hoyListo, true);
  await m.cerrar();
  // Otra visita, todavía sin red: sigue ahí.
  const m2 = await modelo(d, { almacen });
  assert.equal(m2.enCola, 1);
  d.sinRed = false;
  await m2.refrescar();
  await m2.reanudar();
  assert.equal(m2.enCola, 0);
  assert.equal(d.sesiones.size, 1);
  assert.equal((await almacen.listar()).length, 0);
});
await caso('5xx y 429 no gastan nada: quedan y se reintentan', async () => {
  for (const http of [500, 503, 429]) {
    const d = doble();
    const m = await modelo(d);
    await hastaAnotar(m);
    d.estadoHttp = http;
    await m.anotar(toma(124, 78));
    await quieto(m);
    assert.equal(m.enCola, 1, String(http));
    assert.ok(m.estado, 'sigue prendida');
    d.estadoHttp = null;
    await reintentarYa(m);
    assert.equal(m.enCola, 0);
    assert.equal(d.sesiones.size, 1);
  }
});
await caso('4xx que no es 429: se descarta y se refresca el estado', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m);
  d.rpcReal = d.rpc;
  let gets = 0;
  m.rpc = async (fn, p) => {
    if (fn === 'mypump_presion_sesion') { d.llamadas.push(fn); return { ok: false, status: 400, codigo: '22023', clase: 'permanente' }; }
    if (fn === 'mypump_presion_get') gets++;
    return d.rpcReal(fn, p);
  };
  await m.anotar(toma(124, 78));
  await quieto(m);
  assert.equal(m.enCola, 0);
  assert.equal(d.sesiones.size, 0);
  assert.equal(gets, 1);
  assert.ok(m.estado);
});
await caso('ok:false del servidor (serie cerrada, aparato, datos, imposible): se descarta y se refresca', async () => {
  for (const error of ['serie', 'aparato', 'datos', 'imposible']) {
    const d = doble({ okFalse: error });
    const m = await modelo(d);
    await hastaAnotar(m);
    const gets = () => d.llamadas.filter((x) => x === 'mypump_presion_get').length;
    const antes = gets();
    await m.anotar(toma(124, 78));
    await quieto(m);
    assert.equal(m.enCola, 0, error);
    assert.equal(gets(), antes + 1);
    assert.equal(m.curso.etapa, 'listo');          // lo que vio el alumno no cambia
  }
});
await caso('token caído: no se pierde nada y no se sigue llamando', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m);
  d.tokenCaido = true;
  await m.anotar(toma(124, 78));
  await quieto(m);
  assert.equal(m.enCola, 1);
  const n = d.llamadas.length;
  assert.equal(m._reintentoProgramado, false);
  d.tokenCaido = false;
  await m.reanudar();
  assert.equal(m.enCola, 0);
  assert.ok(d.llamadas.length > n);
});
await caso('idempotencia: reenviar la misma sesión y el mismo síntoma no duplica; el orden se respeta', async () => {
  const d = doble();
  const m = await modelo(d);
  d.sinRed = true;
  await hastaAnotar(m);
  await m.anotar(toma(165, 95), true);
  assert.equal(await m.marcarSintoma(['palpitaciones'], 'nota'), 'recibido');
  m.reloj.t += 300000;
  await m.repetir();
  await m.anotar(toma(150, 90));
  await quieto(m);
  assert.deepEqual(m.cola.map((f) => f.clase), ['sesion', 'sintoma']);        // una fila por sesión, en el orden en que nacieron
  assert.equal(m.cola[0].cuerpo.tomas.length, 2);
  d.sinRed = false;
  const filas = copia(m.cola);
  await reintentarYa(m);
  assert.equal(m.enCola, 0);
  assert.deepEqual(d.llamadas.slice(-2), ['mypump_presion_sesion', 'mypump_presion_sintoma']);
  // La respuesta se perdió y todo sale otra vez: el servidor no duplica.
  for (const f of filas) await m._poner(f);
  await reintentarYa(m);
  assert.equal(d.sesiones.size, 1);
  assert.equal(d.sintomas.size, 1);
  assert.deepEqual([...d.sesiones.values()][0].tomas.map((t) => t.orden), [1, 2]);
  const s = [...d.sintomas.values()][0];
  assert.equal(s.contexto, 'boton');
  assert.equal(s.sesion_id, [...d.sesiones.keys()][0]);
  assert.deepEqual(s.codigos, ['palpitaciones']);
  assert.equal(s.sin_sintomas_en_lista, null);
  assert.equal(s.zona_horaria, ZONA);
});
await caso('una toma anotada mientras viajaba la anterior no se pierde', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m);
  const real = m.rpc;
  let soltar;
  const tapon = new Promise((r) => { soltar = r; });
  let primera = true;
  m.rpc = async (fn, p) => { if (fn === 'mypump_presion_sesion' && primera) { primera = false; const c = copia(p); await tapon; return real(fn, c); } return real(fn, p); };
  await m.anotar(toma(165, 95), true);          // sale la primera y queda en viaje
  m.reloj.t += 300000;
  await m.repetir();
  await m.anotar(toma(150, 90));                // se anota la segunda mientras tanto
  soltar();
  await quieto(m);
  await new Promise((r) => setTimeout(r, 5));
  await quieto(m);
  assert.equal(m.enCola, 0);
  assert.deepEqual([...d.sesiones.values()][0].tomas.map((t) => t.orden), [1, 2]);
});

await caso('la sesión en curso sobrevive a recargar: el temporizador sigue por hora de fin', async () => {
  const d = doble();
  const almacen = almacenMemoria();
  const reloj = { t: T0 };
  const m = await modelo(d, { almacen, reloj });
  await m.empezar('estandar');
  await m.responderPrevias(NO);
  reloj.t += 120000;
  const m2 = await modelo(d, { almacen, reloj, desdeId: 10 });
  assert.equal(m2.curso.etapa, 'reposo');
  assert.equal(m2.restante(), 180);
  reloj.t += 400000;                                // estuvo en otra pestaña más de lo que faltaba
  assert.equal(m2.restante(), 0);
  await m2.tiempoCumplido();
  assert.equal(m2.curso.sesion.reposo_cumplido, true);
  await m2.anotar(toma(170, 100), true);
  // Recarga en plena espera de la repetición.
  const m3 = await modelo(d, { almacen, reloj, desdeId: 20 });
  assert.equal(m3.curso.etapa, 'espera');
  assert.equal(m3.restante(), 300);
  assert.equal(m3.esperaVencida, false);
  reloj.t += 11 * 60000;
  assert.equal(m3.esperaVencida, true);             // pasados los 10 minutos es el recordatorio
  assert.deepEqual(m3.pendiente, { sesion_id: m3.curso.sesion.id, nivel: 'alta', local: true, conLista: false });
  assert.equal(await m3.repetir(), true);
  assert.equal(await m3.anotar(toma(140, 88)), 'listo');
  await quieto(m3);
  assert.equal(d.sesiones.size, 1);
  assert.deepEqual([...d.sesiones.values()][0].tomas.map((t) => t.orden), [1, 2]);
});
await caso('una sesión en curso de otro día no se retoma', async () => {
  const d = doble();
  const almacen = almacenMemoria();
  const reloj = { t: T0 - 24 * 3600000 };
  const m = await modelo(d, { almacen, reloj });
  await m.empezar('estandar');
  assert.ok(m.curso);
  reloj.t = T0;
  const m2 = await modelo(d, { almacen, reloj });
  assert.equal(m2.curso, null);
  assert.equal(await almacen.leerKV(m2._kvCurso), undefined);
});
await caso('otra cuenta en el mismo teléfono no ve la cola ni la sesión en curso', async () => {
  const d = doble({ sinRed: false });
  const almacen = almacenMemoria();
  const m = await modelo(d, { almacen });
  d.sinRed = true;
  await hastaAnotar(m);
  await m.anotar(toma(165, 95), true);
  await quieto(m);
  d.sinRed = false;
  const otro = new ModeloPresion({ rpc: d.rpc, almacen, token: 'otro-token-9876543210', zona: ZONA, ahora: () => T0, esperar: () => new Promise(() => {}) });
  await otro.refrescar();
  await otro.cargar();
  assert.equal(otro.enCola, 0);
  assert.equal(otro.curso, null);
});

await caso('repetición pendiente que avisa el servidor (otra sesión del teléfono): se retoma con el mismo id y solo viaja lo que se sabe', async () => {
  const SID = 'bbbbbbbb-0000-4000-8000-000000000001';
  const d = doble({ pendiente: { sesion_id: SID, nivel: 'urgencia', desde: '2026-11-10T11:40:00Z' } });
  d.sesiones.set(SID, { id: SID, serie_id: 'serie-1', tipo: 'estandar', previo: NO, reposo_cumplido: true, tomas: [{ orden: 1, posicion: 'sentado', sis: 186, dia: 108, pulso: 70, latido_irregular: false }] });
  const m = await modelo(d);
  assert.deepEqual(m.pendiente, { sesion_id: SID, nivel: 'urgencia', local: false, conLista: true });
  assert.equal(await m.responderRecordatorio({ dolor_pecho: 'no' }), 'falta');
  assert.equal(await m.responderRecordatorio(Object.fromEntries(P.ALARMA.map((k) => [k, 'no']))), 'sigue');
  await quieto(m);
  let s = [...d.sintomas.values()][0];
  assert.equal(s.contexto, 'recordatorio_180_120');
  assert.equal(s.sesion_id, SID);
  assert.equal(s.sin_sintomas_en_lista, true);
  assert.deepEqual(s.codigos, []);
  assert.equal(await m.retomarDelServidor(), true);
  assert.equal(m.curso.etapa, 'anotar');
  assert.equal(await m.anotar(toma(184, 110), true), 'guardia');          // dos seguidas de 180/120
  assert.equal(m.curso.guardia, 'presion');
  await quieto(m);
  const enviada = d.recibidas[d.recibidas.length - 1];
  assert.equal(enviada.id, SID);
  assert.ok(!('previo' in enviada) && !('reposo_cumplido' in enviada));
  assert.deepEqual(d.sesiones.get(SID).tomas.map((t) => t.orden), [1, 2]);
  assert.deepEqual(d.sesiones.get(SID).previo, NO);                       // lo que ya tenía el servidor no se pisa en el doble
  // Con un Sí en la lista del recordatorio: guardia y el síntoma viaja.
  const d2 = doble({ pendiente: { sesion_id: SID, nivel: 'urgencia', desde: null } });
  const m2 = await modelo(d2);
  assert.equal(await m2.responderRecordatorio({ confusion: 'si' }), 'guardia');
  await quieto(m2);
  s = [...d2.sintomas.values()][0];
  assert.deepEqual(s.codigos, ['confusion']);
  assert.equal(s.sin_sintomas_en_lista, false);
});

await caso('marcar un síntoma sin toma: alarma es guardia, otro queda anotado; nunca pide medir', async () => {
  const d = doble({ aparato: null, serie: null });
  const m = await modelo(d);
  assert.equal(await m.marcarSintoma(['falta_aire', 'inventado'], ''), 'guardia');
  assert.equal(await m.marcarSintoma(['vomitos_diarrea'], 'desde ayer'), 'recibido');
  await quieto(m);
  const xs = [...d.sintomas.values()];
  assert.equal(xs.length, 2);
  assert.deepEqual(xs[0].codigos, ['falta_aire']);
  assert.equal(xs[0].sesion_id, null);
  assert.equal(xs[1].nota, 'desde ayer');
  assert.equal(d.sesiones.size, 0);
});
await caso('síntoma de alarma con una toma en curso: guardia y la sesión lo lleva', async () => {
  const d = doble();
  const m = await modelo(d);
  await hastaAnotar(m);
  await m.anotar(toma(165, 95), true);
  assert.equal(await m.marcarSintoma(['debilidad_un_lado'], ''), 'guardia');
  assert.equal(m.curso.etapa, 'guardia');
  assert.equal(m.curso.guardia, 'sintomas');
  await quieto(m);
  assert.deepEqual([...d.sesiones.values()][0].sintomas, ['debilidad_un_lado']);
  assert.equal(d.sintomas.size, 1);
});

await caso('bajo efecto: hora de la dosis y entreno; si entrenó no cuenta', async () => {
  const d = doble({ serie: { ...SERIE, tipo: 'bajo_efecto' } });
  const m = await modelo(d);
  await m.empezar('bajo_efecto');
  await m.responderBajoEfecto('08:30', false);
  m.reloj.t += 300000;
  await m.tiempoCumplido();
  assert.equal(await m.anotar(toma(130, 82)), 'listo');
  assert.equal(m.curso.sesion.dosis_estimulante_hora, '08:30');
  assert.equal(m.curso.sesion.entreno_entre_dosis_y_toma, false);
  assert.equal(m.curso.cierre.noCuenta, false);
  await quieto(m);
  await m.cerrar();
  await m.empezar('bajo_efecto');
  await m.responderBajoEfecto('cualquiera', true);
  m.reloj.t += 300000;
  await m.tiempoCumplido();
  await m.anotar(toma(130, 82));
  assert.equal(m.curso.sesion.dosis_estimulante_hora, null);
  assert.equal(m.curso.cierre.noCuenta, true);
});
await caso('ortostática: 3 pasos con su reloj; el minuto 3 se cuenta desde que se paró', async () => {
  const d = doble({ serie: { ...SERIE, ortostatica: 'acostado_parado' } });
  const m = await modelo(d);
  await m.empezar('ortostatica');
  assert.equal(m.curso.etapa, 'intro');
  assert.equal(m.curso.variante, 'acostado_parado');
  await m.empezarPaso();
  assert.equal(m.restante(), 300);
  await m.saltearReposo();                          // en las guiadas no se saltea
  assert.equal(m.curso.etapa, 'reposo');
  m.reloj.t += 300000;
  await m.tiempoCumplido();
  assert.equal(await m.anotar(toma(124, 78)), 'parate');
  await m.empezarPaso();
  assert.equal(m.restante(), 60);
  m.reloj.t += 60000;
  await m.tiempoCumplido();
  m.reloj.t += 45000;                               // tardó 45 segundos en medirse y anotar
  assert.equal(await m.anotar(toma(118, 80, 70)), 'reposo');
  assert.equal(m.restante(), 75);                   // 120 desde el minuto 1, no desde ahora
  m.reloj.t += 75000;
  await m.tiempoCumplido();
  assert.equal(await m.anotar(toma(116, 80, 72)), 'listo');
  await quieto(m);
  const s = [...d.sesiones.values()][0];
  assert.equal(s.tipo, 'ortostatica');
  assert.deepEqual(s.tomas.map((t) => [t.posicion, t.minutos_de_pie]), [['acostado', null], ['de_pie', 1], ['de_pie', 3]]);
  assert.equal(m.serie.ortostatica, 'acostado_parado');           // el doble no la da por hecha: manda el servidor
});
await caso('ortostática: «Me mareé» corta ahí y avisa', async () => {
  const d = doble({ serie: { ...SERIE, ortostatica: 'sentado_parado' } });
  const m = await modelo(d);
  await m.empezar('ortostatica');
  assert.equal(m.curso.pasos[0].posicion, 'sentado');
  await m.empezarPaso();
  m.reloj.t += 300000;
  await m.tiempoCumplido();
  await m.anotar(toma(124, 78));
  await m.empezarPaso();
  await m.meMaree();
  assert.equal(m.curso.etapa, 'listo');
  assert.equal(m.curso.cierre.mareo, true);
  await quieto(m);
  const s = [...d.sesiones.values()][0];
  assert.deepEqual(s.sintomas, ['mareo_al_pararse']);
  assert.equal(s.texto_alumno, 'quedate_sentado_ortostatica');
  assert.equal(s.tomas.length, 1);
});
await caso('comparación de brazos: izquierdo, derecho, derecho, izquierdo, sin pedir repetición', async () => {
  const d = doble({ serie: { ...SERIE, comparar_brazos: true } });
  const m = await modelo(d);
  d.sinRed = true;
  await m.empezar('comparacion_brazos');
  await m.empezarPaso();
  assert.equal(m.restante(), 300);
  const esperas = [];
  for (const v of [[165, 95], [150, 90], [150, 90], [150, 90]]) {
    esperas.push(m.restante());
    m.reloj.t += m.restante() * 1000;
    await m.tiempoCumplido();
    await m.anotar(toma(v[0], v[1]), true);
  }
  assert.deepEqual(esperas, [300, 60, 60, 60]);
  assert.equal(m.curso.etapa, 'listo');
  assert.deepEqual(m.curso.sesion.tomas.map((t) => t.brazo), ['izq', 'der', 'der', 'izq']);
  await quieto(m);
  assert.equal(m.serie.comparar_brazos, false);     // con la comparación en la cola ya no se vuelve a pedir
  assert.equal(m.serie.faltan, 2);                  // y no suma al avance
});

// ── 3. La tarjeta de arriba (CONTRATO_APP.md, «Fácil de encontrar y súper visible») ──
await caso('tarjeta: sin serie y sin pendiente no hay; apagada tampoco', async () => {
  const m = await modelo(doble({ serie: null }));
  assert.equal(m.tarjeta, null);
  m.apagar();
  assert.equal(m.tarjeta, null);
});
await caso('tarjeta: los estados, en el orden del contrato', async () => {
  // serie abierta, con aparato y sin toma hoy: la toma de hoy, con el avance
  let m = await modelo(doble());
  igual(m.tarjeta, { estado: 'toma', hechas: 1, total: 3, faltan: 2, primera: false });
  // todavía ninguna: se avisa que son 3
  m = await modelo(doble({ serie: { ...SERIE, dias: [], faltan: 3 } }));
  igual(m.tarjeta, { estado: 'toma', hechas: 0, total: 3, faltan: 3, primera: true });
  // sin aparato, con reloj o con la medida pedida: primero preparar
  for (const ini of [{ aparato: null }, { aparato: { ...APARATO, tipo: 'reloj_anillo_otro' } }, { serie: { ...SERIE, medida_pedida: true } }]) {
    m = await modelo(doble(ini));
    assert.equal(m.tarjeta.estado, 'preparar', JSON.stringify(ini));
  }
  // la de hoy hecha: avance y nada que tocar
  m = await modelo(doble({ serie: { ...SERIE, dias: ['2026-11-09', HOY], faltan: 1 } }));
  igual(m.tarjeta, { estado: 'hoyListo', hechas: 2, total: 3, faltan: 1, primera: false });
  // la repetición pendiente gana a todo, también sin serie y sin aparato
  for (const ini of [{}, { serie: null }, { serie: { ...SERIE, medida_pedida: true } }, { serie: { ...SERIE, dias: [HOY], faltan: 2 } }]) {
    m = await modelo(doble({ ...ini, pendiente: { sesion_id: 'aaaaaaaa-0000-4000-8000-000000000099', nivel: 'alta', desde: '2026-11-10T11:00:00Z' } }));
    igual(m.tarjeta, { estado: 'repetir' }, JSON.stringify(ini));
  }
});
await caso('tarjeta: sigue a lo anotado sin señal (la de hoy pasa a hecha) y a la repetición en curso', async () => {
  const d = doble();
  const m = await modelo(d);
  d.sinRed = true;
  await hastaAnotar(m);
  assert.equal(m.tarjeta.estado, 'toma');
  await m.anotar(toma(124, 78), false);
  assert.equal(m.curso.etapa, 'listo');
  igual(m.tarjeta, { estado: 'hoyListo', hechas: 2, total: 3, faltan: 1, primera: false });
  await m.cerrar();
  assert.equal(m.tarjeta.estado, 'hoyListo');
  // una toma que pide repetición: la tarjeta lleva a repetir
  const m2 = await modelo(doble());
  await hastaAnotar(m2);
  await m2.anotar(toma(166, 98), true);
  assert.equal(m2.curso.etapa, 'espera');
  igual(m2.tarjeta, { estado: 'repetir' });
});
await caso('tarjeta: los textos existen y son de T y N', () => {
  for (const k of ['tarjeta', 'tarjetaPreparar', 'tarjetaSerie', 'empezar', 'repetir', 'tomaDeHoy', 'hoyListo']) assert.ok(typeof N[k] === 'string' && N[k].length > 0, k);
  assert.ok(T.repetirPendiente && T.faltan(2));
});

if (!process.exitCode) console.log(`test-presion: ${ok} casos ok`);
