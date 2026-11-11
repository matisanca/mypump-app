// Prueba los endpoints propuestos pegados al server.mjs REAL contra un doble local de PostgREST y Storage. No habla con
// ningún servicio vivo: SUPABASE_URL apunta a 127.0.0.1 y HOME a una carpeta temporal.
//   node --test supabase/propuestas/nativa_chat_adjuntos_minivision.test.mjs
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
const carp = (id) => createHash('sha256').update(`chat:${id}`).digest('hex').slice(0, 32);

let TOK_A, TOK_B, corrida = 0, db;
function reiniciarDb() {
  corrida += 1;
  TOK_A = `token-del-alumno-a-${corrida}-0000000`;
  TOK_B = `token-del-alumno-b-${corrida}-0000000`;
  db = {
    clientes: new Map([[TOK_A, 'cli-a'], [TOK_B, 'cli-b']]),
    habilitados: new Set(['cli-a', 'cli-b']),
    adjuntos: new Map(), objetos: new Map(), fallos: [], pedidos: [], hoyPorCliente: new Map(), tokenCaido: false,
    apagarAlRegistrar: false,
  };
}
function fallar(patron, tipo, veces = Infinity) { db.fallos.push({ patron, tipo, veces }); }

function puede(c, id) {
  const ya = db.adjuntos.get(id);
  if (ya) return ya.cliente_id === c ? 'ya' : 'ajena';
  if (!db.habilitados.has(c)) return 'no_habilitado';
  if ([...db.adjuntos.values()].filter((a) => a.cliente_id === c).length >= (db.topeDb ?? 30)) return 'tope';
  return 'ok';
}
function rpc(fn, b) {
  switch (fn) {
    case 'mypump_get_cliente_info': { const c = db.clientes.get(b.p_token); return c ? [{ cliente_id: c }] : []; }
    case 'mypump_chat_adjunto_puede': return puede(b.p_cliente_id, b.p_id);
    case 'mypump_chat_adjunto_registrar': {
      if (db.apagarAlRegistrar) db.habilitados.clear();
      const p = puede(b.p_cliente_id, b.p_id);
      if (p === 'ya') { const a = db.adjuntos.get(b.p_id); return { resultado: 'ya', comentario_id: a.comentario_id, created_at: a.created_at }; }
      if (p !== 'ok') return { resultado: p };
      const a = { ...b, cliente_id: b.p_cliente_id, comentario_id: randomUUID(), created_at: new Date().toISOString(), borrado: false };
      db.adjuntos.set(b.p_id, a);
      return { resultado: 'ok', comentario_id: a.comentario_id, created_at: a.created_at };
    }
    case 'mypump_chat_adjuntos_paths':
      return b.p_ids.map((i) => db.adjuntos.get(i)).filter((a) => a && a.cliente_id === b.p_cliente_id && !a.borrado)
        .map((a) => ({ id: a.p_id, tipo: a.p_tipo, path: a.p_path, mime: a.p_mime }));
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
  if (url.pathname === '/storage/v1/object/sign/chat-adjuntos') return contestar(200, json().paths.map((p) => ({ path: p, signedURL: `/object/sign/chat-adjuntos/${p}?token=firmado` })));
  if (url.pathname === '/storage/v1/object/chat-adjuntos' && req.method === 'DELETE') { for (const p of json().prefixes) db.objetos.delete(p); return contestar(200, []); }
  if (url.pathname.startsWith('/storage/v1/object/chat-adjuntos/')) {
    db.objetos.set(url.pathname.slice('/storage/v1/object/chat-adjuntos/'.length), { buf: crudo, tipo: req.headers['content-type'] });
    return contestar(200, { Key: 'ok' });
  }
  contestar(404, { message: `sin ruta ${id}` });
});

