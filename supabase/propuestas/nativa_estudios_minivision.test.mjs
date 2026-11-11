// Prueba los endpoints propuestos pegados al server.mjs REAL contra un doble local de PostgREST y Storage.
// No habla con ningún servicio vivo: SUPABASE_URL apunta a 127.0.0.1 y HOME a una carpeta temporal.
//   node --test supabase/propuestas/nativa_estudios_minivision.test.mjs
// Con SERVIDOR_FINAL=<server.mjs ya armado para producción> prueba ese archivo tal cual.
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const espera = (ms) => new Promise((r) => setTimeout(r, ms));
const carp = (id) => createHash('sha256').update(`estudios:${id}`).digest('hex').slice(0, 32);

let TOK_A, TOK_B, ENV_A, ENV_B, corrida = 0, db;
function reiniciarDb() {
  corrida += 1;
  TOK_A = `token-del-alumno-a-${corrida}-0000000`;
  TOK_B = `token-del-alumno-b-${corrida}-0000000`;
  ENV_A = randomUUID(); ENV_B = randomUUID();
  db = {
    clientes: new Map([[TOK_A, 'cli-a'], [TOK_B, 'cli-b']]),
    habilitado: true,
    envios: new Map([[ENV_A, { cliente: 'cli-a', estado: 'borrador' }], [ENV_B, { cliente: 'cli-b', estado: 'borrador' }]]),
    archivos: new Map(), objetos: new Map(), fallos: [], pedidos: [], firmas: [],
    paths: null,                                     // lo que contesta mypump_estudios_paths_para_firmar
  };
}
function fallar(patron, tipo, veces = Infinity) { db.fallos.push({ patron, tipo, veces }); }
function puede(c, e, a) {
  const x = db.envios.get(e);
  if (!x || x.cliente !== c) return 'no_encontrado';
  const ya = db.archivos.get(a);
  if (ya?.envio_id === e) return 'ya';
  if (ya) return 'ajeno';
  if (!db.habilitado) return 'no_habilitado';
  if (x.estado !== 'borrador') return 'estado';
  return [...db.archivos.values()].filter((v) => v.envio_id === e).length >= 20 ? 'tope' : 'ok';
}
function rpc(fn, b) {
  switch (fn) {
    case 'mypump_get_cliente_info': { const c = db.clientes.get(b.p_token); return c ? [{ cliente_id: c }] : []; }
    case 'mypump_estudios_archivo_puede': return puede(b.p_cliente_id, b.p_envio_id, b.p_archivo_id);
    case 'mypump_estudios_archivo_registrar': {
      const p = puede(b.p_cliente_id, b.p_envio_id, b.p_archivo_id);
      if (p !== 'ok') return p;
      db.archivos.set(b.p_archivo_id, { envio_id: b.p_envio_id, cliente_id: b.p_cliente_id, path: b.p_path, mime: b.p_mime, bytes: b.p_bytes, sha256: b.p_sha256 });
      return 'ok';
    }
    case 'mypump_estudios_paths_para_firmar': db.pedidos.push(`firmar ${b.p_cliente_id} ${b.p_clase} ${b.p_id}`); return typeof db.paths === 'function' ? db.paths(b) : db.paths;
    default: throw new Error(`rpc desconocida ${fn}`);
  }
}
const doble = createServer(async (req, res) => {
  const partes = [];
  for await (const c of req) partes.push(c);
  const crudo = Buffer.concat(partes);
  const url = new URL(req.url, 'http://x');
  const id = `${req.method} ${url.pathname}`;
  const contestar = (s, o) => { res.writeHead(s, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(o)); };
  const f = db.fallos.find((x) => x.veces > 0 && x.patron.test(id));
  if (f) { f.veces -= 1; if (f.tipo === 'red') return req.socket.destroy(); return contestar(f.tipo, { message: 'falla inyectada' }); }
  const json = () => (crudo.length ? JSON.parse(crudo.toString()) : {});
  if (url.pathname.startsWith('/rest/v1/rpc/')) return contestar(200, rpc(url.pathname.split('/').pop(), json()));
  const firma = url.pathname.match(/^\/storage\/v1\/object\/sign\/(\w+)$/);
  if (firma) {
    const b = json();
    db.firmas.push({ bucket: firma[1], expiresIn: b.expiresIn, paths: b.paths });
    return contestar(200, b.paths.map((p) => ({ path: p, signedURL: `/object/sign/${firma[1]}/${p}?token=firmado` })));
  }
  if (url.pathname === '/storage/v1/object/estudios' && req.method === 'DELETE') { for (const p of json().prefixes) db.objetos.delete(p); return contestar(200, []); }
  if (url.pathname.startsWith('/storage/v1/object/estudios/') && req.method === 'POST') {
    db.objetos.set(url.pathname.slice('/storage/v1/object/estudios/'.length), { cuerpo: crudo, mime: req.headers['content-type'] });
    return contestar(200, { Key: 'ok' });
  }
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
  s = s.replace(tope, "const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'estudios' ? RATE_ESTUDIOS : RATE_LIMIT;");
  const cors = "headers['Access-Control-Allow-Headers'] = 'Content-Type';";
  assert.ok(s.includes(cors));
  s = s.replace(cors, "headers['Access-Control-Allow-Headers'] = 'Content-Type, x-estudios-token, x-estudios-envio, x-estudios-archivo';");
  const ruta = "  if (req.method !== 'POST' || req.url !== '/vision')";
  assert.ok(s.includes(ruta));
  s = s.replace(ruta, `  if (req.method === 'POST' && req.url === '/estudios/upload') return handleEstudiosUpload(req, res, origin);
  if (req.method === 'POST' && req.url === '/estudios/urls')   return handleEstudiosUrls(req, res, origin);
${ruta}`);
  s += `\n${readFileSync(join(aqui, 'nativa_estudios_minivision.mjs'), 'utf8')}`;
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
  dir = mkdtempSync(join(tmpdir(), 'est-minivision-'));
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
const PDF = Buffer.concat([Buffer.from('%PDF-1.4\n'), Buffer.alloc(2000, 0x20), Buffer.from('\n%%EOF\n')]);
// Un JPEG mínimo bien formado con un bloque EXIF (APP1) que trae una marca, un APP0 y datos de imagen.
function seg(m, datos) { const l = Buffer.alloc(2); l.writeUInt16BE(datos.length + 2); return Buffer.concat([Buffer.from([0xff, m]), l, datos]); }
const JPEG = Buffer.concat([
  Buffer.from([0xff, 0xd8]), seg(0xe0, Buffer.from('JFIF\0\x01\x01\0\0\x01\0\x01\0\0', 'latin1')),
  seg(0xe1, Buffer.from('Exif\0\0UBICACION-SECRETA-GPS', 'latin1')), seg(0xfe, Buffer.from('comentario-secreto')),
  seg(0xdb, Buffer.alloc(65, 1)), Buffer.from([0xff, 0xda, 0x00, 0x02]), Buffer.alloc(300, 0x11), Buffer.from([0xff, 0xd9]),
]);
const cab = (over = {}) => ({ 'x-estudios-token': TOK_A, 'x-estudios-envio': ENV_A, 'x-estudios-archivo': randomUUID(), ...over });
const subir = (over = {}, b = PDF) => pedir('/estudios/upload', { headers: cab(over), cuerpo: b });
const urls = (o) => pedir('/estudios/urls', { cuerpo: Buffer.from(JSON.stringify(o)) });
function vivo() { assert.equal(murio, null, `el proceso murió:\n${salida.slice(-800)}`); }

test('sube un PDF: path armado por el servidor, sha256 y registro', async () => {
  const id = randomUUID();
  const r = await subir({ 'x-estudios-archivo': id });
  assert.deepEqual([r.status, r.json], [200, { ok: true }]);
  const path = `e/${carp('cli-a')}/${ENV_A}/${id}.pdf`;
  assert.deepEqual([...db.objetos.keys()], [path]);
  assert.equal(db.objetos.get(path).mime, 'application/pdf');
  const f = db.archivos.get(id);
  assert.deepEqual([f.cliente_id, f.path, f.mime, f.bytes, f.sha256], ['cli-a', path, 'application/pdf', PDF.length, createHash('sha256').update(PDF).digest('hex')]);
  assert.equal(path.includes('cli-a'), false, 'la carpeta no lleva el id de la cuenta');
});

test('sube un JPEG sin sus metadatos', async () => {
  const id = randomUUID();
  const r = await subir({ 'x-estudios-archivo': id }, JPEG);
  assert.deepEqual([r.status, r.json], [200, { ok: true }]);
  const g = db.objetos.get(`e/${carp('cli-a')}/${ENV_A}/${id}.jpg`);
  assert.ok(JPEG.includes('UBICACION-SECRETA'), 'la foto de prueba sí lo traía');
  assert.equal(g.cuerpo.includes('UBICACION-SECRETA'), false);
  assert.equal(g.cuerpo.includes('comentario-secreto'), false);
  assert.ok(g.cuerpo.includes('JFIF'));
  assert.deepEqual([g.cuerpo[0], g.cuerpo[1], g.cuerpo.at(-2), g.cuerpo.at(-1)], [0xff, 0xd8, 0xff, 0xd9]);
  assert.equal(db.archivos.get(id).bytes, g.cuerpo.length);
});

test('reintentar el mismo archivo contesta ya y no guarda de nuevo', async () => {
  const id = randomUUID();
  await subir({ 'x-estudios-archivo': id });
  const r = await subir({ 'x-estudios-archivo': id });
  assert.deepEqual([r.status, r.json], [200, { ok: true, ya: true }]);
  assert.equal(db.objetos.size, 1);
});

test('los mismos bytes con otro id entran como otro archivo (el teléfono cuenta los dos)', async () => {
  await subir(); const r = await subir();
  assert.equal(r.status, 200);
  assert.equal(db.archivos.size, 2);
});

test('lo que no es PDF ni JPEG se rechaza por los bytes, no por el encabezado', async () => {
  for (const malo of [Buffer.from('<html>hola</html>'), Buffer.from('PK\x03\x04 un docx'), Buffer.concat([Buffer.from([0x89]), Buffer.from('PNG\r\n')])]) {
    const r = await pedir('/estudios/upload', { headers: { ...cab(), 'content-type': 'application/pdf' }, cuerpo: malo });
    assert.equal(r.status, 400);
  }
  const roto = await subir({}, Buffer.from([0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff, 1, 2, 3]));
  assert.equal(roto.status, 400);
  assert.equal(db.objetos.size, 0);
  vivo();
});

test('token caído es 401; cuenta sin la función, 403; envío ajeno, 404; envío cerrado, 409', async () => {
  assert.equal((await subir({ 'x-estudios-token': 'token-que-no-existe-0000000000' })).status, 401);
  assert.equal((await subir({ 'x-estudios-token': 'corto' })).status, 401);
  assert.equal((await subir({ 'x-estudios-envio': ENV_B })).status, 404, 'el envío de otro alumno no existe para este token');
  db.habilitado = false;
  assert.equal((await subir()).status, 403);
  db.habilitado = true;
  db.envios.get(ENV_A).estado = 'enviado';
  assert.equal((await subir()).status, 409);
  assert.equal(db.objetos.size, 0);
});

test('ids inválidos, sin largo y demasiado grande', async () => {
  assert.equal((await subir({ 'x-estudios-envio': '../../x' })).status, 400);
  assert.equal((await subir({ 'x-estudios-archivo': 'no-es-uuid' })).status, 400);
  const grande = await pedir('/estudios/upload', { headers: { ...cab(), 'content-length': 21 * 1024 * 1024 }, cuerpo: Buffer.from('%PDF-') });
  assert.equal(grande.status, 413);
  vivo();
});

test('el tope de 20 archivos lo da la base', async () => {
  for (let i = 0; i < 20; i++) db.archivos.set(randomUUID(), { envio_id: ENV_A });
  assert.equal((await subir()).status, 413);
});

test('una falla nuestra nunca es 4xx: la cola del teléfono reintenta', async () => {
  fallar(/rpc\/mypump_get_cliente_info/, 500, 1);
  assert.equal((await subir()).status, 503);
  fallar(/rpc\/mypump_estudios_archivo_puede/, 500, 1);
  assert.equal((await subir()).status, 503);
  fallar(/POST \/storage\/v1\/object\/estudios\//, 500, 1);
  assert.equal((await subir()).status, 502);
  fallar(/rpc\/mypump_estudios_archivo_registrar/, 500, 1);
  assert.equal((await subir()).status, 502);
  assert.equal((await subir()).status, 200);
  vivo();
});

test('si el envío se cerró mientras subía, el objeto se saca', async () => {
  const id = randomUUID();
  const viejo = rpcRegistrarCierra();
  const r = await subir({ 'x-estudios-archivo': id });
  viejo();
  assert.equal(r.status, 409);
  assert.equal(db.objetos.size, 0);
});
function rpcRegistrarCierra() {      // el primer «puede» dice ok y, antes de registrar, el envío pasa a enviado
  const e = db.envios.get(ENV_A);
  let n = 0;
  const original = Object.getOwnPropertyDescriptor(e, 'estado');
  Object.defineProperty(e, 'estado', { configurable: true, get() { n += 1; return n <= 1 ? 'borrador' : 'enviado'; } });
  return () => Object.defineProperty(e, 'estado', original);
}

test('urls: firma solo lo que dice la base, 10 minutos, en el bucket de la clase y con nombre neutro', async () => {
  const id = randomUUID();
  db.paths = { resultado: 'ok', bucket: 'analisis', archivos: [{ path: 'cli-a/2026-11-03_lab_PEREZ JUAN_ab12.pdf', mime: 'application/pdf' }, { path: 'cli-a/2026-11-03_foto_cd34.jpg', mime: 'image/jpeg' }] };
  const r = await urls({ token: TOK_A, clase: 'estudio', id });
  assert.equal(r.status, 200);
  assert.equal(r.json.expira_en, 600);
  assert.deepEqual(r.json.archivos.map((a) => a.mime), ['application/pdf', 'image/jpeg']);
  assert.ok(r.json.archivos[0].url.endsWith('&download=estudio-1.pdf'));
  assert.ok(r.json.archivos[1].url.endsWith('&download=estudio-2.jpg'));
  assert.deepEqual(db.firmas, [{ bucket: 'analisis', expiresIn: 600, paths: db.paths.archivos.map((a) => a.path) }]);
  assert.deepEqual(db.pedidos, [`firmar cli-a estudio ${id}`], 'el cliente sale del token');
});

test('urls de una orden: bucket estudios y carpeta de la cuenta', async () => {
  const p = `o/${carp('cli-a')}/${randomUUID()}.pdf`;
  db.paths = { resultado: 'ok', bucket: 'estudios', archivos: [{ path: p, mime: 'application/pdf' }] };
  const r = await urls({ token: TOK_A, clase: 'orden', id: randomUUID() });
  assert.equal(r.status, 200);
  assert.deepEqual(db.firmas[0], { bucket: 'estudios', expiresIn: 600, paths: [p] });
});

test('urls: si la base devolviera un path de otra carpeta o de otro bucket, no se firma', async () => {
  for (const mal of [
    { resultado: 'ok', bucket: 'analisis', archivos: [{ path: 'cli-b/2026_x.pdf', mime: 'application/pdf' }] },
    { resultado: 'ok', bucket: 'analisis', archivos: [{ path: 'cli-a/../cli-b/x.pdf', mime: 'application/pdf' }] },
    { resultado: 'ok', bucket: 'progreso', archivos: [{ path: 'cli-a/x.pdf', mime: 'application/pdf' }] },
    { resultado: 'ok', bucket: 'analisis', archivos: [{ path: 'https://otro.supabase.co/x.pdf', mime: 'application/pdf' }] },
    { resultado: 'ok', bucket: 'analisis', archivos: [] },
  ]) {
    db.paths = mal;
    assert.equal((await urls({ token: TOK_A, clase: 'estudio', id: randomUUID() })).status, 502);
  }
  db.paths = { resultado: 'ok', bucket: 'estudios', archivos: [{ path: `o/${carp('cli-b')}/${randomUUID()}.pdf`, mime: 'application/pdf' }] };
  assert.equal((await urls({ token: TOK_A, clase: 'orden', id: randomUUID() })).status, 502);
  assert.equal(db.firmas.length, 0);
  vivo();
});

test('urls: negativas de la base y pedidos inválidos', async () => {
  db.paths = { resultado: 'todavia_no' };
  const r = await urls({ token: TOK_A, clase: 'estudio', id: randomUUID() });
  assert.deepEqual([r.status, r.json.error], [409, 'todavia_no']);
  db.paths = { resultado: 'no_encontrado' };
  assert.equal((await urls({ token: TOK_A, clase: 'orden', id: randomUUID() })).status, 404);
  db.paths = { resultado: 'no_habilitado' };
  assert.equal((await urls({ token: TOK_A, clase: 'orden', id: randomUUID() })).status, 403);
  assert.equal((await urls({ token: 'token-que-no-existe-0000000000', clase: 'orden', id: randomUUID() })).status, 401);
  assert.equal((await urls({ token: TOK_A, clase: 'receta', id: randomUUID() })).status, 400);
  assert.equal((await urls({ token: TOK_A, clase: 'estudio', id: 'cli-b/x.pdf' })).status, 400);
  db.paths = { resultado: 'no_encontrado' };
  assert.equal((await urls({ token: TOK_A, clase: 'estudio', id: randomUUID(), path: 'cli-b/x.pdf' })).status, 404, 'un path en el pedido se ignora');
  assert.equal(db.firmas.length, 0);
  vivo();
});

test('preflight de la web: CORS con los encabezados x-estudios-*', async () => {
  const r = await pedir('/estudios/upload', { metodo: 'OPTIONS', headers: { origin: 'https://app.mypumpteam.com' } });
  assert.equal(r.status, 204);
  for (const h of ['x-estudios-token', 'x-estudios-envio', 'x-estudios-archivo']) assert.ok(String(r.headers['access-control-allow-headers']).toLowerCase().includes(h), h);
  vivo();
});

test('lo demás del servicio sigue vivo', async () => {
  const s = await new Promise((resolve) => { request({ host: '127.0.0.1', port: puerto, path: '/health', agent: false }, (x) => { x.resume(); x.on('end', () => resolve(x.statusCode)); }).on('error', () => resolve(0)).end(); });
  assert.equal(s, 200); vivo();
});
