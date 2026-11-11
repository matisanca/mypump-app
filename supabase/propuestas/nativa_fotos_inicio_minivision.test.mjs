// Prueba los endpoints propuestos pegados al server.mjs REAL, contra un doble local de PostgREST y Storage. No habla con ningún
// servicio vivo: SUPABASE_URL apunta a 127.0.0.1 y HOME a una carpeta temporal.
//   node --test supabase/propuestas/nativa_fotos_inicio_minivision.test.mjs
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const espera = (ms) => new Promise((r) => setTimeout(r, ms));
const carp = (id) => createHash('sha256').update(`fotos-inicio:${id}`).digest('hex').slice(0, 32);
const CUERPO = ['frente', 'perfil', 'espalda'];

// ── Un JPEG de mentira, con los segmentos de verdad: alcanza para lo que mira el servidor (no decodifica la imagen) ──
function seg(marca, datos) {
  const b = Buffer.alloc(4 + datos.length);
  b[0] = 0xff; b[1] = marca; b.writeUInt16BE(datos.length + 2, 2); datos.copy(b, 4);
  return b;
}
function exif(orientacion) {
  const t = Buffer.alloc(8 + 2 + 12 * 2 + 4 + 40);
  t.write('MM', 0, 'latin1'); t.writeUInt16BE(42, 2); t.writeUInt32BE(8, 4);
  t.writeUInt16BE(2, 8);
  t.writeUInt16BE(0x0112, 10); t.writeUInt16BE(3, 12); t.writeUInt32BE(1, 14); t.writeUInt16BE(orientacion, 18);
  t.writeUInt16BE(0x8825, 22); t.writeUInt16BE(4, 24); t.writeUInt32BE(1, 26); t.writeUInt32BE(38, 30);   // puntero al GPS
  t.write('GPS-34.6037,-58.3816', 38, 'latin1');
  return Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), t]);
}
function jpeg({ ancho = 1200, alto = 1600, orientacion = null, comentario = null, icc = false, xmp = false, cortar = false } = {}) {
  const sof = Buffer.alloc(15);
  sof[0] = 8; sof.writeUInt16BE(alto, 1); sof.writeUInt16BE(ancho, 3); sof[5] = 3;
  const partes = [Buffer.from([0xff, 0xd8]), seg(0xe0, Buffer.from('JFIF\0\x01\x01\0\0\x01\0\x01\0\0', 'latin1'))];
  if (orientacion !== null) partes.push(seg(0xe1, exif(orientacion)));
  if (xmp) partes.push(seg(0xe1, Buffer.from('http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>casa</x:xmpmeta>', 'latin1')));
  if (icc) partes.push(seg(0xe2, Buffer.from('ICC_PROFILE\0\x01\x01perfil-de-color', 'latin1')));
  if (comentario) partes.push(seg(0xfe, Buffer.from(comentario, 'latin1')));
  partes.push(seg(0xdb, Buffer.alloc(65, 1)), seg(0xc0, sof), seg(0xc4, Buffer.alloc(20, 2)), seg(0xda, Buffer.alloc(10, 3)));
  partes.push(Buffer.from([0x12, 0x34, 0xff, 0x00, 0x56, 0x78]), cortar ? Buffer.alloc(0) : Buffer.from([0xff, 0xd9]));
  return Buffer.concat(partes);
}

