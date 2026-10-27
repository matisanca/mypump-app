#!/usr/bin/env node
/* =============================================================
   vectores-consumo.mjs — «Consumido hoy» de la web (DIE-05..07, D25), para que las nativas sumen igual

   Corre `calcularConsumido` de origin/main (cliente.html) con su estado de mentira: el plan del día, las marcas como
   las deja `loadComidasMarcadas` (fila del servidor → {opcion, estado, foodsExcluidos}), los reemplazos que contesta
   `getEffectiveFood` por posición (comida|opción|alimento) y las comidas libres del día. Escribe {entrada, salida}:
   las kcal y macros consumidas, cuántas comidas hay y cuántas se comieron.

   Lo que se prueba: la opción de la marca por NOMBRE (la primera con ese nombre; si no hay, la A, aunque se esté
   mirando otra), los reemplazos de ESA opción, los alimentos destildados (índices de esa opción; los que no existen no
   cuentan), «saltado» no suma, y las comidas libres con `Number(x) || 0`.

   Los ajustes del día («Hoy no la como», porciones) son solo de las nativas: esos vectores los genera iOS
   (ConsumoDelDiaTests, `consumo_dia_ajustes.json`).

   Corpus: las dietas de las cuentas de prueba y la de la demo (públicas) con marcas armadas acá, casos a propósito y
   (privado) las 100 publicadas con marcas pseudoaleatorias fijas.

   Uso: node scripts/nativa/vectores-consumo.mjs
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
  if (i < 0) throw new Error(`no encontré function ${nombre}( en cliente.html@${REF}`);
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

const fabricar = new Function('getActivePlan', 'getEffectiveFood', 'STATE', `${extraer('calcularConsumido')}\nreturn calcularConsumido;`);
const normalizarDieta = new Function(`${extraer('normalizarDieta')}\nreturn normalizarDieta;`)();
const clonar = (x) => JSON.parse(JSON.stringify(x));

/** Las filas del servidor como las deja `loadComidasMarcadas` en STATE.comidasMarcadas. */
function marcasDeFilas(filas) {
  const map = {};
  for (const r of filas || []) {
    map[r.comida_id] = { opcion: r.opcion_elegida, estado: r.estado, marcada_en: r.marcada_en,
      foodsExcluidos: Array.isArray(r.foods_excluidos) ? r.foods_excluidos : [] };
  }
  return map;
}

function correr(entrada) {
  const STATE = { comidasMarcadas: marcasDeFilas(entrada.marcas), comidasLibres: entrada.libres };
  const efectivo = (f, comidaId, opt, idx) => (entrada.swaps || {})[`${comidaId}|${opt}|${idx}`] || f;
  const r = fabricar(() => ({ comidas: entrada.comidas }), efectivo, STATE)();
  return { kcal: r.kcal, prot: r.prot, carb: r.carb, fat: r.fat, nComidas: r.nComidas, nComidasMarcadas: r.nComidasMarcadas };
}

/** Los planes de una dieta como los ve la web después de normalizar: la raíz o cada tipo de día. */
function planes(estructura) {
  const r = normalizarDieta(clonar(estructura));
  if (!r.usable) return [];
  const e = r.est || {};
  return (e.tipos_dia && e.tipos_dia.length ? e.tipos_dia : [e]).filter((p) => (p.comidas || []).length);
}

/** El nombre que guarda la web al marcar: el de la opción, o 'A' si no tiene (`options[optIdx]?.name || 'A'`). */
const nombreWeb = (c, i) => (c.options[i] && c.options[i].name) || 'A';

const fila = (comida_id, opcion_elegida, estado, foods_excluidos = null) => ({ comida_id, opcion_elegida, estado, foods_excluidos });

