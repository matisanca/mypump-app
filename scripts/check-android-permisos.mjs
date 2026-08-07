#!/usr/bin/env node
/* =============================================================
   check-android-permisos.mjs — que el manifest y el bridge digan lo mismo

   POR QUÉ EXISTE
   En Android hay DOS listas que tienen que coincidir y viven en archivos
   distintos, en lenguajes distintos:

     · lo que el bridge PIDE en runtime  → public/js/healthkit-bridge.js
     · lo que el manifest DECLARA        → android/app/src/main/AndroidManifest.xml

   Los dos modos de falla son feos y silenciosos de maneras opuestas:

   1. Pedir un permiso que el manifest NO declara → SecurityException en
      runtime. No pasa en el build, no pasa en los tests: pasa en el teléfono
      del cliente, la primera vez que toca "Conectar".

   2. Declarar un permiso que la app NO usa → Google te lo hace justificar uno
      por uno en la "Health apps declaration" de Play Console, y un permiso sin
      uso es una pregunta sin buena respuesta. El plugin trae 43 (22 lectura +
      21 escritura) y la app usa 17 de lectura; los otros 26 se sacan con
      tools:node="remove". Si alguien borra un remove sin querer, este script
      lo canta.

   El mapeo tipo → permiso NO es derivable: 'calories' es
   READ_ACTIVE_CALORIES_BURNED, 'workouts' es READ_EXERCISE, 'basalCalories' es
   READ_BASAL_METABOLIC_RATE. Está escrito abajo y sale del enum de Kotlin
   (HealthDataType.kt), que es la fuente de verdad.

   USO:  node scripts/check-android-permisos.mjs
   ============================================================= */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const BRIDGE = join(RAIZ, 'public/js/healthkit-bridge.js');
const MANIFEST = join(RAIZ, 'android/app/src/main/AndroidManifest.xml');
const PLUGIN_MANIFEST = join(RAIZ, 'node_modules/@capgo/capacitor-health/android/src/main/AndroidManifest.xml');

const leer = (p) => {
  try { return readFileSync(p, 'utf8'); }
  catch { console.error(`✗ No pude leer ${p}`); process.exit(1); }
};

/* dataType del plugin → permiso de Health Connect.
   Sale de HealthDataType.kt: cada case declara su recordClass, y
   HealthPermission.getReadPermission(X::class) produce estos nombres. */
const PERMISO = {
  steps: 'READ_STEPS',
  distance: 'READ_DISTANCE',
  calories: 'READ_ACTIVE_CALORIES_BURNED',
  totalCalories: 'READ_TOTAL_CALORIES_BURNED',
  basalCalories: 'READ_BASAL_METABOLIC_RATE',
  flightsClimbed: 'READ_FLOORS_CLIMBED',
  heartRate: 'READ_HEART_RATE',
  restingHeartRate: 'READ_RESTING_HEART_RATE',
  heartRateVariability: 'READ_HEART_RATE_VARIABILITY',
  sleep: 'READ_SLEEP',
  respiratoryRate: 'READ_RESPIRATORY_RATE',
  oxygenSaturation: 'READ_OXYGEN_SATURATION',
  bodyTemperature: 'READ_BODY_TEMPERATURE',
  basalBodyTemperature: 'READ_BASAL_BODY_TEMPERATURE',
  bloodGlucose: 'READ_BLOOD_GLUCOSE',
  bloodPressure: 'READ_BLOOD_PRESSURE',
  weight: 'READ_WEIGHT',
  bodyFat: 'READ_BODY_FAT',
  height: 'READ_HEIGHT',
  mindfulness: 'READ_MINDFULNESS',
  vo2Max: 'READ_VO2_MAX',
  // No es un case del enum: el plugin lo maneja por queryWorkouts, pero el
  // permiso que necesita SÍ existe y hay que declararlo.
  workouts: 'READ_EXERCISE',
};

/* ── Lo que el bridge pide en Android ─────────────────────────────────── */
const bridge = leer(BRIDGE);
const bloque = (n) => {
  const m = new RegExp(`const ${n} = \\[([\\s\\S]*?)\\n  \\];`).exec(bridge);
  if (!m) { console.error(`✗ No encontré la tabla ${n} en el bridge.`); process.exit(1); }
  return m[1];
};
const filas = (txt) =>
  [...txt.matchAll(/\{[^}]*dataType:\s*'([^']+)'[^}]*\}/g)]
    .map((m) => ({ dataType: m[1], soloIOS: /soloIOS:\s*true/.test(m[0]) }));

const deTablas = [...filas(bloque('AGG')), ...filas(bloque('SAMPLES'))];
const mNucleo = /const NUCLEO = \[([^\]]*)\]/.exec(bridge);
const nucleo = mNucleo ? [...mNucleo[1].matchAll(/'([^']+)'/g)].map((m) => m[1]) : [];
const mExtra = /\.concat\(\[([^\]]*)\]\)/.exec(bridge);
const extra = mExtra ? [...mExtra[1].matchAll(/'([^']+)'/g)].map((m) => m[1]) : [];

