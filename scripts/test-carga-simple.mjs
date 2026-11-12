// La carga simple de la web contra los vectores de la app 2.3.0 (los mismos del kit y de Android).
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const C = require('../public/js/carga-simple.js');
const V = JSON.parse(readFileSync(new URL('./vectores-app/carga_simple.json', import.meta.url)));
let n = 0;

const ej = (p, nombre = 'Press banca con barra', tipo = 'compuesto') => ({ id: 'x', nombre, tipo, progresion: p });
const texto = (a) => (a.tipo === 'sugerido' || a.tipo === 'aceptado') ? `${a.tipo}:${a.desde}:${a.hasta}` : a.tipo;

for (const c of V.corresponde) { assert.equal(C.corresponde(ej(c.progresion, undefined, c.tipo || 'compuesto'), c.semana, c.mensaje), c.espera, c.caso); n++; }
for (const h of V.hasta) { assert.equal(C.hasta(h.desde, h.equipo), h.espera ?? null, `hasta ${h.desde} ${h.equipo}`); n++; }
for (const m of V.mover) { assert.equal(C.mover(m.desde, m.pasos, m.equipo), m.espera, `mover ${m.desde} ${m.pasos} ${m.equipo}`); n++; }
for (const m of V.moda) { assert.equal(C.moda(m.kilos), m.espera ?? null, `moda ${m.kilos}`); n++; }
for (const g of V.guardia) {
  const s = new C.GuardiaOK();
  if (g.desde != null) s.levantar(1, g.desde);
  assert.equal(s.esDobleToque(g.serie, g.ahora), g.espera.doble, g.caso);
  assert.equal(s.esSegundoToque(g.serie, g.ahora), g.espera.segundo, g.caso);
  n++;
}
for (const e of V.escenarios) {
  const s = new C.Carga(ej(e.progresion, e.nombre || undefined), e.semana,
    { ultimaVez: e.ultimaVez, equipo: e.equipo, sinKg: e.nombre === 'Lagartijas' });
  for (const p of e.pasos) {
    switch (p.accion) {
      case 'moverCarga': s.moverCarga(p.valor); break;
      case 'fijarCarga': s.fijarCarga(p.valor ?? null); break;
      case 'aceptar': s.aceptarAumento(); break;
      case 'descartar': s.descartarAumento(); break;
      case 'ajustarReps': s.ajustarReps(p.i, p.valor); break;
      case 'mismoPeso': s.usarMismoPeso(p.valor); break;
      case 'mirar':
        if (p.espera?.aumento != null) assert.equal(texto(s.aumento), p.espera.aumento, e.caso);
        if (p.espera?.carga != null) assert.equal(s.carga, p.espera.carga, e.caso);
        break;
      case 'ok': case 'okInsistir': {
        const r = s.evaluarOK(p.i, p.ahora, p.accion === 'okInsistir');
        assert.equal(r.res, p.espera?.res, `${e.caso}: ${JSON.stringify(r)}`);
        if (r.res === 'lista') {
          assert.equal(r.reps, p.espera.reps, e.caso);
          assert.equal(r.kg, p.espera.kg ?? null, e.caso);
          Object.assign(s.series[p.i], { reps: r.reps, kg: r.kg, confirmada: true });
          s.anotarOK(p.ahora);
        }
        break;
      }
      default: assert.fail(p.accion);
    }
    n++;
  }
  const f = e.final;
  if (f) {
    if (f.carga != null) assert.equal(s.carga, f.carga, e.caso);
    if (f.aumento != null) assert.equal(texto(s.aumento), f.aumento, e.caso);
    if (f.reps) assert.deepEqual(s.series.map((_, i) => s.reps(i)), f.reps, e.caso);
    if (f.kg) assert.deepEqual(s.series.map(x => x.kg), f.kg, e.caso);
    if (f.confirmadas != null) assert.equal(s.confirmadas, f.confirmadas, e.caso);
    if (f.hechasConOtraCarga != null) assert.equal(s.hechasConOtraCarga, f.hechasConOtraCarga, e.caso);
    n++;
  }
}

// Lo que se guarda en el navegador vuelve igual (recargar la pestaña no cambia nada).
{
  const e = ej([{ semana: 1, series: 4, reps: '10' }, { semana: 2, series: 4, reps: '8' }]);
  const a = new C.Carga(e, 2, { ultimaVez: [{ reps: 10, kg: 80 }, { reps: 10, kg: 80 }], equipo: 'barra' });
  assert.equal(texto(a.aumento), 'sugerido:80:82.5');
  a.aceptarAumento();
  a.ajustarReps(0, 1);
  const g = JSON.parse(JSON.stringify(a.estado));
  const b = new C.Carga(e, 2, { ultimaVez: [{ reps: 10, kg: 82.5 }], equipo: 'barra', estado: g });
  assert.equal(b.carga, 82.5);
  assert.equal(b.cargaUltimaVez, 80);
  assert.equal(texto(b.aumento), 'aceptado:80:82.5');
  assert.equal(b.reps(0), a.reps(0));
  n++;
}

// Con un plan que baja las reps, la base es el plan, no la vez pasada.
{
  const e = ej([{ semana: 1, series: 3, reps: '12' }, { semana: 2, series: 3, reps: '8' }]);
  const a = new C.Carga(e, 2, { ultimaVez: [{ reps: 12, kg: 60 }], equipo: 'barra' });
  assert.deepEqual(a.base(0), { reps: 8, origen: 'plan' });
  n++;
}

// La vez pasada: solo antes de hoy, una fila por serie, la corrección manda y la variante filtra.
{
  const dia = (iso) => iso.slice(0, 10);
  const h = [
    { registrado_en: '2026-11-10T10:00:00', serie_numero: 1, reps_realizadas: 99, peso_kg: 99, notas: null },
    { registrado_en: '2026-11-08T10:05:00', serie_numero: 1, reps_realizadas: 11, peso_kg: 80, notas: 'Soga' },
    { registrado_en: '2026-11-08T10:00:00', serie_numero: 1, reps_realizadas: 10, peso_kg: 80, notas: 'Soga' },
    { registrado_en: '2026-11-08T10:01:00', serie_numero: 2, reps_realizadas: 9, peso_kg: 75, notas: 'Soga' },
    { registrado_en: '2026-11-08T10:02:00', serie_numero: 3, reps_realizadas: 8, peso_kg: 70, notas: 'Barra' },
    { registrado_en: '2026-11-01T10:00:00', serie_numero: 1, reps_realizadas: 5, peso_kg: 50, notas: null },
  ];
  assert.deepEqual(C.ultimaSesion(h, 'Soga', false, '2026-11-10', dia), [{ reps: 11, kg: 80 }, { reps: 9, kg: 75 }]);
  assert.deepEqual(C.ultimaSesion(h, 'Barra', true, '2026-11-10', dia), [{ reps: 8, kg: 70 }]);
  assert.deepEqual(C.ultimaSesion(h, 'Otra', false, '2026-11-02', dia), []);
  assert.deepEqual(C.ultimaSesion(h, 'Otra', true, '2026-11-02', dia), [{ reps: 5, kg: 50 }]);
  n++;
}

console.log(`ok test-carga-simple: ${n} verificaciones`);
