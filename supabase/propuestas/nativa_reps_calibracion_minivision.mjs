// PROPUESTA, SIN APLICAR: los dos endpoints para sumar a mini-vision/server.mjs (se prueba contra un doble local:
// `node --test supabase/propuestas/nativa_reps_calibracion_minivision.test.mjs`).
// Rutas, antes de la de /vision:
//   if (req.method === 'POST' && req.url === '/reps/subir')          return handleRepsSubir(req, res, origin);
//   if (req.method === 'POST' && req.url === '/reps/consentimiento') return handleRepsConsentimiento(req, res, origin);
// En overLimit, el tope de esta función:
//   const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'reps' ? RATE_REPS : feature === 'repsConsent' ? RATE_REPS_CONSENT : RATE_LIMIT;
// Reverso: ver nativa_reps_calibracion_revertir.sql (primero se corta y se vacía, con estos endpoints todavía vivos).
//
// INVARIANTES
// - El cliente_id sale del TOKEN, jamás del pedido. Sin `mypump_reps_puede_subir`, 403: la app nunca decide sola.
// - Nada se escapa de un handler: todo error de red o de Supabase termina en una respuesta (Node corta el proceso con un
//   rechazo sin atajar, y este proceso también atiende visión y fotos).
// - Un error NUNCA es «revocado»: se borra solo con un `false` o una revocación explícitos.
// - El cuerpo se lee recién con el token, el permiso, los topes y un lugar libre: un token cualquiera no llena la memoria
//   ni el disco, y consentirse a sí mismo solo da derecho a su tope.

import { createHash } from 'node:crypto';

const BUCKET_REPS = 'reps-calibracion';
const MAX_REPS_B = 20 * 1024 * 1024;              // por sesión (una sesión real: 2 MB)
const TOPE_CUENTA_REPS_B = 300 * 1024 * 1024;     // guardado por cuenta
const TOPE_BUCKET_REPS_B = 20 * 1024 * 1024 * 1024; // guardado en total: lleno, nadie sube
const RATE_REPS = 30;                             // subidas por token por día
const RATE_REPS_CONSENT = 20;                     // cambios de consentimiento por token por día
const MAX_REPS_EN_CURSO = 2;                      // subidas a la vez en todo el servicio (lo que entra en memoria)
const ESPERA_REPS_MS = 30_000;
const ESPERA_CUERPO_REPS_MS = 120_000;
const BARRIDO_REPS_MS = parseInt(process.env.REPS_BARRIDO_MS || '600000', 10);

const repsEnCurso = new Set();                    // cuentas subiendo ahora

class ErrorServicioReps extends Error {}

function fetchReps(url, opciones = {}) {
  return fetch(url, { signal: AbortSignal.timeout(ESPERA_REPS_MS), ...opciones });
}

async function jsonReps(r, que) {
  if (!r.ok) throw new ErrorServicioReps(`${que}: HTTP ${r.status}`);
  try { return await r.json(); } catch { throw new ErrorServicioReps(`${que}: respuesta no JSON`); }
}

async function rpcReps(fn, cuerpo = {}) {
  const r = await fetchReps(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify(cuerpo),
  });
  return jsonReps(r, fn);
}

// true o false; si no se pudo saber, lanza. Quien llama nunca toma un error por un «no».
async function puedeSubirReps(clienteId) {
  const v = await rpcReps('mypump_reps_puede_subir', { p_cliente_id: clienteId });
  if (typeof v !== 'boolean') throw new ErrorServicioReps('puede_subir: respuesta inesperada');
  return v;
}

function urlFilasReps(tabla, filtros) {
  const q = Object.entries(filtros).map(([k, v]) => `${k}=eq.${encodeURIComponent(v)}`).join('&');
  return `${SUPABASE_URL}/rest/v1/${tabla}?${q}`;
}

async function borrarObjetosReps(paths) {
  for (let i = 0; i < paths.length; i += 500) {
    const r = await fetchReps(`${SUPABASE_URL}/storage/v1/object/${BUCKET_REPS}`, {
      method: 'DELETE', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ prefixes: paths.slice(i, i + 500) }),
    });
    if (!r.ok) throw new ErrorServicioReps(`borrar objetos: HTTP ${r.status}`);
  }
}

async function sacarObjetoReps(path) {
  return borrarObjetosReps([path]).then(() => true, (e) => { console.error('[reps] borrar lo recién subido', e.message || e); return false; });
}

