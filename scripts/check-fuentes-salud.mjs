#!/usr/bin/env node
/* =============================================================
 * check-fuentes-salud.mjs — que toda `fuente` que el código puede escribir
 * esté permitida por el CHECK real de producción.
 *
 * POR QUÉ EXISTE
 * Este es el modo de falla más caro que tiene el pipeline de salud, porque no
 * se parece a un error:
 *
 *   _mypump_upsert_salud hace CONTINUE WHEN check_violation (049:77) para que
 *   una fila mala no aborte el lote entero. Es lo correcto. El efecto lateral
 *   es que una fuente que el CHECK no conoce se descarta FILA POR FILA, en
 *   silencio: sin excepción, sin log, sin fila parcial. La app recibe un 200,
 *   le dice al cliente "sincronizado", y la tabla queda vacía.
 *
 * Pasó de verdad: el bridge se escribió para Android emitiendo 'health_connect'
 * y el CHECK de mig 042 solo tenía las siete fuentes de iOS y los wearables.
 * Con la app instalada, el 25% de los clientes iba a conectar Health Connect y
 * no iba a ver NUNCA su score, sin que nada avisara.
 *
 * Un test del bridge no lo agarra: del lado JS está todo bien. Solo se ve
 * cruzando el código contra el esquema de la base.
 *
 * LA VARA es docs/ESQUEMA_PRODUCCION.txt. Si está viejo, este chequeo miente
 * en la dirección optimista (dice "falta" algo que ya aplicaste). Regeneralo:
 *   ssh mini "~/agentkit-coach/venv/bin/python3 ~/esquema.py" > docs/ESQUEMA_PRODUCCION.txt
 *
 * USO:  node scripts/check-fuentes-salud.mjs
 * Sale con 1 si el código puede escribir algo que la base rechaza.
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const rel = (p) => path.relative(raiz, p);

let problemas = 0;
let avisos = 0;
const fallo = (m, detalle) => { problemas++; console.error(`\n✗ ${m}`); if (detalle) console.error(detalle); };
const aviso = (m) => { avisos++; console.warn(`⚠ ${m}`); };

// ── 1. Lo que la BASE acepta ────────────────────────────────────────────
const esquemaPath = path.join(raiz, 'docs/ESQUEMA_PRODUCCION.txt');
if (!fs.existsSync(esquemaPath)) {
  console.error('✗ falta docs/ESQUEMA_PRODUCCION.txt — regeneralo (ver cabecera)');
  process.exit(1);
}
const esquema = fs.readFileSync(esquemaPath, 'utf8');

/* La sección CHECK CONSTRAINTS del volcado trae una línea por constraint, con
 * el CHECK ya normalizado por Postgres a `= ANY (ARRAY[...])`. */
const seccionChecks = esquema.includes('CHECK CONSTRAINTS')
  ? esquema.split('CHECK CONSTRAINTS')[1].split('PERMISOS DE EJECUCION')[0]
  : '';
if (!seccionChecks.trim()) {
  console.error('✗ el volcado no tiene sección CHECK CONSTRAINTS — ¿cambió el formato de esquema.py?');
  process.exit(1);
}

/** Valores permitidos por el CHECK de `<tabla>.fuente`, o null si no hay CHECK. */
function permitidasEnBase(tabla) {
  const linea = seccionChecks.split('\n').find(
    (l) => l.startsWith(`${tabla}.`) && /_fuente_check\s*:/.test(l));
  if (!linea) return null;                       // la tabla no tiene CHECK de fuente
  return [...linea.matchAll(/'([a-z0-9_]+)'::text/g)].map((m) => m[1]);
}

// ── 2. Lo que el CÓDIGO puede escribir ──────────────────────────────────
/* Se lee del fuente, no de una lista tipeada acá: una lista a mano se
 * desincroniza y el chequeo pasa a mentir en la dirección peligrosa. */
const emisores = [];

// (a) El bridge nativo: la constante FUENTE, que ramifica por plataforma.
const bridgePath = path.join(raiz, 'public/js/healthkit-bridge.js');
const bridge = fs.readFileSync(bridgePath, 'utf8');
const mFuente = bridge.match(/const\s+FUENTE\s*=\s*([^;\n]+)/);
if (!mFuente) {
  fallo(`no encontré la constante FUENTE en ${rel(bridgePath)}`,
        '  Si la renombraste, actualizá este chequeo: sin ella no se valida NADA del bridge.');
} else {
  for (const m of mFuente[1].matchAll(/'([a-z0-9_]+)'/g)) {
    emisores.push({ valor: m[1], donde: `${rel(bridgePath)} (const FUENTE)` });
  }
}

// (b) Cualquier literal `fuente: '...'` suelto en el front o en las functions.
for (const dir of ['public/js', 'functions/api']) {
  const abs = path.join(raiz, dir);
  if (!fs.existsSync(abs)) continue;
  for (const f of fs.readdirSync(abs).filter((x) => x.endsWith('.js'))) {
    const src = fs.readFileSync(path.join(abs, f), 'utf8');
    for (const m of src.matchAll(/\bfuente\s*:\s*'([a-z0-9_]+)'/g)) {
      emisores.push({ valor: m[1], donde: `${dir}/${f}` });
    }
  }
}

// (c) El poller de wearables de la mini: un proveedor nuevo también escribe fuente.
/* Se busca por CONTENIDO y no por nombre de archivo. La primera versión de esto
 * apuntaba a '045_wearables_oauth.sql', que no existe — el archivo real es
 * 045_wearable_conexiones.sql — y como el fs.existsSync daba false, la lista
 * entera de proveedores se saltaba SIN AVISAR. Justo el modo de falla que este
 * script existe para cazar, adentro del script. */
