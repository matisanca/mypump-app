// Los ajustes de comidas y los alimentos agregados de la web dan lo mismo que en las apps nativas.
// Vectores: copia de apps/shared/vectores (rama nativa-202), los que generan los tests de iOS y corre Android.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const A = require('../public/js/ajustes-dieta.js');
const V = (f) => JSON.parse(readFileSync(new URL(`./vectores-app/${f}.json`, import.meta.url)));
let n = 0;
const nul = (xs) => xs.map(v => (v === undefined ? null : v));
const casi = (a, b, msg) => { assert.ok(Math.abs(a - b) < 1e-6, `${msg}: ${a} ≠ ${b}`); };
const marcasDe = (filas) => Object.fromEntries((filas || []).map(f => [f.comida_id,
  { opcion: f.opcion_elegida, estado: f.estado, foodsExcluidos: f.foods_excluidos || [] }]));

// 1. El día con ajustes (AjustePorciones.dia)
for (const caso of V('ajuste_porciones').casos) {
  const aj = A.leerAjustes(caso.ajustes);
  const r = A.dia(caso.comidas, aj);
  for (const [id, e] of Object.entries(caso.esperado)) {
    if (id === '_sinCompensar') {
      const u = caso.comidas[caso.comidas.length - 1];
      casi(r[u.id].noAbsorbido, e, `${caso.nombre} sinCompensar`);
      continue;
    }
    const x = r[id], m = `${caso.nombre} / ${id}`;
    assert.deepEqual(nul(x.alimentos.map(a => a.qty)), e.qty, `${m} qty`);
    assert.deepEqual(nul(x.alimentos.map(a => a.kcal)), e.kcal, `${m} kcal`);
    if (e.prot) assert.deepEqual(nul(x.alimentos.map(a => a.prot)), e.prot, `${m} prot`);
    if (e.carb) assert.deepEqual(nul(x.alimentos.map(a => a.carb)), e.carb, `${m} carb`);
    if (e.fat) assert.deepEqual(nul(x.alimentos.map(a => a.fat)), e.fat, `${m} fat`);
    casi(x.kcal, e.kcalDia, `${m} kcalDia`);
    casi(x.kcalPlan, e.kcalPlan, `${m} kcalPlan`);
    casi(x.propio, e.propio, `${m} propio`);
    casi(x.compensacion, e.compensacion, `${m} compensacion`);
    casi(x.noAbsorbido, e.noAbsorbido, `${m} noAbsorbido`);
    if (e.cambiados) assert.deepEqual([...x.cambiados].sort((a, b) => a - b), e.cambiados, `${m} cambiados`);
    if (e.compensaDe) assert.deepEqual(x.compensaDe, e.compensaDe, `${m} compensaDe`);
    if ('omitida' in e) assert.equal(x.omitida, e.omitida, `${m} omitida`);
    n++;
  }
}

// 2. Agregados
const ag = V('agregados_comida');
for (const c of ag.agregados) {
  const a = A.agregado(c.candidato, c.cantidad, c.medida, 42);
  const esp = c.esperado.agregados[c.esperado.agregados.length - 1];
  for (const k of Object.keys(esp)) {
    if (k === '_ts') continue;
    assert.deepEqual(a[k], esp[k], `agregado ${c.candidato.nombre} ${k}`);
  }
  n++;
}
for (const c of ag.medidas) {
  assert.deepEqual(A.medidas(c.candidato), c.medidas, `medidas ${c.candidato.nombre}`);
  assert.deepEqual(A.inicial(c.candidato), c.inicial, `inicial ${c.candidato.nombre}`);
  n++;
}
for (const c of ag.pasos) {
  assert.equal(A.subirAgregado(c.cantidad, c.medida), c.subir, `subir ${c.cantidad} ${c.medida.nombre}`);
  assert.equal(A.bajarAgregado(c.cantidad, c.medida), c.bajar, `bajar ${c.cantidad} ${c.medida.nombre}`);
  assert.equal(A.acotarAgregado(c.cantidad, c.medida), c.acotar, `acotar ${c.cantidad} ${c.medida.nombre}`);
  n++;
}
for (const c of ag.tildes) {
  assert.deepEqual(A.excluidosTrasBorrar(c.excluidos, c.n, c.j), c.esperado, 'tildes');
  n++;
}
for (const c of ag.dia) {
  const r = A.dia(c.comidas, A.leerAjustes(c.ajustes));
  for (const [id, e] of Object.entries(c.esperado)) {
    if (id === '_sinCompensar') continue;
    assert.deepEqual(nul(r[id].alimentos.map(a => a.qty)), e.qty, `dia agregados ${id} qty`);
    casi(r[id].kcal, e.kcalDia, `dia agregados ${id} kcal`);
    casi(r[id].propio, e.propio, `dia agregados ${id} propio`);
    assert.equal(r[id].ajustada, e.ajustada, `dia agregados ${id} ajustada`);
    assert.deepEqual(r[id].agregados.map(a => ({ carb: a.carb, fat: a.fat, kcal: a.kcal, prot: a.prot })), e.agregados);
    n++;
  }
}

// 3. Lo comido en el día (ConsumoDelDia.calcular)
const consumos = [...ag.consumo, ...V('consumo_dia_ajustes').casos];
for (const c of consumos) {
  const t = A.consumo(c.comidas, marcasDe(c.marcas), c.libres || [], A.leerAjustes(c.ajustes || {}), c.vistas || {});
  const e = c.esperado;
  for (const k of ['kcal', 'prot', 'carb', 'fat']) casi(t[k], e[k], `${c.nombre} ${k}`);
  for (const k of ['comidas', 'hechas', 'salteadas']) assert.equal(t[k], e[k], `${c.nombre} ${k}`);
  n++;
}

// 4. Lo que se guarda: sin agregados la clave no va; lo roto se descarta con los mismos topes.
assert.ok(!('agregados' in A.serializarAjuste(A.nuevoAjuste())));
assert.deepEqual(A.leerAjuste({ deltaKcal: 99999, opcion: 300, compensar: 'x' }),
  { deltaKcal: 0, compensar: true, omitida: false, opcion: 0, cantidades: {}, anclas: {}, agregados: [] });
n++;

// 5. El tope de tamaño: la cota del jsonb nunca da menos que lo que midió la base (ni más del 15 %).
const jb = V('agregados_jsonb_medido');
for (const c of jb.casos) {
  const cota = A.bytesJsonb(A.leerAjustes(c.ajustes));
  assert.ok(cota >= c.jsonb && cota <= c.jsonb * 1.15, `${c.caso}: ${cota} contra ${c.jsonb}`);
  n++;
}
for (const x of jb.numeros) {
  const cota = 4 + A.bytesValor([Number(x.texto)]);
  assert.ok(cota >= x.jsonb && cota <= x.jsonb + 3, `${x.texto}: ${cota} contra ${x.jsonb}`);
  n++;
}
assert.equal(A.gruposNumeric(String(99.89999999999999)).grupos, 5);
assert.deepEqual(A.gruposNumeric('1e-7'), { grupos: 1, largo: false });
assert.ok(A.gruposNumeric('5e-324').largo);
assert.equal(A.gruposNumeric('0').grupos, 0);
n++;

console.log(`✓ ajustes de dieta iguales a la app (${n} casos)`);