/** Marcas armadas sobre un plan: nada, todo A, y una mezcla con otra opción, destildados, salteadas y libres. */
function escenarios(plan, nombre) {
  const cs = plan.comidas;
  const casos = [];
  casos.push({ nombre: `${nombre}: sin marcas`, entrada: { comidas: cs, marcas: [], libres: [] } });
  casos.push({ nombre: `${nombre}: todo comido con la A`, entrada: { comidas: cs, marcas: cs.map((c) => fila(c.id, nombreWeb(c, 0), 'comido')), libres: [] } });
  const mezcla = cs.map((c, i) => {
    const o = Math.min(i % 3, c.options.length - 1);
    if (i % 4 === 1) return fila(c.id, nombreWeb(c, o), 'saltado');
    if (i % 4 === 3) return null;
    return fila(c.id, nombreWeb(c, o), 'comido', i % 2 === 0 ? [0] : [1, 7]);
  }).filter(Boolean);
  // Un reemplazo en la opción marcada y otro en una que no se marcó (no tiene que contar).
  const swaps = {};
  const c0 = cs[0];
  if (c0) {
    swaps[`${c0.id}|0|1`] = { name: 'Reemplazo de prueba', qty: 100, unit: 'g', kcal: 222.5, prot: 20.25, carb: 10, fat: 9.5 };
    if (c0.options.length > 1) swaps[`${c0.id}|1|0`] = { name: 'Otro reemplazo', qty: 50, unit: 'g', kcal: 999, prot: 99, carb: 99, fat: 99 };
  }
  casos.push({ nombre: `${nombre}: mezcla con reemplazos y libres`, entrada: { comidas: cs, marcas: mezcla, swaps,
    libres: [{ kcal: 350, prot: 20, carb: 40.5, fat: 10 }, { kcal: '125', prot: null, carb: 'x', fat: 3.25 }] } });
  return casos;
}

const f = (name, kcal, prot, carb, fat, qty = 100, unit = 'g') => ({ name, qty, unit, kcal, prot, carb, fat });
const huevo = f('Huevo entero', 172, 15.1, 0.8, 11.4, 2, 'unidad');
const pan = f('Pan integral', 200, 8, 38, 2, 80);
const palta = f('Palta', 80, 1, 4, 7.3, 50);
const pollo = f('Pechuga de pollo', 330, 62, 0, 7, 200);
const arroz = f('Arroz', 195, 4, 42, 0.5, 150);
const yogur = f('Yogur', 120, 10, 14, 3, 200);
const comidasBase = [
  { id: 'c1', name: 'Desayuno', options: [{ name: 'A', foods: [huevo, pan, palta] }, { name: 'B', foods: [yogur, pan] }, { name: 'C', foods: [huevo] }] },
  { id: 'c2', name: 'Almuerzo', options: [{ name: 'A', foods: [pollo, arroz] }, { name: 'B', foods: [arroz, palta] }] },
  { id: 'c3', name: 'Merienda', options: [{ name: 'A', foods: [yogur] }] },
];

const sinteticos = [
  { nombre: 'la marca guarda la opción: se cuenta la B aunque se mire la A', entrada: { comidas: comidasBase, marcas: [fila('c1', 'B', 'comido')], libres: [] } },
  { nombre: 'una opción que ya no existe cuenta la A', entrada: { comidas: comidasBase, marcas: [fila('c1', 'Z', 'comido'), fila('c2', null, 'comido')], libres: [] } },
  { nombre: 'saltado no suma ni cuenta como comida comida', entrada: { comidas: comidasBase, marcas: [fila('c1', 'A', 'saltado'), fila('c2', 'B', 'saltado')], libres: [] } },
  { nombre: 'destildados: se descuentan los de esa opción; los que no existen y los repetidos no cambian nada',
    entrada: { comidas: comidasBase, marcas: [fila('c1', 'A', 'comido', [2, 0, 2, 9]), fila('c2', 'B', 'comido', [1]), fila('c3', 'A', 'comido', [])], libres: [] } },
  { nombre: 'todo destildado: la comida cuenta como comida con 0 kcal', entrada: { comidas: comidasBase, marcas: [fila('c1', 'C', 'comido', [0])], libres: [] } },
  { nombre: 'el reemplazo de la opción marcada cuenta; el de otra opción no',
    entrada: { comidas: comidasBase, marcas: [fila('c1', 'B', 'comido'), fila('c2', 'A', 'comido', [0])],
      swaps: { 'c1|1|0': f('Queso untable', 90, 6, 3, 6, 30), 'c1|0|0': f('No cuenta', 500, 50, 50, 50), 'c2|0|0': f('Destildado', 400, 40, 0, 20), 'c2|0|1': f('Fideos', 350, 12, 70, 1.5, 100) },
      libres: [] } },
  { nombre: 'solo comidas libres', entrada: { comidas: comidasBase, marcas: [], libres: [{ kcal: 565, prot: 30, carb: 50, fat: 25 }, { kcal: null, prot: '12.5', carb: 0, fat: null }] } },
  { nombre: 'marcas de comidas que no están en el plan no cuentan', entrada: { comidas: comidasBase, marcas: [fila('c9', 'A', 'comido'), fila('c3', 'A', 'comido')], libres: [] } },
  { nombre: 'alimentos sin macros cuentan cero', entrada: { comidas: [{ id: 'c1', name: 'Snack', options: [{ name: 'A', foods: [{ name: 'Café' }, f('Banana', 105, 1.3, 27, 0.4, 1, 'unidad')] }] }],
    marcas: [fila('c1', 'A', 'comido')], libres: [] } },
  { nombre: 'nombres repetidos: cuenta la primera con ese nombre (como la web)',
    entrada: { comidas: [{ id: 'c1', name: 'Desayuno', options: [{ name: 'A', foods: [huevo] }, { name: 'A', foods: [pan, palta] }, { name: 'B', foods: [yogur] }] }],
      marcas: [fila('c1', 'A', 'comido')], libres: [] } },
  { nombre: 'opciones sin nombre: la web guarda A y cuenta la primera',
    entrada: { comidas: [{ id: 'c1', name: 'Desayuno', options: [{ foods: [huevo] }, { foods: [pan, palta] }] }, { id: 'c2', name: 'Cena', options: [{ foods: [pollo] }, { foods: [arroz] }] }],
      marcas: [fila('c1', 'A', 'comido'), fila('c2', 'A', 'comido', [0])], libres: [] } },
];

