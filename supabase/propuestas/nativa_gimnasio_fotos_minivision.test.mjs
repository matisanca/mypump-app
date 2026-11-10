// Prueba los endpoints propuestos pegados al server.mjs REAL, con el binario de tapado REAL, contra un doble local de PostgREST
// y Storage. No habla con ningún servicio vivo: SUPABASE_URL apunta a 127.0.0.1 y HOME a una carpeta temporal.
//   node --test supabase/propuestas/nativa_gimnasio_fotos_minivision.test.mjs
import { connect as conectarTcp } from 'node:net';
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const aqui = dirname(fileURLToPath(import.meta.url));
const exec = promisify(execFile);
const espera = (ms) => new Promise((r) => setTimeout(r, ms));
const carp = (id) => createHash('sha256').update(`gimnasio:${id}`).digest('hex').slice(0, 32);

let TOK_A, TOK_B, GIM_A, GIM_B, corrida = 0, db;
function reiniciarDb() {
  corrida += 1;
  TOK_A = `token-del-alumno-a-${corrida}-0000000`;
  TOK_B = `token-del-alumno-b-${corrida}-0000000`;
  GIM_A = randomUUID(); GIM_B = randomUUID();
  db = {
    clientes: new Map([[TOK_A, 'cli-a'], [TOK_B, 'cli-b']]),
    habilitado: true,
    gimnasios: new Map([[GIM_A, { cliente: 'cli-a', estado: 'borrador', fotoPedida: false }], [GIM_B, { cliente: 'cli-b', estado: 'borrador', fotoPedida: false }]]),
    fotos: new Map(), objetos: new Map(), fallos: [], retenidos: [], pedidos: [],
  };
}
function fallar(patron, tipo, veces = Infinity) { db.fallos.push({ patron, tipo, veces }); }
function retener(patron) {
  let soltar; const hecho = new Promise((r) => { soltar = r; });
  let llego; const llegada = new Promise((r) => { llego = r; });
  db.retenidos.push({ patron, hecho, llego, usado: false });
  return { soltar, llegada };
}
function puede(c, g, f) {
  const x = db.gimnasios.get(g);
  if (!x || x.cliente !== c) return 'no_encontrado';
  const ya = db.fotos.get(f);
  if (ya?.gimnasio_id === g) return 'ya';
  if (ya) return 'ajena';
  if (!db.habilitado) return 'no_habilitado';
  const n = (r) => [...db.fotos.values()].filter((v) => v.gimnasio_id === g && v.ronda === r).length;
  if (x.estado === 'borrador') return n(0) >= 80 ? 'tope' : 'ok';
  if (x.estado === 'a_confirmar' && x.fotoPedida) return n(1) >= 9 ? 'tope' : 'ok';
  return 'estado';
}
function rpc(fn, b) {
  switch (fn) {
    case 'mypump_get_cliente_info': { const c = db.clientes.get(b.p_token); return c ? [{ cliente_id: c }] : []; }
    case 'mypump_gimnasio_foto_puede': return puede(b.p_cliente_id, b.p_gimnasio_id, b.p_foto_id);
    case 'mypump_gimnasio_foto_registrar': {
      const p = puede(b.p_cliente_id, b.p_gimnasio_id, b.p_foto_id);
      if (p !== 'ok') return p;
      db.fotos.set(b.p_foto_id, { id: b.p_foto_id, gimnasio_id: b.p_gimnasio_id, cliente_id: b.p_cliente_id, zona: b.p_zona, path: b.p_path, bytes: b.p_bytes, caras: b.p_caras, borde: b.p_borde_blanco, ronda: db.gimnasios.get(b.p_gimnasio_id).estado === 'borrador' ? 0 : 1, descartada: false });
      return 'ok';
    }
    case 'mypump_gimnasio_foto_borrar': {
      const f = db.fotos.get(b.p_foto_id);
      if (!f || f.cliente_id !== b.p_cliente_id) return { resultado: 'no_encontrado' };
      const x = db.gimnasios.get(f.gimnasio_id);
      if (!(x.estado === 'borrador' || (x.estado === 'a_confirmar' && f.ronda === 1))) return { resultado: 'estado' };
      db.fotos.delete(b.p_foto_id);
      return { resultado: 'ok', path: f.path };
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
  for (const r of db.retenidos) if (!r.usado && r.patron.test(id)) { r.usado = true; r.llego(); await r.hecho; }
  const f = db.fallos.find((x) => x.veces > 0 && x.patron.test(id));
  if (f) { f.veces -= 1; if (f.tipo === 'red') return req.socket.destroy(); return contestar(f.tipo, { message: 'falla inyectada' }); }
  const json = () => (crudo.length ? JSON.parse(crudo.toString()) : {});
  if (url.pathname.startsWith('/rest/v1/rpc/')) return contestar(200, rpc(url.pathname.split('/').pop(), json()));
  if (url.pathname === '/rest/v1/mypump_gimnasio_fotos' && req.method === 'GET') {
    const f2 = {};
    for (const [k, v] of url.searchParams) if (v.startsWith('eq.')) f2[k] = v.slice(3);
    return contestar(200, [...db.fotos.values()].filter((r) => Object.entries(f2).every(([k, v]) => String(r[k]) === v)).map(({ id: i, zona, path }) => ({ id: i, zona, path })));
  }
  if (url.pathname === '/rest/v1/mypump_gimnasio_fotos' && req.method === 'DELETE') { db.fotos.clear(); return contestar(200, []); }
  if (url.pathname === '/storage/v1/object/sign/gimnasio') return contestar(200, json().paths.map((p) => ({ path: p, signedURL: `/object/sign/gimnasio/${p}?token=firmado` })));
  if (url.pathname === '/storage/v1/object/list/gimnasio') {
    const p = (json().prefix ?? '').replace(/\/$/, ''), nivel = new Map();
    for (const k of db.objetos.keys()) {
      if (p && !k.startsWith(`${p}/`)) continue;
      const resto = p ? k.slice(p.length + 1) : k, i = resto.indexOf('/');
      nivel.set(i < 0 ? resto : resto.slice(0, i), { name: i < 0 ? resto : resto.slice(0, i), id: i < 0 ? 'obj' : null });
    }
    return contestar(200, [...nivel.values()].sort((a, b) => a.name.localeCompare(b.name)).slice(json().offset ?? 0, (json().offset ?? 0) + (json().limit ?? 100)));
  }
  if (url.pathname === '/storage/v1/object/gimnasio' && req.method === 'DELETE') { for (const p of json().prefixes) db.objetos.delete(p); return contestar(200, []); }
  if (url.pathname.startsWith('/storage/v1/object/gimnasio/')) { db.objetos.set(url.pathname.slice('/storage/v1/object/gimnasio/'.length), crudo); return contestar(200, { Key: 'ok' }); }
  if (url.pathname === '/storage/v1/bucket/gimnasio' && req.method === 'DELETE') { db.bucket = false; return contestar(200, {}); }
  contestar(404, { message: `sin ruta ${id}` });
});

let hijo, puerto, puertoDoble, salida = '', murio = null, dir, tapar, generar, control, tmpServidor, foto, fotoGrande;
function armarServidor(d) {
  if (process.env.SERVIDOR_FINAL) {   // la versión final armada para producción, tal cual
    const f = join(d, 'server.mjs');
    writeFileSync(f, readFileSync(process.env.SERVIDOR_FINAL));
    return f;
  }
  let s = readFileSync(join(aqui, '../../mini-vision/server.mjs'), 'utf8');
  const tope = "const tope = feature === 'fotos' ? RATE_FOTOS : RATE_LIMIT;";
  assert.ok(s.includes(tope));
  s = s.replace(tope, "const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'gimnasio' ? RATE_GIMNASIO : RATE_LIMIT;");
  const cors = "headers['Access-Control-Allow-Headers'] = 'Content-Type';";
  assert.ok(s.includes(cors));
  s = s.replace(cors, "headers['Access-Control-Allow-Headers'] = 'Content-Type, x-gimnasio-token, x-gimnasio-id, x-gimnasio-foto, x-gimnasio-zona';");
  const ruta = "  if (req.method !== 'POST' || req.url !== '/vision')";
  assert.ok(s.includes(ruta));
  s = s.replace(ruta, `  if (req.method === 'POST' && req.url === '/gimnasio/upload') return handleGimnasioUpload(req, res, origin);
  if (req.method === 'POST' && req.url === '/gimnasio/urls')   return handleGimnasioUrls(req, res, origin);
  if (req.method === 'POST' && req.url === '/gimnasio/borrar') return handleGimnasioBorrar(req, res, origin);
${ruta}`);
  s += `\n${readFileSync(join(aqui, 'nativa_gimnasio_fotos_minivision.mjs'), 'utf8')}`;
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
  dir = mkdtempSync(join(tmpdir(), 'gim-minivision-'));
  tmpServidor = join(dir, 'tmp'); (await import('node:fs')).mkdirSync(tmpServidor);
  // En la Mini swiftc no compila: ahí se pasan los binarios ya armados en la MacBook.
  const real = process.env.TAPAR_PRECOMPILADO || join(dir, 'tapar-real'); generar = process.env.GENERAR_PRECOMPILADO || join(dir, 'generar');
  if (!process.env.TAPAR_PRECOMPILADO) await exec('swiftc', ['-O', '-o', real, join(aqui, 'gimnasio_tapar_caras/tapar_caras.swift')], { timeout: 180000 });
  if (!process.env.GENERAR_PRECOMPILADO) await exec('swiftc', ['-O', '-o', generar, join(aqui, 'gimnasio_tapar_caras/generar_prueba.swift')], { timeout: 180000 });
  // Envoltorio: con el archivo de control, falla con ese código en vez de tapar.
  control = join(dir, 'control'); tapar = join(dir, 'tapar');
  writeFileSync(tapar, `#!/bin/sh\nif [ -f "${control}" ]; then c=$(cat "${control}"); [ "$c" = "colgar" ] && sleep 60; [ "$c" = "basura" ] && echo hola && exit 0; exit "$c"; fi\nexec "${real}" "$@"\n`);
  chmodSync(tapar, 0o755);
  const a = join(dir, 'a.jpg');
  await exec(generar, ['escribir', a, '2400', '1200', '6']);
  foto = readFileSync(a);
  puerto = await libre();
  hijo = spawn(process.execPath, [armarServidor(dir)], {
    env: { PATH: process.env.PATH, HOME: dir, TMPDIR: tmpServidor, PORT: String(puerto), SUPABASE_URL: `http://127.0.0.1:${puertoDoble}`, SUPABASE_SERVICE_KEY: 'clave-de-prueba', GIMNASIO_TAPAR_BIN: tapar },
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
beforeEach(() => { reiniciarDb(); rmSync(control, { force: true }); });

function pedir(ruta, { headers = {}, cuerpo, mandarCuerpo = true, metodo = 'POST' } = {}) {
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
    if (cuerpo !== undefined && mandarCuerpo) q.write(cuerpo);
    if (mandarCuerpo) q.end(); else q.flushHeaders();
  });
}
const cab = (over = {}) => ({ 'x-gimnasio-token': TOK_A, 'x-gimnasio-id': GIM_A, 'x-gimnasio-foto': randomUUID(), 'x-gimnasio-zona': 'piernas', ...over });
const subir = (over = {}, b = foto) => pedir('/gimnasio/upload', { headers: cab(over), cuerpo: b });
const jsonB = (o) => Buffer.from(JSON.stringify(o));
const urls = (o) => pedir('/gimnasio/urls', { cuerpo: jsonB(o) });
const borrar = (o) => pedir('/gimnasio/borrar', { cuerpo: jsonB(o) });
function vivo() { assert.equal(murio, null, `el proceso murió:\n${salida.slice(-800)}`); }
async function salud() {
  const s = await new Promise((resolve) => { request({ host: '127.0.0.1', port: puerto, path: '/health', agent: false }, (x) => { x.resume(); x.on('end', () => resolve(x.statusCode)); }).on('error', () => resolve(0)).end(); });
  assert.equal(s, 200); vivo();
}
const temporales = () => readdirSync(tmpServidor).filter((f) => f.startsWith('gimnasio-'));

test('sube: tapa, recodifica sin EXIF, y guarda con el path armado por el servidor', async () => {
  const id = randomUUID();
  const r = await subir({ 'x-gimnasio-foto': id });
  assert.deepEqual([r.status, r.json], [200, { ok: true }]);
  const path = `${carp('cli-a')}/${GIM_A}/${id}.jpg`;
  assert.deepEqual([...db.objetos.keys()], [path]);
  const guardado = db.objetos.get(path);
  assert.equal(guardado.includes('MARCA-SECRETA'), false);
  assert.equal(guardado.includes('Exif'), false, 'sin bloque Exif');
  assert.ok(foto.includes('MARCA-SECRETA-EXIF'), 'la foto de prueba sí lo traía');
  const f = db.fotos.get(id);
  assert.deepEqual([f.cliente_id, f.zona, f.path, f.bytes, f.caras], ['cli-a', 'piernas', path, guardado.length, 0]);
  assert.equal(typeof f.borde, 'number');
  assert.deepEqual(temporales(), [], 'no queda la foto original en disco');
});

test('aplica la orientación y reduce a 1600 px', async () => {
  const id = randomUUID();
  assert.equal((await subir({ 'x-gimnasio-foto': id })).status, 200);
  const p = join(dir, 'salida.jpg');
  writeFileSync(p, db.objetos.get(`${carp('cli-a')}/${GIM_A}/${id}.jpg`));
  const { stdout } = await exec(generar, ['metadatos', p]);
  assert.match(stdout, /sin-gps sin-orientacion sin-exif/);
  const { stdout: a } = await exec(generar, ['pixel', p, '799', '1599']);
  assert.match(a, /^\d+ \d+ \d+/, 'la imagen es 800 x 1600 (acostada y rotada)');
});

test('la carpeta del bucket no lleva el id de la cuenta', async () => {
  assert.equal((await subir()).status, 200);
  assert.ok(![...db.objetos.keys()][0].includes('cli-a'));
});

test('idempotente: el mismo id contesta ya, sin volver a procesar ni guardar', async () => {
  const id = randomUUID();
  assert.equal((await subir({ 'x-gimnasio-foto': id })).status, 200);
  const antes = db.pedidos.filter((p) => p.startsWith('POST /storage')).length;
  assert.deepEqual((await subir({ 'x-gimnasio-foto': id })).json, { ok: true, ya: true });
  assert.equal(db.pedidos.filter((p) => p.startsWith('POST /storage')).length, antes);
  assert.equal(db.fotos.size, 1);
});

test('el cliente sale del token: no puede subir a la carga de otro', async () => {
  const r = await subir({ 'x-gimnasio-token': TOK_B });
  assert.equal(r.status, 404);
  assert.equal(db.objetos.size, 0);
});

test('el id de una foto de otro no se pisa', async () => {
  const id = randomUUID();
  assert.equal((await subir({ 'x-gimnasio-foto': id })).status, 200);
  assert.equal((await subir({ 'x-gimnasio-foto': id, 'x-gimnasio-token': TOK_B, 'x-gimnasio-id': GIM_B })).status, 409);
  assert.equal(db.objetos.size, 1);
  assert.equal(db.fotos.get(id).cliente_id, 'cli-a');
});

test('rechazos sin guardar: zona, ids, JPEG falso, imagen rota', async () => {
  for (const over of [{ 'x-gimnasio-zona': 'cocina' }, { 'x-gimnasio-zona': '' }, { 'x-gimnasio-id': '../otra' }, { 'x-gimnasio-foto': 'nada' }]) assert.equal((await subir(over)).status, 400, JSON.stringify(over));
  assert.equal((await subir({}, Buffer.from('PNG no es'))).status, 400);
  const rota = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(200, 7)]);
  assert.equal((await subir({}, rota)).status, 400);
  assert.equal(db.objetos.size, 0);
  assert.deepEqual(temporales(), []);
});

