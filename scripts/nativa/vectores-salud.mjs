#!/usr/bin/env node
/* =============================================================
   vectores-salud.mjs — Salud de iPhone: el bridge de la web es la fuente de verdad

   Corre el healthkit-bridge.js REAL de origin/main (sync, backfill y connect, sin sacar ni
   reescribir una sola función) contra una imitación fiel del plugin que lo alimenta en la app
   de hoy (@capgo/capacitor-health 8.9.3, ios/Sources/HealthPlugin/Health.swift), y graba:

     - cada consulta que el bridge le hizo al plugin, con sus argumentos exactos (ventanas al
       milisegundo) y lo que el plugin le devolvió;
     - cada lote que mandó a mypump_ingest_salud y mypump_ingest_entrenos, con la respuesta;
     - lo que devolvió sync()/backfill()/connect() y cómo quedó su localStorage.

   La nativa (Swift Testing; JUnit en Android) reproduce las respuestas del plugin en el mismo
   orden y exige: las MISMAS consultas, los MISMOS lotes y el MISMO estado final. O sea que el
   vector prueba a la vez las ventanas, la agregación (sueño, HRV, agregados, muestras y
   entrenos), el orden de los registros, los lotes y los cursores del historial.

   La imitación del plugin sigue su código, no a la documentación:
     - readSamples: HKSampleQuery con predicateForSamples(options: []) — la muestra entra si
       endDate >= desde y startDate < hasta —, orden por startDate y `limit`. El sueño sale con
       value = minutos, sleepState (inBed, asleep, awake, light, deep, rem) y `stages` con UNA
       etapa igual a la muestra (desde la 8.x; es lo que hace que el bridge sume un 'inbed' por
       muestra). Un valor de sueño que el plugin no conoce sale sin sleepState ni stages.
     - queryAggregated: HKStatisticsCollectionQuery anclada a la medianoche local de `desde`,
       .strictStartDate (startDate >= desde y < hasta), un balde por día, solo los que tienen
       valor. Las muestras de los casos no cruzan la medianoche ni mezclan fuentes: así la suma
       por día de la imitación es exactamente la de HealthKit.
     - queryWorkouts: límite 100 y orden DESCENDENTE (el bridge no pasa ninguno de los dos) y
       `duration` truncada a segundos enteros (Int(workout.duration)).
     - Las unidades son las `defaultUnit` del plugin: HRV en ms, SpO2 y grasa en fracción 0-1,
       distancia en metros, peso en kg, temperaturas en °C, glucosa en mg/dL.

   Lo que esto NO prueba es que HealthKit conteste lo mismo a la nativa que al plugin: eso lo
   cubre la prueba en el simulador (scripts/nativa/salud-banco.sh).

   Las muestras base salen de public/js/salud-sintetica.js (el mismo generador del banco de
   pruebas de la web); encima se agregan casos armados a mano para cada borde conocido.

   Salidas: apps/shared/vectores/salud_sync.json, salud_backfill.json y salud_conectar.json

   Uso: node scripts/nativa/vectores-salud.mjs
   ============================================================= */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const REF = process.env.VECTORES_REF || 'origin/main';
const mostrar = (ruta) => execFileSync('git', ['show', `${REF}:${ruta}`], { cwd: RAIZ, maxBuffer: 64 * 1024 * 1024 }).toString();
const commit = execFileSync('git', ['rev-parse', '--short', REF], { cwd: RAIZ }).toString().trim();
const BRIDGE = mostrar('public/js/healthkit-bridge.js');
const SINTETICA = mostrar('public/js/salud-sintetica.js');

// ── Reloj falso ──────────────────────────────────────────────────────
// El bridge usa `new Date()` para "ahora" (la punta de la ventana, el sello de la última sync, el
// throttle del historial). Con un reloj fijo, el vector no depende del día en que se generó.
const DateReal = Date;
let AHORA = null;
class DateFalsa extends DateReal {
  constructor(...a) { if (a.length === 0 && AHORA != null) super(AHORA); else super(...a); }
  static now() { return AHORA != null ? AHORA : DateReal.now(); }
}
globalThis.Date = DateFalsa;

// La zona horaria se cambia por caso (Node la relee al asignar process.env.TZ).
function zona(tz) { process.env.TZ = tz; }
zona('America/Argentina/Buenos_Aires');

// ── Navegador mínimo, como scripts/test-bridge.mjs ───────────────────
const store = {};
globalThis.localStorage = {
  getItem: (k) => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: (k) => { delete store[k]; },
};
Object.defineProperty(globalThis, 'navigator', {
  value: { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X)' }, writable: true, configurable: true,
});
globalThis.document = { addEventListener() {}, hidden: false };
globalThis.window = globalThis;
globalThis.addEventListener = () => {};
const AVISOS = [];
console.warn = (...a) => AVISOS.push(a.map(String).join(' '));

// ── El plugin, imitado ───────────────────────────────────────────────
// Los 23 casos del enum HealthDataType de Health.swift (check-healthkit-tipos.mjs los coteja contra el
// plugin instalado). 'workouts' lo maneja aparte parseTypesWithWorkouts.
const TIPOS_PLUGIN = ['steps', 'distance', 'calories', 'heartRate', 'weight', 'sleep', 'respiratoryRate', 'oxygenSaturation',
  'restingHeartRate', 'heartRateVariability', 'bloodPressure', 'bloodGlucose', 'bodyTemperature', 'height', 'flightsClimbed',
  'exerciseTime', 'distanceCycling', 'bodyFat', 'basalBodyTemperature', 'appleSleepingWristTemperature', 'basalCalories',
  'totalCalories', 'mindfulness'];
// queryAggregated: la matriz chica que acepta el plugin (Health.swift:1480).
const MATRIZ_AGG = { steps: ['sum'], distance: ['sum'], calories: ['sum'], heartRate: ['average', 'min', 'max'],
  weight: ['average', 'min', 'max'], restingHeartRate: ['average', 'min', 'max'] };
// sleepStateFromValue (Health.swift:1072): HKCategoryValueSleepAnalysis → texto.
const ESTADO_SUENO = { 0: 'inBed', 1: 'asleep', 2: 'awake', 3: 'light', 4: 'deep', 5: 'rem' };

let ALM = null;            // el "HealthKit" del caso
let LOG = [];              // consultas al plugin, en orden
let FALLAS = {};           // dataType → error que tira el plugin (para probar los catch del bridge)
let RECHAZA_PERMISO = [];  // tipos que hacen fallar requestAuthorization (iOS viejo, tipo desconocido)
const iso = (ms) => new DateReal(ms).toISOString();
const ms = (s) => new DateReal(s).getTime();
const fuente = (i) => ALM.fuentes[i];
const solapa = (ini, fin, d, h) => fin >= d && ini < h;   // predicateForSamples(options: [])
const estricto = (ini, d, h) => ini >= d && ini < h;      // .strictStartDate
const ordenar = (xs, sentido) => xs.slice().sort((a, b) => sentido * (a.ini - b.ini));   // estable, como HealthKit

