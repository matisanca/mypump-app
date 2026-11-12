/* =============================================================
   devolucion.js — «Devolución de Mati» en Revisión (web = app 2.3.0).

   Solo lee `mypump_devolucion_get` con el token: lo publicado, lo suyo. Detrás de la palanca
   `devolucion_semanal`: apagada, no se llama a nada y no se muestra nada. Sin red queda lo último
   que se supo (localStorage, por cuenta). Mismas reglas que DevolucionSemanal.swift / .kt
   (casos compartidos en apps/shared/fixtures/devolucion/casos.json).
   ============================================================= */
(function (raiz) {
  'use strict';

  const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  const MAXIMO = 12;
  const FLAG = 'mypump-palanca-devolucion-semanal';

  /* [año, mes, día] de un AAAA-MM-DD que existe; null si no. */
  function fecha(s) {
    if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
    const [a, m, d] = s.split('-').map(Number);
    const f = new Date(Date.UTC(a, m - 1, d));
    if (f.getUTCFullYear() !== a || f.getUTCMonth() !== m - 1 || f.getUTCDate() !== d) return null;
    return [a, m, d];
  }

  function hoyLocal() {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  function devolucion(j) {
    if (!j || typeof j !== 'object' || Array.isArray(j)) return null;
    const id = typeof j.id === 'string' && j.id ? j.id : null;
    const semana = fecha(j.semana_lunes) ? j.semana_lunes : null;
    if (!id || !semana || typeof j.texto !== 'string') return null;
    const lineas = j.texto.split(/\r\n|\n|\r/).map(l => l.trim()).filter(Boolean);
    if (!lineas.length) return null;
    const p = typeof j.publicado_en === 'string' ? j.publicado_en.slice(0, 10) : null;
    return { id, semanaLunes: semana, lineas, publicadaDia: fecha(p) ? p : null };
  }

  /* null: apagada, token caído o sin habilitar. Si no, la lista de la más nueva a la más vieja, una por semana. */
  function decodificar(j) {
    if (!j || typeof j !== 'object' || j.habilitado !== true) return null;
    const validas = (Array.isArray(j.devoluciones) ? j.devoluciones : []).map(devolucion).filter(Boolean);
    const orden = validas.map((d, i) => [d, i]).sort((x, y) => x[0].semanaLunes === y[0].semanaLunes ? x[1] - y[1] : (x[0].semanaLunes < y[0].semanaLunes ? 1 : -1));
    const vistas = new Set();
    const lista = [];
    for (const [d] of orden) if (!vistas.has(d.semanaLunes)) { vistas.add(d.semanaLunes); lista.push(d); }
    const l = lista.slice(0, MAXIMO);
    return { devoluciones: l, ultima: l[0] || null, anteriores: l.slice(1) };
  }

  /* «Semana del 9 de noviembre»; con el año si no es el de hoy. */
  function etiqueta(semana, hoy = hoyLocal()) {
    const f = fecha(semana);
    if (!f) return 'Tu semana';
    const h = fecha(hoy);
    return `Semana del ${f[2]} de ${MESES[f[1] - 1]}` + (h && h[0] !== f[0] ? ` de ${f[0]}` : '');
  }

  /* Recién llegada: publicada hoy o en los dos días anteriores. */
  function esNueva(d, hoy = hoyLocal()) {
    const p = d && fecha(d.publicadaDia);
    const h = fecha(hoy);
    if (!p || !h) return false;
    const dias = Math.round((Date.UTC(h[0], h[1] - 1, h[2]) - Date.UTC(p[0], p[1] - 1, p[2])) / 86400000);
    return dias >= 0 && dias <= 2;
  }

  function esc(s) {
    return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  /* La tarjeta y el historial. Sin devolución publicada, nada. */
  function html(estado, hoy = hoyLocal()) {
    if (!estado || !estado.ultima) return '';
    const u = estado.ultima;
    const lineas = (l) => l.map(x => `<p>${esc(x)}</p>`).join('');
    const nueva = esNueva(u, hoy) ? '<span class="dv-nueva" data-testid="devolucion-nueva">Nueva</span>' : '';
    const anteriores = estado.anteriores.length ? `
      <div class="dv-historial" data-testid="devolucion-historial">
        <h3 class="dv-hist-tit">Semanas anteriores</h3>
        ${estado.anteriores.map(d => `
          <details class="dv-anterior" data-testid="devolucion-anterior-${esc(d.id)}">
            <summary><span class="dv-ant-sem">${esc(etiqueta(d.semanaLunes, hoy))}</span><span class="dv-ant-prev">${esc(d.lineas[0])}</span></summary>
            <div class="dv-ant-texto">${lineas(d.lineas)}</div>
          </details>`).join('')}
      </div>` : '';
    return `
      <section class="dv-seccion" aria-labelledby="dv-titulo" data-testid="devolucion-seccion">
        <article class="dv-tarjeta" data-testid="devolucion-tarjeta">
          <header class="dv-cabeza">
            <span class="dv-firma" aria-hidden="true">M</span>
            <div class="dv-titulos"><h2 id="dv-titulo">Devolución de Mati</h2><p>${esc(etiqueta(u.semanaLunes, hoy))}</p></div>
            ${nueva}
          </header>
          <div class="dv-texto" data-testid="devolucion-texto">${lineas(u.lineas)}</div>
        </article>
        ${anteriores}
      </section>`;
  }

  /* ── El modelo: palanca, lectura y copia por cuenta ── */
  const ui = { op: null, estado: null, prendida: false };
  const clave = () => `mypump_devolucion_${ui.op && ui.op.token}`;
  function guardar(j) { try { localStorage.setItem(clave(), JSON.stringify(j)); } catch (_) {} }
  function olvidar() { try { localStorage.removeItem(clave()); } catch (_) {} }
  function guardado() { try { return decodificar(JSON.parse(localStorage.getItem(clave()) || 'null')); } catch (_) { return null; } }

  function configurar(op) { ui.op = op; }

  function apagar() {
    const habia = !!ui.estado;
    ui.estado = null;
    if (ui.op) olvidar();
    if (habia && ui.op && ui.op.alCambiar) ui.op.alCambiar();
  }

  async function refrescar() {
    if (!ui.op || !ui.prendida) return;
    const r = await ui.op.rpc('mypump_devolucion_get', { p_token: ui.op.token });
    if (r.ok) {
      const e = decodificar(r.data);
      if (!e) return apagar();
      ui.estado = e;
      guardar(r.data);
    } else if (r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente') {
      return apagar();
    } else if (!ui.estado) {
      ui.estado = guardado();
    }
    if (ui.op.alCambiar) ui.op.alCambiar();
  }

  /* valor: true/false leído del servidor; null = no se pudo leer (sin red): vale lo último que se supo. */
  async function aplicarPalanca(valor) {
    if (!ui.op) return;
    let prendida;
    try {
      if (valor === null) prendida = localStorage.getItem(FLAG) === '1';
      else {
        prendida = valor === true;
        if (prendida) localStorage.setItem(FLAG, '1'); else localStorage.removeItem(FLAG);
      }
    } catch (_) { prendida = valor === true; }
    ui.prendida = prendida;
    if (!prendida) return apagar();
    await refrescar();
  }

  const api = {
    decodificar, etiqueta, esNueva, html, fecha, MAXIMO,
    configurar, aplicarPalanca, refrescar,
    get estado() { return ui.estado; },
    get prendida() { return ui.prendida; },
    _reiniciar() { ui.op = null; ui.estado = null; ui.prendida = false; },
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else raiz.Devolucion = api;
})(typeof window !== 'undefined' ? window : globalThis);
