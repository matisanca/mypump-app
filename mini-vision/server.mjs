/* =============================================================
   mini-vision — Visión con Codex CLI en la Mac mini (F7/F10)

   La app cliente manda una FOTO (etiqueta nutricional o plato de comida) y
   este servicio la interpreta con `codex exec` usando la CUENTA de ChatGPT
   logueada en la Mini (créditos de cuenta, NO API key) y devuelve JSON.

   POST /vision  body JSON: { token, tipo: 'etiqueta'|'plato', imagen_base64 }
     - token: el access_token del cliente de MyPump. Se valida contra Supabase
       (RPC mypump_get_cliente_info con la anon key) — sin secretos en el front.
     - imagen_base64: jpeg en base64 (el front ya lo reduce a ≤1024px).
   Respuesta: { ok:true, data:{...} }  |  { ok:false, error:'...' }

   Sin dependencias (Node 18+). Correr:  node server.mjs
   Deploy en la Mini: ver README-DEPLOY.md en esta carpeta.
   ============================================================= */
import { createServer } from 'node:http';
import { writeFile, unlink } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { tmpdir, homedir } from 'node:os';
import { join } from 'node:path';

// .env local del servicio (chmod 600). Ahí vive la SERVICE KEY que se usa
// para el bucket privado de fotos: no va en el plist ni en el front.
try {
  for (const linea of readFileSync(join(homedir(), 'mini-vision', '.env'), 'utf8').split('\n')) {
    const l = linea.trim();
    if (!l || l.startsWith('#') || !l.includes('=')) continue;
    const i = l.indexOf('=');
    const k = l.slice(0, i).trim();
    const v = l.slice(i + 1).trim().replace(/^["']|["']$/g, '');
    if (!process.env[k]) process.env[k] = v;
  }
} catch { /* sin .env: las fotos quedan deshabilitadas, visión sigue andando */ }

const PORT         = parseInt(process.env.PORT || '8791', 10);
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://gydinputrtptqakdzyvc.supabase.co';
const ANON_KEY     = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd5ZGlucHV0cnRwdHFha2R6eXZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxODk4NDgsImV4cCI6MjA5MTc2NTg0OH0.22TnFVwkRt2817RhmA1Vze8pgZSX-6I42PPTAEwb3Hk';
const CODEX_BIN    = process.env.CODEX_BIN || 'codex';
// Service key: SOLO para subir/firmar fotos de progreso (bucket privado).
// Vive en el .env del servicio (chmod 600), nunca en el front.
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY || '';
const TIMEOUT_MS   = 90_000;
const MAX_IMG_B    = 4 * 1024 * 1024;      // 4 MB de imagen máx
const MAX_FOTO_B   = 3 * 1024 * 1024;      // 3 MB por foto de progreso
const RATE_LIMIT   = 20;                    // pedidos de VISION por token por día
const RATE_FOTOS   = 12;                    // subidas de FOTO por token por día
const BUCKET_FOTOS = 'progreso';
const POSES        = new Set(['frente', 'perfil', 'espalda']);

// CORS: la app en prod + local dev.
const ALLOWED_ORIGINS = new Set([
  'https://app.mypumpteam.com',
  'http://localhost:8790',
  'http://localhost:3000',
]);

const PROMPTS = {
  etiqueta: `Mirá la foto adjunta: es la tabla de "Información Nutricional" de un producto alimenticio (probablemente en español).
Extraé los datos y respondé SOLO con un objeto JSON válido, sin texto extra, con esta forma exacta:
{"nombre": string (nombre del producto si se ve, si no un nombre genérico corto),
 "porcion_g": number (tamaño de la porción de referencia en gramos o ml; si la tabla es por 100g, usá 100),
 "kcal": number (calorías POR ESA porción),
 "prot": number (proteínas en g por porción),
 "carb": number (carbohidratos en g por porción),
 "fat": number (grasas totales en g por porción),
 "confianza": "alta"|"media"|"baja" (qué tan legible estaba la tabla)}
Si un valor no se lee, estimalo con criterio y bajá la confianza. Números con punto decimal, sin unidades.`,
  plato: `Mirá la foto adjunta: es un plato de comida real. Identificá los alimentos, estimá la porción de cada uno en gramos (criterio conservador) y sus macros.
Respondé SOLO con un objeto JSON válido, sin texto extra, con esta forma exacta:
{"descripcion": string (resumen corto del plato, ej "Milanesa con puré"),
 "alimentos": [{"nombre": string, "gramos": number, "kcal": number, "prot": number, "carb": number, "fat": number}],
 "kcal": number (total), "prot": number, "carb": number, "fat": number,
 "confianza": "alta"|"media"|"baja"}
Es un ESTIMATIVO para tracking nutricional: preferí subestimar levemente antes que exagerar. Números sin unidades.`,
};

// ── Rate limit en memoria, SEPARADO por feature (por token, por día) ──
// Antes era un contador único: subir 3 fotos se comía la cuota de visión.
const usage = new Map();   // token → {day, vision, fotos}
function overLimit(token, feature = 'vision') {
  const day = new Date().toISOString().slice(0, 10);
  const tope = feature === 'fotos' ? RATE_FOTOS : RATE_LIMIT;
  let u = usage.get(token);
  if (!u || u.day !== day) { u = { day, vision: 0, fotos: 0 }; usage.set(token, u); }
  if ((u[feature] || 0) >= tope) return true;
  u[feature] = (u[feature] || 0) + 1;
  return false;
}

// ── Resolver el cliente a partir del token (antes solo validaba) ──
// Devuelve el cliente_id o null. INVARIANTE DE SEGURIDAD: el cliente_id que
// arma el path de las fotos sale SIEMPRE de acá, NUNCA del body del request.
async function resolverCliente(token) {
  if (!token || typeof token !== 'string' || token.length < 16) return null;
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/mypump_get_cliente_info`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
      body: JSON.stringify({ p_token: token }),
    });
    if (!res.ok) return null;
    const rows = await res.json();
    return (Array.isArray(rows) && rows[0] && rows[0].cliente_id) ? rows[0].cliente_id : null;
  } catch { return null; }
}

// ── Helpers de fotos de progreso ──
const svcHeaders = (extra = {}) => ({
  apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, ...extra,
});

// Lunes ISO de una fecha YYYY-MM-DD (el mismo anclaje que el check semanal).
function lunesDe(fechaISO) {
  const d = new Date(`${fechaISO}T00:00:00Z`);
  if (isNaN(d)) return null;
  const dow = (d.getUTCDay() + 6) % 7;          // 0 = lunes
  d.setUTCDate(d.getUTCDate() - dow);
  return d.toISOString().slice(0, 10);
}

// Ventana tolerante (+1 / -7) como todas las RPC que reciben fecha del device.
function fechaAceptable(fechaISO) {
  const hoy = new Date();
  const f = new Date(`${fechaISO}T00:00:00Z`);
  if (isNaN(f)) return false;
  const dif = (f - new Date(hoy.toISOString().slice(0, 10) + 'T00:00:00Z')) / 86400000;
  return dif <= 1 && dif >= -7;
}

// JPEG real (no confiar en el prefijo del dataURL).
const esJPEG = (buf) => buf.length > 3 && buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF;

// ── Correr codex exec con la imagen ──
// OJO: `-i` acepta MÚLTIPLES archivos → el prompt va después de `--` (si no,
// codex lo trata como otra imagen y se cuelga leyendo stdin). `mcp_servers={}`
// deshabilita los MCP configurados en la Mini (no hacen falta y demoran).
function runCodex(imgPath, prompt) {
  return new Promise((resolve, reject) => {
    const args = ['exec', '--skip-git-repo-check', '-s', 'read-only',
                  '-c', 'mcp_servers={}', '-i', imgPath, '--', prompt];
    const child = execFile(CODEX_BIN, args, { timeout: TIMEOUT_MS, maxBuffer: 8 * 1024 * 1024, cwd: tmpdir() },
      (err, stdout, stderr) => {
        if (err) console.error('[vision] codex err:', err.message, '| stderr:', String(stderr).slice(-500));
        if (err && !stdout) return reject(new Error(`codex: ${err.message} ${String(stderr).slice(0, 300)}`));
        resolve(String(stdout));
      });
    child.on('error', reject);
    // CLAVE: cerrar stdin del child. Sin esto codex detecta un pipe abierto,
    // queda esperando input que nunca llega y muere por timeout con stdout vacío.
    if (child.stdin) child.stdin.end();
  });
}

// Extrae el ÚLTIMO objeto JSON balanceado del texto (codex agrega logs alrededor).
function extraerJSON(texto) {
  let end = texto.lastIndexOf('}');
  while (end !== -1) {
    let depth = 0;
    for (let i = end; i >= 0; i--) {
      if (texto[i] === '}') depth++;
      else if (texto[i] === '{') {
        depth--;
        if (depth === 0) {
          try { return JSON.parse(texto.slice(i, end + 1)); } catch { break; }
        }
      }
    }
    end = texto.lastIndexOf('}', end - 1);
  }
  return null;
}

function send(res, status, obj, origin) {
  const headers = { 'Content-Type': 'application/json' };
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Headers'] = 'Content-Type';
    headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
  }
  res.writeHead(status, headers);
  res.end(JSON.stringify(obj));
}

// ── Leer el body JSON con límite duro ──
function leerBody(req, res, origin, maxBytes) {
  return new Promise((resolve) => {
    let body = '', tooBig = false;
    req.on('data', (c) => { body += c; if (body.length > maxBytes * 1.4) { tooBig = true; req.destroy(); } });
    req.on('end', () => {
      if (tooBig) return resolve(null);
      try { resolve(JSON.parse(body)); }
      catch { send(res, 400, { ok: false, error: 'JSON inválido' }, origin); resolve(null); }
    });
  });
}

// ── POST /progreso/upload — sube una foto de progreso al bucket PRIVADO ──
async function handleFotoUpload(req, res, origin) {
  if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio de fotos no configurado' }, origin);
  const data = await leerBody(req, res, origin, MAX_FOTO_B);
  if (!data) return;
  const { token, pose, fecha, imagen_base64 } = data || {};

  if (!POSES.has(pose)) return send(res, 400, { ok: false, error: 'pose inválida' }, origin);
  if (!imagen_base64 || typeof imagen_base64 !== 'string') return send(res, 400, { ok: false, error: 'falta imagen' }, origin);
  const fechaISO = (typeof fecha === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(fecha))
    ? fecha : new Date().toISOString().slice(0, 10);
  if (!fechaAceptable(fechaISO)) return send(res, 400, { ok: false, error: 'fecha fuera de rango' }, origin);

  // INVARIANTE: el cliente_id sale del TOKEN, jamás del body.
  const clienteId = await resolverCliente(token);
  if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
  if (overLimit(token, 'fotos')) return send(res, 429, { ok: false, error: 'muchas fotos por hoy, probá mañana' }, origin);

  const buf = Buffer.from(imagen_base64.replace(/^data:image\/\w+;base64,/, ''), 'base64');
  if (!buf.length || buf.length > MAX_FOTO_B) return send(res, 400, { ok: false, error: 'imagen vacía o muy grande' }, origin);
  if (!esJPEG(buf)) return send(res, 400, { ok: false, error: 'la imagen debe ser JPEG' }, origin);

  const semanaLunes = lunesDe(fechaISO);
  const path = `${clienteId}/${semanaLunes}/${pose}.jpg`;

  try {
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET_FOTOS}/${path}`, {
      method: 'POST',
      headers: svcHeaders({ 'Content-Type': 'image/jpeg', 'x-upsert': 'true' }),
      body: buf,
    });
    if (!up.ok) {
      const t = await up.text();
      console.error('[fotos] storage fail', up.status, t.slice(0, 200));
      return send(res, 502, { ok: false, error: 'no se pudo guardar la foto' }, origin);
    }
    // Registro (upsert por cliente+semana+pose)
    const reg = await fetch(`${SUPABASE_URL}/rest/v1/mypump_fotos_progreso?on_conflict=cliente_id,semana_lunes,pose`, {
      method: 'POST',
      headers: svcHeaders({ 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates' }),
      body: JSON.stringify({
        cliente_id: clienteId, semana_lunes: semanaLunes, pose, path,
        bytes: buf.length, tomada_el: fechaISO, updated_at: new Date().toISOString(),
      }),
    });
    if (!reg.ok) {
      const t = await reg.text();
      console.error('[fotos] registro fail', reg.status, t.slice(0, 200));
      return send(res, 502, { ok: false, error: 'foto guardada pero no registrada' }, origin);
    }
    console.log(`[fotos] ok ${clienteId} ${semanaLunes} ${pose} (${Math.round(buf.length / 1024)}kb)`);
    send(res, 200, { ok: true, semana_lunes: semanaLunes, pose }, origin);
  } catch (e) {
    console.error('[fotos] error', e);
    send(res, 502, { ok: false, error: 'error al subir' }, origin);
  }
}

// ── POST /progreso/urls — URLs firmadas de LAS PROPIAS fotos del cliente ──
async function handleFotoUrls(req, res, origin) {
  if (!SERVICE_KEY) return send(res, 503, { ok: false, error: 'servicio de fotos no configurado' }, origin);
  const data = await leerBody(req, res, origin, 64 * 1024);
  if (!data) return;
  const { token, desde } = data || {};

  const clienteId = await resolverCliente(token);
  if (!clienteId) return send(res, 403, { ok: false, error: 'token inválido' }, origin);

  try {
    // INVARIANTE: los paths salen de una query filtrada por el cliente del token.
    // Jamás se firma un path recibido en el body.
    let q = `${SUPABASE_URL}/rest/v1/mypump_fotos_progreso`
          + `?cliente_id=eq.${encodeURIComponent(clienteId)}`
          + `&select=semana_lunes,pose,path&order=semana_lunes.desc`;
    if (typeof desde === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(desde)) q += `&semana_lunes=gte.${desde}`;
    const r = await fetch(q, { headers: svcHeaders() });
    if (!r.ok) return send(res, 502, { ok: false, error: 'no se pudo leer' }, origin);
    const filas = await r.json();
    if (!filas.length) return send(res, 200, { ok: true, fotos: [] }, origin);

    const fr = await fetch(`${SUPABASE_URL}/storage/v1/object/sign/${BUCKET_FOTOS}`, {
      method: 'POST',
      headers: svcHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ expiresIn: 3600, paths: filas.map(f => f.path) }),
    });
    if (!fr.ok) {
      console.error('[fotos] sign fail', fr.status, (await fr.text()).slice(0, 200));
      return send(res, 502, { ok: false, error: 'no se pudieron firmar' }, origin);
    }
    const firmadas = await fr.json();   // [{path, signedURL}]
    const porPath = Object.fromEntries(firmadas.map(x => [String(x.path).replace(/^\/+/, ''), x.signedURL]));
    const fotos = filas.map(f => ({
      semana_lunes: f.semana_lunes, pose: f.pose,
      url: porPath[f.path] ? `${SUPABASE_URL}/storage/v1${porPath[f.path]}` : null,
    })).filter(f => f.url);
    send(res, 200, { ok: true, fotos, expira_en: 3600 }, origin);
  } catch (e) {
    console.error('[fotos] urls error', e);
    send(res, 502, { ok: false, error: 'error al firmar' }, origin);
  }
}

