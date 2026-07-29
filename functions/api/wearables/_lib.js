/* =============================================================
   functions/api/wearables/_lib.js — núcleo compartido de la Vía A

   Registro de proveedores + cripto + helper de RPC. Agregar un proveedor
   nuevo es UNA entrada en PROVEEDORES y una función mapear(): nada más.

   ENV VARS (Cloudflare Pages → Settings → Environment variables):
     OAUTH_ENC_KEY            32 bytes en base64 — cifra los refresh tokens
     OAUTH_REDIRECT_BASE      https://app.mypumpteam.com
     SUPABASE_URL             https://gydinputrtptqakdzyvc.supabase.co
     SUPABASE_SERVICE_ROLE_KEY
     OURA_CLIENT_ID / OURA_CLIENT_SECRET
     WHOOP_CLIENT_ID / WHOOP_CLIENT_SECRET
   ============================================================= */

export const PROVEEDORES = {
  oura: {
    nombre: 'Oura',
    authorize: 'https://cloud.ouraring.com/oauth/authorize',
    token: 'https://api.ouraring.com/oauth/token',
    scopes: ['daily', 'heartrate', 'workout', 'personal'],
    pkce: false,
    idEnv: 'OURA_CLIENT_ID',
    secretEnv: 'OURA_CLIENT_SECRET',
  },
  whoop: {
    nombre: 'WHOOP',
    authorize: 'https://api.prod.whoop.com/oauth/oauth2/auth',
    token: 'https://api.prod.whoop.com/oauth/oauth2/token',
    scopes: ['read:recovery', 'read:sleep', 'read:cycles', 'read:workout', 'offline'],
    pkce: false,
    idEnv: 'WHOOP_CLIENT_ID',
    secretEnv: 'WHOOP_CLIENT_SECRET',
  },
};

export const b64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

export function aleatorio(n = 32) {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  return b64u(b.buffer);
}

/* ── Cifrado AES-GCM de los tokens ───────────────────────────────────────
   Se guardan como ciphertext en Postgres; la clave vive solo en env vars.
   Protege ante exposición del lado Supabase (dashboard, backup, service key
   filtrada). NO protege un servidor comprometido que ya tenga la env var —
   conviene tenerlo claro y no venderlo como más de lo que es.            */
async function clave(env) {
  const raw = Uint8Array.from(atob(env.OAUTH_ENC_KEY), c => c.charCodeAt(0));
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}

export async function cifrar(env, texto) {
  if (!texto) return null;
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv },
    await clave(env), new TextEncoder().encode(texto));
  return b64u(iv.buffer) + '.' + b64u(ct);
}

export async function descifrar(env, blob) {
  if (!blob || !blob.includes('.')) return null;
  const [ivB, ctB] = blob.split('.');
  const un = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: un(ivB) },
    await clave(env), un(ctB));
  return new TextDecoder().decode(pt);
}

/* ── RPC con service key ─────────────────────────────────────────────── */
export async function rpc(env, fn, body) {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`rpc ${fn} ${r.status}: ${(await r.text()).slice(0, 160)}`);
  return await r.json();
}

export function faltaConfig(env, prov) {
  const p = PROVEEDORES[prov];
  if (!p) return 'proveedor desconocido';
  for (const k of ['OAUTH_ENC_KEY', 'OAUTH_REDIRECT_BASE', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', p.idEnv, p.secretEnv]) {
    if (!env[k]) return `falta la env var ${k}`;
  }
  return null;
}

// Se le saca la barra final a la base antes de pegar el path. Parece un
// detalle y no lo es: los proveedores comparan la redirect_uri CARÁCTER POR
// CARÁCTER contra la que quedó registrada en su panel, así que un
// "https://app.mypumpteam.com//api/wearables/callback" se rechaza con
// redirect_uri_mismatch — un error que llega del lado del proveedor, sin
// explicar cuál es la diferencia. Y pegar la URL con barra final al cargar la
// env var es lo más normal del mundo.
export const redirectUri = (env) =>
  `${String(env.OAUTH_REDIRECT_BASE || '').replace(/\/+$/, '')}/api/wearables/callback`;

// Página mínima de cierre. No intenta volver a la app con un esquema custom
// (no existe en el Info.plist y agregarlo obligaría a un build nuevo): la app
// detecta la conexión por polling y cierra el navegador sola.
export const paginaCierre = (titulo, detalle, ok = true) => new Response(
  `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
   <title>${titulo}</title>
   <div style="font:16px/1.5 -apple-system,system-ui,sans-serif;max-width:420px;margin:18vh auto;padding:0 24px;text-align:center;color:#111">
     <div style="font-size:44px;margin-bottom:12px">${ok ? '✅' : '⚠️'}</div>
     <h1 style="font-size:20px;margin:0 0 8px">${titulo}</h1>
     <p style="color:#666;margin:0">${detalle}</p>
   </div>`,
  { status: ok ? 200 : 400, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
