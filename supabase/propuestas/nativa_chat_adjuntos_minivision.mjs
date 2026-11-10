// PROPUESTA, SIN APLICAR: los endpoints de Fotos y audios en el chat para sumar a mini-vision/server.mjs (se prueba contra un
// doble local: `node --test supabase/propuestas/nativa_chat_adjuntos_minivision.test.mjs`).
// Rutas, antes de la de /vision:
//   if (req.method === 'POST' && req.url === '/chat/adjunto') return handleChatAdjunto(req, res, origin);
//   if (req.method === 'POST' && req.url === '/chat/urls')    return handleChatUrls(req, res, origin);
// En overLimit, el tope de esta función: sumar la rama `feature === 'chat' ? RATE_CHAT :` justo antes del `RATE_LIMIT` final
// de `const tope`, sin tocar las demás (el server.mjs vivo puede tener `reps`, `gimnasio`, `tecnica`).
// En send(), para que la web pueda mandar los encabezados (fetch hace un preflight), SUMAR a la lista que haya:
//   x-chat-token, x-chat-id, x-chat-tipo, x-chat-duracion
//
// INVARIANTES
// - El cliente_id sale del TOKEN, jamás del pedido. El path lo arma el servidor; a la app nunca le llega.
// - La carpeta es un hash del cliente_id (algunos ids llevan el nombre): ni el nombre ni el id quedan en el bucket.
// - El tipo de archivo sale de los bytes, no del encabezado. Una foto se guarda sin EXIF ni comentarios aunque el teléfono
//   los haya dejado (se sacan los segmentos APP1, APP3-APP13, APP15 y COM; quedan JFIF, ICC y Adobe).
// - El cuerpo se lee recién con el token, el tipo, el largo, la palanca y el tope. Un rechazo antes de leerlo drena el
//   cuerpo (o corta pasado un tope) para que el navegador vea el 4xx y no un corte de red que reintentaría sin fin.
// - El 4xx es definitivo para la cola del teléfono: una falla nuestra siempre es 5xx o 429, nunca 4xx.
// - Nada se escapa de un handler: todo error termina en una respuesta (este proceso también atiende visión y fotos).

import { createHash as hashChat } from 'node:crypto';

const BUCKET_CHAT = 'chat-adjuntos';
const MAX_CHAT_FOTO_B = 3 * 1024 * 1024;        // la app la reduce a 1600 px: 0,3-0,8 MB
const MAX_CHAT_AUDIO_B = 3 * 1024 * 1024;       // 2 min a 64 kbps ≈ 1 MB; webm/opus de la web, menos
const MAX_CHAT_AUDIO_S = 125;                   // la app corta a los 120 s
const RATE_CHAT = 40;                           // subidas por token por día (en memoria, contra abuso; el de la base es 30/24 h)
const ESPERA_CHAT_MS = 30_000;
const ESPERA_CUERPO_CHAT_MS = 120_000;
const UUID_CHAT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const RECHAZOS_CHAT = {
  ajena: [409, 'id repetido'], no_habilitado: [403, 'no habilitado'], tope: [429, 'muchos adjuntos por hoy, probá mañana'],
};
const EXT_CHAT = { 'image/jpeg': 'jpg', 'audio/mp4': 'm4a', 'audio/webm': 'webm', 'audio/ogg': 'ogg' };

class ErrorServicioChat extends Error {}

function fetchChat(url, opciones = {}) {
  return fetch(url, { signal: AbortSignal.timeout(ESPERA_CHAT_MS), ...opciones });
}

async function rpcChat(fn, cuerpo = {}) {
  const r = await fetchChat(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify(cuerpo),
  });
  if (!r.ok) throw new ErrorServicioChat(`${fn}: HTTP ${r.status}`);
  try { return await r.json(); } catch { throw new ErrorServicioChat(`${fn}: respuesta no JSON`); }
}

function carpetaChat(clienteId) {
  return hashChat('sha256').update(`chat:${clienteId}`).digest('hex').slice(0, 32);
}

