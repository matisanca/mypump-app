#!/usr/bin/env node
/* =============================================================
   grabar-fixtures.mjs — respuestas REALES de las RPC de lectura de una cuenta de prueba

   Las graba en apps/shared/fixtures/<cuenta>/<rpc>.json para que:
   - los modelos Codable se prueben contra lo que devuelve la base de verdad;
   - los bocetos y las previews de SwiftUI/Compose muestren datos reales.

   Solo cuentas de prueba (test-nativa-*): nunca un cliente. El token no se graba.

   Uso: node scripts/nativa/grabar-fixtures.mjs test-nativa-real
   ============================================================= */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const CUENTA = process.argv[2];
if (!CUENTA || !CUENTA.startsWith('test-nativa-')) {
  console.error('✗ uso: grabar-fixtures.mjs test-nativa-<cuenta>');
  process.exit(2);
}
const reg = JSON.parse(fs.readFileSync(path.join(os.homedir(), 'Developer/nativa-evidencia/privado/cuentas-prueba.json'), 'utf8'));
const TOKEN = reg[CUENTA]?.token;
if (!TOKEN) { console.error(`✗ ${CUENTA} no está en el registro`); process.exit(2); }

const w = {};
new Function('window', fs.readFileSync(path.join(RAIZ, 'public/js/config.js'), 'utf8'))(w);
const { SUPABASE_URL, SUPABASE_ANON_KEY } = w.MYPUMP_CONFIG;
const rpc = async (fn, body = {}) => {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/mypump_${fn}`, {
    method: 'POST',
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_token: TOKEN, ...body }),
  });
  return { status: r.status, body: await r.json().catch(() => null) };
};

const salida = path.join(RAIZ, 'apps/shared/fixtures', CUENTA);
fs.mkdirSync(salida, { recursive: true });
const guardar = (fn, body) => fs.writeFileSync(path.join(salida, `${fn}.json`), JSON.stringify(body, null, 1) + '\n');

const hoy = new Date().toLocaleDateString('en-CA');
const hace59 = new Date(Date.now() - 59 * 864e5).toLocaleDateString('en-CA');
const simples = {
  get_cliente_info: {}, get_rutina_activa: {}, get_dieta_activa: {}, get_cliente_prefs: {}, get_custom_foods: {},
  get_comentarios: { p_ambito: null, p_referencia_id: null }, get_chat: { p_antes: null, p_limite: 30 },
  get_habitos_dia: { p_fecha: hoy }, get_streak: {}, get_adherencia_30d: {}, get_comidas_marcadas: { p_fecha: hoy },
  get_comidas_libres: { p_fecha: hoy }, get_salud: { p_desde: hace59, p_hasta: hoy }, get_recuperacion: { p_dias: 14 },
  get_mostrar_recuperacion: {}, get_conexiones: {}, get_checkin_semana: { p_fecha: hoy }, get_fotos_progreso: { p_desde: null },
};
const estados = {};
for (const [fn, body] of Object.entries(simples)) {
  const r = await rpc(fn, body);
  estados[fn] = r.status;
  guardar(fn, r.body);
}

const rutina = JSON.parse(fs.readFileSync(path.join(salida, 'get_rutina_activa.json')))[0];
const dieta = JSON.parse(fs.readFileSync(path.join(salida, 'get_dieta_activa.json')))[0];
const ses = await rpc('get_sesiones_semana', { p_semana: rutina.semana_actual }); guardar('get_sesiones_semana', ses.body);
const sw = await rpc('get_food_swaps', { p_dieta_id: dieta.id }); guardar('get_food_swaps', sw.body);

// Misma normalización que claveEjercicio (cliente.html:2092) y mypump_clave_ejercicio (072).
const clave = (n) => String(n || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  .replace(/\(.*?\)/g, ' ').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
const claves = [...new Set(rutina.estructura.dias.flatMap((d) => (d.bloques || []).filter(Boolean)
  .flatMap((b) => (b.ejercicios || []).map((e) => clave(e.nombre)))))];
const hist = await rpc('get_historico_por_clave', { p_claves: claves, p_limit_por_ej: 48 }); guardar('get_historico_por_clave', hist.body);

// La sesión del primer día de la semana anterior, con sus registros (para la vista de una sesión).
const sd = await rpc('get_sesion_dia', { p_dia_id: rutina.estructura.dias[0].id, p_semana: Math.max(1, rutina.semana_actual - 1) });
guardar('get_sesion_dia', sd.body);
const sesionId = Array.isArray(sd.body) && sd.body[0]?.id;
if (sesionId) {
  guardar('get_registros_sesion', (await rpc('get_registros_sesion', { p_sesion_id: sesionId })).body);
  guardar('get_ejercicios_estado', (await rpc('get_ejercicios_estado', { p_sesion_id: sesionId })).body);
}

const malos = Object.entries(estados).filter(([, s]) => s !== 200);
const contiene = fs.readdirSync(salida).filter((f) => fs.readFileSync(path.join(salida, f), 'utf8').includes(TOKEN));
console.log(`▸ ${CUENTA}: ${fs.readdirSync(salida).length} fixtures, semana ${rutina.semana_actual}, ${(hist.body || []).length} filas de historial`);
if (malos.length) console.log('  ⚠ status != 200:', malos);
if (contiene.length) { console.error('✗ el token quedó en', contiene); process.exit(1); }
