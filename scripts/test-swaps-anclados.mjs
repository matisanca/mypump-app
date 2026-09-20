// test-swaps-anclados.mjs — un swap de comida sigue al ALIMENTO, no al índice
//
// POR QUÉ EXISTE (19-sep-2026). mypump_publicar_cliente conserva el dieta_id
// al republicar, y la key del swap es posicional (comida, opción, índice). Si
// Mati agrega un alimento antes, cada swap cae sobre el que ahora ocupa esa
// posición: el sustituto tapa la corrección recién publicada y el alimento
// rechazado vuelve (la leche de Alejandro Romero, 28-ago). Ahora cada swap
// guarda en food_data._orig el alimento que reemplazó; si no coincide con lo
// que hay hoy en esa posición, no se aplica y se borra del backend. Los swaps
// viejos (sin _orig) se anclan al alimento actual la primera vez.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const HTML = fs.readFileSync(path.join(ROOT, 'public/cliente.html'), 'utf8');
let fallas = 0;
const t = (n, fn) => { try { fn(); console.log(`  ✓ ${n}`); } catch (e) { fallas++; console.log(`  ✗ ${n}\n      ${e.message}`); } };
const ext = (re) => { const m = HTML.match(re); if (!m) throw new Error('no encontré ' + re); return m[0]; };

const codigo = [
  ext(/function _huellaFood\(f\) \{[\s\S]*?\n\}\n/),
  ext(/function _swapAplicable\(swap, originalFood\) \{[\s\S]*?\n\}\n/),
  ext(/function getFoodSwap\(originalFood, comidaId, optIdx, foodIdx\) \{[\s\S]*?\n\}\n/),
  ext(/function getEffectiveFood\(f, comidaId, optIdx, foodIdx\) \{[\s\S]*?\n\}\n/),
  ext(/function _conAncla\(sub, original\) \{[\s\S]*?\n\}\n/),
  ext(/function _foodEnPosicion\(comidaId, optIdx, foodIdx\) \{[\s\S]*?\n\}\n/),
  ext(/function _anclarOSacarSwap\(mapa, key, fila\) \{[\s\S]*?\n\}\n/),
].join('\n');

function armar(dieta) {
  const cola = [];
  const fn = new Function('DIETA_ID', 'STATE', 'DIET', 'OUTBOX_ENABLED', 'TOKEN', 'DATA', 'Outbox',
    codigo + '\nreturn { _huellaFood, _swapAplicable, getFoodSwap, getEffectiveFood, _conAncla, _foodEnPosicion, _anclarOSacarSwap };');
  const STATE = { foodSwaps: {} };
  const api = fn('d1', STATE, dieta, true, 'tok', { _isDemo: false }, { enqueue: (kind, p, key) => cola.push({ kind, p, key }) });
  return { ...api, STATE, cola };
}
const food = (name, qty, unit = 'g') => ({ name, qty, unit, kcal: 100 });
const dietaV1 = { comidas: [{ id: 'c2', options: [{ name: 'A', foods: [food('Café', 200, 'ml'), food('Pan lactal', 60), food('Huevos', 3, 'unidad')] }] }] };
const dietaV2 = { comidas: [{ id: 'c2', options: [{ name: 'A', foods: [food('Yogur', 200), food('Café', 200, 'ml'), food('Pan lactal', 60), food('Huevos', 3, 'unidad')] }] }] };

console.log('\n1. el swap se ancla al alimento que reemplaza');
t('_conAncla guarda nombre, cantidad y unidad del original', () => {
  const a = armar(dietaV1);
  const sub = a._conAncla(food('Arroz', 80), food('Pan lactal', 60));
  if (!sub._orig || sub._orig.name !== 'Pan lactal' || sub._orig.qty !== 60 || sub._orig.unit !== 'g') throw new Error(JSON.stringify(sub._orig));
});
t('con la dieta igual, el swap se aplica', () => {
  const a = armar(dietaV1);
  a.STATE.foodSwaps['swap_d1_c2_0_1'] = { original: null, current: a._conAncla(food('Arroz', 80), food('Pan lactal', 60)) };
  if (a.getEffectiveFood(food('Pan lactal', 60), 'c2', 0, 1).name !== 'Arroz') throw new Error('no aplicó');
});
t('Mati agrega un yogur antes: el swap del pan NO tapa al café', () => {
  const a = armar(dietaV2);
  a.STATE.foodSwaps['swap_d1_c2_0_1'] = { original: null, current: a._conAncla(food('Arroz', 80), food('Pan lactal', 60)) };
  // índice 1 ahora es el Café
  if (a.getEffectiveFood(food('Café', 200, 'ml'), 'c2', 0, 1).name !== 'Café') throw new Error('el swap tapó al café');
});
t('Mati cambia 60 → 80 g del mismo pan: el swap (calculado para 60) no se aplica', () => {
  const a = armar(dietaV1);
  a.STATE.foodSwaps['swap_d1_c2_0_1'] = { original: null, current: a._conAncla(food('Arroz', 80), food('Pan lactal', 60)) };
  if (a.getEffectiveFood(food('Pan lactal', 80), 'c2', 0, 1).name !== 'Pan lactal') throw new Error('aplicó un swap de otra cantidad');
});
t('mayúsculas y espacios no rompen el ancla', () => {
  const a = armar(dietaV1);
  a.STATE.foodSwaps['swap_d1_c2_0_1'] = { original: null, current: a._conAncla(food('Arroz', 80), food('pan lactal ', 60)) };
  if (a.getEffectiveFood(food('Pan Lactal', 60), 'c2', 0, 1).name !== 'Arroz') throw new Error('no aplicó por mayúsculas');
});