let TOK_A, TOK_B, corrida = 0, db;
function reiniciarDb() {
  corrida += 1;
  TOK_A = `token-del-alumno-a-${corrida}-0000000`;
  TOK_B = `token-del-alumno-b-${corrida}-0000000`;
  db = {
    clientes: new Map([[TOK_A, 'cli-a'], [TOK_B, 'cli-b']]),
    palanca: true,
    sets: new Map([['cli-a', { cerrado: false, completado: null, actualizado: null }], ['cli-b', { cerrado: false, completado: null, actualizado: null }]]),
    fotos: new Map(), objetos: new Map(), fallos: [], pedidos: [], borradas: [],
  };
}
function fallar(patron, tipo, veces = Infinity) { db.fallos.push({ patron, tipo, veces }); }
const habilitado = (c) => db.palanca && db.sets.has(c) && !db.sets.get(c).cerrado;
const vigentes = (c, pose) => [...db.fotos.values()].filter((f) => f.cliente_id === c && f.vigente && (!pose || f.pose === pose));
function puede(c, f, pose) {
  const ya = db.fotos.get(f);
  if (ya?.cliente_id === c) return 'ya';
  if (ya) return 'ajena';
  if (!habilitado(c)) return 'no_habilitado';
  if (pose === 'motivacion' && vigentes(c, 'motivacion').length >= 4) return 'tope';
  return 'ok';
}
function rpc(fn, b) {
  switch (fn) {
    case 'mypump_get_cliente_info': { const c = db.clientes.get(b.p_token); return c ? [{ cliente_id: c }] : []; }
    case 'mypump_fotos_inicio_habilitado': return habilitado(b.p_cliente_id);
    case 'mypump_fotos_inicio_puede': return puede(b.p_cliente_id, b.p_foto_id, b.p_pose);
    case 'mypump_fotos_inicio_registrar': {
      if (db.cerrarAlRegistrar) db.sets.get(b.p_cliente_id).cerrado = true;
      const p = puede(b.p_cliente_id, b.p_foto_id, b.p_pose);
      if (p !== 'ok') return { resultado: p, borrar: [] };
      if (b.p_pose !== 'motivacion' && Math.max(b.p_ancho, b.p_alto) < 1080) return { resultado: 'chica', borrar: [] };
      const borrar = [];
      if (b.p_pose !== 'motivacion') for (const v of vigentes(b.p_cliente_id, b.p_pose)) { v.vigente = false; borrar.push({ id: v.id, path: v.path }); }
      db.fotos.set(b.p_foto_id, { id: b.p_foto_id, cliente_id: b.p_cliente_id, pose: b.p_pose, path: b.p_path, bytes: b.p_bytes, ancho: b.p_ancho, alto: b.p_alto,
        tomada_en: b.p_tomada_en, brillo: b.p_brillo, nitidez: b.p_nitidez, vigente: true });
      const s = db.sets.get(b.p_cliente_id);
      if (b.p_pose !== 'motivacion') { s.actualizado = Date.now(); if (CUERPO.every((x) => vigentes(b.p_cliente_id, x).length === 1)) s.completado ??= Date.now(); }
      return { resultado: 'ok', borrar };
    }
    case 'mypump_fotos_inicio_borrar': {
      const f = db.fotos.get(b.p_foto_id);
      if (!f || f.cliente_id !== b.p_cliente_id) return { resultado: 'no_encontrado' };
      if (!f.vigente) return { resultado: 'ok', id: f.id, path: f.path };
      if (f.pose !== 'motivacion') return { resultado: 'no_se_puede' };
      if (!habilitado(b.p_cliente_id)) return { resultado: 'no_habilitado' };
      f.vigente = false;
      return { resultado: 'ok', id: f.id, path: f.path };
    }
    case 'mypump_fotos_inicio_borrada': {
      const f = db.fotos.get(b.p_foto_id);
      if (!f || f.vigente) return false;
      db.fotos.delete(b.p_foto_id); db.borradas.push(b.p_foto_id);
      return true;
    }
    case 'mypump_fotos_inicio_para_limpiar': return [...db.fotos.values()].filter((f) => !f.vigente).slice(0, b.p_limite).map(({ id, path }) => ({ id, path }));
    case 'mypump_fotos_inicio_servicio': {
      if (!db.sets.has(b.p_cliente_id)) return null;
      return { cliente_id: b.p_cliente_id, completo: !!db.sets.get(b.p_cliente_id).completado,
        fotos: vigentes(b.p_cliente_id).map(({ id, pose, path }) => ({ id, pose, path })) };
    }
    default: throw new Error(`rpc desconocida ${fn}`);
  }
}
const doble = createServer(async (req, res) => {
  const partes = [];
  for await (const c of req) partes.push(c);
  const crudo = Buffer.concat(partes);
  const url = new URL(req.url, 'http://x');
  const id = `${req.method} ${url.pathname}`;
  db.pedidos.push(id);
  const contestar = (s, o) => { res.writeHead(s, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(o)); };
  const f = db.fallos.find((x) => x.veces > 0 && x.patron.test(id));
  if (f) { f.veces -= 1; if (f.tipo === 'red') return req.socket.destroy(); return contestar(f.tipo, { message: 'falla inyectada' }); }
  const json = () => (crudo.length ? JSON.parse(crudo.toString()) : {});
  if (url.pathname.startsWith('/rest/v1/rpc/')) return contestar(200, rpc(url.pathname.split('/').pop(), json()));
  if (url.pathname === '/storage/v1/object/sign/fotos-inicio') return contestar(200, json().paths.map((p) => ({ path: p, signedURL: `/object/sign/fotos-inicio/${p}?token=firmado` })));
  if (url.pathname === '/storage/v1/object/fotos-inicio' && req.method === 'DELETE') { for (const p of json().prefixes) db.objetos.delete(p); return contestar(200, []); }
  if (url.pathname.startsWith('/storage/v1/object/fotos-inicio/')) { db.objetos.set(url.pathname.slice('/storage/v1/object/fotos-inicio/'.length), crudo); return contestar(200, { Key: 'ok' }); }
  contestar(404, { message: `sin ruta ${id}` });
});