/* Un tipo que no está en el enum tira cualquier pedido (parseTypesWithWorkouts). Uno que está en el enum pero
 * que el sistema no tiene (RECHAZA_PERMISO: un tipo de iOS 16 en un iOS 15) tira requestAuthorization entero
 * (readAuthorizationObjectTypes sin try?), pero checkAuthorization lo lista como denegado sin error. */
function tipoDesconocido(tipos) {
  const malo = tipos.find((t) => t !== 'workouts' && !TIPOS_PLUGIN.includes(t));
  return malo ? `Unsupported health data type: ${malo}.` : null;
}

const Health = {
  async isAvailable() {
    LOG.push({ m: 'isAvailable' });
    return { available: true, platform: 'ios' };
  },
  async requestAuthorization({ read = [], write = [] }) {
    const e = { m: 'requestAuthorization', read: read.slice(), write: write.slice() };
    LOG.push(e);
    const viejo = read.concat(write).find((t) => RECHAZA_PERMISO.includes(t));
    const err = tipoDesconocido(read.concat(write)) || (viejo ? `The health data type ${viejo} is not available on this device.` : null);
    if (err) { e.error = err; throw new Error(err); }
    return { readAuthorized: read.slice(), readDenied: [], writeAuthorized: [], writeDenied: [] };
  },
  async checkAuthorization({ read = [], write = [] }) {
    const e = { m: 'checkAuthorization', read: read.slice() };
    LOG.push(e);
    const err = tipoDesconocido(read.concat(write));
    if (err) { e.error = err; throw new Error(err); }
    // HealthKit nunca dice si hay permiso de LECTURA: todo lo ya preguntado sale como "autorizado".
    const no = read.filter((x) => RECHAZA_PERMISO.includes(x));
    e.r = { readAuthorized: read.filter((x) => !no.includes(x)), readDenied: no };
    return { ...e.r, writeAuthorized: [], writeDenied: [] };
  },
  async readSamples({ dataType, startDate, endDate, limit, ascending }) {
    const d = ms(startDate), h = ms(endDate);
    const e = { m: 'readSamples', dataType, desde: d, hasta: h, limite: limit ?? 100, asc: !!ascending };
    LOG.push(e);
    if (FALLAS[dataType]) { e.error = FALLAS[dataType]; throw new Error(FALLAS[dataType]); }
    if (!TIPOS_PLUGIN.includes(dataType)) { e.error = `Unsupported health data type: ${dataType}.`; throw new Error(e.error); }
    let filas;
    if (dataType === 'sleep') {
      filas = (ALM.sueno || []).map(([ini, fin, v, f]) => ({ ini, fin, f, valor: (fin - ini) / 60000, estado: ESTADO_SUENO[v] ?? null }));
    } else if (dataType === 'mindfulness') {
      filas = (ALM.mindful || []).map(([ini, fin, f]) => ({ ini, fin, f, valor: (fin - ini) / 60000 }));
    } else {
      filas = (ALM.cantidades[dataType] || []).map(([ini, fin, valor, f]) => ({ ini, fin, f, valor }));
    }
    filas = ordenar(filas.filter((s) => solapa(s.ini, s.fin, d, h)), ascending ? 1 : -1).slice(0, limit ?? 100);
    e.r = filas.map((s) => (dataType === 'sleep' ? [s.ini, s.fin, s.valor, s.f, s.estado] : [s.ini, s.fin, s.valor, s.f]));
    return {
      samples: filas.map((s) => {
        const p = { dataType, value: s.valor, unit: 'x', startDate: iso(s.ini), endDate: iso(s.fin) };
        if (dataType === 'sleep') {
          if (s.estado) {
            p.sleepState = s.estado;
            p.stages = [{ startDate: iso(s.ini), endDate: iso(s.fin), stage: s.estado, durationMinutes: s.valor }];
            p.hasStageData = true;
          } else {
            p.hasStageData = false;
          }
        }
        p.sourceName = fuente(s.f)[1];
        p.sourceId = fuente(s.f)[0];
        p.platformId = `uuid-${s.ini}-${s.f}`;
        return p;
      }),
    };
  },
  async queryAggregated({ dataType, startDate, endDate, bucket, aggregation }) {
    const d = ms(startDate), h = ms(endDate);
    const e = { m: 'queryAggregated', dataType, desde: d, hasta: h, agg: aggregation, balde: bucket };
    LOG.push(e);
    if (FALLAS[dataType]) { e.error = FALLAS[dataType]; throw new Error(FALLAS[dataType]); }
    const ok = MATRIZ_AGG[dataType];
    if (!ok || !ok.includes(aggregation)) {
      e.error = `Aggregated queries are not supported for ${dataType}. Use readSamples instead.`;
      throw new Error(e.error);
    }
    // Ancla: la medianoche local del día de `desde`; un balde por día de calendario.
    const ancla = new DateReal(d); ancla.setHours(0, 0, 0, 0);
    const baldes = [];
    for (let ini = ancla.getTime(); ini <= h;) {
      const sig = new DateReal(ini); sig.setDate(sig.getDate() + 1); sig.setHours(0, 0, 0, 0);
      const xs = (ALM.cantidades[dataType] || []).filter(([i]) => estricto(i, d, h) && i >= ini && i < sig.getTime()).map((s) => s[2]);
      if (xs.length) {
        const suma = xs.reduce((a, b) => a + b, 0);
        baldes.push([ini, sig.getTime(), aggregation === 'sum' ? suma : suma / xs.length]);
      }
      ini = sig.getTime();
    }
    e.r = baldes;
    return { samples: baldes.map(([a, b, v]) => ({ startDate: iso(a), endDate: iso(b), value: v, values: { [aggregation]: v }, unit: 'x' })) };
  },
  async queryWorkouts({ startDate, endDate, limit, ascending }) {
    const d = ms(startDate), h = ms(endDate);
    const e = { m: 'queryWorkouts', desde: d, hasta: h, limite: limit ?? 100, asc: !!ascending };
    LOG.push(e);
    if (FALLAS.workouts) { e.error = FALLAS.workouts; throw new Error(FALLAS.workouts); }
    const ws = ordenar((ALM.entrenos || []).map(([ini, fin, tipo, dur, kcal, dist, f]) => ({ ini, fin, tipo, dur, kcal, dist, f }))
      .filter((w) => solapa(w.ini, w.fin, d, h)), ascending ? 1 : -1).slice(0, limit ?? 100);
    e.r = ws.map((w) => [w.tipo, Math.trunc(w.dur), w.ini, w.fin, w.kcal ?? null, w.dist ?? null, w.f]);
    return {
      workouts: ws.map((w) => {
        const p = { workoutType: w.tipo, duration: Math.trunc(w.dur), startDate: iso(w.ini), endDate: iso(w.fin) };
        if (w.kcal != null) p.totalEnergyBurned = w.kcal;
        if (w.dist != null) p.totalDistance = w.dist;
        p.sourceName = fuente(w.f)[1];
        p.sourceId = fuente(w.f)[0];
        p.platformId = `w-${w.ini}`;
        return p;
      }),
    };
  },
};
globalThis.Capacitor = { isNativePlatform: () => true, getPlatform: () => 'ios', Plugins: { Health } };

