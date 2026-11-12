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
// sinRIR (2.3.1): el texto libre del plan nunca dice RIR en pantalla. Mismos vectores que las apps.
const sr = V('sin_rir');
const prohibido = new RegExp(sr.prohibido, 'i');
assert.equal(sr.reales.length, 25, 'los 25 textos reales');
for (const c of [...sr.reales, ...sr.otros]) {
  const sale = E.sinRIR(c.entra);
  assert.equal(sale, c.sale, `sinRIR ${c.entra}`);
  assert.ok(!prohibido.test(sale), `queda RIR en ${sale}`);
  n++;
}
for (const t of sr.sinCambio) { assert.equal(E.sinRIR(t), t, `sin cambio ${t}`); n++; }
assert.equal(E.sinRIR(null), null);
// Reserva clínica (Mati: lumbar, cardiopatía, excepciones): si el rir de esa semana es mayor que 0, la nota va entera.
for (const r of [null, undefined, '', '0', 0, 'al fallo', 'Al fallo', 'RPE 8', '0-0']) assert.equal(E.conReserva(r), false, `sin reserva ${r}`);
for (const r of ['1-2', '2', 2, '2-3', '0-1', '1,5']) assert.equal(E.conReserva(r), true, `con reserva ${r}`);
for (const r of sr.reserva.conReserva) assert.equal(E.conReserva(r), true, `vector con reserva ${r}`);
for (const r of sr.reserva.sinReserva) assert.equal(E.conReserva(r), false, `vector sin reserva ${r}`);
for (const c of sr.reserva.casos) assert.equal(E.notaParaAlumno(c.entra, c.rir), c.sale, `vector reserva ${c.rir}`);
const notaClinica = 'Compuestos con RIR 2: cuidá la lumbar y dejá 2 repeticiones en reserva.';
assert.equal(E.notaParaAlumno(notaClinica, '2-3'), notaClinica, 'reserva clínica: la nota entera');
assert.equal(E.notaParaAlumno(notaClinica, '0'), 'Compuestos: cuidá la lumbar.', 'al fallo: sin RIR');
assert.equal(E.notaParaAlumno(notaClinica, null), 'Compuestos: cuidá la lumbar.', 'sin dato: sin RIR');
n += 18;
// La web dibuja la nota técnica filtrada y escapada.
const html = readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
assert.ok(html.includes('ReglasEntreno.notaParaAlumno(ex.notas_tecnica, prog.rir)'), 'cliente.html filtra notas_tecnica con el rir de la semana');
assert.ok(html.includes('ReglasEntreno.notaParaAlumno(n, _rirPlan)'), 'cliente.html filtra la nota de la preparación');
assert.ok(!/>\$\{ex\.notas_tecnica\}</.test(html), 'notas_tecnica no va cruda al HTML');
n++;
console.log(`✓ reglas de entreno iguales a la app (${n} casos)`);