test('sin token válido contesta sin esperar el cuerpo', async () => {
  const r = await pedir('/gimnasio/upload', { headers: { ...cab({ 'x-gimnasio-token': 'token-que-no-existe-000' }), 'content-length': 6_000_000 }, mandarCuerpo: false });
  assert.equal(r.status, 403);
  await salud();
});

test('sin largo o con largo de más no lee nada', async () => {
  assert.equal((await pedir('/gimnasio/upload', { headers: { ...cab(), 'transfer-encoding': 'chunked' } })).status, 411);
  assert.equal((await pedir('/gimnasio/upload', { headers: { ...cab(), 'content-length': 9 * 1024 * 1024 }, mandarCuerpo: false })).status, 413);
});

test('apagado por palanca: 403 y no guarda', async () => {
  db.habilitado = false;
  assert.equal((await subir()).status, 403);
  assert.equal(db.objetos.size, 0);
});

test('tope propio: 80 por carga, contando filas', async () => {
  for (let i = 0; i < 80; i++) { const u = randomUUID(); db.fotos.set(u, { id: u, gimnasio_id: GIM_A, cliente_id: 'cli-a', ronda: 0, path: `x/${u}`, zona: 'piernas' }); }
  assert.equal((await subir()).status, 413);
  assert.equal(db.objetos.size, 0);
});

