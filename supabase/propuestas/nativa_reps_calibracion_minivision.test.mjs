// Prueba los endpoints propuestos pegados al server.mjs REAL, contra un doble local de PostgREST y Storage. No habla con
// ningún servicio vivo: SUPABASE_URL apunta a 127.0.0.1 y HOME a una carpeta temporal.
//   node --test supabase/propuestas/nativa_reps_calibracion_minivision.test.mjs
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { createHash } from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const aqui = dirname(fileURLToPath(import.meta.url));
const exec = promisify(execFile);
// Tokens nuevos en cada test: el tope del día vive en la memoria del proceso.
let TOK_A, TOK_B, TOK_AUTO, TOK_BAJA, corrida = 0;
const carp = (id) => createHash('sha256').update(`reps:${id}`).digest('hex').slice(0, 32);
const espera = (ms) => new Promise((r) => setTimeout(r, ms));

// ── El doble ──
let db;
function reiniciarDb() {
  corrida += 1;
  TOK_A = `token-del-alumno-a-${corrida}-0000000`;
  TOK_B = `token-del-alumno-b-${corrida}-0000000`;
  TOK_AUTO = `token-automatico-${corrida}-000000`;
  TOK_BAJA = `token-dado-de-baja-${corrida}-0000`;
  db = {
    clientes: new Map([[TOK_A, { id: 'cli-a', activo: true }], [TOK_B, { id: 'cli-b', activo: true }], [TOK_AUTO, { id: 'cli-auto', activo: true }], [TOK_BAJA, { id: 'cli-baja', activo: false }]]),
    subida: new Map([['cli-auto', { automatica: true, acepta: null, pendiente: false }]]),
    filas: [],
    objetos: new Map(),
    fallos: [],
    retenidos: [],
    bucket: true,
    pedidos: [],
  };
}
// `tipo`: 'red' corta el socket; un número contesta ese status. `veces`: cuántas (Infinity por defecto).
function fallar(patron, tipo, veces = Infinity) { db.fallos.push({ patron, tipo, veces }); }
// Frena el pedido que coincida hasta llamar a lo que devuelve.
function retener(patron) {
  let soltar;
  const hecho = new Promise((r) => { soltar = r; });
  let llego;
  const llegada = new Promise((r) => { llego = r; });
  db.retenidos.push({ patron, hecho, llego, usado: false });
  return { soltar, llegada };
}
const rows = (url) => {
  const f = {};
  for (const [k, v] of url.searchParams) if (v.startsWith('eq.')) f[k] = v.slice(3);
  return db.filas.filter((r) => Object.entries(f).every(([k, v]) => String(r[k]) === v));
};
function rpc(fn, b) {
  const s = (id) => db.subida.get(id);
  switch (fn) {
    case 'mypump_get_cliente_info': { const c = db.clientes.get(b.p_token); return c?.activo ? [{ cliente_id: c.id }] : []; }
    case 'mypump_reps_puede_subir': { const x = s(b.p_cliente_id); return !!x && (x.automatica || (x.acepta === true && !x.pendiente)); }
    case 'mypump_reps_consentir': {
      const c = db.clientes.get(b.p_token);
      if (!c?.activo) return null;
      if (s(c.id)?.pendiente) return false;
      db.subida.set(c.id, { automatica: s(c.id)?.automatica ?? false, acepta: true, pendiente: false });
      return true;
    }
    case 'mypump_reps_revocar': {
      const c = db.clientes.get(b.p_token);
      if (!c) return null;
      if (s(c.id)?.automatica) return { cliente_id: c.id, automatica: true };
      db.subida.set(c.id, { automatica: false, acepta: false, pendiente: true });
      return { cliente_id: c.id, automatica: false };
    }
    case 'mypump_reps_para_borrar': {
      const ids = new Set([...db.subida].filter(([, v]) => v.pendiente).map(([k]) => k));
      for (const r of db.filas) { const v = s(r.cliente_id); if (v && v.acepta === false && !v.automatica) ids.add(r.cliente_id); }
      return [...ids];
    }
    case 'mypump_reps_borrado_hecho': { const x = s(b.p_cliente_id); if (x) x.pendiente = false; return true; }
    case 'mypump_reps_total_bytes': return db.filas.reduce((n, r) => n + r.bytes, 0);
    default: throw new Error(`rpc desconocida ${fn}`);
  }
}
function listar(prefijo, limit = 100, offset = 0) {
  const p = prefijo.replace(/\/$/, '');
  const nivel = new Map();
  for (const k of db.objetos.keys()) {
    if (p && !k.startsWith(`${p}/`)) continue;
    const resto = p ? k.slice(p.length + 1) : k;
    const i = resto.indexOf('/');
    if (i < 0) nivel.set(resto, { name: resto, id: 'obj' });
    else nivel.set(resto.slice(0, i), { name: resto.slice(0, i), id: null });
  }
  return [...nivel.values()].sort((a, b) => a.name.localeCompare(b.name)).slice(offset, offset + limit);
}
const doble = createServer(async (req, res) => {
  const partes = [];
  for await (const c of req) partes.push(c);
  const crudo = Buffer.concat(partes);
  const url = new URL(req.url, 'http://x');
  const id = `${req.method} ${url.pathname}`;
  db.pedidos.push(id);
  const contestar = (status, obj) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
  for (const r of db.retenidos) if (!r.usado && r.patron.test(id)) { r.usado = true; r.llego(); await r.hecho; }
  const f = db.fallos.find((x) => x.veces > 0 && x.patron.test(id));
  if (f) {
    f.veces -= 1;
    if (f.tipo === 'red') return req.socket.destroy();
    return contestar(f.tipo, { message: 'falla inyectada' });
  }
  const json = () => (crudo.length ? JSON.parse(crudo.toString()) : {});
  if (url.pathname.startsWith('/rest/v1/rpc/')) return contestar(200, rpc(url.pathname.split('/').pop(), json()));
  if (url.pathname === '/rest/v1/mypump_reps_subida' && req.method === 'PATCH') {
    const x = db.subida.get(url.searchParams.get('cliente_id').replace('eq.', ''));
    if (x && url.searchParams.get('acepta') === `eq.${x.acepta}`) x.pendiente = json().borrado_pendiente;
    return contestar(200, []);
  }
  if (url.pathname === '/rest/v1/mypump_reps_grabaciones') {
    if (req.method === 'GET') return contestar(200, rows(url));
    if (req.method === 'DELETE') {
      const fuera = new Set(rows(url));
      if (url.searchParams.get('cliente_id')?.startsWith('not.is.null')) db.filas = [];
      else db.filas = db.filas.filter((r) => !fuera.has(r));
      return contestar(200, []);
    }
    const n = json();
    db.filas = db.filas.filter((r) => !(r.cliente_id === n.cliente_id && r.sesion === n.sesion));
    db.filas.push(n);
    return contestar(201, []);
  }
  if (url.pathname === '/storage/v1/object/list/reps-calibracion') return contestar(200, listar(json().prefix ?? '', json().limit, json().offset));
  if (url.pathname === '/storage/v1/object/reps-calibracion' && req.method === 'DELETE') {
    for (const p of json().prefixes) db.objetos.delete(p);
    return contestar(200, []);
  }
  if (url.pathname.startsWith('/storage/v1/object/reps-calibracion/')) {
    db.objetos.set(url.pathname.slice('/storage/v1/object/reps-calibracion/'.length), crudo);
    return contestar(200, { Key: 'ok' });
  }
  if (url.pathname === '/storage/v1/bucket/reps-calibracion' && req.method === 'DELETE') { db.bucket = false; return contestar(200, {}); }
  contestar(404, { message: `sin ruta ${id}` });
});

