#!/usr/bin/env node
/* =============================================================
 * check-contratos.mjs — coteja cada llamada RPC del repo contra la firma
 * REAL de producción.
 *
 * POR QUÉ EXISTE
 * Una RPC mal llamada no da error ruidoso. Si el nombre de un parámetro está
 * mal escrito, Postgres no ve ese argumento: usa el DEFAULT si lo tiene, o
 * responde "no existe la función con esos argumentos" — un 404 que el
 * llamador suele tragarse en un try/catch y convertir en "no hay datos".
 *
 * El 28-jul aparecieron 6 bugs de esta familia, todos invisibles: cuatro
 * funciones SQL consultando una tabla que no existe, una validación que nadie
 * llamaba. Ninguno tiraba un error a la vista. Este script hace el cotejo
 * exacto, sin que nadie tenga que acordarse de mirar.
 *
 * LA VARA es docs/ESQUEMA_PRODUCCION.txt, volcado de la base real. Si está
 * desactualizado el chequeo miente, así que regeneralo antes:
 *   ssh mini "~/agentkit-coach/venv/bin/python3 ~/esquema.py" > docs/ESQUEMA_PRODUCCION.txt
 *
 * USO:  node scripts/check-contratos.mjs
 * Sale con código 1 si encuentra algo, para poder colgarlo de un hook.
 * ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const NUTRIPLAN = path.resolve(raiz, '../../nutriplan');

// ── 1. Firmas reales ────────────────────────────────────────────────────
const esquemaPath = path.join(raiz, 'docs/ESQUEMA_PRODUCCION.txt');
if (!fs.existsSync(esquemaPath)) {
  console.error('✗ falta docs/ESQUEMA_PRODUCCION.txt — regeneralo (ver cabecera)');
  process.exit(1);
}
const esquema = fs.readFileSync(esquemaPath, 'utf8');
const seccionFns = esquema.split('TABLAS Y COLUMNAS')[0];

const firmas = new Map();   // nombre -> Set(params)
for (const m of seccionFns.matchAll(/^(mypump_[a-z0-9_]+|_mypump_[a-z0-9_]+)\(([^\n]*)\)$/gm)) {
  const [, nombre, args] = m;
  const params = new Set();
  for (const a of args.matchAll(/\b(p_[a-z0-9_]+)\s/g)) params.add(a[1]);
  // Un mismo nombre puede estar sobrecargado: se unen los params de todas.
  if (firmas.has(nombre)) for (const p of params) firmas.get(nombre).add(p);
  else firmas.set(nombre, params);
}
console.log(`firmas leídas del esquema: ${firmas.size}`);

/* Funciones declaradas en las migraciones del repo, aplicadas o no.
 * Sirve para distinguir "typo" de "migración todavía sin correr". */
const enMigraciones = new Set();
const dirMig = path.join(raiz, 'supabase/migrations');
if (fs.existsSync(dirMig)) {
  for (const f of fs.readdirSync(dirMig).filter((x) => x.endsWith('.sql'))) {
    const sql = fs.readFileSync(path.join(dirMig, f), 'utf8');
    // Solo definiciones reales: las líneas comentadas del bloque ROLLBACK no cuentan.
    for (const l of sql.split('\n')) {
      if (/^\s*--/.test(l)) continue;
      const m = /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([a-z0-9_]+)/i.exec(l);
      if (m) enMigraciones.add(m[1]);
    }
  }
}
const pendientes = [];

// ── 2. Llamadas en el código ────────────────────────────────────────────
const archivos = [];
const juntar = (dir, exts, prof = 0) => {
  if (!fs.existsSync(dir) || prof > 4) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) juntar(p, exts, prof + 1);
    else if (exts.some((x) => e.name.endsWith(x)) && !e.name.includes('.bak')) archivos.push(p);
  }
};
juntar(path.join(raiz, 'public/js'), ['.js']);
juntar(path.join(raiz, 'functions'), ['.js']);
juntar(path.join(raiz, 'pump-centinela'), ['.py']);
const panel = path.join(NUTRIPLAN, 'panel.html');
if (fs.existsSync(panel)) archivos.push(panel);
// index.html queda afuera a propósito: son +800KB y el proyecto prohíbe
// cargarlo entero. Se lo revisa con grep puntual cuando hace falta.

