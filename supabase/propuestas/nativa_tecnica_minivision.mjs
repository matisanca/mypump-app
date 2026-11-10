// PROPUESTA, SIN APLICAR: los endpoints de Técnica por video para sumar a mini-vision/server.mjs (se prueba contra un doble
// local: `node --test supabase/propuestas/nativa_tecnica_minivision.test.mjs`).
// Rutas, antes de la de /vision:
//   if (req.method === 'POST' && req.url === '/tecnica/upload') return handleTecnicaUpload(req, res, origin);
//   if (req.method === 'POST' && req.url === '/tecnica/url')    return handleTecnicaUrl(req, res, origin);
//   if (req.method === 'POST' && req.url === '/tecnica/borrar') return handleTecnicaBorrar(req, res, origin);
// En overLimit: la rama `feature === 'tecnica' ? RATE_TECNICA :` justo antes del `RATE_LIMIT` final de `const tope`, sin tocar las demás.
// En send(): sumar 'x-tecnica-token, x-tecnica-id' a Access-Control-Allow-Headers.
// Antes de server.listen: `server.requestTimeout = 660_000;` (el de Node es 300 s y cortaría una subida lenta antes que el plazo de acá).
//
// INVARIANTES
// - El cliente_id sale del TOKEN, jamás del pedido. El path lo arma el servidor; a la app nunca le llega.
// - El cuerpo se lee a disco, nunca entero a memoria, y recién con el token, el envío, los topes y un lugar libre.
// - Se guarda solo un MP4 remuxado sin audio y sin metadatos (la ubicación del teléfono viaja en esos metadatos).
//   Si ffprobe o ffmpeg fallan, no se guarda nada (fail-closed).
// - El 4xx es definitivo para la cola del teléfono: una falla nuestra siempre es 5xx o 429, nunca 4xx.
// - Nada se escapa de un handler: este proceso también atiende visión y fotos.

import { execFile as execFileTec } from 'node:child_process';
import { createHash as hashTec } from 'node:crypto';
import { createWriteStream as crearEscrituraTec } from 'node:fs';
import { mkdtemp as mkdtempTec, readdir as readdirTec, readFile as readFileTec, rm as rmTec, stat as statTec } from 'node:fs/promises';
import { tmpdir as tmpdirTec } from 'node:os';
import { join as joinTec } from 'node:path';

const BUCKET_TECNICA = 'tecnica';
const MAX_TECNICA_B = 60 * 1024 * 1024;           // la app comprime a 720p; un video de 75 s entra sobrado
const DURACION_MIN_TECNICA = 4;
const DURACION_MAX_TECNICA = 75;                // +0,5 s de tolerancia como el teléfono: lo que sobra lo corta el `-t`
const RATE_TECNICA = 8;                           // subidas por token por día, contando reintentos
const MAX_TECNICA_EN_CURSO = 2;                   // a la vez en todo el servicio: cada una lanza ffmpeg
const ESPERA_TECNICA_MS = 30_000;
const ESPERA_CUERPO_TECNICA_MS = 600_000;         // total: 60 MB entran con ~0,8 Mb/s (con 240 s hacían falta 2 Mb/s). Exige server.requestTimeout mayor
const ESPERA_SILENCIO_TECNICA_MS = Number(process.env.TECNICA_ESPERA_SILENCIO_MS) || 60_000;  // sin bytes: se corta y libera uno de los dos lugares
const ESPERA_FF_TECNICA_MS = 90_000;
const FFMPEG_TECNICA = process.env.TECNICA_FFMPEG || '/opt/homebrew/bin/ffmpeg';
const FFPROBE_TECNICA = process.env.TECNICA_FFPROBE || '/opt/homebrew/bin/ffprobe';
const UUID_TECNICA = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const RECHAZOS_TECNICA = {
  no_encontrado: [404, 'envío no encontrado'], estado: [409, 'este envío ya no recibe video'], no_habilitado: [403, 'no habilitado'],
};

