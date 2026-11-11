// PROPUESTA, SIN APLICAR: los endpoints de «Estudios y órdenes» para sumar a mini-vision/server.mjs (se prueba contra un doble
// local: `node --test supabase/propuestas/nativa_estudios_minivision.test.mjs`).
// Rutas, antes de la de /vision:
//   if (req.method === 'POST' && req.url === '/estudios/upload') return handleEstudiosUpload(req, res, origin);
//   if (req.method === 'POST' && req.url === '/estudios/urls')   return handleEstudiosUrls(req, res, origin);
// En overLimit, sumar la rama `feature === 'estudios' ? RATE_ESTUDIOS :` justo antes del `RATE_LIMIT` final de `const tope`,
// sin tocar las que ya estén (reps, gimnasio, técnica).
// En send(), sumar a 'Access-Control-Allow-Headers' (sin sacar los que ya estén): x-estudios-token, x-estudios-envio, x-estudios-archivo
//
// INVARIANTES
// - El cliente_id sale del TOKEN, jamás del pedido. El path lo arma el servidor; a la app nunca le llega.
// - El cuerpo se lee recién con el token, el envío abierto y lugar libre.
// - Solo PDF y JPEG, mirando los bytes y no el encabezado. Al JPEG se le sacan los metadatos (EXIF con ubicación) antes de guardar.
// - Lo único que se firma es lo que devuelve `mypump_estudios_paths_para_firmar` para ESE cliente, y además cada path tiene
//   que caer en su carpeta. Nunca se firma un path del pedido. Las URL duran 10 minutos.
// - Nada se escapa de un handler: todo error termina en una respuesta.
// - El 4xx es definitivo para la cola del teléfono: una falla nuestra siempre es 5xx o 429. Token caído = 401 (el teléfono
//   conserva la cola: puede ser un link regenerado); 403 = la cuenta no tiene la función.

import { createHash as hashEst } from 'node:crypto';

const BUCKET_ESTUDIOS = 'estudios';
const BUCKET_ANALISIS = 'analisis';                // el del bot en este proyecto: privado
const MAX_ESTUDIO_B = 20 * 1024 * 1024;
const RATE_ESTUDIOS = 80;                          // archivos por token por día
const MAX_ESTUDIOS_EN_CURSO = 3;                   // a la vez en todo el servicio (cada uno retiene hasta 20 MB en memoria)
const ESPERA_ESTUDIOS_MS = 30_000;
const ESPERA_CUERPO_ESTUDIOS_MS = 180_000;
const FIRMA_ESTUDIOS_S = 600;
const UUID_ESTUDIOS = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const RECHAZOS_ESTUDIOS = {
  no_encontrado: [404, 'envío no encontrado'], ajeno: [409, 'id de archivo repetido'], estado: [409, 'este envío ya no recibe archivos'],
  tope: [413, 'llegaste al máximo de archivos'], no_habilitado: [403, 'no habilitado'],
};

const estudiosEnCurso = new Set();

class ErrorServicioEstudios extends Error {}

function fetchEstudios(url, opciones = {}) {
  return fetch(url, { signal: AbortSignal.timeout(ESPERA_ESTUDIOS_MS), ...opciones });
}

async function rpcEstudios(fn, cuerpo = {}) {
  const r = await fetchEstudios(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify(cuerpo),
  });
  if (!r.ok) throw new ErrorServicioEstudios(`${fn}: HTTP ${r.status}`);
  try { return await r.json(); } catch { throw new ErrorServicioEstudios(`${fn}: respuesta no JSON`); }
}

// La carpeta de la cuenta en el bucket: no lleva el cliente_id, que en algunas cuentas contiene el nombre.
function carpetaEstudios(clienteId) {
  return hashEst('sha256').update(`estudios:${clienteId}`).digest('hex').slice(0, 32);
}