// ── La base, imitada: graba cada lote y contesta según el caso ────────
let INGEST = 'ok';         // 'ok' | 'cero' | 'rechaza' | 'red' | función (n.º de lote) → uno de esos
let RPC = [];
function respuestaIngest(n, cantidad) {
  const modo = typeof INGEST === 'function' ? INGEST(n) : INGEST;
  if (modo === 'rechaza') return { success: false, data: null, error: 'permission denied for function mypump_ingest_salud', code: '42501' };
  if (modo === 'red') return { success: false, data: null, error: 'TypeError: Load failed', code: 'NETWORK', transitorio: true };
  return { success: true, data: modo === 'cero' ? 0 : cantidad, error: null };
}
window.mypumpDB = {
  async ingestSalud(token, registros) {
    const r = respuestaIngest(RPC.filter((x) => x.fn === 'mypump_ingest_salud').length + 1, registros.length);
    RPC.push({ fn: 'mypump_ingest_salud', token, lote: JSON.parse(JSON.stringify(registros)), r: { success: r.success, data: r.data, error: r.error } });
    return r;
  },
  async ingestEntrenos(token, entrenos) {
    const r = respuestaIngest(RPC.filter((x) => x.fn === 'mypump_ingest_entrenos').length + 1, entrenos.length);
    RPC.push({ fn: 'mypump_ingest_entrenos', token, lote: JSON.parse(JSON.stringify(entrenos)), r: { success: r.success, data: r.data, error: r.error } });
    return r;
  },
};
let REPINTADOS = 0;
window.loadSalud = () => { REPINTADOS++; };
window.loadRecuperacion = () => {};

// ── El bridge REAL ───────────────────────────────────────────────────
new Function(BRIDGE)();
const H = globalThis.MyPumpHealth;
const GEN = (() => { const m = { exports: {} }; new Function('module', 'exports', SINTETICA)(m, m.exports); return m.exports; })();

// ── Armado de casos ──────────────────────────────────────────────────
const FUENTES = [
  ['com.apple.health.81A5C2E0-0F7B-4C1E-9D52-2F1E2B8B7A11', 'Apple Watch de Mati'],   // 0 reloj
  ['com.apple.health.5D0E7A2C-3B1A-4E8F-A1C3-77B1E0C9D2F4', 'iPhone de Mati'],        // 1 teléfono
  ['com.ouraring.oura', 'Oura'],                                                        // 2 anillo
  ['com.withings.wiScaleNG', 'Health Mate'],                                            // 3 balanza
  ['com.sleepcycle.sleepcycle', 'Sleep Cycle'],                                         // 4 app de sueño
];
const RELOJ = 0, TEL = 1, OURA = 2, BALANZA = 3, APPSUENO = 4;
const HK = { inBed: 0, asleep: 1, awake: 2, core: 3, deep: 4, rem: 5 };
const MIN = 60000, HORA = 3600000;

/** ms de una hora local: `dia` días antes de AHORA (0 = hoy), a las hh:mm:ss.mmm. */
function t(dia, hh, mm = 0, ss = 0, mss = 0) {
  const x = new DateReal(AHORA); x.setHours(0, 0, 0, 0); x.setDate(x.getDate() - dia); x.setHours(hh, mm, ss, mss);
  return x.getTime();
}
function vacio() { return { fuentes: FUENTES, cantidades: {}, sueno: [], mindful: [], entrenos: [] }; }
function sumar(a, dataType, filas) { (a.cantidades[dataType] = a.cantidades[dataType] || []).push(...filas); return a; }

/** Las muestras de salud-sintetica.js con la forma del plugin 8.9.3 (HRV en ms, etapas como HKCategoryValue). */
function desdeSintetica(escenario, dias, seed) {
  const a = vacio();
  const m = GEN.muestras(escenario, dias, seed);
  const rnd = GEN.mulberry32(seed * 7 + 1);
  const etapa = { asleepDeep: HK.deep, asleepREM: HK.rem, asleepCore: HK.core, inBed: HK.inBed };
  sumar(a, 'steps', m.steps.map((s) => [ms(s.startDate), ms(s.endDate), s.value, TEL]));
  sumar(a, 'calories', m.activeEnergyBurned.map((s) => [ms(s.startDate), ms(s.endDate), s.value + Math.round(rnd() * 1000) / 1000, RELOJ]));
  sumar(a, 'restingHeartRate', m.restingHeartRate.map((s) => [ms(s.startDate), ms(s.endDate), s.value, RELOJ]));
  // El generador da SDNN en segundos (el formato de un plugin viejo); el 8.9.3 lo da en ms, con decimales.
  sumar(a, 'heartRateVariability', m.heartRateVariability.map((s) => [ms(s.startDate), ms(s.endDate),
    Math.round(s.value * 1e6) / 1e3 + Math.round(rnd() * 1e4) / 1e4, RELOJ]));
  sumar(a, 'weight', m.weight.map((s) => [ms(s.startDate), ms(s.endDate), s.value, BALANZA]));
  a.sueno.push(...m.sleep.map((s) => [ms(s.startDate), ms(s.endDate), etapa[s.sleepState], RELOJ]));
  return a;
}

/** Lo que ningún generador da: el resto de los tipos, con valores y unidades del plugin. */
function extras(a, dias, seed, conReloj = true) {
  const rnd = GEN.mulberry32(seed);
  const r = (lo, hi, dec = 0) => Math.round((lo + rnd() * (hi - lo)) * 10 ** dec) / 10 ** dec;
  for (let d = dias - 1; d >= 0; d--) {
    sumar(a, 'exerciseTime', [[t(d, 7, 10), t(d, 7, 10 + r(5, 40)), r(5, 40), RELOJ], [t(d, 18, 5), t(d, 18, 35), r(3, 30, 2), RELOJ]]);
    sumar(a, 'distance', [[t(d, 9), t(d, 9, 40), r(800, 4200, 1), TEL], [t(d, 17, 30), t(d, 18), r(300, 2500, 3), TEL]]);
    sumar(a, 'flightsClimbed', [[t(d, 10), t(d, 10, 5), r(1, 6), TEL], [t(d, 15), t(d, 15, 3), r(1, 4), TEL]]);
    sumar(a, 'basalCalories', Array.from({ length: 4 }, (_, k) => [t(d, k * 6), t(d, k * 6 + 5, 59), r(400, 470, 3), RELOJ]));
    if (rnd() < 0.3) sumar(a, 'bloodGlucose', [[t(d, 8, 5), t(d, 8, 5), r(80, 110, 1), TEL]]);
    if (rnd() < 0.2) sumar(a, 'bodyTemperature', [[t(d, 8, 30), t(d, 8, 30), r(36.1, 37.2, 2), TEL]]);
    if (rnd() < 0.5) a.mindful.push([t(d, 22, 0), t(d, 22, r(3, 15)), RELOJ]);
    if (rnd() < 0.25) sumar(a, 'bodyFat', [[t(d, 8, 1), t(d, 8, 1), r(0.14, 0.2, 3), BALANZA]]);
    if (!conReloj) continue;
    sumar(a, 'respiratoryRate', Array.from({ length: 3 + Math.floor(rnd() * 4) }, (_, k) => [t(d, 1 + k, 20), t(d, 1 + k, 20), r(12, 17, 1), RELOJ]));
    sumar(a, 'oxygenSaturation', Array.from({ length: 2 + Math.floor(rnd() * 3) }, (_, k) => [t(d, 2 + k, 45), t(d, 2 + k, 45), r(0.93, 1, 2), RELOJ]));
    sumar(a, 'appleSleepingWristTemperature', [[t(d, 3, 0), t(d, 6, 30), r(35.2, 36.4, 3), RELOJ]]);
    // FC de todo el día: cada 10 min, con decimales (el reloj promedia).
    const fc = [];
    for (let k = 0; k < 144; k += 1 + Math.floor(rnd() * 2)) fc.push([t(d, 0, k * 10), t(d, 0, k * 10), r(52, 118, 1), RELOJ]);
    sumar(a, 'heartRate', fc);
  }
  return a;
}

