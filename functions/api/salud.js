/* =============================================================
   functions/api/salud.js — Cloudflare Pages Function
   Pipeline de salud, VÍA A (agregador tipo Rook/Terra vía webhook).

   Flujo: el agregador postea acá con un secreto compartido + el cliente_id
   (mapeado al conectar el reloj) + los registros ya normalizados. Se valida
   el secreto y se reenvía a la RPC service_role mypump_ingest_salud_service.

   La VÍA B (Apple Health nativo) NO pasa por acá: el plugin llama la RPC
   mypump_ingest_salud(token, registros) directo con la anon key, igual que el
   resto de escrituras del cliente. Ambas terminan en la misma tabla.

   ENV VARS a configurar en Cloudflare Pages (Settings → Environment variables):
     · SALUD_INGEST_SECRET        secreto compartido con el agregador
     · SUPABASE_URL               https://gydinputrtptqakdzyvc.supabase.co
     · SUPABASE_SERVICE_ROLE_KEY  service_role key (NUNCA en el cliente)

   Body esperado (POST, JSON):
     { "cliente_id": "abc123",
       "registros": [ { "fecha":"2026-07-13", "tipo":"pasos", "valor":8421,
                        "fuente":"rook", "detalle":{...} }, ... ] }
   ============================================================= */

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function onRequestPost(context) {
  const { request, env } = context;

  // 1. Autenticar el webhook con el secreto compartido.
  const secret = request.headers.get('X-Salud-Secret') || '';
  if (!env.SALUD_INGEST_SECRET || secret !== env.SALUD_INGEST_SECRET) {
    return json({ error: 'unauthorized' }, 403);
  }

  // 2. Parsear y validar el body.
  let body;
  try { body = await request.json(); }
  catch { return json({ error: 'bad json' }, 400); }

  const clienteId = body && body.cliente_id;
  const registros = body && body.registros;
  if (!clienteId || !Array.isArray(registros)) {
    return json({ error: 'faltan cliente_id o registros[]' }, 400);
  }

  // 3. Reenviar a la RPC service_role de Supabase.
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
    return json({ error: 'server no configurado (faltan env vars)' }, 500);
  }
  let rpcRes;
  try {
    rpcRes = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/mypump_ingest_salud_service`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': env.SUPABASE_SERVICE_ROLE_KEY,
        'Authorization': `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ p_cliente_id: clienteId, p_registros: registros }),
    });
  } catch (e) {
    return json({ error: 'no se pudo contactar el backend', detail: String(e).slice(0, 200) }, 502);
  }

  if (!rpcRes.ok) {
    const txt = await rpcRes.text().catch(() => '');
    return json({ error: 'rpc fail', status: rpcRes.status, detail: txt.slice(0, 200) }, 502);
  }

  const ingresados = await rpcRes.json().catch(() => null);  // la RPC devuelve un INTEGER
  return json({ ok: true, ingresados }, 200);
}
// (Otros métodos → 405 automático: solo exportamos onRequestPost.)
