/* =============================================================
   GET /api/wearables/iniciar?t=TOKEN&proveedor=oura

   Valida el token del cliente, guarda el `state` (anti-CSRF) y redirige al
   proveedor. Cero secretos del lado del cliente: el client_secret nunca sale
   de las env vars.

   POR QUÉ ESTE FLUJO Y NO UN ESQUEMA CUSTOM (mypump://):
   El Info.plist no tiene CFBundleURLTypes, y agregarlo obligaría a un build
   nuevo de TestFlight. Acá la app abre esta URL con @capacitor/browser
   (SFSafariViewController, que vive fuera de limitsNavigationsToAppBoundDomains),
   y detecta el final por POLLING de mypump_get_conexiones — el callback no
   necesita volver a la app. Todo deployable por web.
   ============================================================= */
import { PROVEEDORES, aleatorio, rpc, faltaConfig, redirectUri, paginaCierre } from './_lib.js';

export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const token = url.searchParams.get('t') || '';
  const prov = (url.searchParams.get('proveedor') || '').toLowerCase();

  const p = PROVEEDORES[prov];
  if (!p) return paginaCierre('Proveedor desconocido', 'Volvé a MyPump e intentá de nuevo.', false);

  const falta = faltaConfig(env, prov);
  if (falta) {
    // Mensaje distinto para el cliente y para el log: al cliente no le sirve
    // saber qué env var falta, pero a Mati sí.
    console.error('[wearables/iniciar] config incompleta:', falta);
    return paginaCierre('Todavía no está habilitado',
      `La conexión con ${p.nombre} no está configurada. Avisale a Mati.`, false);
  }
  if (!/^[a-zA-Z0-9_-]{16,64}$/.test(token)) {
    return paginaCierre('Enlace inválido', 'Abrí la conexión desde la app.', false);
  }

  const state = aleatorio(24);
  let clienteId = null;
  try {
    clienteId = await rpc(env, 'mypump_oauth_iniciar_service', {
      p_token: token, p_proveedor: prov, p_state: state, p_verifier: null,
    });
  } catch (e) {
    console.error('[wearables/iniciar] rpc:', e);
    return paginaCierre('No pudimos empezar', 'Probá de nuevo en un rato.', false);
  }
  if (!clienteId) return paginaCierre('Enlace inválido', 'Tu acceso no es válido. Escribile a Mati.', false);

  const a = new URL(p.authorize);
  a.searchParams.set('response_type', 'code');
  a.searchParams.set('client_id', env[p.idEnv]);
  a.searchParams.set('redirect_uri', redirectUri(env));
  a.searchParams.set('scope', p.scopes.join(' '));
  a.searchParams.set('state', state);

  return Response.redirect(a.toString(), 302);
}