const server = createServer(async (req, res) => {
  const origin = req.headers.origin || '';
  if (req.method === 'OPTIONS') return send(res, 204, {}, origin);
  if (req.method === 'GET' && req.url === '/health') return send(res, 200, { ok: true, service: 'mini-vision' }, origin);
  if (req.method === 'POST' && req.url === '/progreso/upload') return handleFotoUpload(req, res, origin);
  if (req.method === 'POST' && req.url === '/progreso/urls')   return handleFotoUrls(req, res, origin);
  if (req.method !== 'POST' || req.url !== '/vision') return send(res, 404, { ok: false, error: 'not found' }, origin);

  // Body (límite duro)
  let body = '';
  let tooBig = false;
  req.on('data', (c) => { body += c; if (body.length > MAX_IMG_B * 1.4) { tooBig = true; req.destroy(); } });
  req.on('end', async () => {
    if (tooBig) return;   // conexión ya destruida
    let data;
    try { data = JSON.parse(body); } catch { return send(res, 400, { ok: false, error: 'JSON inválido' }, origin); }
    const { token, tipo, imagen_base64 } = data || {};
    if (!PROMPTS[tipo]) return send(res, 400, { ok: false, error: 'tipo inválido' }, origin);
    if (!imagen_base64 || typeof imagen_base64 !== 'string') return send(res, 400, { ok: false, error: 'falta imagen' }, origin);

    if (!(await resolverCliente(token))) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
    if (overLimit(token, 'vision')) return send(res, 429, { ok: false, error: 'límite diario alcanzado, probá mañana' }, origin);

    const b64 = imagen_base64.replace(/^data:image\/\w+;base64,/, '');
    const buf = Buffer.from(b64, 'base64');
    if (!buf.length || buf.length > MAX_IMG_B) return send(res, 400, { ok: false, error: 'imagen vacía o muy grande' }, origin);

    const imgPath = join(tmpdir(), `mypump_vision_${Date.now()}_${Math.floor(Math.random() * 1e6)}.jpg`);
    try {
      await writeFile(imgPath, buf);
      const out = await runCodex(imgPath, PROMPTS[tipo]);
      const json = extraerJSON(out);
      if (!json) {
        console.error('[vision] sin JSON parseable. Output de codex (últimos 800):', String(out).slice(-800));
        return send(res, 502, { ok: false, error: 'no se pudo interpretar la foto, probá con más luz' }, origin);
      }
      send(res, 200, { ok: true, data: json }, origin);
    } catch (e) {
      send(res, 502, { ok: false, error: `visión falló: ${String(e.message || e).slice(0, 200)}` }, origin);
    } finally {
      unlink(imgPath).catch(() => {});
    }
  });
});

server.listen(PORT, () => console.log(`[mini-vision] escuchando en :${PORT}`));
