#!/usr/bin/env node
/* =============================================================
   seed-cliente.mjs — fabricar CUALQUIER caso de cliente desde la Mac

   EL PROBLEMA QUE RESUELVE
   Hasta ahora, para ver cómo se comporta la app con un cliente en la semana 13
   de un macrociclo, o con uno que abandonó hace 3 semanas, había que esperar a
   que existiera. Los bordes —el plan sin macros_target que deja la app en
   blanco, el día sin ejercicios, la dieta de 2 opciones— no se veían nunca
   hasta que le pasaban a alguien.

   CÓMO FUNCIONA
   Dos mitades, porque los permisos de Supabase están partidos al medio y está
   bien que lo estén:

     1. EL PLAN (rutina + dieta). Vive en mypump_rutinas/mypump_dietas, que
        tienen RLS de `authenticated`: publicar es del coach, no del cliente.
        El script NO puede escribirlo con la anon key — y no debería.
        → Emite un .sql para pegar en el SQL Editor (o lo aplica solo si hay
          SUPABASE_SERVICE_KEY en el entorno; ver más abajo).

     2. LA HISTORIA (sesiones, cargas, comidas, checks, peso, hábitos,
        comentarios, salud). Todo eso lo escribe el CLIENTE, así que hay RPC
        con GRANT a anon y token. El script las llama exactamente igual que la
        app: mismas funciones, mismos parámetros, mismas validaciones.
        → Se aplica solo, sin pegar nada.

   POR QUÉ LA HISTORIA VA POR LAS RPC REALES Y NO POR INSERT
   Un INSERT directo se saltea los CHECK, los triggers y las reglas de negocio
   que viven adentro de las funciones. El banco estaría probando una base que
   la app nunca produce. Yendo por la RPC, si mañana alguien le agrega una
   validación a mypump_registrar_carga, el banco se entera.

   USO
     node scripts/seed-cliente.mjs --lista
     node scripts/seed-cliente.mjs --escenario en-ritmo
     node scripts/seed-cliente.mjs --escenario macrociclo-2 --aplicar
     node scripts/seed-cliente.mjs --escenario estancado --visible-al-coach

   FLAGS
     --escenario N     cuál fabricar (--lista los muestra todos)
     --cliente ID      forzar el cliente_id (default: derivado del escenario)
     --aplicar         además de emitir el SQL, escribir la historia por RPC
     --solo-sql        emitir el SQL y nada más
     --visible-al-coach  usar un nombre que el centinela y el Radar NO filtren
     --seed N          semilla del PRNG (default 42)
     --limpiar         borrar la historia de este cliente y salir

   SOBRE --visible-al-coach
   El centinela (centinela.py:1103) y el Radar del Cerebro descartan todo
   cliente_id que arranque con "test" o cuyo nombre contenga "test". Es una
   red de seguridad buena: sin ella los clientes sintéticos aparecerían en el
   radar real de Mati mezclados con gente. Por eso el default es ser invisible.
   Cuando lo que se quiere probar ES el lado del coach, este flag los hace
   visibles a propósito — y ahí hay que acordarse de limpiar después.
   ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { rutina, dieta, sqlPlan, mulberry32 } from './lib/plan-sintetico.mjs';
import { resolver, NOMBRES, ESCENARIOS } from './lib/escenarios-cliente.mjs';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// ── Args ──────────────────────────────────────────────────────────────
const A = process.argv.slice(2);
const flag = (n) => A.includes(n);
const val = (n, d) => { const i = A.indexOf(n); return i >= 0 && A[i + 1] ? A[i + 1] : d; };

if (flag('--lista') || (!flag('--escenario') && !flag('--limpiar'))) {
  console.log('\nEscenarios disponibles:\n');
  for (const n of NOMBRES) {
    console.log(`  ${n.padEnd(24)} ${ESCENARIOS[n]._que}`);
    console.log(`  ${' '.repeat(24)} ↳ mirar: ${ESCENARIOS[n]._mirar}\n`);
  }
  console.log('  node scripts/seed-cliente.mjs --escenario <nombre> --aplicar\n');
  process.exit(0);
}

const NOMBRE_ESC = val('--escenario', 'en-ritmo');
const ESC = resolver(NOMBRE_ESC);
if (!ESC) {
  console.error(`✗ no existe el escenario "${NOMBRE_ESC}". Probá --lista.`);
  process.exit(1);
}

const SEED = Number(val('--seed', 42));
const VISIBLE = flag('--visible-al-coach');
// El prefijo es lo que decide si el coach lo ve. Ver la cabecera.
const CLIENTE_ID = val('--cliente', (VISIBLE ? 'banco-' : 'test-banco-') + NOMBRE_ESC);
const NOMBRE_CLI = VISIBLE ? `Banco ${NOMBRE_ESC}` : `Test ${NOMBRE_ESC}`;
const TOKEN = 'BANCO_' + NOMBRE_ESC.toUpperCase().replace(/-/g, '_') + '_TOKEN';

// ── Supabase (anon: lo mismo que usa la app) ──────────────────────────
function configDeLaApp() {
  const src = fs.readFileSync(path.join(RAIZ, 'public/js/config.js'), 'utf8');
  const w = {};
  new Function('window', src)(w);
  const c = w.MYPUMP_CONFIG || {};
  if (!c.SUPABASE_URL || !c.SUPABASE_ANON_KEY) throw new Error('config.js sin SUPABASE_URL/ANON_KEY');
  return c;
}
const { SUPABASE_URL, SUPABASE_ANON_KEY } = configDeLaApp();
// Opcional: si está en el entorno, el script puede aplicar el plan solo.
// NUNCA se guarda ni se imprime; si no está, se emite el .sql y listo.
const SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || '';

async function rpc(fn, body, { servicio = false } = {}) {
  const key = servicio ? SERVICE_KEY : SUPABASE_ANON_KEY;
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`${fn} HTTP ${r.status}: ${t.slice(0, 200)}`);
  return t ? JSON.parse(t) : null;
}

// ── Fechas ────────────────────────────────────────────────────────────
const hoy = new Date();
const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const haceDias = (n) => { const d = new Date(hoy); d.setDate(d.getDate() - n); return d; };
// Lunes de la semana de una fecha (el check y el análisis se indexan por lunes)
const lunesDe = (d) => { const x = new Date(d); const w = (x.getDay() + 6) % 7; x.setDate(x.getDate() - w); return x; };

const rnd = mulberry32(SEED);
const entre = (a, b) => a + (b - a) * rnd();

// ── 1. El plan ────────────────────────────────────────────────────────
const R = rutina({
  split: ESC.split, semanasTotal: ESC.semanasTotal, objetivo: ESC.objetivo,
  semanaOffset: ESC.semanaOffset, seed: SEED, ...(ESC.rutinaRota || {}),
});
const D = dieta({
  comidas: ESC.comidas, opciones: ESC.opciones, kcal: ESC.kcal,
  seed: SEED, ...(ESC.dietaRota || {}),
});
// El bloque en cola tiene que ser OTRO plan: si fuera igual, activarlo no se
// notaría y el caso no probaría nada.
const SIG = ESC.conBloqueEnCola
  ? rutina({ split: 'upper-lower-4', semanasTotal: 8, objetivo: 'Definición', seed: SEED + 1 })
  : null;

const SQL = sqlPlan({
  clienteId: CLIENTE_ID, nombre: NOMBRE_CLI, perfil: ESC.perfil, token: TOKEN,
  rutina: R, dieta: D, semanaActual: ESC.semanaActual,
  conBloqueEnCola: ESC.conBloqueEnCola, siguiente: SIG, sinDieta: ESC.sinDieta,
});

const RUTA_SQL = path.join(RAIZ, 'scripts', `.plan-${NOMBRE_ESC}.sql`);
fs.writeFileSync(RUTA_SQL, SQL);

console.log(`\n▸ escenario: ${NOMBRE_ESC}`);
console.log(`  ${ESC._que}`);
console.log(`  mirar: ${ESC._mirar}\n`);
console.log(`  cliente_id : ${CLIENTE_ID}${VISIBLE ? '   (VISIBLE para el coach)' : '   (invisible para el coach)'}`);
console.log(`  token      : ${TOKEN}`);
console.log(`  plan       : semana ${ESC.semanaActual}/${ESC.semanasTotal}` +
            (ESC.semanaOffset ? ` con offset ${ESC.semanaOffset} → muestra SEM ${ESC.semanaActual + ESC.semanaOffset}/${ESC.semanasTotal + ESC.semanaOffset}` : '') +
            `, ${R.dias ? R.dias.length : 0} días, dieta ${ESC.sinDieta ? 'AUSENTE' : `${ESC.comidas} comidas × ${ESC.opciones} opciones`}`);
console.log(`  SQL        : ${path.relative(RAIZ, RUTA_SQL)}\n`);

if (flag('--solo-sql')) {
  console.log('  Pegá ese archivo en Supabase → SQL Editor y listo.\n');
  process.exit(0);
}

// ── 2. La historia ────────────────────────────────────────────────────
async function aplicarPlan() {
  if (!SERVICE_KEY) {
    console.log('  ⚠ El plan NO se aplicó: mypump_rutinas/mypump_dietas piden un rol');
    console.log('    `authenticated` y este script corre con la anon key.');
    console.log(`    → Pegá ${path.relative(RAIZ, RUTA_SQL)} en Supabase → SQL Editor.`);
    console.log('    (o exportá SUPABASE_SERVICE_KEY y volvé a correr con --aplicar)\n');
    return false;
  }
  // Con service key: se aplica por PostgREST, sentencia por sentencia.
  console.log('  · aplicando el plan con la service key…');
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/exec_sql`, {
    method: 'POST',
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ q: SQL }),
  });
  if (!r.ok) {
    console.log(`  ⚠ no hay RPC exec_sql en esta base (HTTP ${r.status}).`);
    console.log(`    → Pegá ${path.relative(RAIZ, RUTA_SQL)} en el SQL Editor.\n`);
    return false;
  }
  console.log('  ✓ plan aplicado');
  return true;
}

/** ¿Existe el cliente y responde su token? Es la puerta de todo lo demás. */
async function clienteVivo() {
  try {
    const info = await rpc('mypump_get_cliente_info', { p_token: TOKEN });
    return Array.isArray(info) ? info.length > 0 : !!info;
  } catch { return false; }
}

