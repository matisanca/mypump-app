/* =============================================================
   GET /api/wearables/callback?code=…&state=…

   Canjea el code por tokens, los CIFRA y los guarda. Devuelve una página de
   cierre; no intenta volver a la app (la app lo detecta por polling).
   ============================================================= */
import { PROVEEDORES, cifrar, rpc, redirectUri, paginaCierre } from './_lib.js';

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  const err = url.searchParams.get('error');

  if (err) return paginaCierre('No se conectó', 'Cancelaste el permiso. Podés intentarlo cuando quieras.', false);
  if (!code || !state) return paginaCierre('Faltan datos', 'Volvé a MyPump e intentá de nuevo.', false);

  // El state dice de qué proveedor es: se resuelve leyendo la fila guardada.
  let fila = null;
  try {
    const r = await fetch(`${env.SUPABASE_URL}/rest/v1/mypump_oauth_estados?state=eq.${encodeURIComponent(state)}&select=proveedor,cliente_id,usado_en&limit=1`, {
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
    });
    fila = (await r.json())[0] || null;
  } catch (e) { console.error('[wearables/callback] lookup:', e); }

  if (!fila || fila.usado_en) {
    // Un state usado dos veces es un replay: se rechaza sin dar detalle.
    return paginaCierre('Enlace vencido', 'Volvé a MyPump y tocá conectar de nuevo.', false);
  }
  const p = PROVEEDORES[fila.proveedor];
  if (!p) return paginaCierre('Proveedor desconocido', '', false);

  // Canje del code. Los proveedores difieren en si el secret va en el body o
  // en Basic auth; Oura y Whoop aceptan los dos, se usa el body por simple.
  let tok;
  try {
    const res = await fetch(p.token, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri: redirectUri(env),
        client_id: env[p.idEnv],
        client_secret: env[p.secretEnv],
      }),
    });
    if (!res.ok) {
      console.error('[wearables/callback] token:', res.status, (await res.text()).slice(0, 200));
      return paginaCierre('No pudimos conectar', `${p.nombre} rechazó la conexión. Probá de nuevo.`, false);
    }
    tok = await res.json();
  } catch (e) {
    console.error('[wearables/callback] fetch token:', e);
    return paginaCierre('No pudimos conectar', 'Probá de nuevo en un rato.', false);
  }

  const expira = tok.expires_in ? new Date(Date.now() + tok.expires_in * 1000).toISOString() : null;
  const scopes = (tok.scope || '').split(/[\s,]+/).filter(Boolean);

  try {
    const clienteId = await rpc(env, 'mypump_oauth_completar_service', {
      p_state: state,
      p_acc_enc: await cifrar(env, tok.access_token),
      p_ref_enc: await cifrar(env, tok.refresh_token),
      p_kid: 'v1',
      p_expira: expira,
      p_prov_user: tok.user_id ? String(tok.user_id) : null,
      p_scopes: scopes,
    });
    if (!clienteId) return paginaCierre('Enlace vencido', 'Volvé a MyPump y tocá conectar de nuevo.', false);
  } catch (e) {
    console.error('[wearables/callback] guardar:', e);
    return paginaCierre('No pudimos guardar la conexión', 'Probá de nuevo.', false);
  }

  return paginaCierre(`${p.nombre} conectado`,
    'Ya podés volver a MyPump. Tus datos van a empezar a aparecer en un rato.');
}