// ── Correr un caso ───────────────────────────────────────────────────
function reiniciar(estado) {
  for (const k of Object.keys(store)) delete store[k];
  Object.assign(store, { mypump_token: 'tok-de-prueba-nativa-0001' }, estado || {});
  LOG = []; RPC = []; AVISOS.length = 0; FALLAS = {}; RECHAZA_PERMISO = []; INGEST = 'ok'; REPINTADOS = 0;
}
const estadoSalud = () => Object.fromEntries(Object.entries(store).filter(([k]) => k.startsWith('mypump_health_')).sort());

async function correr(c) {
  zona(c.tz);
  AHORA = c.ahora;
  ALM = c.almacen;
  reiniciar(c.estado);
  if (c.fallas) FALLAS = c.fallas;
  if (c.rechazaPermiso) RECHAZA_PERMISO = c.rechazaPermiso;
  if (c.ingest) INGEST = c.ingest;
  const estadoInicial = estadoSalud();
  const progreso = [];
  let resultado;
  if (c.accion === 'sync') {
    resultado = await H.sync();
  } else if (c.accion === 'backfill') {
    resultado = await H.backfill((hecho, total) => progreso.push([hecho, total]));
  } else if (c.accion === 'conectar') {
    const r = await H.connect({ onProgreso: (hecho, total) => progreso.push([hecho, total]), esperarBackfill: true });
    resultado = { ...r, backfill: await r.backfill };
  } else if (c.accion === 'estado') {
    resultado = await H.estado();
  }
  const diag = store.mypump_health_diag ? JSON.parse(store.mypump_health_diag) : null;
  return {
    nombre: c.nombre,
    descripcion: c.descripcion,
    accion: c.accion,
    tz: c.tz,
    ahora: c.ahora,
    fuentes: ALM.fuentes,
    estadoInicial,
    consultas: LOG,
    rpc: RPC,
    resultado: JSON.parse(JSON.stringify(resultado)),
    progreso,
    estadoFinal: Object.fromEntries(Object.entries(estadoSalud()).filter(([k]) => k !== 'mypump_health_diag')),
    diag: diag && { paso: diag.paso, motivo: diag.motivo ?? null, preguntados: diag.preguntados ?? null, total: diag.total ?? null,
      rechazados: diag.rechazados ?? null },
  };
}

/** Un "ahora" en hora local de la zona del caso. */
function ahoraEn(tz, y, mo, d, hh, mm) {
  zona(tz);
  return new DateReal(y, mo - 1, d, hh, mm, 17, 345).getTime();
}

const BA = 'America/Argentina/Buenos_Aires';
const SYNC = { mypump_health_connected: '1', mypump_health_backfill_v1: '1' };
const casosSync = [];
const casosBackfill = [];
const casosConectar = [];
const caso = (lista, c) => lista.push(c);

// Escenarios del banco de pruebas de la web, con el resto de los tipos encima.
for (const [i, esc] of GEN.ESCENARIOS.entries()) {
  const tz = BA;
  const ahora = ahoraEn(tz, 2026, 10, 14, [21, 7, 0, 13, 23][i], [40, 15, 5, 30, 59][i]);
  AHORA = ahora;
  const a = desdeSintetica(esc, 12, 40 + i);
  extras(a, 12, 90 + i, esc !== 'sin-reloj');
  caso(casosSync, { nombre: `sintetica-${esc}`, descripcion: `salud-sintetica.js "${esc}" + el resto de los tipos`, accion: 'sync', tz, ahora, almacen: a, estado: SYNC });
}