const dirMigs = path.join(raiz, 'supabase/migrations');
const archivosMig = fs.readdirSync(dirMigs).filter((f) => f.endsWith('.sql')).sort();
let halleProveedores = false;
for (const f of archivosMig) {
  const sql = fs.readFileSync(path.join(dirMigs, f), 'utf8');
  const mProv = sql.match(/proveedor\s+(?:TEXT\s+)?(?:NOT NULL\s+)?(?:CHECK\s*\()?\s*proveedor\s+IN\s*\(([^)]+)\)|proveedor\s+IN\s*\(([^)]+)\)/i);
  if (!mProv) continue;
  for (const m of (mProv[1] || mProv[2]).matchAll(/'([a-z0-9_]+)'/g)) {
    emisores.push({ valor: m[1], donde: `${f} (proveedores OAuth)` });
  }
  halleProveedores = true;
}
if (!halleProveedores) {
  aviso('no encontré la lista de proveedores OAuth en ninguna migración.\n' +
        '  Si se renombró la columna, este chequeo dejó de cubrir los wearables.');
}

// ── 3. El cotejo ────────────────────────────────────────────────────────
const TABLAS = ['mypump_salud_diaria', 'mypump_entrenos_health'];

console.log(`fuentes que el código puede escribir: ${[...new Set(emisores.map((e) => e.valor))].sort().join(', ')}`);

for (const tabla of TABLAS) {
  const ok = permitidasEnBase(tabla);
  if (ok === null) {
    aviso(`${tabla}: sin CHECK de fuente en producción — entra cualquier string.\n` +
          `  No rompe nada hoy, pero tampoco protege. La migración 056 lo agrega NOT VALID.`);
    continue;
  }
  console.log(`${tabla}: la base acepta ${ok.length} → ${ok.join(', ')}`);

  const faltantes = new Map();
  for (const e of emisores) {
    if (!ok.includes(e.valor)) {
      if (!faltantes.has(e.valor)) faltantes.set(e.valor, new Set());
      faltantes.get(e.valor).add(e.donde);
    }
  }
  if (faltantes.size) {
    /* Distinguir las dos situaciones importa, porque la acción es distinta:
     *  · hay una migración en el repo que lo arregla → falta APLICARLA
     *  · no la hay                                   → hay que ESCRIBIRLA
     * Si no se distingue, el mismo mensaje manda a buscar un bug que no existe. */
    const detalle = [...faltantes].map(([v, donde]) => {
      const mig = archivosMig.find((f) => {
        const sql = fs.readFileSync(path.join(dirMigs, f), 'utf8');
        return new RegExp(`fuente\\s+IN\\s*\\([^)]*'${v}'`, 'i').test(sql);
      });
      return `    '${v}'  ← ${[...donde].join(', ')}\n` + (mig
        ? `        PENDIENTE: la migración ${mig} lo agrega. Aplicala en el editor SQL.`
        : `        SIN ARREGLO: ninguna migración del repo suma '${v}' al CHECK. Hay que escribirla.`);
    }).join('\n');

    fallo(
      `${tabla}: el código escribe ${faltantes.size} fuente(s) que la base RECHAZA.`,
      detalle +
      '\n\n  Estas filas NO dan error: _mypump_upsert_salud hace CONTINUE WHEN' +
      '\n  check_violation, así que se descartan de a una y en silencio. El cliente' +
      '\n  ve "sincronizado" y su score nunca aparece.' +
      '\n\n  Si ya aplicaste la migración, esto sigue en rojo hasta regenerar el volcado:' +
      '\n    ssh mini "~/agentkit-coach/venv/bin/python3 ~/esquema.py" > docs/ESQUEMA_PRODUCCION.txt');
  }
}

// ── 4. El motor tiene que saber desempatar por cada fuente ──────────────
/* Una fuente aceptada por el CHECK pero desconocida para el CASE de prioridad
 * cae al ELSE, o sea POR DEBAJO de un peso tipeado a mano: el motor preferiría
 * el número escrito con el dedo antes que el del reloj. */
const migMotor = fs.readdirSync(path.join(raiz, 'supabase/migrations'))
  .filter((f) => /^\d+_.*\.sql$/.test(f)).sort().reverse()
  .map((f) => path.join(raiz, 'supabase/migrations', f))
  .find((p) => fs.readFileSync(p, 'utf8').includes('mypump_calc_recuperacion'));

if (migMotor) {
  const sqlMotor = fs.readFileSync(migMotor, 'utf8');
  const sinPrioridad = [...new Set(emisores.map((e) => e.valor))]
    .filter((v) => v !== 'manual' && !sqlMotor.includes(`'${v}'`));
  if (sinPrioridad.length) {
    fallo(`el motor de recuperación no conoce: ${sinPrioridad.join(', ')}`,
          `  Última migración que lo toca: ${rel(migMotor)}\n` +
          '  Sin su rama en el CASE, esas fuentes caen al ELSE y pierden contra "manual".');
  } else {
    console.log(`el motor (${path.basename(migMotor)}) conoce todas las fuentes emitidas`);
  }
}

// ── Veredicto ───────────────────────────────────────────────────────────
console.log('');
if (problemas) {
  console.error(`✗ ${problemas} problema(s) de fuentes de salud`);
  process.exit(1);
}
if (avisos) console.log(`✓ ninguna fuente rechazada (con ${avisos} aviso/s)`);
else console.log('✓ toda fuente que el código escribe está permitida por la base y conocida por el motor');
