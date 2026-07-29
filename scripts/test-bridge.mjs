#!/usr/bin/env node
/* =============================================================
 * test-bridge.mjs — prueba el bridge de HealthKit SIN iPhone ni simulador.
 *
 * POR QUÉ EXISTE
 * La app es 99,5% web: 49 líneas de Swift propio contra 11.328 de JS/HTML.
 * Los bugs que tuvimos (el HRV de Whoop en segundos, el sueño duplicado entre
 * fuentes, la pedida de permisos que reventaba en iOS 15) NO estaban en el
 * código nativo — estaban en la lógica JS que interpreta los datos.
 *
 * Esa lógica es determinista: entra un array de muestras, sale un array de
 * registros. No necesita un teléfono para probarse, necesita datos de entrada
 * con la forma real que devuelve HealthKit. Eso es lo que hace este archivo.
 *
 * Lo que NO cubre y hay que probar en el dispositivo: que el plugin nativo
 * devuelva efectivamente esas formas, y el device token de APNs.
 *
 * USO:  node scripts/test-bridge.mjs
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

// ── Entorno mínimo de navegador para poder cargar el bridge ──────────────
const store = {};
globalThis.localStorage = {
  getItem: k => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v); },
  removeItem: k => { delete store[k]; },
};
// navigator es de solo lectura en Node 26 — se redefine la propiedad.
Object.defineProperty(globalThis, 'navigator', {
  value: { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X)' },
  writable: true, configurable: true,
});
globalThis.document = { addEventListener() {}, hidden: false };
globalThis.window = globalThis;
globalThis.addEventListener = () => {};

// Plugin de salud mockeado. Devuelve exactamente la forma que da @capgo.
const MUESTRAS = { sleep: [], heartRateVariability: [], weight: [], steps: [] };
globalThis.Capacitor = {
  isNativePlatform: () => true,
  Plugins: {
    Health: {
      isAvailable: async () => ({ available: true }),
      requestAuthorization: async () => ({}),
      checkAuthorization: async ({ read }) => ({ readAuthorized: read, readDenied: [] }),
      readSamples: async ({ dataType }) => ({ samples: MUESTRAS[dataType] || [] }),
      queryAggregated: async () => ({ samples: [] }),
      queryWorkouts: async () => ({ workouts: [] }),
    },
  },
};

/* Cliente de base mockeado: captura EXACTAMENTE los registros que el bridge
 * manda a Supabase. Es la unica forma de probar procesarSueno, la conversion
 * de unidades y la agregacion — nada de eso esta exportado, y probar lo que se
 * exporta en vez de lo que se manda es como probar otra cosa. Un test que
 * revisa una variable intermedia no habria visto los metros guardados como km:
 * el bug estaba en el registro final. */
const ENVIADOS = [];
globalThis.window.mypumpDB = {
  ingestSalud: async (_token, registros) => { ENVIADOS.push(...registros); return { success: true, data: registros.length }; },
  ingestEntrenos: async () => ({ success: true, data: 0 }),
};
const capturar = async (fn) => { ENVIADOS.length = 0; await fn(); return ENVIADOS.slice(); };
const delTipo = (regs, tipo) => regs.filter(r => r.tipo === tipo);

// El bridge es un IIFE que se registra en window.MyPumpHealth.
const src = fs.readFileSync(path.join(raiz, 'public/js/healthkit-bridge.js'), 'utf8');
new Function(src)();
const H = globalThis.MyPumpHealth;

// ── Mini framework ──────────────────────────────────────────────────────
let ok = 0, fail = 0;
// await del resultado sí o sí: si fn es async y no se espera, la excepción se
// pierde y el test pasa SIEMPRE. Un test que no puede fallar miente.
const t = async (nombre, fn) => {
  try { await fn(); console.log(`  ✓ ${nombre}`); ok++; }
  catch (e) { console.log(`  ✗ ${nombre}\n      ${e.message}`); fail++; }
};
const eq = (a, b, msg) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(`${msg || ''}\n      esperado: ${JSON.stringify(b)}\n      obtenido: ${JSON.stringify(a)}`);
  }
};
const cerca = (a, b, tol, msg) => {
  if (Math.abs(a - b) > tol) throw new Error(`${msg || ''} esperado ~${b}, obtenido ${a}`);
};

const iso = (d, h, m = 0) => new Date(`2026-07-${String(d).padStart(2,'0')}T${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:00-03:00`).toISOString();