async function sembrarEntrenos() {
  const dias = (R.dias || []);
  if (!dias.length || !ESC.semanasEntrenadas) return 0;
  let sesiones = 0;
  for (let s = ESC.semanasEntrenadas; s >= 1; s--) {
    const semana = Math.max(1, ESC.semanaActual - (s - 1));
    for (let di = 0; di < dias.length; di++) {
      if (rnd() > ESC.adherenciaEntreno) continue;   // el día que se salteó
      const dia = dias[di];
      const res = await rpc('mypump_iniciar_sesion', { p_token: TOKEN, p_dia_id: dia.id, p_semana: semana });
      const sesionId = res && (res.sesion_id || res.id || res);
      if (!sesionId || typeof sesionId !== 'string') continue;
      for (const b of (dia.bloques || [])) {
        for (const e of b.ejercicios) {
          // La carga sube (o no) según progresoCarga: es lo que mira el motor
          // de estancamiento del centinela.
          const semDesde = ESC.semanasEntrenadas - s;
          const base = e.tipo === 'compuesto' ? 60 : 20;
          const peso = Math.round(base * (1 + ESC.progresoCarga * semDesde) * 2) / 2;
          for (let serie = 1; serie <= e.series; serie++) {
            await rpc('mypump_registrar_carga', {
              p_token: TOKEN, p_sesion_id: sesionId, p_dia_id: dia.id,
              p_ejercicio_id: e.id, p_ejercicio_nombre: e.nombre,
              p_serie: serie, p_peso: peso,
              p_reps: e.tipo === 'compuesto' ? 7 : 11,
              p_rir: Math.round(entre(0, 2)), p_notas: null,
            });
          }
        }
      }
      await rpc('mypump_finalizar_sesion', {
        p_token: TOKEN, p_sesion_id: sesionId, p_notas: null,
        p_duracion_segundos: Math.round(entre(2700, 5400)),
      });
      sesiones++;
    }
  }
  return sesiones;
}