let hijo, puerto, puertoDoble, salida = '', murio = null, dir;
function armarServidor(d) {
  if (process.env.SERVIDOR_FINAL) {   // la versión final armada para producción, tal cual
    const f = join(d, 'server.mjs');
    writeFileSync(f, readFileSync(process.env.SERVIDOR_FINAL));
    return f;
  }
  let s = readFileSync(join(aqui, '../../mini-vision/server.mjs'), 'utf8');
  const tope = "const tope = feature === 'fotos' ? RATE_FOTOS : RATE_LIMIT;";
  assert.ok(s.includes(tope));
  s = s.replace(tope, "const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'inicio' ? RATE_INICIO : RATE_LIMIT;");
  const cors = "headers['Access-Control-Allow-Headers'] = 'Content-Type';";
  assert.ok(s.includes(cors));
  s = s.replace(cors, "headers['Access-Control-Allow-Headers'] = 'Content-Type, x-inicio-token, x-inicio-foto, x-inicio-pose, x-inicio-tomada, x-inicio-brillo, x-inicio-nitidez';");
  const ruta = "  if (req.method !== 'POST' || req.url !== '/vision')";
  assert.ok(s.includes(ruta));
  s = s.replace(ruta, `  if (req.method === 'POST' && req.url === '/inicio/upload') return handleInicioUpload(req, res, origin);
  if (req.method === 'POST' && req.url === '/inicio/urls')   return handleInicioUrls(req, res, origin);
  if (req.method === 'POST' && req.url === '/inicio/borrar') return handleInicioBorrar(req, res, origin);
${ruta}`);
  s += `\n${readFileSync(join(aqui, 'nativa_fotos_inicio_minivision.mjs'), 'utf8')}`;
  const f = join(d, 'server.mjs');
  writeFileSync(f, s);
  return f;
}
async function libre() {
  const s = createServer();
  await new Promise((r) => s.listen(0, '127.0.0.1', r));
  const p = s.address().port;
  await new Promise((r) => s.close(r));
  return p;
}
before(async () => {
  reiniciarDb();
  await new Promise((r) => doble.listen(0, '127.0.0.1', r));
  puertoDoble = doble.address().port;
  dir = mkdtempSync(join(tmpdir(), 'inicio-minivision-'));
  mkdirSync(join(dir, 'tmp'));
  puerto = await libre();
  hijo = spawn(process.execPath, [armarServidor(dir)], {
    env: { PATH: process.env.PATH, HOME: dir, TMPDIR: join(dir, 'tmp'), PORT: String(puerto), SUPABASE_URL: `http://127.0.0.1:${puertoDoble}`, SUPABASE_SERVICE_KEY: 'clave-de-prueba' },
  });
  hijo.stdout.on('data', (d) => { salida += d; });
  hijo.stderr.on('data', (d) => { salida += d; });
  hijo.on('exit', (c, s) => { murio = `${c}/${s}`; });
  for (let i = 0; i < 100 && !salida.includes('escuchando'); i++) await espera(50);
  assert.ok(salida.includes('escuchando'), salida);
});
after(async () => {
  hijo.kill();
  doble.closeAllConnections();
  await new Promise((r) => doble.close(r));
  rmSync(dir, { recursive: true, force: true });
});
beforeEach(() => { reiniciarDb(); });