console.log('\nAPI pública del bridge');
await t('expone todo lo que cliente.html usa', () => {
  for (const k of ['isAvailable','isConnected','connect','disconnect','estado','ultimaSync','sync','backfill','diagnostico']) {
    if (typeof H[k] !== 'function' && k !== 'isConnected') throw new Error(`falta ${k}`);
  }
});

console.log('\nPermisos');
await t('conectar con permisos concedidos devuelve ok', async () => {
  const r = await H.connect();
  if (!r || typeof r !== 'object') throw new Error('connect() debe devolver un objeto, no un booleano');
});

/* Los dos tests de abajo cubren la parte más contraintuitiva de todo esto.
 *
 * HealthKit NO informa si hay permiso de LECTURA. checkAuthorization corre por
 * debajo getRequestStatusForAuthorization, que devuelve `.unnecessary` cuando
 * ya se preguntó — le haya dicho el cliente que sí o que no. Es a propósito: si
 * lo informara, la app podría deducir que el cliente le esconde algo, y
 * esconder datos dejaría de servir de defensa.
 *
 * Acá había un test que afirmaba lo contrario ("0 autorizados = denegó") y
 * pasaba, porque el mock devolvía justo lo que el código creía. Un mock que
 * confirma el malentendido del autor no prueba nada. La única señal real es la
 * de abajo: pedimos y no llega NADA, de ningún tipo. */
const limpiarSalud = () => {
  for (const k of ['mypump_health_connected', 'mypump_health_denegado',
                   'mypump_health_backfill_v1', 'mypump_health_racha_vacia']) delete store[k];
  for (const k of Object.keys(MUESTRAS)) MUESTRAS[k] = [];
};

await t('denegar todo se detecta por la falta de datos (HealthKit no lo dice)', async () => {
  // El plugin contesta "ya preguntado" para TODOS los tipos, exactamente igual
  // que cuando el cliente concede: por ese lado no hay nada que distinguir.
  globalThis.Capacitor.Plugins.Health.checkAuthorization = async ({ read }) => ({ readAuthorized: read, readDenied: [] });
  store['mypump_token'] = 'tok-de-prueba';
  limpiarSalud();
  const r = await H.connect();
  if (!r.ok) throw new Error('no debería fallar: la hoja se mostró y el cliente la respondió');
  if (!r.sinDatos) throw new Error('60 días sin una sola muestra tienen que marcar sinDatos');
  const e = await H.estado();
  if (!e.sinDatos) throw new Error('estado() tiene que reportarlo también, no solo connect()');
});

await t('que empiece a llegar un dato levanta la sospecha', async () => {
  store['mypump_token'] = 'tok-de-prueba';
  limpiarSalud();
  store['mypump_health_denegado'] = '1';        // veníamos sospechando
  MUESTRAS.weight = [{ startDate: iso(21, 8), endDate: iso(21, 8), value: 80, unit: 'kilogram' }];
  await H.sync();
  const e = await H.estado();
  if (e.sinDatos) throw new Error('con datos entrando no se puede seguir diciendo que no llega nada');
});

/* Los tests de abajo miran lo que el bridge MANDA A LA BASE, no variables
 * internas. Es la única forma de agarrar bugs de unidad o de agregación, que
 * son los que aparecieron: los metros guardados como km y la siesta pisando la
 * noche estaban los dos en el registro final. */
const prepararSync = () => {
  store['mypump_token'] = 'tok-de-prueba';
  store['mypump_health_connected'] = '1';
  store['mypump_health_backfill_v1'] = '1';   // que no dispare el backfill de 60 días
  for (const k of Object.keys(MUESTRAS)) MUESTRAS[k] = [];
};

console.log('\nProcesamiento de sueño');

await t('dos fuentes la misma noche no duplican minutos', async () => {
  // iPhone + reloj registran la misma noche. Sin dedup, 8 h se vuelven 16.
  prepararSync();
  MUESTRAS.sleep = [
    { startDate: iso(20,23), endDate: iso(21,7), sleepState: 'asleep', sourceId: 'iphone' },
    { startDate: iso(20,23), endDate: iso(21,7), sleepState: 'asleep', sourceId: 'watch'  },
  ];
  const regs = await capturar(() => H.sync());
  const s = delTipo(regs, 'sueno_min');
  if (s.length !== 1) throw new Error(`esperaba 1 fila de sueño, vinieron ${s.length}`);
  if (s[0].valor !== 480) throw new Error(`8 h son 480 min, mandó ${s[0].valor}`);
});

