#!/usr/bin/env node
/* =============================================================
   vectores-alimentos.mjs — el motor de sustitución de alimentos de la web, en vectores

   Corre el código REAL de origin/main con un `window` falso: public/js/app.js
   (window.MyPump.foodSwap), public/js/food-db.js (window.MYPUMP_FOOD_DB) y dos funciones
   sacadas de public/cliente.html (inferFoodCategory, y hydrateSwapsAndCustomFoodsFromBackend
   para sumar los alimentos propios del cliente exactamente como lo hace la web).

   Salidas:
   - apps/shared/food-db.json: el MYPUMP_FOOD_DB ya armado (categoría inferida + medida
     casera). La nativa lo empaqueta tal cual: no porta detectUnit ni el armado de la base.
   - apps/shared/vectores/categoria_alimento.json: nombre + macros → categoría con las TRES
     copias de la inferencia (_inferCategory de app.js, inferFoodCategory de cliente.html e
     inferCategory de food-db.js). Si alguna vez se separan, el test lo dice.
   - apps/shared/vectores/sustitutos_alimento.json: la lista completa de findSubstitutes y su
     _lastInfo, por alimento original × preferencias × con/sin alimentos propios, más unas
     búsquedas por texto (searchSubstitutes).
   - privado/vectores/ (nunca se commitea): lo mismo sobre las dietas activas reales, si está
     ~/Developer/nativa-evidencia/privado/estructuras/dietas.json.

   Para que el archivo no explote (con objetos completos, 8 MB): los originales, los sustitutos
   y las listas repetidas (las preferencias muchas veces no cambian nada) van una sola vez y se
   referencian por índice (ver `compactador`). Lo lee apps/ios/.../AlimentosTests.swift.

   Uso: node scripts/nativa/vectores-alimentos.mjs
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
const git = (...args) => execFileSync('git', args, { cwd: RAIZ, maxBuffer: 64 * 1024 * 1024 }).toString();
const APP = git('show', `${REF}:public/js/app.js`);
const FOOD_DB_JS = git('show', `${REF}:public/js/food-db.js`);
const HTML = git('show', `${REF}:public/cliente.html`);
const commit = git('rev-parse', '--short', REF).trim();
const FUENTE = `public/js/app.js, public/js/food-db.js y public/cliente.html @${commit}`;

/** Corta desde `function <nombre>(` (con su `async`, si lo tiene) hasta la llave que la cierra. */
function extraer(texto, nombre, archivo) {
  let i = texto.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no encontré function ${nombre}( en ${archivo}@${REF}`);
  if (texto.slice(i - 6, i) === 'async ') i -= 6;
  let prof = 0;
  for (let k = texto.indexOf('{', i); k < texto.length; k++) {
    if (texto[k] === '{') prof++;
    else if (texto[k] === '}' && --prof === 0) return texto.slice(i, k + 1);
  }
  throw new Error(`function ${nombre} sin cierre en ${archivo}`);
}

// ── La web, cargada como en el navegador ─────────────────────────────
const web = {};
new Function('window', APP)(web);
new Function('window', FOOD_DB_JS)(web);
const swap = web.MyPump.foodSwap;
const BASE = web.MYPUMP_FOOD_DB;
const inferFoodCategory = new Function(`${extraer(HTML, 'inferFoodCategory', 'cliente.html')}\nreturn inferFoodCategory;`)();
const inferCategoryDB = new Function(`${extraer(FOOD_DB_JS, 'inferCategory', 'food-db.js')}\nreturn inferCategory;`)();
const hidratar = new Function('window', 'TOKEN', 'DIETA_ID', 'STATE', 'renderDiet',
  `${extraer(HTML, 'hydrateSwapsAndCustomFoodsFromBackend', 'cliente.html')}\nreturn hydrateSwapsAndCustomFoodsFromBackend;`);

/** La base con los alimentos propios sumados por la función REAL de cliente.html (reemplaza por nombre o agrega al final). */
async function baseConPropios(propios) {
  const window = {
    MYPUMP_FOOD_DB: BASE.map((f) => ({ ...f })),
    mypumpDB: {
      getClientePrefs: async () => ({ excluir: [], idioma: 'es' }),
      getCustomFoods: async () => propios.map((p) => ({ ...p })),
      getFoodSwaps: async () => null,   // "no se pudo preguntar": corta antes de tocar los swaps
    },
  };
  const avisos = [];
  const warn = console.warn;
  console.warn = (...a) => avisos.push(a.join(' '));
  try {
    await hidratar(window, 'token-de-vectores', 'dieta-de-vectores', { scene: 'otra', foodSwaps: {} }, () => {})();
  } finally {
    console.warn = warn;
  }
  if (avisos.length) throw new Error(`el hidratado de cliente.html falló: ${avisos[0]}`);
  for (const p of propios) {
    if (!window.MYPUMP_FOOD_DB.some((f) => f._isCustom && f.name === p.name)) throw new Error(`el hidratado no sumó ${p.name}`);
  }
  return window.MYPUMP_FOOD_DB;
}

// ── Corpus ───────────────────────────────────────────────────────────
const leer = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const alimentosDe = (estructuras) => estructuras.flatMap((e) => {
  const planes = e && Array.isArray(e.tipos_dia) && e.tipos_dia.length ? e.tipos_dia : [e];
  return planes.flatMap((p) => ((p && p.comidas) || []).flatMap((c) => ((c && c.options) || [])
    .flatMap((o) => ((o && o.foods) || []).filter((f) => f && typeof f === 'object'))));
});
const unicos = (lista) => {
  const vistos = new Set();
  return lista.filter((x) => { const k = JSON.stringify(x); return vistos.has(k) ? false : (vistos.add(k), true); });
};

const fixtures = path.join(RAIZ, 'apps/shared/fixtures');
const dietasPublicas = fs.readdirSync(fixtures).sort()
  .map((c) => path.join(fixtures, c, 'get_dieta_activa.json')).filter((p) => fs.existsSync(p))
  .flatMap((p) => leer(p).map((fila) => fila.estructura));
dietasPublicas.push(leer(path.join(RAIZ, 'apps/shared/demo/dieta.json')));
const alimentosPublicos = unicos(alimentosDe(dietasPublicas));

const rutaDietasPrivadas = path.join(PRIVADO, 'estructuras/dietas.json');
const alimentosPrivados = fs.existsSync(rutaDietasPrivadas) ? unicos(alimentosDe(leer(rutaDietasPrivadas))) : [];

const r1 = (x) => Math.round(x * 10) / 10;

// Una muestra de la base como si fuera un alimento del plan: 100 g (las macros por 100 g son el total).
const muestraBase = BASE.filter((_, i) => i % 7 === 3)
  .map((f) => ({ name: f.name, qty: 100, unit: 'g', kcal: f.kcal, prot: f.prot, carb: f.carb, fat: f.fat }));
// Los que tienen medida casera, en unidades: originalQtyG = qty × unitGrams.
const conUnidad = BASE.filter((f) => f.unitGrams).map((f, i) => {
  const qty = 1 + (i % 3);
  const g = qty * f.unitGrams;
  return { name: f.name, qty, unit: f.unit, unitGrams: f.unitGrams,
    kcal: Math.round(f.kcal * g / 100), prot: r1(f.prot * g / 100), carb: r1(f.carb * g / 100), fat: r1(f.fat * g / 100) };
});

// Originales difíciles a propósito: cada uno entra por una rama distinta de findSubstitutes.
const ORIGINALES_DIFICILES = [
  { name: 'Sal', qty: 2, unit: 'g', kcal: 0, prot: 0, carb: 0, fat: 0 },                       // condimento real: lista vacía
  { name: 'Mostaza', qty: 10, unit: 'g', kcal: 8, prot: 0.4, carb: 0.6, fat: 0.4 },
  { name: 'Chimichurri', qty: 30, unit: 'g', kcal: 150, prot: 0.5, carb: 2, fat: 16 },          // "condimento" calórico: sigue
  { name: 'Mayonesa', qty: 15, unit: 'g', kcal: 100, prot: 0, carb: 0.2, fat: 11, category: 'condimento' },
  { name: 'Pollo al horno', qty: 150, unit: 'g', kcal: 250, prot: 0, carb: 0, fat: 0 },         // macros en cero, kcal válida
  { name: 'Arroz yamaní', qty: 80, unit: 'g', prot: 6, carb: 60, fat: 2 },                      // sin kcal
  { name: 'Banana', kcal: 105, prot: 1.3, carb: 27, fat: 0.4 },                                 // sin qty ni unidad
  { name: 'Aceite de oliva', qty: 20, unit: 'g', kcal: 400, prot: 0, carb: 0, fat: 45 },        // densidad > 950
  { name: 'Pechuga de pollo', qty: 500, unit: 'g', kcal: 20, prot: 5, carb: 0, fat: 0 },        // densidad < 10
  { name: 'Milanesa de soja', qty: 100, unit: 'g', kcal: 250, prot: 15, carb: 20, fat: 12, category: 'prote' },
  { name: 'Fideos con salsa', qty: 200, unit: 'g', kcal: 300, prot: 10, carb: 55, fat: 4, category: 'carb' },
  { name: 'Zapallo anco', qty: 200, unit: 'g', kcal: 60, prot: 2, carb: 14, fat: 0.2, category: 'verdura' },
  { name: 'Yogur bebible', qty: 200, unit: 'ml', kcal: 150, prot: 6, carb: 24, fat: 3, category: '' },
  { name: 'PECHUGA DE POLLO', qty: 200, unit: 'g', kcal: 220, prot: 46, carb: 0, fat: 2.4 },    // mismo nombre que la base, otra caja
  { name: 'Vaci\u0301o', qty: 200, unit: 'g', kcal: 324, prot: 41.4, carb: 0, fat: 16.8 },      // "Vacío" en NFD: para JS es OTRO nombre
  { name: 'Leche descremada', qty: 250, unit: 'ml', kcal: 88, prot: 8.5, carb: 12.5, fat: 0.3 },
  { name: 'Huevo entero', qty: 3, unit: 'unidad', unitGrams: 60, kcal: 257, prot: 22.6, carb: 1.3, fat: 17.8 },
  { name: 'Pan lactal', qty: 2, unit: 'rebanada', kcal: 160, prot: 5, carb: 30, fat: 2 },      // unidad sin unitGrams
  { name: 'Ñoquis de papa', qty: 250, unit: 'g', kcal: 340, prot: 8, carb: 70, fat: 2 },
  { name: 'Maní tostado', qty: 30, unit: 'g', kcal: 180, prot: 7.5, carb: 5, fat: 15 },
  { name: 'Jamón cocido', qty: 60, unit: 'g', kcal: 75, prot: 11, carb: 1, fat: 3 },
  { name: 'Langostinos', qty: 150, unit: 'g', kcal: 150, prot: 30, carb: 1, fat: 2 },
  { name: 'Queso cremoso', qty: 40, unit: 'g', kcal: 120, prot: 8, carb: 1, fat: 9.5 },
  { name: 'Lechuga', qty: 300, unit: 'g', kcal: 45, prot: 4, carb: 8, fat: 0.6 },
  { name: 'Ajo\n', qty: 5, unit: 'g', kcal: 7, prot: 0.3, carb: 1.6, fat: 0 },                  // \n final: `$` de JS no lo acepta
  { name: 'Agua', qty: 500, unit: 'ml', kcal: 0, prot: 0, carb: 0, fat: 0 },
  { name: 'Barrita de proteína', qty: 0, unit: 'g', kcal: 200, prot: 20, carb: 22, fat: 6 },   // qty 0
  { name: 'Whey', qty: 30, unit: 'g', kcal: 120, prot: 24, carb: 3, fat: 1.5 },
  { name: 'Bife de chorizo', qty: 250, unit: 'g', kcal: 538, prot: 52, carb: 0, fat: 35 },
  { name: 'Leche de coco', qty: 100, unit: 'ml', kcal: 197, prot: 2.2, carb: 2.8, fat: 21 },
  { name: 'Papas fritas', qty: 100, unit: 'g', kcal: 312, prot: 3.4, carb: 41, fat: 15 },
  { name: 'Pan dulce', qty: 80, unit: 'g', kcal: 300, prot: 6, carb: 48, fat: 10 },
  { name: 'Tortilla española', qty: 150, unit: 'g', kcal: 260, prot: 9, carb: 18, fat: 17 },
  { name: 'Mix de frutos secos', qty: 30, unit: 'g', kcal: 180, prot: 5, carb: 6, fat: 15 },
  { name: 'Pizza', qty: 2, unit: 'porcion', unitGrams: 120, kcal: 640, prot: 26, carb: 80, fat: 24 },
  { name: 'Gaseosa light', qty: 350, unit: 'ml', kcal: 1, prot: 0, carb: 0.2, fat: 0 },
];

// Tres alimentos propios sintéticos, con la forma de get_custom_foods. Uno pisa a un alimento de la base (mismo
// nombre en otra caja: la web lo reemplaza en su lugar) y otro va por unidad.
const PROPIOS = [
  { name: 'Barrita proteica casera', kcal: 380, prot: 30, carb: 40, fat: 10, unit: 'unidad', unit_grams: 50, category: 'carbohidrato' },
  { name: 'PECHUGA DE POLLO', kcal: 120, prot: 23, carb: 0, fat: 2.5, unit: 'g', unit_grams: null, category: 'proteina' },
  { name: 'Yogur de almendras', kcal: 95, prot: 3.5, carb: 9, fat: 5, unit: 'g', unit_grams: 0, category: 'lacteo' },
];
const PREFERENCIAS = [[], ['cerdo'], ['mariscos'], ['lacteos'], ['cerdo', 'mariscos', 'lacteos']];
const CONSULTAS = ['pollo', '  ARROZ ', 'á', 'pan', '', '   ', 'zzz', '\u00a0pan\u00a0', '\ufeffpan', 'pan\u0085', 'Ñ'];

// ── Categorías ───────────────────────────────────────────────────────
// Perfiles de macros para los nombres que no matchean ninguna palabra clave (la heurística decide).
const PERFILES = [
  {}, { prot: 0, carb: 0, fat: 0 }, { prot: null, carb: null, fat: null }, { prot: 25, carb: 2, fat: 3 },
  { prot: 2, carb: 60, fat: 1 }, { prot: 1, carb: 2, fat: 50 }, { prot: 10, carb: 10, fat: 2 }, { prot: 10, carb: 45, fat: 45 },
  { prot: 30, carb: 30, fat: 40 }, { prot: 50, carb: 50, fat: 0 }, { carb: 10, fat: 10 }, { prot: null, carb: 10, fat: 10 },
  { prot: 0.1, carb: 0.2, fat: 0.3 }, { prot: 1, carb: 1, fat: 1 }, { prot: 0, carb: 41, fat: 59 }, { prot: 7, carb: 0, fat: 7 },
];
const SIN_PALABRA_CLAVE = ['Agua', 'Creatina', 'Pizza', 'Hielo', 'Bebida isotónica', 'Cerveza', 'Suplemento X', '', 'Ｐｉｚｚａ', 'İskender'];
const NOMBRES_DIFICILES = [
  'Leche de coco', 'Leche de coco light', 'Bife de chorizo', 'Chorizo fresco', 'Pan dulce', 'Pan con tomate', 'Pancake de avena',
  'Papas fritas', 'Papa frita', 'Papa', 'Maní', 'Maní tostado', 'Mani', 'Mantequilla de maní', 'Manteca de maní', 'Ñoquis',
  'ñoquis de papa', 'Ajo', 'Ajos', 'Ajo en polvo', 'Ajo\n', 'Maní\n', 'ajo\r\n', 'Cabeza de ajo', 'Ensalada César', 'Ensalada cesar',
  'Ensalada mixta', 'Chile con carne', 'Chile jalapeño', 'Helado de frutilla', 'Jugo de naranja', 'Tortilla española',
  'Tortilla de trigo', 'Crema de leche', 'Crema de maní', 'Queso crema', 'Yogur con frutillas', 'Café con leche', 'Leche de soja',
  'Proteína whey', 'Proteina vegetal', 'Seitán', 'Atún al natural', 'ATÚN', 'Vacío', 'Vaci\u0301o', 'Pechuga', 'Hamburguesa de soja',
  'Sal', 'Sal marina', 'Salsa de tomate', 'Salsa picante', 'Pimienta', 'Nuez moscada', 'Pasta', 'Pastafrola', 'Pie de limón',
  'Durazno en almíbar', 'Melón', 'MELÓN', 'Ananá', 'Piña colada', 'Plátano macho', 'Platano', 'Banana split', 'Chía',
  'Semillas de chía', 'Lino', 'Linaza', 'Coco rallado', 'Coco fresco', 'Aceitunas', 'Olivas negras', 'Polenta', 'Harina de maíz',
  'Copos de maíz', 'Corn flakes', 'Choclo', 'Maíz', 'Batata', 'Yuca', 'Tapioca', 'Lentejas', 'Porotos negros', 'Soja cocida',
  'Edamame', 'Fideos', 'Ravioles', 'Gnocchi', 'Empanada de carne', 'Milanesa de pollo', 'Milanesa de soja', 'Tofu', 'Huevos revueltos',
  'Jamón cocido', 'Jamon crudo', 'Panceta', 'Lechón', 'Langostinos', 'Kani kama', 'Agua de coco', 'Ｐａｎ', 'PAN', 'Pan\u00a0integral',
  'pan\tintegral', 'Yogur griego', 'Kéfir', 'Requesón', 'Ricotta', 'Burrata', 'Mozarella', 'Provoleta', 'Chocolatada', 'Dulce de leche',
  'Alfajor', 'Barra cereal', 'Gomitas', 'Azúcar', 'Edulcorante', 'Mermelada de durazno', 'Kétchup', 'Vinagre', 'Aceto balsámico',
  'Chimichurri', 'Caldo cubo', 'Pimentón fresco', 'Jengibre fresco', 'Cúrcuma fresca', 'Páprika', 'Verduras salteadas',
  'Wok de verduras', 'Brócoli', 'Espinacas', 'Rúcula', 'Tomates cherry', 'Zapallitos', 'Champiñones', 'Espárragos', 'Alcaucil',
  'Palmitos', 'Morrón', 'Ají picante', 'Ají molido', 'Frutillas con crema', 'Uvas', 'Pera', 'Peras al vino', 'Tuna', 'Atún en aceite',
  'Pavita', 'Riñón', 'Mondongo', 'Carpaccio', 'Vísceras', 'Prote', 'Hongos', 'Hongo', 'Pochoclo', 'Galletas de arroz',
  'Barrita de cereal con chocolate', 'Leche', 'leche', 'LECHE', 'Le\u0301che', 'Queso', 'Yogurt', 'Yoghurt natural',
];
function vectoresCategoria(alimentos, conDificiles) {
  const entradas = alimentos.map((f) => {
    const e = { name: f.name };
    for (const k of ['prot', 'carb', 'fat']) if (k in f) e[k] = f[k];
    return e;
  });
  if (conDificiles) {
    for (const n of NOMBRES_DIFICILES) entradas.push({ name: n, prot: 5, carb: 10, fat: 3 });
    for (const n of SIN_PALABRA_CLAVE) for (const p of PERFILES) entradas.push({ name: n, ...p });
    entradas.push({ prot: 20, carb: 1, fat: 1 }, {});   // sin nombre
  }
  const casos = unicos(entradas).map((e) => ({
    ...e,
    app: swap._inferCategory(e),
    cliente: inferFoodCategory(e),
    fooddb: inferCategoryDB(e),
  }));
  return { casos };
}

// ── Sustitutos ───────────────────────────────────────────────────────
// Formato compacto (con objetos completos el archivo público pesaba 8 MB):
// - alimentos[a] = lo que un sustituto toma de la base: {name, category, _isCustom?, _universal?, _en?};
// - items[k]     = un sustituto: [a, qty, unit, kcal, prot, carb, fat, _dev];
// - resultados[r] = una lista de findSubstitutes: índices de items, en orden;
// - casos[c]     = {o: original, x: preferencias, p: con propios, r, info: [prefsFiltraron, macrosSospechosos, categoriaFallback]}.
// `compactar` reconstruye cada lista y exige el MISMO JSON que devolvió la web: el formato no pierde nada.
const CAMPOS = ['name', 'qty', 'unit', 'kcal', 'prot', 'carb', 'fat', 'category', '_dev', '_isCustom', '_universal', '_en'];
function findSubstitutes(base, excluir, original) {
  web.MYPUMP_FOOD_DB = base;
  web.MYPUMP_PREFS = { excluir, idioma: 'es' };
  const lista = swap.findSubstitutes(structuredClone(original));
  for (const s of lista) {
    for (const k of Object.keys(s)) if (!CAMPOS.includes(k)) throw new Error(`campo nuevo en findSubstitutes: ${k}`);
    for (const k of ['qty', 'kcal', 'prot', 'carb', 'fat', '_dev']) if (!Number.isFinite(s[k])) throw new Error(`${k} no finito en ${s.name}`);
  }
  const i = swap._lastInfo;
  return { lista, info: [i.prefsFiltraron, i.macrosSospechosos, i.categoriaFallback] };
}

function compactador() {
  const alimentos = [], items = [], resultados = [];
  const idx = { alimentos: new Map(), items: new Map(), resultados: new Map() };
  const meter = (tabla, mapa, clave, valor) => {
    if (!mapa.has(clave)) { mapa.set(clave, tabla.length); tabla.push(valor); }
    return mapa.get(clave);
  };
  const reconstruir = (k) => {
    const [a, qty, unit, kcal, prot, carb, fat, dev] = items[k];
    const { name, category, _isCustom, _universal, _en } = alimentos[a];
    const s = { name, qty, unit, kcal, prot, carb, fat, category, _dev: dev };
    if (_isCustom !== undefined) s._isCustom = _isCustom;
    if (_universal !== undefined) { s._universal = _universal; s._en = _en; }
    return s;
  };
  function compactar(lista) {
    const ks = lista.map((s) => {
      const al = { name: s.name, category: s.category };
      if ('_isCustom' in s) al._isCustom = s._isCustom;
      if ('_universal' in s) { al._universal = s._universal; al._en = s._en; }
      const a = meter(alimentos, idx.alimentos, JSON.stringify(al), al);
      const item = [a, s.qty, s.unit, s.kcal, s.prot, s.carb, s.fat, s._dev];
      return meter(items, idx.items, JSON.stringify(item), item);
    });
    if (JSON.stringify(ks.map(reconstruir)) !== JSON.stringify(lista)) throw new Error(`la lista compacta no reconstruye: ${JSON.stringify(lista[0])}`);
    return meter(resultados, idx.resultados, JSON.stringify(ks), ks);
  }
  return { alimentos, items, resultados, compactar };
}

async function vectoresSustitutos(originales, preferencias, conPropios, consultas) {
  const bases = [{ p: false, base: BASE }];
  if (conPropios) bases.push({ p: true, base: await baseConPropios(PROPIOS) });
  const { alimentos, items, resultados, compactar } = compactador();
  const casos = [];
  originales.forEach((original, o) => {
    for (const { p, base } of bases) {
      preferencias.forEach((excluir, x) => {
        const { lista, info } = findSubstitutes(base, excluir, original);
        casos.push({ o, x, p, r: compactar(lista), info });
      });
    }
  });
  // searchSubstitutes: filtra por texto la lista sin preferencias ni propios; se guardan las posiciones que quedan.
  const busquedas = [];
  originales.slice(0, consultas.length ? 40 : 0).forEach((original, o) => {
    const c = casos.findIndex((k) => k.o === o && !k.p && !preferencias[k.x].length);
    const { lista } = findSubstitutes(BASE, [], original);
    for (const consulta of consultas) {
      const hallados = swap.searchSubstitutes(structuredClone(original), consulta);
      busquedas.push({ c, consulta, posiciones: hallados.map((s) => lista.findIndex((t) => t.name === s.name)) });
    }
  });
  const datos = {
    base: { archivo: 'apps/shared/food-db.json', largo: BASE.length },
    propios: conPropios ? PROPIOS : [],
    preferencias, originales, alimentos, items, resultados, casos,
  };
  if (conPropios) {
    const conP = bases[1].base;
    // Dónde quedó cada propio en la base (la web reemplaza en su lugar al que tiene el mismo nombre).
    datos.baseConPropios = { largo: conP.length, propios: conP.flatMap((f, i) => (f._isCustom ? [i] : [])) };
  }
  if (busquedas.length) datos.busquedas = busquedas;
  return datos;
}

// ── Escritura ────────────────────────────────────────────────────────
function escribir(destino, nombre, datos) {
  fs.mkdirSync(destino, { recursive: true });
  fs.writeFileSync(path.join(destino, `${nombre}.json`), JSON.stringify({ fuente: FUENTE, ...datos }) + '\n');
  return datos.casos.length;
}

// La base, un alimento por línea (que el diff de git sea legible).
fs.writeFileSync(path.join(RAIZ, 'apps/shared/food-db.json'),
  `{"fuente":${JSON.stringify(`public/js/food-db.js@${commit}`)},"alimentos":[\n${BASE.map((f) => JSON.stringify(f)).join(',\n')}\n]}\n`);

const sal = path.join(RAIZ, 'apps/shared/vectores');
const originalesPublicos = unicos([...alimentosPublicos, ...muestraBase, ...conUnidad, ...ORIGINALES_DIFICILES]);
const nCat = escribir(sal, 'categoria_alimento', vectoresCategoria([...BASE, ...alimentosPublicos, ...ORIGINALES_DIFICILES, ...PROPIOS], true));
const nSus = escribir(sal, 'sustitutos_alimento', await vectoresSustitutos(originalesPublicos, PREFERENCIAS, true, CONSULTAS));

let nCatPriv = 0, nSusPriv = 0;
if (alimentosPrivados.length) {
  const priv = path.join(PRIVADO, 'vectores');
  nCatPriv = escribir(priv, 'categoria_alimento', vectoresCategoria(alimentosPrivados, false));
  nSusPriv = escribir(priv, 'sustitutos_alimento', await vectoresSustitutos(alimentosPrivados, [[], ['cerdo']], false, []));
}

// Las tres copias de la inferencia tienen que dar lo mismo; si no, avisar (el test elige contra cuál comparar).
const distintas = JSON.parse(fs.readFileSync(path.join(sal, 'categoria_alimento.json'), 'utf8')).casos
  .filter((c) => c.app !== c.cliente || c.app !== c.fooddb);
console.log(`▸ ${FUENTE}`);
console.log(`  food-db.json: ${BASE.length} alimentos`);
console.log(`  categoria_alimento: ${nCat} públicos / ${nCatPriv} privados · copias que difieren: ${distintas.length}`);
console.log(`  sustitutos_alimento: ${nSus} públicos / ${nSusPriv} privados`);
for (const c of distintas.slice(0, 10)) console.log('   ≠', JSON.stringify(c));