function pedir(ruta, { headers = {}, cuerpo, metodo = 'POST' } = {}) {
  return new Promise((resolve) => {
    const h = { ...headers };
    if (cuerpo !== undefined && h['content-length'] === undefined) h['content-length'] = cuerpo.length;
    const q = request({ host: '127.0.0.1', port: puerto, path: ruta, method: metodo, headers: h, agent: false }, (r) => {
      let t = '';
      r.on('data', (c) => { t += c; });
      r.on('end', () => resolve({ status: r.statusCode, json: t ? JSON.parse(t) : null, headers: r.headers }));
      r.on('error', () => resolve({ status: 0 }));
    });
    q.on('error', () => resolve({ status: 0 }));
    if (cuerpo !== undefined) q.write(cuerpo);
    q.end();
  });
}
const cab = (over = {}) => ({ 'x-inicio-token': TOK_A, 'x-inicio-foto': randomUUID(), 'x-inicio-pose': 'frente', ...over });
const subir = (over = {}, b = jpeg()) => pedir('/inicio/upload', { headers: cab(over), cuerpo: b });
const jsonB = (o) => Buffer.from(JSON.stringify(o));
const urls = (o) => pedir('/inicio/urls', { cuerpo: jsonB(o) });
const borrar = (o) => pedir('/inicio/borrar', { cuerpo: jsonB(o) });
// Lo que el servidor hace después de contestar (sacar la reemplazada) termina enseguida: se espera a que pase.
async function hasta(cond) { for (let i = 0; i < 60 && !cond(); i++) await espera(25); assert.ok(cond(), 'no pasó a tiempo'); }
function vivo() { assert.equal(murio, null, `el proceso murió:\n${salida.slice(-800)}`); }

test('sube una pose: queda en la carpeta de la cuenta, con el tamaño leído del JPEG', async () => {
  const id = randomUUID();
  const r = await subir({ 'x-inicio-foto': id, 'x-inicio-tomada': '2026-11-10T14:03:22-03:00', 'x-inicio-brillo': '118.4', 'x-inicio-nitidez': '42' }, jpeg({ ancho: 1200, alto: 1600 }));
  assert.deepEqual([r.status, r.json], [200, { ok: true, ancho: 1200, alto: 1600 }]);
  const f = db.fotos.get(id);
  assert.equal(f.path, `${carp('cli-a')}/${id}.jpg`);
  assert.deepEqual([f.cliente_id, f.pose, f.ancho, f.alto, f.tomada_en, f.brillo, f.nitidez], ['cli-a', 'frente', 1200, 1600, '2026-11-10T14:03:22-03:00', 118.4, 42]);
  assert.ok(db.objetos.has(f.path));
  assert.ok(!f.path.includes('cli-a'));
  vivo();
});