let tecnicaBarrido = null;
function barrerTemporalesTecnica() {                 // una caída a mitad de proceso deja un video en el temporal
  tecnicaBarrido ??= readdirTec(tmpdirTec()).then((nombres) => Promise.all(nombres.filter((n) => n.startsWith('tecnica-'))
    .map((n) => rmTec(joinTec(tmpdirTec(), n), { recursive: true, force: true })))).catch((e) => console.error('[tecnica] barrido', e.message || e));
  return tecnicaBarrido;
}

const tecnicaEnCurso = new Set();

class ErrorServicioTecnica extends Error {}

function fetchTecnica(url, opciones = {}) {
  return fetch(url, { signal: AbortSignal.timeout(ESPERA_TECNICA_MS), ...opciones });
}

async function rpcTecnica(fn, cuerpo = {}) {
  const r = await fetchTecnica(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify(cuerpo) });
  if (!r.ok) throw new ErrorServicioTecnica(`${fn}: HTTP ${r.status}`);
  try { return await r.json(); } catch { throw new ErrorServicioTecnica(`${fn}: respuesta no JSON`); }
}

function carpetaTecnica(clienteId) {                 // sin el cliente_id, que en algunas cuentas contiene el nombre
  return hashTec('sha256').update(`tecnica:${clienteId}`).digest('hex').slice(0, 32);
}

// Después de responder se lee lo que falte del cuerpo, con tope de bytes y de tiempo. Cortar la conexión con la subida a medio
// camino hace que el navegador vea un corte de red y no el 4xx, y el video se reintentaría sin fin.
const DRENAR_TECNICA_MS = 15_000;
function drenarOCortarTecnica(req) {
  if (req.complete || req.destroyed) return;
  let leidos = 0;
  const cortar = () => { clearTimeout(plazo); req.destroy(); };
  const plazo = setTimeout(cortar, DRENAR_TECNICA_MS);
  plazo.unref?.();
  req.on('data', (c) => { leidos += c.length; if (leidos > MAX_TECNICA_B) cortar(); });
  req.once('end', () => clearTimeout(plazo));
  req.once('close', () => clearTimeout(plazo));
  req.once('error', cortar);
}

function rechazarTecnica(req, res, status, error, origin) {
  res.once('finish', () => drenarOCortarTecnica(req));
  send(res, status, { ok: false, error }, origin);
}

function correrTecnica(bin, args) {
  return new Promise((resolve, reject) => {
    execFileTec(bin, args, { timeout: ESPERA_FF_TECNICA_MS, maxBuffer: 1024 * 1024 }, (err, out, stderr) => {
      if (err) { err.detalle = String(stderr).slice(0, 200); return reject(err); }
      resolve(String(out));
    });
  });
}

function cuerpoADisco(req, largo, ruta) {
  return new Promise((resolve) => {
    if (req.destroyed || req.socket?.destroyed) return resolve(null);
    const salida = crearEscrituraTec(ruta, { mode: 0o600 });
    let total = 0, listo = false, recibido = false, cabecera = Buffer.alloc(0);
    const fin = (v) => { if (!listo) { listo = true; clearTimeout(plazo); clearTimeout(silencio); if (!salida.destroyed) salida.destroy(); resolve(v); } };
    const vencer = () => { fin(null); req.destroy(); };
    const plazo = setTimeout(vencer, ESPERA_CUERPO_TECNICA_MS);
    let silencio = setTimeout(vencer, ESPERA_SILENCIO_TECNICA_MS);
    salida.on('error', () => { fin(null); req.destroy(); });
    req.on('data', (c) => {
      total += c.length;
      clearTimeout(silencio); silencio = setTimeout(vencer, ESPERA_SILENCIO_TECNICA_MS);
      if (total > largo) { fin(null); req.destroy(); return; }
      if (cabecera.length < 12) cabecera = Buffer.concat([cabecera, c]).subarray(0, 12);
      if (!salida.write(c)) { req.pause(); salida.once('drain', () => req.resume()); }
    });
    req.on('end', () => { recibido = true; clearTimeout(silencio); salida.end(() => { if (!listo) { listo = true; clearTimeout(plazo); resolve({ total, cabecera }); } }); });
    req.on('close', () => { if (!recibido) fin(null); });     // después de `end` también llega `close`: ahí manda el disco
    req.on('error', () => fin(null));
  });
}

