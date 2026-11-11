/* =============================================================
   wins.js — «Récords y logros» (web = app 2.3.0), detrás de la palanca `wins_app`.

   · La regla pura (qué es un récord del día) y los textos: los mismos vectores que las
     apps (apps/shared/vectores/wins.json, copia en scripts/fixtures/wins.json), que corre
     scripts/test-wins.mjs.
   · El estado: si la función está prendida y si el alumno dio su permiso
     (`mypump_wins_estado`, `mypump_wins_permiso`). Lo último que se supo queda en este
     navegador, por cuenta, para decidir sin red.
   · La cola local: cada logro se guarda acá con su id y se vacía con
     `mypump_wins_registrar`. Solo se encola con el permiso dado. La web NUNCA publica ni
     manda mensajes: deja filas `pendiente` que después aprueba Mati.
   · El festejo y la hoja de permiso (lo único que toca la pantalla).

   Con la palanca apagada no se llama a nada y no se muestra nada. Si la función del
   servidor no existe (PGRST202), tampoco.
   ============================================================= */
(function (raiz) {
  'use strict';

  const TOL = 1e-6;
  const TOPE = 12;            // récords en un festejo
  const TOPE_COLA = 50;       // lo más viejo se descarta
  const INTENTOS_MAX = 3;     // un rechazo que no es de red ni de datos: se prueba tres veces y se descarta
  const PERMISO_VERSION = 1;
  const HITOS = [7, 14, 21, 30, 60, 90, 120, 180, 365];
  const PLATAFORMA = 'web';
  const FLAG = 'mypump-palanca-wins-app';

  const FIJOS = {
    contarle: 'Contarle a Mati',
    seguir: 'Seguir',
    permiso_titulo: '¿Compartir tus logros con Mati?',
    permiso_cuerpo: [
      'Cuando logres un récord o una racha de pasos, Mati lo va a ver y lo puede compartir con el equipo de Pump Team.',
      'Se comparte tu nombre y el logro: el ejercicio y la marca, o los días de tu racha. Nunca tus fotos, tu peso ni otros datos de salud.',
      'Lo podés desactivar cuando quieras en Mis datos. Lo ya compartido no se puede borrar.',
    ],
    permiso_si: 'Sí, compartir',
    permiso_no: 'Ahora no',
    ajuste_seccion: 'Logros',
    ajuste_interruptor: 'Compartir mis logros con Mati',
    ajuste_pie: 'Mati ve tus récords y tus rachas de pasos, y los puede compartir con el equipo de Pump Team. Nunca tus fotos, tu peso ni otros datos de salud.',
    desactivado: 'Listo, no se comparte nada más.',
    sin_red: 'No se pudo guardar. Probá de nuevo cuando tengas conexión.',
    demo: 'En la demo no se envía nada.',
    racha_con_permiso: 'Mati se va a enterar de esta racha.',
  };

  // ───────────────────────── La regla ─────────────────────────
  // Como el número de JS pasado a texto, con coma: 60 → "60", 62.5 → "62,5".
  const kilos = (x) => String(x).replace('.', ',');
  const sirve = (m) => !!m && typeof m.kg === 'number' && Number.isFinite(m.kg) && m.kg > 0 && Number.isInteger(m.reps) && m.reps >= 1;
  function mejor(marcas) {
    const kg = Math.max(...marcas.map((m) => m.kg));
    const reps = Math.max(...marcas.filter((m) => Math.abs(m.kg - kg) < TOL).map((m) => m.reps));
    return { kg, reps };
  }

  /** ejercicios: [{clave, nombre, anteriores:[{kg,reps}], hoy:[{kg,reps}], sin_kg?, suficiente?}], en el orden del día.
      A lo sumo un récord por ejercicio y como mucho 12. */
  function records(ejercicios) {
    const salida = [];
    for (const e of Array.isArray(ejercicios) ? ejercicios : []) {
      if (!e || e.sin_kg || e.suficiente === false) continue;
      const antes = (e.anteriores || []).filter(sirve);
      const hoy = (e.hoy || []).filter(sirve);
      if (!antes.length || !hoy.length) continue;
      const a = mejor(antes), h = mejor(hoy);
      let tipo, delta, chip;
      if (h.kg > a.kg + TOL) {
        tipo = 'record_kg';
        delta = Math.round((h.kg - a.kg) * 100) / 100;
        chip = `+${kilos(delta)} kg`;
      } else if (Math.abs(h.kg - a.kg) < TOL && h.reps > a.reps) {
        tipo = 'record_reps';
        delta = h.reps - a.reps;
        chip = `+${delta} rep${delta === 1 ? '' : 's'}`;
      } else continue;
      salida.push({
        tipo, clave: e.clave, ejercicio: e.nombre, kg: h.kg, reps: h.reps, antes_kg: a.kg, antes_reps: a.reps, delta,
        marca: `${kilos(h.kg)} kg × ${h.reps}`, chip, antes: `Antes: ${kilos(a.kg)} kg × ${a.reps}`,
      });
      if (salida.length === TOPE) break;
    }
    return salida;
  }

  const titulo = (n) => (n === 1 ? 'Récord nuevo' : `${n} récords hoy`);
  const subtitulo = (n) => (n === 1 ? 'Superaste tu mejor marca.' : `Superaste ${n} de tus mejores marcas.`);
  const conPermiso = (n) => (n === 1 ? 'Mati se va a enterar de este logro.' : 'Mati se va a enterar de estos logros.');
  const esHito = (dias) => HITOS.includes(dias);

  // ───────────────────────── El estado y la cola ─────────────────────────
  const ui = { op: null, prendida: false, activa: false, permiso: null, cola: [], vaciando: null, enviados: new Set() };

  function hash(t) { let h = 5381; for (const c of String(t || '')) h = ((h * 33) ^ c.charCodeAt(0)) >>> 0; return h.toString(36); }
  const clave = () => `mypump-wins-${hash(ui.op && ui.op.token)}`;
  function leerDisco() {
    try {
      const j = JSON.parse(localStorage.getItem(clave()) || 'null');
      if (!j || typeof j !== 'object') return;
      ui.activa = j.activa === true;
      ui.permiso = j.permiso === true ? true : j.permiso === false ? false : null;
      ui.cola = (Array.isArray(j.cola) ? j.cola : []).filter((x) => x && typeof x.id === 'string' && typeof x.tipo === 'string').slice(-TOPE_COLA);
    } catch (_) { /* sin almacenamiento: solo en memoria */ }
  }
  function guardarDisco() {
    try { localStorage.setItem(clave(), JSON.stringify({ activa: ui.activa, permiso: ui.permiso, cola: ui.cola })); } catch (_) { /* queda en memoria */ }
  }
  function avisar() { if (ui.op && ui.op.alCambiar) { try { ui.op.alCambiar(); } catch (_) {} } }

  function uuid() {
    try { if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID(); } catch (_) {}
    const b = new Uint8Array(16);
    try { crypto.getRandomValues(b); } catch (_) { for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256); }
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  /** op: { token, rpc(fn, params) → {ok,data}|{ok:false,status,codigo,clase}, alCambiar() } */
  function configurar(op) {
    ui.op = op; ui.prendida = false; ui.activa = false; ui.permiso = null; ui.cola = []; ui.vaciando = null; ui.enviados = new Set();
    leerDisco();
    // La palanca se recuerda: arranca con lo último que se supo (cerrar la sesión con mala señal festeja igual).
    try { ui.prendida = localStorage.getItem(FLAG) === '1'; } catch (_) { /* sin almacenamiento */ }
    // Otra pestaña de la misma cuenta cambió el permiso o la cola: esta toma lo que quedó en el disco.
    if (!ui.oyente && typeof window !== 'undefined' && window.addEventListener) {
      ui.oyente = true;
      window.addEventListener('storage', (e) => { if (ui.op && e && e.key === clave()) { if (ui.vaciando) tomarRevocado(); else leerDisco(); avisar(); } });
    }
  }

  /** Si otra pestaña sacó el permiso (quedó `false` en el disco), esta lo respeta: sin permiso y sin cola. */
  function tomarRevocado() {
    try {
      const j = JSON.parse(localStorage.getItem(clave()) || 'null');
      if (j && j.permiso === false && ui.permiso === true) { ui.permiso = false; ui.cola = []; ui.enviados.clear(); return true; }
    } catch (_) { /* sin almacenamiento */ }
    return false;
  }
  /** Al terminar de mandar: lo que otra pestaña encoló mientras tanto no se pierde. */
  function sumarDelDisco(sacados) {
    try {
      const j = JSON.parse(localStorage.getItem(clave()) || 'null');
      if (!j || !Array.isArray(j.cola) || ui.permiso !== true) return;
      for (const x of j.cola) {
        if (x && typeof x.id === 'string' && typeof x.tipo === 'string' && !sacados.has(x.id) && !ui.cola.some((y) => y.id === x.id)) ui.cola.push(x);
      }
      ui.cola = ui.cola.slice(-TOPE_COLA);
    } catch (_) { /* sin almacenamiento */ }
  }
  const huella = (x) => `${x.tipo}|${x.clave}|${x.dia}|${JSON.stringify(x.datos)}`;

  const noExiste = (r) => r && !r.ok && (r.status === 404 || r.codigo === 'PGRST202');

  /** Lo que se sabe del servidor. Sin red queda lo último que se supo. */
  async function refrescar() {
    if (!ui.op || !ui.prendida) return;
    const r = await ui.op.rpc('mypump_wins_estado', { p_token: ui.op.token });
    if (r && r.ok && r.data && r.data.ok === true) {
      ui.activa = r.data.activa === true;
      ui.permiso = r.data.permiso === true;
      if (!ui.permiso) { ui.cola = []; ui.enviados.clear(); }
      guardarDisco();
    } else if (noExiste(r)) {
      // La función no está: nada de esto existe todavía. Cualquier otro error deja todo como estaba.
      ui.activa = false; ui.permiso = false; ui.cola = []; ui.enviados.clear();
      guardarDisco();
    }
    avisar();
    if (ui.activa && ui.permiso === true) await vaciar();
  }

  /** valor: true/false leído de mypump_get_app_config; null = no se pudo leer: vale lo último que se supo. */
  async function aplicarPalanca(valor) {
    if (!ui.op) return;
    let prendida;
    try {
      if (valor === null || valor === undefined) prendida = localStorage.getItem(FLAG) === '1';
      else {
        prendida = valor === true;
        if (prendida) localStorage.setItem(FLAG, '1'); else localStorage.removeItem(FLAG);
      }
    } catch (_) { prendida = valor === true; }
    ui.prendida = prendida;
    if (!prendida) { avisar(); return; }
    await refrescar();
  }

  const puedeFestejar = () => !!(ui.op && ui.prendida && ui.activa);
  // Con la palanca apagada y el permiso dado, el interruptor se sigue viendo: para poder apagarlo.
  const ajusteVisible = () => !!ui.op && (puedeFestejar() || ui.permiso === true);

  async function darPermiso() {
    if (!ui.op || !puedeFestejar()) return false;
    const r = await ui.op.rpc('mypump_wins_permiso', { p_token: ui.op.token, p_otorga: true, p_version: PERMISO_VERSION, p_plataforma: PLATAFORMA });
    if (!(r && r.ok && r.data && r.data.ok === true && r.data.permiso === true)) return false;
    ui.permiso = true;
    guardarDisco(); avisar();
    return true;
  }

  /** Sacar el permiso anda siempre (también con la palanca apagada) y vacía la cola local. */
  async function revocar() {
    if (!ui.op) return false;
    const r = await ui.op.rpc('mypump_wins_permiso', { p_token: ui.op.token, p_otorga: false });
    if (!(r && r.ok && r.data && r.data.ok === true)) return false;
    ui.permiso = false; ui.cola = []; ui.enviados.clear();
    guardarDisco(); avisar();
    return true;
  }

  /** Solo con el último permiso conocido en true. Devuelve si quedó en la cola. */
  function encolar(logro) {
    if (!ui.op || !puedeFestejar() || ui.permiso !== true || !logro) return false;
    const { tipo, dia, datos } = logro;
    const k = typeof logro.clave === 'string' ? logro.clave : '';
    if (!['record_kg', 'record_reps', 'racha_pasos'].includes(tipo) || !k || !/^\d{4}-\d{2}-\d{2}$/.test(String(dia)) || !datos || typeof datos !== 'object') return false;
    const esRacha = tipo === 'racha_pasos';
    // El mismo ejercicio el mismo día: queda la marca nueva (el servidor guarda uno por día).
    const i = ui.cola.findIndex((x) => x.clave === k && x.dia === dia && (x.tipo === 'racha_pasos') === esRacha);
    // El mismo id solo si es exactamente el mismo logro (un reintento); una marca nueva lleva id nuevo, porque el
    // servidor contesta «ya» por id y se quedaría con la vieja.
    // Lo mismo que ya está en la cola o que ya salió en esta sesión no se encola otra vez.
    const igual = i >= 0 && ui.cola[i].tipo === tipo && JSON.stringify(ui.cola[i].datos) === JSON.stringify(datos);
    if (igual || ui.enviados.has(huella({ tipo, clave: k, dia, datos }))) { vaciar().catch(() => {}); return true; }
    const item = { id: uuid(), tipo, clave: k, dia, datos, intentos: 0 };
    if (i >= 0) ui.cola[i] = item; else ui.cola.push(item);
    if (ui.cola.length > TOPE_COLA) ui.cola = ui.cola.slice(-TOPE_COLA);
    guardarDisco();
    vaciar().catch(() => {});
    return true;
  }

  function encolarRecords(lista, dia) {
    let n = 0;
    for (const r of lista || []) {
      if (encolar({ tipo: r.tipo, clave: r.clave, dia, datos: { ejercicio: r.ejercicio, kg: r.kg, reps: r.reps, antes_kg: r.antes_kg, antes_reps: r.antes_reps } })) n++;
    }
    return n;
  }

  /** La racha de pasos del «Pump del día»: solo en un hito y con permiso. */
  function encolarRacha(dias, meta, dia) {
    if (!esHito(dias)) return false;
    return encolar({ tipo: 'racha_pasos', clave: 'pasos', dia, datos: { dias, meta } });
  }

  /** Manda lo pendiente, de a uno y en orden. Un corte de red deja el resto para después. */
  function vaciar() {
    if (ui.vaciando) return ui.vaciando;
    if (!ui.op || !ui.prendida || !ui.cola.length) return Promise.resolve();
    const op = ui.op;
    const sacados = new Set();
    ui.vaciando = (async () => {
      while (ui.op === op && ui.cola.length) {
        if (tomarRevocado()) { avisar(); break; }
        const x = ui.cola[0];
        const r = await op.rpc('mypump_wins_registrar', { p_token: op.token, p_id: x.id, p_tipo: x.tipo, p_clave: x.clave, p_dia: x.dia, p_datos: x.datos });
        if (ui.op !== op) return;
        if (tomarRevocado()) { avisar(); break; }
        const sacar = () => { sacados.add(x.id); ui.cola = ui.cola.filter((y) => y.id !== x.id); };
        const unIntento = () => { const y = ui.cola.find((z) => z.id === x.id); if (y) { y.intentos = (y.intentos || 0) + 1; if (y.intentos >= INTENTOS_MAX) sacar(); } };
        if (r && r.ok) {
          const d = r.data;
          if (d && d.ok === true) {
            sacar();
            if (d.motivo === 'sin_permiso') {
              // El servidor dice que no hay permiso: se recuerda y no queda nada pendiente.
              for (const y of ui.cola) sacados.add(y.id);
              ui.permiso = false; ui.cola = []; ui.enviados.clear(); avisar();
              break;
            }
            if (d.guardado !== false) ui.enviados.add(huella(x));
          } else if (d && d.ok === false && d.motivo === 'datos') {
            sacar();
          } else {
            unIntento();   // token caído o una respuesta que no se entiende: se reintenta, hasta el tercero
            break;
          }
        } else if (noExiste(r)) {
          for (const y of ui.cola) sacados.add(y.id);
          ui.cola = []; ui.activa = false; ui.permiso = false; ui.enviados.clear(); avisar();
          break;
        } else if (r && r.clase === 'permanente') {
          unIntento();
          break;
        } else {
          break;     // sin red o el servidor caído: después, sin contar intentos
        }
        sumarDelDisco(sacados); guardarDisco();
      }
      if (ui.op === op) { sumarDelDisco(sacados); guardarDisco(); }
    })().finally(() => { ui.vaciando = null; });
    return ui.vaciando;
  }

  // ───────────────────────── La pantalla ─────────────────────────
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  const TROFEO = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path fill="currentColor" d="M7 3h10v2h3v3a4 4 0 0 1-4 4h-.3A5 5 0 0 1 13 14.9V17h3v3H8v-3h3v-2.1A5 5 0 0 1 8.3 12H8a4 4 0 0 1-4-4V5h3V3Zm0 4H6v1a2 2 0 0 0 1 1.7V7Zm10 2.7A2 2 0 0 0 18 8V7h-1v2.7Z"/></svg>';

  /** modo: 'sin_permiso' (botón «Contarle a Mati»), 'con_permiso' (la línea) o 'demo_avisado' (la línea de la demo). */
  function htmlPie(n, modo) {
    if (modo === 'con_permiso') return `<p class="wn-linea" role="status" data-test="wins-con-permiso">${esc(conPermiso(n))}</p>`;
    if (modo === 'demo_avisado') return `<p class="wn-linea" role="status" data-test="wins-demo">${esc(FIJOS.demo)}</p>`;
    return `<button type="button" class="wn-boton wn-sec" data-wn="contarle" data-test="wins-contarle">${esc(FIJOS.contarle)}</button>`;
  }
  function htmlFestejo(lista, modo) {
    const n = lista.length;
    const filas = lista.map((r) => `
      <li class="wn-fila" data-test="wins-fila">
        <div class="wn-fila-txt"><span class="wn-ej">${esc(r.ejercicio)}</span><span class="wn-antes">${esc(r.antes)}</span></div>
        <div class="wn-fila-num"><span class="wn-marca">${esc(r.marca)}</span><span class="wn-chip">${esc(r.chip)}</span></div>
      </li>`).join('');
    return `<div class="wn-fondo" data-wn="fondo"></div>
      <div class="wn-caja" role="dialog" aria-modal="true" aria-labelledby="wnTit" aria-describedby="wnSub" data-test="wins-festejo">
        <div class="wn-cuerpo">
          <div class="wn-trofeo" aria-hidden="true"><span class="wn-halo"></span>${TROFEO}</div>
          <h2 class="wn-tit" id="wnTit">${esc(titulo(n))}</h2>
          <p class="wn-sub" id="wnSub">${esc(subtitulo(n))}</p>
          <ul class="wn-lista">${filas}</ul>
        </div>
        <div class="wn-pie"><div class="wn-pie-estado">${htmlPie(n, modo)}</div>
          <button type="button" class="wn-boton wn-pri" data-wn="seguir" data-test="wins-seguir">${esc(FIJOS.seguir)}</button></div>
      </div>`;
  }
  function htmlPermiso() {
    return `<div class="wn-fondo" data-wn="no"></div>
      <div class="wn-caja wn-hoja" role="dialog" aria-modal="true" aria-labelledby="wnPerTit" data-test="wins-permiso">
        <div class="wn-cuerpo">
          <h2 class="wn-tit wn-tit-hoja" id="wnPerTit">${esc(FIJOS.permiso_titulo)}</h2>
          ${FIJOS.permiso_cuerpo.map((p) => `<p class="wn-parrafo">${esc(p)}</p>`).join('')}
          <p class="wn-error" role="alert" data-test="wins-sin-red" hidden></p>
        </div>
        <div class="wn-pie">
          <button type="button" class="wn-boton wn-pri" data-wn="si" data-test="wins-permiso-si">${esc(FIJOS.permiso_si)}</button>
          <button type="button" class="wn-boton wn-sec" data-wn="no" data-test="wins-permiso-no">${esc(FIJOS.permiso_no)}</button>
        </div>
      </div>`;
  }

  const reducir = () => { try { return !!(raiz.matchMedia && raiz.matchMedia('(prefers-reduced-motion: reduce)').matches); } catch (_) { return false; } };
  function capa(clase, html) {
    const el = document.createElement('div');
    el.className = `wn-capa ${clase}${reducir() ? ' is-quieta' : ''}`;
    el.innerHTML = html;
    document.body.appendChild(el);
    return el;
  }
  /** El foco no sale de la hoja: Tab da la vuelta adentro. */
  function atrapar(el, ev) {
    if (ev.key !== 'Tab') return;
    const f = [...el.querySelectorAll('button:not([disabled]), [href], input:not([disabled]), [tabindex]:not([tabindex="-1"])')].filter((x) => x.offsetParent !== null || x === document.activeElement);
    if (!f.length) { ev.preventDefault(); return; }
    const i = f.indexOf(document.activeElement);
    if (ev.shiftKey && i <= 0) { ev.preventDefault(); f[f.length - 1].focus(); }
    else if (!ev.shiftKey && (i < 0 || i === f.length - 1)) { ev.preventDefault(); f[0].focus(); }
  }
  function vibrar() {
    try {
      // Sin un toque previo, el navegador la bloquea. En iPhone la web no vibra.
      if (navigator.vibrate && (!navigator.userActivation || navigator.userActivation.hasBeenActive)) navigator.vibrate(reducir() ? 20 : [10, 60, 10, 60, 30]);
    } catch (_) {}
  }

  /** La hoja de permiso. `alDar` corre cuando el servidor lo confirmó. */
  function abrirPermiso(opciones) {
    if (typeof document === 'undefined' || document.querySelector('.wn-capa.wn-permiso')) return;
    const o = opciones || {};
    const previo = document.activeElement;
    const el = capa('wn-permiso', htmlPermiso());
    const cerrar = () => {
      document.removeEventListener('keydown', tecla);
      el.remove();
      try { if (previo && previo.isConnected) previo.focus({ preventScroll: true }); } catch (_) {}
      if (o.alCerrar) o.alCerrar();
    };
    const tecla = (ev) => { if (ev.key === 'Escape' && !ocupado) cerrar(); else atrapar(el, ev); };
    let ocupado = false;
    el.addEventListener('click', async (ev) => {
      const b = ev.target.closest('[data-wn]');
      if (!b || ocupado) return;
      if (b.dataset.wn === 'no') return cerrar();
      if (b.dataset.wn !== 'si') return;
      ocupado = true;
      const err = el.querySelector('.wn-error');
      err.hidden = true;
      el.querySelectorAll('button').forEach((x) => { x.disabled = true; });
      let ok = false;
      try { ok = await darPermiso(); } catch (_) { ok = false; }
      ocupado = false;
      if (ok) { cerrar(); if (o.alDar) o.alDar(); return; }
      el.querySelectorAll('button').forEach((x) => { x.disabled = false; });
      err.textContent = FIJOS.sin_red;
      err.hidden = false;
    });
    document.addEventListener('keydown', tecla);
    const si = el.querySelector('[data-wn="si"]');
    if (si) si.focus({ preventScroll: true });
  }

  /** El festejo al cerrar la sesión. opciones: { demo, dia }. Con permiso, los récords quedan en la cola. */
  function abrirFestejo(lista, opciones) {
    if (typeof document === 'undefined' || !Array.isArray(lista) || !lista.length || document.querySelector('.wn-capa.wn-festejo')) return false;
    const o = opciones || {};
    if (!o.demo && !puedeFestejar()) return false;
    const n = lista.length;
    let modo = 'sin_permiso';
    if (!o.demo && ui.permiso === true) { encolarRecords(lista, o.dia); modo = 'con_permiso'; }
    const previo = document.activeElement;
    const el = capa('wn-festejo', htmlFestejo(lista, modo));
    const cerrar = () => {
      document.removeEventListener('keydown', tecla);
      el.classList.add('is-saliendo');
      setTimeout(() => el.remove(), reducir() ? 0 : 200);
      try { if (previo && previo.isConnected) previo.focus({ preventScroll: true }); } catch (_) {}
      if (o.alCerrar) o.alCerrar();
    };
    const tecla = (ev) => { if (document.querySelector('.wn-capa.wn-permiso')) return; if (ev.key === 'Escape') cerrar(); else atrapar(el, ev); };
    const pie = (m) => { const p = el.querySelector('.wn-pie-estado'); if (p) p.innerHTML = htmlPie(n, m); };
    el.addEventListener('click', (ev) => {
      const b = ev.target.closest('[data-wn]');
      if (!b) return;
      if (b.dataset.wn === 'seguir' || b.dataset.wn === 'fondo') return cerrar();
      if (b.dataset.wn !== 'contarle') return;
      if (o.demo) return pie('demo_avisado');
      abrirPermiso({ alDar: () => { encolarRecords(lista, o.dia); pie('con_permiso'); } });
    });
    document.addEventListener('keydown', tecla);
    vibrar();
    const seguir = el.querySelector('[data-wn="seguir"]');
    // El foco entra al diálogo en el momento (no después de la animación) y vuelve a donde estaba al cerrar.
    if (seguir) seguir.focus({ preventScroll: true });
    return true;
  }

  const api = {
    TOPE, TOPE_COLA, HITOS, PERMISO_VERSION, PLATAFORMA, FIJOS,
    records, titulo, subtitulo, conPermiso, esHito, kilos,
    cuenta: (t) => hash(t),
    configurar, aplicarPalanca, refrescar, darPermiso, revocar, encolar, encolarRecords, encolarRacha, vaciar,
    puedeFestejar, ajusteVisible,
    htmlFestejo, htmlPermiso, abrirFestejo, abrirPermiso,
    get permiso() { return ui.permiso; },
    get activa() { return ui.activa; },
    get prendida() { return ui.prendida; },
    get cola() { return ui.cola.map((x) => ({ ...x })); },
    _reiniciar() { ui.op = null; ui.prendida = false; ui.activa = false; ui.permiso = null; ui.cola = []; ui.vaciando = null; },
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else raiz.Wins = api;
})(typeof window !== 'undefined' ? window : globalThis);
