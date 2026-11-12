#!/usr/bin/env node
// 2.3.1: los protectores (fármacos que indica Mati) van aparte de «Tu día» en «Tu guía» (reglas-guia.js) y en la pestaña
// Suplementación (_vistaSupl de cliente.html), sin compra y sin marcar. Mismos vectores que iOS y Android.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const RG = require('../public/js/reglas-guia.js');
const F = require('../public/js/feedback.js');
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/protectores.json', import.meta.url)));
const sinCampo = (s) => ({ ...s, items: s.items.map(({ protector, tipo, ...i }) => i) });
const momentos = (v) => v.momentos.map(m => ({ id: m.id, nombres: m.filas.map(f => f.nombre) }));
let n = 0;

// «Tu guía»
const g = RG.normalizarGuia({ suplementacion: V.suplementacion }).suplementacion;
const vg = RG.vistaSuplementacion(g);
assert.equal(RG.TITULO_PROTECTORES, V.titulo);
assert.deepEqual(momentos(vg), V.momentos, 'guía: momentos sin protectores');
assert.deepEqual(vg.protectores.map(p => ({ nombre: p.nombre, cantidad: p.cantidad, momento: p.momento, nota: p.nota, item: p.item })), V.protectores, 'guía: protectores');
assert.deepEqual(vg.sale.map(x => x.nombre), V.sale);
const vg0 = RG.vistaSuplementacion(RG.normalizarGuia({ suplementacion: sinCampo(V.suplementacion) }).suplementacion);
assert.deepEqual(vg0.protectores, [], 'guía sin el campo: sin protectores');
assert.deepEqual(momentos(vg0), V.sinCampo.momentos, 'guía sin el campo: como antes');
n += 6;

// Pestaña Suplementación (la función real de cliente.html).
const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
const fn = (nombre) => { const m = html.match(new RegExp(`\\n(function ${nombre}\\([^)]*\\) \\{[\\s\\S]*?\\n\\})\\n`)); assert.ok(m, nombre); return m[1]; };
const consts = html.match(/\nconst _SUPL_MOMENTOS = [\s\S]*?;\n/);
assert.ok(consts, '_SUPL_MOMENTOS');
const ctx = {}; vm.createContext(ctx);
vm.runInContext([consts[0], fn('_suplTxt'), fn('_suplMayus'), fn('_vistaSupl'), 'this._vistaSupl = _vistaSupl;'].join('\n'), ctx);
const vp = ctx._vistaSupl(V.suplementacion);
assert.deepEqual(JSON.parse(JSON.stringify(momentos(vp))), V.momentos, 'pestaña: momentos sin protectores');
assert.deepEqual(JSON.parse(JSON.stringify(vp.protectores)), V.protectores, 'pestaña: protectores');
const vp0 = ctx._vistaSupl(sinCampo(V.suplementacion));
assert.deepEqual(JSON.parse(JSON.stringify(vp0.protectores)), []);
assert.deepEqual(JSON.parse(JSON.stringify(momentos(vp0))), V.sinCampo.momentos, 'pestaña sin el campo: como antes');
assert.ok(html.includes('Protectores, indicados por Mati'), 'el bloque en la pestaña');
n += 5;

// «¿Ya lo tenés?» no ofrece marcar un protector, venga como venga.
const marcables = F.filas(V.suplementacion.items, {}).map(f => f.nombre);
for (const x of ['Telmisartán', 'Ezetimibe', 'Cardioaspirina']) assert.ok(!marcables.includes(x), `no se marca ${x}`);
n++;
console.log(`✓ protectores aparte (${n} casos)`);