// Lo que las nativas deciden distinto a propósito (no va en los casos; lo prueban ConsumoDelDiaTests / ConsumoDelDiaTest).
const excepciones = [
  'Opciones sin nombre: la web guarda "A" para cualquiera (`name || \'A\'`) y siempre cuenta la primera; las nativas guardan la letra de la que se ve (A, B, C…) y cuentan esa. Una marca "A" de la web cuenta la primera en las tres.',
  'Ajustes del día (D22): «Hoy no la como» no muestra Comí / Salté ni cuenta entre las comidas, y lo comido son las porciones ajustadas. La web no conoce los ajustes (vectores en consumo_dia_ajustes.json, de iOS).',
];

const leer = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const fixtures = path.join(RAIZ, 'apps/shared/fixtures');
const publicas = fs.readdirSync(fixtures)
  .map((c) => [c, path.join(fixtures, c, 'get_dieta_activa.json')])
  .filter(([, p]) => fs.existsSync(p))
  .map(([c, p]) => [c, leer(p)[0]?.estructura])
  .filter(([, e]) => e);
publicas.push(['demo', extraerConst('SAMPLE_DIET')]);

const casosPublicos = [];
for (const [nombre, estructura] of publicas) planes(estructura).forEach((p, i) => casosPublicos.push(...escenarios(p, `${nombre}${i ? ` (plan ${i + 1})` : ''}`)));
casosPublicos.push(...sinteticos);

const escribir = (destino, datos) => {
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  const casos = datos.casos.map((c) => ({ ...c, salida: correr(c.entrada) }));
  fs.writeFileSync(destino, JSON.stringify({ fuente: `cliente.html@${commit}`, excepciones, ...datos, casos }) + '\n');
  return casos.length;
};
const n1 = escribir(path.join(RAIZ, 'apps/shared/vectores/consumo_dia.json'), { casos: casosPublicos });

// Privado: las dietas publicadas con marcas pseudoaleatorias fijas (la misma semilla da los mismos casos).
let n2 = 0;
const privadas = path.join(PRIVADO, 'estructuras/dietas.json');
if (fs.existsSync(privadas)) {
  let semilla = 20261027;
  const azar = () => ((semilla = (semilla * 1103515245 + 12345) % 2147483648) / 2147483648);
  const casos = [];
  leer(privadas).forEach((estructura, d) => planes(estructura).forEach((p, i) => {
    for (let k = 0; k < 3; k++) {
      const marcas = [];
      for (const c of p.comidas) {
        const x = azar();
        if (x < 0.25) continue;
        const o = Math.floor(azar() * c.options.length);
        const n = c.options[o].foods.length;
        const excl = azar() < 0.4 ? [Math.floor(azar() * (n + 1))] : null;
        marcas.push(fila(c.id, nombreWeb(c, o), x < 0.4 ? 'saltado' : 'comido', excl));
      }
      const libres = azar() < 0.3 ? [{ kcal: Math.round(azar() * 800), prot: Math.round(azar() * 400) / 10, carb: Math.round(azar() * 900) / 10, fat: Math.round(azar() * 300) / 10 }] : [];
      casos.push({ nombre: `dieta ${d}, plan ${i}, ${k}`, entrada: { comidas: p.comidas, marcas, libres } });
    }
  }));
  n2 = escribir(path.join(PRIVADO, 'vectores/consumo_dia.json'), { casos });
}
console.log(`▸ calcularConsumido@${commit}: ${n1} públicos · ${n2} privados`);
