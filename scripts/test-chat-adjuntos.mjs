#!/usr/bin/env node
/* =============================================================
 * test-chat-adjuntos.mjs — reglas y cola de fotos y audios del chat contra un doble de mini-vision, con el almacén en
 * memoria. La grabación, IndexedDB real y la pantalla se prueban en el navegador.
 * USO:  node scripts/test-chat-adjuntos.mjs
 * ============================================================= */
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const CA = require('../public/js/chat-adjuntos.js');
const { R, T, ModeloChatAdjuntos, almacenMemoria } = CA;

const TOK = 'token-de-prueba-0123456789';
let ok = 0;
async function caso(n, f) { try { await f(); ok++; } catch (e) { console.error('MAL', n, '\n', e.stack || e); process.exitCode = 1; } }

const jpeg = (n = 2000) => { const b = new Uint8Array(n); b.set([0xff, 0xd8, 0xff, 0xe0]); return b; };
const m4a = (n = 2000) => { const b = new Uint8Array(n); b.set([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]); return b; };
let sec = 0;
const ids = () => `0000000${sec}-0000-4000-8000-00000000000${sec++ % 10}`.slice(-36).padStart(36, '0');

function doble(ini = {}) {
  const d = { habilitado: true, sinRed: false, respuestas: [], subidas: [], firmas: [], programados: [], ...ini };
  d.rpc = async (fn) => {
    if (d.sinRed) return { ok: false, status: 0, codigo: 'NETWORK', clase: 'red' };
    if (d.sinFuncion) return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    assert.equal(fn, 'mypump_chat_adjuntos_estado');
    return { ok: true, data: d.habilitado ? { habilitado: true, audio_max_s: 120 } : { habilitado: false } };
  };
  d.fetch = async (url, op) => {
    if (url.endsWith('/chat/urls')) {
      const b = JSON.parse(op.body);
      d.firmas.push(b.ids);
      if (d.sinRed) throw new Error('red');
      return { ok: true, status: 200, json: async () => ({ ok: true, adjuntos: b.ids.map((id) => ({ id, tipo: 'foto', mime: 'image/jpeg', url: `https://x.test/${id}` })) }) };
    }
    assert.ok(url.endsWith('/chat/adjunto'));
    d.subidas.push({ headers: op.headers, largo: op.body.length });
    if (d.sinRed) throw new Error('red');
    const [status, cuerpo] = d.respuestas.length ? d.respuestas.shift() : [200, { ok: true, comentario_id: 'c1', created_at: '2026-11-10T12:00:00Z' }];
    return { ok: status < 300, status, json: async () => cuerpo };
  };
  d.programar = (fn, ms) => { const p = { fn, ms, vivo: true }; d.programados.push(p); return () => { p.vivo = false; }; };
  return d;
}
async function prendido(d, extra = {}) {
  const corte = d.sinRed;
  d.sinRed = false;
  const m = modelo(d, extra);
  await m.consultar(true);
  d.sinRed = corte;
  return m;
}
function modelo(d, extra = {}) {
  sec = 0;
  return new ModeloChatAdjuntos({ token: TOK, visionUrl: 'https://vision.test/', rpc: d.rpc, fetch: d.fetch, programar: d.programar, nuevoId: () => ids(), ...extra });
}
const espera = () => new Promise((r) => setTimeout(r, 0));
async function quieto(m) { for (let i = 0; i < 20; i++) { await espera(); if (!m.drenando) return; } }

