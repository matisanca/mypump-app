#!/usr/bin/env node
// 2.3.1: «¿Cómo se lee?» de Dieta con los mismos textos que iOS y Android (apps/shared/vectores/como_se_lee.json).
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
globalThis.window = { MyPump: {} };
require('../public/js/app.js');
const C = globalThis.window.MyPump.comoSeLee;
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/como_se_lee.json', import.meta.url)));
assert.equal(C.BOTON, V.boton);
assert.equal(C.TITULO, V.titulo);
assert.deepEqual(C.PASOS, V.pasos);
assert.equal(C.VER_VIDEO, V.verVideo);
assert.equal(C.CERRAR, V.cerrar);
assert.equal(C.VIDEO, V.video);
for (const p of C.PASOS) { assert.doesNotMatch(p, /rir/i); assert.doesNotMatch(p, /entrenador/); }
assert.equal(C.urlVideo(), null);
assert.equal(C.urlVideo('http://x.com/v'), null);
assert.equal(C.urlVideo('javascript:alert(1)'), null);
assert.equal(C.urlVideo('https://x.com/v"onload="x'), null);
assert.equal(C.urlVideo(' https://x.com/v '), 'https://x.com/v');
const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
assert.match(html, /data-como-se-lee/);
assert.match(html, /function abrirComoSeLee\(\)/);
console.log('test-como-se-lee: OK');