// ── El tipo, por los bytes ──
function mimeChat(buf, tipo) {
  if (tipo === 'foto') return buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff ? 'image/jpeg' : null;
  if (buf.length < 12) return null;
  if (buf.toString('latin1', 4, 8) === 'ftyp') return 'audio/mp4';
  if (buf[0] === 0x1a && buf[1] === 0x45 && buf[2] === 0xdf && buf[3] === 0xa3) return 'audio/webm';
  if (buf.toString('latin1', 0, 4) === 'OggS') return 'audio/ogg';
  return null;
}

// Saca del JPEG los segmentos de metadatos (EXIF con GPS, XMP, comentarios). Recorre los marcadores hasta el inicio del
// barrido (SOS) y copia el resto tal cual. null si la estructura no cierra: esa foto no se guarda.
function jpegSinMetadatos(buf) {
  const partes = [buf.subarray(0, 2)];
  let i = 2;
  while (i + 4 <= buf.length) {
    if (buf[i] !== 0xff) return null;
    const m = buf[i + 1];
    if (m === 0xff) { i += 1; continue; }                     // relleno entre marcadores
    if (m === 0xd9) return null;                               // termina sin imagen
    const largo = buf.readUInt16BE(i + 2);
    if (largo < 2 || i + 2 + largo > buf.length) return null;
    const segmento = buf.subarray(i, i + 2 + largo);
    if (m === 0xda) { partes.push(buf.subarray(i)); return Buffer.concat(partes); }   // SOS: de acá en adelante, la imagen
    const metadatos = m === 0xfe || (m >= 0xe1 && m <= 0xef && m !== 0xe2 && m !== 0xee);   // COM, APP1, APP3-13, APP15
    if (!metadatos) partes.push(segmento);
    i += 2 + largo;
  }
  return null;
}

// ── Rechazos con el cuerpo pendiente ──
// Se drena con el mismo plazo que una subida (un audio de 1 MB por datos lentos tarda más de 15 s): si se corta antes,
// el teléfono ve un corte de red en vez del 429/403 y vuelve a mandar el archivo entero. Sin datos por 20 s, se corta.
const DRENAR_CHAT_MS = ESPERA_CUERPO_CHAT_MS;
const DRENAR_QUIETO_MS = 20_000;
const MAX_DRENANDO_CHAT = 16;
let drenandoChat = 0;
function drenarOCortarChat(req) {
  if (req.complete || req.destroyed) return;
  if (drenandoChat >= MAX_DRENANDO_CHAT) { req.destroy(); return; }
  drenandoChat++;
  let leidos = 0, listo = false;
  const terminar = () => { if (!listo) { listo = true; drenandoChat--; clearTimeout(plazo); clearTimeout(quieto); } };
  const cortar = () => { terminar(); req.destroy(); };
  const plazo = setTimeout(cortar, DRENAR_CHAT_MS);
  plazo.unref?.();
  let quieto = setTimeout(cortar, DRENAR_QUIETO_MS);
  quieto.unref?.();
  req.on('data', (c) => {
    leidos += c.length;
    if (leidos > MAX_CHAT_FOTO_B + MAX_CHAT_AUDIO_B) return cortar();
    clearTimeout(quieto);
    quieto = setTimeout(cortar, DRENAR_QUIETO_MS);
    quieto.unref?.();
  });
  req.once('end', terminar);
  req.once('close', terminar);
  req.once('error', cortar);
  req.resume();
}

function rechazarChat(req, res, status, error, origin) {
  res.once('finish', () => drenarOCortarChat(req));
  send(res, status, { ok: false, error }, origin);
}

