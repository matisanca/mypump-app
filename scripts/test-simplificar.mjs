// Simplificar (OK de Mati del 11/11, palanca web_230): las reglas puras nuevas y lo cableado en cliente.html.
// La prueba en el navegador, contra un doble, está en nativa-evidencia/mi-salud/h/web/simplificar.mjs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const M = require('../public/js/mi-salud.js');
const G = require('../public/js/reglas-guia.js').R;
const D = require('../public/js/donde-entreno.js');
const leer = (f) => fs.readFileSync(new URL(`../public/${f}`, import.meta.url), 'utf8');
let n = 0;
const caso = (nombre, fn) => { try { fn(); n++; } catch (e) { console.error(`✗ ${nombre}`); throw e; } };
const DIA = 86400000;

// ── 1. «Mi salud» en Entreno ──
const todo = { estudios: true, proximoControl: true, tarjetaEstudios: { titulo: 'Tenés una orden nueva' }, controlCerca: true,
  presion: true, tarjetaPresion: { estado: 'toma', faltan: 2 }, recuperacion: true };
caso('masCosas: nada con una sola; «Y 1 cosa más»; «Y N cosas más»', () => {
  assert.equal(M.masCosas(0), null);
  assert.equal(M.masCosas(1), null);
  assert.equal(M.masCosas(2), 'Y 1 cosa más');
  assert.equal(M.masCosas(3), 'Y 2 cosas más');
});
caso('tarjetaInicio: solo con algo para hacer y con lo primero pendiente', () => {
  assert.equal(M.tarjetaInicio({ recuperacion: true }), null, 'sin nada pendiente no hay tarjeta en Entreno');
  assert.equal(M.tarjetaInicio({ presion: true, tarjetaPresion: { estado: 'hoyListo' }, recuperacion: true }), null, '«La de hoy ya está» no cuenta');
  assert.deepEqual(M.tarjetaInicio(todo), { linea: 'Tenés una orden nueva', numero: 3, primero: 'estudios', mas: 'Y 2 cosas más' });
  const c = M.tarjetaInicio({ ...todo, tarjetaEstudios: null });
  assert.equal(c.primero, 'control'); assert.equal(c.linea, M.T.control); assert.equal(c.mas, 'Y 1 cosa más');
  const p = M.tarjetaInicio({ presion: true, tarjetaPresion: { estado: 'repetir' }, recuperacion: true });
  assert.deepEqual(p, { linea: M.T.presionRepetir, numero: 1, primero: 'presion', mas: null });
});

// ── 3. «Tu inicio con Mati»: la fila de la guía terminada ──
caso('completa: todo visto y sin tanda nueva', () => {
  assert.equal(G.completa({ total: 5, vistos: 5 }, null), true);
  assert.equal(G.completa({ total: 5, vistos: 4 }, null), false);
  assert.equal(G.completa({ total: 5, vistos: 5 }, { total: 1, vistos: 0 }), false, 'un video nuevo de Mati la vuelve a abrir');
  assert.equal(G.completa({ total: 0, vistos: 0 }, null), false);
});
caso('filaInicioVigente: 7 días desde que se terminó; sin fecha, sigue', () => {
  const ahora = new Date('2026-11-11T12:00:00-03:00');
  assert.equal(G.DIAS_FILA_COMPLETA, 7);
  assert.equal(G.filaInicioVigente(null, ahora), true);
  assert.equal(G.filaInicioVigente(new Date(ahora - 6.9 * DIA), ahora), true);
  assert.equal(G.filaInicioVigente(new Date(ahora - 7 * DIA), ahora), false);
  assert.equal(G.filaInicioVigente(new Date('x'), ahora), true, 'una fecha rota no oculta nada');
});

// ── 4. «Mi gimnasio y mi técnica» ──
caso('titulo y bajada según lo que haya', () => {
  assert.equal(D.titulo(true, true), 'Mi gimnasio y mi técnica');
  assert.equal(D.titulo(true, false), 'Mi gimnasio');
  assert.equal(D.titulo(false, true), 'Mi técnica');
  assert.equal(D.titulo(false, false), null);
  assert.equal(D.bajada(false, false), null);
  assert.equal(D.bajada(false, true), 'Tus videos y lo que te respondió Mati');
});
caso('respuestaReciente: la publicada más nueva de los últimos 7 días', () => {
  const ahora = new Date('2026-11-11T12:00:00Z');
  const iso = (d) => new Date(ahora - d * DIA).toISOString();
  const env = [
    { id: 'a', estado: 'publicado', devolucion: {}, publicadoEn: iso(3) },
    { id: 'b', estado: 'publicado', devolucion: {}, publicadoEn: iso(1) },
    { id: 'c', estado: 'enviado', devolucion: null, publicadoEn: null },
    { id: 'd', estado: 'publicado', devolucion: {}, publicadoEn: iso(8) },
    { id: 'e', estado: 'publicado', devolucion: null, publicadoEn: iso(0.5) },
    { id: 'f', estado: 'publicado', devolucion: {}, publicadoEn: 'no-es-fecha' },
  ];
  assert.equal(D.respuestaReciente(env, ahora).id, 'b');
  assert.equal(D.respuestaReciente([env[3]], ahora), null, 'de hace más de 7 días, no');
  assert.equal(D.respuestaReciente([], ahora), null);
  assert.equal(D.respuestaReciente(null, ahora), null);
});

// ── Lo cableado en cliente.html y los módulos ──
const html = leer('cliente.html');
caso('escena nueva y scripts cargados', () => {
  assert.match(html, /id="scene-dondeentreno"/);
  assert.match(html, /<script src="\/js\/donde-entreno\.js"><\/script>/);
  assert.match(leer('sw.js'), /'\/js\/donde-entreno\.js'/);
});
caso('todo va detrás de web_230', () => {
  for (const f of ['function _deOn() { return !!(window.DondeEntreno && web230()); }', 'function _miProgresoOn() { return web230(); }',
    "root.innerHTML = web230() ? _misDatos230Html(", "${web230() ? '<div id=\"revision-novedades-host\" hidden></div>' : ''}"]) {
    assert.ok(html.includes(f), f);
  }
  assert.match(leer('js/guia.js'), /if \(w230\(\)\) return htmlInicioConMati\(m\);/);
  assert.match(leer('js/gimnasio-ui.js'), /casaEnHub/);
});
caso('Mis datos 2.3.0: sin Novedades, Mi gimnasio, Mi técnica ni Mis fotos de inicio', () => {
  const i = html.indexOf('function _misDatos230Html(');
  const cuerpo = html.slice(i, html.indexOf('\n}\n', i));
  for (const id of ['mdNovedades', 'mdGimnasio', 'mdTecnica', 'mdFotosInicio']) assert.ok(!cuerpo.includes(id), id);
  for (const t of ['Mi plan', 'Ajustes', 'Privacidad', 'mdMiSalud', 'mdGuia', 'mdDocumentos', 'mis-datos-recorrido', 'data-fuentes="myday"', 'eliminar-datos.html']) assert.ok(cuerpo.includes(t), t);
});

console.log(`✓ simplificar: ${n} casos`);
