#!/usr/bin/env node
/* =============================================================
   generar-vectores.mjs — la web es la fuente de verdad de la lógica que se porta

   Saca funciones de public/cliente.html de origin/main (no de la rama nativa, que se
   queda vieja), las corre sobre un corpus y escribe {entrada, salida}. XCTest (iOS) y
   JUnit (Android) leen los mismos archivos: si la nativa no da lo mismo que la web, el
   test falla. Los desvíos a propósito se declaran en apps/shared/vectores/excepciones.json.

   Corpus:
   - público (se commitea): fixtures de las cuentas de prueba y la demo de la web;
   - privado (nunca se commitea): las estructuras reales de los planes activos, si están
     en ~/Developer/nativa-evidencia/privado/estructuras/.

   Salidas: apps/shared/vectores/<regla>.json y privado/vectores/<regla>.json

   Uso: node scripts/nativa/generar-vectores.mjs
   ============================================================= */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const PRIVADO = path.join(os.homedir(), 'Developer', 'nativa-evidencia', 'privado');
const REF = process.env.VECTORES_REF || 'origin/main';

process.env.TZ = 'America/Argentina/Buenos_Aires';
const HTML = execFileSync('git', ['show', `${REF}:public/cliente.html`], { cwd: RAIZ, maxBuffer: 64 * 1024 * 1024 }).toString();
const commit = execFileSync('git', ['rev-parse', '--short', REF], { cwd: RAIZ }).toString().trim();

/** Corta desde `function <nombre>(` hasta la llave que la cierra (mismo método que test-normalizar-plan.mjs). */
function extraer(nombre) {
  const i = HTML.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no encontré function ${nombre}( en cliente.html@${REF}`);
  let prof = 0;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}' && --prof === 0) return HTML.slice(i, k + 1);
  }
  throw new Error(`function ${nombre} sin cierre`);
}

/** Saca `const NOMBRE = { … };` (objetos literales de la demo). */
function extraerConst(nombre) {
  const i = HTML.indexOf(`const ${nombre} = {`);
  if (i < 0) throw new Error(`no encontré const ${nombre}`);
  let prof = 0;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}' && --prof === 0) return new Function(`return (${HTML.slice(HTML.indexOf('{', i), k + 1)});`)();
  }
  throw new Error(`const ${nombre} sin cierre`);
}

const reglas = new Function(`${extraer('getProgresionActual')}\n${extraer('computeProgresionNota')}\n${extraer('claveEjercicio')}\nreturn { getProgresionActual, computeProgresionNota, claveEjercicio };`)();

// ── Corpus ───────────────────────────────────────────────────────────
const leer = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const fixtures = path.join(RAIZ, 'apps/shared/fixtures');
const rutinasPublicas = fs.readdirSync(fixtures).map((c) => leer(path.join(fixtures, c, 'get_rutina_activa.json'))[0].estructura);
const demo = { rutina: extraerConst('SAMPLE_RUTINA'), dieta: extraerConst('SAMPLE_DIET') };
rutinasPublicas.push(demo.rutina);
const rutinasPrivadas = fs.existsSync(path.join(PRIVADO, 'estructuras/rutinas.json'))
  ? [...leer(path.join(PRIVADO, 'estructuras/rutinas.json')), ...leer(path.join(PRIVADO, 'estructuras/rutinas-en-cola.json'))]
  : [];

const ejerciciosDe = (rutinas) => rutinas.flatMap((r) => (r.dias || []).flatMap((d) => (d.bloques || []).filter(Boolean)
  .flatMap((b) => (b.ejercicios || []).filter((e) => e && typeof e === 'object'))));

// Los ejercicios van una vez; cada vector los referencia por índice (e) para que el archivo no repita la progresión.
function vectoresProgresion(rutinas) {
  const ejercicios = ejerciciosDe(rutinas);
  const casos = [];
  ejercicios.forEach((e, i) => {
    const largo = Array.isArray(e.progresion) ? e.progresion.length : 0;
    for (let semana = 1; semana <= Math.max(2, largo + 2); semana++) {
      casos.push({ e: i, semana, actual: reglas.getProgresionActual(e, semana), nota: reglas.computeProgresionNota(e, semana) });
    }
  });
  return { ejercicios, casos };
}

function escribir(destino, nombre, datos) {
  fs.mkdirSync(destino, { recursive: true });
  fs.writeFileSync(path.join(destino, `${nombre}.json`), JSON.stringify({ fuente: `public/cliente.html@${commit}`, ...datos }) + '\n');
  return datos.casos.length;
}

// Nombres difíciles a propósito: acentos, ñ, ø (la web la descarta; el folding de Swift la volvería "o"),
// paréntesis anidados o con salto de línea, grados, guiones largos, emoji, espacios raros.
const NOMBRES_DIFICILES = ['Jalón al pecho (prono)', 'Jalon al pecho', 'Curl araña', 'Press inclinado 45° — mancuernas',
  'Ørsted row', 'Curl (cabeza larga) (polea)', 'Pájaro (x\ny) invertido', '  Sentadilla   búlgara  ', '', 'X (pectoral superior)',
  'Remo 🏋️ con barra', 'Extensión de tríceps — polea alta', 'Hip thrust 1½', 'CURL FEMORAL SENTADO', 'Prensa 45º', 'Abducción (máquina',
  'Face-pull/con banda', 'Ｆｕｌｌ width', 'İnclinado', 'straße', 'œuvre', 'naïve café'];
function vectoresClave(nombres) {
  const unicos = [...new Set(nombres.filter((n) => typeof n === 'string'))];
  return { casos: unicos.map((nombre) => ({ nombre, clave: reglas.claveEjercicio(nombre) })) };
}
const nombresDe = (rutinas) => ejerciciosDe(rutinas).map((e) => e.nombre);

const sal = path.join(RAIZ, 'apps/shared/vectores');
const n1 = escribir(sal, 'progresion', vectoresProgresion(rutinasPublicas));
const n3 = escribir(sal, 'clave_ejercicio', vectoresClave([...NOMBRES_DIFICILES, ...nombresDe(rutinasPublicas)]));
fs.mkdirSync(path.join(RAIZ, 'apps/shared/demo'), { recursive: true });
fs.writeFileSync(path.join(RAIZ, 'apps/shared/demo/rutina.json'), JSON.stringify(demo.rutina, null, 1) + '\n');
fs.writeFileSync(path.join(RAIZ, 'apps/shared/demo/dieta.json'), JSON.stringify(demo.dieta, null, 1) + '\n');
let n2 = 0, n4 = 0;
if (rutinasPrivadas.length) {
  n2 = escribir(path.join(PRIVADO, 'vectores'), 'progresion', vectoresProgresion(rutinasPrivadas));
  const historicos = fs.existsSync(path.join(PRIVADO, 'estructuras/nombres-registrados.json')) ? leer(path.join(PRIVADO, 'estructuras/nombres-registrados.json')) : [];
  n4 = escribir(path.join(PRIVADO, 'vectores'), 'clave_ejercicio', vectoresClave([...nombresDe(rutinasPrivadas), ...historicos]));
}
console.log(`▸ cliente.html@${commit}: progresion ${n1} públicos / ${n2} privados · clave_ejercicio ${n3} públicos / ${n4} privados · demo en apps/shared/demo/`);
