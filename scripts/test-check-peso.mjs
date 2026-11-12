#!/usr/bin/env node
/* =============================================================
 * test-check-peso.mjs — «Tu peso de hoy» del check de la semana y la tarjeta Peso corporal (web).
 *
 * Falla reportada (12/11): el alumno escribía el peso en el check, tocaba «Enviar mi check», el peso SÍ se guardaba
 * pero el campo quedaba vacío y parecía que se había borrado (lo volvía a escribir en la nota).
 *
 * Se corre el código REAL de public/cliente.html (las funciones se extraen por texto) con un DOM mínimo:
 *  · después de enviar, el campo muestra el peso guardado de hoy con una línea que lo confirma;
 *  · «Actualizar mi check» con el peso sin tocar no lo vuelve a mandar; corregido, sí;
 *  · coma o punto decimal («69,900», «69.9») dan 69,9;
 *  · un repintado de la tarjeta Peso corporal no borra lo que el alumno está escribiendo.
 *
 * USO:  node scripts/test-check-peso.mjs
 * ============================================================= */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const html = fs.readFileSync(path.join(raiz, 'public/cliente.html'), 'utf8');
const funcion = (nombre) => {
  const m = html.match(new RegExp(`\\n((?:async )?function ${nombre}\\([^)]*\\) \\{[\\s\\S]*?\\n\\})\\n`));
  if (!m) { console.error(`✗ no encontré ${nombre} en cliente.html`); process.exit(1); }
  return m[1];
};
const linea = (inicio) => {
  const m = html.match(new RegExp(`\\n(${inicio.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[^\\n]*)\\n`));
  if (!m) { console.error(`✗ no encontré «${inicio}» en cliente.html`); process.exit(1); }
  return m[1];
};