async function sembrarComidas() {
  if (!ESC.diasComidas || ESC.sinDieta || !(D.comidas || []).length) return 0;
  let n = 0;
  for (let d = ESC.diasComidas; d >= 1; d--) {
    const fecha = ymd(haceDias(d));
    for (const c of D.comidas) {
      if (rnd() > ESC.comidasMarcadas) continue;
      const op = c.options[Math.floor(rnd() * c.options.length)];
      try {
        await rpc('mypump_marcar_comida', {
          p_token: TOKEN, p_fecha: fecha, p_comida_id: c.id,
          p_opcion: op.name, p_estado: 'comido', p_foods_excluidos: null,
        });
        n++;
      } catch { /* la RPC rechaza fechas viejas: es su regla, no un error nuestro */ }
    }
  }
  return n;
}

async function sembrarChecks() {
  let n = 0;
  for (let s = ESC.semanasChecks; s >= 1; s--) {
    const fecha = ymd(lunesDe(haceDias(s * 7)));
    try {
      await rpc('mypump_guardar_checkin', {
        p_token: TOKEN, p_fecha: fecha,
        p_energia: ESC.check.energia, p_descanso: ESC.check.descanso,
        p_hambre: ESC.check.hambre, p_adherencia: ESC.check.adherencia,
        p_nota: null,
      });
      n++;
    } catch { /* idem */ }
  }
  return n;
}