// ── El servidor real con la propuesta pegada ──
let hijo, puerto, puertoDoble, salida = '', murio = null;
function armarServidor(dir) {
  let s = readFileSync(join(aqui, '../../mini-vision/server.mjs'), 'utf8');
  const tope = "const tope = feature === 'fotos' ? RATE_FOTOS : RATE_LIMIT;";
  assert.ok(s.includes(tope));
  s = s.replace(tope, "const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'reps' ? RATE_REPS : feature === 'repsConsent' ? RATE_REPS_CONSENT : RATE_LIMIT;");
  const ruta = "  if (req.method !== 'POST' || req.url !== '/vision')";
  assert.ok(s.includes(ruta));
  s = s.replace(ruta, `  if (req.method === 'POST' && req.url === '/reps/subir')          return handleRepsSubir(req, res, origin);
  if (req.method === 'POST' && req.url === '/reps/consentimiento') return handleRepsConsentimiento(req, res, origin);
${ruta}`);
  s += `\n${readFileSync(join(aqui, 'nativa_reps_calibracion_minivision.mjs'), 'utf8')}`;
  const f = join(dir, 'server.mjs');
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
  const dir = mkdtempSync(join(tmpdir(), 'reps-minivision-'));
  puerto = await libre();
  hijo = spawn(process.execPath, [armarServidor(dir)], {
    env: { PATH: process.env.PATH, HOME: dir, PORT: String(puerto), SUPABASE_URL: `http://127.0.0.1:${puertoDoble}`, SUPABASE_SERVICE_KEY: 'clave-de-prueba', REPS_BARRIDO_MS: '100000000' },
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
});
beforeEach(() => { reiniciarDb(); });

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
    if (mandarCuerpo) q.end();
    else q.flushHeaders();
  });
}
const mpcal = (texto = 'datos') => Buffer.from(`MPC1${texto}`);
const sha = (b) => createHash('sha256').update(b).digest('hex');
const cab = (b, token = TOK_A, sesion = '2026-11-07-s6-a') => ({ 'x-reps-token': token, 'x-reps-sesion': sesion, 'x-reps-sha256': sha(b) });
const subir = (b, token, sesion) => pedir('/reps/subir', { headers: cab(b, token, sesion), cuerpo: b });
const consentir = (token, acepta) => {
  const c = Buffer.from(JSON.stringify({ token, acepta, plataforma: 'ios', app: '2.3' }));
  return pedir('/reps/consentimiento', { headers: { 'content-type': 'application/json' }, cuerpo: c });
};
function vivo() { assert.equal(murio, null, `el proceso murió:\n${salida.slice(-800)}`); }
async function salud() {
  const r = await new Promise((resolve) => {
    request({ host: '127.0.0.1', port: puerto, path: '/health', agent: false }, (x) => { x.resume(); x.on('end', () => resolve(x.statusCode)); }).on('error', () => resolve(0)).end();
  });
  assert.equal(r, 200);
  vivo();
}
async function aceptarA() { assert.equal((await consentir(TOK_A, true)).status, 200); }

