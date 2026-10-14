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

const reglas = new Function(`${extraer('getProgresionActual')}\n${extraer('computeProgresionNota')}\n${extraer('claveEjercicio')}\n${extraer('porcionReferencia')}\nreturn { getProgresionActual, computeProgresionNota, claveEjercicio, porcionReferencia };`)();
// _swapAplicable consulta _foodsEnPosicion(comidaId, optIdx, foodIdx) (los alimentos de esa posición en TODOS los
// tipos de día): se inyecta una versión que lee la dieta del caso.
const anclaje = new Function('_foodsEnPosicion', `${extraer('_huellaFood')}\n${extraer('_swapAplicable')}\nreturn { _huellaFood, _swapAplicable };`);

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

// ── Alimentos: porción casera y anclaje de swaps ─────────────────────
const FOOD_DB = (() => {
  const w = {};
  new Function('window', execFileSync('git', ['show', `${REF}:public/js/food-db.js`], { cwd: RAIZ }).toString())(w);
  return w.MYPUMP_FOOD_DB;
})();
const dietasPublicas = fs.readdirSync(fixtures).map((c) => leer(path.join(fixtures, c, 'get_dieta_activa.json'))[0].estructura);
dietasPublicas.push(demo.dieta);
// Formato B sintético: la misma posición con otra cantidad según el tipo de día ("Avena 80 g" entreno / "Avena 50 g"
// descanso) y otro alimento en otra posición. Es el caso que rompió el anclaje el 20-sep.
dietasPublicas.push({ tipos_dia: [
  { id: 'entreno', nombre: 'Entreno', comidas: [{ id: 'desayuno', name: 'Desayuno', options: [{ name: 'A', foods: [
    { name: 'Avena', qty: 80, unit: 'g', kcal: 300, prot: 10, carb: 54, fat: 6 },
    { name: 'Leche', qty: 250, unit: 'ml', kcal: 120, prot: 8, carb: 12, fat: 4 },
    { name: 'Tostadas', qty: 2, unit: 'unidad', kcal: 140, prot: 4, carb: 26, fat: 2 } ] }] }] },
  { id: 'descanso', nombre: 'Descanso', comidas: [{ id: 'desayuno', name: 'Desayuno', options: [{ name: 'A', foods: [
    { name: 'Avena', qty: 50, unit: 'g', kcal: 190, prot: 6, carb: 34, fat: 4 },
    { name: 'Leche', qty: 250, unit: 'ml', kcal: 120, prot: 8, carb: 12, fat: 4 },
    { name: 'Banana', qty: 1, unit: 'unidad', kcal: 105, prot: 1, carb: 27, fat: 0 } ] }] }] },
] });
const dietasPrivadas = fs.existsSync(path.join(PRIVADO, 'estructuras/dietas.json')) ? leer(path.join(PRIVADO, 'estructuras/dietas.json')) : [];
const comidasDe = (d) => [...(d.comidas || []), ...(d.tipos_dia || []).flatMap((t) => t.comidas || [])];
const alimentosDe = (dietas) => dietas.flatMap((d) => comidasDe(d).flatMap((c) => (c.options || []).flatMap((o) => o.foods || [])));

// Porción casera: los alimentos de las dietas, más FOOD_DB con varias cantidades y unidades (lo que puede quedar
// después de un swap), más casos borde.
function corpusPorcion(dietas, conBase) {
  const out = [...alimentosDe(dietas)];
  if (conBase) {
    for (const f of FOOD_DB) {
      for (const qty of [6, 15, 30, 50, 80, 100, 120, 150, 185, 200, 245, 300, 480]) out.push({ ...f, qty, unit: 'g' });
      if (f.unitGrams) for (const qty of [0.5, 1, 2, 3, 25, 60]) out.push({ ...f, qty, unit: f.unit || 'unidad' });
    }
    out.push({ name: 'Leche descremada', qty: 250, unit: 'ml' }, { name: 'Gaseosa', qty: 500, unit: 'cc' },
      { name: 'Aceite de oliva', qty: 5, unit: 'ml' }, { name: 'Huevos', qty: 3, unit: 'u' }, { name: 'Panes', qty: 2, unit: 'unidades' },
      { name: 'Arroz', qty: 1, unit: 'taza' }, { name: 'Atún al natural', qty: 20, unit: 'g' }, { name: 'Atún', qty: 170, unit: 'g' },
      { name: 'Atún', qty: 240, unit: 'g' }, { name: 'Papaya', qty: 200, unit: 'g' }, { name: 'Pan rallado', qty: 30, unit: 'g' },
      { name: 'Pechuga de pollo cruda', qty: 230, unit: 'g' }, { name: '', qty: 100, unit: 'g' }, { name: 'Pollo', qty: 0, unit: 'g' },
      { name: 'Pollo', qty: 'abc', unit: 'g' }, { name: 'Nueces', qty: '45', unit: 'G' }, { name: 'Crema de maní', qty: 6, unit: 'g' },
      { name: 'Lápices', qty: 40, unit: 'paquetes', unitGrams: 5 }, { name: 'Raíces', qty: 30, unit: 'unidad', unitGrams: 10 });
  }
  return out;
}
function vectoresPorcion(alimentos) {
  const vistos = new Set();
  const casos = [];
  for (const f of alimentos) {
    const k = JSON.stringify([f.name, f.qty, f.unit, f.unitGrams]);
    if (vistos.has(k)) continue;
    vistos.add(k);
    casos.push({ alimento: { name: f.name, qty: f.qty, unit: f.unit, unitGrams: f.unitGrams }, porcion: reglas.porcionReferencia(f) });
  }
  return { casos };
}

