#!/usr/bin/env node
/* =============================================================
   test-bridge-android.mjs — el bridge corriendo como Android

   POR QUÉ UN ARCHIVO APARTE
   El bridge lee la plataforma UNA vez, al evaluarse (es un IIFE). No hay forma
   de cambiarla en caliente, así que Android necesita su propia carga con su
   propio mock de Capacitor. test-bridge.mjs sigue siendo el de iOS y no se
   toca — así, si un cambio para Android rompe iPhone, salta ahí.

   QUÉ PROTEGE
   Cuatro cosas que si salen mal no dan error, dan datos silenciosamente malos:

   1. exerciseTime y appleSleepingWristTemperature NO existen en el enum de
      Kotlin. Pedirlos voltea el pedido de permisos ENTERO — el mismo bug que
      vo2Max nos hizo en iOS, donde los 13 tipos de la tanda secundaria se
      quedaban sin autorizar y cada readSamples devolvía "Authorization not
      determined". El cliente conecta, la app dice que sí, y no llega nada.

   2. La fuente. Los datos de Android van con fuente 'health_connect'. Si
      fueran como 'apple_health', el motor desempataría sobre una etiqueta
      falsa y el panel le mostraría "Apple Health" a alguien con un Samsung.

   3. La métrica de HRV. Health Connect solo tiene rMSSD; HealthKit solo SDNN.
      El motor le da MÁS peso al rMSSD (45 vs 40) porque el SDNN del Apple
      Watch tiene ~29% de error. Etiquetarlo mal le baja el peso a un dato que
      es mejor.

   4. basalCalories, que es un factor 4x. En Android el plugin devuelve
      BasalMetabolicRateRecord.inKilocaloriesPerDay — una TASA, el mismo ~1.800
      repetido en cada lectura. Sumarlo da 7.200 kcal de metabolismo basal, y
      ese número entra a mypump_get_gasto_real y el coach lo lee como "TDEE
      medido".

   USO:  node scripts/test-bridge-android.mjs
   ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// ── Entorno: mismo esqueleto que test-bridge.mjs, pero Android ──────────
const store = {};
globalThis.localStorage = {
  getItem: k => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: k => { delete store[k]; },
};
Object.defineProperty(globalThis, 'navigator', {
  // UA de Android: sin "OS 18_2", así que iosMajor() da 0. Es a propósito —
  // verifica que el filtro por minIOS no se cuelgue en Android.
  value: { userAgent: 'Mozilla/5.0 (Linux; Android 14; SM-S911B) AppleWebKit/537.36' },
  writable: true, configurable: true,
});
globalThis.document = { addEventListener() {}, hidden: false };
globalThis.window = globalThis;
globalThis.addEventListener = () => {};

const MUESTRAS = {};
const PEDIDOS = [];            // lo que se pidió autorizar, en orden
globalThis.Capacitor = {
  isNativePlatform: () => true,
  getPlatform: () => 'android',           // ← lo único que cambia
  Plugins: {
    Health: {
      isAvailable: async () => ({ available: true }),
      requestAuthorization: async ({ read }) => { PEDIDOS.push(...read); return {}; },
      checkAuthorization: async ({ read }) => ({ readAuthorized: read, readDenied: [] }),
      readSamples: async ({ dataType }) => ({ samples: MUESTRAS[dataType] || [] }),
      queryAggregated: async () => ({ samples: [] }),
      queryWorkouts: async () => ({ workouts: [] }),
    },
  },
};

const ENVIADOS = [];
globalThis.window.mypumpDB = {
  ingestSalud: async (_t, regs) => { ENVIADOS.push(...regs); return { success: true, data: regs.length }; },
  ingestEntrenos: async () => ({ success: true, data: 0 }),
};
const capturar = async (fn) => { ENVIADOS.length = 0; await fn(); return ENVIADOS.slice(); };
const delTipo = (regs, tipo) => regs.filter(r => r.tipo === tipo);

const src = fs.readFileSync(path.join(raiz, 'public/js/healthkit-bridge.js'), 'utf8');
new Function(src)();
const H = globalThis.MyPumpHealth;

// ── Framework ───────────────────────────────────────────────────────────
let ok = 0, fail = 0;
const t = async (n, fn) => {
  try { await fn(); console.log(`  ✓ ${n}`); ok++; }
  catch (e) { console.log(`  ✗ ${n}\n      ${e.message}`); fail++; }
};
const si = (c, m) => { if (!c) throw new Error(m); };
const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}\n      esperado ${JSON.stringify(b)}\n      obtenido ${JSON.stringify(a)}`); };

const iso = (d, h, m = 0) => new Date(`2026-07-${String(d).padStart(2,'0')}T${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:00-03:00`).toISOString();
const prepararSync = () => {
  store['mypump_token'] = 'tok';
  store['mypump_health_connected'] = '1';
  store['mypump_health_backfill_v1'] = '1';
  for (const k of Object.keys(MUESTRAS)) delete MUESTRAS[k];
  PEDIDOS.length = 0;
};

// ── Tipos pedidos ───────────────────────────────────────────────────────
console.log('\nQué tipos se le piden a Health Connect');

await t('NO se piden los dos tipos que Android no conoce', async () => {
  prepararSync();
  await H.connect({ esperarBackfill: true });
  for (const prohibido of ['exerciseTime', 'appleSleepingWristTemperature']) {
    si(!PEDIDOS.includes(prohibido),
       `se pidió '${prohibido}', que no existe en el enum de Kotlin → el pedido ENTERO se cae y ningún tipo queda autorizado`);
  }
});

await t('SÍ se piden los tres que alimentan el score de recuperación', async () => {
  prepararSync();
  await H.connect({ esperarBackfill: true });
  for (const nec of ['restingHeartRate', 'sleep', 'heartRateVariability']) {
    si(PEDIDOS.includes(nec), `falta '${nec}': sin él no hay score`);
  }
});

await t('se sigue pidiendo workouts (va aparte del enum)', async () => {
  prepararSync();
  await H.connect({ esperarBackfill: true });
  si(PEDIDOS.includes('workouts'), 'sin esto los entrenos del reloj no llegan');
});

// ── Fuente y métrica ────────────────────────────────────────────────────
console.log('\nCómo se etiqueta lo que llega');

await t("todo se graba con fuente 'health_connect', nunca 'apple_health'", async () => {
  prepararSync();
  MUESTRAS.weight = [{ startDate: iso(21, 8), endDate: iso(21, 8), value: 80, unit: 'kilogram' }];
  const regs = await capturar(() => H.sync());
  si(regs.length, 'no se mandó nada');
  const malas = regs.filter(r => r.fuente !== 'health_connect');
  eq(malas.map(r => r.fuente), [], 'hay registros con la fuente equivocada');
});

await t("el HRV se etiqueta 'rmssd', que es lo que da Health Connect", async () => {
  prepararSync();
  MUESTRAS.heartRateVariability = [
    { startDate: iso(21, 3), endDate: iso(21, 3), value: 0.055, unit: 'second' },
    { startDate: iso(21, 4), endDate: iso(21, 4), value: 0.061, unit: 'second' },
  ];
  const hrv = delTipo(await capturar(() => H.sync()), 'hrv_ms');
  si(hrv.length, 'no se mandó HRV');
  eq(hrv[0].detalle.metrica, 'rmssd',
     'etiquetado como SDNN: el motor le baja el peso de 45 a 40 a un dato que en realidad es mejor');
});

// ── basalCalories: el factor 4x ─────────────────────────────────────────
console.log('\nbasalCalories: una TASA, no un acumulado');

await t('4 lecturas de ~1.800 kcal/día NO dan 7.200', async () => {
  prepararSync();
  // Lo que devuelve HealthManager.kt:380-388: el mismo BMR repetido.
  MUESTRAS.basalCalories = [1795, 1800, 1805, 1800].map((v, i) => ({
    startDate: iso(21, 6 + i), endDate: iso(21, 6 + i), value: v, unit: 'kilocalorie',
  }));
  const bas = delTipo(await capturar(() => H.sync()), 'kcal_basales');
  si(bas.length, 'no se mandó kcal_basales');
  const v = bas[0].valor;
  si(v > 1500 && v < 2100,
     `kcal_basales = ${v}. Es una tasa repetida: sumarla da ~7.200 y el coach lo lee como "TDEE medido"`);
});

// ── Que no se haya roto iOS de rebote ───────────────────────────────────
console.log('\nEl filtro por plataforma no se pasa de largo');

await t('minIOS no descarta nada en Android (el UA no tiene versión de iOS)', async () => {
  prepararSync();
  await H.connect({ esperarBackfill: true });
  // respiratoryRate no tiene minIOS y sí existe en Kotlin: tiene que estar.
  si(PEDIDOS.includes('respiratoryRate'),
     'el filtro de versión de iOS se está aplicando en Android y descarta tipos válidos');
});

await t('la plataforma se resuelve como android', async () => {
  const d = await H.diagnostico();
  si(d && typeof d === 'object', 'diagnostico() no devolvió nada');
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
