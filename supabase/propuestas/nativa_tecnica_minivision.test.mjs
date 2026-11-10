// Prueba los endpoints propuestos pegados al server.mjs REAL, con ffmpeg y ffprobe REALES, contra un doble local de PostgREST
// y Storage. No habla con ningún servicio vivo: SUPABASE_URL apunta a 127.0.0.1 y HOME a una carpeta temporal.
//   node --test supabase/propuestas/nativa_tecnica_minivision.test.mjs
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const aqui = dirname(fileURLToPath(import.meta.url));
const exec = promisify(execFile);
const espera = (ms) => new Promise((r) => setTimeout(r, ms));
const carp = (id) => createHash('sha256').update(`tecnica:${id}`).digest('hex').slice(0, 32);
const FF = existsSync('/opt/homebrew/bin/ffmpeg') ? '/opt/homebrew/bin/ffmpeg' : 'ffmpeg';
const FP = existsSync('/opt/homebrew/bin/ffprobe') ? '/opt/homebrew/bin/ffprobe' : 'ffprobe';

let TOK_A, TOK_B, ID_A, ID_B, corrida = 0, db;
function reiniciarDb() {
  corrida += 1;
  TOK_A = `token-del-alumno-a-${corrida}-0000000`; TOK_B = `token-del-alumno-b-${corrida}-0000000`;
  ID_A = randomUUID(); ID_B = randomUUID();
  db = {
    clientes: new Map([[TOK_A, 'cli-a'], [TOK_B, 'cli-b']]), habilitado: true,
    filas: new Map([[ID_A, { cliente: 'cli-a', estado: 'borrador', path: null }], [ID_B, { cliente: 'cli-b', estado: 'borrador', path: null }]]),
    objetos: new Map(), fallos: [], pedidos: [],
  };
}
function fallar(patron, tipo, veces = Infinity) { db.fallos.push({ patron, tipo, veces }); }
function puede(c, i) {
  const x = db.filas.get(i);
  if (!x || x.cliente !== c) return 'no_encontrado';
  if (x.path) return 'ya';
  if (!db.habilitado) return 'no_habilitado';
  return x.estado === 'borrador' ? 'ok' : 'estado';
}
function rpc(fn, b) {
  switch (fn) {
    case 'mypump_get_cliente_info': { const c = db.clientes.get(b.p_token); return c ? [{ cliente_id: c }] : []; }
    case 'mypump_tecnica_puede': return puede(b.p_cliente_id, b.p_id);
    case 'mypump_tecnica_registrar': {
      const p = puede(b.p_cliente_id, b.p_id);
      if (p !== 'ok') return p;
      Object.assign(db.filas.get(b.p_id), { path: b.p_path, bytes: b.p_bytes, duracion: b.p_duracion, estado: 'enviado' });
      return 'ok';
    }
    case 'mypump_tecnica_borrar_video': {
      const f = db.filas.get(b.p_id);
      if (!f || f.cliente !== b.p_cliente_id || !f.path) return { resultado: 'no_encontrado' };
      if (f.estado === 'procesando') return { resultado: 'estado' };
      const path = f.path; f.borrado = true; f.estado = 'descartado';
      return { resultado: 'ok', path };
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
  if (url.pathname === '/rest/v1/mypump_tecnica' && req.method === 'GET') {
    const filtroId = url.searchParams.get('id').slice(3), cli = url.searchParams.get('cliente_id').slice(3);
    const x = db.filas.get(filtroId);
    if (!x || x.cliente !== decodeURIComponent(cli) || x.borrado) return contestar(200, []);
    return contestar(200, x.path ? [{ path: x.path, estado: x.estado }] : []);
  }
  if (url.pathname.startsWith('/storage/v1/object/sign/tecnica/')) return contestar(200, { signedURL: `/object/sign/tecnica/${url.pathname.slice('/storage/v1/object/sign/tecnica/'.length)}?token=firmado` });
  if (url.pathname === '/storage/v1/object/tecnica' && req.method === 'DELETE') { for (const p of json().prefixes) db.objetos.delete(p); return contestar(200, []); }
  if (url.pathname.startsWith('/storage/v1/object/tecnica/')) { db.objetos.set(url.pathname.slice('/storage/v1/object/tecnica/'.length), crudo); return contestar(200, { Key: 'ok' }); }
  contestar(404, { message: `sin ruta ${id}` });
});

let hijo, puerto, puertoDoble, salida = '', murio = null, dir, control, tmpServidor, video, corto, largoV;
function armarServidor(d) {
  let s = readFileSync(join(aqui, '../../mini-vision/server.mjs'), 'utf8');
  const tope = "const tope = feature === 'fotos' ? RATE_FOTOS : RATE_LIMIT;";
  assert.ok(s.includes(tope));
  s = s.replace(tope, "const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'tecnica' ? RATE_TECNICA : RATE_LIMIT;");
  const ruta = "  if (req.method !== 'POST' || req.url !== '/vision')";
  assert.ok(s.includes(ruta));
  s = s.replace(ruta, `  if (req.method === 'POST' && req.url === '/tecnica/upload') return handleTecnicaUpload(req, res, origin);
  if (req.method === 'POST' && req.url === '/tecnica/url')    return handleTecnicaUrl(req, res, origin);
  if (req.method === 'POST' && req.url === '/tecnica/borrar') return handleTecnicaBorrar(req, res, origin);
${ruta}`);
  s += `\n${readFileSync(join(aqui, 'nativa_tecnica_minivision.mjs'), 'utf8')}`;
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
async function generar(ruta, segundos) {
  await exec(FF, ['-nostdin', '-v', 'error', '-y', '-f', 'lavfi', '-i', `testsrc=size=160x120:rate=10:duration=${segundos}`, '-f', 'lavfi', '-i', `sine=frequency=440:duration=${segundos}`,
    '-metadata', 'location=+12.3456-078.9012/', '-metadata', 'title=secreto', '-c:v', 'libx264', '-preset', 'ultrafast', '-c:a', 'aac', '-shortest', ruta], { timeout: 60000 });
}
before(async () => {
  reiniciarDb();
  await new Promise((r) => doble.listen(0, '127.0.0.1', r));
  puertoDoble = doble.address().port;
  dir = mkdtempSync(join(tmpdir(), 'tec-minivision-'));
  tmpServidor = join(dir, 'tmp'); mkdirSync(tmpServidor);
  control = join(dir, 'control');
  const envolver = (nombre, real) => {
    const f = join(dir, nombre);
    writeFileSync(f, `#!/bin/sh\nif [ -f "${control}.${nombre}" ]; then exit "$(cat "${control}.${nombre}")"; fi\nexec "${real}" "$@"\n`);
    chmodSync(f, 0o755);
    return f;
  };
  const a = join(dir, 'a.mp4'), b = join(dir, 'b.mp4'), c = join(dir, 'c.mp4');
  await generar(a, 6); await generar(b, 2); await generar(c, 80);
  video = readFileSync(a); corto = readFileSync(b); largoV = readFileSync(c);
  puerto = await libre();
  hijo = spawn(process.execPath, [armarServidor(dir)], {
    env: { PATH: process.env.PATH, HOME: dir, TMPDIR: tmpServidor, PORT: String(puerto), SUPABASE_URL: `http://127.0.0.1:${puertoDoble}`, SUPABASE_SERVICE_KEY: 'clave-de-prueba',
           TECNICA_FFMPEG: envolver('ffmpeg', FF), TECNICA_FFPROBE: envolver('ffprobe', FP) },
  });
  hijo.stdout.on('data', (d) => { salida += d; });
  hijo.stderr.on('data', (d) => { salida += d; });
  hijo.on('exit', (c2, s) => { murio = `${c2}/${s}`; });
  for (let i = 0; i < 100 && !salida.includes('escuchando'); i++) await espera(50);
  assert.ok(salida.includes('escuchando'), salida);
});
after(async () => {
  hijo.kill();
  doble.closeAllConnections();
  await new Promise((r) => doble.close(r));
  rmSync(dir, { recursive: true, force: true });
});
beforeEach(() => { reiniciarDb(); for (const n of ['ffmpeg', 'ffprobe']) rmSync(`${control}.${n}`, { force: true }); });

function pedir(ruta, { headers = {}, cuerpo, mandarCuerpo = true } = {}) {
  return new Promise((resolve) => {
    const h = { ...headers };
    if (cuerpo !== undefined && h['content-length'] === undefined) h['content-length'] = cuerpo.length;
    const q = request({ host: '127.0.0.1', port: puerto, path: ruta, method: 'POST', headers: h, agent: false }, (r) => {
      let t = '';
      r.on('data', (c) => { t += c; });
      r.on('end', () => resolve({ status: r.statusCode, json: t ? JSON.parse(t) : null }));
      r.on('error', () => resolve({ status: 0 }));
    });
    q.on('error', () => resolve({ status: 0 }));
    if (cuerpo !== undefined && mandarCuerpo) q.write(cuerpo);
    if (mandarCuerpo) q.end(); else q.flushHeaders();
  });
}
const cab = (over = {}) => ({ 'x-tecnica-token': TOK_A, 'x-tecnica-id': ID_A, ...over });
const subir = (over = {}, b = video) => pedir('/tecnica/upload', { headers: cab(over), cuerpo: b });
const j = (o) => ({ headers: { 'content-type': 'application/json' }, cuerpo: Buffer.from(JSON.stringify(o)) });
const temporales = () => readdirSync(tmpServidor).filter((n) => n.startsWith('tecnica-'));
async function sinTemporales() { for (let i = 0; i < 40 && temporales().length; i++) await espera(25); assert.deepEqual(temporales(), []); }

test('sube, registra y pasa a enviado; el path no lleva el cliente', async () => {
  const r = await subir();
  assert.equal(r.status, 200); assert.equal(r.json.ok, true);
  const f = db.filas.get(ID_A);
  assert.equal(f.estado, 'enviado'); assert.equal(f.path, `${carp('cli-a')}/${ID_A}.mp4`);
  assert.ok(!f.path.includes('cli-a'));
  assert.ok(f.duracion > 5 && f.duracion < 7);
  assert.ok(db.objetos.has(f.path));
  await sinTemporales();
});
test('lo guardado va sin audio y sin metadatos', async () => {
  await subir();
  const f = db.filas.get(ID_A);
  const p = join(dir, 'guardado.mp4');
  writeFileSync(p, db.objetos.get(f.path));
  const { stdout } = await exec(FP, ['-v', 'error', '-show_entries', 'stream=codec_type:format_tags', '-of', 'json', p]);
  const d = JSON.parse(stdout);
  assert.deepEqual(d.streams.map((s) => s.codec_type), ['video']);
  assert.ok(!JSON.stringify(d.format?.tags ?? {}).match(/location|secreto/));
});
test('reintento: ya, sin volver a procesar', async () => {
  await subir();
  const antes = db.pedidos.length;
  const r = await subir();
  assert.equal(r.json.ya, true);
  assert.ok(!db.pedidos.slice(antes).some((p) => p.includes('/storage/')));
});
test('token inválido: 403 y no guarda', async () => {
  const r = await subir({ 'x-tecnica-token': 'no-es-un-token-de-nadie-000000' });
  assert.equal(r.status, 403); assert.equal(db.objetos.size, 0);
});
test('el envío de otro: 404', async () => {
  const r = await subir({ 'x-tecnica-id': ID_B });
  assert.equal(r.status, 404); assert.equal(db.objetos.size, 0);
});
test('id inválido: 400; sin largo: 411', async () => {
  assert.equal((await subir({ 'x-tecnica-id': 'hola' })).status, 400);
  assert.equal((await pedir('/tecnica/upload', { headers: { ...cab(), 'transfer-encoding': 'chunked' }, cuerpo: undefined })).status, 411);
});
test('muy pesado: 413 sin leer el cuerpo', async () => {
  const r = await pedir('/tecnica/upload', { headers: { ...cab(), 'content-length': String(61 * 1024 * 1024) }, mandarCuerpo: false });
  assert.equal(r.status, 413);
});
test('no habilitado: 403; ya enviado por otro camino: 409', async () => {
  db.habilitado = false;
  assert.equal((await subir()).status, 403);
  db.habilitado = true; db.filas.get(ID_A).estado = 'descartado';
  assert.equal((await subir()).status, 409);
});
test('no es un video: 400', async () => {
  const r = await subir({}, Buffer.from('esto no es un video, para nada, ni cerca'));
  assert.equal(r.status, 400); assert.equal(db.objetos.size, 0);
  await sinTemporales();
});
test('con cabecera de MP4 pero roto: 400', async () => {
  const b = Buffer.concat([video.subarray(0, 32), Buffer.alloc(4000, 7)]);
  const r = await subir({}, b);
  assert.equal(r.status, 400); assert.equal(db.objetos.size, 0);
});
test('duración: muy corto y muy largo, 400', async () => {
  assert.equal((await subir({}, corto)).json.error, 'video muy corto');
  assert.equal((await subir({}, largoV)).json.error, 'video muy largo');
  assert.equal(db.objetos.size, 0);
  await sinTemporales();
});
test('ffmpeg no puede con el archivo: 400, nada guardado, fila intacta', async () => {
  writeFileSync(`${control}.ffmpeg`, '1');
  const r = await subir();
  assert.equal(r.status, 400); assert.equal(db.objetos.size, 0);
  assert.equal(db.filas.get(ID_A).estado, 'borrador');
  await sinTemporales();
});
test('la base falla al preguntar: 503', async () => {
  fallar(/rpc\/mypump_tecnica_puede/, 500);
  assert.equal((await subir()).status, 503);
});
test('Storage falla: 502 sin registrar', async () => {
  fallar(/POST \/storage\/v1\/object\/tecnica/, 500);
  const r = await subir();
  assert.equal(r.status, 502); assert.equal(db.filas.get(ID_A).estado, 'borrador');
});
test('registrar se cae: 502 y el objeto queda para el reintento', async () => {
  fallar(/rpc\/mypump_tecnica_registrar/, 'red', 1);
  const r = await subir();
  assert.equal(r.status, 502); assert.equal(db.objetos.size, 1);
  const r2 = await subir();
  assert.equal(r2.status, 200);
  assert.equal(db.filas.get(ID_A).estado, 'enviado');
});
test('cambió de estado mientras subía: saca el objeto', async () => {
  const original = db.filas.get(ID_A);
  fallar(/POST \/storage\/v1\/object\/tecnica\/nunca/, 500);
  let pasado = false;
  const intervalo = setInterval(() => { if (db.objetos.size && !pasado) { pasado = true; original.estado = 'descartado'; } }, 1);
  const prom = subir();
  const r = await prom;
  clearInterval(intervalo);
  // Si el cambio llegó antes de registrar: 409 y sin objeto. Si llegó después, ya quedó enviado: las dos salidas son válidas.
  if (r.status === 409) assert.equal(db.objetos.size, 0);
  else assert.equal(r.status, 200);
});
test('corte a mitad del cuerpo: no queda nada', async () => {
  await new Promise((resolve) => {
    const q = request({ host: '127.0.0.1', port: puerto, path: '/tecnica/upload', method: 'POST', headers: { ...cab(), 'content-length': String(video.length) }, agent: false });
    q.on('error', () => resolve());
    q.write(video.subarray(0, 100));
    setTimeout(() => { q.destroy(); resolve(); }, 300);
  });
  await sinTemporales();
  assert.equal(db.objetos.size, 0);
  assert.equal(murio, null);
});
test('topes por token: 429 al pasar los de hoy', async () => {
  const ids = [];
  for (let i = 0; i < 9; i++) { const n = randomUUID(); db.filas.set(n, { cliente: 'cli-a', estado: 'borrador', path: null }); ids.push(n); }
  const r = [];
  for (const n of ids) r.push((await subir({ 'x-tecnica-id': n })).status);
  assert.deepEqual(r.slice(0, 8), Array(8).fill(200));
  assert.equal(r[8], 429);
});
test('url: la propia, firmada; la de otro, no', async () => {
  await subir();
  const r = await pedir('/tecnica/url', j({ token: TOK_A, id: ID_A }));
  assert.equal(r.status, 200); assert.match(r.json.url, /token=firmado/);
  assert.ok(!('path' in r.json));
  assert.equal((await pedir('/tecnica/url', j({ token: TOK_B, id: ID_A }))).status, 404);
  assert.equal((await pedir('/tecnica/url', j({ token: 'nadie-nadie-nadie-nadie-000', id: ID_A }))).status, 403);
});
test('borrar: saca objeto y marca; repetir contesta ya', async () => {
  await subir();
  const r = await pedir('/tecnica/borrar', j({ token: TOK_A, id: ID_A }));
  assert.equal(r.status, 200); assert.equal(db.objetos.size, 0);
  assert.equal(db.filas.get(ID_A).borrado, true);
  assert.equal((await pedir('/tecnica/borrar', j({ token: TOK_A, id: ID_A }))).json.ya, true);
});
test('borrar: si Storage falla no marca, y el reintento lo termina', async () => {
  await subir();
  fallar(/DELETE \/storage\/v1\/object\/tecnica/, 500, 1);
  assert.equal((await pedir('/tecnica/borrar', j({ token: TOK_A, id: ID_A }))).status, 503);
  assert.equal(db.filas.get(ID_A).borrado, undefined);
  assert.equal((await pedir('/tecnica/borrar', j({ token: TOK_A, id: ID_A }))).status, 200);
  assert.equal(db.objetos.size, 0);
});
test('borrar: durante el análisis, 409', async () => {
  await subir();
  db.filas.get(ID_A).estado = 'procesando';
  assert.equal((await pedir('/tecnica/borrar', j({ token: TOK_A, id: ID_A }))).status, 409);
  assert.equal(db.objetos.size, 1);
});
test('borrar: no toca el video de otro', async () => {
  await subir();
  await pedir('/tecnica/borrar', j({ token: TOK_B, id: ID_A }));
  assert.equal(db.objetos.size, 1);
});
test('el servidor sigue vivo', () => { assert.equal(murio, null); });