console.log('\n2. hidratar desde el backend');
t('swap legado (sin _orig): se ancla al alimento actual y se re-sube', () => {
  const a = armar(dietaV1);
  const mapa = { 'swap_d1_c2_0_1': { original: null, current: food('Arroz', 80) } };
  a._anclarOSacarSwap(mapa, 'swap_d1_c2_0_1', { comida_id: 'c2', opt_idx: 0, food_idx: 1 });
  if (!mapa['swap_d1_c2_0_1'].current._orig || mapa['swap_d1_c2_0_1'].current._orig.name !== 'Pan lactal') throw new Error('no ancló');
  if (!a.cola.some(o => o.kind === 'swap' && o.p.food._orig)) throw new Error('no re-subió el ancla');
});
t('swap anclado que ya no coincide: se saca del mapa y se borra en el backend', () => {
  const a = armar(dietaV2);
  const mapa = { 'swap_d1_c2_0_1': { original: null, current: a._conAncla(food('Arroz', 80), food('Pan lactal', 60)) } };
  a._anclarOSacarSwap(mapa, 'swap_d1_c2_0_1', { comida_id: 'c2', opt_idx: 0, food_idx: 1 });
  if (mapa['swap_d1_c2_0_1']) throw new Error('quedó el swap fantasma');
  if (!a.cola.some(o => o.kind === 'swap_del' && o.key === 'swap_d1_c2_0_1')) throw new Error('no lo borró del backend');
});
t('swap anclado que sigue coincidiendo: intacto y sin tráfico', () => {
  const a = armar(dietaV1);
  const mapa = { 'swap_d1_c2_0_1': { original: null, current: a._conAncla(food('Arroz', 80), food('Pan lactal', 60)) } };
  a._anclarOSacarSwap(mapa, 'swap_d1_c2_0_1', { comida_id: 'c2', opt_idx: 0, food_idx: 1 });
  if (!mapa['swap_d1_c2_0_1'] || a.cola.length) throw new Error('tocó lo que estaba bien');
});
t('posición que ya no existe: no rompe', () => {
  const a = armar(dietaV1);
  const mapa = { 'swap_d1_c2_0_9': { original: null, current: food('Arroz', 80) } };
  a._anclarOSacarSwap(mapa, 'swap_d1_c2_0_9', { comida_id: 'c2', opt_idx: 0, food_idx: 9 });
  if (a.cola.length) throw new Error('mandó algo para una posición inexistente');
});

console.log('\n3. cableado');
t('confirmSwap y el custom food guardan el ancla y la mandan', () => {
  const i = HTML.indexOf('async function confirmSwap()');
  if (!HTML.slice(i, i + 1500).includes('_conAncla(sub, original)')) throw new Error('confirmSwap sin ancla');
  const j = HTML.indexOf('async function aplicarCustomFoodComoSwap(name)');
  if (!HTML.slice(j, j + 1500).includes('_conAncla(sub, orig)')) throw new Error('custom food sin ancla');
});
t('renderFood decide con el mismo criterio que getEffectiveFood', () => {
  const i = HTML.indexOf('function renderFood(originalFood, comidaId, optIdx, foodIdx)');
  if (!HTML.slice(i, i + 400).includes('getFoodSwap(originalFood, comidaId, optIdx, foodIdx)')) throw new Error('renderFood lee STATE.foodSwaps a pelo');
});
t('el hydrate ancla o saca cada swap remoto', () => {
  const i = HTML.indexOf('async function hydrateSwapsAndCustomFoodsFromBackend()');
  if (!HTML.slice(i, i + 5000).includes('_anclarOSacarSwap(newSwaps, key, s)')) throw new Error('hydrate no pasa por _anclarOSacarSwap');
});

console.log();
if (fallas) { console.log(`✗ ${fallas} fallo(s): los swaps vuelven a ser posicionales\n`); process.exit(1); }
console.log('✓ swaps anclados al alimento\n');
