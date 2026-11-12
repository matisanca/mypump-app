#!/usr/bin/env node
// 2.3.1, cardio en la web: el slug de cinta gana sobre el tipo, la cinta va por tiempo con la palanca 2.3.0 prendida o no
// (también con una progresión de «10 min» que trae series) y se puede sustituir por otra máquina de cardio.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const CS = require('../public/js/carga-simple.js');
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };

// esCardio: el slug gana sobre el tipo; el nombre solo, no.
ok(CS.esCardio('Cinta', 'compuesto', ['walking_treadmill']), 'cinta con slug y tipo compuesto');
ok(CS.esCardio('Lo que sea', 'accesorio', [null, 'Elliptical_Trainer']), 'slug con mayúsculas');
ok(!CS.esCardio('Cinta', 'compuesto', []), 'el nombre solo respeta el tipo');
ok(CS.esCardio('Cinta', 'calentamiento', []), 'calentamiento por nombre');
ok(CS.esCardio('Bici', 'cardio', []), 'tipo cardio');
ok(!CS.esCardio('Press banca', 'compuesto', ['bench_press']), 'fuerza');

// Reps que son tiempo.
for (const r of ['10 min', '10min', '20\'', '30 s', '45 seg', '1 h', '15-20 min', '12 minutos', '8,5 min']) ok(CS.repsEsTiempo(r), `tiempo ${r}`);
for (const r of ['12', '8-10', '6 × 30 s / 30 s', 'AMRAP', null, '', '10 reps']) ok(!CS.repsEsTiempo(r), `no tiempo ${r}`);

// pauta: con progresión por tiempo, sin series aunque el plan las traiga; los intervalos siguen con las del plan.
const cinta = { nombre: 'Cinta', tipo: 'cardio', progresion: [{ semana: 1, series: 1, reps: '10 min' }, { semana: 2, series: 3, reps: '12 min' }] };
assert.deepEqual(CS.pauta(cinta, 2), { series: null, reps: '12 min' }); n++;
const intervalos = { nombre: 'Bici', tipo: 'cardio', progresion: [{ semana: 1, series: 6, reps: '6 × 30 s / 30 s' }] };
assert.deepEqual(CS.pauta(intervalos, 1), { series: 6, reps: '6 × 30 s / 30 s' }); n++;
const fuerza = { nombre: 'Plancha', tipo: 'core', progresion: [{ semana: 1, series: 3, reps: '30 s' }] };
assert.deepEqual(CS.pauta(fuerza, 1), { series: 3, reps: '30 s' }, 'la plancha por tiempo sigue con series'); n++;

// cliente.html: por tiempo sin depender de la palanca, y la métrica dice «Duración».
const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
const fn = (nombre) => { const m = html.match(new RegExp(`\\n(function ${nombre}\\([^)]*\\) \\{[\\s\\S]*?\\n\\})\\n`)); assert.ok(m, nombre); return m[1]; };
const ctx = { CS, DATA: { rutina: { semana_actual: 1 } } }; vm.createContext(ctx);
vm.runInContext([fn('getProgresionActual'), fn('_csCardioPorTiempo'), 'this.f = _csCardioPorTiempo;'].join('\n'), ctx);
ok(ctx.f({ nombre: 'Cinta', tipo: 'cardio', progresion: [] }), 'cinta sin progresión');
ok(ctx.f({ nombre: 'Cinta', tipo: 'compuesto', catalogo_slug: 'walking_treadmill', series: 3, reps: '10' }), 'cinta como compuesto con slug');
ok(ctx.f(cinta), 'cinta con progresión de minutos y series');
ok(!ctx.f(intervalos), 'intervalos: con series');
ok(!ctx.f({ nombre: 'Press', tipo: 'compuesto', series: 3, reps: '10' }), 'fuerza');
const linea = html.split('\n').find(l => l.includes('const _porTiempo ='));
ok(linea && !linea.includes('_csOn()'), 'la tarjeta va por tiempo sin la palanca');
ok(!html.includes('_csOn() && _csCardioPorTiempo'), 'ningún camino depende de la palanca para la cinta');
ok(html.includes("_metricasHtml(ex, _porTiempo ? Object.assign({}, prog, { series: null }) : prog)"), 'la métrica dice Duración');

// exGetSubs: el cardio ofrece cardio (antes, nada).
globalThis.window = { MyPump: {} };
require('../public/js/app.js');
const SW = globalThis.window.MyPump.exerciseSwap;
globalThis.window.MYPUMP_EJERCICIO_DB = [
  { slug_en: 'Walking_Treadmill', name_en: 'Walking, Treadmill', equipment: 'machine' },
  { slug_en: 'Bicycling_Stationary', name_en: 'Bicycling, Stationary', equipment: 'machine' },
  { slug_en: 'Elliptical_Trainer', name_en: 'Elliptical Trainer', equipment: 'machine' },
  { slug_en: 'Barbell_Bench_Press', name_en: 'Barbell Bench Press', equipment: 'barbell', patron_movimiento: 'empuje_horizontal' },
];
const subs = SW.cardioSubstitutes({ nombre: 'Cinta', catalogo_slug: 'Walking_Treadmill' });
assert.deepEqual(subs.map(s => s.name), ['Bicicleta fija', 'Elíptico'], 'sin la del plan, en el orden de la lista'); n++;
const sub = fn('exGetSubs');
ok(sub.includes('cardioSubstitutes(orig)') && sub.indexOf('cardioSubstitutes') < sub.indexOf("ex.tipo === 'cardio') return []"), 'exGetSubs ofrece cardio antes de cortar');
console.log(`✓ cardio en la web (${n} casos)`);