// Un objeto sin fila de quien ya revocó (`acepta` falso, no un simple «no puede subir»: sacarle la marca automática no
// borra): sin esta marca el barrido no lo vería nunca.
async function marcarBorradoSiRevoco(clienteId) {
  try {
    const r = await fetchReps(urlFilasReps('mypump_reps_subida', { cliente_id: clienteId, acepta: false }), {
      method: 'PATCH', headers: svcHeaders({ 'Content-Type': 'application/json' }), body: JSON.stringify({ borrado_pendiente: true }),
    });
    if (!r.ok) throw new ErrorServicioReps(`marcar: HTTP ${r.status}`);
  } catch (e) {
    console.error('[reps] marcar borrado pendiente', e.message || e);
  }
}

// La carpeta de la cuenta en el bucket: no lleva el cliente_id, que en algunas cuentas contiene el nombre.
function carpetaReps(clienteId) {
  return createHash('sha256').update(`reps:${clienteId}`).digest('hex').slice(0, 32);
}

// Los objetos bajo una carpeta, a cualquier profundidad (Storage devuelve las carpetas con id null).
async function listarObjetosReps(prefijo) {
  const paths = [];
  for (let offset = 0; ; offset += 100) {
    const r = await fetchReps(`${SUPABASE_URL}/storage/v1/object/list/${BUCKET_REPS}`, {
      method: 'POST', headers: svcHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ prefix: prefijo, limit: 100, offset, sortBy: { column: 'name', order: 'asc' } }),
    });
    const lista = await jsonReps(r, 'listar');
    if (!Array.isArray(lista)) throw new ErrorServicioReps('listar: respuesta inesperada');
    for (const e of lista) {
      const p = `${prefijo}/${e.name}`;
      if (e.id === null || e.id === undefined) paths.push(...await listarObjetosReps(p));
      else paths.push(p);
    }
    if (lista.length < 100) return paths;
  }
}

// Borra todo lo de un alumno: objetos por carpeta (no depende de las filas), después filas, y comprueba que no quedó
// nada. true solo si quedó vacío. No lanza: un fallo devuelve false y lo reintenta la app o el barrido.
async function borrarGrabaciones(clienteId) {
  try {
    await borrarObjetosReps(await listarObjetosReps(carpetaReps(clienteId)));
    const filas = await fetchReps(urlFilasReps('mypump_reps_grabaciones', { cliente_id: clienteId }), { method: 'DELETE', headers: svcHeaders() });
    if (!filas.ok) throw new ErrorServicioReps(`borrar filas: HTTP ${filas.status}`);
    return (await listarObjetosReps(carpetaReps(clienteId))).length === 0;
  } catch (e) {
    console.error('[reps] no se pudo borrar', e.message || e);
    return false;
  }
}

// Reintenta los borrados que quedaron a medias: revocaciones con el borrado sin confirmar y filas de quien revocó.
let barriendoReps = false;
async function barrerReps() {
  if (!SERVICE_KEY || barriendoReps) return;
  barriendoReps = true;
  try {
    const ids = await rpcReps('mypump_reps_para_borrar');
    for (const id of Array.isArray(ids) ? ids : []) {
      if (await borrarGrabaciones(id)) await rpcReps('mypump_reps_borrado_hecho', { p_cliente_id: id });
    }
  } catch (e) {
    console.error('[reps] barrido', e.message || e);
  } finally {
    barriendoReps = false;
  }
}
if (process.env.MINI_VISION_SIN_ESCUCHAR !== '1') setInterval(barrerReps, BARRIDO_REPS_MS).unref();

