// PROPUESTA, SIN APLICAR: los dos endpoints para sumar a mini-vision/server.mjs, con el mismo estilo que /progreso/upload.
// Rutas:
//   if (req.method === 'POST' && req.url === '/reps/subir')          return handleRepsSubir(req, res, origin);
//   if (req.method === 'POST' && req.url === '/reps/consentimiento') return handleRepsConsentimiento(req, res, origin);
// Reverso: quitar estas funciones y las dos rutas; el resto del servicio no depende de ellas.
//
// En overLimit, el tope de esta función: `const tope = feature === 'fotos' ? RATE_FOTOS : feature === 'reps' ? RATE_REPS : RATE_LIMIT;`
//
// INVARIANTE: el cliente_id sale del TOKEN, jamás del body. Sin `mypump_reps_puede_subir`, 403: la app nunca decide sola.

import { createHash } from 'node:crypto';

const BUCKET_REPS = 'reps-calibracion';
const MAX_REPS_B = 20 * 1024 * 1024;     // 20 MB por sesión
const RATE_REPS = 30;                    // subidas por token por día

async function puedeSubirReps(clienteId) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/mypump_reps_puede_subir`, {
    method: 'POST',
    headers: svcHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify({ p_cliente_id: clienteId }),
  });
  return r.ok && (await r.json()) === true;
}

// ── POST /reps/subir — { token, sesion, sha256, mpcal_base64 } ──
// Idempotente: una sesión por cliente, y el mismo hash no vuelve a escribir (`ya: true`). Si la sesión creció en el
// iPhone, el archivo nuevo reemplaza al anterior (x-upsert).
async function handleRepsSubir(req, res, origin) {
  if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
  const data = await leerBody(req, res, origin, Math.ceil(MAX_REPS_B * 1.4));
  if (!data) return;
  const { token, sesion, sha256, mpcal_base64 } = data || {};
  if (typeof sesion !== 'string' || !/^[0-9A-Za-z-]{1,80}$/.test(sesion)) return send(res, 400, { ok: false, error: 'sesión inválida' }, origin);
  if (typeof sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(sha256)) return send(res, 400, { ok: false, error: 'hash inválido' }, origin);
  if (typeof mpcal_base64 !== 'string' || !mpcal_base64) return send(res, 400, { ok: false, error: 'falta el archivo' }, origin);

  const clienteId = await clienteOResponder(token, res, origin);
  if (clienteId === undefined) return;
  if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
  if (!(await puedeSubirReps(clienteId))) return send(res, 403, { ok: false, error: 'no habilitado' }, origin);
  if (overLimit(token, 'reps', { contar: false })) return send(res, 429, { ok: false, error: 'demasiadas subidas por hoy' }, origin);

  const buf = Buffer.from(mpcal_base64, 'base64');
  if (!buf.length || buf.length > MAX_REPS_B) return send(res, 400, { ok: false, error: 'archivo vacío o muy grande' }, origin);
  if (buf.subarray(0, 4).toString('latin1') !== 'MPC1') return send(res, 400, { ok: false, error: 'formato inválido' }, origin);
  if (createHash('sha256').update(buf).digest('hex') !== sha256) return send(res, 400, { ok: false, error: 'hash no coincide' }, origin);

  try {
    const q = `${SUPABASE_URL}/rest/v1/mypump_reps_grabaciones?cliente_id=eq.${encodeURIComponent(clienteId)}&sesion=eq.${encodeURIComponent(sesion)}&select=sha256`;
    const previo = await (await fetch(q, { headers: svcHeaders() })).json();
    if (previo?.[0]?.sha256 === sha256) return send(res, 200, { ok: true, ya: true }, origin);

    const path = `${clienteId}/${sesion}.mpcal`;
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_REPS}/${path}`, {
      method: 'POST',
      headers: svcHeaders({ 'Content-Type': 'application/octet-stream', 'x-upsert': 'true' }),
      body: buf,
    });
    if (!up.ok) return send(res, 502, { ok: false, error: 'no se pudo guardar' }, origin);

    const reg = await fetch(`${SUPABASE_URL}/rest/v1/mypump_reps_grabaciones?on_conflict=cliente_id,sesion`, {
      method: 'POST',
      headers: svcHeaders({ 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates' }),
      body: JSON.stringify({ cliente_id: clienteId, sesion, sha256, path, bytes: buf.length, subida_en: new Date().toISOString() }),
    });
    if (!reg.ok) return send(res, 502, { ok: false, error: 'guardado sin registrar' }, origin);
    sumarUso(token, 'reps');
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[reps] error', e);
    send(res, 502, { ok: false, error: 'error al subir' }, origin);
  }
}

// ── POST /reps/consentimiento — { token, acepta, plataforma, app } ──
// Con `acepta: false` borra además lo ya subido por ese alumno. La cuenta `automatica` no pasa por acá.
async function handleRepsConsentimiento(req, res, origin) {
  if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio no configurado' }, origin);
  const data = await leerBody(req, res, origin, 4 * 1024);
  if (!data) return;
  const { token, acepta, plataforma, app } = data || {};
  if (typeof acepta !== 'boolean') return send(res, 400, { ok: false, error: 'falta la decisión' }, origin);
  const clienteId = await clienteOResponder(token, res, origin);
  if (clienteId === undefined) return;
  if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);

  try {
    const g = await fetch(`${SUPABASE_URL}/rest/v1/rpc/mypump_reps_consentir`, {
      method: 'POST',
      headers: svcHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ p_token: token, p_acepta: acepta, p_plataforma: plataforma ?? null, p_app: app ?? null }),
    });
    if (!g.ok) return send(res, 502, { ok: false, error: 'no se pudo guardar' }, origin);

    if (acepta === false) {
      const q = `${SUPABASE_URL}/rest/v1/mypump_reps_grabaciones?cliente_id=eq.${encodeURIComponent(clienteId)}&select=path`;
      const filas = await (await fetch(q, { headers: svcHeaders() })).json();
      const paths = (filas || []).map((f) => f.path);
      if (paths.length) {
        const del = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_REPS}`, {
          method: 'DELETE',
          headers: svcHeaders({ 'Content-Type': 'application/json' }),
          body: JSON.stringify({ prefixes: paths }),
        });
        if (!del.ok) return send(res, 502, { ok: false, error: 'no se pudo borrar' }, origin);
      }
      const delFilas = await fetch(`${SUPABASE_URL}/rest/v1/mypump_reps_grabaciones?cliente_id=eq.${encodeURIComponent(clienteId)}`, { method: 'DELETE', headers: svcHeaders() });
      if (!delFilas.ok) return send(res, 502, { ok: false, error: 'no se pudo borrar' }, origin);
    }
    send(res, 200, { ok: true }, origin);
  } catch (e) {
    console.error('[reps] consentimiento', e);
    send(res, 502, { ok: false, error: 'error al guardar' }, origin);
  }
}