// ── Camino normal ──
test('sin consentimiento no sube; con consentimiento sí', async () => {
  const b = mpcal();
  assert.equal((await subir(b)).status, 403);
  assert.equal(db.objetos.size, 0);
  await aceptarA();
  const r = await subir(b);
  assert.deepEqual([r.status, r.json], [200, { ok: true }]);
  assert.deepEqual([...db.objetos.keys()], [`${carp('cli-a')}/2026-11-07-s6-a/${sha(b)}.mpcal`]);
  assert.equal(db.filas[0].cliente_id, 'cli-a');
  assert.deepEqual(db.objetos.values().next().value, b);
});

test('la cuenta automática sube sin consentimiento y no puede revocar por acá', async () => {
  assert.equal((await subir(mpcal(), TOK_AUTO)).status, 200);
  assert.equal((await consentir(TOK_AUTO, false)).status, 403);
  assert.equal(db.objetos.size, 1);
});

test('idempotente: el mismo hash no reescribe; más chica no reemplaza; más grande reemplaza y limpia', async () => {
  await aceptarA();
  const b1 = mpcal('una serie');
  assert.equal((await subir(b1)).status, 200);
  const r = await subir(b1);
  assert.deepEqual(r.json, { ok: true, ya: true });
  assert.equal((await subir(mpcal('x'))).json.ya, true);
  const b2 = mpcal('una serie y otra serie');
  assert.equal((await subir(b2)).status, 200);
  assert.deepEqual([...db.objetos.keys()], [`${carp('cli-a')}/2026-11-07-s6-a/${sha(b2)}.mpcal`]);
  assert.equal(db.filas.length, 1);
  assert.equal(db.filas[0].sha256, sha(b2));
});