let hijo, puerto, puertoDoble, salida = '', murio = null, dir;
function armarServidor(d) {
  if (process.env.SERVIDOR_FINAL) {
    const f = join(d, 'server.mjs');
    writeFileSync(f, readFileSync(process.env.SERVIDOR_FINAL));
    return f;
  }
  let s = readFileSync(join(aqui, '../../mini-vision/server.mjs'), 'utf8');
  const tope = "const tope = feature === 'fotos' ? RATE_FOTOS : RATE_LIMIT;";
  assert.ok(s.includes(tope));
  s = s.replace(tope, "const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'chat' ? RATE_CHAT : RATE_LIMIT;");
  const cors = "headers['Access-Control-Allow-Headers'] = 'Content-Type';";
  assert.ok(s.includes(cors));
  s = s.replace(cors, "headers['Access-Control-Allow-Headers'] = 'Content-Type, x-chat-token, x-chat-id, x-chat-tipo, x-chat-duracion';");
  const ruta = "  if (req.method !== 'POST' || req.url !== '/vision')";
  assert.ok(s.includes(ruta));
  s = s.replace(ruta, `  if (req.method === 'POST' && req.url === '/chat/adjunto') return handleChatAdjunto(req, res, origin);
  if (req.method === 'POST' && req.url === '/chat/urls')    return handleChatUrls(req, res, origin);
${ruta}`);
  s += `\n${readFileSync(join(aqui, 'nativa_chat_adjuntos_minivision.mjs'), 'utf8')}`;
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
  dir = mkdtempSync(join(tmpdir(), 'chat-minivision-'));
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
beforeEach(() => reiniciarDb());

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

// Un JPEG chico pero con la forma real: SOI, APP0 JFIF, APP1 EXIF (con «GPS» adentro), COM, APP2 ICC, DQT, SOS, datos, EOI.
function seg(marca, contenido) {
  const b = Buffer.alloc(4); b[0] = 0xff; b[1] = marca; b.writeUInt16BE(contenido.length + 2, 2);
  return Buffer.concat([b, contenido]);
}
const JFIF = seg(0xe0, Buffer.from('JFIF\0\x01\x01\0\0\x01\0\x01\0\0', 'latin1'));
const EXIF = seg(0xe1, Buffer.from('Exif\0\0GPSLatitude-34.6 Longitude-58.4 iPhone de Alguien', 'latin1'));
const COM = seg(0xfe, Buffer.from('comentario con un nombre', 'latin1'));
const ICC = seg(0xe2, Buffer.from('ICC_PROFILE\0perfil', 'latin1'));
const DQT = seg(0xdb, Buffer.alloc(65, 1));
const SOS = Buffer.concat([seg(0xda, Buffer.alloc(10, 2)), Buffer.alloc(3000, 7), Buffer.from([0xff, 0xd9])]);
const fotoConExif = Buffer.concat([Buffer.from([0xff, 0xd8]), JFIF, EXIF, COM, ICC, DQT, SOS]);
const m4a = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypM4A \0\0\0\0', 'latin1'), Buffer.alloc(4000, 3)]);
const webm = Buffer.concat([Buffer.from([0x1a, 0x45, 0xdf, 0xa3]), Buffer.alloc(3000, 4)]);
const ogg = Buffer.concat([Buffer.from('OggS', 'latin1'), Buffer.alloc(3000, 5)]);

const cab = (over = {}) => ({ 'x-chat-token': TOK_A, 'x-chat-id': randomUUID(), 'x-chat-tipo': 'foto', ...over });
const subir = (over = {}, b = fotoConExif) => pedir('/chat/adjunto', { headers: cab(over), cuerpo: b });
const urls = (o) => pedir('/chat/urls', { cuerpo: Buffer.from(JSON.stringify(o)) });
function vivo() { assert.equal(murio, null, `el proceso murió:\n${salida.slice(-800)}`); }
const subidas = () => db.pedidos.filter((p) => p.startsWith('POST /storage/v1/object/chat-adjuntos/')).length;

test('foto: se guarda en la carpeta con hash, sin EXIF ni comentarios, y crea el mensaje', async () => {
  const id = randomUUID();
  const r = await subir({ 'x-chat-id': id });
  assert.equal(r.status, 200, JSON.stringify(r.json));
  assert.equal(r.json.ok, true); assert.equal(r.json.ya, false); assert.ok(r.json.comentario_id);
  const path = `${carp('cli-a')}/${id}.jpg`;
  const o = db.objetos.get(path);
  assert.ok(o, [...db.objetos.keys()].join());
  assert.equal(o.tipo, 'image/jpeg');
  const s = o.buf.toString('latin1');
  assert.ok(!s.includes('GPS') && !s.includes('iPhone') && !s.includes('comentario'), 'quedaron metadatos');
  assert.ok(s.includes('JFIF') && s.includes('ICC_PROFILE'), 'se perdió JFIF o ICC');
  assert.ok(o.buf.subarray(-2).equals(Buffer.from([0xff, 0xd9])));
  assert.equal(o.buf.length, fotoConExif.length - EXIF.length - COM.length);
  const a = db.adjuntos.get(id);
  assert.equal(a.p_path, path); assert.equal(a.p_mime, 'image/jpeg'); assert.equal(a.p_bytes, o.buf.length); assert.equal(a.p_duracion_s, null);
  assert.ok(!path.includes('cli-a'));
  vivo();
});

test('reintento del mismo id: ya, el mismo mensaje, sin volver a subir', async () => {
  const id = randomUUID();
  const r1 = await subir({ 'x-chat-id': id });
  const n = subidas();
  const r2 = await subir({ 'x-chat-id': id });
  assert.equal(r2.status, 200); assert.equal(r2.json.ya, true); assert.equal(r2.json.comentario_id, r1.json.comentario_id);
  assert.equal(subidas(), n);
  vivo();
});

test('audio m4a, webm y ogg: el tipo sale de los bytes', async () => {
  for (const [b, mime, ext] of [[m4a, 'audio/mp4', 'm4a'], [webm, 'audio/webm', 'webm'], [ogg, 'audio/ogg', 'ogg']]) {
    const id = randomUUID();
    const r = await subir({ 'x-chat-id': id, 'x-chat-tipo': 'audio', 'x-chat-duracion': '42.4' }, b);
    assert.equal(r.status, 200, JSON.stringify(r.json));
    const a = db.adjuntos.get(id);
    assert.equal(a.p_mime, mime); assert.equal(a.p_duracion_s, 42.4); assert.ok(a.p_path.endsWith(`.${ext}`));
    assert.ok(db.objetos.get(a.p_path).buf.equals(b));
  }
  vivo();
});

test('rechazos legibles antes de leer el cuerpo (el teléfono ve el 4xx, no un corte)', async () => {
  const grande = Buffer.alloc(3 * 1024 * 1024 + 10, 1);
  const casos = [
    [{ 'x-chat-id': 'no-uuid' }, fotoConExif, 400],
    [{ 'x-chat-tipo': 'video' }, fotoConExif, 400],
    [{ 'x-chat-tipo': 'audio' }, m4a, 400],
    [{ 'x-chat-tipo': 'audio', 'x-chat-duracion': 'NaN' }, m4a, 400],
    [{ 'x-chat-tipo': 'audio', 'x-chat-duracion': '200' }, m4a, 413],
    [{}, grande, 413],
    [{ 'x-chat-token': 'token-que-no-existe-0000000' }, fotoConExif, 403],
  ];
  for (const [over, b, st] of casos) {
    const r = await subir(over, b);
    assert.equal(r.status, st, `${JSON.stringify(over)} → ${r.status} ${JSON.stringify(r.json)}`);
    assert.equal(r.json.ok, false); assert.ok(r.json.error);
  }
  assert.equal(subidas(), 0); assert.equal(db.adjuntos.size, 0);
  vivo();
});

test('la palanca, el tope y la cuenta ajena', async () => {
  db.habilitados.delete('cli-a');
  let r = await subir();
  assert.equal(r.status, 403); assert.equal(r.json.error, 'no habilitado');
  db.habilitados.add('cli-a');
  const id = randomUUID();
  await subir({ 'x-chat-id': id, 'x-chat-token': TOK_B });
  r = await subir({ 'x-chat-id': id });
  assert.equal(r.status, 409);
  db.topeDb = 0;
  r = await subir();
  assert.equal(r.status, 429);
  db.topeDb = undefined;
  assert.equal(subidas(), 1);
  vivo();
});

test('lo que no es lo que dice: 400 sin guardar', async () => {
  let r = await subir({}, m4a);
  assert.equal(r.status, 400); assert.match(r.json.error, /JPEG/);
  r = await subir({ 'x-chat-tipo': 'audio', 'x-chat-duracion': '3' }, Buffer.alloc(500, 9));
  assert.equal(r.status, 400); assert.match(r.json.error, /formato/);
  r = await subir({}, fotoConExif.subarray(0, 40));
  assert.equal(r.status, 400); assert.match(r.json.error, /no se puede leer/);
  assert.equal(subidas(), 0); assert.equal(db.adjuntos.size, 0);
  vivo();
});

test('fallas nuestras son 5xx: storage, registrar, token con Supabase caído', async () => {
  fallar(/^POST \/storage\/v1\/object\/chat-adjuntos\//, 500, 1);
  let r = await subir();
  assert.equal(r.status, 502); assert.equal(db.adjuntos.size, 0);
  const id = randomUUID();
  fallar(/mypump_chat_adjunto_registrar/, 500, 1);
  r = await subir({ 'x-chat-id': id });
  assert.equal(r.status, 502);
  r = await subir({ 'x-chat-id': id });            // el reintento de la cola entra
  assert.equal(r.status, 200); assert.equal(r.json.ya, false);
  fallar(/mypump_get_cliente_info/, 500, 1);
  r = await subir();
  assert.equal(r.status, 503);
  fallar(/mypump_chat_adjunto_puede/, 'red', 1);
  r = await subir();
  assert.equal(r.status, 503);
  vivo();
});

test('si se apaga mientras sube, no queda el archivo', async () => {
  db.apagarAlRegistrar = true;
  const r = await subir();
  assert.equal(r.status, 403);
  assert.equal(db.objetos.size, 0);
  vivo();
});

test('urls: solo las propias, firmadas, nunca un path del pedido', async () => {
  const ids = [];
  for (let i = 0; i < 2; i++) { const id = randomUUID(); await subir({ 'x-chat-id': id }); ids.push(id); }
  const ajeno = randomUUID(); await subir({ 'x-chat-id': ajeno, 'x-chat-token': TOK_B });
  let r = await urls({ token: TOK_A, ids: [...ids, ajeno, randomUUID()] });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json.adjuntos.map((a) => a.id).sort(), [...ids].sort());
  assert.ok(r.json.adjuntos.every((a) => a.url.includes('/storage/v1/object/sign/chat-adjuntos/') && a.tipo === 'foto' && !('path' in a)));
  r = await urls({ token: TOK_A, ids: ['../../otro'] });
  assert.equal(r.status, 400);
  r = await urls({ token: TOK_A, ids: Array.from({ length: 61 }, () => randomUUID()) });
  assert.equal(r.status, 400);
  r = await urls({ token: 'token-que-no-existe-0000000', ids });
  assert.equal(r.status, 403);
  r = await urls({ token: TOK_A, ids: [] });
  assert.equal(r.status, 400);
  vivo();
});

test('preflight de la web: CORS con los encabezados x-chat-*', async () => {
  const r = await pedir('/chat/adjunto', { metodo: 'OPTIONS', headers: { origin: 'https://app.mypumpteam.com' } });
  assert.equal(r.status, 204);
  assert.match(r.headers['access-control-allow-headers'], /x-chat-token/);
  assert.match(r.headers['access-control-allow-headers'], /x-chat-duracion/);
  const r2 = await subir({ origin: 'https://app.mypumpteam.com' });
  assert.equal(r2.headers['access-control-allow-origin'], 'https://app.mypumpteam.com');
});

test('el log no lleva ids ni nombres', async () => {
  const id = randomUUID();
  await subir({ 'x-chat-id': id });
  assert.ok(!salida.includes(id) && !salida.includes('cli-a'), salida.slice(-400));
  const r = await pedir('/health', { metodo: 'GET' });
  assert.equal(r.status, 200);
  vivo();
});
