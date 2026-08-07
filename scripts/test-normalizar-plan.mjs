#!/usr/bin/env node
/* =============================================================
   test-normalizar-plan.mjs — que ningún plan publicable tumbe la app

   POR QUÉ EXISTE
   El Cerebro publica JSON libre en mypump_rutinas.estructura y
   mypump_dietas.estructura. Son columnas jsonb: nada valida su forma del lado
   de la base. Un plan al que le falte una clave llega igual al teléfono, y la
   app lo desreferencia sin preguntar en ~8 lugares
   (DATA.dia.bloques.flatMap(...)).

   Cinco formas publicables que la tumbaban, todas reproducibles con el banco
   (scripts/seed-cliente.mjs):

     escenario           qué pasaba
     plan-sin-dias       dias:[] es TRUTHY → pasaba la guarda y moría en dias[0]
     dia-vacio           .flatMap de undefined
     sin-descanso        chip "NaN:NaN" y timer de descanso eterno
     plan-sin-macros     tg.kcal → TypeError que se lleva el ARRANQUE ENTERO
     dieta-1-opcion      comida sin options → renderMeal rompe

   Se extraen las funciones de cliente.html por texto, igual que test-outbox.mjs
   con el IIFE del Outbox: son 8100 líneas con DOM adentro, no hay módulo que
   importar. Si alguien las renombra, esto falla ruidosamente — que es lo que
   queremos.

   USO:  node scripts/test-normalizar-plan.mjs
   ============================================================= */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const HTML = fs.readFileSync(path.join(RAIZ, 'public/cliente.html'), 'utf8');

/** Corta desde `function <nombre>(` hasta la línea `}` a nivel 0. */
function extraer(nombre) {
  const i = HTML.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no encontré function ${nombre}( en cliente.html`);
  let prof = 0, fin = -1;
  for (let k = HTML.indexOf('{', i); k < HTML.length; k++) {
    if (HTML[k] === '{') prof++;
    else if (HTML[k] === '}') { prof--; if (prof === 0) { fin = k + 1; break; } }
  }
  if (fin < 0) throw new Error(`no pude cerrar ${nombre}`);
  return HTML.slice(i, fin);
}

const src = [
  'const DESCANSO_POR_DEFECTO = 90;',
  extraer('normalizarRutina'),
  extraer('normalizarDieta'),
  'return { normalizarRutina, normalizarDieta };',
].join('\n');
const { normalizarRutina, normalizarDieta } = new Function(src)();

let ok = 0, fail = 0;
const t = (n, fn) => {
  try { fn(); console.log(`  ✓ ${n}`); ok++; }
  catch (e) { console.log(`  ✗ ${n}\n      ${e.message}`); fail++; }
};
const si = (c, m) => { if (!c) throw new Error(m); };
const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}\n      esperado ${JSON.stringify(b)}\n      obtenido ${JSON.stringify(a)}`); };

// Un plan sano de referencia.
const ej = (extra = {}) => ({ id: 'x', nombre: 'Press banca', tipo: 'compuesto', series: 4, reps: '6-8', descanso_segundos: 180, ...extra });
const sano = () => ({
  semanas_total: 12,
  dias: [{ id: 'lun', nombre: 'PUSH', bloques: [{ titulo: 'A', ejercicios: [ej()] }] }],
});

console.log('\nRutina');

t('un plan sano pasa sin tocarle nada ni inventar problemas', () => {
  const r = normalizarRutina(sano());
  si(r.usable, 'marcó usable:false');
  eq(r.problemas, [], 'inventó problemas');
  eq(r.est.dias[0].bloques[0].ejercicios[0].descanso_segundos, 180, 'pisó el descanso');
});

t('dias:[] NO es usable, y el motivo que da es el correcto', () => {
  si([], 'sanity');                        // [] es truthy en JS: por eso pasaba la guarda vieja
  const r = normalizarRutina({ dias: [] });
  si(!r.usable, 'lo dio por usable');
  // El mensaje importa: es lo que el cliente termina leyendo en el cartel y lo
  // que Mati ve en la captura. "sin días cargados" y "ningún día tiene
  // ejercicios" son diagnósticos distintos y mandan a revisar cosas distintas.
  si(/no tiene días/i.test(r.problemas.join(' ')),
     `dijo "${r.problemas.join(' ')}" en vez de que el plan no tiene días`);
});

t('estructura ausente o basura no rompe', () => {
  for (const v of [null, undefined, {}, { dias: null }, { dias: 'ocho' }]) {
    const r = normalizarRutina(v);
    si(!r.usable, `dio usable con ${JSON.stringify(v)}`);
  }
});

t('día sin bloques queda con bloques:[] y se reporta', () => {
  const p = sano(); p.dias.push({ id: 'mar', nombre: 'PULL' });
  const r = normalizarRutina(p);
  si(r.usable, 'un día roto no debería invalidar el plan entero');
  eq(r.est.dias[1].bloques, [], 'no normalizó a array');
  si(r.problemas.some(x => /PULL/.test(x)), 'no reportó el día');
});

t('bloque sin ejercicios queda con array vacío (no undefined)', () => {
  const p = sano(); p.dias[0].bloques.push({ titulo: 'B' });
  const r = normalizarRutina(p);
  eq(r.est.dias[0].bloques[1].ejercicios, [], 'dejó ejercicios undefined → .flatMap explota');
});

t('NINGÚN día con ejercicios → no usable', () => {
  const r = normalizarRutina({ dias: [{ id: 'a', bloques: [] }, { id: 'b', bloques: [{ ejercicios: [] }] }] });
  si(!r.usable, 'dio usable un plan sin un solo ejercicio');
});

