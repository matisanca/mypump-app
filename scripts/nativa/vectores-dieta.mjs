#!/usr/bin/env node
/* =============================================================
   vectores-dieta.mjs — normalizarDieta de la web, para que la nativa indexe igual

   La web descarta las comidas sin opciones y las opciones sin alimentos ANTES de indexar
   (cliente.html:1842). Los swaps de comida se guardan con `optIdx`: si la nativa no
   normaliza igual, una opción vacía en el medio corre los índices y lo reemplazado en una
   app no se ve en la otra (o el anclaje borra el swap de la otra). Lo encontró la revisión
   del 14-oct en 1 de las 90 dietas publicadas.

   Corre la función real de origin/main sobre: las dietas de las cuentas de prueba, la de
   la demo, casos armados a propósito y (privado) las 90 publicadas. Escribe un resumen
   por plan: comidas, opciones y alimentos que quedan, y el objetivo de macros.

   Uso: node scripts/nativa/vectores-dieta.mjs
   ============================================================= */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const PRIVADO = path.join(os.homedir(), 'Developer', 'nativa-evidencia', 'privado');
const REF = process.env.VECTORES_REF || 'origin/main';
const HTML = execFileSync('git', ['show', `${REF}:public/cliente.html`], { cwd: RAIZ, maxBuffer: 64 * 1024 * 1024 }).toString();
const commit = execFileSync('git', ['rev-parse', '--short', REF], { cwd: RAIZ }).toString().trim();