test('rechaza formato, hash y largo equivocados sin guardar', async () => {
  await aceptarA();
  const malo = Buffer.from('XXXXdatos');
  assert.equal((await subir(malo)).status, 400);
  const b = mpcal();
  assert.equal((await pedir('/reps/subir', { headers: { ...cab(b), 'x-reps-sha256': 'a'.repeat(64) }, cuerpo: b })).status, 400);
  assert.equal((await pedir('/reps/subir', { headers: { ...cab(b), 'x-reps-sesion': '../otro' }, cuerpo: b })).status, 400);
  assert.equal(db.objetos.size, 0);
});

// ── Punto 7: nada se lee antes del token ni pasa los topes ──
test('con token inválido contesta sin esperar el cuerpo', async () => {
  const r = await pedir('/reps/subir', { headers: { 'x-reps-token': 'token-que-no-existe-000', 'x-reps-sesion': 's-1', 'x-reps-sha256': 'a'.repeat(64), 'content-length': 15_000_000 }, mandarCuerpo: false });
  assert.equal(r.status, 403);
  await salud();
});

test('sin largo o con largo de más no lee nada', async () => {
  await aceptarA();
  assert.equal((await pedir('/reps/subir', { headers: { ...cab(mpcal()), 'transfer-encoding': 'chunked' }, cuerpo: undefined })).status, 411);
  assert.equal((await pedir('/reps/subir', { headers: { ...cab(mpcal()), 'content-length': 21 * 1024 * 1024 }, mandarCuerpo: false })).status, 413);
});

test('tope por cuenta: un token que se autoconsiente no llena el bucket', async () => {
  await aceptarA();
  db.filas.push({ cliente_id: 'cli-a', sesion: 'vieja', sha256: 'b'.repeat(64), path: 'cli-a/vieja/x.mpcal', bytes: 300 * 1024 * 1024 - 2 });
  assert.equal((await subir(mpcal())).status, 413);
  assert.equal(db.objetos.size, 0);
});

test('tope global: lleno, nadie sube', async () => {
  await aceptarA();
  db.filas.push({ cliente_id: 'cli-otra', sesion: 'vieja', sha256: 'b'.repeat(64), path: 'x', bytes: 20 * 1024 * 1024 * 1024 });
  assert.equal((await subir(mpcal())).status, 507);
});

test('una sola subida por cuenta a la vez, y el lugar se libera si el cliente se corta', async () => {
  await aceptarA();
  const b = mpcal('12345');
  const a = pedir('/reps/subir', { headers: cab(b), cuerpo: undefined, mandarCuerpo: false });
  const q = request({ host: '127.0.0.1', port: puerto, path: '/reps/subir', method: 'POST', agent: false, headers: { ...cab(b, TOK_A, 's-2'), 'content-length': b.length * 2 } });
  q.on('error', () => {});
  q.write(b.subarray(0, 2));
  await espera(100);
  assert.equal((await subir(b, TOK_A, 's-3')).status, 429);
  q.destroy();
  await espera(100);
  assert.equal((await subir(b, TOK_A, 's-3')).status, 200);
  a.catch?.(() => {});
});

test('tope del día por token', async () => {
  await aceptarA();
  for (let i = 0; i < 30; i++) assert.equal((await subir(mpcal(`v${i}`), TOK_A, `s-${i}`)).status, 200);
  assert.equal((await subir(mpcal('otra'), TOK_A, 's-30')).status, 429);
});

