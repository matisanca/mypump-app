#!/usr/bin/env node
/* =============================================================
 * test-metas.mjs — «Pump del día» y ritmo de peso, con los MISMOS vectores
 * de iOS y Android (scripts/vectores-app/metas_pasos.json, copia exacta de
 * apps/shared/vectores/metas_pasos.json), más que el service worker guarde
 * el módulo y que la palanca esté apagada si el servidor no la manda.
 * USO:  node scripts/test-metas.mjs
 * ============================================================= */
import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const M = require('../public/js/metas.js');
const V = JSON.parse(fs.readFileSync(new URL('./vectores-app/metas_pasos.json', import.meta.url), 'utf8'));

let ok = 0, fail = 0;
const igual = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function t(nombre, cond, extra) {
  if (cond) { ok++; return; }
  fail++;
  console.log(`  ✗ ${nombre}${extra === undefined ? '' : ` → ${JSON.stringify(extra)}`}`);
}

for (const c of V.metas) {
  const m = M.metasDe(c.estructura);
  t(`metas ${c.nombre}`, m.metaPasos === c.metaPasos && m.ritmo === c.ritmo, m);
}
for (const c of V.vista) {
  const v = M.vista(c.pasos, c.meta, c.hoy), e = c.esperado;
  const r = v && { pasosHoy: v.pasosHoy, falta: v.falta, cumplido: v.cumplido, racha: v.racha, semana: v.semana.map((d) => d.estado), promedio7: v.promedio7 };
  t(`vista ${c.nombre}`, v && Math.abs(v.fraccion - e.fraccion) < 1e-6 &&
    igual(r, { pasosHoy: e.pasosHoy, falta: e.falta, cumplido: e.cumplido, racha: e.racha, semana: e.semana, promedio7: e.promedio7 }), r);
}
for (const c of V.celebrar) t(`celebrar ${c.nombre}`, M.debeCelebrar(c.celebrados, c.hoy, c.pasos, c.meta) === c.celebra);
for (const c of V.ritmo) {
  const serie = Object.entries(c.pesos).map(([fecha, kg]) => ({ fecha, kg })).sort((a, b) => (a.fecha < b.fecha ? -1 : 1));
  const r = M.ritmo(c.ritmo, serie, c.hoy), e = c.esperado;
  t(`ritmo ${c.nombre}`, r.meta === e.meta && r.tendencia === e.tendencia && r.enRitmo === e.enRitmo, r);
}
for (const c of V.cantidad) t(`cantidad ${c.kg}`, M.cantidad(c.kg) === c.texto, M.cantidad(c.kg));

// Una vez por día, y el registro guarda las últimas 60 fechas en orden.
let reg = [];
t('celebra la primera', M.debeCelebrar(reg, '2026-11-10', 10000, 10000));
reg = M.marcar(reg, '2026-11-10');
t('no dos veces el mismo día', !M.debeCelebrar(reg, '2026-11-10', 12000, 10000));
t('al día siguiente sí', M.debeCelebrar(reg, '2026-11-11', 10000, 10000));
let largo = [];
for (let i = 0; i < 70; i++) largo = M.marcar(largo, M.texto(M.numero('2026-01-01') + i));
t('poda a 60', largo.length === 60 && largo[0] === M.texto(M.numero('2026-01-01') + 10));
t('fecha rota', M.vista({}, 10000, '2026-02-30') === null);

// Textos sin dos puntos, guiones ni emojis.
const v = M.vista({ '2026-11-10': 7420 }, 10000, '2026-11-10');
const textos = [M.T.deMeta(v), M.T.estado(v), M.T.racha(3), M.T.sinSalud(10000), M.T.conectar, M.T.conectarBoton,
  M.T.celebracion(10000), M.T.celebracionRacha(4), M.T.seguir, M.T.lineaSalud(10000, 8200), M.T.enRitmo, M.textoMeta(-0.5)];
t('estado', M.T.estado(v) === 'Te faltan 2.580 pasos', M.T.estado(v));
for (const s of textos) t(`texto limpio «${s}»`, !/[:\-–—]|\p{Extended_Pictographic}/u.test(s));
t('sin «coach»', !textos.some((s) => /coach|entrenador|IA\b/i.test(s)));

// El service worker guarda el módulo (la app abre sin red) y la palanca está apagada si no viene.
const sw = fs.readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8');
t('sw guarda metas.js', sw.includes("'/js/metas.js'"));
const html = fs.readFileSync(new URL('../public/cliente.html', import.meta.url), 'utf8');
t('cliente carga metas.js', html.includes('<script src="/js/metas.js"></script>'));
t('palanca estricta', /metas_pasos === true/.test(html));
{
  const i = html.indexOf('function _metasPalanca('), cuerpo = html.slice(i, html.indexOf('\n}\n', i));
  t('sin respuesta de la config: lo último guardado', i > 0 && /getItem\(_METAS_PALANCA_KEY\) === '1'/.test(cuerpo) && /removeItem\(_METAS_PALANCA_KEY\)/.test(cuerpo));
}

console.log(`test-metas: ${ok} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
