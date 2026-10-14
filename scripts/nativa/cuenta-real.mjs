#!/usr/bin/env node
/* =============================================================
   cuenta-real.mjs — cuenta de prueba con la FORMA REAL del Cerebro

   Las cuentas de seed-cliente traen el plan sintético con los campos viejos
   (series/reps/rir_objetivo sueltos, sin progresion, sin images, sin catalogo_slug).
   Los clientes reales tienen otra forma, y la nativa tiene que dibujar esa. Este
   script crea `test-nativa-real` con un molde real:
   - progresión por semana con título;
   - imágenes y catalogo_slug;
   - semana_offset y fase.

   El molde es el plan genérico de un tester (no de un cliente). Se lee de
   ~/Developer/nativa-evidencia/privado/molde.json, fuera del repo.

   - El plan se aplica en la mini con ~/_aplicar.py (necesita rol authenticated).
   - La historia va por las RPC reales, siguiendo la progresión de cada semana.
   - El token queda en privado/cuentas-prueba.json.

   Uso: node scripts/nativa/cuenta-real.mjs [--semana-actual 5] [--semanas-historia 4]
   ============================================================= */

import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sqlPlan, mulberry32 } from '../lib/plan-sintetico.mjs';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const PRIVADO = path.join(os.homedir(), 'Developer', 'nativa-evidencia', 'privado');
const REGISTRO = path.join(PRIVADO, 'cuentas-prueba.json');
const MOLDE = path.join(PRIVADO, 'molde.json');

const A = process.argv.slice(2);
const val = (n, d) => { const i = A.indexOf(n); return i >= 0 && A[i + 1] ? A[i + 1] : d; };
const SEMANA_ACTUAL = Number(val('--semana-actual', 5));
const SEMANAS_HISTORIA = Number(val('--semanas-historia', 4));
const CLIENTE_ID = 'test-nativa-real';
const NOMBRE = 'Test Nativa real';

const w = {};
new Function('window', fs.readFileSync(path.join(RAIZ, 'public/js/config.js'), 'utf8'))(w);
const { SUPABASE_URL, SUPABASE_ANON_KEY } = w.MYPUMP_CONFIG;

const registro = fs.existsSync(REGISTRO) ? JSON.parse(fs.readFileSync(REGISTRO, 'utf8')) : {};
const tokenAleatorio = () => {
  const ab = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let t = '';
  for (const b of crypto.randomBytes(64)) { if (b < 248) t += ab[b % 62]; if (t.length === 32) break; }
  return t;
};
const TOKEN = registro[CLIENTE_ID]?.token || tokenAleatorio();

async function rpc(fn, body) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_token: TOKEN, ...body }),
  });
  const t = await r.text();
  if (!r.ok) throw new Error(`${fn} HTTP ${r.status}: ${t.slice(0, 200)}`);
  return t ? JSON.parse(t) : null;
}

// ── 1. El plan ───────────────────────────────────────────────────────
const molde = JSON.parse(fs.readFileSync(MOLDE, 'utf8'));
const rutina = { ...molde.rutina, nombre_plan: 'Plan de prueba — Tirón / Empuje / Piernas / Torso' };
const dieta = molde.dieta;
const sql = sqlPlan({ clienteId: CLIENTE_ID, nombre: NOMBRE, perfil: 'natural', token: TOKEN, rutina, dieta, semanaActual: SEMANA_ACTUAL });
const sqlLocal = path.join(PRIVADO, `.plan-${CLIENTE_ID}.sql`);
fs.writeFileSync(sqlLocal, sql);
const sqlRemoto = `/tmp/nativa-plan-${CLIENTE_ID}.sql`;
execFileSync('scp', ['-q', sqlLocal, `mini:${sqlRemoto}`], { stdio: 'inherit' });
const aplicado = execFileSync('ssh', ['mini', `~/agentkit-coach/venv/bin/python3 ~/_aplicar.py ${sqlRemoto} && rm -f ${sqlRemoto}`]).toString();
fs.rmSync(sqlLocal, { force: true });
if (!/COMMIT/.test(aplicado)) { console.error(aplicado); process.exit(1); }
console.log(`▸ plan aplicado: ${CLIENTE_ID}, semana ${SEMANA_ACTUAL}/${rutina.semanas_total}, ${rutina.dias.length} días`);

// ── 2. La historia, siguiendo la progresión de cada semana ──────────
const rnd = mulberry32(7);
const repsBajas = (reps) => { const m = String(reps || '').match(/\d+/); return m ? Number(m[0]) : 10; };
const rirDe = (rir) => { const m = String(rir ?? '').match(/\d+/); return m ? Number(m[0]) : 1; };
let sesiones = 0, series = 0;
for (let semana = Math.max(1, SEMANA_ACTUAL - SEMANAS_HISTORIA); semana < SEMANA_ACTUAL; semana++) {
  for (const dia of rutina.dias) {
    if (rnd() > 0.85) continue;   // algún día salteado
    const sesionId = await rpc('mypump_iniciar_sesion', { p_dia_id: dia.id, p_semana: semana });
    if (!sesionId) continue;
    for (const b of (dia.bloques || []).filter(Boolean)) {
      for (const e of (b.ejercicios || [])) {
        if (['cardio', 'calentamiento'].includes(e.tipo)) continue;
        const p = (e.progresion || [])[Math.min(semana, (e.progresion || []).length) - 1] || {};
        const n = Number(p.series) || 3;
        const base = e.tipo === 'compuesto' ? 50 : e.tipo === 'core' ? 0 : 15;
        const peso = base ? Math.round(base * (1 + 0.04 * semana) * 2) / 2 : 0;
        for (let s = 1; s <= n; s++) {
          await rpc('mypump_registrar_carga', {
            p_sesion_id: sesionId, p_dia_id: dia.id, p_ejercicio_id: e.id, p_ejercicio_nombre: e.nombre,
            p_serie: s, p_peso: peso, p_reps: repsBajas(p.reps) + (s === 1 ? 1 : 0), p_rir: rirDe(p.rir), p_notas: null,
          });
          series++;
        }
      }
    }
    await rpc('mypump_finalizar_sesion', { p_sesion_id: sesionId, p_notas: null, p_duracion_segundos: 3000 + Math.round(rnd() * 1800) });
    sesiones++;
  }
}

// Peso de los últimos 21 días y un check de la semana pasada.
const ymd = (d) => d.toLocaleDateString('en-CA');
const pesos = [];
for (let i = 21; i >= 1; i--) pesos.push({ fecha: ymd(new Date(Date.now() - i * 864e5)), tipo: 'peso_kg', valor: Math.round((82 - i * 0.04 + (rnd() - 0.5) * 0.6) * 10) / 10, fuente: 'manual' });
await rpc('mypump_ingest_salud', { p_registros: pesos });

console.log(`▸ historia: ${sesiones} sesiones, ${series} series, ${pesos.length} pesos`);
registro[CLIENTE_ID] = { token: TOKEN, escenario: 'molde-real', visible: false, nombre: NOMBRE,
  creada: registro[CLIENTE_ID]?.creada || new Date().toISOString(), resembrada: new Date().toISOString() };
fs.writeFileSync(REGISTRO, JSON.stringify(registro, null, 2), { mode: 0o600 });
console.log(`✓ ${CLIENTE_ID} lista (token en privado/cuentas-prueba.json, no se imprime)`);