// Después de responder se lee lo que falte del cuerpo, con tope de bytes y de tiempo: cortar la conexión a mitad de la subida
// hace que el navegador vea un corte de red y no el 4xx, y el archivo se reintentaría sin fin.
const DRENAR_ESTUDIOS_MS = 15_000;
const MAX_DRENANDO_ESTUDIOS = 8;
let drenandoEstudios = 0;
function drenarOCortarEstudios(req) {
  if (req.complete || req.destroyed) return;
  if (drenandoEstudios >= MAX_DRENANDO_ESTUDIOS) { req.destroy(); return; }
  drenandoEstudios++;
  let leidos = 0, listo = false;
  const terminar = () => { if (!listo) { listo = true; drenandoEstudios--; clearTimeout(plazo); } };
  const cortar = () => { terminar(); req.destroy(); };
  const plazo = setTimeout(cortar, DRENAR_ESTUDIOS_MS);
  plazo.unref?.();
  req.on('data', (c) => { leidos += c.length; if (leidos > MAX_ESTUDIO_B) cortar(); });
  req.once('end', terminar);
  req.once('close', terminar);
  req.once('error', cortar);
}

function rechazarEstudios(req, res, status, error, origin) {
  res.once('finish', () => drenarOCortarEstudios(req));
  send(res, status, { ok: false, error }, origin);
}