// ── POST /tecnica/upload — cuerpo: el video crudo; x-tecnica-token, x-tecnica-id, Content-Length ──
// Idempotente: un reintento contesta `ya`. Subir ES enviar: la fila pasa a `enviado` al registrarse.
async function handleTecnicaUpload(req, res, origin) {
  let ocupada = null, dir = null;
  try {
    if (!SERVICE_KEY) return rechazarTecnica(req, res, 503, 'servicio no configurado', origin);
    const token = req.headers['x-tecnica-token'];
    const id = String(req.headers['x-tecnica-id'] || '').toLowerCase();
    const largo = Number(req.headers['content-length']);
    if (!UUID_TECNICA.test(id)) return rechazarTecnica(req, res, 400, 'id inválido', origin);
    if (!Number.isInteger(largo) || largo <= 0) return rechazarTecnica(req, res, 411, 'falta el largo', origin);
    if (largo > MAX_TECNICA_B) return rechazarTecnica(req, res, 413, 'video muy pesado', origin);

    const clienteId = await clienteOResponder(token, res, origin);
    if (clienteId === undefined) { res.once('finish', () => drenarOCortarTecnica(req)); return; }
    if (!clienteId) return rechazarTecnica(req, res, 403, 'token inválido', origin);

    const antes = await rpcTecnica('mypump_tecnica_puede', { p_cliente_id: clienteId, p_id: id });
    if (antes === 'ya') { req.resume(); return send(res, 200, { ok: true, ya: true }, origin); }
    if (antes !== 'ok') {
      const [status, error] = RECHAZOS_TECNICA[antes] || [];
      if (!status) throw new ErrorServicioTecnica('puede: respuesta inesperada');
      return rechazarTecnica(req, res, status, error, origin);
    }
    if (overLimit(token, 'tecnica', { contar: false })) return rechazarTecnica(req, res, 429, 'muchos videos por hoy, probá mañana', origin);
    if (tecnicaEnCurso.has(clienteId) || tecnicaEnCurso.size >= MAX_TECNICA_EN_CURSO) return rechazarTecnica(req, res, 429, 'ocupado, probá en un rato', origin);
    tecnicaEnCurso.add(clienteId);
    ocupada = clienteId;

    await barrerTemporalesTecnica();
    dir = await mkdtempTec(joinTec(tmpdirTec(), 'tecnica-'));
    const entrada = joinTec(dir, 'entrada'), salida = joinTec(dir, 'salida.mp4');
    const c = await cuerpoADisco(req, largo, entrada);
    if (!c) return;                                   // se cortó: no hay a quién contestarle
    if (c.total !== largo) return send(res, 400, { ok: false, error: 'largo incorrecto' }, origin);
    if (c.cabecera.subarray(4, 8).toString('latin1') !== 'ftyp') return send(res, 400, { ok: false, error: 'el archivo debe ser un video MP4 o MOV' }, origin);

    let duracion;
    try {
      const out = await correrTecnica(FFPROBE_TECNICA, ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'format=duration:stream=codec_type', '-of', 'json', entrada]);
      const d = JSON.parse(out);
      if (!d.streams?.length) return send(res, 400, { ok: false, error: 'el video no se puede leer' }, origin);
      duracion = Number(d.format?.duration);
    } catch (e) {
      if (e instanceof SyntaxError || e.killed) throw e;      // salida rota o colgado: nuestra falla, 503
      if (e.code === 'ENOENT') throw e;                       // sin binario, también
      return send(res, 400, { ok: false, error: 'el video no se puede leer' }, origin);
    }
    if (!Number.isFinite(duracion) || duracion < DURACION_MIN_TECNICA) return send(res, 400, { ok: false, error: 'video muy corto' }, origin);
    if (duracion > DURACION_MAX_TECNICA + 0.5) return send(res, 400, { ok: false, error: 'video muy largo' }, origin);

    try {
      await correrTecnica(FFMPEG_TECNICA, ['-nostdin', '-v', 'error', '-y', '-protocol_whitelist', 'file', '-i', entrada, '-t', String(DURACION_MAX_TECNICA), '-map', '0:v:0', '-c', 'copy', '-an', '-sn', '-dn', '-map_metadata', '-1',
        '-map_chapters', '-1', '-movflags', '+faststart', salida]);
    } catch (e) {
      if (e.killed || e.code === 'ENOENT') throw e;           // colgado o sin binario: 503, se puede reintentar
      return send(res, 400, { ok: false, error: 'el video no se puede leer' }, origin);
    }
    const peso = (await statTec(salida)).size;
    if (peso <= 0 || peso > MAX_TECNICA_B) return send(res, 413, { ok: false, error: 'video muy pesado' }, origin);

    const path = `${carpetaTecnica(clienteId)}/${id}.mp4`;
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_TECNICA}/${path}`, {
      method: 'POST', signal: AbortSignal.timeout(ESPERA_CUERPO_TECNICA_MS),
      headers: svcHeaders({ 'Content-Type': 'video/mp4', 'x-upsert': 'true' }), body: await readFileTec(salida),
    });
    if (!up.ok) {
      console.error('[tecnica] storage', up.status);
      return send(res, 502, { ok: false, error: 'no se pudo guardar' }, origin);
    }
    let reg;
    try {
      reg = await rpcTecnica('mypump_tecnica_registrar', { p_cliente_id: clienteId, p_id: id, p_path: path, p_bytes: peso, p_duracion: Math.min(duracion, DURACION_MAX_TECNICA) });
    } catch (e) {
      // Con la red cortada la fila pudo haber entrado: el reintento contesta `ya` y el objeto tiene que seguir estando.
      console.error('[tecnica] registrar', e.message || e);
      return send(res, 502, { ok: false, error: 'guardado sin registrar' }, origin);
    }
    if (reg === 'ya') return send(res, 200, { ok: true, ya: true }, origin);
    if (reg !== 'ok') {
      await sacarObjetoTecnica(path);
      const [status, error] = RECHAZOS_TECNICA[reg] || [502, 'guardado sin registrar'];
      return send(res, status, { ok: false, error }, origin);
    }
    sumarUso(token, 'tecnica');
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[tecnica] error', e.message || e, e.detalle || '');
    if (res.headersSent) return;
    rechazarTecnica(req, res, 503, 'no se pudo subir, probá en un rato', origin);
  } finally {
    if (ocupada) tecnicaEnCurso.delete(ocupada);
    if (dir) await rmTec(dir, { recursive: true, force: true }).catch((e) => console.error('[tecnica] temporal', e.message || e));
  }
}

async function sacarObjetoTecnica(path) {
  try {
    const r = await fetchTecnica(`${SUPABASE_URL}/storage/v1/object/${BUCKET_TECNICA}`, { method: 'DELETE', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ prefixes: [path] }) });
    if (!r.ok) throw new ErrorServicioTecnica(`HTTP ${r.status}`);
    return true;
  } catch (e) {
    console.error('[tecnica] sacar objeto', e.message || e);
    return false;
  }
}

async function jsonTecnica(req, res, origin) {
  const data = await leerBody(req, res, origin, 4 * 1024);
  if (data && typeof data === 'object' && !Array.isArray(data)) return data;
  if (!res.headersSent && !req.socket?.destroyed) send(res, 400, { ok: false, error: 'pedido inválido' }, origin);
  return null;
}

// ── POST /tecnica/url — { token, id } ── URL firmada de SU video, por una hora. Nunca firma un path del pedido.
async function handleTecnicaUrl(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await jsonTecnica(req, res, origin);
    if (!data) return;
    const id = String(data.id || '').toLowerCase();
    if (!UUID_TECNICA.test(id)) return send(res, 400, { ok: false, error: 'id inválido' }, origin);
    const clienteId = await clienteOResponder(data.token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
    const r = await fetchTecnica(`${SUPABASE_URL}/rest/v1/mypump_tecnica?id=eq.${id}&cliente_id=eq.${encodeURIComponent(clienteId)}&video_borrado_en=is.null&select=path&limit=1`, { headers: svcHeaders() });
    if (!r.ok) return send(res, 502, { ok: false, error: 'no se pudo leer' }, origin);
    const filas = await r.json();
    if (!Array.isArray(filas) || !filas[0]?.path) return send(res, 404, { ok: false, error: 'sin video' }, origin);
    const fr = await fetchTecnica(`${SUPABASE_URL}/storage/v1/object/sign/${BUCKET_TECNICA}/${filas[0].path}`, { method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ expiresIn: 3600 }) });
    if (!fr.ok) return send(res, 502, { ok: false, error: 'no se pudo firmar' }, origin);
    const firmado = await fr.json();
    if (!firmado?.signedURL) return send(res, 502, { ok: false, error: 'no se pudo firmar' }, origin);
    send(res, 200, { ok: true, url: `${SUPABASE_URL}/storage/v1${firmado.signedURL}`, expira_en: 3600 }, origin);
  } catch (e) {
    console.error('[tecnica] url', e.message || e);
    if (!res.headersSent) send(res, 502, { ok: false, error: 'error al firmar' }, origin);
  }
}

// ── POST /tecnica/borrar — { token, id } ── El alumno saca su video.
async function handleTecnicaBorrar(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await jsonTecnica(req, res, origin);
    if (!data) return;
    const id = String(data.id || '').toLowerCase();
    if (!UUID_TECNICA.test(id)) return send(res, 400, { ok: false, error: 'id inválido' }, origin);
    const clienteId = await clienteOResponder(data.token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
    // Primero el objeto y recién después la marca: si Storage falla, el reintento del teléfono vuelve a encontrar el path.
    const q = await fetchTecnica(`${SUPABASE_URL}/rest/v1/mypump_tecnica?id=eq.${id}&cliente_id=eq.${encodeURIComponent(clienteId)}&video_borrado_en=is.null&select=path,estado&limit=1`, { headers: svcHeaders() });
    if (!q.ok) throw new ErrorServicioTecnica(`leer: HTTP ${q.status}`);
    const filas = await q.json();
    if (!Array.isArray(filas)) throw new ErrorServicioTecnica('leer: respuesta inesperada');
    if (!filas[0]?.path) return send(res, 200, { ok: true, ya: true }, origin);
    if (filas[0].estado === 'procesando') return send(res, 409, { ok: false, error: 'se está procesando, probá en un rato' }, origin);
    if (!await sacarObjetoTecnica(filas[0].path)) throw new ErrorServicioTecnica('no se pudo sacar el objeto');
    const r = await rpcTecnica('mypump_tecnica_borrar_video', { p_cliente_id: clienteId, p_id: id });
    if (r?.resultado === 'estado') return send(res, 409, { ok: false, error: 'se está procesando, probá en un rato' }, origin);
    if (r?.resultado !== 'ok' && r?.resultado !== 'no_encontrado') throw new ErrorServicioTecnica('borrar: respuesta inesperada');
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[tecnica] borrar', e.message || e);
    if (!res.headersSent) send(res, 503, { ok: false, error: 'no se pudo borrar, probá en un rato' }, origin);
  }
}