test('lo guardado no lleva EXIF, GPS, XMP ni comentarios; el perfil de color queda', async () => {
  const id = randomUUID();
  const original = jpeg({ orientacion: 1, xmp: true, comentario: 'mi casa, calle falsa 123', icc: true });
  assert.ok(original.includes('GPS-34.6037'));
  const r = await subir({ 'x-inicio-foto': id }, original);
  assert.equal(r.status, 200);
  const guardado = db.objetos.get(db.fotos.get(id).path);
  for (const s of ['Exif', 'GPS', 'xmpmeta', 'calle falsa']) assert.ok(!guardado.includes(s), s);
  assert.ok(guardado.includes('ICC_PROFILE'));
  assert.ok(guardado.length < original.length);
  assert.deepEqual([guardado[0], guardado[1], guardado.at(-2), guardado.at(-1)], [0xff, 0xd8, 0xff, 0xd9]);
  assert.equal(db.fotos.get(id).bytes, guardado.length);
});

test('una foto con la orientación sin aplicar no entra', async () => {
  const r = await subir({}, jpeg({ orientacion: 6 }));
  assert.equal(r.status, 400);
  assert.equal(db.objetos.size, 0);
});

test('reintento con el mismo id: `ya`, sin guardar de nuevo', async () => {
  const id = randomUUID();
  assert.equal((await subir({ 'x-inicio-foto': id })).status, 200);
  const antes = db.pedidos.filter((p) => p.includes('/storage/')).length;
  const r = await subir({ 'x-inicio-foto': id });
  assert.deepEqual([r.status, r.json], [200, { ok: true, ya: true }]);
  assert.equal(db.pedidos.filter((p) => p.includes('/storage/')).length, antes);
});

test('sacar de nuevo una pose reemplaza a la anterior y la saca del bucket', async () => {
  const a = randomUUID(), b = randomUUID();
  await subir({ 'x-inicio-foto': a });
  const pathA = db.fotos.get(a).path;
  assert.equal((await subir({ 'x-inicio-foto': b })).status, 200);
  await hasta(() => !db.objetos.has(pathA) && !db.fotos.has(a));
  assert.deepEqual(vigentes('cli-a', 'frente').map((f) => f.id), [b]);
  assert.deepEqual(db.borradas, [a]);
});

test('si la reemplazada no se pudo sacar, la fila queda y la levanta el barrido de la subida siguiente', async () => {
  const a = randomUUID(), b = randomUUID();
  await subir({ 'x-inicio-foto': a });
  const pathA = db.fotos.get(a).path;
  fallar(/^DELETE \/storage\/v1\/object\/fotos-inicio$/, 500, 1);
  assert.equal((await subir({ 'x-inicio-foto': b })).status, 200);
  await hasta(() => db.pedidos.includes('POST /rest/v1/rpc/mypump_fotos_inicio_para_limpiar'));
  await hasta(() => !db.objetos.has(pathA) && !db.fotos.has(a));
});

test('con las tres poses el set queda completo', async () => {
  for (const pose of CUERPO) assert.equal((await subir({ 'x-inicio-pose': pose })).status, 200);
  assert.ok(db.sets.get('cli-a').completado);
  assert.equal(db.sets.get('cli-b').completado, null);
});

test('poca resolución: una pose del cuerpo no entra, y la de motivación tiene su propio mínimo', async () => {
  const r = await subir({}, jpeg({ ancho: 800, alto: 1000 }));
  assert.deepEqual([r.status, r.json.error], [422, 'la foto tiene poca resolución']);
  assert.equal(db.objetos.size, 0);
  assert.equal((await subir({}, jpeg({ ancho: 810, alto: 1080 }))).status, 200);
  assert.equal((await subir({ 'x-inicio-pose': 'motivacion' }, jpeg({ ancho: 400, alto: 500 }))).status, 200);
  assert.equal((await subir({ 'x-inicio-pose': 'motivacion' }, jpeg({ ancho: 200, alto: 300 }))).status, 422);
});

