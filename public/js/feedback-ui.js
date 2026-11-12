/* =============================================================
   feedback-ui.js — «Feedback del alumno» (2.3.0) en la web: el modelo y las pantallas.

   Gemelo de ModeloFeedback.swift, MeDueleView.swift y SeccionYaLoTenes de la app.
   Una sola lectura (mypump_feedback_get) y dos escrituras directas, sin cola: son
   avisos que el alumno manda mirando la pantalla y, si no salen, se le dice ahí.
   Con las palancas `me_duele` y `suple_estado` apagadas, sin el servidor nuevo o
   sin cuenta no se llama a nada ni se muestra nada. Todo texto sale de Feedback.T.
   «Me duele» no escribe comentarios.
   ============================================================= */
(function (raiz) {
  'use strict';

  const F = raiz.Feedback;
  const T = F.T;
  const FLAG = 'mypump_palanca_feedback';
  const CACHE = 'mypump_feedback_v1';
  const SEG_ENTRE_REFRESCOS = 60;

  const ui = {
    op: null,              // { token, rpc, version, alCambiar, ejercicio(id) }
    prendida: false,
    estado: null,          // null: apagado, sin el servidor nuevo, o sin red y sin nada guardado
    marcando: new Set(),   // las marcas que todavía viajan
    escrituras: 0,
    refrescando: null,
    ultimoRefresco: 0,
    enganchado: false,
    hoja: null,
    falloSuple: false,
  };

  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const svg = (d, lado) => `<svg viewBox="0 0 24 24" width="${lado || 20}" height="${lado || 20}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const IC = {
    venda: svg('<rect x="2.5" y="8.5" width="19" height="7" rx="3.5" transform="rotate(-45 12 12)"/><path d="M9.2 9.2l5.6 5.6M11 13h.01M13 11h.01"/>'),
    tilde: svg('<circle cx="12" cy="12" r="9"/><path d="m8 12.5 3 3 5-6"/>'),
    alerta: svg('<path d="M12 3 2.5 20h19L12 3z"/><path d="M12 10v4M12 17h.01"/>', 16),
    bolsa: svg('<path d="M5 8h14l-1 12H6L5 8z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>', 16),
    lupa: svg('<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>', 16),
    pausa: svg('<circle cx="12" cy="12" r="9"/><path d="M10 9v6M14 9v6"/>', 16),
    circulo: svg('<circle cx="12" cy="12" r="8"/>', 16),
    elegir: svg('<path d="m8 9 4-4 4 4M8 15l4 4 4-4"/>', 12),
  };

  // ───────────────────────── El modelo ─────────────────────────
  function avisar() {
    if (ui.op && ui.op.alCambiar) { try { ui.op.alCambiar(); } catch (_) {} }
  }
  function leerCache() {
    try {
      const c = JSON.parse(localStorage.getItem(CACHE) || 'null');
      return (c && ui.op && c.token === ui.op.token) ? F.decodificarEstado(c.resp) : null;
    } catch (_) { return null; }
  }
  function guardarCache(resp) { try { localStorage.setItem(CACHE, JSON.stringify({ token: ui.op.token, resp })); } catch (_) {} }
  function borrarCache() { try { localStorage.removeItem(CACHE); } catch (_) {} }

  function apagar() {
    const habia = !!ui.estado;
    ui.estado = null;
    ui.marcando = new Set();
    ui.falloSuple = false;
    if (ui.hoja && !ui.hoja.enviada) cerrarHoja();
    if (habia) avisar();
  }

  async function refrescar() {
    if (!ui.op || !ui.prendida) return;
    if (ui.refrescando) return ui.refrescando;
    const escriturasAntes = ui.escrituras;
    ui.refrescando = (async () => {
      const r = await ui.op.rpc('mypump_feedback_get', { p_token: ui.op.token });
      ui.ultimoRefresco = Date.now();
      if (!ui.prendida) return;
      // Una escritura que salió o volvió mientras se leía sabe más que esta lectura.
      if (ui.escrituras !== escriturasAntes || ui.marcando.size) return;
      if (r && r.ok) {
        if (r.data === null || r.data === undefined) { ui.estado = null; avisar(); return; }   // token caído
        const est = F.decodificarEstado(r.data);
        if (!est) { borrarCache(); apagar(); return; }
        ui.estado = est;
        guardarCache(r.data);
        avisar();
      } else if (r && (r.status === 404 || r.codigo === 'PGRST202' || r.clase === 'permanente')) {
        borrarCache();
        apagar();
      } else if (!ui.estado) {
        // Sin red, lo último que se supo: se ve qué se avisó y qué se marcó. Avisar algo nuevo va a decir que no hay señal.
        const c = leerCache();
        if (c) { ui.estado = c; avisar(); }
      }
    })().catch(() => {}).finally(() => { ui.refrescando = null; });
    return ui.refrescando;
  }

  /* `valor`: true o false = lo que dijo mypump_get_app_config (alguna de las dos palancas); null = no se pudo preguntar. */
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
    if (!prendida) { apagar(); return; }
    enganchar();
    await refrescar();
  }

  function enganchar() {
    if (ui.enganchado) return;
    ui.enganchado = true;
    document.addEventListener('visibilitychange', () => {
      if (document.hidden || !ui.prendida || ui.hoja) return;
      if (Date.now() - ui.ultimoRefresco > SEG_ENTRE_REFRESCOS * 1000) refrescar();
    });
  }

  function uuid() {
    const c = raiz.crypto;
    if (c && c.randomUUID) return c.randomUUID();
    const b = new Uint8Array(16);
    if (c && c.getRandomValues) c.getRandomValues(b); else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  /* Avisa una molestia. Devuelve 'ok', 'sinSenal', 'tope' o 'error'. */
  async function avisarMolestia(id, ej, borrador) {
    const p = F.parametrosMolestia(ui.op.token, id, ej.id, F.nombreParaAvisar(ej.nombre, ej.original), ej.diaId, borrador, ui.op.version);
    if (!p) return 'error';
    ui.escrituras++;
    let r;
    try { r = await ui.op.rpc('mypump_molestia_registrar', p); } catch (_) { r = { ok: false, clase: 'red' }; }
    ui.escrituras++;
    if (r && r.ok) {
      const j = r.data;
      if (j && typeof j === 'object' && j.ok === true) {
        const m = F.decodificarMolestia(j.molestia);
        if (m) {
          const est = ui.estado || F.decodificarEstado({});
          est.molestias = [m].concat(est.molestias.filter((x) => x.id !== m.id));
          ui.estado = est;
          avisar();
        }
        return 'ok';
      }
      return (j && j.error === 'tope') ? 'tope' : 'error';
    }
    return (r && (r.clase === 'red' || r.clase === 'transitorio')) ? 'sinSenal' : 'error';
  }

  /* Marca un suplemento. Se ve enseguida; si el servidor no lo toma, vuelve a como estaba y devuelve false. */
  async function marcar(nombre, nuevo) {
    const k = F.clave(nombre);
    if (!k || !ui.estado || ui.marcando.has(k) || !F.estadoSuple(nuevo)) return false;
    const antes = ui.estado.marcas[k];
    if (antes === nuevo) return true;
    ui.estado.marcas[k] = nuevo;
    ui.marcando.add(k);
    ui.escrituras++;
    ui.falloSuple = false;
    avisar();
    let r;
    try { r = await ui.op.rpc('mypump_suple_marcar', { p_token: ui.op.token, p_item: nombre, p_estado: nuevo, p_nota: null }); } catch (_) { r = null; }
    ui.escrituras++;
    ui.marcando.delete(k);
    const bien = !!(r && r.ok && r.data && typeof r.data === 'object' && r.data.ok === true);
    if (!bien && ui.estado) {   // puede haberse apagado mientras viajaba
      if (antes === undefined) delete ui.estado.marcas[k]; else ui.estado.marcas[k] = antes;
      ui.falloSuple = true;
    }
    avisar();
    return bien;
  }

  const dueleHabilitado = () => !!(ui.estado && ui.estado.dueleHabilitado);
  const supleHabilitado = () => !!(ui.estado && ui.estado.supleHabilitado);
  const molestia = (ejercicioId) => F.molestiaDe(ui.estado, ejercicioId);

  // ───────────────────────── En el ejercicio ─────────────────────────
  const sinDuele = (ex) => !ex || ex.tipo === 'calentamiento' || ex.tipo === 'cardio';

  /* El botón «Me duele» de la fila de acciones. Con una molestia ya avisada se corrige desde su tarjeta. */
  function botonHtml(ex) {
    if (!dueleHabilitado() || sinDuele(ex)) return '';
    const m = molestia(ex.id);
    if (m && m.abierta) return '';
    return `<button type="button" class="ex-swap-btn fb-duele-btn" data-duele-ex="${e(ex.id)}">${IC.venda}<span>${e(T.dueleBoton)}</span></button>`;
  }

  /* Lo que «Me duele» deja a la vista en el ejercicio: la molestia avisada (o ya revisada) y «Cambiar». Sin molestia, nada. */
  function estadoHtml(ex) {
    if (!dueleHabilitado() || !ex) return '';
    const m = molestia(ex.id);
    if (!m) return '';
    const nombre = F.nombreZona(m.zona, m.lado);
    return `<div class="fb-estado ${m.abierta ? 'is-avisada' : 'is-resuelta'}" data-duele-estado="${m.abierta ? 'avisada' : 'resuelta'}">
      <span class="fb-estado-ic">${m.abierta ? IC.venda : IC.tilde}</span>
      <div class="fb-estado-txt"><strong>${e(m.abierta ? T.dueleAvisada : T.dueleResuelta)}</strong>
        <span>${e(m.abierta ? `${nombre}. ${T.dueleListo}` : `${nombre}.`)}</span></div>
      ${m.abierta ? `<button type="button" class="fb-estado-btn" data-duele-ex="${e(ex.id)}">${e(T.dueleCambiar)}</button>` : ''}
    </div>`;
  }

  // ───────────────────────── La hoja «Me duele» ─────────────────────────
  function formaSvg(p, clase, crece) {
    const a = p.a, c = crece || 0;
    if (p.forma === 'capsula') return `<line class="${clase} es-linea" x1="${a[0]}" y1="${a[1]}" x2="${a[2]}" y2="${a[3]}" stroke-width="${2 * (a[4] + c)}" stroke-linecap="round"/>`;
    if (p.forma === 'elipse') return `<ellipse class="${clase}" cx="${a[0]}" cy="${a[1]}" rx="${a[2] + c}" ry="${a[3] + c}"/>`;
    return `<rect class="${clase}" x="${a[0] - c}" y="${a[1] - c}" width="${a[2] + 2 * c}" height="${a[3] + 2 * c}" rx="${a[4] + c}"/>`;
  }
  /* La figura, con las piezas compartidas. Cada parte es un botón (teclado y lector de pantalla); el dedo usa un blanco más
     generoso que el dibujo (Feedback.piezaEn). */
  function cuerpoSvg(vista, b) {
    const partes = F.piezas(vista).map((p) => {
      if (!p.zona) return `<g class="fb-pieza es-cabeza" aria-hidden="true">${formaSvg(p, 'fb-forma')}</g>`;
      const si = F.piezaElegida(p, b);
      return `<g class="fb-pieza${si ? ' is-on' : ''}" role="button" tabindex="0" aria-pressed="${si}" aria-label="${e(F.nombreZona(p.zona, p.lado || 'centro'))}" data-pieza="${e(F.idPieza(p))}">${formaSvg(p, 'fb-halo', 3)}${formaSvg(p, 'fb-forma')}</g>`;
    }).join('');
    return `<svg class="fb-cuerpo" viewBox="0 0 ${F.CUERPO.ancho} ${F.CUERPO.alto}" role="group" aria-label="${e(T.dueleDonde)}" data-vista="${vista}">${partes}</svg>`;
  }
  const opciones = (grupo, lista, elegida) => lista.map((o) =>
    `<button type="button" class="fb-op${elegida === o.id ? ' is-on' : ''}" aria-pressed="${elegida === o.id}" data-fb-op="${grupo}" data-valor="${e(o.id)}">${e(o.texto)}</button>`).join('');
  const pregunta = (grupo, titulo, lista, elegida) => `<section class="fb-tarjeta" role="group" aria-labelledby="fbT-${grupo}">
      <h3 class="fb-h" id="fbT-${grupo}">${e(titulo)}</h3><div class="fb-ops" data-fb-grupo="${grupo}">${opciones(grupo, lista, elegida)}</div></section>`;
  /* Barras que crecen: una, dos, tres o cuatro encendidas. */
  const medidor = (n) => `<span class="fb-medidor" aria-hidden="true">${F.NIVELES.map((_, i) => `<i class="${i < n ? 'is-on' : ''}" style="height:${10 + i * 4}px"></i>`).join('')}</span>`;

  function formularioHtml(h) {
    const b = h.borrador;
    return `
    <div class="fb-cuerpo-hoja" id="fbScroll">
      <div class="fb-cab"><h2 class="fb-ej">${e(h.ej.nombre)}</h2><p class="fb-sub">${e(T.dueleIntro)}</p></div>
      <section class="fb-tarjeta" aria-labelledby="fbT-donde">
        <div><h3 class="fb-h" id="fbT-donde">${e(T.dueleDonde)}</h3><p class="fb-sub">${e(T.dueleDondeAyuda)}</p></div>
        <div class="fb-seg" role="group" aria-label="${e(T.dueleDonde)}">
          ${F.VISTAS.map((v) => `<button type="button" class="fb-seg-b${h.vista === v ? ' is-on' : ''}" aria-pressed="${h.vista === v}" data-fb-vista="${v}">${e(v === 'frente' ? T.dueleFrente : T.dueleEspalda)}</button>`).join('')}
        </div>
        <div class="fb-lienzo" id="fbLienzo">${cuerpoSvg(h.vista, b)}</div>
        <div id="fbZona" aria-live="polite"></div>
      </section>
      ${pregunta('desde', T.dueleDesde, F.DESDE, b.desde)}
      ${pregunta('cuando', T.dueleCuando, F.CUANDO, b.cuando)}
      ${pregunta('tipo', T.dueleTipo, F.TIPO, b.tipo)}
      <section class="fb-tarjeta" role="group" aria-labelledby="fbT-cuanto">
        <h3 class="fb-h" id="fbT-cuanto">${e(T.dueleCuanto)}</h3>
        <div class="fb-niveles" data-fb-grupo="intensidad">
          ${F.NIVELES.map((n, i) => `<button type="button" class="fb-nivel${b.intensidad === n.id ? ' is-on' : ''}" aria-pressed="${b.intensidad === n.id}" data-fb-op="intensidad" data-valor="${n.id}">${medidor(i + 1)}<span>${e(n.texto)}</span></button>`).join('')}
        </div>
      </section>
      <section class="fb-tarjeta">
        <textarea class="fb-nota" id="fbNota" rows="2" placeholder="${e(T.dueleNota)}" aria-label="${e(T.dueleNota)}">${e(b.nota)}</textarea>
      </section>
    </div>
    <div class="fb-pie">
      <div class="fb-pie-msg" id="fbMsg" role="status"></div>
      <button type="button" class="fb-enviar" id="fbEnviar"></button>
    </div>`;
  }
  function listoHtml(h) {
    return `<div class="fb-listo" data-duele-recibido>
      <span class="fb-listo-ic">${svg('<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="m7.5 12.5 3 3 6-7" stroke="var(--color-on-brand)" stroke-width="2.4"/>', 72)}</span>
      <h2 class="fb-ej" id="fbListoTit" tabindex="-1">${e(T.dueleListoTitulo)}</h2>
      <div class="fb-listo-txt"><p>${e(T.dueleListo)}</p>${F.esFuerte(h.borrador.intensidad || 0) ? `<p class="es-fuerte" id="fbListoFuerte">${e(T.dueleListoFuerte)}</p>` : ''}</div>
    </div>
    <div class="fb-pie"><button type="button" class="fb-enviar" id="fbListo">${e(T.listo)}</button></div>`;
  }

  /* Pone la hoja al día sin rearmarla: no se pierde ni el foco ni lo escrito. */
  function sincronizar() {
    const h = ui.hoja;
    if (!h || h.enviada) return;
    const b = h.borrador, r = h.el;
    r.querySelectorAll('[data-fb-op]').forEach((x) => {
      const si = String(b[x.dataset.fbOp]) === x.dataset.valor;
      x.classList.toggle('is-on', si);
      x.setAttribute('aria-pressed', String(si));
    });
    r.querySelectorAll('[data-fb-vista]').forEach((x) => {
      const si = x.dataset.fbVista === h.vista;
      x.classList.toggle('is-on', si);
      x.setAttribute('aria-pressed', String(si));
    });
    const dibujo = r.querySelector('.fb-cuerpo');
    if (dibujo && dibujo.dataset.vista !== h.vista) r.querySelector('#fbLienzo').innerHTML = cuerpoSvg(h.vista, b);
    else {
      const ps = F.piezas(h.vista);
      r.querySelectorAll('[data-pieza]').forEach((g) => {
        const p = ps.find((x) => F.idPieza(x) === g.dataset.pieza);
        const si = !!p && F.piezaElegida(p, b);
        g.classList.toggle('is-on', si);
        g.setAttribute('aria-pressed', String(si));
      });
    }
    const zona = r.querySelector('#fbZona');
    const nombre = F.nombreZonaBorrador(b);
    const clave = nombre ? `${nombre}|${b.lado}` : '';
    if (zona.dataset.clave !== clave) {
      const conFoco = zona.contains(document.activeElement) ? document.activeElement.dataset.valor : null;
      zona.dataset.clave = clave;
      zona.innerHTML = !nombre ? '' : `<p class="fb-zona" id="fbZonaNombre">${IC.tilde}<span>${e(nombre)}</span></p>
        ${b.lado !== 'centro' ? `<div class="fb-ops es-centradas" role="group" aria-label="${e(T.dueleLado)}" data-fb-grupo="lado">${opciones('lado', F.LADOS_ELEGIBLES, b.lado)}</div>` : ''}`;
      if (conFoco) { const x = zona.querySelector(`[data-valor="${conFoco}"]`); if (x) x.focus(); }
    }
    const completa = F.completa(b);
    const msg = r.querySelector('#fbMsg');
    msg.className = 'fb-pie-msg' + (h.fallo ? ' es-fallo' : '');
    msg.innerHTML = h.fallo ? `${IC.alerta}<span id="fbFallo">${e(h.fallo)}</span>` : (!completa ? `<span id="fbFalta">${e(T.dueleFalta)}</span>` : '');
    const env = r.querySelector('#fbEnviar');
    env.disabled = !completa || h.enviando;
    env.classList.toggle('is-ocupado', h.enviando);
    env.setAttribute('aria-busy', String(h.enviando));
    env.innerHTML = h.enviando ? `<span class="fb-giro" aria-hidden="true"></span><span class="fb-solo-lector">${e(h.corrige ? T.dueleCorregir : T.dueleEnviar)}</span>` : e(h.corrige ? T.dueleCorregir : T.dueleEnviar);
    r.querySelector('#fbCerrar').disabled = h.enviando;
  }

  function elegirPieza(p) {
    const h = ui.hoja;
    if (!h || h.enviando || !p || !p.zona) return;
    h.borrador = F.tocarPieza(h.borrador, p);
    h.fallo = null;
    sincronizar();
  }

  async function enviar() {
    const h = ui.hoja;
    if (!h || h.enviando || !F.completa(h.borrador)) return;
    h.enviando = true; h.fallo = null;
    sincronizar();
    const r = await avisarMolestia(h.id, h.ej, h.borrador);
    if (ui.hoja !== h) return;
    h.enviando = false;
    if (r === 'ok') {
      h.enviada = true;
      h.el.querySelector('#fbContenido').innerHTML = listoHtml(h);
      h.el.querySelector('#fbCerrar').disabled = false;
      h.el.querySelector('#fbListo').onclick = cerrarHoja;
      const t = h.el.querySelector('#fbListoTit');
      if (t) t.focus();
      return;
    }
    h.fallo = r === 'sinSenal' ? T.dueleSinRed : r === 'tope' ? T.dueleTope : T.dueleError;
    sincronizar();
  }

  function cerrarHoja() {
    const h = ui.hoja;
    if (!h || h.enviando) return;
    ui.hoja = null;
    document.removeEventListener('keydown', h.tecla, true);
    h.el.remove();
    document.documentElement.classList.remove('fb-sin-scroll');
    // El foco vuelve a quien abrió, o a lo que quedó en su lugar (la tarjeta de la molestia).
    const vuelve = document.querySelector(`[data-duele-ex="${(raiz.CSS && CSS.escape) ? CSS.escape(h.ej.id) : h.ej.id}"]`);
    if (vuelve && vuelve.focus) { try { vuelve.focus({ preventScroll: true }); } catch (_) {} }
  }

  /* «Me duele»: dónde (el dibujo), desde cuándo, en qué parte del movimiento, cómo es y cuánto. Un solo envío; si ya había
     una abierta para este ejercicio, la corrige. `ej` = { id, nombre, original, diaId, tipo }. */
  function abrir(ej) {
    if (ui.hoja || !dueleHabilitado() || !ej || !ej.id || sinDuele(ej)) return;
    const h = { ej, borrador: F.borradorVacio(), vista: 'frente', id: uuid(), enviando: false, enviada: false, fallo: null, corrige: false };
    const m = molestia(ej.id);
    if (m && m.abierta) {
      h.borrador = F.borradorDe(m);
      h.vista = F.vistaDe(m.zona);
      h.id = m.id;
      h.corrige = true;
    }
    const el = document.createElement('div');
    el.className = 'fb-fondo';
    el.innerHTML = `<div class="fb-hoja" role="dialog" aria-modal="true" aria-labelledby="fbTitulo" id="fbHoja">
      <header class="fb-barra"><button type="button" class="fb-cerrar" id="fbCerrar">${e(T.cerrar)}</button><h1 id="fbTitulo" tabindex="-1">${e(T.dueleTitulo)}</h1><span class="fb-cerrar" aria-hidden="true" style="visibility:hidden">${e(T.cerrar)}</span></header>
      <div class="fb-contenido" id="fbContenido">${formularioHtml(h)}</div></div>`;
    h.el = el;
    ui.hoja = h;

    el.addEventListener('click', (ev) => {
      if (ev.target === el) return cerrarHoja();
      if (h.enviada) return;
      const t = ev.target;
      const vista = t.closest('[data-fb-vista]');
      if (vista) { h.vista = vista.dataset.fbVista; return sincronizar(); }
      const o = t.closest('[data-fb-op]');
      if (o) {
        if (h.enviando) return;
        const g = o.dataset.fbOp;
        h.borrador = { ...h.borrador, [g]: g === 'intensidad' ? Number(o.dataset.valor) : o.dataset.valor };
        h.fallo = null;
        return sincronizar();
      }
      const dibujo = t.closest('.fb-cuerpo');
      if (dibujo) {
        // El toque: primero la pieza que el dedo tapa de verdad, después la más cercana dentro del margen.
        const ps = F.piezas(h.vista);
        const g = t.closest('[data-pieza]');
        const suya = g ? ps.find((x) => F.idPieza(x) === g.dataset.pieza) : null;
        const caja = dibujo.getBoundingClientRect();
        const x = (ev.clientX - caja.left) * F.CUERPO.ancho / (caja.width || 1), y = (ev.clientY - caja.top) * F.CUERPO.alto / (caja.height || 1);
        const conPunto = caja.width > 0 && (ev.clientX || ev.clientY);
        if (suya && (!conPunto || F.contiene(suya, x, y, 0))) return elegirPieza(suya);
        return elegirPieza((conPunto && F.piezaEn(h.vista, x, y)) || suya);
      }
    });
    el.querySelector('#fbCerrar').onclick = cerrarHoja;
    el.querySelector('#fbEnviar').onclick = enviar;
    const nota = el.querySelector('#fbNota');
    nota.addEventListener('input', () => {
      const corta = F.nota(nota.value);
      if (corta !== nota.value) nota.value = corta;
      h.borrador.nota = corta;
    });
    h.tecla = (ev) => {
      if (ui.hoja !== h) return;
      if (ev.key === 'Escape') { ev.preventDefault(); return cerrarHoja(); }
      const g = ev.target && ev.target.closest ? ev.target.closest('[data-pieza]') : null;
      if (g && (ev.key === 'Enter' || ev.key === ' ')) {
        ev.preventDefault();
        return elegirPieza(F.piezas(h.vista).find((x) => F.idPieza(x) === g.dataset.pieza));
      }
      if (ev.key !== 'Tab') return;
      // El foco no sale de la hoja.
      const fs = Array.from(el.querySelectorAll('button:not([disabled]), textarea, [tabindex="0"]')).filter((x) => x.getClientRects().length);
      if (!fs.length) return;
      const primero = fs[0], ultimo = fs[fs.length - 1];
      if (!el.contains(document.activeElement)) { ev.preventDefault(); primero.focus(); }
      else if (ev.shiftKey && document.activeElement === primero) { ev.preventDefault(); ultimo.focus(); }
      else if (!ev.shiftKey && document.activeElement === ultimo) { ev.preventDefault(); primero.focus(); }
    };
    document.addEventListener('keydown', h.tecla, true);
    document.documentElement.classList.add('fb-sin-scroll');
    document.body.appendChild(el);
    sincronizar();
    el.querySelector('#fbTitulo').focus({ preventScroll: true });
  }

  // ───────────────────────── «¿Ya lo tenés?» ─────────────────────────
  const ICONO_MARCA = { tomando: IC.tilde, comprado: IC.bolsa, no_lo_consigo: IC.lupa, lo_deje: IC.pausa };

  /* La sección de Suplementación: cada suplemento una vez, con su marca. Los protectores no aparecen. Con la palanca apagada
     o sin el servidor nuevo devuelve '' y la sección no existe. `items` = los ítems crudos de mypump_suplementacion. */
  function supleHtml(items) {
    if (!supleHabilitado()) return '';
    const fs = F.filas(items, ui.estado.marcas);
    if (!fs.length) return '';
    const fila = (f, n) => {
      const est = F.estadoSuple(f.estado);
      const viaja = ui.marcando.has(f.id);
      return `<div class="fb-supl-fila">
        <div class="fb-supl-top"><span class="fb-supl-nombre">${e(f.nombre)}</span>
          <label class="fb-marca${est ? ` es-${est.id}` : ''}${viaja ? ' is-viajando' : ''}">
            ${viaja ? '<span class="fb-giro" aria-hidden="true"></span>' : (est ? ICONO_MARCA[est.id] : IC.circulo)}
            <span class="fb-marca-txt">${e(est ? est.marcado : T.supleMarcar)}</span>${IC.elegir}
            <select data-supl-marca="${n}" data-nombre="${e(f.nombre)}" aria-label="${e(`${f.nombre}, ${est ? est.marcado : T.supleMarcar}`)}"${viaja ? ' disabled' : ''}>
              ${est ? '' : `<option value="" selected disabled hidden>${e(T.supleMarcar)}</option>`}
              ${F.ESTADOS_SUPLE.map((x) => `<option value="${x.id}"${est && est.id === x.id ? ' selected' : ''}>${e(x.accion)}</option>`).join('')}
            </select>
          </label></div>
        ${f.estado === 'no_lo_consigo' ? `<p class="fb-supl-aviso" data-supl-no-consigo>${e(T.supleNoConsigoAviso)}</p>` : ''}
      </div>`;
    };
    return `<section class="fb-supl" data-supl-estado aria-labelledby="fbSuplTit">
      <div class="fb-supl-cab"><h3 class="supl-ceja" id="fbSuplTit">${e(T.supleTitulo)}</h3><span class="fb-supl-resumen" id="fbSuplResumen">${e(F.resumen(fs))}</span></div>
      <div class="supl-momento">${fs.map(fila).join('')}</div>
      ${ui.falloSuple ? `<p class="fb-supl-fallo" id="fbSuplFallo" role="alert">${IC.alerta}<span>${e(T.supleError)}</span></p>` : ''}
      <p class="fb-supl-ayuda">${e(T.supleAyuda)}</p>
    </section>`;
  }
  /* Después de pintar la sección. */
  function enlazarSuple(root) {
    if (!root) return;
    root.querySelectorAll('select[data-supl-marca]').forEach((s) => {
      s.onchange = () => {
        const n = s.dataset.suplMarca;
        marcar(s.dataset.nombre, s.value).then(() => {
          const otra = document.querySelector(`select[data-supl-marca="${n}"]`);   // la sección se repintó: el foco sigue en su fila
          if (otra && document.activeElement === document.body) { try { otra.focus({ preventScroll: true }); } catch (_) {} }
        });
      };
    });
  }

  function configurar(op) { ui.op = op; }

  raiz.FeedbackUI = {
    configurar, aplicarPalanca, refrescar, botonHtml, estadoHtml, abrir, supleHtml, enlazarSuple,
    dueleHabilitado, supleHabilitado, molestia,
    get _estado() { return ui.estado; },
  };
})(window);
