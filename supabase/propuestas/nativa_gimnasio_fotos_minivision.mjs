// PROPUESTA, SIN APLICAR: los endpoints de Gimnasio por fotos para sumar a mini-vision/server.mjs (se prueba contra un doble
// local: `node --test supabase/propuestas/nativa_gimnasio_fotos_minivision.test.mjs`).
// Rutas, antes de la de /vision:
//   if (req.method === 'POST' && req.url === '/gimnasio/upload') return handleGimnasioUpload(req, res, origin);
//   if (req.method === 'POST' && req.url === '/gimnasio/urls')   return handleGimnasioUrls(req, res, origin);
//   if (req.method === 'POST' && req.url === '/gimnasio/borrar') return handleGimnasioBorrar(req, res, origin);
// En overLimit, el tope de esta función:
//   const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'gimnasio' ? RATE_GIMNASIO : RATE_LIMIT;
// En send(), para que la web pueda mandar los encabezados (fetch hace un preflight):
//   headers['Access-Control-Allow-Headers'] = 'Content-Type, x-gimnasio-token, x-gimnasio-id, x-gimnasio-foto, x-gimnasio-zona';
// El binario: en la Mini `swiftc` no compila (Command Line Tools rotas: redefinition of module SwiftBridging). Compilar en la MacBook
// con `swiftc -O -o tapar-caras gimnasio_tapar_caras/tapar_caras.swift` y copiarlo a ~/pump-gimnasio/bin/ (probado que corre en la Mini).
//
// INVARIANTES
// - El cliente_id sale del TOKEN, jamás del pedido. El path lo arma el servidor; a la app nunca le llega.
// - El cuerpo se lee recién con el token, la carga, los topes y un lugar libre.
// - Sin tapar y recodificar no se guarda nada: si el binario falla, no hay objeto (fail-closed).
// - El tope de 80 sale de contar filas con la carga trabada, no de la memoria del proceso. El de memoria es solo contra abuso.
// - Nada se escapa de un handler: todo error termina en una respuesta (este proceso también atiende visión y fotos).
// - El 4xx es definitivo para la cola del teléfono: por eso una falla nuestra siempre es 5xx o 429, nunca 4xx.

import { execFile as execFileGim } from 'node:child_process';
import { createHash as hashGim } from 'node:crypto';
import { mkdtemp as mkdtempGim, readFile as readFileGim, rm as rmGim, writeFile as writeFileGim } from 'node:fs/promises';
import { tmpdir as tmpdirGim, homedir as homedirGim } from 'node:os';
import { join as joinGim } from 'node:path';

const BUCKET_GIMNASIO = 'gimnasio';
const MAX_GIMNASIO_B = 8 * 1024 * 1024;           // lo que entra por la red; el binario lo baja a 1600 px y menos de 3 MB
const RATE_GIMNASIO = 150;                        // subidas por token por día: 80 por carga y las que se repiten
const MAX_GIMNASIO_EN_CURSO = 2;                  // a la vez en todo el servicio: cada una lanza un proceso con Vision
const ESPERA_GIMNASIO_MS = 30_000;
const ESPERA_CUERPO_GIMNASIO_MS = 120_000;
const ESPERA_TAPAR_MS = 30_000;
const TAPAR_CARAS_BIN = process.env.GIMNASIO_TAPAR_BIN || joinGim(homedirGim(), 'pump-gimnasio', 'bin', 'tapar-caras');
const ZONAS_GIMNASIO = new Set(['poleas', 'accesorios_polea', 'piernas', 'empuje', 'tiron', 'barras_racks', 'discos', 'mancuernas', 'bancos', 'otros']);
const UUID_GIMNASIO = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// Lo que contesta el servidor para cada negativa de la base.
const RECHAZOS_GIMNASIO = {
  no_encontrado: [404, 'carga no encontrada'], ajena: [409, 'id de foto repetido'], estado: [409, 'esta carga ya no recibe fotos'],
  tope: [413, 'llegaste al máximo de fotos'], no_habilitado: [403, 'no habilitado'],
};

const gimnasioEnCurso = new Set();                // cuentas subiendo ahora

class ErrorServicioGimnasio extends Error {}

function fetchGimnasio(url, opciones = {}) {
  return fetch(url, { signal: AbortSignal.timeout(ESPERA_GIMNASIO_MS), ...opciones });
}