// Sueño: dos y tres fuentes, siestas, huecos, despierto, en cama, bordes.
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 10, 20); AHORA = ahora;
  const a = vacio();
  // Despierta hoy: el iPhone pone "en cama", el reloj las etapas con ratos despierto, Sleep Cycle "dormido". Gana el
  // reloj (444 min de sueño real contra 420).
  a.sueno.push([t(1, 22, 50), t(0, 7, 10), HK.inBed, TEL]);
  a.sueno.push([t(1, 23, 5), t(1, 23, 50), HK.core, RELOJ], [t(1, 23, 50), t(0, 0, 40), HK.deep, RELOJ], [t(0, 0, 40), t(0, 1, 5), HK.rem, RELOJ],
    [t(0, 1, 5), t(0, 1, 17), HK.awake, RELOJ], [t(0, 1, 17), t(0, 4, 2, 30), HK.core, RELOJ], [t(0, 4, 2, 30), t(0, 4, 50), HK.rem, RELOJ],
    [t(0, 4, 50), t(0, 6, 41), HK.core, RELOJ], [t(0, 6, 41), t(0, 6, 55), HK.awake, RELOJ]);
  a.sueno.push([t(1, 23, 30), t(0, 6, 30), HK.asleep, APPSUENO]);
  // Despierta ayer: solo el iPhone, en cama → estimado al 90 %.
  a.sueno.push([t(2, 23, 40), t(1, 7, 25), HK.inBed, TEL]);
  // Despierta anteayer: "en cama" con un rato "despierto" y nada más (el plugin cuenta los dos como en cama).
  a.sueno.push([t(3, 23, 30), t(2, 7, 0), HK.inBed, TEL], [t(2, 3, 0), t(2, 3, 25), HK.awake, TEL]);
  // Día 3: un hueco de exactamente 60 min (no corta) y una siesta (suma, pero no fija el punto medio).
  a.sueno.push([t(3, 0, 10), t(3, 3, 0), HK.core, RELOJ], [t(3, 4, 0), t(3, 7, 45), HK.core, RELOJ], [t(3, 14, 30), t(3, 15, 12), HK.asleep, RELOJ]);
  // Día 4: muestras superpuestas de la misma fuente (se fusionan) y una de largo cero.
  a.sueno.push([t(5, 23, 0), t(4, 6, 0), HK.core, RELOJ], [t(4, 1, 0), t(4, 2, 30), HK.deep, RELOJ], [t(4, 5, 30), t(4, 6, 15), HK.rem, RELOJ],
    [t(4, 9, 0), t(4, 9, 0), HK.core, RELOJ]);
  // Día 5: un hueco de 60 min y 1 ms corta la noche en dos bloques del mismo día; el punto medio es el del más largo.
  a.sueno.push([t(5, 1, 0), t(5, 3, 0), HK.core, RELOJ], [t(5, 4, 0, 0, 1), t(5, 6, 30), HK.rem, RELOJ]);
  // Día 6: empate exacto de minutos entre dos fuentes (gana la primera que aparece) y una siesta con un valor de sueño
  // que el plugin no conoce (sale sin sleepState y el bridge la toma como dormido).
  a.sueno.push([t(6, 0, 0), t(6, 6, 0), HK.asleep, OURA], [t(6, 0, 0), t(6, 6, 0), HK.core, RELOJ], [t(6, 15, 0), t(6, 15, 30), 99, RELOJ]);
  // La noche del borde (día 7, el más viejo de la ventana): empezó el día 8 a la noche y entra entera porque el sueño
  // se pide desde el mediodía anterior. La siesta del día 8 sale en la consulta pero se descarta (fecha < corte).
  a.sueno.push([t(8, 22, 50), t(7, 7, 0), HK.inBed, TEL], [t(8, 23, 0), t(7, 6, 50), HK.core, RELOJ], [t(7, 3, 0), t(7, 3, 25), HK.awake, TEL],
    [t(8, 15, 0), t(8, 15, 40), HK.core, RELOJ]);
  // HRV durante cada noche (bordes incluidos), de madrugada fuera del sueño y de día; ceros y negativos se ignoran.
  sumar(a, 'heartRateVariability', [
    [t(0, 2, 0), t(0, 2, 0), 48.21, RELOJ], [t(0, 3, 30), t(0, 3, 31), 52.7, RELOJ], [t(0, 9, 30), t(0, 9, 30), 31.5, RELOJ],
    [t(0, 6, 55), t(0, 6, 55), 60, RELOJ], [t(0, 15, 0), t(0, 15, 0), 20, RELOJ],
    [t(1, 8, 0), t(1, 8, 0), 44.44, RELOJ], [t(1, 12, 0), t(1, 12, 0), 70, RELOJ], [t(1, 9, 59, 59, 999), t(1, 9, 59, 59, 999), 40.5, RELOJ],
    [t(2, 10, 0), t(2, 10, 0), 33.5, RELOJ], [t(2, 18, 0), t(2, 18, 0), 34.5, RELOJ],
    [t(3, 2, 0), t(3, 2, 0), 0, RELOJ], [t(3, 2, 30), t(3, 2, 30), -5, RELOJ], [t(3, 3, 30), t(3, 3, 30), 55.5, RELOJ],
    [t(3, 3, 59), t(3, 3, 59), 56.5, RELOJ], [t(3, 14, 40), t(3, 14, 40), 61.25, RELOJ],
    [t(6, 6, 0), t(6, 6, 0), 47.5, OURA], [t(7, 0, 30), t(7, 0, 30), 39.49, TEL], [t(5, 3, 30), t(5, 3, 30), 45.5, RELOJ],
  ]);
  caso(casosSync, { nombre: 'sueno-fuentes-y-bordes', descripcion: 'fuentes que compiten, siesta, huecos de 60 min, en cama, despierto, empate, valor desconocido, la noche del borde y la HRV de cada ventana',
    accion: 'sync', tz, ahora, almacen: a, estado: SYNC });
}

// Cada tipo de muestra con sus bordes: escala 0-1, factor de metros, "último" con empate, mediana par, sumas que dan 0.
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 20, 0); AHORA = ahora;
  const a = vacio();
  sumar(a, 'oxygenSaturation', [[t(0, 3), t(0, 3), 0.97, RELOJ], [t(0, 4), t(0, 4), 0.955, RELOJ], [t(1, 3), t(1, 3), 96.5, OURA], [t(1, 4), t(1, 4), 1, RELOJ]]);
  sumar(a, 'bodyFat', [[t(0, 8), t(0, 8), 0.1849, BALANZA], [t(2, 8), t(2, 8), 18.25, BALANZA], [t(2, 9), t(2, 9), 0.18, BALANZA]]);
  sumar(a, 'distance', [[t(0, 8), t(0, 9), 3200, TEL], [t(0, 18), t(0, 19), 2220, TEL], [t(1, 8), t(1, 9), 49, TEL], [t(2, 7), t(2, 8), 50, TEL], [t(3, 7), t(3, 8), 0.4, TEL]]);
  sumar(a, 'weight', [[t(0, 7, 30), t(0, 7, 30), 82.35, BALANZA], [t(0, 20, 0), t(0, 20, 0), 83.05, TEL], [t(0, 20, 0), t(0, 20, 0), 83.15, BALANZA],
    [t(1, 7), t(1, 7), 82.25, BALANZA], [t(3, 7), t(3, 7), 0, BALANZA]]);
  sumar(a, 'respiratoryRate', [[t(0, 2), t(0, 2), 14, RELOJ], [t(0, 3), t(0, 3), 15, RELOJ], [t(0, 4), t(0, 4), 13.5, RELOJ], [t(0, 5), t(0, 5), 16.05, RELOJ]]);
  sumar(a, 'appleSleepingWristTemperature', [[t(0, 2), t(0, 7), 35.95, RELOJ], [t(1, 2), t(1, 7), 36.25, RELOJ], [t(1, 3), t(1, 6), 36.35, RELOJ]]);
  sumar(a, 'exerciseTime', [[t(0, 7), t(0, 8), 0.5, RELOJ], [t(0, 9), t(0, 10), 0.45, RELOJ], [t(1, 9), t(1, 10), 0.04, RELOJ], [t(2, 9), t(2, 10), 0, RELOJ]]);
  sumar(a, 'flightsClimbed', [[t(0, 10), t(0, 11), 3, TEL], [t(0, 12), t(0, 13), 4, TEL]]);
  sumar(a, 'basalCalories', [[t(0, 0), t(0, 12), 812.345, RELOJ], [t(0, 12), t(0, 20), 545.555, RELOJ]]);
  sumar(a, 'bodyTemperature', [[t(0, 8), t(0, 8), 36.65, TEL], [t(1, 8), t(1, 8), 37.05, TEL]]);
  sumar(a, 'bloodGlucose', [[t(0, 8), t(0, 8), 95.45, TEL], [t(0, 13), t(0, 13), 120.55, TEL]]);
  a.mindful.push([t(0, 22, 0), t(0, 22, 10, 30), RELOJ], [t(0, 23, 0), t(0, 23, 4, 15), TEL], [t(1, 22), t(1, 22), RELOJ]);
  sumar(a, 'heartRate', [[t(0, 1), t(0, 1), 55.5, RELOJ], [t(0, 2), t(0, 2), 54.5, RELOJ], [t(1, 1), t(1, 1), 60, RELOJ]]);
  // Una muestra que empezó antes de la ventana y la cruza: el plugin la devuelve y el bridge la anota en SU fecha.
  sumar(a, 'exerciseTime', [[t(9, 23, 30), t(7, 0, 15), 45, RELOJ]]);
  // Agregados: decimales al .5, ceros, promedio de varias lecturas de FC en reposo.
  sumar(a, 'steps', [[t(0, 0, 5), t(0, 9), 4520.5, TEL], [t(0, 9), t(0, 18), 3000, TEL], [t(1, 1), t(1, 2), 0, TEL], [t(2, 10), t(2, 11), 1234.49, TEL]]);
  sumar(a, 'calories', [[t(0, 8), t(0, 9), 123.5, RELOJ], [t(0, 10), t(0, 11), 99.75, RELOJ], [t(1, 8), t(1, 9), 0.4, RELOJ]]);
  sumar(a, 'restingHeartRate', [[t(0, 4), t(0, 4), 51, RELOJ], [t(0, 5), t(0, 5), 54, RELOJ], [t(1, 4), t(1, 4), 52.5, RELOJ]]);
  caso(casosSync, { nombre: 'muestras-y-agregados-bordes', descripcion: 'escala 0-1, metros a km, último con empate, medianas, sumas en cero, una muestra que cruza el inicio de la ventana y redondeos al .5',
    accion: 'sync', tz, ahora, almacen: a, estado: SYNC });
}