test('lo que no es un JPEG entero no se guarda', async () => {
  for (const b of [Buffer.from('hola, no soy una foto'), jpeg({ cortar: true }), jpeg().subarray(0, 60), Buffer.from([0xff, 0xd8, 0xff, 0xd9])]) {
    const r = await subir({}, b);
    assert.equal(r.status, 400, r.json?.error);
  }
  assert.equal(db.objetos.size, 0);
  vivo();
});

test('pedidos mal armados: 4xx sin tocar la base', async () => {
  assert.equal((await subir({ 'x-inicio-foto': 'no-es-un-uuid' })).status, 400);
  assert.equal((await subir({ 'x-inicio-pose': 'selfie' })).status, 400);
  assert.equal((await pedir('/inicio/upload', { headers: { ...cab(), 'content-length': 0 } })).status, 411);
  assert.equal((await pedir('/inicio/upload', { headers: { ...cab(), 'content-length': 5 * 1024 * 1024 } })).status, 413);
  assert.equal(db.pedidos.length, 0);
});

test('la fecha de la foto: solo ISO con zona; otra cosa se ignora', async () => {
  const a = randomUUID(), b = randomUUID();
  await subir({ 'x-inicio-foto': a, 'x-inicio-tomada': 'ayer a la tarde', 'x-inicio-brillo': 'mucho', 'x-inicio-nitidez': '-3' });
  assert.deepEqual([db.fotos.get(a).tomada_en, db.fotos.get(a).brillo, db.fotos.get(a).nitidez], [null, null, null]);
  await subir({ 'x-inicio-foto': b, 'x-inicio-pose': 'perfil', 'x-inicio-tomada': '2026-11-10T17:03:22.120Z' });
  assert.equal(db.fotos.get(b).tomada_en, '2026-11-10T17:03:22.120Z');
});

test('token inválido: 403; el cliente sale del token y nunca del pedido', async () => {
  assert.equal((await subir({ 'x-inicio-token': 'token-que-no-existe-0000000000' })).status, 403);
  const id = randomUUID();
  await subir({ 'x-inicio-token': TOK_B, 'x-inicio-foto': id, 'x-inicio-cliente': 'cli-a' });
  assert.equal(db.fotos.get(id).cliente_id, 'cli-b');
  assert.ok(db.fotos.get(id).path.startsWith(carp('cli-b')));
});

test('el id de la foto de otra cuenta no se pisa', async () => {
  const id = randomUUID();
  await subir({ 'x-inicio-foto': id });
  const r = await subir({ 'x-inicio-token': TOK_B, 'x-inicio-foto': id });
  assert.equal(r.status, 409);
  assert.equal(db.fotos.get(id).cliente_id, 'cli-a');
});

test('apagado o cerrado: 403 y nada guardado', async () => {
  db.palanca = false;
  assert.equal((await subir()).status, 403);
  db.palanca = true; db.sets.get('cli-a').cerrado = true;
  assert.equal((await subir()).status, 403);
  db.sets.delete('cli-b');
  assert.equal((await subir({ 'x-inicio-token': TOK_B })).status, 403);
  assert.equal(db.objetos.size, 0);
});

test('motivación: hasta cuatro', async () => {
  for (let i = 0; i < 4; i++) assert.equal((await subir({ 'x-inicio-pose': 'motivacion' })).status, 200);
  const r = await subir({ 'x-inicio-pose': 'motivacion' });
  assert.deepEqual([r.status, r.json.error], [413, 'llegaste al máximo de fotos']);
  assert.equal(vigentes('cli-a', 'motivacion').length, 4);
});

