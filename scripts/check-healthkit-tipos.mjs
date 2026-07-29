#!/usr/bin/env node
/* =============================================================
   check-healthkit-tipos.mjs — cotejar los tipos que pide el bridge
   contra lo que el plugin IMPLEMENTA DE VERDAD en iOS.

   POR QUÉ EXISTE
   El 29-jul-2026 la conexión a Apple Health quedaba a medias y nadie lo veía:
   13 de los 19 tipos de datos nunca pedían permiso. La causa fue una sola
   línea del bridge pidiendo 'vo2Max'.

   'vo2Max' está declarado en el union HealthDataType del plugin
   (dist/esm/definitions.d.ts) — o sea que TypeScript lo acepta y el editor lo
   autocompleta — pero NO existe en el enum de Swift (Health.swift), que es el
   que realmente valida. Cero menciones en todo el fuente iOS del plugin.

   Y no falla solo ese tipo: el plugin parsea TODOS los identificadores ANTES
   de hablar con HealthKit (Health.swift:1344 parseTypesWithWorkouts), así que
   uno desconocido tira el pedido COMPLETO. La tanda entera se caía, el catch
   la tragaba con un console.warn, y el síntoma aparecía mucho después y en
   otro lado: cada readSamples devolviendo "Authorization not determined".

   O sea: la fuente de verdad NO son los tipos de TypeScript. Es el enum de
   Swift. Este script compara contra ese.

   QUÉ VERIFICA
   1. Todo dataType que el bridge pide existe en el enum de Swift.
   2. Todo lo que va por queryAggregated está en la matriz chica que el plugin
      acepta (Health.swift:1480), con una agregación válida para ese tipo.
   3. Reporta el drift TypeScript↔Swift del plugin, para saber qué tipos son
      trampas aunque hoy no los usemos.
   ============================================================= */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const PLUGIN = join(RAIZ, 'node_modules/@capgo/capacitor-health');
const BRIDGE = join(RAIZ, 'public/js/healthkit-bridge.js');
const SWIFT = join(PLUGIN, 'ios/Sources/HealthPlugin/Health.swift');
const DTS = join(PLUGIN, 'dist/esm/definitions.d.ts');

const leer = (p) => {
  try { return readFileSync(p, 'utf8'); }
  catch { console.error(`✗ No pude leer ${p}`); process.exit(1); }
};

/* ── 1. Lo que el plugin implementa DE VERDAD (enum de Swift) ────────── */
const swiftSrc = leer(SWIFT);
const mEnum = /enum HealthDataType: String, CaseIterable \{([\s\S]*?)\n\s*func /.exec(swiftSrc);
if (!mEnum) {
  console.error('✗ No encontré el enum HealthDataType en Health.swift.');
  console.error('  El plugin cambió de forma: revisá este script antes de confiar en él.');
  process.exit(1);
}
const swiftTipos = [...mEnum[1].matchAll(/^\s*case (\w+)/gm)].map((m) => m[1]);

// 'workouts' no es un case del enum: parseTypesWithWorkouts lo trata aparte
// (Health.swift:1349) antes de intentar el HealthDataType(rawValue:).
const ACEPTA_NATIVO = new Set([...swiftTipos, 'workouts']);

/* ── 2. Lo que el plugin DECLARA en TypeScript (puede mentir) ────────── */
const dts = leer(DTS);
const mUnion = /export type HealthDataType\s*=\s*([\s\S]*?);/.exec(dts);
const tsTipos = mUnion ? [...mUnion[1].matchAll(/'([^']+)'/g)].map((m) => m[1]) : [];

/* ── 3. Lo que el bridge pide ────────────────────────────────────────── */
const bridge = leer(BRIDGE);

// Se parsean los literales de las tablas AGG y SAMPLES en vez de importar el
// módulo: el bridge es un IIFE que toca window/localStorage y no corre en node.
const bloque = (nombre) => {
  const m = new RegExp(`const ${nombre} = \\[([\\s\\S]*?)\\n  \\];`).exec(bridge);
  if (!m) { console.error(`✗ No encontré la tabla ${nombre} en el bridge.`); process.exit(1); }
  return m[1];
};

const filas = (txt) =>
  [...txt.matchAll(/\{[^}]*dataType:\s*'([^']+)'[^}]*\}/g)].map((m) => ({
    dataType: m[1],
    agg: (/agg:\s*'([^']+)'/.exec(m[0]) || [])[1] || null,
  }));

const agg = filas(bloque('AGG'));
const samples = filas(bloque('SAMPLES'));

// NUCLEO y los sueltos que tiposLectura() concatena.
const mNucleo = /const NUCLEO = \[([^\]]*)\]/.exec(bridge);
const nucleo = mNucleo ? [...mNucleo[1].matchAll(/'([^']+)'/g)].map((m) => m[1]) : [];
const mExtra = /\.concat\(\[([^\]]*)\]\)/.exec(bridge);
const extra = mExtra ? [...mExtra[1].matchAll(/'([^']+)'/g)].map((m) => m[1]) : [];