/* Formas de llamada que se reconocen:
 *   .rpc('fn', { p_x: ... })            supabase-js (cliente y panel)
 *   rpcMutation('fn', { p_x: ... })     wrapper de supabase-client.js
 *   rpc(env, 'fn', { p_x: ... })        Pages Functions
 *   "/rest/v1/rpc/fn", { "p_x": ... }   scripts de la mini (Python)
 */
const PATRONES = [
  /\.rpc\(\s*['"]([a-z_0-9]+)['"]\s*,\s*\{([^}]*)\}/g,
  /\brpc(?:Mutation)?\(\s*(?:env\s*,\s*)?['"]([a-z_0-9]+)['"]\s*,\s*\{([^}]*)\}/g,
  /rpc\/([a-z_0-9]+)["'][^{]{0,80}\{([^}]*)\}/g,
];

const problemas = [];
let llamadas = 0;

for (const archivo of archivos) {
  const src = fs.readFileSync(archivo, 'utf8');
  const rel = path.relative(raiz, archivo);
  const vistos = new Set();

  for (const pat of PATRONES) {
    for (const m of src.matchAll(pat)) {
      const [todo, fn, cuerpo] = m;
      if (!fn.startsWith('mypump')) continue;
      const clave = fn + '@' + m.index;
      if (vistos.has(clave)) continue;
      vistos.add(clave);
      llamadas++;
      const linea = src.slice(0, m.index).split('\n').length;

      if (!firmas.has(fn)) {
        /* Dos cosas MUY distintas se ven igual acá:
         *   (a) un typo o una función que no existe en ningún lado → error;
         *   (b) una función que SÍ está escrita en una migración del repo pero
         *       todavía no se aplicó en producción → pendiente, no error.
         *
         * El caso (b) es el patrón normal cuando el código sale antes que la
         * migración (con fallback en el cliente). Tratarlo como error obliga a
         * elegir entre romper el test o no poder deployar en ese orden, y lo
         * que termina pasando es que alguien apaga el test entero. */
        if (enMigraciones.has(fn)) {
          pendientes.push({ rel, linea, fn });
        } else {
          problemas.push({ rel, linea, fn, tipo: 'no existe',
            detalle: 'no está en producción NI en ninguna migración del repo (¿typo?)' });
        }
        continue;
      }
      const validos = firmas.get(fn);
      const mandados = [...cuerpo.matchAll(/['"]?(p_[a-z0-9_]+)['"]?\s*:/g)].map((x) => x[1]);
      const sobran = mandados.filter((p) => !validos.has(p));
      if (sobran.length) {
        problemas.push({ rel, linea, fn, tipo: 'parámetro inexistente',
          detalle: `manda ${sobran.join(', ')} — la firma acepta: ${[...validos].join(', ') || '(ninguno)'}` });
      }
    }
  }
}

// ── 3. Informe ──────────────────────────────────────────────────────────
console.log(`llamadas RPC encontradas: ${llamadas} en ${archivos.length} archivos\n`);

if (pendientes.length) {
  console.log(`⏳ ${pendientes.length} llamada(s) a funciones de MIGRACIONES SIN APLICAR en producción:\n`);
  for (const p of pendientes) {
    console.log(`  ${p.rel}:${p.linea}`);
    console.log(`    ${p.fn} — está escrita en una migración del repo pero NO en la base\n`);
  }
  console.log('  Hasta que se aplique, el código tiene que tener fallback. Aplicá la migración');
  console.log('  y volvé a volcar el esquema:');
  console.log('    ssh mini "~/agentkit-coach/venv/bin/python3 ~/esquema.py" > docs/ESQUEMA_PRODUCCION.txt\n');
}

if (!problemas.length) {
  console.log('✓ toda llamada RPC coincide con la firma real de producción'
    + (pendientes.length ? ' (salvo las pendientes de arriba)' : ''));
  process.exit(0);
}
console.log(`✗ ${problemas.length} desajuste(s):\n`);
for (const p of problemas) {
  console.log(`  ${p.rel}:${p.linea}`);
  console.log(`    ${p.fn} — ${p.tipo}`);
  console.log(`    ${p.detalle}\n`);
}
process.exit(1);