const pideAndroid = [...new Set([
  ...deTablas.filter((f) => !f.soloIOS).map((f) => f.dataType),
  ...nucleo, ...extra,
])];

/* ── Lo que el manifest declara y lo que saca ─────────────────────────── */
const manifest = leer(MANIFEST);
const declarados = new Set();
const removidos = new Set();
for (const m of manifest.matchAll(/<uses-permission[^>]*android:name="android\.permission\.health\.([A-Z_0-9]+)"([^>]*)>/g)) {
  (/tools:node="remove"/.test(m[2]) ? removidos : declarados).add(m[1]);
}

let fallas = 0;
const fallar = (msg) => { console.error(`  ✗ ${msg}`); fallas++; };

console.log(`\nel bridge pide ${pideAndroid.length} tipos en Android`);
console.log(`el manifest declara ${declarados.size} permisos y saca ${removidos.size}\n`);

console.log('1. Todo tipo pedido tiene su permiso declarado');
const antes1 = fallas;
for (const t of pideAndroid) {
  const p = PERMISO[t];
  if (!p) {
    fallar(`'${t}' no está en la tabla PERMISO de este script — agregalo o el chequeo no vale nada.`);
    continue;
  }
  if (removidos.has(p)) {
    fallar(`'${t}' se pide en runtime pero su permiso ${p} está con tools:node="remove".\n` +
           `      Health Connect tira SecurityException la primera vez que el cliente toca Conectar.`);
  } else if (!declarados.has(p)) {
    fallar(`'${t}' se pide en runtime y ${p} NO está declarado en el manifest.\n` +
           `      SecurityException en el teléfono; no se ve ni en el build ni en los tests.`);
  }
}
if (fallas === antes1) console.log(`   ✓ los ${pideAndroid.length} tienen permiso`);

console.log('\n2. No se declara nada que no se use');
const antes2 = fallas;
const necesarios = new Set(pideAndroid.map((t) => PERMISO[t]).filter(Boolean));
for (const p of declarados) {
  if (!necesarios.has(p)) {
    fallar(`${p} está declarado pero ningún tipo del bridge lo necesita.\n` +
           `      Google lo hace justificar uno por uno en la Health apps declaration.`);
  }
}
if (fallas === antes2) console.log(`   ✓ los ${declarados.size} declarados se usan`);

console.log('\n3. Ningún permiso de ESCRITURA sobrevive al merge');
const antes3 = fallas;
// MyPump solo lee. El plugin trae los 21 de escritura y hay que sacarlos todos.
const pluginSrc = leer(PLUGIN_MANIFEST);
const writesDelPlugin = [...new Set(
  [...pluginSrc.matchAll(/android\.permission\.health\.(WRITE_[A-Z_0-9]+)/g)].map((m) => m[1])
)];
for (const w of writesDelPlugin) {
  if (!removidos.has(w)) {
    fallar(`${w} lo trae el plugin y el manifest de la app NO lo saca.\n` +
           `      Va a terminar en el APK: la app pide escribir algo que nunca escribe.`);
  }
}
if (fallas === antes3) console.log(`   ✓ los ${writesDelPlugin.length} de escritura del plugin están removidos`);

/* ── 4. App Links: el assetlinks.json ─────────────────────────────────
   El manifest tiene autoVerify="true" para app.mypumpteam.com. Android va a
   buscar https://app.mypumpteam.com/.well-known/assetlinks.json y comparar el
   SHA-256 con el que firmó el APK.

   Si no coincide, la verificación falla y el link del coach abre el navegador
   en vez de la app. No hay error, no hay aviso: simplemente no funciona, y el
   cliente que instaló la app igual termina en la web.

   El fingerprint sale de Play App Signing (Play Console → Integridad de la
   app), y no existe hasta que se sube el primer AAB. Por eso esto avisa en vez
   de fallar: el repo tiene que poder estar verde antes de que la cuenta de
   Play exista. */
console.log('\n4. App Links (assetlinks.json)');
try {
  const al = leer(join(RAIZ, 'public/.well-known/assetlinks.json'));
  if (al.includes('REEMPLAZAR_CON_EL_SHA256')) {
    console.log('   ⚠ el fingerprint sigue siendo el placeholder.');
    console.log('     Los links del coach van a abrir el NAVEGADOR, no la app, sin avisar.');
    console.log('     Se completa con el SHA-256 de Play App Signing después del primer AAB.');
    console.log('     Ver docs/ANDROID.md.');
  } else if (!/\b[A-F0-9]{2}(:[A-F0-9]{2}){31}\b/i.test(al)) {
    fallar('el fingerprint de assetlinks.json no tiene forma de SHA-256 (32 bytes en hex separados por ":").');
  } else {
    console.log('   ✓ fingerprint cargado');
  }
} catch {
  fallar('falta public/.well-known/assetlinks.json — sin él los App Links no verifican nunca.');
}

console.log('');
if (fallas) {
  console.error(`✗ ${fallas} problema(s) entre el bridge y el manifest de Android.`);
  process.exit(1);
}
console.log('✓ el manifest de Android declara exactamente lo que el bridge pide, y nada más');