function extraer(nombre) {
  const i = HTML.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no encontré function ${nombre}(`);
  let prof = 0;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}' && --prof === 0) return HTML.slice(i, k + 1);
  }
  throw new Error(`function ${nombre} sin cierre`);
}
function extraerConst(nombre) {
  const i = HTML.indexOf(`const ${nombre} = {`);
  let prof = 0;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}' && --prof === 0) return new Function(`return (${HTML.slice(HTML.indexOf('{', i), k + 1)});`)();
  }
  throw new Error(`const ${nombre} sin cierre`);
}

const normalizarDieta = new Function(`${extraer('normalizarDieta')}\nreturn normalizarDieta;`)();
const clonar = (x) => JSON.parse(JSON.stringify(x));

/** Lo que la nativa tiene que reproducir: por plan (tipo de día o la raíz), comidas → opciones → alimentos y objetivo. */
function resumen(entrada) {
  const r = normalizarDieta(clonar(entrada));
  const e = r.est || {};
  const planes = e.tipos_dia && e.tipos_dia.length ? e.tipos_dia : [e];
  return {
    usable: r.usable,
    problemas: r.problemas,
    planes: planes.map((p) => ({
      macros: p.macros_target ? [p.macros_target.kcal, p.macros_target.prot, p.macros_target.carb, p.macros_target.fat].map((v) => Number(v)) : null,
      comidas: (p.comidas || []).map((c) => ({ id: c.id ?? null, opciones: c.options.map((o) => ({ nombre: o.name ?? null, alimentos: o.foods.map((f) => f && f.name) })) })),
    })),
  };
}

const f = (name, kcal = 100, prot = 10, carb = 10, fat = 5) => ({ name, qty: 100, unit: 'g', kcal, prot, carb, fat });
const sinteticos = [
  // La que encontró la revisión: llena, llena, VACÍA, llena.
  { macros_target: { kcal: 2000, prot: 150, carb: 200, fat: 60 }, comidas: [
    { id: 'c1', name: 'Desayuno', options: [{ name: 'A', foods: [f('Huevo')] }, { name: 'B', foods: [f('Pan')] }, { name: 'C', foods: [] }, { name: 'D', foods: [f('Avena')] }] } ] },
  // Vacía ANTES de dos llenas (corría el anclaje a otro alimento).
  { macros_target: { kcal: 1800, prot: 140, carb: 180, fat: 50 }, comidas: [
    { id: 'c1', name: 'Almuerzo', options: [{ name: 'A', foods: [] }, { name: 'B', foods: [f('Pollo'), f('Arroz')] }, { name: 'C', foods: [f('Carne'), f('Papa')] }] } ] },
  // Comida sin opciones y comida con todas vacías: se van, con su problema.
  { macros_target: { kcal: 1500 }, comidas: [
    { id: 'c1', name: 'Merienda', options: [] }, { id: 'c2', name: 'Cena', options: [{ name: 'A', foods: [] }] }, { id: 'c3', name: 'Snack', options: [{ name: 'A', foods: [f('Yogur')] }] } ] },
  // Sin macros_target: suma de la opción A redondeada (con decimales y un número como texto).
  { comidas: [
    { id: 'c1', name: 'Desayuno', options: [{ name: 'A', foods: [f('Huevo', 143.4, 12.6, 0.7, 9.5), { name: 'Pan', kcal: '75.6', prot: 2.5, carb: 14.2, fat: 0.9 }] }] },
    { id: 'c2', name: 'Almuerzo', options: [{ name: 'A', foods: [f('Pollo', 165.5, 31.1, 0, 3.6)] }, { name: 'B', foods: [f('Tofu', 76, 8, 2, 4.8)] }] } ] },
  // macros_target con kcal 0: también se recalcula.
  { macros_target: { kcal: 0, prot: 0, carb: 0, fat: 0 }, comidas: [{ id: 'c1', name: 'X', options: [{ name: 'A', foods: [f('Banana', 89, 1.1, 22.8, 0.3)] }] }] },
  // tipos_dia vacío = formato A.
  { tipos_dia: [], macros_target: { kcal: 2100, prot: 160, carb: 210, fat: 70 }, comidas: [{ id: 'c1', name: 'Desayuno', options: [{ name: 'A', foods: [f('Huevo')] }] }] },
  // Formato B: un tipo sin comidas usables y otro bien, uno sin macros.
  { tipos_dia: [
    { id: 'entreno', nombre: 'Entreno', macros_target: { kcal: 2500, prot: 180, carb: 300, fat: 60 }, comidas: [{ id: 'c1', name: 'Pre', options: [{ name: 'A', foods: [f('Banana')] }, { name: 'B', foods: [] }] }] },
    { id: 'descanso', nombre: 'Descanso', comidas: [{ id: 'c1', name: 'Pre', options: [{ name: 'A', foods: [f('Nueces', 654, 15.2, 13.7, 65.2)] }] }] } ] },
  // Nada usable.
  { macros_target: { kcal: 2000 }, comidas: [{ id: 'c1', name: 'Desayuno', options: [{ name: 'A', foods: [] }] }] },
];

const leer = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const fixtures = path.join(RAIZ, 'apps/shared/fixtures');
const publicas = fs.readdirSync(fixtures)
  .map((c) => path.join(fixtures, c, 'get_dieta_activa.json'))
  .filter((p) => fs.existsSync(p))
  .map((p) => leer(p)[0]?.estructura)
  .filter(Boolean);
publicas.push(extraerConst('SAMPLE_DIET'));

const escribir = (destino, datos) => {
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  fs.writeFileSync(destino, JSON.stringify({ fuente: `cliente.html@${commit}`, ...datos }) + '\n');
  return datos.casos.length;
};

const casosPublicos = [...publicas, ...sinteticos].map((entrada) => ({ entrada, salida: resumen(entrada) }));
const n1 = escribir(path.join(RAIZ, 'apps/shared/vectores/normalizar_dieta.json'), { casos: casosPublicos });
let n2 = 0;
const privadas = path.join(PRIVADO, 'estructuras/dietas.json');
if (fs.existsSync(privadas)) {
  n2 = escribir(path.join(PRIVADO, 'vectores/normalizar_dieta.json'), { casos: leer(privadas).map((entrada) => ({ entrada, salida: resumen(entrada) })) });
}
console.log(`▸ normalizarDieta@${commit}: ${n1} públicos · ${n2} privados`);