async function rpcGimnasio(fn, cuerpo = {}) {
  const r = await fetchGimnasio(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify(cuerpo),
  });
  if (!r.ok) throw new ErrorServicioGimnasio(`${fn}: HTTP ${r.status}`);
  try { return await r.json(); } catch { throw new ErrorServicioGimnasio(`${fn}: respuesta no JSON`); }
}

// La carpeta de la cuenta en el bucket: no lleva el cliente_id, que en algunas cuentas contiene el nombre.
function carpetaGimnasio(clienteId) {
  return hashGim('sha256').update(`gimnasio:${clienteId}`).digest('hex').slice(0, 32);
}

function rechazarGimnasio(req, res, status, error, origin) {
  res.once('finish', () => req.destroy());
  send(res, status, { ok: false, error }, origin);
}

async function clienteGimnasio(token, req, res, origin) {
  const c = await clienteOResponder(token, res, origin);
  if (c === undefined) res.once('finish', () => req.destroy());
  return c;
}

function leerCuerpoGimnasio(req, largo) {
  return new Promise((resolve) => {
    if (req.destroyed || req.socket?.destroyed) return resolve(null);
    const partes = [];
    let total = 0, listo = false;
    const fin = (v) => { if (!listo) { listo = true; clearTimeout(plazo); resolve(v); } };
    const plazo = setTimeout(() => { fin(null); req.destroy(); }, ESPERA_CUERPO_GIMNASIO_MS);
    req.on('data', (c) => {
      total += c.length;
      if (total > largo) { fin(null); req.destroy(); return; }
      partes.push(c);
    });
    req.on('end', () => fin(Buffer.concat(partes)));
    req.on('close', () => fin(null));
    req.on('error', () => fin(null));
  });
}

// Tapa y recodifica. Devuelve { buf, caras, borde_blanco }, null si no era una imagen válida, o lanza si el binario falló.
async function taparCaras(buf) {
  const dir = await mkdtempGim(joinGim(tmpdirGim(), 'gimnasio-'));   // 0700: la foto original solo la ve este usuario
  try {
    const entrada = joinGim(dir, 'entrada.jpg'), salida = joinGim(dir, 'salida.jpg');
    await writeFileGim(entrada, buf, { mode: 0o600 });
    const stdout = await new Promise((resolve, reject) => {
      execFileGim(TAPAR_CARAS_BIN, [entrada, salida], { timeout: ESPERA_TAPAR_MS, maxBuffer: 64 * 1024 }, (err, out, stderr) => {
        if (err) { err.detalle = String(stderr).slice(0, 200); return reject(err); }
        resolve(String(out));
      });
    });
    let info;
    try { info = JSON.parse(stdout); } catch { throw new ErrorServicioGimnasio('tapar-caras: salida inválida'); }
    if (!Number.isInteger(info.caras) || info.caras < 0) throw new ErrorServicioGimnasio('tapar-caras: salida inválida');
    return { buf: await readFileGim(salida), caras: info.caras, borde_blanco: Number.isFinite(info.borde_blanco) ? info.borde_blanco : null };
  } catch (e) {
    if (e.code === 2) return null;                    // el binario dice que no es un JPEG legible: culpa de la foto
    throw e;
  } finally {
    await rmGim(dir, { recursive: true, force: true }).catch((e) => console.error('[gimnasio] temporal', e.message || e));
  }
}

async function sacarObjetoGimnasio(path) {
  try {
    const r = await fetchGimnasio(`${SUPABASE_URL}/storage/v1/object/${BUCKET_GIMNASIO}`, {
      method: 'DELETE', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ prefixes: [path] }),
    });
    if (!r.ok) throw new ErrorServicioGimnasio(`HTTP ${r.status}`);
    return true;
  } catch (e) {
    console.error('[gimnasio] sacar objeto', e.message || e);   // queda en la carpeta: el barrido de 90 días va por carpeta
    return false;
  }
}

