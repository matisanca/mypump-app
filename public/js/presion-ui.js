/* =============================================================
   presion-ui.js — «Presión arterial»: las pantallas de la web (presion/CONTRATO_APP.md).

   · Todo texto sale de Presion.T (protocolo, tal cual) y Presion.N (propios).
   · Con la palanca apagada, sin el servidor nuevo o sin cuenta no se crea nada:
     ni modelo, ni IndexedDB, ni llamadas, ni la fila de Mis datos.
   · El alumno ve sus pasos, sus temporizadores, sus tomas tal como las anotó y el avance.
     Nada de promedios, categorías ni colores de riesgo: `resumenSerie` no se usa acá.
   · Los temporizadores van por hora de fin (la guarda el modelo): cambiar de pestaña no los frena.
   · Nada de esta sección toca Entreno ni la rutina.
   ============================================================= */
(function (raiz) {
  'use strict';

  const P = raiz.Presion;
  const D = raiz.PresionDibujos;
  const { T, N } = P;
  const FLAG = 'mypump_palanca_presion_app';
  const SEG_ENTRE_REFRESCOS = 60;
  const TRAMOS = ['estandar', 'grande', 'extra_grande', 'mas_52'];
  const PREVIAS = ['cafeina', 'fumo', 'comida', 'ejercicio'];

  const ui = {
    op: null, modelo: null, arrancando: false, enganchado: false, ultimoRefresco: 0,
    pila: [], enSesion: false, error: null, ocupado: false, ultimoHtml: null, presionando: false, pendiente: false, entrada: false,
    form: null, tras: null, medidaHecha: false, origen: 'misdatos', directo: false,
    previas: {}, previasAviso: false, be: { hora: '', entreno: null },
    toma: { sis: '', dia: '', pulso: '', irregular: false }, avisoNumero: null,
    marcados: {}, nota: '', recordatorio: {}, recordatorioDe: null, guardia: null,
    vozInicio: null, vozFin: null,
  };

  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const IC = {
    chev: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>',
  };

  // ── Piezas ──
  const nota = (t, alerta, id) => `<p class="gim-nota${alerta ? ' is-alerta' : ''}"${alerta ? ' role="alert"' : ''}${id ? ` id="${id}"` : ''}>${e(t)}</p>`;
  const errorHtml = () => (ui.error ? nota(ui.error, true, 'preError') : '');
  const titulo = (t, id) => `<h2 class="gim-h gim-h-chico"${id ? ` id="${id}"` : ''}>${e(t)}</h2>`;
  const parrafos = (xs, id) => `<div class="pre-texto"${id ? ` id="${id}"` : ''}>${xs.filter(Boolean).map((x) => `<p>${e(x)}</p>`).join('')}</div>`;
  const numerados = (xs, id) => `<ol class="pre-pasos"${id ? ` id="${id}"` : ''}>${xs.map((x) => `<li>${e(x)}</li>`).join('')}</ol>`;
  const boton = (accion, texto, clase, extra) => `<button type="button" class="${clase || 'btn-primary'}" data-pre="${accion}" id="pre-${accion}"${extra || ''}>${e(texto)}</button>`;
  /* El dibujo es un SVG inline con role="img": el texto alternativo se lo pone quien lo usa. */
  const dibujo = (nombre, alt, clase) => `<div class="pre-dibujo${clase ? ` ${clase}` : ''}">${String(D[nombre] || '').replace('role="img"', `role="img" aria-label="${e(alt)}"`)}</div>`;
  const cm = (x) => `${String(x).replace('.', ',')} ${N.cm}`;
  const mmss = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  const lado = (b) => (b === 'der' ? N.brazoDer : N.brazoIzq);

  /* Una fila con Sí y No: grupo de radio sin ninguno marcado, los dos del mismo tamaño y color. Se lee «Dolor de pecho. Sí. No.» */
  function filaSN(grupo, clave, texto, valor) {
    const id = `pre-${grupo}-${clave}`;
    const b = (v, t) => `<button type="button" role="radio" aria-checked="${valor === v ? 'true' : 'false'}" class="pre-sn-b${valor === v ? ' is-on' : ''}" data-pre="sn" data-g="${grupo}" data-k="${clave}" data-v="${v}">${e(t)}</button>`;
    return `<div class="pre-sn" role="radiogroup" aria-labelledby="${id}"><span class="pre-sn-t" id="${id}">${e(texto)}</span><span class="pre-sn-bs">${b('si', T.si)}${b('no', T.no)}</span></div>`;
  }
  const listaAlarma = (grupo, respuestas) => `<div class="pre-lista" id="preLista">${P.ALARMA.map((k) => filaSN(grupo, k, P.SINTOMAS[k], respuestas[k] || null)).join('')}</div>`;
  const tilde = (k, texto, marcado) => `<label class="pre-tilde"><input type="checkbox" data-pre-tilde="${k}"${marcado ? ' checked' : ''}><span>${e(texto)}</span></label>`;
  const marcar = () => `<button type="button" class="pre-enlace" data-pre="sintoma" id="pre-sintoma">${e(T.marcarSintoma)}</button>`;

  function relojHtml(m, etiqueta) {
    return `<div class="pre-reloj-caja"><div class="pre-reloj" id="preReloj" role="timer" aria-live="off">${mmss(m.restante())}</div>${etiqueta ? `<p class="pre-reloj-t" id="preRelojT">${e(etiqueta)}</p>` : ''}</div>`;
  }

  // ── Avance, gráfico y lista de «Tus tomas» ──
  function avance(serie) {
    const total = serie.tomas_objetivo, n = Math.max(0, Math.min(total, total - serie.faltan));
    const cs = Array.from({ length: total }, (_, i) => `<span class="pre-circ${i < n ? ' is-on' : ''}"></span>`).join('');
    return `<div class="pre-avance" id="preAvance"><div class="pre-circs" role="img" aria-label="${e(T.avanceAlt(n, total))}">${cs}</div>
      <p class="pre-avance-t">${e(serie.faltan > 0 ? T.faltan(serie.faltan) : T.listoSerieCorto)}</p></div>`;
  }

  const fechaCorta = (f) => {
    try { return new Intl.DateTimeFormat('es', { weekday: 'short', day: 'numeric', month: 'short' }).format(new Date(`${f}T12:00:00`)).replace(/\./g, ''); } catch (_) { return f || ''; }
  };

  /* Alta y baja por día, tal como las anotó. Un solo color neutro, sin líneas de corte, sin promedio y sin colores de riesgo. */
  function graficoSVG(sesiones) {
    const dias = [];
    for (const s of sesiones.slice().reverse()) {
      let d = dias.find((x) => x.fecha === s.fecha);
      if (!d) { d = { fecha: s.fecha, tomas: [] }; dias.push(d); }
      for (const t of s.tomas) d.tomas.push(t);
    }
    dias.sort((a, b) => (a.fecha < b.fecha ? -1 : a.fecha > b.fecha ? 1 : 0));
    const ult = dias.slice(-14);
    const todas = ult.reduce((a, d) => a.concat(d.tomas), []);
    if (todas.length < 2) return '';
    const w = 320, h = 168, izq = 18, der = 18, arr = 22, aba = 40;
    const min = Math.min.apply(null, todas.map((t) => t.dia)), max = Math.max.apply(null, todas.map((t) => t.sis));
    const rango = (max - min) || 1;
    const Y = (v) => arr + (1 - (v - min) / rango) * (h - arr - aba);
    const X = (i) => (ult.length === 1 ? w / 2 : izq + (i * (w - izq - der)) / (ult.length - 1));
    const conNumeros = todas.length <= 8;
    const cadaCuanto = Math.ceil(ult.length / 6);
    const c = 'var(--color-text-secondary)';
    let g = '';
    ult.forEach((d, i) => {
      d.tomas.forEach((t, j) => {
        const x = (X(i) + (j - (d.tomas.length - 1) / 2) * 9).toFixed(1), ya = Y(t.sis).toFixed(1), yb = Y(t.dia).toFixed(1);
        g += `<line x1="${x}" y1="${ya}" x2="${x}" y2="${yb}" stroke="${c}" stroke-width="2" stroke-linecap="round" opacity=".55"/>`
          + `<circle cx="${x}" cy="${ya}" r="3.6" fill="${c}"/>`
          + `<circle cx="${x}" cy="${yb}" r="3" fill="var(--color-bg-primary)" stroke="${c}" stroke-width="1.8"/>`;
        if (conNumeros && d.tomas.length === 1) {
          g += `<text x="${x}" y="${(Y(t.sis) - 8).toFixed(1)}" text-anchor="middle" font-size="10" fill="${c}">${t.sis}</text>`
            + `<text x="${x}" y="${(Y(t.dia) + 15).toFixed(1)}" text-anchor="middle" font-size="10" fill="${c}">${t.dia}</text>`;
        }
      });
      if (ult.length <= 7 || i % cadaCuanto === 0 || i === ult.length - 1) {
        const p = String(d.fecha || '').split('-');
        g += `<text x="${X(i).toFixed(1)}" y="${h - 6}" text-anchor="middle" font-size="10" fill="var(--color-text-muted)">${p.length === 3 ? `${Number(p[2])}/${Number(p[1])}` : ''}</text>`;
      }
    });
    return `<svg class="peso-chart pre-chart" id="preGrafico" viewBox="0 0 ${w} ${h}" role="img" aria-label="${e(N.graficoAlt(todas.length))}">${g}</svg>
      <p class="pre-leyenda" aria-hidden="true"><span class="pre-ley is-alta"></span>${e(N.alta)}<span class="pre-ley is-baja"></span>${e(N.baja)}</p>`;
  }

  function tusTomas(m) {
    const ss = m.sesiones;
    const filas = ss.map((s) => s.tomas.map((t) => `<div class="pre-toma"><span class="pre-toma-f">${e(fechaCorta(s.fecha))}</span>
      <span class="pre-toma-v">${t.sis}/${t.dia}</span><span class="pre-toma-p">${t.pulso != null ? `${e(N.pulso)} ${t.pulso}` : ''}</span></div>`).join('')).join('');
    return `<div class="md-ceja gim-sin-mayus" id="preTusTomas">${e(N.tusTomas)}</div>
      ${ss.length ? `<div class="pre-tarjeta">${graficoSVG(ss)}<div class="pre-tomas" id="preTomas">${filas}</div></div>` : nota(N.sinTomas, false, 'preSinTomas')}`;
  }

  // ── Barra de talles ──
  function posicionEnBarra(x) {
    let p;
    if (x < 22) p = 0;
    else if (x < 32) p = ((x - 22) / 10) * 25;
    else if (x < 42) p = 25 + ((x - 32) / 10) * 25;
    else if (x <= 52) p = 50 + ((x - 42) / 10) * 25;
    else p = 75 + Math.min(1, (x - 52) / 10) * 25;
    return Math.max(1.5, Math.min(98.5, p));
  }
  function barraHtml(x) {
    const tramo = P.tramoBrazo(x);
    return `<div class="pre-talles" id="preTalles">
      <p class="pre-talles-42"><span>${e(T.marca42)}</span></p>
      <div class="pre-talles-barra" aria-hidden="true">${TRAMOS.map((k) => `<span class="pre-talle${tramo === k ? ' is-on' : ''}"></span>`).join('')}
        ${typeof x === 'number' && x > 0 ? `<span class="pre-talles-m" id="preMarcador" style="left:${posicionEnBarra(x).toFixed(1)}%"></span>` : ''}</div>
      <div class="pre-talles-txt">${TRAMOS.map((k) => `<span${tramo === k ? ' class="is-on" aria-current="true"' : ''}><strong>${e(T.tramos[k])}</strong><small>${e(T.tramosRango[k])}</small></span>`).join('')}</div>
    </div>`;
  }

  // ── Pantalla 1 · Inicio ──
  /* Lo que hace el botón principal. → { texto, accion } | { nota } | null */
  function principal(m) {
    const est = m.estado, serie = m.serie, c = m.curso;
    if (c) return m.esperaVencida ? null : { texto: N.seguir, accion: 'retomar' };
    if (!est.aparato) return { texto: N.empezar, accion: 'antes' };
    if (!m.metodo.admite_tomas) return { nota: N.relojNoSirve };
    if (m.pendiente) return null;                             // el bloque de la repetición trae su botón
    if (!serie) return { texto: N.tomaSuelta, accion: 'toma' };
    if (m.hoyListo) return serie.ortostatica ? { nota: N.hoyListo, texto: N.seguir, accion: 'ortostatica' } : { nota: N.hoyListo };
    if (serie.faltan <= 0) return { texto: N.tomaSuelta, accion: 'suelta' };
    return { texto: N.tomaDeHoy, accion: 'toma' };
  }

  function bloquePendiente(m) {
    const p = m.pendiente;
    if (!p || (p.local && !m.esperaVencida)) return '';
    let lista = '';
    if (p.conLista) {
      if (p.local) lista = listaAlarma('lista', m.curso.respuestas || {});
      else if (ui.recordatorioDe !== p.sesion_id) lista = listaAlarma('rec', ui.recordatorio);
    }
    return `<div class="pre-tarjeta" id="prePendiente"><p class="pre-fuerte">${e(T.repetirPendiente)}</p>
      ${lista ? `<p class="gim-sub">${e(T.esperaLista)}</p>${lista}` : ''}
      ${boton('repetir', N.repetir)}</div>`;
  }

  function avisosAparato(m) {
    const a = m.estado.aparato, met = m.metodo, hayLista = !!m.estado.tensiometros;
    if (!a) return '';
    const dos = (xs) => parrafos(hayLista ? xs : xs.slice(0, 1), 'preAvisoAparato');
    let h = '';
    if (met.metodo === 'muneca_provisoria') h = dos(T.muneca);
    else if (a.tipo === 'muneca' && met.pedir_validado) h = hayLista ? parrafos([T.munecaNoValidada], 'preAvisoAparato') : '';
    else if (a.tipo === 'brazo' && met.pedir_validado) h = dos(T.noValidado);
    if (h && hayLista && P.tramoBrazo(m.estado.circunferencia_brazo_cm) && T.porTramo[P.tramoBrazo(m.estado.circunferencia_brazo_cm)]) h += boton('lista', T.verCuales, 'btn-secondary');
    return h;
  }

  function pInicio(m) {
    const est = m.estado, serie = m.serie, a = est.aparato, pr = principal(m);
    const detalleAparato = a ? ([a.marca, a.modelo].filter(Boolean).join(' ') || N.tipos[a.tipo]) : N.tipos.ninguno;
    return `${serie ? avance(serie) : ''}
      ${bloquePendiente(m)}
      ${pr && pr.nota ? `<p class="pre-fuerte" id="preNotaPrincipal">${e(pr.nota)}</p>` : ''}
      ${pr && pr.texto ? boton('principal', pr.texto) : ''}
      ${errorHtml()}
      ${m.enCola ? `<p class="gim-nota" role="status" id="preSinSenal">${e(N.sinSenal)}</p>` : ''}
      ${avisosAparato(m)}
      ${boton('sintoma', T.marcarSintoma, 'btn-secondary')}
      ${tusTomas(m)}
      <div class="md-ceja gim-sin-mayus">${e(N.aparato)}</div>
      <div class="md-grupo">
        <button type="button" class="md-fila pre-fila" data-pre="cambiar" id="pre-cambiar"><span class="gim-zona-txt"><span>${e(detalleAparato)}</span>${a && a.modelo_codigo ? `<small>${e(a.modelo_codigo)}</small>` : ''}</span>
          <span class="pre-fila-acc">${e(N.cambiarAparato)}</span><span class="md-chev">${IC.chev}</span></button>
        ${est.circunferencia_brazo_cm ? `<div class="md-fila pre-fila-fija"><span>${e(N.brazo)}</span><span class="pre-fila-acc">${e(cm(est.circunferencia_brazo_cm))}</span></div>` : ''}
      </div>`;
  }

  // ── Pantalla 2 · Antes de la primera serie, medir de nuevo y cambiar el aparato ──
  function formInicial(m, modo) {
    const est = m.estado, a = est.aparato;
    const n = (x) => (typeof x === 'number' ? String(x).replace('.', ',') : '');
    return {
      modo, paso: 0, pasos: modo === 'primera' ? ['leer', 'medir', 'aparato'] : modo === 'medir' ? ['medir'] : ['medir', 'aparato'],
      cm: modo === 'medir' ? '' : n(est.circunferencia_brazo_cm),
      tipo: a ? a.tipo : null, marca: (a && a.marca) || '', modelo: (a && a.modelo) || '', codigo: (a && a.modelo_codigo) || '',
      min: a ? n(a.manguito_min_cm) : '', max: a ? n(a.manguito_max_cm) : '',
    };
  }
  const leer = (s) => raiz.PresionCola.leerMedida(s);
  /* El rango que cuenta para el talle: el del formulario; si el aparato no cambió, el validado manda (lo decide `manguitoCalza`). */
  function aparatoDelForm(m) {
    const f = ui.form, a = m.estado.aparato;
    const mismo = a && a.tipo === f.tipo && (a.modelo_codigo || '') === f.codigo.trim();
    return { tipo: f.tipo, manguito_min_cm: leer(f.min), manguito_max_cm: leer(f.max),
      manguito_validado_min_cm: mismo ? a.manguito_validado_min_cm : null, manguito_validado_max_cm: mismo ? a.manguito_validado_max_cm : null };
  }
  function fueraDeTalle(m) {
    const f = ui.form, x = leer(f.cm);
    if (x === null || (f.tipo !== 'brazo' && f.tipo !== 'muneca')) return false;
    return P.manguitoCalza(x, f.modo === 'medir' ? m.estado.aparato : aparatoDelForm(m)) === false;
  }
  const medidaLista = () => raiz.PresionCola.medidaValida(leer(ui.form.cm));
  function tramoConLista(m) {
    const k = P.tramoBrazo(leer(ui.form.cm));
    return m.estado.tensiometros && k && T.porTramo[k] ? k : null;
  }
  const campo = (id, etiqueta, valor, extra, clase) => `<label class="pre-campo${clase ? ` ${clase}` : ''}"><span>${e(etiqueta)}</span><input type="text" id="${id}" data-pre-campo="${id}" value="${e(valor)}" autocomplete="off"${extra || ''}></label>`;
  /* Lo que cambia mientras escribe la medida, sin rehacer la pantalla: la barra, el aviso de talle y los botones. */
  function zonaMedida(m) {
    const x = leer(ui.form.cm);
    return `<div id="preZonaMedida">${barraHtml(x)}
      ${fueraDeTalle(m) ? `<p class="pre-fuerte" id="preFuera" role="status">${e(T.fueraDeTalle)}</p>` : ''}
      ${tramoConLista(m) ? boton('lista', T.verCuales, 'btn-secondary') : ''}</div>`;
  }

  /* Un paso por pantalla: leer de qué se trata, medir el brazo y anotar el tensiómetro. El último guarda. */
  const pasoAntes = () => ui.form.pasos[ui.form.paso];
  const ultimoAntes = () => ui.form.paso >= ui.form.pasos.length - 1;
  const puedeSeguirAntes = () => !ui.ocupado && (pasoAntes() === 'leer' || (pasoAntes() === 'medir' ? medidaLista() : medidaLista() && !!ui.form.tipo));
  function pAntes(m) {
    const f = ui.form, est = m.estado, paso = pasoAntes();
    const tipos = ['brazo', 'muneca', 'reloj_anillo_otro', 'ninguno'];
    const esTensiometro = f.tipo === 'brazo' || f.tipo === 'muneca';
    const pie = `${errorHtml()}${boton(ultimoAntes() ? 'guardar' : 'seguirAntes', ultimoAntes() ? N.guardar : N.seguir, 'btn-primary', puedeSeguirAntes() ? '' : ' disabled')}`;
    if (paso === 'leer') {
      return `${titulo(N.antesTitulo, 'preAntesTitulo')}${numerados(est.fotos ? T.antes : T.antes.slice(0, 3), 'preAntes')}${pie}`;
    }
    if (paso === 'medir') {
      return `${titulo(N.medirBrazoTitulo, 'preAntesTitulo')}
        ${f.modo === 'medir' ? `<p class="pre-fuerte" id="preMedirDeNuevo">${e(T.medirDeNuevo)}</p>` : ''}
        ${dibujo('presion_g3_medir_brazo', T.g3Alt)}
        ${numerados(T.g3, 'preG3')}
        ${numerados(T.medirBrazo, 'preMedirBrazo')}
        ${campo('preCm', N.medida, f.cm, ' inputmode="decimal" maxlength="5" enterkeyhint="done"', 'is-grande')}
        ${zonaMedida(m)}
        ${pie}`;
    }
    return `${titulo(N.tipoAparato, 'preTipoT')}
      <div class="pre-ops" role="radiogroup" aria-labelledby="preTipoT">${tipos.map((k) => `<button type="button" role="radio" aria-checked="${f.tipo === k ? 'true' : 'false'}" class="gim-op${f.tipo === k ? ' is-on' : ''}" data-pre="tipo" data-k="${k}">${e(N.tipos[k])}</button>`).join('')}</div>
      ${f.tipo === 'reloj_anillo_otro' ? `<p class="pre-fuerte" id="preReloj0">${e(N.relojNoSirve)}</p>` : ''}
      ${esTensiometro ? `${campo('preMarca', N.marca, f.marca, ' maxlength="80"')}${campo('preModelo', N.modelo, f.modelo, ' maxlength="80"')}
        ${campo('preCodigo', N.codigo, f.codigo, ' maxlength="80" autocapitalize="characters" aria-describedby="preCodigoAyuda"')}<p class="gim-nota" id="preCodigoAyuda">${e(N.codigoAyuda)}</p>
        <div class="md-ceja gim-sin-mayus">${e(N.rango)}</div>
        <div class="pre-dos">${campo('preMin', N.desde, f.min, ' inputmode="decimal" maxlength="5"')}${campo('preMax', N.hasta, f.max, ' inputmode="decimal" maxlength="5"')}</div>
        ${fueraDeTalle(m) ? `<p class="pre-fuerte" id="preFuera" role="status">${e(T.fueraDeTalle)}</p>` : ''}` : ''}
      ${pie}`;
  }

  function pLista(m) {
    const x = ui.form ? leer(ui.form.cm) : m.estado.circunferencia_brazo_cm;
    const k = P.tramoBrazo(x), t = m.estado.tensiometros;
    const xs = (t && k && t.tramos[k]) || [];
    return `${titulo(T.verCuales)}
      ${k && T.porTramo[k] ? `<p class="gim-sub" id="prePorTramo">${e(T.porTramo[k])}</p>` : ''}
      ${xs.length ? `<div class="md-grupo" id="preTensiometros">${xs.map((o) => `<div class="md-fila pre-fila-fija"><span class="gim-zona-txt"><span>${e(o.nombre)}</span>
        <small>${e([o.codigo, o.pais, o.nota].filter(Boolean).join(', '))}</small></span></div>`).join('')}</div>` : nota(N.sinLista, false, 'preSinLista')}`;
  }

  // ── Pantalla 3 · Cuándo y Cómo ──
  function pCuando(m) {
    const serie = m.serie;
    if (serie && serie.tipo === 'bajo_efecto') return `${numerados(T.bajoEfecto, 'preBajoEfecto')}${boton('seguirCuando', N.seguir)}`;
    return `${titulo(T.cuandoTitulo)}${numerados(T.cuando, 'preCuando')}
      ${boton('evitar', T.queEvitar, 'btn-secondary')}
      ${boton('seguirCuando', N.seguir)}`;
  }
  function pEvitar() {
    return `${titulo(T.queEvitar)}
      <div class="pre-grilla" id="preEvitar" role="list" aria-label="${e(T.g5Alt)}">${T.g5.map((x, i) => `<div class="pre-tarjeta pre-evitar" role="listitem">
        ${dibujo(`presion_g5_${String(i + 1).padStart(2, '0')}`, `${T.asiNo}. ${x[0]}`, 'is-chico')}<strong>${e(x[0])}</strong><small>${e(x[1])}</small></div>`).join('')}</div>`;
  }
  function pComo(m) {
    const serie = m.serie;
    const icono = (bien) => String(D[bien ? 'presion_tilde' : 'presion_cruz']).replace('role="img"', `role="img" aria-label="${e(bien ? T.bien : T.asiNo)}" class="pre-ic"`);
    return `${titulo(T.comoTitulo)}
      ${dibujo('presion_g1_postura', T.g1Alt)}${numerados(T.g1, 'preG1')}
      ${dibujo('presion_g2_altura_brazo', T.g2Alt)}
      <div class="pre-tres" id="preG2">${T.g2.map((x, i) => `<div>${icono(i === 1)}<strong>${e(x[0])}</strong><small>${e(x[1])}</small></div>`).join('')}</div>
      ${dibujo('presion_g4_colocar_manguito', T.g4Alt)}${numerados(T.g4, 'preG4')}
      <ol class="pre-pasos is-aparte" id="preComo">${T.como(serie ? serie.brazo : 'izq').map((x) => `<li>${e(x)}</li>`).join('')}</ol>
      ${errorHtml()}${boton('seguirComo', N.seguir)}`;
  }

  // ── Pantalla 9 · Marcar un síntoma ──
  function hojaSintomas(conEnviar) {
    return `<div class="md-ceja gim-sin-mayus" id="preAlarmaT">${e(N.alarma)}</div>
      <div class="pre-tildes" role="group" aria-labelledby="preAlarmaT">${P.ALARMA.map((k) => tilde(k, P.SINTOMAS[k], ui.marcados[k])).join('')}</div>
      <div class="md-ceja gim-sin-mayus" id="preOtrosT">${e(N.otros)}</div>
      <div class="pre-tildes" role="group" aria-labelledby="preOtrosT">${P.OTROS.map((k) => tilde(k, P.SINTOMAS[k], ui.marcados[k])).join('')}</div>
      <textarea class="gim-area" id="preNota" rows="3" maxlength="500" placeholder="${e(N.nota)}" aria-label="${e(N.nota)}"></textarea>
      ${errorHtml()}
      ${conEnviar ? boton('enviarSintoma', N.enviar, 'btn-primary', ui.ocupado ? ' disabled' : '') : boton('seguirSintomas', N.seguir, 'btn-primary', ui.ocupado ? ' disabled' : '')}`;
  }
  const pSintoma = () => `${titulo(T.marcarSintoma)}${hojaSintomas(true)}`;
  function pRecibido(m) {
    const puede = !!m.estado.aparato && m.metodo.admite_tomas && !m.curso;
    return `<p class="pre-fuerte" id="preRecibido" role="status">${e(N.sintomaRecibido)}</p>
      ${puede ? boton('suelta', N.tomaSuelta, 'btn-secondary') : ''}${boton('volver', N.cerrar, 'btn-primary')}`;
  }
  /* El texto de guardia: el único aviso que la app muestra sola. No promete respuesta. */
  function pGuardia(clase) {
    return `<div class="pre-guardia" id="preGuardia" role="alert">${numerados(clase === 'presion' ? T.guardiaPresion : T.guardiaSintomas, 'preGuardiaTexto')}</div>
      ${boton('cerrarSesion', N.cerrar)}`;
  }

  // ── Pantallas 4 a 8 · La sesión en curso ──
  function etiquetaPaso(c) {
    const s = c.sesion;
    if (s.tipo === 'ortostatica') return T.g6(c.variante === 'sentado_parado')[c.paso];
    if (s.tipo === 'comparacion_brazos') return lado(c.pasos[c.paso].brazo);
    return null;
  }
  const meMaree = (c) => (c.sesion.tipo === 'ortostatica' ? boton('meMaree', N.meMaree, 'btn-secondary') : '');

  function pPrevias(m, c) {
    if (c.sesion.tipo === 'bajo_efecto') {
      return `${titulo(N.previas)}
        <label class="pre-campo"><span>${e(N.horaDosis)}</span><input type="time" id="preHora" data-pre-campo="preHora" value="${e(ui.be.hora)}"></label>
        <div class="pre-lista">${filaSN('be', 'entreno', N.entrenoEntre, ui.be.entreno)}</div>
        ${boton('seguirPrevias', N.seguir, 'btn-primary', (!ui.be.hora || !ui.be.entreno || ui.ocupado) ? ' disabled' : '')}`;
    }
    const todas = PREVIAS.every((k) => ui.previas[k]);
    return `${titulo(N.previas)}
      <div class="pre-lista" id="prePrevias">${PREVIAS.map((k) => filaSN('previa', k, N.previa[k], ui.previas[k] || null)).join('')}</div>
      ${ui.previasAviso ? `<p class="pre-fuerte" id="preEsperarMejor" role="status">${e(N.esperarMejor)}</p>
        ${boton('esperar', N.esperar)}${boton('medirIgual', N.medirIgual, 'btn-secondary')}`
    : boton('seguirPrevias', N.seguir, 'btn-primary', (!todas || ui.ocupado) ? ' disabled' : '')}`;
  }

  function pIntro(m, c) {
    if (c.sesion.tipo === 'comparacion_brazos') return `${parrafos(T.brazos, 'preBrazos')}${boton('empezarPaso', N.empezar)}`;
    const sentado = c.variante === 'sentado_parado';
    const alt = sentado ? `${T.g6(true).join('. ')}. ${T.g6Mareo}.` : T.g6Alt;
    return `${dibujo(sentado ? 'presion_g6_ortostatica_sentado' : 'presion_g6_ortostatica', alt)}
      ${numerados(T.g6(sentado), 'preG6')}
      ${parrafos([T.g6Antebrazo, T.g6Mareo])}
      <ol class="pre-pasos" id="preOrtostatica">${T.ortostatica(sentado).map((x) => `<li>${e(x)}</li>`).join('')}</ol>
      ${boton('empezarPaso', N.empezar)}${meMaree(c)}`;
  }

  function pReposo(m, c) {
    const guiada = c.sesion.tipo === 'ortostatica' || c.sesion.tipo === 'comparacion_brazos';
    return `${relojHtml(m, guiada ? etiquetaPaso(c) : N.reposo)}
      ${guiada ? '' : boton('saltear', N.saltear, 'btn-secondary')}${meMaree(c)}${marcar()}`;
  }
  function pParate(m, c) {
    const xs = T.ortostatica(c.variante === 'sentado_parado');
    return `<p class="pre-fuerte" id="preParate">${e(xs[xs.length - 4])}</p>${boton('empezarPaso', N.empezar)}${meMaree(c)}${marcar()}`;
  }

  function pAnotar(m, c) {
    const paso = etiquetaPaso(c), av = ui.avisoNumero;
    const num = (id, etiqueta, v) => `<label class="pre-num"><span>${e(etiqueta)}</span><input type="text" id="${id}" data-pre-campo="${id}" inputmode="numeric" pattern="[0-9]*" maxlength="3" autocomplete="off" enterkeyhint="${id === 'prePul' ? 'done' : 'next'}" value="${e(v)}"${av === 'confirmar' ? ' readonly' : ''}></label>`;
    const revisar = m.estado.fotos ? T.revisarNumero : T.revisarNumeroSinFoto;
    return `${titulo(N.anotar)}${paso ? `<p class="gim-sub" id="prePaso">${e(paso)}</p>` : ''}
      <div class="pre-nums">${num('preSis', N.alta, ui.toma.sis)}${num('preDia', N.baja, ui.toma.dia)}${num('prePul', N.pulso, ui.toma.pulso)}</div>
      <label class="pre-tilde"><input type="checkbox" id="preIrregular"${ui.toma.irregular ? ' checked' : ''}${av === 'confirmar' ? ' disabled' : ''}><span>${e(N.irregular)}</span></label>
      ${av ? `<p class="pre-fuerte" id="preRevisar" role="alert">${e(revisar)}</p>` : ''}
      <div class="pre-pie" id="prePie">${av === 'confirmar' ? `${boton('confirmar', N.confirmar, 'btn-primary', ui.ocupado ? ' disabled' : '')}${boton('corregir', N.corregir, 'btn-secondary')}`
    : boton('anotar', N.anotar, 'btn-primary', ui.ocupado ? ' disabled' : '')}</div>
      ${meMaree(c)}${marcar()}`;
  }

  /* `presion_espera_sintomas`: el temporizador y, con 180/120 o más, la lista de alarma con Sí y No. */
  function pEspera(m, c) {
    const termino = m.restante() === 0;
    return `<div id="presion_espera_sintomas">${relojHtml(m, T.esperaTitulo)}
      ${termino ? boton('repetir', N.repetir) : ''}
      ${c.lista && c.sesion.lista_espera === null ? `<p class="gim-sub" id="preEsperaLista">${e(T.esperaLista)}</p>${listaAlarma('lista', c.respuestas || {})}` : ''}
      ${marcar()}</div>`;
  }

  function pListo(m, c) {
    const z = c.cierre || {}, s = c.sesion, serie = m.serie;
    const sigueOrto = !z.mareo && (s.tipo === 'estandar' || s.tipo === 'bajo_efecto') && !!serie && serie.id === s.serie_id && !!serie.ortostatica;
    const sigueToma = s.tipo === 'comparacion_brazos' && !!serie && serie.id === s.serie_id && !m.hoyListo && serie.faltan > 0;
    const cierre = z.mareo || sigueToma ? null : s.tipo === 'suelta' ? N.sintomaRecibido : z.completa ? T.listoSerie : z.noCuenta ? null : T.como(s.brazo)[7];
    return `${parrafos([z.mareo ? T.mareoOrtostatica : null, z.noCuenta ? T.noCuenta : null, z.agua ? T.sentateAgua : null, z.irregular ? T.latidoIrregular : null, cierre], 'preListo')}
      ${sigueOrto ? boton('ortostatica', N.seguir) : sigueToma ? boton('tomaTrasBrazos', N.seguir) : boton('cerrarSesion', N.cerrar)}${marcar()}`;
  }

  function pSesion(m) {
    const c = m.curso;
    switch (c.etapa) {
      case 'previas': return pPrevias(m, c);
      case 'intro': return pIntro(m, c);
      case 'reposo': return pReposo(m, c);
      case 'parate': return pParate(m, c);
      case 'anotar': return pAnotar(m, c);
      case 'sintomas': return `${titulo(T.marcarSintoma)}${hojaSintomas(false)}`;
      case 'espera': return pEspera(m, c);
      case 'guardia': return pGuardia(c.guardia);
      default: return pListo(m, c);
    }
  }

  // ── Armar y pintar ──
  const tope = () => ui.pila[ui.pila.length - 1] || null;
  const VISTAS = {
    antes: pAntes, lista: pLista, cuando: pCuando, evitar: pEvitar, como: pComo, sintoma: pSintoma, recibido: pRecibido,
    guardia: () => pGuardia(ui.guardia || 'sintomas'),
  };

  function cuerpo(m) {
    const v = tope();
    if (v && VISTAS[v.t]) return VISTAS[v.t](m, v);
    if (ui.enSesion && m.curso) return pSesion(m);
    ui.enSesion = false;
    return pInicio(m);
  }

  function raizEscena() { return document.getElementById('scene-presion'); }
  function escenaActiva() { const r = raizEscena(); return !!r && r.classList.contains('is-active'); }
  const escribiendo = () => {
    const r = raizEscena(), a = document.activeElement;
    return !!r && !!a && r.contains(a) && (a.tagName === 'TEXTAREA' || (a.tagName === 'INPUT' && a.type !== 'checkbox'));
  };

  /* El lector de pantalla oye el temporizador solo al empezar y al terminar: lo dice esta región, no el reloj. */
  function decir(texto) {
    const v = document.getElementById('preVoz');
    if (!v) return;
    v.textContent = '';
    setTimeout(() => { v.textContent = texto; }, 50);
  }

  function renderEscena() {
    const r = raizEscena(), m = ui.modelo;
    if (!r) return;
    if (!m || !m.estado) { r.innerHTML = ''; ui.ultimoHtml = null; if (escenaActiva()) cerrar(); return; }
    // No se le rehace la pantalla a quien escribe, ni el botón que tiene bajo el dedo.
    if (escribiendo() || ui.presionando) { ui.pendiente = true; return; }
    ui.pendiente = false;
    if (!document.getElementById('preCuerpo')) {
      r.innerHTML = '<div class="pre-voz" id="preVoz" aria-live="polite" role="status"></div><div class="gim pre" id="preCuerpo"></div>';
      ui.ultimoHtml = null;
    }
    const enBase = !ui.pila.length && !(ui.enSesion && m.curso);
    const h = `<button type="button" class="sd-volver" data-pre="volver" id="preVolver">‹ ${e(enBase ? N.cerrar : N.volver)}</button>${cuerpo(m)}`;
    if (h !== ui.ultimoHtml) {
      document.getElementById('preCuerpo').innerHTML = h;
      ui.ultimoHtml = h;
      // La nota no va en el HTML: si no, escribir cambiaría la comparación.
      const n = document.getElementById('preNota');
      if (n) n.value = ui.nota;
    }
    const t = document.getElementById('hdrTitle');
    if (t) t.textContent = N.titulo;
    const c = m.curso;
    if (ui.enSesion && c && c.fin && (c.etapa === 'reposo' || c.etapa === 'espera') && m.restante() > 0 && ui.vozInicio !== c.fin) {
      ui.vozInicio = c.fin;
      decir(c.etapa === 'espera' ? T.esperaVoz : (etiquetaPaso(c) || N.reposo));
    }
  }

  /* Cada medio segundo, contra la hora de fin: si la pestaña estuvo de fondo, al volver muestra lo que de verdad falta. */
  function tic() {
    const m = ui.modelo, c = m && m.curso;
    if (!c || !c.fin || !escenaActiva()) return;
    const s = m.restante(), r = document.getElementById('preReloj');
    if (r && r.textContent !== mmss(s)) r.textContent = mmss(s);
    if (s > 0 || ui.vozFin === c.fin) return;
    ui.vozFin = c.fin;
    if (c.etapa === 'reposo') {
      if (ui.enSesion) decir(etiquetaPaso(c) && c.sesion.tipo === 'ortostatica' && c.paso > 0 ? N.minutoParado(c.pasos[c.paso].minutos_de_pie) : N.anotar);
      m.tiempoCumplido().catch(() => {});
    } else if (c.etapa === 'espera') {
      if (ui.enSesion) decir(N.repetir);
      renderEscena();
    }
  }

  function pintar() {
    if (!ui.op) return;
    const ve = !!(ui.modelo && ui.modelo.visibleEntrada);
    if (ve !== ui.entrada) { ui.entrada = ve; ui.op.alCambiarEntrada(); }
    montarTarjeta(document.getElementById('scene-train'));
    if (ui.op.alCambiarTarjeta) { try { ui.op.alCambiarTarjeta(); } catch (_) {} }
    if (escenaActiva()) renderEscena();
  }

  function limpiarToma() { ui.toma = { sis: '', dia: '', pulso: '', irregular: false }; ui.avisoNumero = null; }
  function limpiarHoja() { ui.marcados = {}; ui.nota = ''; }
  function apilar(v) { ui.pila.push(v); ui.error = null; renderEscena(); window.scrollTo(0, 0); }
  function aInicio() { ui.pila = []; ui.enSesion = false; ui.error = null; renderEscena(); window.scrollTo(0, 0); }
  function aSesion() { ui.pila = []; ui.enSesion = true; ui.error = null; renderEscena(); window.scrollTo(0, 0); }

  function abrir(origen) {
    const m = ui.modelo;
    if (!m || !m.estado) return;
    ui.origen = origen === 'train' || origen === 'misalud' ? origen : 'misdatos';   // «misalud»: la pantalla de la 2.3.0
    ui.pila = [];
    ui.error = null;
    ui.form = null;
    ui.tras = null;
    // Una sesión a medias se retoma donde iba; pasados los 10 minutos sin repetir, el inicio muestra el recordatorio.
    ui.enSesion = !!m.curso && !m.esperaVencida;
    ui.op.irA('presion');
    m.refrescar().then(() => ui.modelo && ui.modelo.reanudar()).catch(() => {});
  }
  function cerrar() { if (ui.op) ui.op.irA(ui.origen === 'train' || ui.origen === 'misalud' ? ui.origen : 'misdatos'); }

  /* Desde la tarjeta o un aviso: Presión abierta directo en lo que toca (la repetición, preparar o la toma de hoy).
     Si el modelo todavía no llegó (arranque en frío desde un aviso), queda pedido y se abre apenas llega. */
  function abrirDirecto(origen) {
    const m = ui.modelo;
    if (!m || !m.estado) { ui.directo = origen || 'train'; return; }
    ui.directo = false;
    const t = m.tarjeta;
    abrir(origen || 'train');
    if (ui.enSesion || !t) return;                       // una sesión a medias se retoma donde iba
    if (t.estado === 'repetir') { const p = ACCIONES.repetir(); if (p && p.catch) p.catch(() => {}); return; }
    if (t.estado === 'preparar') {
      if (!m.estado.aparato) ACCIONES.antes();
      else if (!m.metodo.admite_tomas) ACCIONES.cambiar();
      else ACCIONES.toma();                              // pide la medida y sigue con la toma
      return;
    }
    if (t.estado === 'toma') ACCIONES.toma();
  }

  // ── La tarjeta de arriba en Entreno ──
  function circulos(n, total) {
    return `<span class="pre-circs" role="img" aria-label="${e(T.avanceAlt(n, total))}">${Array.from({ length: total }, (_, i) => `<span class="pre-circ${i < n ? ' is-on' : ''}"></span>`).join('')}</span>`;
  }
  function tarjetaHtml(m, idBoton = 'presion-tarjeta-boton') {
    const t = m && m.estado ? m.tarjeta : null;
    if (!t) return '';
    const h = `<strong class="pre-tj-h">${e(N.tarjeta)}</strong>`;
    const b = (texto) => `<button type="button" class="btn-primary" id="${e(idBoton)}" data-tj="directo">${e(texto)}</button>`;
    if (t.estado === 'repetir') return `${h}<p class="pre-tj-t">${e(T.repetirPendiente)}</p>${b(N.repetir)}`;
    if (t.estado === 'preparar') return `${h}<p class="pre-tj-t">${e(N.tarjetaPreparar)}</p>${b(N.empezar)}`;
    if (t.estado === 'toma') {
      return `${h}<p class="pre-tj-t">${e(T.faltan(t.faltan))}</p>${t.primera ? `<p class="pre-tj-s">${e(N.tarjetaSerie)}</p>` : ''}${circulos(t.hechas, t.total)}${b(N.tomaDeHoy)}`;
    }
    return `${h}${circulos(t.hechas, t.total)}<p class="pre-tj-t">${e(N.hoyListo)}</p>`;
  }
  /* renderTrain rehace todo: se vuelve a poner, siempre primera. No toca nada de la rutina: es una tarjeta más, arriba. */
  /* Con «Mi salud» (2.3.0) la tarjeta de Entreno sale solo cuando pide algo y lleva a Presión con «Mi salud» debajo. */
  const origenTarjeta = () => (ui.op && ui.op.origenTarjeta ? ui.op.origenTarjeta() : 'train');
  function montarTarjeta(root) {
    let host = document.getElementById('presion-tarjeta');
    const soloConAlgo = !!(ui.op && ui.op.soloConAlgo && ui.op.soloConAlgo());
    const t = ui.modelo && ui.modelo.estado ? ui.modelo.tarjeta : null;
    const html = soloConAlgo && t && t.estado === 'hoyListo' ? '' : tarjetaHtml(ui.modelo);
    if (!root || !html) { if (host) host.remove(); return; }
    if (!host) {
      host = document.createElement('section');
      host.id = 'presion-tarjeta';
      host.className = 'pre-tj';
      host.setAttribute('aria-label', N.tarjeta);
      host.addEventListener('click', (ev) => {
        if (ev.target.closest('[data-tj="directo"]')) abrirDirecto(origenTarjeta());
        else if (ui.modelo && ui.modelo.tarjeta && ui.modelo.tarjeta.estado === 'hoyListo') abrir(origenTarjeta());
      });
    }
    const sinBoton = ui.modelo.tarjeta.estado === 'hoyListo';
    if (host.dataset.h !== html) { host.innerHTML = html; host.dataset.h = html; }
    // Sin botón, toda la tarjeta abre Presión: se puede llegar con el teclado.
    if (sinBoton) { host.setAttribute('role', 'button'); host.tabIndex = 0; host.onkeydown = (ev) => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); abrir(origenTarjeta()); } }; }
    else { host.removeAttribute('role'); host.removeAttribute('tabindex'); host.onkeydown = null; }
    if (root.firstChild !== host) root.insertBefore(host, root.firstChild);
  }

  async function empezarSesion(tipo) {
    const m = ui.modelo;
    ui.previas = {}; ui.previasAviso = false; ui.be = { hora: '', entreno: null };
    limpiarToma(); limpiarHoja();
    if (await m.empezar(tipo)) aSesion(); else aInicio();
  }
  /* El recorrido de una toma: medir el brazo si la serie lo pide, la comparación de brazos si falta, y Cuándo y Cómo. */
  function iniciarToma(suelta) {
    const m = ui.modelo, serie = suelta ? null : m.serie;
    if (serie && serie.medida_pedida && !ui.medidaHecha) { ui.form = formInicial(m, 'medir'); ui.tras = 'toma'; apilar({ t: 'antes' }); return; }
    if (serie && serie.comparar_brazos) { empezarSesion('comparacion_brazos'); return; }
    ui.tipoPedido = serie ? serie.tipo : 'suelta';
    apilar({ t: serie ? 'cuando' : 'como' });
  }

  async function guardarAntes() {
    const m = ui.modelo, f = ui.form, x = leer(f.cm);
    if (ui.ocupado || !medidaLista()) return;
    ui.ocupado = true; ui.error = null;
    renderEscena();
    let r = 'ok';
    try {
      if (f.modo === 'medir' || x !== m.estado.circunferencia_brazo_cm) r = await m.guardarMedida(x);
      const a = m.estado && m.estado.aparato;
      const esAparato = f.tipo && f.tipo !== 'ninguno';
      const igual = a && a.tipo === f.tipo && (a.marca || '') === f.marca.trim() && (a.modelo || '') === f.modelo.trim() && (a.modelo_codigo || '') === f.codigo.trim()
        && a.manguito_min_cm === leer(f.min) && a.manguito_max_cm === leer(f.max);
      if (r === 'ok' && f.modo !== 'medir' && esAparato && !igual) {
        const tens = f.tipo === 'brazo' || f.tipo === 'muneca';
        r = await m.guardarAparato({ tipo: f.tipo, marca: tens ? f.marca : null, modelo: tens ? f.modelo : null, modelo_codigo: tens ? f.codigo : null,
          manguito_min_cm: tens ? leer(f.min) : null, manguito_max_cm: tens ? leer(f.max) : null });
      }
    } finally { ui.ocupado = false; }
    if (!ui.modelo || !ui.modelo.estado) return;
    if (r !== 'ok') { ui.error = N.noGuardo; renderEscena(); return; }
    const tras = ui.tras;
    ui.tras = null; ui.form = null; ui.pila = [];
    if (f.modo === 'medir') ui.medidaHecha = true;
    if (tras === 'toma') iniciarToma(false); else aInicio();
  }

  function leerToma() {
    const n = (s) => (/^\d{1,3}$/.test(String(s).trim()) ? Number(String(s).trim()) : NaN);
    return { sis: n(ui.toma.sis), dia: n(ui.toma.dia), pulso: n(ui.toma.pulso), latido_irregular: ui.toma.irregular };
  }
  async function anotar(confirmada) {
    const m = ui.modelo;
    if (ui.ocupado) return;
    ui.ocupado = true;
    let r;
    try { r = await m.anotar(leerToma(), confirmada); } finally { ui.ocupado = false; }
    if (r === 'imposible' || r === 'confirmar') ui.avisoNumero = r;
    else { limpiarToma(); limpiarHoja(); window.scrollTo(0, 0); }
    renderEscena();
  }

  // ── Toques ──
  const ACCIONES = {
    async volver() {
      const m = ui.modelo, c = m.curso;
      if (ui.pila.length) {
        const arriba = tope();
        if (arriba.t === 'antes' && ui.form && ui.form.paso > 0) { ui.form.paso -= 1; ui.error = null; renderEscena(); window.scrollTo(0, 0); return; }
        const v = ui.pila.pop();
        if (v.t === 'antes') { ui.form = null; ui.tras = null; }
        if (v.t === 'guardia' || v.t === 'recibido') { ui.pila = []; ui.guardia = null; }
        ui.error = null;
        renderEscena();
      } else if (ui.enSesion && c) {
        if (c.etapa === 'previas' || c.etapa === 'intro') await m.descartar();
        else if (c.etapa === 'guardia' || c.etapa === 'listo') await m.cerrar();
        aInicio();
      } else cerrar();
    },
    principal() {
      const pr = principal(ui.modelo);
      if (pr && pr.accion && ACCIONES[pr.accion]) return ACCIONES[pr.accion]();
    },
    retomar() { aSesion(); },
    antes() { ui.form = formInicial(ui.modelo, 'primera'); ui.tras = null; apilar({ t: 'antes' }); },
    cambiar() { ui.form = formInicial(ui.modelo, ui.modelo.estado.aparato ? 'cambiar' : 'primera'); ui.tras = null; apilar({ t: 'antes' }); },
    toma() { iniciarToma(false); },
    suelta() { ui.pila = []; iniciarToma(true); },
    ortostatica() { return ui.modelo.cerrar().then(() => empezarSesion('ortostatica')); },
    tomaTrasBrazos() { return ui.modelo.cerrar().then(() => { ui.enSesion = false; iniciarToma(false); }); },
    tipo(b) { ui.form.tipo = b.dataset.k; renderEscena(); },
    guardar() { return guardarAntes(); },
    seguirAntes() { if (!puedeSeguirAntes() || ultimoAntes()) return; ui.form.paso += 1; ui.error = null; renderEscena(); window.scrollTo(0, 0); },
    lista() { apilar({ t: 'lista' }); },
    evitar() { apilar({ t: 'evitar' }); },
    seguirCuando() { apilar({ t: 'como' }); },
    seguirComo() { return empezarSesion(ui.tipoPedido || 'suelta'); },
    sn(b) {
      const g = b.dataset.g, k = b.dataset.k, v = b.dataset.v, m = ui.modelo;
      if (g === 'previa') { ui.previas[k] = v; ui.previasAviso = false; renderEscena(); return; }
      if (g === 'be') { ui.be.entreno = v; renderEscena(); return; }
      if (g === 'lista') return m.responderLista(k, v === 'si').then((etapa) => { if (etapa === 'guardia') aSesion(); else renderEscena(); });
      if (g === 'rec') {
        const p = m.pendiente;
        ui.recordatorio[k] = v;
        const todas = P.ALARMA.every((x) => ui.recordatorio[x] === 'no');
        if (v !== 'si' && !todas) { renderEscena(); return; }
        return m.responderRecordatorio(v === 'si' ? { [k]: 'si' } : ui.recordatorio).then((r) => {
          ui.recordatorio = {};
          if (p) ui.recordatorioDe = p.sesion_id;
          if (r === 'guardia') { ui.guardia = 'sintomas'; ui.pila = [{ t: 'guardia' }]; }
          renderEscena();
          window.scrollTo(0, 0);
        });
      }
    },
    seguirPrevias() {
      const m = ui.modelo, c = m.curso;
      if (!c) return;
      if (c.sesion.tipo === 'bajo_efecto') return m.responderBajoEfecto(ui.be.hora, ui.be.entreno === 'si');
      if (PREVIAS.some((k) => ui.previas[k] === 'si')) { ui.previasAviso = true; renderEscena(); return; }
      return ACCIONES.medirIgual();
    },
    medirIgual() { return ui.modelo.responderPrevias(Object.fromEntries(PREVIAS.map((k) => [k, ui.previas[k] === 'si']))); },
    esperar() { return ui.modelo.descartar().then(aInicio); },
    empezarPaso() { return ui.modelo.empezarPaso(); },
    saltear() { return ui.modelo.saltearReposo(); },
    meMaree() { return ui.modelo.meMaree(); },
    anotar() { return anotar(false); },
    confirmar() { return anotar(true); },
    corregir() { ui.avisoNumero = null; renderEscena(); const i = document.getElementById('preSis'); if (i) i.focus(); },
    async repetir() {
      const m = ui.modelo;
      limpiarToma();
      if (m.curso) { await m.repetir(); aSesion(); return; }
      if (await m.retomarDelServidor()) aSesion();
    },
    sintoma() { limpiarHoja(); apilar({ t: 'sintoma' }); },
    async enviarSintoma() {
      const m = ui.modelo;
      if (ui.ocupado) return;
      ui.ocupado = true;
      let r;
      try { r = await m.marcarSintoma(Object.keys(ui.marcados).filter((k) => ui.marcados[k]), ui.nota); } finally { ui.ocupado = false; }
      limpiarHoja();
      if (r === 'guardia' && m.curso && m.curso.etapa === 'guardia') { aSesion(); return; }
      if (r === 'guardia') { ui.guardia = 'sintomas'; ui.pila = [{ t: 'guardia' }]; }
      else ui.pila = [{ t: 'recibido' }];
      renderEscena();
      window.scrollTo(0, 0);
    },
    async seguirSintomas() {
      if (ui.ocupado) return;
      ui.ocupado = true;
      try { await ui.modelo.responderSintomas(Object.keys(ui.marcados).filter((k) => ui.marcados[k]), ui.nota); } finally { ui.ocupado = false; }
      limpiarHoja();
      renderEscena();
      window.scrollTo(0, 0);
    },
    async cerrarSesion() {
      if (ui.pila.length) { ui.guardia = null; aInicio(); return; }
      await ui.modelo.cerrar();
      aInicio();
    },
  };

  const CAMPOS = { preCm: 'cm', preMarca: 'marca', preModelo: 'modelo', preCodigo: 'codigo', preMin: 'min', preMax: 'max' };
  const NUMS = { preSis: 'sis', preDia: 'dia', prePul: 'pulso' };
  const SIGUE = { preSis: 'preDia', preDia: 'prePul' };
  const TOPES = { preSis: P.LIM.sisMax, preDia: P.LIM.diaMax, prePul: P.LIM.pulMax };
  /* Tres cifras, o dos que ya no admiten una tercera (con «95» no hay alta posible de tres cifras). */
  const numeroEntero = (v, tope) => v.length === 3 || (v.length === 2 && Number(v) * 10 > tope);

  function alEscribir(ev) {
    const t = ev.target, m = ui.modelo;
    if (!m) return;
    if (t.id === 'preNota') { ui.nota = t.value; return; }
    if (t.dataset.preTilde) { ui.marcados[t.dataset.preTilde] = t.checked; return; }
    if (t.id === 'preIrregular') { ui.toma.irregular = t.checked; return; }
    if (t.id === 'preHora') {
      ui.be.hora = t.value;
      const b = document.getElementById('pre-seguirPrevias');
      if (b) b.disabled = !ui.be.hora || !ui.be.entreno || ui.ocupado;
      ui.ultimoHtml = null;
      return;
    }
    if (NUMS[t.id]) {
      const limpio = t.value.replace(/\D/g, '').slice(0, 3);
      if (limpio !== t.value) t.value = limpio;
      ui.toma[NUMS[t.id]] = limpio;
      if (ui.avisoNumero === 'imposible') { ui.avisoNumero = null; ui.pendiente = true; }
      // El foco pasa solo al campo que sigue cuando el número ya está entero; después del pulso se va el teclado.
      if (ev.type === 'input' && numeroEntero(limpio, TOPES[t.id])) {
        const sig = SIGUE[t.id] ? document.getElementById(SIGUE[t.id]) : null;
        if (sig) { sig.focus(); if (sig.select) sig.select(); } else t.blur();
      }
      return;
    }
    if (CAMPOS[t.id] && ui.form) {
      ui.form[CAMPOS[t.id]] = t.value;
      // La barra, el aviso de talle y el botón siguen a lo que escribe, sin rehacer la pantalla (no se le va el teclado).
      const z = document.getElementById('preZonaMedida');
      if (z) z.outerHTML = zonaMedida(m);
      const g = document.getElementById('pre-guardar') || document.getElementById('pre-seguirAntes');
      if (g) g.disabled = !puedeSeguirAntes();
      // El aviso de talle del paso del tensiómetro depende del rango que escribe: se repinta al soltar el campo.
      if (t.id === 'preMin' || t.id === 'preMax') ui.pendiente = true;
      ui.ultimoHtml = null;
    }
  }

  function enganchar() {
    if (ui.enganchado) return;
    ui.enganchado = true;
    const r = raizEscena();
    if (r) {
      r.addEventListener('click', (ev) => {
        const b = ev.target.closest('[data-pre]');
        if (!b || b.disabled || !ui.modelo) return;
        const foco = document.activeElement;
        if (foco && r.contains(foco) && foco !== b && (foco.tagName === 'INPUT' || foco.tagName === 'TEXTAREA')) foco.blur();
        const f = ACCIONES[b.dataset.pre];
        if (f) { const p = f(b); if (p && p.catch) p.catch(() => {}); }
      });
      r.addEventListener('input', alEscribir);
      r.addEventListener('change', alEscribir);
      // En un grupo de radio las flechas mueven el foco, sin elegir: en la lista de alarma un Sí no puede salir de una flecha.
      r.addEventListener('keydown', (ev) => {
        if (ev.key !== 'ArrowLeft' && ev.key !== 'ArrowRight' && ev.key !== 'ArrowUp' && ev.key !== 'ArrowDown') return;
        const b = ev.target.closest('[role="radio"]'), g = b && b.closest('[role="radiogroup"]');
        if (!g) return;
        const xs = [...g.querySelectorAll('[role="radio"]')], i = xs.indexOf(b);
        const sig = xs[(i + (ev.key === 'ArrowLeft' || ev.key === 'ArrowUp' ? xs.length - 1 : 1)) % xs.length];
        if (sig) { ev.preventDefault(); sig.focus(); }
      });
      const repintarPendiente = () => setTimeout(() => { if (ui.pendiente && ui.modelo && escenaActiva()) renderEscena(); }, 60);
      r.addEventListener('pointerdown', () => { ui.presionando = true; }, true);
      const soltar = () => { if (!ui.presionando) return; ui.presionando = false; repintarPendiente(); };
      window.addEventListener('pointerup', soltar, true);
      window.addEventListener('pointercancel', soltar, true);
      r.addEventListener('focusout', repintarPendiente);
    }
    /* El botón de «Anotar» queda siempre a la vista: pegado arriba del teclado si está abierto, o de la barra de pestañas. */
    if (r) {
      const vv = window.visualViewport;
      const pie = () => {
        const tab = document.querySelector('.tabbar');
        const teclado = vv ? Math.max(0, window.innerHeight - vv.height - vv.offsetTop) : 0;
        r.style.setProperty('--pre-pie', `${Math.round(teclado > 80 ? teclado : (tab ? tab.offsetHeight : 0))}px`);
      };
      if (vv) { vv.addEventListener('resize', pie); vv.addEventListener('scroll', pie); }
      window.addEventListener('resize', pie);
      pie();
    }
    setInterval(tic, 500);
    window.addEventListener('online', () => { if (ui.modelo) ui.modelo.reanudar(); });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible' || !ui.modelo) return;
      tic();
      if (Date.now() - ui.ultimoRefresco > SEG_ENTRE_REFRESCOS * 1000) { ui.ultimoRefresco = Date.now(); ui.modelo.refrescar().catch(() => {}); }
      ui.modelo.reanudar();
    });
  }

  const conLock = (token) => (fn) => {
    if (!navigator.locks || !navigator.locks.request) return fn();
    return navigator.locks.request(`presion-cola-${token}`, () => fn());
  };

  /* op: { token, rpc, irA(escena), alCambiarEntrada(), appVersion } */
  function configurar(op) { ui.op = op; }

  /* valor: true o false si el servidor contestó; null si no se pudo preguntar (se sigue con lo último que se supo). */
  async function aplicarPalanca(valor) {
    if (!ui.op || ui.arrancando) return;
    let prendida;
    try {
      if (valor === null) prendida = localStorage.getItem(FLAG) === '1';
      else {
        prendida = valor === true;
        if (prendida) localStorage.setItem(FLAG, '1'); else localStorage.removeItem(FLAG);
      }
    } catch (_) { prendida = valor === true; }
    if (!prendida) {
      ui.directo = false;
      if (ui.modelo) { ui.modelo.apagar(); ui.modelo = null; pintar(); }
      return;
    }
    if (ui.modelo) return;
    ui.arrancando = true;
    try {
      // `arrancar` pregunta antes de abrir nada en el teléfono: a una cuenta sin la función no se le crea ni la base.
      const m = await raiz.PresionCola.arrancar({ palanca: true, rpc: ui.op.rpc, token: ui.op.token, appVersion: ui.op.appVersion || null, plataforma: 'web', conLock: conLock(ui.op.token) });
      if (!m) return;
      m.alCambiar = pintar;
      ui.modelo = m;
      ui.ultimoRefresco = Date.now();
      enganchar();
      pintar();
      m.reanudar();
      if (ui.directo) abrirDirecto(typeof ui.directo === 'string' ? ui.directo : 'train');
    } catch (_) {
      ui.modelo = null;
    } finally {
      ui.arrancando = false;
      ui.directo = false;
    }
  }

  raiz.PresionUI = {
    configurar, aplicarPalanca, abrir, abrirDirecto, montarTarjeta, renderEscena,
    get origen() { return ui.origen; },
    titulo: () => N.titulo,
    entrada: () => N.entrada,
    entradaVisible: () => !!(ui.modelo && ui.modelo.visibleEntrada),
    /* Para «Mi salud»: la tarjeta de hoy (null si no hay) y su HTML con otro id de botón. */
    tarjeta: () => (ui.modelo && ui.modelo.estado ? ui.modelo.tarjeta || null : null),
    tarjetaHtml: (idBoton) => tarjetaHtml(ui.modelo, idBoton),
    get _modelo() { return ui.modelo; },
    get _ui() { return ui; },
    _accion: (nombre, b) => ACCIONES[nombre] && ACCIONES[nombre](b || { dataset: {} }),
  };
})(window);