// El límite de 5000: la ventana se parte al medio y la muestra que cruza el corte se cuenta una vez.
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 23, 50); AHORA = ahora;
  const a = vacio();
  const fc = [];
  let k = 0;
  for (let d = 7; d >= 0; d--) for (let m = 0; m < 24 * 60; m += 2) fc.push([t(d, 0, m), t(d, 0, m, 30), 60 + ((k++ * 37) % 61) + (k % 3) / 4, RELOJ]);
  // Una lectura que cruza la mitad de la ventana: el plugin la devuelve en las dos mitades (predicado sin límites
  // estrictos) y el bridge la tiene que contar una sola vez.
  const desde = t(7, 0), hasta = ahora;
  const medio = Math.trunc((desde + hasta) / 2);
  fc.push([medio - 10000, medio + 10000, 77.7, RELOJ]);
  sumar(a, 'heartRate', fc);
  sumar(a, 'exerciseTime', [[medio - 20 * MIN, medio + 25 * MIN, 45, RELOJ]]);
  caso(casosSync, { nombre: 'limite-5000-biseccion', descripcion: 'más de 5000 muestras de FC: la ventana se parte y no se duplica lo que cruza el corte',
    accion: 'sync', tz, ahora, almacen: a, estado: SYNC });
}

// Entrenos: FC dentro y fuera, duración truncada, distancia cero, kcal con decimales, más de 100 en la ventana.
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 19, 5); AHORA = ahora;
  const a = vacio();
  a.entrenos.push(
    [t(0, 10), t(0, 10, 30), 'running', 1800.9, 300.5, 5000, RELOJ],
    [t(1, 18), t(1, 19, 2), 'strengthTraining', 3725.4, 412.49, null, RELOJ],
    [t(2, 7), t(2, 7, 45), 'cycling', 2700, null, 0, RELOJ],
    [t(3, 20), t(3, 20, 50), 'soccer', 3000.5, 640, 6120.4, RELOJ],
    [t(4, 6), t(4, 6, 20), 'other', 1199.999, 80.123, 1234.5678, TEL],
  );
  sumar(a, 'heartRate', [
    [t(0, 10, 5), t(0, 10, 5), 140, RELOJ], [t(0, 10, 15), t(0, 10, 15), 160.4, RELOJ], [t(0, 10, 25), t(0, 10, 25), 150.5, RELOJ],
    [t(0, 10, 30), t(0, 10, 30), 151, RELOJ], [t(0, 14), t(0, 14), 60, RELOJ],
    [t(1, 18, 0), t(1, 18, 0), 98.5, RELOJ], [t(1, 18, 40), t(1, 18, 40), 131.25, RELOJ], [t(1, 19, 2), t(1, 19, 2), 120.75, RELOJ],
    [t(3, 20, 10), t(3, 20, 10), 0, RELOJ], [t(3, 20, 11), t(3, 20, 11), -3, RELOJ],
  ]);
  caso(casosSync, { nombre: 'entrenos-con-fc', descripcion: 'FC media y máxima de las muestras de cada entreno; duración, kcal y distancia como las arma el bridge',
    accion: 'sync', tz, ahora, almacen: a, estado: SYNC });

  const b = vacio();
  for (let i = 0; i < 130; i++) b.entrenos.push([t(6, 1) + i * 70 * MIN, t(6, 1) + i * 70 * MIN + 30 * MIN, i % 2 ? 'walking' : 'yoga', 1800, 100 + i, null, RELOJ]);
  caso(casosSync, { nombre: 'entrenos-mas-de-100', descripcion: 'el plugin corta en 100 y en orden descendente (el bridge no pasa límite ni orden)',
    accion: 'sync', tz, ahora, almacen: b, estado: SYNC });
}

// Zonas con cambio de hora: medianoches, punto medio del sueño y "antes de las 10" en días de 25 h.
for (const [tz, y, mo, d, nombre] of [['America/New_York', 2026, 11, 4, 'zona-nueva-york-cambio-de-hora'], ['Europe/Madrid', 2026, 10, 27, 'zona-madrid-cambio-de-hora']]) {
  const ahora = ahoraEn(tz, y, mo, d, 8, 45); AHORA = ahora;
  const a = desdeSintetica('normal', 9, 77);
  extras(a, 9, 78);
  caso(casosSync, { nombre, descripcion: `${tz}: la ventana de 7 días cruza el cambio de hora`, accion: 'sync', tz, ahora, almacen: a, estado: SYNC });
}

// Errores: un tipo que el plugin rechaza, un agregado que tira, la base que rechaza o no contesta.
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 12, 0); AHORA = ahora;
  const a = desdeSintetica('normal', 8, 5);
  caso(casosSync, { nombre: 'errores-del-plugin', descripcion: 'readSamples y queryAggregated que tiran: el bridge sigue con lo demás',
    accion: 'sync', tz, ahora, almacen: a, estado: SYNC,
    fallas: { respiratoryRate: 'Authorization not determined', steps: 'Statistics query failed', workouts: 'Workout query failed' } });
  caso(casosSync, { nombre: 'ingesta-rechazada', descripcion: 'el servidor rechaza los lotes: errorIngesta con el texto', accion: 'sync', tz, ahora,
    almacen: a, estado: SYNC, ingest: 'rechaza' });
  caso(casosSync, { nombre: 'ingesta-sin-red', descripcion: 'sin señal: cuenta como rechazo, no como "no había nada"', accion: 'sync', tz, ahora,
    almacen: a, estado: SYNC, ingest: 'red' });
  caso(casosSync, { nombre: 'ingesta-devuelve-cero', descripcion: 'token revocado: 200 con 0 (no es error)', accion: 'sync', tz, ahora,
    almacen: a, estado: SYNC, ingest: 'cero' });
}

