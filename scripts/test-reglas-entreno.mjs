// Preparación, descanso elegido, RIR del plan y récord de la web: iguales a la app 2.0.3.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const E = require('../public/js/reglas-entreno.js');
const V = (f) => JSON.parse(readFileSync(new URL(`./vectores-app/${f}.json`, import.meta.url)));
let n = 0;

const prep = V('preparacion');
for (const c of prep.casos) {
  const plan = 'plan' in c ? E.aproximacionesDelPlan(c.plan) : null;
  const sale = E.preparacion(prep.dias[c.dia], c.indice, c.ejercicio, c.equipo, c.sinKg, c.kg, plan)
    .map(s => ({ tipo: s.tipo, numero: s.numero, reps: s.reps, kg: s.kg, barraSola: s.barraSola, opcional: s.opcional }));
  const esp = c.sale.map(s => ({ tipo: s.tipo, numero: s.numero, reps: s.reps, kg: s.kg, barraSola: s.barraSola, opcional: s.opcional }));
  assert.deepEqual(sale, esp, c.nombre);
  n++;
}
for (const c of prep.clasificacion.casos) {
  assert.equal(E.esPrincipal(c.nombre, c.tipo), c.principal, `principal ${c.nombre}`);
  assert.equal(E.sinPreparacion(c.nombre), c.sinPreparacion, `sin preparación ${c.nombre}`);
  n++;
}

const e = V('entreno_203');
assert.deepEqual(E.OPCIONES_DESCANSO, e.descanso.opciones);
for (const c of e.descanso.casos) {
  assert.equal(E.segundosDescanso(c.propio, c.plan), c.sale, `descanso ${JSON.stringify(c)}`);
  n++;
}
for (const c of e.rir.casos) {
  assert.equal(E.rirAGuardar(c.objetivo), c.guarda, `rir guarda ${c.objetivo}`);
  assert.equal(E.leyendaRir(c.objetivo), c.leyenda, `rir leyenda ${c.objetivo}`);
  n++;
}
for (const c of e.record.casos) {
  const r = E.evaluarRecord(c.serie, !!c.sinKg, c.verosimil !== false, c.anteriores, c.hoy || []);
  assert.equal(r ? r.texto : null, c.sale, c.nombre);
  n++;
}
console.log(`✓ reglas de entreno iguales a la app (${n} casos)`);