// El cuerpo crudo, con tope y plazo. null si se cortó, se pasó o tardó de más.
function leerCuerpoReps(req, largo) {
  return new Promise((resolve) => {
    if (req.destroyed || req.socket?.destroyed) return resolve(null);   // se cortó mientras se miraban los topes
    const partes = [];
    let total = 0, listo = false;
    const fin = (v) => { if (!listo) { listo = true; clearTimeout(plazo); resolve(v); } };
    const plazo = setTimeout(() => { fin(null); req.destroy(); }, ESPERA_CUERPO_REPS_MS);
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

// Antes de leer el cuerpo: se contesta y se corta la conexión, sin recibir lo que falta.
function rechazarReps(req, res, status, error, origin) {
  res.once('finish', () => req.destroy());
  send(res, status, { ok: false, error }, origin);
}

// ── POST /reps/subir — cuerpo: el .mpcal crudo; x-reps-token, x-reps-sesion, x-reps-sha256 y Content-Length ──
// Idempotente: una fila por sesión y el objeto se llama como su contenido (`carpeta/sesion/sha.mpcal`). El mismo hash no
// vuelve a escribir (`ya: true`). Solo una versión más grande de la sesión reemplaza a la anterior.
async function handleRepsSubir(req, res, origin) {
  let ocupada = null;
  try {
    if (!SERVICE_KEY) return rechazarReps(req, res, 503, 'servicio no configurado', origin);
    const token = req.headers['x-reps-token'];
    const sesion = req.headers['x-reps-sesion'];
    const sha256 = req.headers['x-reps-sha256'];
    const largo = Number(req.headers['content-length']);
    if (typeof sesion !== 'string' || !/^[0-9A-Za-z-]{1,80}$/.test(sesion)) return rechazarReps(req, res, 400, 'sesión inválida', origin);
    if (typeof sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(sha256)) return rechazarReps(req, res, 400, 'hash inválido', origin);
    if (!Number.isInteger(largo) || largo <= 0) return rechazarReps(req, res, 411, 'falta el largo', origin);
    if (largo > MAX_REPS_B) return rechazarReps(req, res, 413, 'archivo muy grande', origin);

    const clienteId = await clienteOResponderReps(token, req, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return rechazarReps(req, res, 403, 'token inválido', origin);
    if (!(await puedeSubirReps(clienteId))) return rechazarReps(req, res, 403, 'no habilitado', origin);
    if (overLimit(token, 'reps', { contar: false })) return rechazarReps(req, res, 429, 'demasiadas subidas por hoy', origin);
    if (repsEnCurso.has(clienteId) || repsEnCurso.size >= MAX_REPS_EN_CURSO) return rechazarReps(req, res, 429, 'ocupado, probá en un rato', origin);
    repsEnCurso.add(clienteId);
    ocupada = clienteId;

    const filas = await jsonReps(await fetchReps(`${urlFilasReps('mypump_reps_grabaciones', { cliente_id: clienteId })}&select=sesion,sha256,path,bytes`, { headers: svcHeaders() }), 'filas');
    if (!Array.isArray(filas)) throw new ErrorServicioReps('filas: respuesta inesperada');
    const previo = filas.find((f) => f.sesion === sesion);
    if (previo?.sha256 === sha256 || (previo && previo.bytes >= largo)) {
      // Lo más completo se queda (el alumno borró en el iPhone o el tope recortó). Ya autenticado: se descarta lo que venga.
      req.resume();
      return send(res, 200, { ok: true, ya: true }, origin);
    }
    const usado = filas.reduce((s, f) => s + f.bytes, 0) - (previo?.bytes || 0);
    if (usado + largo > TOPE_CUENTA_REPS_B) return rechazarReps(req, res, 413, 'tope de la cuenta', origin);
    const total = await rpcReps('mypump_reps_total_bytes');
    if (typeof total !== 'number') throw new ErrorServicioReps('total: respuesta inesperada');
    if (total + largo > TOPE_BUCKET_REPS_B) return rechazarReps(req, res, 507, 'sin lugar', origin);

    const buf = await leerCuerpoReps(req, largo);
    if (!buf) return;                                 // se cortó: no hay a quién contestarle
    if (buf.length !== largo) return send(res, 400, { ok: false, error: 'largo incorrecto' }, origin);
    if (buf.subarray(0, 4).toString('latin1') !== 'MPC1') return send(res, 400, { ok: false, error: 'formato inválido' }, origin);
    if (createHash('sha256').update(buf).digest('hex') !== sha256) return send(res, 400, { ok: false, error: 'hash no coincide' }, origin);

    const path = `${carpetaReps(clienteId)}/${sesion}/${sha256}.mpcal`;
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_REPS}/${path}`, {
      method: 'POST',
      signal: AbortSignal.timeout(ESPERA_CUERPO_REPS_MS),
      headers: svcHeaders({ 'Content-Type': 'application/octet-stream', 'x-upsert': 'true' }),   // mismo nombre = mismo contenido
      body: buf,
    });
    if (!up.ok) return send(res, 502, { ok: false, error: 'no se pudo guardar' }, origin);

    const reg = await fetchReps(`${SUPABASE_URL}/rest/v1/mypump_reps_grabaciones?on_conflict=cliente_id,sesion`, {
      method: 'POST',
      headers: svcHeaders({ 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates' }),
      body: JSON.stringify({ cliente_id: clienteId, sesion, sha256, path, bytes: buf.length, subida_en: new Date().toISOString() }),
    }).catch((e) => { console.error('[reps] registrar', e.message || e); return null; });
    if (!reg?.ok) {
      // Sin fila no lo vería el tope de la cuenta. Con la red cortada la fila pudo haber entrado: también se saca, para
      // que un reintento no conteste `ya` sobre un archivo que no está.
      if (await sacarObjetoReps(path)) {
        await fetchReps(urlFilasReps('mypump_reps_grabaciones', { cliente_id: clienteId, sesion, sha256 }), { method: 'DELETE', headers: svcHeaders() }).catch(() => {});
      } else {
        await marcarBorradoSiRevoco(clienteId);
      }
      return send(res, 502, { ok: false, error: 'guardado sin registrar' }, origin);
    }

    // Registrar y después volver a preguntar cierra la carrera con la revocación: o esta pregunta ve el «no», o la
    // revocación ve el archivo. Si no se pudo preguntar no se borra nada: el barrido lo levanta si de verdad revocó.
    if (!(await puedeSubirReps(clienteId))) {
      // La fila se saca solo si el objeto salió: si no, es lo único que le avisa al barrido que queda algo por borrar.
      if (await sacarObjetoReps(path)) {
        await fetchReps(urlFilasReps('mypump_reps_grabaciones', { cliente_id: clienteId, sesion, sha256 }), { method: 'DELETE', headers: svcHeaders() })
          .catch((e) => console.error('[reps] borrar la fila recién subida', e.message || e));
      }
      return send(res, 403, { ok: false, error: 'no habilitado' }, origin);
    }
    if (previo?.path && previo.path !== path) {
      await borrarObjetosReps([previo.path]).catch((e) => console.error('[reps] borrar la versión anterior', e.message || e));
    }
    sumarUso(token, 'reps');
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[reps] error', e.message || e);
    if (res.headersSent) return;
    rechazarReps(req, res, 503, 'no se pudo subir, probá en un rato', origin);
  } finally {
    if (ocupada) repsEnCurso.delete(ocupada);
  }
}

// clienteOResponder manda el 503 sin cortar el pedido: acá además no se lee el cuerpo.
async function clienteOResponderReps(token, req, res, origin) {
  const c = await clienteOResponder(token, res, origin);
  if (c === undefined) res.once('finish', () => req.destroy());
  return c;
}

// ── POST /reps/consentimiento — { token, acepta, plataforma, app } ──
// Revocar vale también con el token dado de baja (solo para esto): baja el permiso y borra lo de esa cuenta, nada más. Si
// el borrado falla queda pendiente: 502 para que la app reintente, y el barrido lo termina igual. Volver a aceptar con un
// borrado pendiente da 409. La cuenta `automatica` no pasa por acá.
async function handleRepsConsentimiento(req, res, origin) {
  try {
    if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
    const data = await leerBody(req, res, origin, 4 * 1024);
    if (!data) {                                      // null: ya contestó o se cortó; `null`, `0` o `false` en el JSON: falta contestar
      if (!res.headersSent && !req.socket?.destroyed) send(res, 400, { ok: false, error: 'pedido inválido' }, origin);
      return;
    }
    const { token, acepta, plataforma, app } = data || {};
    if (typeof acepta !== 'boolean') return send(res, 400, { ok: false, error: 'falta la decisión' }, origin);
    if (typeof token !== 'string' || token.length < 16 || token.length > 200) return send(res, 403, { ok: false, error: 'token inválido' }, origin);

    if (!acepta) {
      const r = await rpcReps('mypump_reps_revocar', { p_token: token });
      if (!r) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
      if (r.automatica === true) return send(res, 403, { ok: false, error: 'cuenta automática' }, origin);
      if (overLimit(token, 'repsConsent')) return send(res, 429, { ok: false, error: 'probá mañana' }, origin);   // el barrido borra igual
      if (!(await borrarGrabaciones(r.cliente_id))) return send(res, 502, { ok: false, error: 'no se pudo borrar' }, origin);
      await rpcReps('mypump_reps_borrado_hecho', { p_cliente_id: r.cliente_id }).catch((e) => console.error('[reps] borrado hecho', e.message || e));
      return send(res, 200, { ok: true }, origin);
    }

    const clienteId = await clienteOResponder(token, res, origin);
    if (clienteId === undefined) return;
    if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
    if (overLimit(token, 'repsConsent')) return send(res, 429, { ok: false, error: 'probá mañana' }, origin);
    const g = await rpcReps('mypump_reps_consentir', { p_token: token, p_acepta: true, p_plataforma: plataforma ?? null, p_app: app ?? null });
    if (g === false) return send(res, 409, { ok: false, error: 'todavía se está borrando' }, origin);
    if (g !== true) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[reps] consentimiento', e.message || e);
    if (!res.headersSent) send(res, 503, { ok: false, error: 'no se pudo guardar, probá en un rato' }, origin);
  }
}
