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
import { execFile } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const PORT         = parseInt(process.env.PORT || '8791', 10);
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://gydinputrtptqakdzyvc.supabase.co';
const ANON_KEY     = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd5ZGlucHV0cnRwdHFha2R6eXZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxODk4NDgsImV4cCI6MjA5MTc2NTg0OH0.22TnFVwkRt2817RhmA1Vze8pgZSX-6I42PPTAEwb3Hk';
const CODEX_BIN    = process.env.CODEX_BIN || 'codex';
const TIMEOUT_MS   = 90_000;
const MAX_IMG_B    = 4 * 1024 * 1024;      // 4 MB de imagen máx
const RATE_LIMIT   = 20;                    // pedidos por token por día

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

// ── Rate limit simple en memoria (por token, por día) ──
const usage = new Map();   // token → {day, count}
function overLimit(token) {
  const day = new Date().toISOString().slice(0, 10);
  const u = usage.get(token);
  if (!u || u.day !== day) { usage.set(token, { day, count: 1 }); return false; }
  if (u.count >= RATE_LIMIT) return true;
  u.count++;
  return false;
}

// ── Validar el token del cliente contra Supabase ──
async function validarToken(token) {
  if (!token || typeof token !== 'string' || token.length < 16) return false;
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/mypump_get_cliente_info`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
      body: JSON.stringify({ p_token: token }),
    });
    if (!res.ok) return false;
    const rows = await res.json();
    return Array.isArray(rows) && rows.length > 0;
  } catch { return false; }
}

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

const server = createServer(async (req, res) => {
  const origin = req.headers.origin || '';
  if (req.method === 'OPTIONS') return send(res, 204, {}, origin);
  if (req.method === 'GET' && req.url === '/health') return send(res, 200, { ok: true, service: 'mini-vision' }, origin);
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

    if (!(await validarToken(token))) return send(res, 403, { ok: false, error: 'token inválido' }, origin);
    if (overLimit(token)) return send(res, 429, { ok: false, error: 'límite diario alcanzado, probá mañana' }, origin);

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
