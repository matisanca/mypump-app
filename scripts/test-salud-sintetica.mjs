#!/usr/bin/env node
/* =============================================================
   test-salud-sintetica.mjs — el generador del banco no puede mentir

   POR QUÉ EXISTE
   Los datos sintéticos entran por el RPC real, que descarta en SILENCIO todo
   valor fuera de rango (049:78 hace CONTINUE, no falla). Si el generador se
   fuera de rango, el seeder posteaba, la card quedaba vacía y uno se pasaba una
   hora buscando el bug en el motor de recuperación.

   Los rangos NO se copian a mano: se PARSEAN de la migración 047. Así, si
   mañana alguien aprieta un rango en SQL y el generador queda afuera, este test
   se entera solo — que es exactamente la clase de desincronización que después
   se paga cara.

   USO:  node scripts/test-salud-sintetica.mjs
   ============================================================= */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
const GEN = require(path.join(RAIZ, 'public/js/salud-sintetica.js'));

let ok = 0, fail = 0;
const t = (nombre, fn) => {
  try { fn(); console.log(`  ✓ ${nombre}`); ok++; }
  catch (e) { console.log(`  ✗ ${nombre}\n      ${e.message}`); fail++; }
};
const eq = (a, b, msg) => { if (a !== b) throw new Error(`${msg}\n      esperado: ${b}\n      obtenido: ${a}`); };

/* Rangos reales, leídos de la migración. */
function rangosDeLaMigracion() {
  const sql = fs.readFileSync(path.join(RAIZ, 'supabase/migrations/047_salud_cobertura_completa.sql'), 'utf8');
  const rangos = {};
  const re = /WHEN\s+'([a-z0-9_]+)'\s+THEN\s+p_valor\s+BETWEEN\s+(-?\d+(?:\.\d+)?)\s+AND\s+(-?\d+(?:\.\d+)?)/gi;
  let m;
  while ((m = re.exec(sql))) rangos[m[1]] = [Number(m[2]), Number(m[3])];
  return rangos;
}

const RANGOS = rangosDeLaMigracion();

console.log('Generador de datos sintéticos de salud');

t('la migración 047 se pudo parsear (si no, el resto no prueba nada)', () => {
  if (Object.keys(RANGOS).length < 20) {
    throw new Error(`solo salieron ${Object.keys(RANGOS).length} rangos: cambió el formato del SQL`);
  }
  eq(RANGOS.fc_reposo[0], 25, 'fc_reposo mal parseado');
  eq(RANGOS.hrv_ms[1], 400, 'hrv_ms mal parseado');
});

for (const esc of GEN.ESCENARIOS) {
  t(`${esc}: ningún valor cae fuera de rango (el RPC los tiraría en silencio)`, () => {
    for (const r of GEN.filasIngest(esc, 60, 7)) {
      const rg = RANGOS[r.tipo];
      if (!rg) throw new Error(`tipo "${r.tipo}" no existe en el CHECK de la 047: el ingest lo rechaza entero`);
      if (!(r.valor >= rg[0] && r.valor <= rg[1])) {
        throw new Error(`${r.tipo}=${r.valor} fuera de [${rg[0]}, ${rg[1]}] el ${r.fecha}`);
      }
      if (!Number.isFinite(r.valor)) throw new Error(`${r.tipo} no es un número finito`);
    }
  });
}

t('sin-reloj NO manda nada de la noche (es el punto del escenario)', () => {
  const tipos = new Set(GEN.filasIngest('sin-reloj', 30, 1).map(r => r.tipo));
  for (const t2 of ['fc_reposo', 'hrv_ms', 'sueno_min']) {
    if (tipos.has(t2)) throw new Error(`mandó ${t2}: entonces no reproduce un iPhone sin reloj`);
  }
  if (!tipos.has('pasos')) throw new Error('no mandó ni pasos: no reproduce nada');
});

t('recien-conectado da 3 días aunque le pidas 60 (si no, no calibra)', () => {
  eq(new Set(GEN.filasIngest('recien-conectado', 60, 1).map(r => r.fecha)).size, 3, 'días generados');
});

t('la misma semilla da exactamente la misma serie', () => {
  const a = JSON.stringify(GEN.filasIngest('normal', 20, 99));
  const b = JSON.stringify(GEN.filasIngest('normal', 20, 99));
  eq(a, b, 'el generador no es determinista: un fallo intermitente sería irreproducible');
  const c = JSON.stringify(GEN.filasIngest('normal', 20, 100));
  if (a === c) throw new Error('cambiar la semilla no cambió nada: la semilla se ignora');
});

t('fatiga empeora de verdad contra su propio baseline', () => {
  const d = GEN.generarDias('fatiga', 60, 3);
  const prom = (arr, k) => arr.reduce((s, x) => s + x[k], 0) / arr.length;
  const viejos = d.slice(0, 30), nuevos = d.slice(-7);
  if (!(prom(nuevos, 'fc_reposo') > prom(viejos, 'fc_reposo') + 2)) {
    throw new Error('el pulso en reposo no subió: el motor no lo va a ver como fatiga');
  }
  if (!(prom(nuevos, 'hrv_ms') < prom(viejos, 'hrv_ms') - 5)) {
    throw new Error('la HRV no bajó: el motor no lo va a ver como fatiga');
  }
});

t('maladaptacion oscila más que fatiga (es lo que dispara cv_alto)', () => {
  const cv = (esc) => {
    const u = GEN.generarDias(esc, 60, 5).slice(-7).map(x => x.hrv_ms);
    const m = u.reduce((a, b) => a + b, 0) / u.length;
    return Math.sqrt(u.reduce((a, b) => a + (b - m) ** 2, 0) / u.length) / m;
  };
  const cvM = cv('maladaptacion'), cvF = cv('fatiga');
  if (!(cvM > cvF)) {
    throw new Error(`maladaptacion CV=${cvM.toFixed(3)} no supera a fatiga CV=${cvF.toFixed(3)}: ` +
                    'los dos escenarios serían indistinguibles para el motor');
  }
});

t('las muestras HealthKit tienen la forma que espera el bridge', () => {
  const ms = GEN.muestras('normal', 10, 2);
  for (const tipo of ['steps', 'restingHeartRate', 'heartRateVariability', 'sleep']) {
    if (!ms[tipo] || !ms[tipo].length) throw new Error(`no generó muestras de ${tipo}`);
    for (const s of ms[tipo]) {
      if (!s.startDate || !s.endDate) throw new Error(`${tipo}: falta startDate/endDate`);
      if (isNaN(new Date(s.startDate))) throw new Error(`${tipo}: startDate no es una fecha ISO`);
      if (new Date(s.endDate) < new Date(s.startDate)) throw new Error(`${tipo}: termina antes de empezar`);
    }
  }
  // El plugin entrega SDNN en segundos; si el generador diera ms, el bridge lo
  // multiplicaría por 1000 y guardaría HRV de 65000 ms.
  if (!ms.heartRateVariability.every(s => s.value < 1)) {
    throw new Error('la HRV sintética no está en segundos: el bridge la va a convertir mal');
  }
  if (!ms.sleep.some(s => s.sleepState === 'inBed')) throw new Error('sin inBed no se puede probar la dedup de sueño');
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