// Nada de nada: la racha de cosechas vacías y la sospecha de permiso denegado.
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 9, 0); AHORA = ahora;
  caso(casosSync, { nombre: 'vacio-primera', descripcion: 'sin datos: la racha sube a 1', accion: 'sync', tz, ahora, almacen: vacio(), estado: SYNC });
  caso(casosSync, { nombre: 'vacio-tercera', descripcion: 'tercera vacía seguida: "no llega nada"', accion: 'sync', tz, ahora, almacen: vacio(),
    estado: { ...SYNC, mypump_health_racha_vacia: '2' } });
  const a = vacio();
  sumar(a, 'weight', [[t(0, 8), t(0, 8), 80, BALANZA]]);
  caso(casosSync, { nombre: 'vuelve-a-llegar', descripcion: 'con la sospecha prendida, un dato la apaga', accion: 'sync', tz, ahora, almacen: a,
    estado: { ...SYNC, mypump_health_racha_vacia: '5', mypump_health_denegado: '1' } });
}

// Lotes de 300: muestras largas que empiezan cada una en otro día y cruzan la ventana (cada una es una fecha).
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 18, 30); AHORA = ahora;
  const a = desdeSintetica('normal', 8, 11);
  for (let i = 0; i < 340; i++) a.mindful.push([t(8 + i, 21, 0), t(3, 21, 30), RELOJ]);
  caso(casosSync, { nombre: 'lotes-de-300', descripcion: 'más de 300 registros: se mandan de a 300', accion: 'sync', tz, ahora, almacen: a, estado: SYNC });
}

// ── Historial de 60 días ─────────────────────────────────────────────
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 22, 10); AHORA = ahora;
  const lleno = desdeSintetica('normal', 62, 21);
  lleno.entrenos.push([t(33, 18), t(33, 19), 'running', 3600, 520, 9800, RELOJ], [t(12, 7), t(12, 7, 40), 'strengthTraining', 2400, 210, null, RELOJ]);
  sumar(lleno, 'heartRate', [[t(33, 18, 30), t(33, 18, 30), 150, RELOJ], [t(12, 7, 10), t(12, 7, 10), 118.5, RELOJ]]);
  const conectado = { mypump_health_connected: '1' };
  caso(casosBackfill, { nombre: 'historial-completo', descripcion: '12 ventanas de 5 días, de la más vieja a la más nueva, y queda hecho', accion: 'backfill',
    tz, ahora, almacen: lleno, estado: conectado });
  caso(casosBackfill, { nombre: 'historial-retoma-cursor', descripcion: 'cortado en el día 20: retoma desde ahí', accion: 'backfill', tz, ahora,
    almacen: lleno, estado: { ...conectado, mypump_health_backfill_off: JSON.stringify({ off: 20, alcance: 60 }) } });
  caso(casosBackfill, { nombre: 'historial-cursor-viejo', descripcion: 'el cursor del formato viejo (solo el número)', accion: 'backfill', tz, ahora,
    almacen: lleno, estado: { ...conectado, mypump_health_backfill_off: '20' } });
  caso(casosBackfill, { nombre: 'historial-cursor-parcial', descripcion: 'un cursor de alcance 30 no trunca el de 60', accion: 'backfill', tz, ahora,
    almacen: lleno, estado: { ...conectado, mypump_health_backfill_off: JSON.stringify({ off: 20, alcance: 30 }) } });
  caso(casosBackfill, { nombre: 'historial-todo-rechazado', descripcion: 'las 12 ventanas rechazadas: no queda hecho ni acusa de denegar', accion: 'backfill',
    tz, ahora, almacen: lleno, estado: conectado, ingest: 'rechaza' });
  caso(casosBackfill, { nombre: 'historial-sin-red-a-medias', descripcion: 'se corta la red a mitad: esas ventanas cuentan como fallidas', accion: 'backfill',
    tz, ahora, almacen: lleno, estado: conectado, ingest: (n) => (n >= 4 && n <= 6 ? 'red' : 'ok') });
  caso(casosBackfill, { nombre: 'historial-nada-entra', descripcion: 'se leyó todo y la base aceptó 0: no se marca hecho', accion: 'backfill', tz, ahora,
    almacen: lleno, estado: conectado, ingest: 'cero' });
  caso(casosBackfill, { nombre: 'historial-vacio', descripcion: '60 días sin una muestra: "no llega nada" de una', accion: 'backfill', tz, ahora,
    almacen: vacio(), estado: conectado });
  caso(casosBackfill, { nombre: 'historial-ya-hecho', descripcion: 'con la marca puesta no consulta nada', accion: 'backfill', tz, ahora, almacen: lleno,
    estado: { ...conectado, mypump_health_backfill_v1: '1' } });
}

// ── Conectar: permisos en dos tandas, sync de 7 días y el historial ──
{
  const tz = BA, ahora = ahoraEn(tz, 2026, 10, 14, 11, 0); AHORA = ahora;
  const a = desdeSintetica('recien-conectado', 3, 9);
  caso(casosConectar, { nombre: 'conectar-primera-vez', descripcion: 'núcleo, resto, sync y los 60 días', accion: 'conectar', tz, ahora, almacen: a, estado: {} });
  caso(casosConectar, { nombre: 'conectar-tipo-rechazado', descripcion: 'la tanda secundaria falla en bloque y se pide de a uno', accion: 'conectar', tz, ahora,
    almacen: a, estado: {}, rechazaPermiso: ['appleSleepingWristTemperature'] });
  caso(casosConectar, { nombre: 'conectar-nucleo-falla', descripcion: 'el núcleo falla: reintento pelado con pasos y sueño', accion: 'conectar', tz, ahora,
    almacen: a, estado: {}, rechazaPermiso: ['weight'] });
  caso(casosConectar, { nombre: 'conectar-sin-datos', descripcion: 'pasa por la hoja y no llega nada en 60 días', accion: 'conectar', tz, ahora,
    almacen: vacio(), estado: {} });
  caso(casosConectar, { nombre: 'reintentar-con-historial-hecho', descripcion: '"Reintentar" no apaga el cartel si no llegó nada', accion: 'conectar', tz, ahora,
    almacen: vacio(), estado: { mypump_health_backfill_v1: '1', mypump_health_denegado: '1', mypump_health_racha_vacia: '4' } });
  caso(casosConectar, { nombre: 'estado', descripcion: 'estado(): disponible, conectado, preguntados y última sync', accion: 'estado', tz, ahora,
    almacen: a, estado: { mypump_health_connected: '1', mypump_health_last_sync: '2026-10-14T13:59:00.000Z' } });
}