const pedidos = [...new Set([
  ...agg.map((r) => r.dataType),
  ...samples.map((r) => r.dataType),
  ...nucleo,
  ...extra,
])];

/* ── 4. Verificaciones ───────────────────────────────────────────────── */
let fallas = 0;
const fallar = (msg) => { console.error(`  ✗ ${msg}`); fallas++; };
// Para no cantar "✓" en un bloque que acaba de fallar: se compara el contador
// contra el que había al entrar. Un OK mentiroso es peor que no imprimir nada.
const okSi = (antes, msg) => { if (fallas === antes) console.log(`   ✓ ${msg}`); };

console.log(`enum de Swift: ${swiftTipos.length} tipos · union de TS: ${tsTipos.length}`);
console.log(`el bridge pide: ${pedidos.length} tipos\n`);

console.log('1. Todo tipo pedido existe en el enum de Swift');
const antes1 = fallas;
for (const t of pedidos) {
  if (!ACEPTA_NATIVO.has(t)) {
    const enTS = tsTipos.includes(t);
    fallar(
      `'${t}' NO está en el enum de Swift` +
      (enTS
        ? ` — SÍ está en el union de TypeScript, que acá miente.\n` +
          `      El plugin valida todos los tipos juntos, así que este solo` +
          ` tira la tanda ENTERA\n` +
          `      y los demás se quedan sin pedir permiso, en silencio.`
        : ' ni en el union de TypeScript (typo?).')
    );
  }
}
okSi(antes1, `los ${pedidos.length} entran`);
console.log('');

console.log('2. queryAggregated: solo la matriz chica que el plugin acepta');
const antes2 = fallas;
// Health.swift:1480 — cumulativos solo 'sum'; discretos solo average/min/max.
const MATRIZ = {
  steps: ['sum'], distance: ['sum'], calories: ['sum'],
  heartRate: ['average', 'min', 'max'],
  weight: ['average', 'min', 'max'],
  restingHeartRate: ['average', 'min', 'max'],
};
for (const r of agg) {
  const ok = MATRIZ[r.dataType];
  if (!ok) {
    fallar(`'${r.dataType}' va por queryAggregated pero el plugin lo rechaza en nativo. Usá readSamples.`);
  } else if (r.agg && !ok.includes(r.agg)) {
    fallar(`'${r.dataType}' pide agg '${r.agg}'; el plugin solo acepta ${ok.join('/')}.`);
  }
}
// El inverso: un tipo que el plugin NO agrega, pedido por el camino agregado.
const RECHAZA_AGG = ['sleep', 'respiratoryRate', 'oxygenSaturation', 'heartRateVariability'];
for (const t of RECHAZA_AGG) {
  if (agg.some((r) => r.dataType === t)) {
    fallar(`'${t}' está en AGG y el plugin lo rechaza explícitamente en nativo (Health.swift:1456).`);
  }
}
okSi(antes2, `las ${agg.length} entradas de AGG son válidas`);
console.log('');

console.log('3. Todo lo que se LEE está en la lista de permisos');
const antes3 = fallas;
// El invariante que hubiera cazado los dos bugs del 29-jul de una: en
// HealthKit, leer sin haber pedido ese tipo NO da error visible al usuario —
// da "Authorization not determined" en un log que nadie mira, y la métrica
// simplemente no aparece nunca.
const autorizados = new Set([...nucleo, ...agg.map((r) => r.dataType),
  ...samples.map((r) => r.dataType), ...extra]);
const leidos = [
  ...agg.map((r) => ({ tipo: r.dataType, via: 'queryAggregated' })),
  ...samples.map((r) => ({ tipo: r.dataType, via: 'readSamples' })),
];
// queryWorkouts lee HKWorkoutTypeIdentifier, cuyo permiso se pide con el
// identificador 'workouts' (Health.swift:1349). No sale de ninguna tabla.
if (/h\.queryWorkouts\(/.test(bridge)) leidos.push({ tipo: 'workouts', via: 'queryWorkouts' });
for (const l of leidos) {
  if (!autorizados.has(l.tipo)) {
    fallar(`'${l.tipo}' se lee por ${l.via} pero NO está en el pedido de permisos.\n` +
           `      HealthKit no avisa: devuelve "Authorization not determined" y el dato no llega nunca.`);
  }
}
okSi(antes3, `los ${leidos.length} tipos que se leen están autorizados`);
console.log('');

console.log('4. Drift del plugin (TypeScript declara, Swift no implementa)');
const trampas = tsTipos.filter((t) => !ACEPTA_NATIVO.has(t));
if (trampas.length) {
  console.log(`   ⚠ ${trampas.join(', ')} — declarados en TS, ausentes en iOS. NO usarlos.`);
} else {
  console.log('   ✓ sin drift');
}

console.log('');
if (fallas) {
  console.error(`✗ ${fallas} problema(s). El pedido de permisos se rompe en silencio.`);
  process.exit(1);
}
console.log('✓ los tipos del bridge coinciden con lo que el plugin implementa en iOS');
