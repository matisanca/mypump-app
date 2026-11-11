// PROPUESTA, SIN APLICAR: los endpoints de «Fotos de inicio» para sumar a mini-vision/server.mjs (se prueba contra un doble
// local: `node --test supabase/propuestas/nativa_fotos_inicio_minivision.test.mjs`).
// Rutas, antes de la de /vision:
//   if (req.method === 'POST' && req.url === '/inicio/upload') return handleInicioUpload(req, res, origin);
//   if (req.method === 'POST' && req.url === '/inicio/urls')   return handleInicioUrls(req, res, origin);
//   if (req.method === 'POST' && req.url === '/inicio/borrar') return handleInicioBorrar(req, res, origin);
// En overLimit, el tope de esta función:
//   sumar la rama `feature === 'inicio' ? RATE_INICIO :` justo antes del `RATE_LIMIT` final de `const tope`, sin tocar las demás.
// En send(), para que la web pueda mandar los encabezados (fetch hace un preflight), SUMAR a los que ya estén:
//   x-inicio-token, x-inicio-foto, x-inicio-pose, x-inicio-tomada, x-inicio-brillo, x-inicio-nitidez
//
// INVARIANTES
// - El cliente_id sale del TOKEN, jamás del pedido. El path lo arma el servidor; a la app nunca le llega.
// - El cuerpo se lee recién con el token y el permiso de la base.
// - Lo que se guarda no lleva EXIF, GPS, XMP ni comentarios: se sacan acá aunque el teléfono ya los haya sacado. Si el JPEG no
//   se puede recorrer, no se guarda nada (fail-closed).
// - El ancho y el alto se leen del JPEG, no del pedido. Una pose del cuerpo con menos de 1080 px del lado largo no entra.
// - Nada se escapa de un handler: todo error termina en una respuesta (este proceso también atiende visión y fotos).
// - El 4xx es definitivo para la cola del teléfono: por eso una falla nuestra siempre es 5xx o 429, nunca 4xx.

import { createHash as hashIni } from 'node:crypto';

const BUCKET_INICIO = 'fotos-inicio';
const MAX_INICIO_B = 4 * 1024 * 1024;             // el teléfono manda 1600 px a 0,85: menos de 1 MB
const RATE_INICIO = 40;                           // subidas por token por día: tres poses, las que se repiten y la motivación
const MIN_LADO_INICIO = 1080;
const MIN_LADO_MOTIVACION = 320;
const ESPERA_INICIO_MS = 30_000;
const ESPERA_CUERPO_INICIO_MS = 120_000;
const POSES_INICIO = new Set(['frente', 'perfil', 'espalda', 'motivacion']);
const UUID_INICIO = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const FECHA_INICIO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/;
const RECHAZOS_INICIO = {
  ajena: [409, 'id de foto repetido'], no_habilitado: [403, 'no habilitado'], tope: [413, 'llegaste al máximo de fotos'],
  chica: [422, 'la foto tiene poca resolución'],
};

const inicioEnCurso = new Set();                  // cuentas subiendo ahora: una foto por vez por cuenta

class ErrorServicioInicio extends Error {}

function fetchInicio(url, opciones = {}) {
  return fetch(url, { signal: AbortSignal.timeout(ESPERA_INICIO_MS), ...opciones });
}

async function rpcInicio(fn, cuerpo = {}) {
  const r = await fetchInicio(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify(cuerpo),
  });
  if (!r.ok) throw new ErrorServicioInicio(`${fn}: HTTP ${r.status}`);
  try { return await r.json(); } catch { throw new ErrorServicioInicio(`${fn}: respuesta no JSON`); }
}

// La carpeta de la cuenta en el bucket: no lleva el cliente_id, que en algunas cuentas contiene el nombre.
function carpetaInicio(clienteId) {
  return hashIni('sha256').update(`fotos-inicio:${clienteId}`).digest('hex').slice(0, 32);
}