// ── Las cards (cliente.html): qué valor gana cada día, los motivos del score, la regularidad ──
// Las funciones salen de cliente.html@REF por su texto (como generar-vectores.mjs) y corren con un STATE armado.
const HTML = mostrar('public/cliente.html');
function extraerFn(nombre) {
  const i = HTML.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no encontré function ${nombre}( en cliente.html@${REF}`);
  let prof = 0;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}' && --prof === 0) return HTML.slice(i, k + 1);
  }
  throw new Error(`function ${nombre} sin cierre`);
}
function extraerObjeto(nombre) {
  const i = HTML.indexOf(`const ${nombre} = {`);
  if (i < 0) throw new Error(`no encontré const ${nombre}`);
  let prof = 0;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}' && --prof === 0) return HTML.slice(i, k + 1) + ';';
  }
  throw new Error(`const ${nombre} sin cierre`);
}
function extraerLinea(nombre) {
  const i = HTML.indexOf(`const ${nombre} =`);
  if (i < 0) throw new Error(`no encontré const ${nombre}`);
  return HTML.slice(i, HTML.indexOf('\n', i));
}
const STATE = { salud: [] };
let HOY = '2026-10-14';
const vista = new Function('STATE', 'hoyLocal', [extraerObjeto('_PREF_FUENTE'), extraerLinea('_fmtHs'), extraerFn('_saludValor'),
  extraerFn('_serieSalud'), extraerFn('_recDrivers'), extraerFn('_promCircularMin'), extraerFn('_hhmmReloj'), extraerFn('_saludTieneReciente'),
  'return { _saludValor, _serieSalud, _recDrivers, _promCircularMin, _hhmmReloj, _saludTieneReciente };'].join('\n'))(STATE, () => HOY);

/** El HTML de un motivo → {flecha, antes, negrita, despues}. */
function motivoDeHtml(div) {
  const m = /<span class="rec-arrow">(.*?)<\/span><span>(.*)<\/span><\/div>$/.exec(div);
  const t = m[2];
  const b = /^(.*?)<b>(.*?)<\/b>(.*)$/.exec(t);
  return b ? { flecha: m[1], antes: b[1], negrita: b[2], despues: b[3] } : { flecha: m[1], antes: t, negrita: '', despues: '' };
}

function vectoresVista() {
  zona(BA);
  const rnd = GEN.mulberry32(2026);
  const elegir = (xs) => xs[Math.floor(rnd() * xs.length)];
  const FUENTES_DB = ['apple_health', 'health_connect', 'oura', 'whoop', 'withings', 'polar', 'rook', 'manual', 'garmin'];
  const TIPOS = ['pasos', 'hrv_ms', 'sueno_min', 'fc_reposo', 'peso_kg', 'actividad_min'];
  const fechas = Array.from({ length: 12 }, (_, i) => `2026-10-${String(3 + i).padStart(2, '0')}`);
  const valores = [];
  for (let n = 0; n < 40; n++) {
    const salud = [];
    const filas = 1 + Math.floor(rnd() * 30);
    for (let k = 0; k < filas; k++) {
      const tipo = elegir(TIPOS);
      const r = { fecha: elegir(fechas), tipo, valor: rnd() < 0.05 ? null : Math.round(rnd() * 100000) / 100, fuente: elegir(FUENTES_DB) };
      if (tipo === 'hrv_ms' && rnd() < 0.7) r.detalle = { metrica: elegir(['sdnn', 'rmssd']), ventana: 'nocturna', n: 3 };
      salud.push(r);
    }
    STATE.salud = salud;
    const porTipo = {};
    for (const tipo of TIPOS) {
      porTipo[tipo] = { serie: vista._serieSalud(tipo), valores: fechas.map((f) => vista._saludValor(tipo, f)) };
    }
    HOY = elegir(fechas);
    const recientes = [7, 60, 1, 0].map((dias) => ({ dias, nocturnos: vista._saludTieneReciente(['fc_reposo', 'hrv_ms', 'sueno_min'], dias),
      diurnos: vista._saludTieneReciente(['pasos', 'actividad_min', 'kcal_activas'], dias) }));
    valores.push({ salud, fechas, porTipo, hoy: HOY, recientes });
  }
  const motivos = [];
  for (let n = 0; n < 120; n++) {
    const ms = Array.from({ length: Math.floor(rnd() * 5) }, () => {
      const tipo = elegir(['sueno', 'fc_reposo', 'hrv', 'carga', 'regularidad', 'otro']);
      const m = { tipo, dir: elegir([1, -1, 0]) };
      if (tipo === 'sueno') { m.valor = Math.round(rnd() * 6000) / 10; m.baseline = elegir([null, 0, Math.round(rnd() * 6000) / 10]); }
      if (tipo === 'fc_reposo') { m.valor = 40 + Math.round(rnd() * 400) / 10; m.baseline = elegir([null, 0, 40 + Math.round(rnd() * 400) / 10]); }
      if (tipo === 'hrv') { m.valor = Math.round(rnd() * 1500) / 10; m.baseline = elegir([null, 0, Math.round(rnd() * 1500) / 10]); }
      if (tipo === 'carga') m.agudo = elegir([12, 30, 7.5, '9']);
      return m;
    });
    const fila = { motivos: rnd() < 0.05 ? null : ms };
    const html = vista._recDrivers(fila);
    const divs = html ? html.split('</div>').filter(Boolean).map((d) => motivoDeHtml(d + '</div>')) : [];
    motivos.push({ motivos: fila.motivos, salida: divs });
  }
  const circular = [];
  for (let n = 0; n < 80; n++) {
    const vals = Array.from({ length: 1 + Math.floor(rnd() * 7) }, () => Math.round((rnd() * 1800 - 180) * 10) / 10);
    const { m, sd } = vista._promCircularMin(vals);
    circular.push({ vals, m, sd, dormirse: vista._hhmmReloj(m - 210), sdRedondo: Math.round(sd) });
  }
  const relojes = [-1500.5, -30, -0.5, 0, 0.4999, 59.5, 719.5, 1439.5, 1440, 2879.4, 100000.5].map((x) => ({ x, hhmm: vista._hhmmReloj(x) }));
  return { casos: [{ valores, motivos, circular, relojes }] };
}

// ── Escribir ─────────────────────────────────────────────────────────
const sal = path.join(RAIZ, 'apps/shared/vectores');
{
  const v = vectoresVista();
  fs.writeFileSync(path.join(sal, 'salud_vista.json'), JSON.stringify({ fuente: `public/cliente.html@${commit}`, ...v }) + '\n');
  const c = v.casos[0];
  console.log(`salud_vista: ${c.valores.length} escenarios de valores · ${c.motivos.length} de motivos · ${c.circular.length} de regularidad`);
}
fs.mkdirSync(sal, { recursive: true });
async function escribir(nombre, lista) {
  const casos = [];
  for (const c of lista) casos.push(await correr(c));
  const total = casos.reduce((n, c) => n + c.rpc.filter((x) => x.fn === 'mypump_ingest_salud').reduce((m, x) => m + x.lote.length, 0), 0);
  const entrenos = casos.reduce((n, c) => n + c.rpc.filter((x) => x.fn === 'mypump_ingest_entrenos').reduce((m, x) => m + x.lote.length, 0), 0);
  fs.writeFileSync(path.join(sal, `${nombre}.json`), JSON.stringify({ fuente: `public/js/healthkit-bridge.js@${commit}`, plugin: '@capgo/capacitor-health 8.9.3', casos }) + '\n');
  return { casos: casos.length, registros: total, entrenos, consultas: casos.reduce((n, c) => n + c.consultas.length, 0) };
}
const r1 = await escribir('salud_sync', casosSync);
const r2 = await escribir('salud_backfill', casosBackfill);
const r3 = await escribir('salud_conectar', casosConectar);
zona(BA);
for (const [n, r] of [['salud_sync', r1], ['salud_backfill', r2], ['salud_conectar', r3]]) {
  console.log(`${n}: ${r.casos} casos · ${r.consultas} consultas al plugin · ${r.registros} registros · ${r.entrenos} entrenos`);
}