t('descanso_segundos ausente, 0, negativo o basura → default', () => {
  for (const v of [undefined, 0, -30, null, 'noventa', NaN]) {
    const p = sano(); p.dias[0].bloques[0].ejercicios = [ej({ descanso_segundos: v })];
    const d = normalizarRutina(p).est.dias[0].bloques[0].ejercicios[0].descanso_segundos;
    si(Number.isFinite(d) && d > 0, `descanso quedó ${d} con entrada ${JSON.stringify(v)} → NaN:NaN y timer eterno`);
  }
});

t('series inválidas no producen NaN', () => {
  const p = sano(); p.dias[0].bloques[0].ejercicios = [ej({ series: undefined })];
  const s = normalizarRutina(p).est.dias[0].bloques[0].ejercicios[0].series;
  si(Number.isFinite(s) && s > 0, `series quedó ${s}`);
});

t('semanas_total ausente se asume 12 y se avisa', () => {
  const p = sano(); delete p.semanas_total;
  const r = normalizarRutina(p);
  eq(r.est.semanas_total, 12, 'no puso default');
  si(r.problemas.some(x => /semanas/i.test(x)), 'no avisó');
});

t('no muta la estructura original', () => {
  const p = sano(); const antes = JSON.stringify(p);
  normalizarRutina(p);
  eq(JSON.stringify(p), antes, 'mutó el objeto que le pasaron');
});

console.log('\nDieta');

const comida = (n = 'Desayuno', id = 'c1') => ({
  id, name: n, options: [{ name: 'A', foods: [{ name: 'Avena', qty: 90, kcal: 342, prot: 12, carb: 60, fat: 6 }] }],
});
const dietaSana = () => ({ macros_target: { kcal: 2800, prot: 180, carb: 300, fat: 80 }, comidas: [comida()] });

t('una dieta sana pasa intacta', () => {
  const r = normalizarDieta(dietaSana());
  si(r.usable, 'no usable');
  eq(r.problemas, [], 'inventó problemas');
  eq(r.est.macros_target.kcal, 2800, 'pisó el target');
});

t('sin macros_target se deriva de la opción A en vez de romper el arranque', () => {
  const d = dietaSana(); delete d.macros_target;
  const r = normalizarDieta(d);
  si(r.usable, 'no usable');
  eq(r.est.macros_target.kcal, 342, 'no derivó las kcal');
  si(r.problemas.some(x => /calor/i.test(x)), 'no avisó que lo calculó');
});

t('macros_target con kcal 0 o basura también se deriva', () => {
  for (const tg of [{ kcal: 0 }, { kcal: null }, { kcal: 'mucho' }, {}]) {
    const d = dietaSana(); d.macros_target = tg;
    si(normalizarDieta(d).est.macros_target.kcal > 0, `no derivó con ${JSON.stringify(tg)} → division por 0 en el anillo`);
  }
});

t('comida sin options se descarta y se reporta (no rompe renderMeal)', () => {
  const d = dietaSana();
  d.comidas.push({ id: 'c2', name: 'Almuerzo', options: [] });
  const r = normalizarDieta(d);
  eq(r.est.comidas.length, 1, 'dejó la comida rota adentro');
  si(r.problemas.some(x => /Almuerzo/.test(x)), 'no reportó cuál');
  si(r.usable, 'invalidó la dieta entera por una comida');
});

t('opción sin foods se descarta pero la comida sobrevive si le queda otra', () => {
  const d = dietaSana();
  d.comidas[0].options.push({ name: 'B', foods: [] });
  const r = normalizarDieta(d);
  eq(r.est.comidas[0].options.length, 1, 'dejó la opción vacía');
  si(r.usable, 'invalidó la comida');
});

t('tipos_dia:[] se trata como ausente (si no, getActivePlan devuelve la raíz)', () => {
  const d = dietaSana(); d.tipos_dia = [];
  const r = normalizarDieta(d);
  si(!('tipos_dia' in r.est), 'dejó tipos_dia vacío → buildMeals rompe');
  si(r.usable, 'no usable');
});

t('formato B con tipos_dia normaliza CADA tipo de día', () => {
  const d = { tipos_dia: [
    { id: 'entreno', nombre: 'Entreno', comidas: [comida()] },
    { id: 'descanso', nombre: 'Descanso', comidas: [comida('Cena', 'c9')] },
  ] };
  const r = normalizarDieta(d);
  si(r.usable, 'no usable');
  for (const p of r.est.tipos_dia) si(p.macros_target && p.macros_target.kcal > 0, `${p.nombre} sin target`);
});

t('sin ninguna comida válida → no usable (cae a SAMPLE_DIET, que ya no escribe)', () => {
  si(!normalizarDieta({ comidas: [] }).usable, 'dio usable una dieta vacía');
  si(!normalizarDieta({ comidas: [{ id: 'c1', options: [] }] }).usable, 'dio usable con la única comida rota');
  si(!normalizarDieta(null).usable, 'dio usable con null');
});

console.log('\nLa dieta de ejemplo no escribe en la base');

t('las 4 escrituras de comida cortan por _dietaEjemplo', () => {
  // Sin esto, marcar una comida de SAMPLE_DIET escribe filas reales contra ids
  // (c1, c2…) que no existen en ningún plan del cliente, y el coach termina
  // viendo adherencia de dieta de alguien que no tiene dieta.
  const guardas = (HTML.match(/_dietaEjemplo/g) || []).length;
  si(guardas >= 4, `solo ${guardas} referencias a _dietaEjemplo; deberían ser al menos 4 (declaración + 3 escrituras)`);
  si(/DATA\._isDemo \|\| DATA\._dietaEjemplo/.test(HTML), 'las guardas no combinan demo con dieta de ejemplo');
});

console.log(`\n${ok} pasaron, ${fail} fallaron\n`);
process.exit(fail ? 1 : 0);