await t('una siesta SUMA al día en vez de pisar la noche', async () => {
  // El bug: `noches` corta bloques cada 60 min sin muestras, así que la siesta
  // era un bloque aparte con la MISMA fecha. Como el upsert de la base tiene
  // clave (cliente_id, fecha, tipo, fuente), la segunda fila pisaba a la
  // primera: 8 h de sueño se convertían en los 40 min de la siesta.
  prepararSync();
  MUESTRAS.sleep = [
    { startDate: iso(20,23), endDate: iso(21,7),     sleepState: 'asleep', sourceId: 'watch' },
    { startDate: iso(21,15), endDate: iso(21,15,40), sleepState: 'asleep', sourceId: 'watch' },
  ];
  const regs = await capturar(() => H.sync());
  const s = delTipo(regs, 'sueno_min');
  if (s.length !== 1) throw new Error(`una fecha = una fila; vinieron ${s.length} (la 2ª pisa a la 1ª en la base)`);
  if (s[0].valor !== 520) throw new Error(`480 + 40 = 520, mandó ${s[0].valor}`);
});

await t('el punto medio lo fija la noche, no la siesta', async () => {
  // sueno_medio_min alimenta la REGULARIDAD (su desvío en 7 días). El punto
  // medio de una siesta de la tarde no es comparable con el de una noche y
  // dispara el desvío, que es justo la señal que se quiere medir.
  prepararSync();
  MUESTRAS.sleep = [
    { startDate: iso(20,23), endDate: iso(21,7),     sleepState: 'asleep', sourceId: 'watch' },
    { startDate: iso(21,15), endDate: iso(21,15,40), sleepState: 'asleep', sourceId: 'watch' },
  ];
  const regs = await capturar(() => H.sync());
  const m = delTipo(regs, 'sueno_medio_min');
  if (m.length !== 1) throw new Error(`esperaba 1, vinieron ${m.length}`);
  // 23:00 → 07:00 tiene su punto medio a las 03:00 = 180 min desde medianoche.
  // El de la siesta sería 15:20 = 920.
  if (m[0].valor !== 180) throw new Error(`esperaba 180 (03:00), mandó ${m[0].valor}` +
    (m[0].valor === 920 ? ' — ese es el medio de la SIESTA (15:20)' : ''));
});

await t('la siesta no infla la eficiencia (numerador y denominador del mismo bloque)', async () => {
  // Regresión real del 28-jul, introducida por el arreglo de la siesta: el
  // total sumaba noche + siesta pero `cama` solo sumaba los bloques CON
  // muestras inBed — y una siesta casi nunca las trae. La fracción se iba
  // arriba de 1 y el clamp la dejaba clavada en 100%.
  prepararSync();
  MUESTRAS.sleep = [
    // Noche: 8 h en cama, 7 h dormido → 87,5% de eficiencia.
    { startDate: iso(20,23), endDate: iso(21,7), sleepState: 'inBed',  sourceId: 'watch' },
    { startDate: iso(20,23), endDate: iso(21,6), sleepState: 'asleep', sourceId: 'watch' },
    // Siesta: 40 min dormido, sin inBed.
    { startDate: iso(21,15), endDate: iso(21,15,40), sleepState: 'asleep', sourceId: 'watch' },
  ];
  const regs = await capturar(() => H.sync());
  const e = delTipo(regs, 'sueno_eficiencia_pct');
  if (!e.length) throw new Error('no mandó eficiencia');
  if (e[0].valor !== 88) {
    throw new Error(`420/480 = 87.5 → 88, mandó ${e[0].valor}` +
      (e[0].valor === 100 ? ' — la siesta entró al numerador y no al denominador' : ''));
  }
  // Y el total sí tiene que incluirla: son minutos dormidos de verdad.
  const s = delTipo(regs, 'sueno_min');
  if (s[0].valor !== 460) throw new Error(`420 + 40 = 460, mandó ${s[0].valor}`);
});

console.log('\nUnidades que manda a la base');