// La orientación del EXIF (1 a 8), o 1 si no la trae o no se entiende.
function orientacionExifInicio(seg) {
  if (seg.length < 14 || seg.toString('latin1', 0, 6) !== 'Exif\0\0') return 1;
  const t = seg.subarray(6);
  const le = t.toString('latin1', 0, 2) === 'II';
  if (!le && t.toString('latin1', 0, 2) !== 'MM') return 1;
  const u16 = (o) => (le ? t.readUInt16LE(o) : t.readUInt16BE(o));
  const u32 = (o) => (le ? t.readUInt32LE(o) : t.readUInt32BE(o));
  try {
    const ifd = u32(4);
    const n = u16(ifd);
    for (let i = 0; i < n; i++) {
      const e = ifd + 2 + i * 12;
      if (u16(e) === 0x0112) { const v = u16(e + 8); return v >= 1 && v <= 8 ? v : 1; }
    }
  } catch { /* EXIF cortado: como si no estuviera */ }
  return 1;
}

// Recorre el JPEG, saca todo lo que no hace a la imagen (EXIF, GPS, XMP, IPTC, comentarios) y lee el tamaño.
// Devuelve { buf, ancho, alto }, 'girada' si la orientación venía sin aplicar, o null si no es un JPEG que se pueda recorrer.
function limpiarJpegInicio(buf) {
  if (buf.length < 4 || buf[0] !== 0xff || buf[1] !== 0xd8) return null;
  const partes = [buf.subarray(0, 2)];
  let i = 2, ancho = 0, alto = 0;
  while (i + 4 <= buf.length) {
    if (buf[i] !== 0xff) return null;
    let m = buf[i + 1];
    while (m === 0xff && i + 2 < buf.length) { i += 1; m = buf[i + 1]; }   // relleno
    if (i + 4 > buf.length) return null;                                     // el relleno llegó al final: no es un JPEG entero
    if (m === 0xd8 || m === 0x00 || (m >= 0xd0 && m <= 0xd7) || m === 0x01) return null;   // no van antes del SOS
    if (m === 0xd9) return null;                                             // terminó sin imagen
    const largo = buf.readUInt16BE(i + 2);
    if (largo < 2 || i + 2 + largo > buf.length) return null;
    const seg = buf.subarray(i + 4, i + 2 + largo);
    const esSOF = m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc;
    if (esSOF) {
      if (seg.length < 5) return null;
      alto = seg.readUInt16BE(1); ancho = seg.readUInt16BE(3);
    }
    if (m === 0xe1 && orientacionExifInicio(seg) !== 1) return 'girada';
    const icc = m === 0xe2 && seg.toString('latin1', 0, 12) === 'ICC_PROFILE\0';
    const adobe = m === 0xee && seg.toString('latin1', 0, 5) === 'Adobe';
    const fuera = (m >= 0xe1 && m <= 0xef && !icc && !adobe) || m === 0xfe;
    if (!fuera) partes.push(buf.subarray(i, i + 2 + largo));
    i += 2 + largo;
    if (m === 0xda) {                                                        // desde acá, la imagen comprimida tal cual
      if (!ancho || !alto) return null;
      const resto = buf.subarray(i);
      if (resto.length < 2 || resto[resto.length - 2] !== 0xff || resto[resto.length - 1] !== 0xd9) return null;   // cortada
      partes.push(resto);
      return { buf: Buffer.concat(partes), ancho, alto };
    }
  }
  return null;
}

// Después de responder se lee lo que falte del cuerpo, con tope de bytes y de tiempo. Cortar la conexión con la subida a medio
// camino hace que el navegador vea un corte de red y no el 4xx, y la foto se reintentaría sin fin.
const DRENAR_INICIO_MS = 15_000;
const MAX_DRENANDO_INICIO = 16;
let drenandoInicio = 0;
function drenarOCortarInicio(req) {
  if (req.complete || req.destroyed) return;
  if (drenandoInicio >= MAX_DRENANDO_INICIO) { req.destroy(); return; }
  drenandoInicio++;
  let leidos = 0, listo = false;
  const terminar = () => { if (!listo) { listo = true; drenandoInicio--; clearTimeout(plazo); } };
  const cortar = () => { terminar(); req.destroy(); };
  const plazo = setTimeout(cortar, DRENAR_INICIO_MS);
  plazo.unref?.();
  req.on('data', (c) => { leidos += c.length; if (leidos > MAX_INICIO_B) cortar(); });
  req.once('end', terminar);
  req.once('close', terminar);
  req.once('error', cortar);
}