test('tope del día por token, separado del de progreso', async () => {
  for (let i = 0; i < 150; i++) {
    const g = randomUUID();
    db.gimnasios.set(g, { cliente: 'cli-a', estado: 'borrador' });
    assert.equal((await subir({ 'x-gimnasio-id': g }, foto)).status, 200, `foto ${i}`);
  }
  assert.equal((await subir()).status, 429);
  assert.ok(db.objetos.size === 150);
});

test('una carga enviada ya no recibe fotos; la pedida en la confirmación sí', async () => {
  db.gimnasios.get(GIM_A).estado = 'enviado';
  assert.equal((await subir()).status, 409);
  db.gimnasios.get(GIM_A).estado = 'a_confirmar';
  assert.equal((await subir()).status, 409, 'sin pedido de foto');
  db.gimnasios.get(GIM_A).fotoPedida = true;
  const id = randomUUID();
  assert.equal((await subir({ 'x-gimnasio-foto': id })).status, 200);
  assert.equal(db.fotos.get(id).ronda, 1);
});

test('cambia a enviado mientras se guarda: saca el objeto y contesta 409', async () => {
  const r = retener(/POST \/storage\/v1\/object\/gimnasio\//);
  const sube = subir();
  await r.llegada;
  db.gimnasios.get(GIM_A).estado = 'enviado';
  r.soltar();
  assert.equal((await sube).status, 409);
  assert.equal(db.objetos.size, 0);
  assert.equal(db.fotos.size, 0);
});

test('una sola subida por cuenta a la vez, y el lugar se libera si el cliente se corta', async () => {
  const q = request({ host: '127.0.0.1', port: puerto, path: '/gimnasio/upload', method: 'POST', agent: false, headers: { ...cab(), 'content-length': foto.length * 2 } });
  q.on('error', () => {});
  q.write(foto.subarray(0, 8));
  await espera(100);
  assert.equal((await subir()).status, 429);
  q.destroy();
  await espera(100);
  assert.equal((await subir()).status, 200);
});

test('a la vez en todo el servicio: máximo dos', async () => {
  const c1 = request({ host: '127.0.0.1', port: puerto, path: '/gimnasio/upload', method: 'POST', agent: false, headers: { ...cab(), 'content-length': foto.length * 2 } });
  const c2 = request({ host: '127.0.0.1', port: puerto, path: '/gimnasio/upload', method: 'POST', agent: false, headers: { ...cab({ 'x-gimnasio-token': TOK_B, 'x-gimnasio-id': GIM_B }), 'content-length': foto.length * 2 } });
  for (const c of [c1, c2]) { c.on('error', () => {}); c.write(foto.subarray(0, 8)); }
  await espera(150);
  db.clientes.set('token-del-alumno-c-99999-0000000', 'cli-c');
  const g = randomUUID(); db.gimnasios.set(g, { cliente: 'cli-c', estado: 'borrador' });
  assert.equal((await subir({ 'x-gimnasio-token': 'token-del-alumno-c-99999-0000000', 'x-gimnasio-id': g })).status, 429);
  c1.destroy(); c2.destroy();
  await espera(100);
});

test('se corta a mitad del cuerpo: no guarda nada', async () => {
  const q = request({ host: '127.0.0.1', port: puerto, path: '/gimnasio/upload', method: 'POST', agent: false, headers: { ...cab(), 'content-length': foto.length } });
  q.on('error', () => {});
  q.write(foto.subarray(0, 3));
  await espera(80);
  q.destroy();
  await espera(80);
  assert.equal(db.objetos.size, 0);
  await salud();
});

// ── Fail-closed: sin tapar no se guarda ──
for (const [nombre, c, status] of [['falla Vision', '4', 503], ['no puede escribir', '3', 503], ['salida basura', 'basura', 503], ['no es imagen', '2', 400]]) {
  test(`binario: ${nombre} → ${status} y nada guardado`, async () => {
    writeFileSync(control, c);
    assert.equal((await subir()).status, status);
    assert.equal(db.objetos.size, 0);
    assert.equal(db.fotos.size, 0);
    assert.deepEqual(temporales(), []);
    await salud();
  });
}
test('sin binario: 503, nada guardado', { skip: false }, async () => {
  writeFileSync(control, '127');
  assert.equal((await subir()).status, 503);
  assert.equal(db.objetos.size, 0);
});

// ── Red y 5xx ──
for (const [nombre, tipo] of [['corte de red', 'red'], ['503', 503]]) {
  test(`${nombre} al validar el token: 503, no 403`, async () => {
    fallar(/mypump_get_cliente_info/, tipo);
    assert.equal((await subir()).status, 503);
    await salud();
  });
  test(`${nombre} en el chequeo: 503 y no guarda`, async () => {
    fallar(/mypump_gimnasio_foto_puede/, tipo);
    assert.equal((await subir()).status, 503);
    assert.equal(db.objetos.size, 0);
    await salud();
  });
  test(`${nombre} en Storage: 5xx, sin fila`, async () => {
    fallar(/POST \/storage\/v1\/object\/gimnasio\//, tipo);
    assert.ok((await subir()).status >= 500);
    assert.equal(db.fotos.size, 0);
    await salud();
  });
  test(`${nombre} al registrar: 502 y el reintento funciona`, async () => {
    const id = randomUUID();
    fallar(/mypump_gimnasio_foto_registrar/, tipo, 1);
    assert.equal((await subir({ 'x-gimnasio-foto': id })).status, 502);
    assert.equal(db.fotos.size, 0);
    assert.equal((await subir({ 'x-gimnasio-foto': id })).status, 200);
    assert.equal(db.fotos.size, 1);
    assert.equal(db.objetos.size, 1);
    await salud();
  });
  test(`${nombre} en urls y borrar: contesta y sigue vivo`, async () => {
    fallar(/mypump_gimnasio_foto_borrar|GET \/rest\/v1\/mypump_gimnasio_fotos/, tipo);
    assert.ok((await urls({ token: TOK_A, gimnasio_id: GIM_A })).status >= 500);
    assert.ok((await borrar({ token: TOK_A, foto_id: randomUUID() })).status >= 500);
    await salud();
  });
}
test('Supabase caído del todo: todas las rutas contestan y el proceso sigue', async () => {
  fallar(/.*/, 'red');
  assert.ok((await subir()).status >= 500);
  assert.ok((await urls({ token: TOK_A, gimnasio_id: GIM_A })).status >= 500);
  assert.ok((await borrar({ token: TOK_A, foto_id: randomUUID() })).status >= 500);
  await salud();
});

// ── URLs ──
test('urls: firma solo las de su carga, nunca un path del pedido', async () => {
  const id = randomUUID();
  assert.equal((await subir({ 'x-gimnasio-foto': id })).status, 200);
  const r = await urls({ token: TOK_A, gimnasio_id: GIM_A, path: 'otra/cosa.jpg', paths: ['otra/cosa.jpg'] });
  assert.equal(r.status, 200);
  assert.equal(r.json.fotos.length, 1);
  assert.equal(r.json.fotos[0].id, id);
  assert.ok(r.json.fotos[0].url.includes(`/storage/v1/object/sign/gimnasio/${carp('cli-a')}/`));
  assert.equal(r.json.fotos[0].path, undefined, 'el path no sale');
  assert.deepEqual((await urls({ token: TOK_B, gimnasio_id: GIM_A })).json.fotos, []);
});
test('urls: token e id inválidos', async () => {
  assert.equal((await urls({ token: 'token-que-no-existe-000', gimnasio_id: GIM_A })).status, 403);
  assert.equal((await urls({ token: TOK_A, gimnasio_id: 'x' })).status, 400);
  assert.equal((await pedir('/gimnasio/urls', { cuerpo: Buffer.from('{no') })).status, 400);
  for (const c of ['null', '0', '[]']) assert.equal((await pedir('/gimnasio/urls', { cuerpo: Buffer.from(c) })).status, 400, c);
});

// ── Borrar ──
test('borrar: saca fila y objeto; otra cuenta no puede; una carga enviada no se toca', async () => {
  const id = randomUUID(), otra = randomUUID();
  assert.equal((await subir({ 'x-gimnasio-foto': id })).status, 200);
  assert.equal((await subir({ 'x-gimnasio-foto': otra })).status, 200);
  assert.deepEqual((await borrar({ token: TOK_B, foto_id: id })).json, { ok: true, ya: true });
  assert.ok(db.fotos.has(id), 'la de otro sigue');
  assert.deepEqual((await borrar({ token: TOK_A, foto_id: id })).json, { ok: true });
  assert.equal(db.fotos.has(id), false);
  assert.equal(db.objetos.size, 1);
  db.gimnasios.get(GIM_A).estado = 'enviado';
  assert.equal((await borrar({ token: TOK_A, foto_id: otra })).status, 409);
  assert.equal(db.objetos.size, 1);
});

test('CORS: el preflight de la web deja pasar los encabezados', async () => {
  const r = await pedir('/gimnasio/upload', { metodo: 'OPTIONS', headers: { origin: 'capacitor://localhost' } });
  assert.equal(r.status, 204);
  assert.match(r.headers['access-control-allow-headers'], /x-gimnasio-token/);
  assert.match(r.headers['access-control-allow-headers'], /x-gimnasio-zona/);
});

// ── El reverso ──
const script = join(aqui, 'nativa_gimnasio_fotos_vaciar.mjs');
const correr = (...a) => exec(process.execPath, [script, ...a], { env: { PATH: process.env.PATH, SUPABASE_URL: `http://127.0.0.1:${puertoDoble}`, SUPABASE_SERVICE_KEY: 'clave-de-prueba' } });
test('el reverso vacía objetos y filas, y el bucket recién vacío', async () => {
  assert.equal((await subir()).status, 200);
  assert.match((await correr('vaciar')).stdout, /objetos: 1/);
  assert.equal(db.objetos.size, 1, 'sin --confirmar no borra');
  await assert.rejects(correr('bucket', '--confirmar'), /primero vaciar/);
  await correr('vaciar', '--confirmar');
  assert.equal(db.objetos.size, 0);
  assert.equal(db.fotos.size, 0);
  await correr('bucket', '--confirmar');
  assert.equal(db.bucket, false);
});

// El 4xx tiene que llegar legible con la subida a medio camino: cortar la conexión ahí lo vuelve un error de red en el navegador.
function rechazoEnCurso(headers, total) {
  return new Promise((resolve) => {
    const res = { status: 0, json: null, error: null, escribio: 0, cerroAntes: false };
    let t = '', listo = false;
    const s = conectarTcp(puerto, '127.0.0.1');
    const fin = () => {
      if (listo) return;
      listo = true; clearInterval(seguir); s.destroy();
      res.status = Number(/^HTTP\/1\.1 (\d+)/.exec(t)?.[1] || 0);
      try { res.json = JSON.parse(t.slice(t.indexOf('{'), t.lastIndexOf('}') + 1)); } catch { res.json = null; }
      resolve(res);
    };
    s.on('data', (c) => { t += c; });
    s.on('error', (e) => { res.error = e.code || e.message; });
    s.on('close', () => { res.cerroAntes = res.escribio < total; fin(); });
    const lineas = Object.entries({ ...headers, host: 'prueba', connection: 'keep-alive', 'content-length': total }).map(([k, v]) => `${k}: ${v}`).join('\r\n');
    s.write(`POST /gimnasio/upload HTTP/1.1\r\n${lineas}\r\n\r\n`);
    const seguir = setInterval(() => {
      if (res.escribio >= total) { clearInterval(seguir); setTimeout(fin, 150); return; }
      s.write(Buffer.alloc(64 * 1024)); res.escribio += 64 * 1024;
    }, 2);
  });
}

test('un 4xx llega legible con la subida en curso', async () => {
  const r = await rechazoEnCurso(cab({ 'x-gimnasio-token': 'token-que-no-existe' }), 2 * 1024 * 1024);
  assert.equal(r.error, null);
  assert.equal(r.status, 403);
  assert.equal(r.json?.ok, false);
  assert.equal(r.cerroAntes, false, 'el servidor no corta a mitad de la subida');
});

test('preflight del navegador: permite los encabezados', { skip: !process.env.SERVIDOR_FINAL }, async () => {
  const r = await new Promise((resolve) => {
    const q = request({ host: '127.0.0.1', port: puerto, path: '/gimnasio/upload', method: 'OPTIONS', headers: { origin: 'https://app.mypumpteam.com' }, agent: false }, (x) => { x.resume(); resolve(x); });
    q.end();
  });
  assert.equal(r.statusCode, 204);
  for (const h of ['x-gimnasio-token', 'x-gimnasio-id', 'x-gimnasio-foto', 'x-gimnasio-zona']) assert.ok(String(r.headers['access-control-allow-headers']).toLowerCase().includes(h), h);
});