let ok = 0, fail = 0;
const t = (nombre, fn) => {
  try { fn(); console.log(`  ✓ ${nombre}`); ok++; }
  catch (e) { console.log(`  ✗ ${nombre}\n      ${e.message}`); fail++; }
};
const igual = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}: ${JSON.stringify(a)} ≠ ${JSON.stringify(b)}`); };

/* DOM mínimo: un contenedor por id; los elementos de adentro salen del HTML que se le puso (valor, texto, hidden). */
function crearDom() {
  const contenedores = {};
  let cache = {};
  const doc = { activeElement: null };
  const desatar = (s) => s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  const elemento = (id, html) => {
    const input = html.match(new RegExp(`<input[^>]*id="${id}"[^>]*>`));
    const ta = html.match(new RegExp(`<textarea[^>]*id="${id}"[^>]*>([\\s\\S]*?)</textarea>`));
    const otro = html.match(new RegExp(`<(\\w+)[^>]*id="${id}"([^>]*)>([^<]*)<`));
    const handlers = {};
    const el = {
      id, handlers, hidden: false, textContent: '', value: '',
      addEventListener: (ev, f) => { (handlers[ev] = handlers[ev] || []).push(f); },
      focus: () => { doc.activeElement = el; },
      setSelectionRange: () => {},
      fire: (ev) => (handlers[ev] || []).forEach(f => f({ key: '', preventDefault() {} })),
      style: {},
    };
    if (input) {
      const v = input[0].match(/value="([^"]*)"/);
      el.value = v ? desatar(v[1]) : '';
    } else if (ta) {
      el.value = desatar(ta[1]);
    } else if (otro) {
      el.hidden = /\shidden(\s|$|>)/.test(otro[0]);
      el.textContent = otro[3];
    }
    return el;
  };
  doc.getElementById = (id) => {
    if (contenedores[id]) return contenedores[id];
    if (cache[id]) return cache[id];
    const dueño = Object.values(contenedores).find(c => c.innerHTML.includes(`id="${id}"`));
    if (!dueño) return null;
    return (cache[id] = elemento(id, dueño.innerHTML));
  };
  const contenedor = (id) => {
    let h = '';
    contenedores[id] = {
      get innerHTML() { return h; },
      set innerHTML(v) { h = v; cache = {}; if (doc.activeElement && doc.activeElement.id !== id) doc.activeElement = null; },
      querySelectorAll: () => [],
    };
  };
  return { doc, contenedor };
}

function contexto() {
  const { doc, contenedor } = crearDom();
  contenedor('myday-checkin');
  contenedor('myday-peso');
  const cola = [];
  const ctx = {
    console, document: doc, isFinite, Number, String, Math, JSON, setTimeout: () => 0,
    STATE: { scene: 'revision', checkin: null, checkinDraft: null, checkinPeso: null, pesoBorrador: null, salud: [] },
    DEMO: false, DATA: null,
    hoyLocal: () => '2026-11-12',
    web230: () => false, checkGuiadoPrendido: () => false,
    _encabezadoAvance: () => '', _saludSemanaHtml: () => '', renderRecordatorio: () => {},
    Outbox: { enqueue: (kind, payload, key) => cola.push({ kind, payload, key }), pendingByKey: () => new Map(cola.map(o => [o.key, o])) },
    // La tarjeta Peso corporal: lo que no hace al campo, vacío.
    _pesoSerie: () => ctx.STATE.salud.filter(r => r.tipo === 'peso_kg').map(r => ({ fecha: r.fecha, kg: Number(r.valor) })),
    _pesoMedia: () => null, pesoChartSVG: () => '', _ritmoPesoHTML: () => '',
  };
  vm.createContext(ctx);
  vm.runInContext([
    funcion('escapeHtml'),
    'const CHECKIN_METRICAS = [{k:"energia",label:"Energía"},{k:"descanso",label:"Descanso"},{k:"hambre",label:"Hambre"},{k:"adherencia",label:"Adherencia"}];',
    funcion('_cgPesoDeHoy'),
    linea('const _ckKg = '),
    funcion('_ckPesoValor'), funcion('_ckPesoOkTexto'), funcion('_ckPintarPesoHoy'),
    funcion('renderMydayCheckin'), funcion('renderMydayPeso'),
    'this.renderMydayCheckin = renderMydayCheckin; this.renderMydayPeso = renderMydayPeso; this._ckPintarPesoHoy = _ckPintarPesoHoy;',
  ].join('\n'), ctx);
  const $ = (id) => doc.getElementById(id);
  const escribir = (id, texto) => { const e = $(id); e.focus(); e.value = texto; e.fire('input'); };
  const enviar = () => $('ckSave').fire('click');
  const lleno = () => { ctx.STATE.checkinDraft = { energia: 4, descanso: 4, hambre: 4, adherencia: 4 }; };
  return { ctx, doc, $, cola, escribir, enviar, lleno };
}

console.log('Check de la semana · el peso después de enviar');
t('el peso escrito con coma se guarda y el campo sigue mostrándolo (no queda vacío)', () => {
  const c = contexto();
  c.lleno(); c.ctx.renderMydayCheckin();
  c.escribir('ckPeso', '69,900');
  c.enviar();
  igual(c.cola.filter(o => o.kind === 'peso').map(o => o.payload), [{ fecha: '2026-11-12', valor: 69.9 }], 'el peso que sale por la cola');
  igual(c.$('ckPeso').value, '69,9', 'el campo después de enviar');
  igual(c.$('ckPesoOk').hidden, false, 'la línea de confirmación se ve');
  if (!c.$('ckPesoOk').textContent.includes('69,9 kg')) throw new Error(`confirmación: «${c.$('ckPesoOk').textContent}»`);
});
t('con punto también: «69.9» da 69,9', () => {
  const c = contexto();
  c.lleno(); c.ctx.renderMydayCheckin();
  c.escribir('ckPeso', '69.9');
  c.enviar();
  igual(c.cola.filter(o => o.kind === 'peso').map(o => o.payload.valor), [69.9], 'peso');
  igual(c.$('ckPeso').value, '69,9', 'campo');
});
t('«Actualizar mi check» con el peso sin tocar no lo manda de nuevo', () => {
  const c = contexto();
  c.lleno(); c.ctx.renderMydayCheckin();
  c.escribir('ckPeso', '69,9');
  c.enviar();
  c.escribir('ckNota', 'hoy pesé 69,9');
  c.ctx.STATE.checkinDraft = { ...c.ctx.STATE.checkin, nota: 'hoy pesé 69,9' };
  c.ctx.renderMydayCheckin();
  c.enviar();
  igual(c.cola.filter(o => o.kind === 'peso').length, 1, 'pesos en la cola');
  igual(c.cola.filter(o => o.kind === 'checkin').length, 2, 'checks en la cola');
  igual(c.$('ckPeso').value, '69,9', 'campo');
});
t('corregido en el check, sale el nuevo', () => {
  const c = contexto();
  c.ctx.STATE.salud = [{ fecha: '2026-11-12', tipo: 'peso_kg', valor: '69.90', fuente: 'manual' }];
  c.lleno(); c.ctx.renderMydayCheckin();
  igual(c.$('ckPeso').value, '69,9', 'viene puesto el de hoy');
  c.escribir('ckPeso', '70,2');
  c.enviar();
  igual(c.cola.filter(o => o.kind === 'peso').map(o => o.payload.valor), [70.2], 'peso');
  igual(c.$('ckPeso').value, '70,2', 'campo');
});
t('sin peso hoy: vacío y sin confirmación; si lo borra a propósito, queda vacío', () => {
  const c = contexto();
  c.lleno(); c.ctx.renderMydayCheckin();
  igual(c.$('ckPeso').value, '', 'campo');
  igual(c.$('ckPesoOk').hidden, true, 'confirmación oculta');
  c.ctx.STATE.salud = [{ fecha: '2026-11-12', tipo: 'peso_kg', valor: 69.9, fuente: 'manual' }];
  c.escribir('ckPeso', '');
  c.ctx.renderMydayCheckin();
  igual(c.$('ckPeso').value, '', 'lo que borró no vuelve mientras no envía');
});
t('fuera de 30-300 avisa y no manda nada', () => {
  const c = contexto();
  c.lleno(); c.ctx.renderMydayCheckin();
  c.escribir('ckPeso', '69900');
  c.enviar();
  igual(c.cola.length, 0, 'cola');
  igual(c.$('ckPesoAviso').hidden, false, 'aviso');
});
t('cuando llega la salud del servidor, el peso de hoy aparece sin repintar (y no pisa lo que escribe)', () => {
  const c = contexto();
  c.lleno(); c.ctx.renderMydayCheckin();
  const campo = c.$('ckPeso');
  c.ctx.STATE.salud = [{ fecha: '2026-11-12', tipo: 'peso_kg', valor: 69.9, fuente: 'manual' }];
  c.ctx._ckPintarPesoHoy();
  igual(campo.value, '69,9', 'campo sin tocar');
  c.escribir('ckPeso', '70');
  c.ctx._ckPintarPesoHoy();
  igual(campo.value, '70', 'lo que escribe');
});

console.log('Peso corporal · un repintado no borra lo que escribe');
t('lo escrito sin guardar sobrevive al repintado y conserva el foco', () => {
  const c = contexto();
  c.ctx.STATE.scene = 'cuerpo';
  c.ctx.renderMydayPeso();
  c.escribir('pesoInput', '69,9');
  c.ctx.renderMydayPeso();   // p. ej. llega loadSalud o el «pump» del día
  igual(c.$('pesoInput').value, '69,9', 'campo');
  igual(c.doc.activeElement && c.doc.activeElement.id, 'pesoInput', 'foco');
});
t('si se fue sin guardar, la tarjeta vuelve al peso guardado (no queda un borrador suelto)', () => {
  const c = contexto();
  c.ctx.STATE.salud = [{ fecha: '2026-11-12', tipo: 'peso_kg', valor: 70.2, fuente: 'manual' }];
  c.ctx.renderMydayPeso();
  c.escribir('pesoInput', '7');
  c.doc.activeElement = null;   // se fue a otra parte
  c.ctx.renderMydayPeso();
  igual(c.$('pesoInput').value, '70,2', 'campo');
});
t('un peso de hoy con dos decimales que viene puesto no se reenvía redondeado', () => {
  const c = contexto();
  c.ctx.STATE.salud = [{ fecha: '2026-11-12', tipo: 'peso_kg', valor: 69.85, fuente: 'manual' }];
  c.lleno(); c.ctx.renderMydayCheckin();
  c.enviar();
  igual(c.cola.filter(o => o.kind === 'peso').length, 0, 'pesos en la cola');
});
t('al guardar, el borrador se limpia y queda el valor guardado', () => {
  const c = contexto();
  c.ctx.renderMydayPeso();
  c.escribir('pesoInput', '69,900');
  c.$('pesoSave').fire('click');
  igual(c.cola.map(o => o.payload), [{ fecha: '2026-11-12', valor: 69.9 }], 'cola');
  igual(c.ctx.STATE.pesoBorrador, null, 'borrador');
  igual(c.$('pesoInput').value, '69,9', 'campo');
});

console.log(`\n${ok} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