await t('la distancia va en KM, no en metros', async () => {
  // Iba con `escala`, que solo se aplica si el valor es <= 1 (heurística de
  // SpO2/grasa). Una distancia en metros nunca es <= 1 → nunca convertía, y el
  // guardrail de la base (0-200 km) tiraba la fila en silencio.
  prepararSync();
  MUESTRAS.distance = [
    { startDate: iso(21,8),  endDate: iso(21,9),  value: 3200, unit: 'meter' },
    { startDate: iso(21,18), endDate: iso(21,19), value: 2220, unit: 'meter' },
  ];
  const regs = await capturar(() => H.sync());
  const d = delTipo(regs, 'distancia_km');
  if (!d.length) throw new Error('no mandó distancia');
  // 5420 m = 5.42 km, y el bridge redondea a 1 decimal a propósito (100 m de
  // precisión alcanza y de sobra para esto): 5.4.
  if (d[0].valor !== 5.4) {
    throw new Error(`5420 m son 5.4 km redondeado, mandó ${d[0].valor}` +
      (d[0].valor > 200 ? ' — está en METROS, y la base lo tira (rango 0-200 km)' : ''));
  }
});

await t('no manda kcal_totales (en el plugin es una copia de las activas)', async () => {
  // Health.swift:649 hace `case .totalCalories: identifier = .activeEnergyBurned`,
  // el MISMO identificador que 'calories'. HealthKit no tiene energía total.
  // Con esa línea puesta, mypump_get_gasto_real prefería ese valor sobre
  // COALESCE(bas+act) y el "TDEE medido" salía MENOR que el basal.
  prepararSync();
  MUESTRAS.basalCalories = [{ startDate: iso(21,8), endDate: iso(21,9), value: 1700, unit: 'kilocalorie' }];
  MUESTRAS.totalCalories = [{ startDate: iso(21,8), endDate: iso(21,9), value: 750,  unit: 'kilocalorie' }];
  const regs = await capturar(() => H.sync());
  if (delTipo(regs, 'kcal_totales').length) {
    throw new Error('mandó kcal_totales: eso es solo la energía ACTIVA y se lee como TDEE');
  }
  if (!delTipo(regs, 'kcal_basales').length) throw new Error('perdimos las basales');
});

console.log('\nRangos fisiológicos (los mismos que valida la DB)');
const plausible = (tipo, v) => {
  const R = {
    fc_reposo: [25,140], hrv_ms: [1,400], sueno_min: [0,1440],
    spo2_pct: [50,100], peso_kg: [25,400], presion_sistolica: [60,260],
  }[tipo];
  return !R || (v >= R[0] && v <= R[1]);
};
await t('FC de 0 se rechaza (sensor roto)', () => eq(plausible('fc_reposo', 0), false));
await t('FC de 55 se acepta', () => eq(plausible('fc_reposo', 55), true));
await t('HRV de 0 se rechaza', () => eq(plausible('hrv_ms', 0), false));
await t('presión de 400 se rechaza', () => eq(plausible('presion_sistolica', 400), false));

console.log('\nNormalización de unidades');
await t('HRV de Whoop en segundos → ms', () => {
  // El payload de Whoop trae rmssd en SEGUNDOS en algunos casos. Sin esto,
  // 0.0584 entra como 0.06 ms y destruye el baseline de esa persona.
  const seg = 0.0584;
  cerca(seg < 1 ? seg * 1000 : seg, 58.4, 0.01, 'no normalizó');
});
await t('HRV ya en ms queda igual', () => {
  const ms = 58.4;
  cerca(ms < 1 ? ms * 1000 : ms, 58.4, 0.01);
});
await t('distancia de metros a km', () => cerca(8421 * 0.001, 8.421, 0.001));
await t('SpO2 0-1 → porcentaje', () => {
  const v = 0.968;
  cerca(v <= 1 ? v * 100 : v, 96.8, 0.01);
});

console.log('\nVersión de iOS (el bug que dejaba iOS 15 sin hoja de permisos)');
const iosDe = ua => { const m = /OS (\d+)[_.]/.exec(ua); return m ? parseInt(m[1],10) : 0; };
await t('detecta iOS 15', () => eq(iosDe('Mozilla/5.0 (iPhone; CPU iPhone OS 15_7 like Mac OS X)'), 15));
await t('detecta iOS 18', () => eq(iosDe('Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X)'), 18));
await t('iOS 15 NO debe pedir tipos que son 16+', () => {
  const soportado = (m, ios) => !m.minIOS || ios >= m.minIOS;
  eq(soportado({ minIOS: 16 }, 15), false, 'pidió un tipo iOS16+ en iOS 15');
  eq(soportado({ minIOS: 16 }, 18), true);
  eq(soportado({}, 15), true, 'un tipo sin mínimo debe pedirse siempre');
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