async function sembrarPeso() {
  if (!ESC.diasPeso) return 0;
  const regs = [];
  for (let d = ESC.diasPeso; d >= 0; d -= 2) {
    const semanas = d / 7;
    const kg = ESC.pesoInicial - ESC.tendenciaPeso * (ESC.diasPeso / 7 - semanas) + entre(-0.4, 0.4);
    regs.push({ fecha: ymd(haceDias(d)), tipo: 'peso_kg', valor: Math.round(kg * 10) / 10, fuente: 'manual' });
  }
  await rpc('mypump_ingest_salud', { p_token: TOKEN, p_registros: regs });
  return regs.length;
}

async function sembrarComentarios() {
  const ambitos = [
    ['ejercicio', R.dias?.[0]?.bloques?.[0]?.ejercicios?.[0]?.id, R.dias?.[0]?.bloques?.[0]?.ejercicios?.[0]?.nombre, 'Bajá el peso y subí una rep.'],
    ['dieta', null, null, 'Si te da hambre a la tarde, movete la fruta ahí.'],
    ['rutina', null, null, 'Esta semana priorizá el descanso entre series.'],
    ['general', null, null, 'Vas bien. Seguí así.'],
  ];
  let n = 0;
  for (let i = 0; i < Math.min(ESC.comentariosCoach, ambitos.length); i++) {
    const [ambito, refId, refNom, texto] = ambitos[i];
    try {
      await rpc('mypump_agregar_comentario', {
        p_token: TOKEN, p_ambito: ambito, p_referencia_id: refId,
        p_referencia_nombre: refNom, p_contenido: texto,
      });
      n++;
    } catch { /* algunos ámbitos pueden no estar habilitados */ }
  }
  return n;
}

async function sembrarSalud() {
  if (!ESC.salud) return 0;
  const { filasIngest } = await import('../public/js/salud-sintetica.js')
    .then(m => m.default || m)
    .catch(() => ({}));
  if (!filasIngest) {
    console.log('  · salud: usá scripts/seed-salud.mjs --token ' + TOKEN + ' --escenario ' + ESC.salud);
    return 0;
  }
  const regs = filasIngest(ESC.salud, 60, SEED, 'apple_health');
  for (let i = 0; i < regs.length; i += 300) {
    await rpc('mypump_ingest_salud', { p_token: TOKEN, p_registros: regs.slice(i, i + 300) });
  }
  return regs.length;
}

// ── Limpieza ──────────────────────────────────────────────────────────
if (flag('--limpiar')) {
  console.log('  La historia se borra con SQL (las RPC de cliente no borran).');
  console.log(`  Corré scripts/cleanup-test-data.sql con cliente_id = '${CLIENTE_ID}'.\n`);
  process.exit(0);
}

// ── Main ──────────────────────────────────────────────────────────────
if (!flag('--aplicar')) {
  console.log('  (dry-run: solo se generó el SQL. Agregá --aplicar para sembrar la historia.)\n');
  process.exit(0);
}

await aplicarPlan();

if (!(await clienteVivo())) {
  console.log('  ⚠ El token todavía no resuelve: el plan no está aplicado.');
  console.log('    Pegá el SQL y volvé a correr con --aplicar. La historia se siembra encima.\n');
  process.exit(1);
}

console.log('  · sembrando la historia por las RPC reales del cliente…');
const ses = await sembrarEntrenos();
const com = await sembrarComidas();
const chk = await sembrarChecks();
const pes = await sembrarPeso();
const cmt = await sembrarComentarios();
const sal = await sembrarSalud();

console.log(`\n  ✓ ${ses} sesiones · ${com} comidas · ${chk} checks · ${pes} pesos · ${cmt} comentarios · ${sal} filas de salud\n`);
console.log(`  Abrilo:  http://localhost:3000/cliente.html?t=${TOKEN}`);
console.log(`  (npm run dev si no está levantado)\n`);