// Anclaje: para cada dieta, swaps sintéticos sobre cada posición (ancla igual, otra cantidad, otro nombre, legado
// sin ancla), evaluados contra lo que hay en esa posición en el tipo de día que se renderiza.
function vectoresAnclaje(dietas) {
  const casos = [];
  for (const [di, d] of dietas.entries()) {
    const tipos = (d.tipos_dia && d.tipos_dia.length) ? d.tipos_dia : [{ comidas: d.comidas || [] }];
    const foodsEnPosicion = (comidaId, optIdx, foodIdx) => tipos.map((t) => {
      const c = (t.comidas || []).find((x) => x.id === comidaId);
      return c && c.options && c.options[optIdx] && (c.options[optIdx].foods || [])[foodIdx];
    }).filter(Boolean);
    const { _swapAplicable } = anclaje(foodsEnPosicion);
    for (const t of tipos) for (const c of (t.comidas || [])) (c.options || []).forEach((o, oi) => (o.foods || []).forEach((f, fi) => {
      const variantes = [
        { name: 'X', _orig: { name: f.name, qty: f.qty, unit: f.unit } },
        { name: 'X', _orig: { name: ` ${String(f.name).toUpperCase()} `, qty: f.qty, unit: String(f.unit || '').toUpperCase() } },
        { name: 'X', _orig: { name: f.name, qty: (Number(f.qty) || 0) + 10, unit: f.unit } },
        { name: 'X', _orig: { name: 'Otro alimento', qty: f.qty, unit: f.unit } },
        { name: 'X' },
        // El ancla es lo que hay en ESA posición en otro tipo de día (Avena 80 entreno vista en descanso con 50).
        ...foodsEnPosicion(c.id, oi, fi).filter((g) => g !== f).map((g) => ({ name: 'X', _orig: { name: g.name, qty: g.qty, unit: g.unit } })),
      ];
      for (const cur of variantes) {
        casos.push({ dieta: di, comidaId: c.id, optIdx: oi, foodIdx: fi, original: f,
          current: cur, aplica: _swapAplicable({ current: cur }, f, c.id, oi, fi), aplicaSinComida: _swapAplicable({ current: cur }, f, null, oi, fi) });
      }
    }));
  }
  return { casos };
}

const sal = path.join(RAIZ, 'apps/shared/vectores');
const n1 = escribir(sal, 'progresion', vectoresProgresion(rutinasPublicas));
const n3 = escribir(sal, 'clave_ejercicio', vectoresClave([...NOMBRES_DIFICILES, ...nombresDe(rutinasPublicas)]));
const n5 = escribir(sal, 'porcion_casera', vectoresPorcion(corpusPorcion(dietasPublicas, true)));
const n6 = escribir(sal, 'anclaje_swaps', vectoresAnclaje(dietasPublicas));
fs.mkdirSync(path.join(RAIZ, 'apps/shared/demo'), { recursive: true });
fs.writeFileSync(path.join(RAIZ, 'apps/shared/demo/rutina.json'), JSON.stringify(demo.rutina, null, 1) + '\n');
fs.writeFileSync(path.join(RAIZ, 'apps/shared/demo/dieta.json'), JSON.stringify(demo.dieta, null, 1) + '\n');
let n2 = 0, n4 = 0;
if (rutinasPrivadas.length) {
  n2 = escribir(path.join(PRIVADO, 'vectores'), 'progresion', vectoresProgresion(rutinasPrivadas));
  const historicos = fs.existsSync(path.join(PRIVADO, 'estructuras/nombres-registrados.json')) ? leer(path.join(PRIVADO, 'estructuras/nombres-registrados.json')) : [];
  n4 = escribir(path.join(PRIVADO, 'vectores'), 'clave_ejercicio', vectoresClave([...nombresDe(rutinasPrivadas), ...historicos]));
}
let n7 = 0, n8 = 0;
if (dietasPrivadas.length) {
  n7 = escribir(path.join(PRIVADO, 'vectores'), 'porcion_casera', vectoresPorcion(corpusPorcion(dietasPrivadas, false)));
  n8 = escribir(path.join(PRIVADO, 'vectores'), 'anclaje_swaps', vectoresAnclaje(dietasPrivadas));
}
console.log(`▸ cliente.html@${commit}: progresion ${n1}/${n2} · clave_ejercicio ${n3}/${n4} · porcion_casera ${n5}/${n7} · anclaje_swaps ${n6}/${n8} (públicos/privados) · demo en apps/shared/demo/`);
