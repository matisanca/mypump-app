#!/usr/bin/env node
/* =============================================================
   seed-salud.mjs — carga datos de salud sintéticos en un cliente de prueba

   POR QUÉ EXISTE
   Para ver cómo se comporta la card de Recuperación en cada escenario había
   que conseguir un cliente real que estuviera en ese escenario y esperar. Con
   esto se elige el escenario y se ve en el navegador en 10 segundos.

   Postea por el RPC REAL (mypump_ingest_salud), no escribe la tabla a mano: así
   pasa por las mismas validaciones de plausibilidad que los datos de verdad, y
   si una migración rompe el ingest, esto se entera.

   USO
     node scripts/seed-salud.mjs --token TOKEN [opciones]

     --escenario  normal | fatiga | maladaptacion | sin-reloj | recien-conectado
                  (default: normal)
     --dias N     cuántos días generar (default 60; recien-conectado fuerza 3)
     --seed N     semilla del generador (default 42; misma semilla = misma serie)
     --fuente F   apple_health (default) | oura | whoop | withings | polar | manual
     --dry-run    imprime lo que mandaría y no postea nada

     El token también sale de la env MYPUMP_TOKEN.

   QUÉ ESPERAR DE CADA ESCENARIO (ver docs/BANCO_PRUEBAS_SALUD.md)
     normal            → score con banda alta/media
     fatiga            → banda baja, "fatiga acumulada"
     maladaptacion     → banda baja, estado autonómico 'maladaptacion'
     sin-reloj         → estado 'insuficiente': solo pasos, sin score. Es el
                         caso del iPhone sin reloj, el que se veía como un
                         botón muerto antes de la 1.0.5.
     recien-conectado  → estado 'calibrando', "3 / 14 días"

   OJO: los datos quedan en producción bajo el cliente de prueba y el centinela
   los ve. Limpiá con scripts/cleanup-test-data.sql al terminar.
   ============================================================= */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(import.meta.url);
const GEN = require(path.join(RAIZ, 'public/js/salud-sintetica.js'));

// ── Argumentos ────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const arg = (n, def) => {
  const i = argv.indexOf(`--${n}`);
  return i === -1 ? def : argv[i + 1];
};
const flag = (n) => argv.includes(`--${n}`);

const TOKEN     = arg('token', process.env.MYPUMP_TOKEN || '');
const ESCENARIO = arg('escenario', 'normal');
const DIAS      = parseInt(arg('dias', '60'), 10);
const SEED      = parseInt(arg('seed', '42'), 10);
const FUENTE    = arg('fuente', 'apple_health');
const DRY       = flag('dry-run');

if (!TOKEN) {
  console.error('Falta --token TOKEN (o la env MYPUMP_TOKEN).\n' +
                'El token de un cliente sale de mypump_clientes.access_token.');
  process.exit(1);
}
if (!GEN.ESCENARIOS.includes(ESCENARIO)) {
  console.error(`--escenario desconocido: ${ESCENARIO}\nOpciones: ${GEN.ESCENARIOS.join(', ')}`);
  process.exit(1);
}

// ── Credenciales ──────────────────────────────────────────────────────
// Se leen de public/js/config.js, que es el mismo archivo que usa la app. La
// anon key es pública por diseño (se sirve en el HTML); no hay ningún secreto
// acá y no hace falta un .env aparte.
function configDeLaApp() {
  const src = fs.readFileSync(path.join(RAIZ, 'public/js/config.js'), 'utf8');
  const w = {};
  new Function('window', src)(w);
  const c = w.MYPUMP_CONFIG || {};
  if (!c.SUPABASE_URL || !c.SUPABASE_ANON_KEY) {
    throw new Error('no pude leer SUPABASE_URL/ANON_KEY de public/js/config.js');
  }
  return c;
}

const { SUPABASE_URL, SUPABASE_ANON_KEY } = configDeLaApp();

async function rpc(fn, body) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`${fn} HTTP ${r.status}: ${txt.slice(0, 300)}`);
  return txt ? JSON.parse(txt) : null;
}

// ── Main ──────────────────────────────────────────────────────────────
const regs = GEN.filasIngest(ESCENARIO, DIAS, SEED, FUENTE);
const dias = new Set(regs.map(r => r.fecha)).size;
const tipos = [...new Set(regs.map(r => r.tipo))];

console.log(`escenario ${ESCENARIO} · ${dias} días · ${regs.length} filas · fuente ${FUENTE} · seed ${SEED}`);
console.log(`tipos: ${tipos.join(', ')}`);

if (DRY) {
  console.log('\n[dry-run] primeras 5 filas:');
  for (const r of regs.slice(0, 5)) console.log('  ' + JSON.stringify(r));
  console.log('\n[dry-run] no se posteó nada.');
  process.exit(0);
}

let aceptadas = 0;
const LOTE = 300;   // mismo tamaño que usa el bridge
for (let i = 0; i < regs.length; i += LOTE) {
  const lote = regs.slice(i, i + LOTE);
  const n = await rpc('mypump_ingest_salud', { p_token: TOKEN, p_registros: lote });
  aceptadas += Number(n) || 0;
  process.stdout.write(`\r  posteando… ${Math.min(i + LOTE, regs.length)}/${regs.length}`);
}
console.log('');

/* El RPC devuelve cuántas filas entraron. Si descarta, lo hace en SILENCIO
 * (049:78 hace CONTINUE cuando el valor no es plausible), así que un total que
 * no cierra es la única señal de que el generador se fue de rango. Sin este
 * chequeo uno se queda mirando una card vacía sin saber por qué. */
if (aceptadas !== regs.length) {
  console.warn(`\n⚠️  se generaron ${regs.length} filas pero entraron ${aceptadas}.`);
  console.warn('   Las que faltan las descartó mypump_salud_valor_plausible (migración 047):');
  console.warn('   algún valor del generador se fue del rango permitido para su tipo.');
  process.exit(1);
}

console.log(`✓ ${aceptadas} filas cargadas.`);
console.log(`\nAbrí:  http://localhost:3000/cliente.html?t=${TOKEN}   (npm run dev)`);
console.log('Al terminar, limpiá con scripts/cleanup-test-data.sql — el centinela ve este cliente.');