// ── POST /gimnasio/upload — cuerpo: el JPEG crudo; x-gimnasio-token, x-gimnasio-id, x-gimnasio-foto, x-gimnasio-zona, Content-Length ──
// Idempotente: el id de la foto lo manda el teléfono. Un reintento contesta `ya` sin volver a procesar.
async function handleGimnasioUpload(req, res, origin) {
  let ocupada = null;
  try {
    if (!SERVICE_KEY) return rechazarGimnasio(req, res, 503, 'servicio no configurado', origin);
    const token = req.headers['x-gimnasio-token'];
    const gimnasioId = String(req.headers['x-gimnasio-id'] || '').toLowerCase();
    const fotoId = String(req.headers['x-gimnasio-foto'] || '').toLowerCase();
    const zona = req.headers['x-gimnasio-zona'];
    const largo = Number(req.headers['content-length']);
    if (!UUID_GIMNASIO.test(gimnasioId) || !UUID_GIMNASIO.test(fotoId)) return rechazarGimnasio(req, res, 400, 'id inválido', origin);
    if (typeof zona !== 'string' || !ZONAS_GIMNASIO.has(zona)) return rechazarGimnasio(req, res, 400, 'falta la zona', origin);
    if (!Number.isInteger(largo) || largo <= 0) return rechazarGimnasio(req, res, 411, 'falta el largo', origin);
    if (largo > MAX_GIMNASIO_B) return rechazarGimnasio(req, res, 413, 'foto muy grande', origin);

    const clienteId = await clienteGimnasio(token, req, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return rechazarGimnasio(req, res, 403, 'token inválido', origin);

    const antes = await rpcGimnasio('mypump_gimnasio_foto_puede', { p_cliente_id: clienteId, p_gimnasio_id: gimnasioId, p_foto_id: fotoId });
    if (antes === 'ya') { req.resume(); return send(res, 200, { ok: true, ya: true }, origin); }
    if (antes !== 'ok') {
      const [status, error] = RECHAZOS_GIMNASIO[antes] || [];
      if (!status) throw new ErrorServicioGimnasio('puede: respuesta inesperada');
      return rechazarGimnasio(req, res, status, error, origin);
    }
    if (overLimit(token, 'gimnasio', { contar: false })) return rechazarGimnasio(req, res, 429, 'muchas fotos por hoy, probá mañana', origin);
    if (gimnasioEnCurso.has(clienteId) || gimnasioEnCurso.size >= MAX_GIMNASIO_EN_CURSO) return rechazarGimnasio(req, res, 429, 'ocupado, probá en un rato', origin);
    gimnasioEnCurso.add(clienteId);
    ocupada = clienteId;

    const buf = await leerCuerpoGimnasio(req, largo);
    if (!buf) return;                                 // se cortó: no hay a quién contestarle
    if (buf.length !== largo) return send(res, 400, { ok: false, error: 'largo incorrecto' }, origin);
    if (!(buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff)) return send(res, 400, { ok: false, error: 'la imagen debe ser JPEG' }, origin);

    const tapada = await taparCaras(buf);
    if (!tapada) return send(res, 400, { ok: false, error: 'la imagen no se puede leer' }, origin);

    const path = `${carpetaGimnasio(clienteId)}/${gimnasioId}/${fotoId}.jpg`;
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_GIMNASIO}/${path}`, {
      method: 'POST',
      signal: AbortSignal.timeout(ESPERA_CUERPO_GIMNASIO_MS),
      headers: svcHeaders({ 'Content-Type': 'image/jpeg', 'x-upsert': 'true' }),
      body: tapada.buf,
    });
    if (!up.ok) {
      console.error('[gimnasio] storage', up.status);
      return send(res, 502, { ok: false, error: 'no se pudo guardar' }, origin);
    }

    let reg;
    try {
      reg = await rpcGimnasio('mypump_gimnasio_foto_registrar', {
        p_cliente_id: clienteId, p_gimnasio_id: gimnasioId, p_foto_id: fotoId, p_zona: zona, p_path: path,
        p_bytes: tapada.buf.length, p_caras: tapada.caras, p_borde_blanco: tapada.borde_blanco,
      });
    } catch (e) {
      // Sin fila no lo cuenta el tope. Con la red cortada la fila pudo haber entrado: el reintento contesta `ya` y el objeto
      // tiene que seguir estando, así que acá no se saca nada; si no entró, lo levanta el barrido por carpeta.
      console.error('[gimnasio] registrar', e.message || e);
      return send(res, 502, { ok: false, error: 'guardada sin registrar' }, origin);
    }
    if (reg === 'ya') return send(res, 200, { ok: true, ya: true }, origin);
    if (reg !== 'ok') {
      await sacarObjetoGimnasio(path);                // cambió mientras se procesaba (la enviaron, llegó al tope)
      const [status, error] = RECHAZOS_GIMNASIO[reg] || [502, 'guardada sin registrar'];
      return send(res, status, { ok: false, error }, origin);
    }
    sumarUso(token, 'gimnasio');
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[gimnasio] error', e.message || e, e.detalle || '');
    if (res.headersSent) return;
    rechazarGimnasio(req, res, 503, 'no se pudo subir, probá en un rato', origin);
  } finally {
    if (ocupada) gimnasioEnCurso.delete(ocupada);
  }
}

// El cuerpo JSON de los otros dos: chico y con tope. null si ya se contestó o se cortó.
async function jsonGimnasio(req, res, origin) {
  const data = await leerBody(req, res, origin, 4 * 1024);
  if (data && typeof data === 'object' && !Array.isArray(data)) return data;
  if (!res.headersSent && !req.socket?.destroyed) send(res, 400, { ok: false, error: 'pedido inválido' }, origin);
  return null;
}

// ── POST /gimnasio/urls — { token, gimnasio_id } ── URLs firmadas de SUS fotos. Nunca firma un path del pedido.
async function handleGimnasioUrls(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await jsonGimnasio(req, res, origin);
    if (!data) return;
    const gimnasioId = String(data.gimnasio_id || '').toLowerCase();
    if (!UUID_GIMNASIO.test(gimnasioId)) return send(res, 400, { ok: false, error: 'id inválido' }, origin);
    const clienteId = await clienteOResponder(data.token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);

    const q = `${SUPABASE_URL}/rest/v1/mypump_gimnasio_fotos?cliente_id=eq.${encodeURIComponent(clienteId)}`
            + `&gimnasio_id=eq.${gimnasioId}&descartada=eq.false&select=id,zona,path&order=creado_en.asc&limit=100`;
    const r = await fetchGimnasio(q, { headers: svcHeaders() });
    if (!r.ok) return send(res, 502, { ok: false, error: 'no se pudo leer' }, origin);
    const filas = await r.json();
    if (!Array.isArray(filas)) return send(res, 502, { ok: false, error: 'no se pudo leer' }, origin);
    if (!filas.length) return send(res, 200, { ok: true, fotos: [] }, origin);

    const fr = await fetchGimnasio(`${SUPABASE_URL}/storage/v1/object/sign/${BUCKET_GIMNASIO}`, {
      method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ expiresIn: 3600, paths: filas.map((f) => f.path) }),
    });
    if (!fr.ok) return send(res, 502, { ok: false, error: 'no se pudieron firmar' }, origin);
    const firmadas = await fr.json();
    const porPath = Object.fromEntries((Array.isArray(firmadas) ? firmadas : []).map((x) => [String(x.path).replace(/^\/+/, ''), x.signedURL]));
    const fotos = filas.filter((f) => porPath[f.path]).map((f) => ({ id: f.id, zona: f.zona, url: `${SUPABASE_URL}/storage/v1${porPath[f.path]}` }));
    send(res, 200, { ok: true, fotos, expira_en: 3600 }, origin);
  } catch (e) {
    console.error('[gimnasio] urls', e.message || e);
    if (!res.headersSent) send(res, 502, { ok: false, error: 'error al firmar' }, origin);
  }
}

// ── POST /gimnasio/borrar — { token, foto_id } ── Saca una foto mientras la carga se puede cambiar.
async function handleGimnasioBorrar(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await jsonGimnasio(req, res, origin);
    if (!data) return;
    const fotoId = String(data.foto_id || '').toLowerCase();
    if (!UUID_GIMNASIO.test(fotoId)) return send(res, 400, { ok: false, error: 'id inválido' }, origin);
    const clienteId = await clienteOResponder(data.token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);

    const r = await rpcGimnasio('mypump_gimnasio_foto_borrar', { p_cliente_id: clienteId, p_foto_id: fotoId });
    if (r?.resultado === 'no_encontrado') return send(res, 200, { ok: true, ya: true }, origin);   // ya estaba borrada: la cola del teléfono termina
    if (r?.resultado === 'estado') return send(res, 409, { ok: false, error: 'esta carga ya no se puede cambiar' }, origin);
    if (r?.resultado !== 'ok' || typeof r.path !== 'string') throw new ErrorServicioGimnasio('borrar: respuesta inesperada');
    await sacarObjetoGimnasio(r.path);
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[gimnasio] borrar', e.message || e);
    if (!res.headersSent) send(res, 503, { ok: false, error: 'no se pudo borrar, probá en un rato' }, origin);
  }
}