function leerCuerpoChat(req, largo) {
  return new Promise((resolve) => {
    if (req.destroyed || req.socket?.destroyed) return resolve(null);
    const partes = [];
    let total = 0, listo = false;
    const fin = (v) => { if (!listo) { listo = true; clearTimeout(plazo); resolve(v); } };
    const plazo = setTimeout(() => { fin(null); req.destroy(); }, ESPERA_CUERPO_CHAT_MS);
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

async function sacarObjetoChat(path) {
  try {
    const r = await fetchChat(`${SUPABASE_URL}/storage/v1/object/${BUCKET_CHAT}`, {
      method: 'DELETE', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ prefixes: [path] }),
    });
    if (!r.ok) throw new ErrorServicioChat(`HTTP ${r.status}`);
  } catch (e) {
    console.error('[chat] sacar objeto', e.message || e);   // queda huérfano en la carpeta, sin fila: no se firma nunca
  }
}

// ── POST /chat/adjunto — cuerpo: el archivo crudo; x-chat-token, x-chat-id, x-chat-tipo (foto|audio),
//    x-chat-duracion (audio, en segundos), Content-Length ──
// Idempotente: el id lo manda el teléfono. Un reintento contesta `ya` con el mismo mensaje, sin volver a guardar.
async function handleChatAdjunto(req, res, origin) {
  try {
    if (!SERVICE_KEY) return rechazarChat(req, res, 503, 'servicio no configurado', origin);
    const token = req.headers['x-chat-token'];
    const id = String(req.headers['x-chat-id'] || '').toLowerCase();
    const tipo = req.headers['x-chat-tipo'];
    const largo = Number(req.headers['content-length']);
    if (!UUID_CHAT.test(id)) return rechazarChat(req, res, 400, 'id inválido', origin);
    if (tipo !== 'foto' && tipo !== 'audio') return rechazarChat(req, res, 400, 'tipo inválido', origin);
    let duracion = null;
    if (tipo === 'audio') {
      duracion = Number(req.headers['x-chat-duracion']);
      if (!Number.isFinite(duracion) || duracion <= 0) return rechazarChat(req, res, 400, 'falta la duración', origin);
      if (duracion > MAX_CHAT_AUDIO_S) return rechazarChat(req, res, 413, 'audio muy largo', origin);
    }
    if (!Number.isInteger(largo) || largo <= 0) return rechazarChat(req, res, 411, 'falta el largo', origin);
    if (largo > (tipo === 'foto' ? MAX_CHAT_FOTO_B : MAX_CHAT_AUDIO_B)) return rechazarChat(req, res, 413, 'archivo muy grande', origin);

    let clienteId;
    try { clienteId = await resolverCliente(token); }
    catch (e) { console.warn('[chat] token:', e.message); return rechazarChat(req, res, 503, 'no se pudo validar el acceso, probá en un rato', origin); }
    if (!clienteId) return rechazarChat(req, res, 403, 'token inválido', origin);

    const antes = await rpcChat('mypump_chat_adjunto_puede', { p_cliente_id: clienteId, p_id: id });
    if (antes !== 'ok' && antes !== 'ya') {
      const [status, error] = RECHAZOS_CHAT[antes] || [];
      if (!status) throw new ErrorServicioChat('puede: respuesta inesperada');
      return rechazarChat(req, res, status, error, origin);
    }
    if (antes === 'ya') {
      // Un reintento de algo que ya entró (se perdió la respuesta): no se vuelve a leer ni a guardar. registrar devuelve
      // el mismo mensaje sin tocar nada (path y mime no se usan).
      const ya = await rpcChat('mypump_chat_adjunto_registrar', {
        p_cliente_id: clienteId, p_id: id, p_tipo: tipo, p_path: `${carpetaChat(clienteId)}/${id}`, p_mime: 'image/jpeg', p_bytes: 1,
        p_duracion_s: duracion,
      });
      if (ya?.resultado !== 'ya') throw new ErrorServicioChat('ya: respuesta inesperada');
      res.once('finish', () => drenarOCortarChat(req));
      return send(res, 200, { ok: true, ya: true, comentario_id: ya.comentario_id, created_at: ya.created_at }, origin);
    }
    if (overLimit(token, 'chat', { contar: false })) return rechazarChat(req, res, 429, 'muchos adjuntos por hoy, probá mañana', origin);

    const crudo = await leerCuerpoChat(req, largo);
    if (!crudo) return;                                   // se cortó: no hay a quién contestarle
    if (crudo.length !== largo) return send(res, 400, { ok: false, error: 'largo incorrecto' }, origin);
    const mime = mimeChat(crudo, tipo);
    if (!mime) return send(res, 400, { ok: false, error: tipo === 'foto' ? 'la imagen debe ser JPEG' : 'formato de audio no soportado' }, origin);
    const buf = mime === 'image/jpeg' ? jpegSinMetadatos(crudo) : crudo;
    if (!buf) return send(res, 400, { ok: false, error: 'la imagen no se puede leer' }, origin);

    const path = `${carpetaChat(clienteId)}/${id}.${EXT_CHAT[mime]}`;
    {
      const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_CHAT}/${path}`, {
        method: 'POST',
        signal: AbortSignal.timeout(ESPERA_CUERPO_CHAT_MS),
        headers: svcHeaders({ 'Content-Type': mime, 'x-upsert': 'true' }),
        body: buf,
      });
      if (!up.ok) {
        console.error('[chat] storage', up.status);
        return send(res, 502, { ok: false, error: 'no se pudo guardar' }, origin);
      }
    }

    let reg;
    try {
      reg = await rpcChat('mypump_chat_adjunto_registrar', {
        p_cliente_id: clienteId, p_id: id, p_tipo: tipo, p_path: path, p_mime: mime, p_bytes: buf.length, p_duracion_s: duracion,
      });
    } catch (e) {
      // Con la red cortada la fila pudo haber entrado: el reintento contesta `ya` y el objeto tiene que seguir estando.
      console.error('[chat] registrar', e.message || e);
      return send(res, 502, { ok: false, error: 'guardado sin registrar' }, origin);
    }
    if (reg?.resultado === 'ok' || reg?.resultado === 'ya') {
      if (reg.resultado === 'ok') sumarUso(token, 'chat');
      console.log(`[chat] ${reg.resultado} ${tipo} ${Math.round(buf.length / 1024)}kb`);   // sin ids ni contenido
      return send(res, 200, { ok: true, ya: reg.resultado === 'ya', comentario_id: reg.comentario_id, created_at: reg.created_at }, origin);
    }
    await sacarObjetoChat(path);   // cambió mientras se subía (se apagó la palanca, llegó al tope)
    const [status, error] = RECHAZOS_CHAT[reg?.resultado] || [502, 'guardado sin registrar'];
    send(res, status, { ok: false, error }, origin);
  } catch (e) {
    console.error('[chat] error', e.message || e);
    if (res.headersSent) return;
    rechazarChat(req, res, 503, 'no se pudo subir, probá en un rato', origin);
  }
}

// ── POST /chat/urls — { token, ids: [uuid…] } ── URLs firmadas (1 h) de adjuntos de SU chat. Nunca firma un path del pedido.
async function handleChatUrls(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await leerBody(req, res, origin, 8 * 1024);
    if (!data) return;
    if (typeof data !== 'object' || Array.isArray(data)) return send(res, 400, { ok: false, error: 'pedido inválido' }, origin);
    const ids = Array.isArray(data.ids) ? [...new Set(data.ids.map((x) => String(x).toLowerCase()))] : null;
    if (!ids || !ids.length || ids.length > 60 || !ids.every((x) => UUID_CHAT.test(x))) return send(res, 400, { ok: false, error: 'ids inválidos' }, origin);
    const clienteId = await clienteOResponder(data.token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);

    const filas = await rpcChat('mypump_chat_adjuntos_paths', { p_cliente_id: clienteId, p_ids: ids });
    if (!Array.isArray(filas)) return send(res, 502, { ok: false, error: 'no se pudo leer' }, origin);
    if (!filas.length) return send(res, 200, { ok: true, adjuntos: [], expira_en: 3600 }, origin);
    const fr = await fetchChat(`${SUPABASE_URL}/storage/v1/object/sign/${BUCKET_CHAT}`, {
      method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ expiresIn: 3600, paths: filas.map((f) => f.path) }),
    });
    if (!fr.ok) return send(res, 502, { ok: false, error: 'no se pudieron firmar' }, origin);
    const firmadas = await fr.json();
    const porPath = Object.fromEntries((Array.isArray(firmadas) ? firmadas : []).map((x) => [String(x.path).replace(/^\/+/, ''), x.signedURL]));
    const adjuntos = filas.filter((f) => porPath[f.path])
      .map((f) => ({ id: f.id, tipo: f.tipo, mime: f.mime, url: `${SUPABASE_URL}/storage/v1${porPath[f.path]}` }));
    send(res, 200, { ok: true, adjuntos, expira_en: 3600 }, origin);
  } catch (e) {
    console.error('[chat] urls', e.message || e);
    if (!res.headersSent) send(res, 502, { ok: false, error: 'error al firmar' }, origin);
  }
}