await caso('reglas: mapeo de mini-vision', () => {
  assert.equal(CA.subida(200, true), 'ok');
  assert.equal(CA.subida(200, false), 'reintentar');
  assert.equal(CA.subida(0, false), 'reintentar');
  assert.equal(CA.subida(503, false), 'reintentar');
  assert.equal(CA.subida(408, false), 'reintentar');
  assert.equal(CA.subida(429, false), 'tope');
  assert.equal(CA.subida(409, false), 'idRepetido');
  assert.equal(CA.subida(403, false, 'token inválido'), 'token');
  assert.equal(CA.subida(403, false, 'no habilitado'), 'rechazo');
  assert.equal(CA.subida(413, false), 'rechazo');
});
await caso('reglas: duración y textos', () => {
  assert.equal(CA.duracion(42.4), '0:42');
  assert.equal(CA.duracion(120), '2:00');
  assert.equal(CA.duracion(-3), '0:00');
  assert.equal(CA.duracionHablada(65), '1 minuto 5 segundos');
  assert.equal(CA.textoAudio(7), 'Audio de 0:07');
  assert.equal(CA.textoFallo(R.CODIGO_TOPE), T.TOPE);
  assert.equal(CA.sePuedeReintentar(R.CODIGO_SIN_ARCHIVO), false);
});
await caso('los textos no nombran nada interno ni dicen coach', () => {
  for (const t of CA.TEXTOS) assert.doesNotMatch(t, /\bIA\b|inteligencia|transcrib|autom|robot|claude|deepgram|coach|entrenador/i, t);
});
await caso('formato por los bytes y grabador preferido', () => {
  assert.equal(CA.formatoDeBytes(jpeg(), 'foto'), 'image/jpeg');
  assert.equal(CA.formatoDeBytes(m4a(), 'foto'), null);
  assert.equal(CA.formatoDeBytes(m4a(), 'audio'), 'audio/mp4');
  const webm = new Uint8Array(20); webm.set([0x1a, 0x45, 0xdf, 0xa3]);
  assert.equal(CA.formatoDeBytes(webm, 'audio'), 'audio/webm');
  assert.equal(CA.mimeGrabacion((m) => m.startsWith('audio/webm')), 'audio/webm;codecs=opus');
  assert.equal(CA.mimeGrabacion((m) => m === 'audio/mp4'), 'audio/mp4');
  assert.equal(CA.mimeGrabacion(() => false), '');
});
await caso('palanca: apagada no muestra nada; el servidor manda', async () => {
  const d = doble();
  const m = modelo(d);
  assert.equal(await m.consultar(false), false);
  assert.equal(await m.consultar(true), true);
  d.habilitado = false;
  assert.equal(await m.consultar(true), false);
  const n = modelo(doble({ sinFuncion: true }));
  assert.equal(await n.consultar(true), false);
});
await caso('palanca: sin red queda lo último que se supo', async () => {
  const d = doble();
  const almacen = almacenMemoria();
  const m = await prendido(d, { almacen });
  d.sinRed = true;
  const m2 = modelo(d, { almacen });
  assert.equal(await m2.consultar(null), true);
});
await caso('apagado no encola', async () => {
  const m = modelo(doble());
  assert.equal(await m.encolar('foto', jpeg()), null);
});
await caso('foto: sale con sus encabezados y se confirma', async () => {
  const d = doble();
  const m = modelo(d);
  await m.consultar(true);
  const id = await m.encolar('foto', jpeg());
  await quieto(m);
  assert.equal(d.subidas.length, 1);
  const h = d.subidas[0].headers;
  assert.equal(h['x-chat-token'], TOK);
  assert.equal(h['x-chat-id'], id);
  assert.equal(h['x-chat-tipo'], 'foto');
  assert.equal(h['Content-Type'], 'image/jpeg');
  assert.equal(h['x-chat-duracion'], undefined);
  assert.equal(m.pendientes.size, 0);
  assert.equal(m.confirmados.get(id).comentarioId, 'c1');
});
await caso('audio: duración redondeada y con tope; muy corto no sale', async () => {
  const d = doble();
  const m = modelo(d);
  await m.consultar(true);
  await m.encolar('audio', m4a(), 41.6);
  await m.encolar('audio', m4a(), 180);
  await quieto(m);
  assert.deepEqual(d.subidas.map((s) => s.headers['x-chat-duracion']), ['42', '120']);
  assert.equal(await m.encolar('audio', m4a(), 0.4), null);
  assert.equal(m.anuncio.texto, T.MUY_CORTO);
});
await caso('foto que no es JPEG o muy grande no se encola', async () => {
  const m = modelo(doble());
  await m.consultar(true);
  assert.equal(await m.encolar('foto', m4a()), null);
  assert.equal(m.anuncio.texto, T.FOTO_ILEGIBLE);
  assert.equal(await m.encolar('foto', jpeg(R.BYTES_MAXIMOS + 1)), null);
});
await caso('sin señal queda enviando y espera; al despertar sale', async () => {
  const d = doble({ sinRed: true });
  const almacen = almacenMemoria();
  const m = await prendido(d, { almacen });
  const id = await m.encolar('foto', jpeg());
  await quieto(m);
  assert.equal(m.pendientes.get(id).fallo, false);
  assert.equal(d.programados.length, 1);
  assert.equal(m.burbujas()[0].id, 'adj_' + id);
  assert.equal(m.burbujas()[0]._tmp, true);
  d.sinRed = false;
  m.despertar();
  await quieto(m);
  assert.equal(m.pendientes.size, 0);
  assert.equal(d.programados[0].vivo, false);
});
await caso('503 espera más cada vez', async () => {
  const d = doble({ respuestas: [[503, {}], [503, {}]] });
  const m = modelo(d);
  await m.consultar(true);
  await m.encolar('foto', jpeg());
  await quieto(m);
  d.programados[0].fn();
  await quieto(m);
  assert.ok(d.programados[1].ms > d.programados[0].ms);
});
await caso('la pestaña cerrada: vuelve de la cola y sale', async () => {
  const d = doble({ sinRed: true });
  const almacen = almacenMemoria();
  const m = await prendido(d, { almacen });
  const id = await m.encolar('audio', m4a(), 5);
  await quieto(m);
  d.sinRed = false;
  const m2 = modelo(d, { almacen });
  await m2.consultar(true);
  await m2.cargar();
  await quieto(m2);
  assert.equal(m2.pendientes.size, 0);
  assert.equal(m2.confirmados.has(id), true);
});
await caso('lo de más de 14 días se limpia', async () => {
  const d = doble({ sinRed: true });
  const almacen = almacenMemoria();
  const m = await prendido(d, { almacen, ahora: () => Date.parse('2026-10-01T00:00:00Z') });
  await m.encolar('foto', jpeg());
  const m2 = modelo(d, { almacen });
  await m2.cargar();
  assert.equal(m2.pendientes.size, 0);
  assert.equal((await almacen.listar()).length, 0);
});
await caso('otra cuenta en el mismo navegador no ve lo ajeno', async () => {
  const d = doble({ sinRed: true });
  const almacen = almacenMemoria();
  const m = await prendido(d, { almacen });
  await m.encolar('foto', jpeg());
  const otra = new ModeloChatAdjuntos({ token: 'otro-token-9999999999', visionUrl: 'https://vision.test', rpc: d.rpc, fetch: d.fetch, programar: d.programar, almacen });
  await otra.cargar();
  assert.equal(otra.pendientes.size, 0);
});
await caso('429: no salió con el texto del tope, sin reintento solo; Reintentar lo manda', async () => {
  const d = doble({ respuestas: [[429, { ok: false, error: 'muchos' }]] });
  const m = modelo(d);
  await m.consultar(true);
  const id = await m.encolar('foto', jpeg());
  await quieto(m);
  const p = m.pendientes.get(id);
  assert.equal(p.fallo, true);
  assert.equal(p.motivo, R.CODIGO_TOPE);
  assert.equal(m.anuncio.texto, T.TOPE);
  assert.equal(d.programados.length, 0);
  assert.equal(CA.textoFallo(m.burbujas()[0]._motivo), T.TOPE);
  await m.reintentar(id);
  await quieto(m);
  assert.equal(m.pendientes.size, 0);
  assert.equal(d.subidas.length, 2);
});
await caso('429 con más en la cola: lo demás queda no salió sin volver a subir', async () => {
  const d = doble({ sinRed: true });
  const m = await prendido(d);
  await m.encolar('foto', jpeg());
  await m.encolar('audio', m4a(), 4);
  await quieto(m);
  d.sinRed = false;
  d.respuestas.push([429, { ok: false }]);
  const antes = d.subidas.length;
  m.despertar();
  await quieto(m);
  assert.equal(d.subidas.length - antes, 1);
  assert.ok([...m.pendientes.values()].every((p) => p.fallo && p.motivo === R.CODIGO_TOPE));
});
await caso('413 o formato: no salió; Borrar lo saca', async () => {
  const d = doble({ respuestas: [[413, { ok: false, error: 'archivo muy grande' }]] });
  const almacen = almacenMemoria();
  const m = await prendido(d, { almacen });
  const id = await m.encolar('foto', jpeg());
  await quieto(m);
  assert.equal(m.pendientes.get(id).motivo, R.CODIGO_RECHAZO);
  await m.descartar(id);
  assert.equal(m.pendientes.size, 0);
  assert.equal((await almacen.listar()).length, 0);
});
await caso('409: sale con un id nuevo', async () => {
  const d = doble({ respuestas: [[409, { ok: false, error: 'id repetido' }]] });
  const m = modelo(d);
  await m.consultar(true);
  const id = await m.encolar('foto', jpeg());
  await quieto(m);
  assert.equal(d.subidas.length, 2);
  assert.notEqual(d.subidas[1].headers['x-chat-id'], id);
  assert.equal(m.pendientes.size, 0);
});
await caso('sin el archivo: no salió sin Reintentar', async () => {
  const d = doble({ sinRed: true });
  const almacen = almacenMemoria();
  const m = await prendido(d, { almacen });
  const id = await m.encolar('foto', jpeg());
  const meta = (await almacen.listar())[0];
  await almacen.sacar(id);
  await almacen.agregar(meta, null);
  d.sinRed = false;
  m.despertar();
  await quieto(m);
  assert.equal(m.pendientes.get(id).motivo, R.CODIGO_SIN_ARCHIVO);
  await m.reintentar(id);
  assert.equal(m.pendientes.get(id).fallo, true);
});
await caso('token caído: la cola se frena sin marcar nada', async () => {
  const d = doble({ respuestas: [[403, { ok: false, error: 'token inválido' }]] });
  const m = modelo(d);
  await m.consultar(true);
  const id = await m.encolar('foto', jpeg());
  await quieto(m);
  assert.equal(m.pendientes.get(id).fallo, false);
  assert.equal(m.pausadoPorToken, true);
  await m.encolar('foto', jpeg());
  await quieto(m);
  assert.equal(d.subidas.length, 1);
});
await caso('firmas: de a muchas, en caché; sin red queda para reintentar', async () => {
  const d = doble();
  const m = modelo(d);
  const a = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', b = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  assert.equal(await m.url(a, [a, b]), `https://x.test/${a}`);
  assert.equal(await m.url(b, [a, b]), `https://x.test/${b}`);
  assert.equal(d.firmas.length, 1);
  assert.deepEqual(d.firmas[0].sort(), [a, b].sort());
  assert.equal(m.mime(a), 'image/jpeg');
  const d2 = doble({ sinRed: true });
  const n = modelo(d2);
  assert.equal(await n.url(a), null);
  assert.equal(n.sinBajar.has(a), true);
  d2.sinRed = false;
  assert.equal(await n.url(a), `https://x.test/${a}`);
  assert.equal(n.sinBajar.has(a), false);
});
await caso('lo propio se ve sin pedir firma', async () => {
  const d = doble({ sinRed: true });
  globalThis.URL.createObjectURL = () => 'blob:local';
  const m = await prendido(d);
  const id = await m.encolar('foto', jpeg());
  assert.equal(await m.url(id), 'blob:local');
  assert.equal(d.firmas.length, 0);
  assert.equal(m.mime(id), 'image/jpeg');
});

await caso('después de recargar, lo que espera se ve del archivo guardado', async () => {
  const d = doble({ sinRed: true });
  globalThis.URL.createObjectURL = () => 'blob:guardado';
  const almacen = almacenMemoria();
  const m = await prendido(d, { almacen });
  const id = await m.encolar('foto', jpeg());
  await quieto(m);
  const m2 = await prendido(d, { almacen });
  await m2.cargar();
  assert.equal(await m2.url(id), 'blob:guardado');
  assert.equal(d.firmas.length, 0);
});

console.log(`chat-adjuntos: ${ok} casos OK${process.exitCode ? ' (con fallas)' : ''}`);
