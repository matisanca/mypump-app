// «Novedades de tu plan»: los mismos casos que NovedadesPlanTests (iOS) y NovedadesPlanTest (Android).
// scripts/fixtures/novedades-casos.json es copia de apps/shared/fixtures/novedades/casos.json (rama nativa).
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const N = require('../public/js/novedades-plan.js');
let n = 0;
const eq = (a, b, m) => { assert.deepEqual(a, b, m); n++; };

const casos = JSON.parse(readFileSync(new URL('./fixtures/novedades-casos.json', import.meta.url), 'utf8'));
assert.ok(casos.length >= 30);
for (const c of casos) eq(N.calcular(c.antes, c.despues), c.esperado ?? null, c.nombre);

// Reglas de texto: sin dos puntos ni guiones, nunca RIR, fallo, coach ni entrenador, nunca una dosis, a lo sumo 4 líneas.
for (const c of casos) {
  const r = N.calcular(c.antes, c.despues);
  if (!r) continue;
  const textos = [r.titular, r.resumen, ...r.partes.flatMap((p) => [p.titular, ...p.lineas])];
  for (const t of textos) {
    assert.ok(!/:| - |—|–/.test(t), t);
    assert.ok(!/rir|fallo|coach|entrenador/.test(t.toLowerCase()), t);
  }
  const dosis = ['antes', 'despues'].flatMap((k) => {
    const s = c[k].suplementacion && c[k].suplementacion.suplementacion;
    return s && Array.isArray(s.items) ? s.items.flatMap((it) => [it.cantidad, it.antes, ...(it.tomas || []).map((t) => t.cantidad)]) : [];
  }).filter((x) => typeof x === 'string' && x);
  for (const p of r.partes) {
    assert.ok(p.lineas.length <= N.MAX_LINEAS);
    for (const l of p.lineas) for (const d of dosis) assert.ok(!l.includes(d), `dosis en ${l}`);
  }
  n++;
}

eq(N.formatoKcal(980), '980', 'kcal');
eq(N.formatoKcal(12345.6), '12.346', 'kcal miles');
eq(N.formatoCantidad(1, 'u'), '1 unidad', 'unidad');
eq(N.formatoCantidad(1.25, 'g'), '1,3 g', 'decimal');
eq(N.formatoCantidad(250, 'ml'), '250 ml', 'ml');
eq(N.formatoCantidad(30, null), '30 g', 'sin unidad');
eq(N.repsNormal(' 8–10 '), '8 a 10', 'reps');
eq(N.formatoCantidad(1.04, 'u'), '1 unidad', 'singular redondeado');
eq(N.formatoPauta(3, '10-12 al fallo'), '3 series', 'repes con texto prohibido');
eq(N.formatoPauta(3, 'AMRAP'), '3 series, AMRAP', 'repes con texto');
eq(N.clave('Pre\u0301nsa'), N.clave('Prénsa'), 'NFC');

// ---- El modelo: la base y la lista en el navegador, por cuenta.
const almacen = () => { const m = new Map(); return { m, leer: (k) => m.has(k) ? m.get(k) : null, guardar: (k, v) => m.set(k, v) }; };
const caso = (nombre) => casos.find((c) => c.nombre === nombre);
const conRutina = casos.find((c) => c.antes.rutina && c.despues.rutina && c.esperado && c.esperado.partes.length === 1
  && c.esperado.partes[0].area === 'rutina' && !c.esperado.partes[0].grande);
assert.ok(conRutina, 'hay un caso de rutina chico');
let ahora = 1_000_000;
{
  const a = almacen();
  const m = N.crearModelo('tok', a, () => ahora);
  // Primera vez, sin base ni semilla: se guarda callado.
  eq(m.observar({ rutina: conRutina.antes.rutina }), null, 'sin base no hay novedad');
  eq(m.lista.length, 0, 'lista vacía');
  // Llega otra versión: hay novedad, pendiente y reciente.
  const nov = m.observar({ rutina: conRutina.despues.rutina });
  eq([nov.titular, nov.resumen, nov.vista], [conRutina.esperado.titular, conRutina.esperado.resumen, false], 'novedad');
  eq(m.pendiente.id, nov.id, 'pendiente');
  eq(m.reciente.id, nov.id, 'reciente');
  // La misma versión otra vez: nada.
  eq(m.observar({ rutina: conRutina.despues.rutina }), null, 'misma versión');
  // Lo que no llegó no se compara ni pisa la base.
  eq(m.observar({}), null, 'no llegó');
  m.marcarVista(nov.id);
  eq(m.pendiente, null, 'vista');
  // Persiste: otro modelo de la misma cuenta la ve, otra cuenta no.
  eq(N.crearModelo('tok', a, () => ahora).lista[0].vista, true, 'persiste');
  eq(N.crearModelo('otro', a, () => ahora).lista.length, 0, 'por cuenta');
  ahora += N.DIAS_TARJETA * 86400000;
  eq(N.crearModelo('tok', a, () => ahora).reciente, null, 'la tarjeta vence');
}
{
  // Con semilla (lo que había en el navegador): la primera carga ya avisa.
  const m = N.crearModelo('tok', almacen(), () => ahora);
  const nov = m.observar({ rutina: conRutina.despues.rutina }, { rutina: conRutina.antes.rutina });
  eq(nov && nov.titular, conRutina.esperado.titular, 'semilla');
}
{
  // Suplementación sin ítems con nombre = no hay; la primera vez que llega, «te armó».
  const s = casos.find((c) => c.despues.suplementacion && c.esperado && c.esperado.partes.some((p) => p.titular === 'Mati te armó tu suplementación'));
  if (s) {
    const m = N.crearModelo('tok', almacen(), () => ahora);
    m.observar({ suplementacion: { suplementacion: { items: [] } } });
    const nov = m.observar({ suplementacion: s.despues.suplementacion });
    eq(nov && nov.partes[0].titular, 'Mati te armó tu suplementación', 'supl primera vez');
  }
}
{
  // Tope de 12.
  const a = almacen();
  const m = N.crearModelo('tok', a, () => ahora);
  m.observar({ rutina: conRutina.antes.rutina });
  for (let i = 0; i < 15; i++) m.observar({ rutina: i % 2 ? conRutina.antes.rutina : conRutina.despues.rutina });
  eq(m.lista.length, N.MAXIMO, 'tope');
  eq(m.lista.filter((x) => !x.vista).length, 1, 'solo la última sin ver');
}
void caso;
console.log(`novedades-plan: ${n} ok (${casos.length} casos compartidos)`);