test('una falla nuestra nunca es 4xx: la cola del teléfono reintenta', async () => {
  fallar(/mypump_get_cliente_info/, 500, 1);
  assert.equal((await subir()).status, 503);
  fallar(/mypump_fotos_inicio_puede/, 500, 1);
  assert.equal((await subir()).status, 503);
  fallar(/^POST \/storage\/v1\/object\/fotos-inicio\//, 500, 1);
  assert.equal((await subir()).status, 502);
  assert.equal(db.fotos.size, 0);
  vivo();
});

test('guardada sin registrar: 502, y el reintento con el mismo id entra', async () => {
  const id = randomUUID();
  fallar(/mypump_fotos_inicio_registrar/, 500, 1);
  assert.equal((await subir({ 'x-inicio-foto': id })).status, 502);
  assert.equal(db.fotos.size, 0);
  assert.equal((await subir({ 'x-inicio-foto': id })).status, 200);
  assert.ok(db.objetos.has(db.fotos.get(id).path));
});

test('si la cierran mientras sube, el objeto no queda suelto', async () => {
  db.cerrarAlRegistrar = true;
  const r = await subir();
  assert.equal(r.status, 403);
  assert.equal(db.objetos.size, 0);
  assert.equal(db.fotos.size, 0);
});

test('tope del día por token: 429', async () => {
  for (let i = 0; i < 40; i++) assert.equal((await subir({ 'x-inicio-pose': 'perfil' })).status, 200, `subida ${i}`);
  assert.equal((await subir({ 'x-inicio-pose': 'perfil' })).status, 429);
});

test('urls: solo las propias y vigentes, con su pose', async () => {
  const a = randomUUID(), b = randomUUID(), m = randomUUID();
  await subir({ 'x-inicio-foto': a });
  await subir({ 'x-inicio-foto': m, 'x-inicio-pose': 'motivacion' });
  await subir({ 'x-inicio-token': TOK_B, 'x-inicio-foto': b });
  const r = await urls({ token: TOK_A });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json.fotos.map((f) => [f.id, f.pose]), [[a, 'frente'], [m, 'motivacion']]);
  assert.ok(r.json.fotos.every((f) => f.url.includes('token=firmado') && f.url.includes(carp('cli-a'))));
  assert.equal(JSON.stringify(r.json).includes('path'), false);
  assert.equal((await urls({ token: 'token-que-no-existe-0000000000' })).status, 403);
  assert.equal((await urls({ token: TOK_A, paths: ['x'] })).json.fotos.length, 2);
  db.sets.get('cli-a').cerrado = true;
  assert.deepEqual((await urls({ token: TOK_A })).json.fotos, []);
});

test('borrar: solo las de motivación, y solo las propias', async () => {
  const cuerpo = randomUUID(), m = randomUUID();
  await subir({ 'x-inicio-foto': cuerpo });
  await subir({ 'x-inicio-foto': m, 'x-inicio-pose': 'motivacion' });
  const path = db.fotos.get(m).path;
  assert.equal((await borrar({ token: TOK_A, foto_id: cuerpo })).status, 409);
  assert.deepEqual((await borrar({ token: TOK_B, foto_id: m })).json, { ok: true, ya: true });
  assert.ok(db.fotos.get(m).vigente);
  assert.deepEqual((await borrar({ token: TOK_A, foto_id: m })).json, { ok: true });
  await hasta(() => !db.objetos.has(path) && !db.fotos.has(m));
  assert.deepEqual((await borrar({ token: TOK_A, foto_id: m })).json, { ok: true, ya: true });
  assert.equal((await borrar({ token: TOK_A, foto_id: 'x' })).status, 400);
});

test('la web puede mandar los encabezados', async () => {
  const r = await pedir('/inicio/upload', { metodo: 'OPTIONS', headers: { origin: 'https://app.mypumpteam.com' } });
  assert.ok(String(r.headers['access-control-allow-headers'] || '').includes('x-inicio-pose'), JSON.stringify(r.headers));
});