function leerCuerpoEstudios(req, largo) {
  return new Promise((resolve) => {
    if (req.destroyed || req.socket?.destroyed) return resolve(null);
    const partes = [];
    let total = 0, listo = false;
    const fin = (v) => { if (!listo) { listo = true; clearTimeout(plazo); resolve(v); } };
    const plazo = setTimeout(() => { fin(null); req.destroy(); }, ESPERA_CUERPO_ESTUDIOS_MS);
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

// Saca del JPEG los bloques de metadatos (APP1 a APP15 y comentarios: EXIF con ubicación, XMP, miniaturas). Deja APP0 (JFIF),
// APP2 si es el perfil de color y APP14 de Adobe (sin él, algunos JPEG se ven con los colores cambiados).
// Devuelve null si no es un JPEG bien formado.
function limpiarJpegEstudios(buf) {
  if (!(buf.length > 4 && buf[0] === 0xff && buf[1] === 0xd8)) return null;
  const partes = [buf.subarray(0, 2)];
  let i = 2;
  while (i + 4 <= buf.length) {
    if (buf[i] !== 0xff) return null;
    const m = buf[i + 1];
    if (m === 0xff) { i += 1; continue; }                                   // relleno
    if (m === 0xda) { partes.push(buf.subarray(i)); return Buffer.concat(partes); }   // empieza la imagen: el resto va tal cual
    if (m === 0xd9) return null;                                            // terminó sin imagen
    const largo = buf.readUInt16BE(i + 2);
    if (largo < 2 || i + 2 + largo > buf.length) return null;
    const seg = buf.subarray(i, i + 2 + largo);
    const esIcc = m === 0xe2 && seg.subarray(4, 15).toString('latin1') === 'ICC_PROFILE';
    const esAdobe = m === 0xee && seg.subarray(4, 9).toString('latin1') === 'Adobe';
    const sacar = (m >= 0xe1 && m <= 0xef && !esIcc && !esAdobe) || m === 0xfe;
    if (!sacar) partes.push(seg);
    i += 2 + largo;
  }
  return null;
}

async function sacarObjetoEstudios(path) {
  try {
    const r = await fetchEstudios(`${SUPABASE_URL}/storage/v1/object/${BUCKET_ESTUDIOS}`, {
      method: 'DELETE', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ prefixes: [path] }),
    });
    if (!r.ok) throw new ErrorServicioEstudios(`HTTP ${r.status}`);
  } catch (e) {
    console.error('[estudios] sacar objeto', e.message || e);
  }
}

// ── POST /estudios/upload — cuerpo: el PDF o el JPEG crudo; x-estudios-token, x-estudios-envio, x-estudios-archivo, Content-Length ──
// Idempotente: los ids los manda el teléfono. Un reintento contesta `ya` sin volver a guardar.
async function handleEstudiosUpload(req, res, origin) {
  let ocupada = null;
  try {
    if (!SERVICE_KEY) return rechazarEstudios(req, res, 503, 'servicio no configurado', origin);
    const token = req.headers['x-estudios-token'];
    const envioId = String(req.headers['x-estudios-envio'] || '').toLowerCase();
    const archivoId = String(req.headers['x-estudios-archivo'] || '').toLowerCase();
    const largo = Number(req.headers['content-length']);
    if (!UUID_ESTUDIOS.test(envioId) || !UUID_ESTUDIOS.test(archivoId)) return rechazarEstudios(req, res, 400, 'id inválido', origin);
    if (!Number.isInteger(largo) || largo <= 0) return rechazarEstudios(req, res, 411, 'falta el largo', origin);
    if (largo > MAX_ESTUDIO_B) return rechazarEstudios(req, res, 413, 'archivo muy grande', origin);

    let clienteId;
    try { clienteId = await resolverCliente(token); }
    catch (e) {
      console.warn('[estudios] no se pudo validar el token:', e.message || e);
      return rechazarEstudios(req, res, 503, 'no se pudo validar el acceso, probá en un rato', origin);
    }
    if (!clienteId) return rechazarEstudios(req, res, 401, 'token inválido', origin);

    const antes = await rpcEstudios('mypump_estudios_archivo_puede', { p_cliente_id: clienteId, p_envio_id: envioId, p_archivo_id: archivoId });
    if (antes === 'ya') { rechazarEstudiosOk(req, res, origin); return; }
    if (antes !== 'ok') {
      const [status, error] = RECHAZOS_ESTUDIOS[antes] || [];
      if (!status) throw new ErrorServicioEstudios('puede: respuesta inesperada');
      return rechazarEstudios(req, res, status, error, origin);
    }
    if (overLimit(token, 'estudios', { contar: false })) return rechazarEstudios(req, res, 429, 'muchos archivos por hoy, probá mañana', origin);
    if (estudiosEnCurso.has(clienteId) || estudiosEnCurso.size >= MAX_ESTUDIOS_EN_CURSO) return rechazarEstudios(req, res, 429, 'ocupado, probá en un rato', origin);
    estudiosEnCurso.add(clienteId);
    ocupada = clienteId;

    let buf = await leerCuerpoEstudios(req, largo);
    if (!buf) return;                                 // se cortó: no hay a quién contestarle
    if (buf.length !== largo) return send(res, 400, { ok: false, error: 'largo incorrecto' }, origin);

    let mime, ext;
    if (buf.subarray(0, 5).toString('latin1') === '%PDF-') { mime = 'application/pdf'; ext = 'pdf'; }
    else if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
      buf = limpiarJpegEstudios(buf);
      if (!buf) return send(res, 400, { ok: false, error: 'la imagen no se puede leer' }, origin);
      mime = 'image/jpeg'; ext = 'jpg';
    } else return send(res, 400, { ok: false, error: 'tiene que ser un PDF o una foto JPEG' }, origin);

    const sha256 = hashEst('sha256').update(buf).digest('hex');
    const path = `e/${carpetaEstudios(clienteId)}/${envioId}/${archivoId}.${ext}`;
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_ESTUDIOS}/${path}`, {
      method: 'POST',
      signal: AbortSignal.timeout(ESPERA_CUERPO_ESTUDIOS_MS),
      headers: svcHeaders({ 'Content-Type': mime, 'x-upsert': 'true' }),
      body: buf,
    });
    if (!up.ok) {
      console.error('[estudios] storage', up.status);
      return send(res, 502, { ok: false, error: 'no se pudo guardar' }, origin);
    }

    let reg;
    try {
      reg = await rpcEstudios('mypump_estudios_archivo_registrar', {
        p_cliente_id: clienteId, p_envio_id: envioId, p_archivo_id: archivoId, p_path: path, p_mime: mime, p_bytes: buf.length, p_sha256: sha256,
      });
    } catch (e) {
      // Con la red cortada la fila pudo haber entrado: el reintento contesta `ya` y el objeto tiene que seguir estando.
      console.error('[estudios] registrar', e.message || e);
      return send(res, 502, { ok: false, error: 'guardado sin registrar' }, origin);
    }
    if (reg === 'ya') return send(res, 200, { ok: true, ya: true }, origin);
    if (reg !== 'ok') {
      await sacarObjetoEstudios(path);                // cambió mientras se subía (lo enviaron, llegó al tope)
      const [status, error] = RECHAZOS_ESTUDIOS[reg] || [502, 'guardado sin registrar'];
      return send(res, status, { ok: false, error }, origin);
    }
    sumarUso(token, 'estudios');
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[estudios] error', e.message || e);
    if (res.headersSent) return;
    rechazarEstudios(req, res, 503, 'no se pudo subir, probá en un rato', origin);
  } finally {
    if (ocupada) estudiosEnCurso.delete(ocupada);
  }
}

// El reintento de algo ya guardado: 200 sin leer el cuerpo (se drena con tope).
function rechazarEstudiosOk(req, res, origin) {
  res.once('finish', () => drenarOCortarEstudios(req));
  send(res, 200, { ok: true, ya: true }, origin);
}

// ── POST /estudios/urls — { token, clase: 'estudio'|'orden', id } ── URLs firmadas de 10 minutos de SU estudio o SU orden.
async function handleEstudiosUrls(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await leerBody(req, res, origin, 4 * 1024);
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      if (!res.headersSent && !req.socket?.destroyed) send(res, 400, { ok: false, error: 'pedido inválido' }, origin);
      return;
    }
    const id = String(data.id || '').toLowerCase();
    const clase = data.clase;
    if (!UUID_ESTUDIOS.test(id) || (clase !== 'estudio' && clase !== 'orden')) return send(res, 400, { ok: false, error: 'pedido inválido' }, origin);
    const clienteId = await clienteOResponder(data.token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 401, { ok: false, error: 'token inválido' }, origin);

    const r = await rpcEstudios('mypump_estudios_paths_para_firmar', { p_cliente_id: clienteId, p_clase: clase, p_id: id });
    if (r?.resultado === 'no_habilitado') return send(res, 403, { ok: false, error: 'no habilitado' }, origin);
    if (r?.resultado === 'no_encontrado') return send(res, 404, { ok: false, error: 'no encontrado' }, origin);
    if (r?.resultado === 'todavia_no') return send(res, 409, { ok: false, error: 'todavia_no' }, origin);
    if (r?.resultado !== 'ok' || !Array.isArray(r.archivos) || !r.archivos.length) throw new ErrorServicioEstudios('paths: respuesta inesperada');

    // Segunda barrera, acá: el bucket es el de la clase y cada path cae en la carpeta de este cliente.
    const bucket = clase === 'orden' ? BUCKET_ESTUDIOS : BUCKET_ANALISIS;
    const prefijo = clase === 'orden' ? `o/${carpetaEstudios(clienteId)}/` : `${clienteId}/`;
    if (r.bucket !== bucket) throw new ErrorServicioEstudios('paths: bucket inesperado');
    for (const a of r.archivos) {
      if (typeof a?.path !== 'string' || !a.path.startsWith(prefijo) || a.path.includes('..') || a.path.includes('://')) {
        throw new ErrorServicioEstudios('paths: fuera de la carpeta del cliente');
      }
    }

    const fr = await fetchEstudios(`${SUPABASE_URL}/storage/v1/object/sign/${bucket}`, {
      method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ expiresIn: FIRMA_ESTUDIOS_S, paths: r.archivos.map((a) => a.path) }),
    });
    if (!fr.ok) return send(res, 502, { ok: false, error: 'no se pudieron firmar' }, origin);
    const firmadas = await fr.json();
    const porPath = Object.fromEntries((Array.isArray(firmadas) ? firmadas : []).filter((x) => x && x.signedURL && !x.error)
      .map((x) => [String(x.path).replace(/^\/+/, ''), x.signedURL]));
    if (r.archivos.some((a) => !porPath[a.path])) return send(res, 502, { ok: false, error: 'no se pudieron firmar' }, origin);
    // El nombre con que se baja es neutro: el del bot puede traer el nombre o el documento del paciente.
    const EXT = { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic' };
    const archivos = r.archivos.map((a, n) => {
      const mime = EXT[a.mime] ? a.mime : 'application/pdf';
      return { url: `${SUPABASE_URL}/storage/v1${porPath[a.path]}&download=${clase}-${n + 1}.${EXT[mime]}`, mime };
    });
    send(res, 200, { ok: true, archivos, expira_en: FIRMA_ESTUDIOS_S }, origin);
  } catch (e) {
    console.error('[estudios] urls', e.message || e);
    if (!res.headersSent) send(res, 502, { ok: false, error: 'error al firmar' }, origin);
  }
}