// ── Puntos 1 y 2: red y 5xx ──
for (const [nombre, tipo] of [['corte de red', 'red'], ['503', 503]]) {
  test(`${nombre} en el permiso: contesta, no mata el proceso y no borra`, async () => {
    await aceptarA();
    const b = mpcal('guardado');
    assert.equal((await subir(b)).status, 200);
    fallar(/mypump_reps_puede_subir/, tipo);
    const r = await subir(mpcal('guardado y mas'));
    assert.equal(r.status, 503);
    assert.equal(db.objetos.size, 1);
    assert.equal(db.filas.length, 1);
    await salud();
  });

  test(`${nombre} en el rechequeo: nunca se toma por revocado`, async () => {
    await aceptarA();
    const b1 = mpcal('v1');
    assert.equal((await subir(b1)).status, 200);
    const b2 = mpcal('v1 y mas');
    fallar(/mypump_reps_puede_subir/, tipo);
    db.fallos[0].veces = Infinity;
    // Deja pasar la primera pregunta y falla la segunda.
    let n = 0;
    db.fallos[0].patron = { test: (id) => /mypump_reps_puede_subir/.test(id) && ++n >= 2 };
    const r = await subir(b2);
    assert.equal(r.status, 503);
    assert.ok(db.objetos.has(`${carp('cli-a')}/2026-11-07-s6-a/${sha(b1)}.mpcal`), 'lo anterior no se tocó');
    assert.ok(db.objetos.has(`${carp('cli-a')}/2026-11-07-s6-a/${sha(b2)}.mpcal`), 'lo nuevo tampoco');
    await salud();
  });

  for (const [donde, patron] of [['las filas', /GET \/rest\/v1\/mypump_reps_grabaciones/], ['el total', /mypump_reps_total_bytes/], ['el guardado', /POST \/storage\/v1\/object\/reps-calibracion\//], ['el registro', /POST \/rest\/v1\/mypump_reps_grabaciones/]]) {
    test(`${nombre} en ${donde}: responde y sigue vivo`, async () => {
      await aceptarA();
      fallar(patron, tipo);
      const r = await subir(mpcal());
      assert.ok(r.status >= 500, `status ${r.status}`);
      assert.equal(db.filas.length, 0);
      if (donde === 'el registro') assert.equal(db.objetos.size, 0, 'sin fila no queda el objeto');
      await salud();
    });
  }

  test(`${nombre} en la validación del token: 503, no 403`, async () => {
    fallar(/mypump_get_cliente_info/, tipo);
    assert.equal((await subir(mpcal())).status, 503);
    await salud();
  });

  test(`${nombre} al revocar: no borra por error y queda pendiente para el reintento`, async () => {
    await aceptarA();
    assert.equal((await subir(mpcal())).status, 200);
    fallar(/mypump_reps_revocar/, tipo, 1);
    assert.equal((await consentir(TOK_A, false)).status, 503);
    assert.equal(db.objetos.size, 1, 'no se pudo revocar: nada se borró');
    assert.equal((await consentir(TOK_A, false)).status, 200);
    assert.equal(db.objetos.size, 0);
    assert.equal(db.filas.length, 0);
    await salud();
  });

  for (const [donde, patron] of [['listar', /object\/list/], ['borrar objetos', /DELETE \/storage/], ['borrar filas', /DELETE \/rest/]]) {
    test(`${nombre} al ${donde} en la revocación: 502, pendiente y el reintento termina`, async () => {
      await aceptarA();
      assert.equal((await subir(mpcal())).status, 200);
      fallar(patron, tipo, 1);
      assert.equal((await consentir(TOK_A, false)).status, 502);
      assert.equal(db.subida.get('cli-a').pendiente, true);
      assert.equal((await consentir(TOK_A, true)).status, 409, 'no se puede volver a aceptar a medias');
      assert.equal((await consentir(TOK_A, false)).status, 200);
      assert.equal(db.objetos.size, 0);
      assert.equal(db.filas.length, 0);
      assert.equal(db.subida.get('cli-a').pendiente, false);
      await salud();
    });
  }
}

test('Supabase caído del todo: todas las rutas contestan y el proceso sigue', async () => {
  fallar(/.*/, 'red');
  const b = mpcal();
  assert.ok((await subir(b)).status >= 500);
  assert.ok((await consentir(TOK_A, true)).status >= 500);
  assert.ok((await consentir(TOK_A, false)).status >= 500);
  await salud();
});

test('un consentimiento con JSON roto o sin token no rompe', async () => {
  assert.equal((await pedir('/reps/consentimiento', { cuerpo: Buffer.from('{no') })).status, 400);
  assert.equal((await pedir('/reps/consentimiento', { cuerpo: Buffer.from('{"acepta":false}') })).status, 403);
  await salud();
});

// ── Revocación y carreras ──
test('revocar borra todo lo de esa cuenta y nada de otra', async () => {
  await aceptarA();
  assert.equal((await consentir(TOK_B, true)).status, 200);
  assert.equal((await subir(mpcal('a1'), TOK_A, 's-1')).status, 200);
  assert.equal((await subir(mpcal('a2'), TOK_A, 's-2')).status, 200);
  assert.equal((await subir(mpcal('b'), TOK_B, 's-1')).status, 200);
  assert.equal((await consentir(TOK_A, false)).status, 200);
  assert.deepEqual([...db.objetos.keys()].map((k) => k.split('/')[0]), [carp('cli-b')]);
  assert.deepEqual(db.filas.map((f) => f.cliente_id), ['cli-b']);
  assert.equal((await subir(mpcal('a3'), TOK_A, 's-3')).status, 403);
});

test('borra por carpeta también objetos sin fila', async () => {
  await aceptarA();
  db.objetos.set(`${carp('cli-a')}/huerfana/x.mpcal`, Buffer.from('MPC1'));
  assert.equal((await consentir(TOK_A, false)).status, 200);
  assert.equal(db.objetos.size, 0);
});

test('token dado de baja: puede revocar y se borra, pero no subir ni aceptar', async () => {
  db.subida.set('cli-baja', { automatica: false, acepta: true, pendiente: false });
  db.objetos.set(`${carp('cli-baja')}/s-1/x.mpcal`, Buffer.from('MPC1'));
  db.filas.push({ cliente_id: 'cli-baja', sesion: 's-1', sha256: 'c'.repeat(64), path: 'cli-baja/s-1/x.mpcal', bytes: 4 });
  assert.equal((await subir(mpcal(), TOK_BAJA)).status, 403);
  assert.equal((await consentir(TOK_BAJA, true)).status, 403);
  assert.equal(db.objetos.size, 1, 'un rechazo no borra');
  assert.equal((await consentir(TOK_BAJA, false)).status, 200);
  assert.equal(db.objetos.size, 0);
  assert.equal(db.filas.length, 0);
  assert.equal(db.clientes.get(TOK_BAJA).activo, false, 'no reactiva nada');
});

test('un token que no existe no puede revocar a nadie', async () => {
  assert.equal((await consentir('token-que-no-existe-000', false)).status, 403);
});

test('revoca mientras se guarda el objeto: no queda nada', async () => {
  await aceptarA();
  const r = retener(/POST \/storage\/v1\/object\/reps-calibracion\//);
  const sube = subir(mpcal());
  await r.llegada;
  assert.equal((await consentir(TOK_A, false)).status, 200);
  r.soltar();
  assert.equal((await sube).status, 403);
  assert.equal(db.objetos.size, 0);
  assert.equal(db.filas.length, 0);
  await salud();
});

test('revoca justo después del rechequeo: la revocación ve el archivo y lo borra', async () => {
  await aceptarA();
  let n = 0;
  const r = retener({ test: (id) => /mypump_reps_puede_subir/.test(id) && ++n === 2 });
  const sube = subir(mpcal());
  await r.llegada;
  const re = consentir(TOK_A, false);
  await espera(50);
  r.soltar();
  await Promise.all([sube, re]);
  // Si el rechequeo contestó antes de revocar, la revocación barrió; si después, el rechequeo borró.
  assert.equal(db.objetos.size, 0);
  assert.equal(db.filas.length, 0);
});

test('revocó y no se pudo borrar lo recién subido: la fila queda para el barrido', async () => {
  await aceptarA();
  const r = retener(/POST \/storage\/v1\/object\/reps-calibracion\//);
  const sube = subir(mpcal());
  await r.llegada;
  assert.equal((await consentir(TOK_A, false)).status, 200);
  fallar(/DELETE \/storage\/v1\/object\/reps-calibracion/, 503);
  r.soltar();
  assert.equal((await sube).status, 403);
  assert.equal(db.objetos.size, 1);
  assert.equal(db.filas.length, 1);
  assert.deepEqual(rpc('mypump_reps_para_borrar', {}), ['cli-a']);
});

test('sin registrar, sin poder borrar y ya revocó: queda marcado para el barrido', async () => {
  await aceptarA();
  const r = retener(/POST \/storage\/v1\/object\/reps-calibracion\//);
  const sube = subir(mpcal());
  await r.llegada;
  assert.equal((await consentir(TOK_A, false)).status, 200);
  fallar(/POST \/rest\/v1\/mypump_reps_grabaciones/, 503);
  fallar(/DELETE \/storage\/v1\/object\/reps-calibracion/, 503);
  r.soltar();
  assert.equal((await sube).status, 502);
  assert.equal(db.subida.get('cli-a').pendiente, true);
  assert.deepEqual(rpc('mypump_reps_para_borrar', {}), ['cli-a']);
});

test('sin registrar y sin poder borrar, sin haber revocado: no se marca nada para borrar', async () => {
  const r = retener(/POST \/storage\/v1\/object\/reps-calibracion\//);
  const sube = subir(mpcal(), TOK_AUTO);
  await r.llegada;
  db.subida.get('cli-auto').automatica = false;
  fallar(/POST \/rest\/v1\/mypump_reps_grabaciones/, 503);
  fallar(/DELETE \/storage\/v1\/object\/reps-calibracion/, 503);
  r.soltar();
  assert.equal((await sube).status, 502);
  assert.ok(!db.subida.get('cli-auto').pendiente);
  assert.deepEqual(rpc('mypump_reps_para_borrar', {}), []);
});

test('rechequeo falla y además revocó: el barrido termina el borrado', async () => {
  await aceptarA();
  const b = mpcal();
  let n = 0;
  fallar({ test: (id) => /mypump_reps_puede_subir/.test(id) && ++n === 2 }, 503);
  assert.equal((await subir(b)).status, 503);
  db.subida.get('cli-a').acepta = false;   // revocado sin haber llegado a borrar
  assert.deepEqual(rpc('mypump_reps_para_borrar', {}), ['cli-a']);
});

test('sacarle la marca automática no borra lo guardado', async () => {
  assert.equal((await subir(mpcal(), TOK_AUTO)).status, 200);
  db.subida.get('cli-auto').automatica = false;
  assert.equal((await subir(mpcal('mas larga'), TOK_AUTO)).status, 403);
  assert.deepEqual(rpc('mypump_reps_para_borrar', {}), []);
  assert.equal(db.objetos.size, 1);
});

test('se corta el cliente a mitad del cuerpo: no guarda nada', async () => {
  await aceptarA();
  const b = mpcal('completo');
  const q = request({ host: '127.0.0.1', port: puerto, path: '/reps/subir', method: 'POST', agent: false, headers: { ...cab(b), 'content-length': b.length } });
  q.on('error', () => {});
  q.write(b.subarray(0, 3));
  await espera(80);
  q.destroy();
  await espera(80);
  assert.equal(db.objetos.size, 0);
  await salud();
});

test('la carpeta del bucket no lleva el id de la cuenta', async () => {
  await aceptarA();
  assert.equal((await subir(mpcal())).status, 200);
  assert.ok(![...db.objetos.keys()][0].includes('cli-a'));
});

test('borra con más de una página de sesiones', async () => {
  await aceptarA();
  for (let i = 0; i < 230; i++) db.objetos.set(`${carp('cli-a')}/s-${i}/x.mpcal`, Buffer.from('MPC1'));
  assert.equal((await consentir(TOK_A, false)).status, 200);
  assert.equal(db.objetos.size, 0);
});

test('si el cliente se corta mientras se miran los topes, el lugar no queda ocupado', async () => {
  await aceptarA();
  const b = mpcal();
  const r = retener(/GET \/rest\/v1\/mypump_reps_grabaciones/);
  const q = request({ host: '127.0.0.1', port: puerto, path: '/reps/subir', method: 'POST', agent: false, headers: { ...cab(b), 'content-length': b.length } });
  q.on('error', () => {});
  q.flushHeaders();
  await r.llegada;
  q.destroy();
  await espera(60);
  r.soltar();
  await espera(60);
  assert.equal((await subir(b, TOK_A, 's-9')).status, 200);
});

test('un JSON que no es objeto recibe respuesta', async () => {
  for (const c of ['null', '0', 'false']) assert.equal((await pedir('/reps/consentimiento', { cuerpo: Buffer.from(c) })).status, 400, c);
});

// ── El reverso ──
const script = join(aqui, 'nativa_reps_calibracion_vaciar.mjs');
const correrScript = (...a) => exec(process.execPath, [script, ...a], { env: { PATH: process.env.PATH, SUPABASE_URL: `http://127.0.0.1:${puertoDoble}`, SUPABASE_SERVICE_KEY: 'clave-de-prueba' } });

test('el reverso vacía objetos y filas, y el bucket recién vacío', async () => {
  await aceptarA();
  assert.equal((await subir(mpcal(), TOK_A)).status, 200);
  assert.equal((await subir(mpcal('auto'), TOK_AUTO)).status, 200);
  const seco = await correrScript('vaciar');
  assert.match(seco.stdout, /objetos: 2/);
  assert.equal(db.objetos.size, 2, 'sin --confirmar no borra');
  await assert.rejects(correrScript('bucket', '--confirmar'), /primero vaciar/);
  assert.equal(db.bucket, true);
  await correrScript('vaciar', '--confirmar');
  assert.equal(db.objetos.size, 0);
  assert.equal(db.filas.length, 0);
  await correrScript('bucket', '--confirmar');
  assert.equal(db.bucket, false);
});

test('el reverso pagina con más de cien carpetas', async () => {
  for (let i = 0; i < 206; i++) db.objetos.set(`c-${i}/s/x.mpcal`, Buffer.from('MPC1'));
  await correrScript('vaciar', '--confirmar');
  assert.equal(db.objetos.size, 0);
});

test('el reverso falla a la vista si Storage no responde', async () => {
  db.objetos.set(`${carp('cli-a')}/s/x.mpcal`, Buffer.from('MPC1'));
  fallar(/DELETE \/storage/, 503);
  await assert.rejects(correrScript('vaciar', '--confirmar'), /HTTP 503/);
  assert.equal(db.objetos.size, 1);
});

// ── El barrido corre de verdad en un proceso aparte, con intervalo corto ──
test('el barrido termina una revocación que quedó a medias', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'reps-barrido-'));
  const p = await libre();
  db.subida.set('cli-a', { automatica: false, acepta: false, pendiente: true });
  db.objetos.set(`${carp('cli-a')}/s/x.mpcal`, Buffer.from('MPC1'));
  db.filas.push({ cliente_id: 'cli-a', sesion: 's', sha256: 'c'.repeat(64), path: 'cli-a/s/x.mpcal', bytes: 4 });
  fallar(/DELETE \/storage/, 503, 1);
  const h = spawn(process.execPath, [armarServidor(dir)], {
    env: { PATH: process.env.PATH, HOME: dir, PORT: String(p), SUPABASE_URL: `http://127.0.0.1:${puertoDoble}`, SUPABASE_SERVICE_KEY: 'clave-de-prueba', REPS_BARRIDO_MS: '100' },
    stdio: 'ignore',
  });
  try {
    for (let i = 0; i < 60 && db.subida.get('cli-a').pendiente; i++) await espera(50);
    assert.equal(db.subida.get('cli-a').pendiente, false);
    assert.equal(db.objetos.size, 0);
    assert.equal(db.filas.length, 0);
    assert.equal(h.exitCode, null, 'el barrido no mata el proceso');
  } finally { h.kill(); }
});