function rechazarInicio(req, res, status, error, origin) {
  res.once('finish', () => drenarOCortarInicio(req));
  send(res, status, { ok: false, error }, origin);
}

function leerCuerpoInicio(req, largo) {
  return new Promise((resolve) => {
    if (req.destroyed || req.socket?.destroyed) return resolve(null);
    const partes = [];
    let total = 0, listo = false;
    const fin = (v) => { if (!listo) { listo = true; clearTimeout(plazo); resolve(v); } };
    const plazo = setTimeout(() => { fin(null); req.destroy(); }, ESPERA_CUERPO_INICIO_MS);
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

// Saca del bucket lo que la base dio por reemplazado o borrado, y recién ahí se va la fila. Lo que falle queda para el barrido.
async function sacarObjetosInicio(lista) {
  for (const x of Array.isArray(lista) ? lista : []) {
    if (!x || typeof x.path !== 'string' || !UUID_INICIO.test(String(x.id))) continue;
    try {
      const r = await fetchInicio(`${SUPABASE_URL}/storage/v1/object/${BUCKET_INICIO}`, {
        method: 'DELETE', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ prefixes: [x.path] }),
      });
      if (!r.ok) throw new ErrorServicioInicio(`HTTP ${r.status}`);
      await rpcInicio('mypump_fotos_inicio_borrada', { p_foto_id: x.id });
    } catch (e) {
      console.error('[inicio] sacar objeto', e.message || e);   // la fila queda sin vigencia: la levanta el barrido
    }
  }
}

// El barrido: lo que quedó sin sacar de otras veces. De a poco, después de una subida, sin frenar la respuesta.
let barriendoInicio = false;
async function barrerInicio() {
  if (barriendoInicio) return;
  barriendoInicio = true;
  try { await sacarObjetosInicio(await rpcInicio('mypump_fotos_inicio_para_limpiar', { p_limite: 20 })); }
  catch (e) { console.error('[inicio] barrido', e.message || e); }
  finally { barriendoInicio = false; }
}

function numeroInicio(v, max) {
  const n = Number(v);
  return typeof v === 'string' && v.length <= 12 && Number.isFinite(n) && n >= 0 && n <= max ? n : null;
}

// ── POST /inicio/upload — cuerpo: el JPEG crudo; x-inicio-token, x-inicio-foto, x-inicio-pose, Content-Length ──
// Opcionales: x-inicio-tomada (ISO 8601 con zona), x-inicio-brillo y x-inicio-nitidez (lo que midió el control del teléfono).
// Idempotente: el id de la foto lo manda el teléfono. Un reintento contesta `ya` sin volver a guardar.
async function handleInicioUpload(req, res, origin) {
  let ocupada = null;
  try {
    if (!SERVICE_KEY) return rechazarInicio(req, res, 503, 'servicio no configurado', origin);
    const token = req.headers['x-inicio-token'];
    const fotoId = String(req.headers['x-inicio-foto'] || '').toLowerCase();
    const pose = req.headers['x-inicio-pose'];
    const largo = Number(req.headers['content-length']);
    const tomadaCruda = req.headers['x-inicio-tomada'];
    const tomada = typeof tomadaCruda === 'string' && FECHA_INICIO.test(tomadaCruda) && !Number.isNaN(Date.parse(tomadaCruda)) ? tomadaCruda : null;
    if (!UUID_INICIO.test(fotoId)) return rechazarInicio(req, res, 400, 'id inválido', origin);
    if (typeof pose !== 'string' || !POSES_INICIO.has(pose)) return rechazarInicio(req, res, 400, 'pose inválida', origin);
    if (!Number.isInteger(largo) || largo <= 0) return rechazarInicio(req, res, 411, 'falta el largo', origin);
    if (largo > MAX_INICIO_B) return rechazarInicio(req, res, 413, 'foto muy grande', origin);

    const clienteId = await clienteOResponder(token, res, origin);
    if (clienteId === undefined) { res.once('finish', () => drenarOCortarInicio(req)); return; }
    if (!clienteId) return rechazarInicio(req, res, 403, 'token inválido', origin);

    const antes = await rpcInicio('mypump_fotos_inicio_puede', { p_cliente_id: clienteId, p_foto_id: fotoId, p_pose: pose });
    if (antes === 'ya') { req.resume(); return send(res, 200, { ok: true, ya: true }, origin); }
    if (antes !== 'ok') {
      const [status, error] = RECHAZOS_INICIO[antes] || [];
      if (!status) throw new ErrorServicioInicio('puede: respuesta inesperada');
      return rechazarInicio(req, res, status, error, origin);
    }
    if (overLimit(token, 'inicio', { contar: false })) return rechazarInicio(req, res, 429, 'muchas fotos por hoy, probá mañana', origin);
    if (inicioEnCurso.has(clienteId)) return rechazarInicio(req, res, 429, 'ocupado, probá en un rato', origin);
    inicioEnCurso.add(clienteId);
    ocupada = clienteId;

    const buf = await leerCuerpoInicio(req, largo);
    if (!buf) return;                                 // se cortó: no hay a quién contestarle
    if (buf.length !== largo) return send(res, 400, { ok: false, error: 'largo incorrecto' }, origin);
    const limpia = limpiarJpegInicio(buf);
    if (limpia === null) return send(res, 400, { ok: false, error: 'la imagen no se puede leer' }, origin);
    if (limpia === 'girada') return send(res, 400, { ok: false, error: 'la imagen vino sin enderezar' }, origin);
    const lado = Math.max(limpia.ancho, limpia.alto);
    if (lado < (pose === 'motivacion' ? MIN_LADO_MOTIVACION : MIN_LADO_INICIO)) return send(res, 422, { ok: false, error: 'la foto tiene poca resolución' }, origin);

    const path = `${carpetaInicio(clienteId)}/${fotoId}.jpg`;
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_INICIO}/${path}`, {
      method: 'POST',
      signal: AbortSignal.timeout(ESPERA_CUERPO_INICIO_MS),
      headers: svcHeaders({ 'Content-Type': 'image/jpeg', 'x-upsert': 'true' }),
      body: limpia.buf,
    });
    if (!up.ok) {
      console.error('[inicio] storage', up.status);
      return send(res, 502, { ok: false, error: 'no se pudo guardar' }, origin);
    }

    let reg;
    try {
      reg = await rpcInicio('mypump_fotos_inicio_registrar', {
        p_cliente_id: clienteId, p_foto_id: fotoId, p_pose: pose, p_path: path, p_bytes: limpia.buf.length,
        p_ancho: limpia.ancho, p_alto: limpia.alto, p_tomada_en: tomada,
        p_brillo: numeroInicio(req.headers['x-inicio-brillo'], 255), p_nitidez: numeroInicio(req.headers['x-inicio-nitidez'], 100000),
      });
    } catch (e) {
      // Con la red cortada la fila pudo haber entrado: el reintento contesta `ya` y el objeto tiene que seguir estando.
      console.error('[inicio] registrar', e.message || e);
      return send(res, 502, { ok: false, error: 'guardada sin registrar' }, origin);
    }
    if (reg?.resultado === 'ya') return send(res, 200, { ok: true, ya: true }, origin);
    if (reg?.resultado !== 'ok') {
      // Cambió mientras subía (la cerraron, llegó al tope): el objeto no tiene fila y se saca acá.
      await fetchInicio(`${SUPABASE_URL}/storage/v1/object/${BUCKET_INICIO}`, {
        method: 'DELETE', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ prefixes: [path] }),
      }).catch((e) => console.error('[inicio] sacar sin fila', e.message || e));
      const [status, error] = RECHAZOS_INICIO[reg?.resultado] || [502, 'guardada sin registrar'];
      return send(res, status, { ok: false, error }, origin);
    }
    sumarUso(token, 'inicio');
    send(res, 200, { ok: true, ancho: limpia.ancho, alto: limpia.alto }, origin);
    await sacarObjetosInicio(reg.borrar);             // la que reemplazó, ya con la respuesta mandada
    barrerInicio();
  } catch (e) {
    console.error('[inicio] error', e.message || e);
    if (res.headersSent) return;
    rechazarInicio(req, res, 503, 'no se pudo subir, probá en un rato', origin);
  } finally {
    if (ocupada) inicioEnCurso.delete(ocupada);
  }
}

// El cuerpo JSON de los otros dos: chico y con tope. null si ya se contestó o se cortó.
async function jsonInicio(req, res, origin) {
  const data = await leerBody(req, res, origin, 4 * 1024);
  if (data && typeof data === 'object' && !Array.isArray(data)) return data;
  if (!res.headersSent && !req.socket?.destroyed) send(res, 400, { ok: false, error: 'pedido inválido' }, origin);
  return null;
}

// ── POST /inicio/urls — { token } ── URLs firmadas (1 h) de SUS fotos vigentes, para las miniaturas. Nunca firma un path del pedido.
async function handleInicioUrls(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await jsonInicio(req, res, origin);
    if (!data) return;
    const clienteId = await clienteOResponder(data.token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);

    const set = await rpcInicio('mypump_fotos_inicio_servicio', { p_cliente_id: clienteId });
    // Cerrado o apagado: la app ya no las muestra, y tampoco se firman.
    const habilitado = await rpcInicio('mypump_fotos_inicio_habilitado', { p_cliente_id: clienteId });
    const filas = habilitado === true && set && Array.isArray(set.fotos) ? set.fotos : [];
    if (!filas.length) return send(res, 200, { ok: true, fotos: [] }, origin);

    const fr = await fetchInicio(`${SUPABASE_URL}/storage/v1/object/sign/${BUCKET_INICIO}`, {
      method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ expiresIn: 3600, paths: filas.map((f) => f.path) }),
    });
    if (!fr.ok) return send(res, 502, { ok: false, error: 'no se pudieron firmar' }, origin);
    const firmadas = await fr.json();
    const porPath = Object.fromEntries((Array.isArray(firmadas) ? firmadas : []).map((x) => [String(x.path).replace(/^\/+/, ''), x.signedURL]));
    const fotos = filas.filter((f) => porPath[f.path]).map((f) => ({ id: f.id, pose: f.pose, url: `${SUPABASE_URL}/storage/v1${porPath[f.path]}` }));
    send(res, 200, { ok: true, fotos, expira_en: 3600 }, origin);
  } catch (e) {
    console.error('[inicio] urls', e.message || e);
    if (!res.headersSent) send(res, 502, { ok: false, error: 'error al firmar' }, origin);
  }
}

// ── POST /inicio/borrar — { token, foto_id } ── Saca una foto de «el físico que te motiva». Las del cuerpo se reemplazan.
async function handleInicioBorrar(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await jsonInicio(req, res, origin);
    if (!data) return;
    const fotoId = String(data.foto_id || '').toLowerCase();
    if (!UUID_INICIO.test(fotoId)) return send(res, 400, { ok: false, error: 'id inválido' }, origin);
    const clienteId = await clienteOResponder(data.token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);

    const r = await rpcInicio('mypump_fotos_inicio_borrar', { p_cliente_id: clienteId, p_foto_id: fotoId });
    if (r?.resultado === 'no_encontrado') return send(res, 200, { ok: true, ya: true }, origin);   // ya estaba borrada
    if (r?.resultado === 'no_se_puede') return send(res, 409, { ok: false, error: 'esa foto se reemplaza, no se borra' }, origin);
    if (r?.resultado === 'no_habilitado') return send(res, 403, { ok: false, error: 'no habilitado' }, origin);
    if (r?.resultado !== 'ok' || typeof r.path !== 'string') throw new ErrorServicioInicio('borrar: respuesta inesperada');
    send(res, 200, { ok: true }, origin);
    await sacarObjetosInicio([{ id: r.id, path: r.path }]);
  } catch (e) {
    console.error('[inicio] borrar', e.message || e);
    if (!res.headersSent) send(res, 503, { ok: false, error: 'no se pudo borrar, probá en un rato' }, origin);
  }
}
