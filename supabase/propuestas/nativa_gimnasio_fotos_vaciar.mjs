#!/usr/bin/env node
// Reverso de Gimnasio por fotos: vacía objetos y filas, y borra el bucket por la API de Storage (ver el orden en
// nativa_gimnasio_fotos_revertir.sql). Sin --confirmar solo cuenta. Con la service key en el entorno, nunca en el repo.
//   SUPABASE_URL=… SUPABASE_SERVICE_KEY=… node nativa_gimnasio_fotos_vaciar.mjs vaciar  [--confirmar]
//   SUPABASE_URL=… SUPABASE_SERVICE_KEY=… node nativa_gimnasio_fotos_vaciar.mjs bucket  [--confirmar]
const BUCKET = 'gimnasio';
const URLB = process.env.SUPABASE_URL, KEY = process.env.SUPABASE_SERVICE_KEY;
if (!URLB || !KEY) { console.error('faltan SUPABASE_URL y SUPABASE_SERVICE_KEY'); process.exit(2); }
const H = (extra = {}) => ({ apikey: KEY, Authorization: `Bearer ${KEY}`, ...extra });
const [modo, ...resto] = process.argv.slice(2);
const confirmar = resto.includes('--confirmar');

async function listar(prefijo) {
  const paths = [];
  for (let offset = 0; ; offset += 100) {
    const r = await fetch(`${URLB}/storage/v1/object/list/${BUCKET}`, {
      method: 'POST', headers: H({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ prefix: prefijo, limit: 100, offset, sortBy: { column: 'name', order: 'asc' } }),
    });
    if (!r.ok) throw new Error(`listar: HTTP ${r.status}`);
    const lista = await r.json();
    if (!Array.isArray(lista)) throw new Error('listar: respuesta inesperada');
    for (const e of lista) {
      const p = prefijo ? `${prefijo}/${e.name}` : e.name;
      if (e.id === null || e.id === undefined) paths.push(...await listar(p));
      else paths.push(p);
    }
    if (lista.length < 100) return paths;
  }
}

async function vaciar() {
  const paths = await listar('');
  console.log(`objetos: ${paths.length}`);
  if (!confirmar) { console.log('sin --confirmar no se borra nada'); return; }
  for (let i = 0; i < paths.length; i += 500) {
    const r = await fetch(`${URLB}/storage/v1/object/${BUCKET}`, {
      method: 'DELETE', headers: H({ 'Content-Type': 'application/json' }), body: JSON.stringify({ prefixes: paths.slice(i, i + 500) }),
    });
    if (!r.ok) throw new Error(`borrar objetos: HTTP ${r.status}`);
  }
  const f = await fetch(`${URLB}/rest/v1/mypump_gimnasio_fotos?id=not.is.null`, { method: 'DELETE', headers: H() });
  if (!f.ok) throw new Error(`borrar filas: HTTP ${f.status}`);
  const quedan = await listar('');
  if (quedan.length) throw new Error(`quedan ${quedan.length} objetos: ¿se cortó la subida antes?`);
  console.log('vacío');
}

async function bucket() {
  const quedan = await listar('');
  if (quedan.length) throw new Error(`quedan ${quedan.length} objetos: primero vaciar`);
  if (!confirmar) { console.log('bucket vacío; sin --confirmar no se borra'); return; }
  const r = await fetch(`${URLB}/storage/v1/bucket/${BUCKET}`, { method: 'DELETE', headers: H() });
  if (!r.ok) throw new Error(`borrar bucket: HTTP ${r.status}`);
  console.log('bucket borrado');
}

try {
  if (modo === 'vaciar') await vaciar();
  else if (modo === 'bucket') await bucket();
  else { console.error('uso: vaciar|bucket [--confirmar]'); process.exit(2); }
} catch (e) {
  console.error(e.message || e);
  process.exit(1);
}
