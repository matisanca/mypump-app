/* «Novedades de tu plan» en la web (app 2.3.0, palanca `novedades_plan`): la hoja que se abre sola una vez cuando Mati
 * publica un cambio, la tarjeta de Entreno (7 días) y la lista en Mis datos. Las reglas están en js/novedades-plan.js.
 * Apagada no se crea nada, no se guarda nada y no se ve nada. */
(function (global) {
  'use strict';
  const NP = global.NovedadesPlan;

  const T = {
    ceja: 'Novedades de tu plan',
    entradaMisDatos: 'Novedades de tu plan',
    vacio: 'Cuando Mati cambie tu rutina, tu dieta o tu suplementación, lo vas a ver acá.',
    listo: 'Listo',
    ver: 'Ver',
    area: (a) => a === 'rutina' ? 'Rutina' : a === 'dieta' ? 'Dieta' : 'Suplementación',
    boton: (a) => a === 'rutina' ? 'Ver mi rutina' : a === 'dieta' ? 'Ver mi dieta' : 'Ver mi suplementación',
    etiquetaGrande: (p) => !p.grande ? null
      : p.area === 'rutina' ? (p.titular.includes('bloque') ? 'Bloque nuevo' : 'Nueva')
      : p.titular.includes('nueva') ? 'Nueva' : 'Primera vez',
  };
  const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  /** «Hoy», «Ayer», «Hace 3 días», «4 de noviembre». */
  function cuando(ms, hoy = new Date()) {
    const d = new Date(ms);
    const a = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    const b = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
    const dias = Math.round((b - a) / 86400000);
    if (dias <= 0) return 'Hoy';
    if (dias === 1) return 'Ayer';
    if (dias < 7) return `Hace ${dias} días`;
    return `${d.getDate()} de ${MESES[d.getMonth()]}`;
  }

  const svg = (p, w = 22) => `<svg width="${w}" height="${w}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
  const IC = {
    chispas: svg('<path d="M12 3l1.9 4.6L18.5 9.5l-4.6 1.9L12 16l-1.9-4.6L5.5 9.5l4.6-1.9z"/><path d="M19 15l.8 1.9 1.9.8-1.9.8L19 20.4l-.8-1.9-1.9-.8 1.9-.8z"/>'),
    rutina: svg('<path d="M6.5 6.5v11M17.5 6.5v11M3.5 9v6M20.5 9v6M6.5 12h11"/>', 18),
    dieta: svg('<path d="M7 3v8a2 2 0 0 0 2 2v8M11 3v8a2 2 0 0 1-2 2M17 21V3c-2 0-3.5 2.5-3.5 6s1.5 5 3.5 5"/>', 18),
    suplementacion: svg('<rect x="3" y="8.5" width="18" height="7" rx="3.5" transform="rotate(-45 12 12)"/><path d="M9.5 9.5l5 5"/>', 18),
    chev: svg('<polyline points="9 6 15 12 9 18"/>', 14),
  };
  const e = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const ui = { op: null, modelo: null, prendida: false, abierta: null, yaPedida: false };

  /** op: {token, irA(area), puedeIr(area), host() → el #modalHost, ocupado() → otra hoja o el onboarding a la vista}. */
  function configurar(op) { ui.op = op; }

  const ALMACEN = { leer: (k) => { try { return localStorage.getItem(k); } catch (_) { return null; } },
    guardar: (k, v2) => { try { localStorage.setItem(k, v2); } catch (_) {} },
    borrar: (k) => { try { localStorage.removeItem(k); } catch (_) {} } };

  function aplicarPalanca(v) {
    ui.prendida = v === true;
    if (!ui.prendida || !ui.op || !NP) {
      ui.modelo = null;
      // Apagada, el plan «ya visto» se borra en cada carga (la lista de novedades guardadas queda).
      if (!ui.prendida && ui.op && NP) NP.olvidarBase(ui.op.token, ALMACEN);
      return;
    }
    if (!ui.modelo) ui.modelo = NP.crearModelo(ui.op.token, ALMACEN);
  }
  /** La demo y las capturas: una lista armada, sin guardar nada. */
  function usarMuestra(lista) {
    const mem = new Map([[`mypump_novedades_${'demo'}`, JSON.stringify(lista)]]);
    ui.prendida = true;
    ui.modelo = NP.crearModelo('demo', { leer: (k) => mem.get(k) || null, guardar: (k, v) => mem.set(k, v) });
  }

  /** Las capturas y la demo (?novedades=plan|rutina|bloque, con «-vista» ya vistas): lo mismo que DemoNovedades de iOS. */
  function muestra(tipo) {
    const ahora = Date.now();
    const rutina = { area: 'rutina', titular: 'Mati actualizó tu rutina', grande: false, lineas: [
      'En Tirón A cambia Pullover en polea por Remo en máquina', 'En Tirón A, Jalón al pecho prono pasa a 4 series de 6 a 8',
      'En Empuje A se suma Vuelos laterales'] };
    const dieta = { area: 'dieta', titular: 'Mati actualizó tu dieta', grande: false, lineas: [
      'Tu objetivo del día pasa a 2.450 kcal', 'En Almuerzo, Arroz blanco cocido pasa a 180 g', 'En Merienda cambia Manzana por Frutillas'] };
    const supl = { area: 'suplementacion', titular: 'Mati actualizó tu suplementación', grande: false, lineas: ['Se suma Magnesio glicinato'] };
    const bloque = { area: 'rutina', titular: 'Mati te armó un bloque nuevo', grande: true, lineas: ['3 días, Tirón A, Empuje A y Pierna A', '9 ejercicios nuevos'] };
    const una = (id, p, fecha = ahora, vista = false) => ({ id, fecha, titular: p.titular, resumen: p.lineas[0], partes: [p], vista });
    const vista = /-vista$/.test(tipo || '');
    const t = (tipo || '').replace(/-vista$/, '');
    const l = t === 'bloque' ? [una('demo-b', bloque)] : t === 'rutina' ? [una('demo-r', rutina)] : [
      { id: 'demo-p', fecha: ahora, titular: 'Mati actualizó tu plan', resumen: 'Hay cambios en tu rutina, tu dieta y tu suplementación', partes: [rutina, dieta, supl], vista: false },
      una('demo-v', bloque, ahora - 9 * 86400000, true)];
    return vista ? l.map((n) => Object.assign({}, n, { vista: true })) : l;
  }

  function observar(llego, semilla) {
    if (!ui.modelo) return null;
    return ui.modelo.observar(llego, semilla);
  }

  // ------------------------------------------------------------ Piezas

  function parteHtml(p, varias) {
    const chip = T.etiquetaGrande(p);
    const ir = varias && ui.op && ui.op.puedeIr(p.area)
      ? `<button type="button" class="nov-ver" data-nov-ir="${e(p.area)}">${e(T.ver)}${IC.chev}</button>` : '';
    return `<div class="nov-parte">
      <div class="nov-parte-cab"><span class="nov-parte-ic">${IC[p.area] || IC.chispas}</span>
        <span class="nov-parte-tit">${e(T.area(p.area))}</span>${chip ? `<span class="nov-chip">${e(chip)}</span>` : ''}${ir}</div>
      <ul class="nov-lineas">${p.lineas.map((l) => `<li>${e(l)}</li>`).join('')}</ul></div>`;
  }

  function contenidoHtml(n) {
    const varias = n.partes.length > 1;
    return `<div class="nov-cab"><span class="nov-icono">${IC.chispas}</span>
        <div class="nov-ceja">${e(T.ceja)} · ${e(cuando(n.fecha))}</div>
        <h2 class="nov-titular">${e(n.titular)}</h2>
        ${varias ? `<p class="nov-resumen">${e(n.resumen)}</p>` : ''}</div>
      <div class="nov-partes">${n.partes.map((p) => parteHtml(p, varias)).join('')}</div>`;
  }

  function cerrar() {
    const h = ui.op && ui.op.host();
    if (h && h.querySelector('#novBack')) h.innerHTML = '';
    ui.abierta = null;
  }

  function abrirHoja(n) {
    if (!n || !ui.op) return;
    const h = ui.op.host();
    if (!h) return;
    ui.abierta = n.id;
    ui.modelo && ui.modelo.marcarVista(n.id);
    const una = n.partes.length === 1 ? n.partes[0] : null;
    const botones = una && ui.op.puedeIr(una.area)
      ? `<button class="btn-primary nov-btn" data-nov-ir="${e(una.area)}">${e(T.boton(una.area))}</button>
         <button class="btn-secondary nov-btn" data-nov-listo>${e(T.listo)}</button>`
      : `<button class="btn-primary nov-btn" data-nov-listo>${e(T.listo)}</button>`;
    h.innerHTML = `<div class="modal-back" id="novBack"><div class="modal-sheet nov-hoja" role="dialog" aria-modal="true" aria-labelledby="novTit">
      <div class="modal-handle"></div>${contenidoHtml(n).replace('class="nov-titular"', 'class="nov-titular" id="novTit"')}
      <div class="nov-botones">${botones}</div></div></div>`;
    const back = h.querySelector('#novBack');
    back.addEventListener('click', (ev) => {
      if (ev.target === back || ev.target.closest('[data-nov-listo]')) { cerrar(); return; }
      const ir = ev.target.closest('[data-nov-ir]');
      if (ir) { cerrar(); ui.op.irA(ir.getAttribute('data-nov-ir')); }
    });
    const foco = h.querySelector('.nov-btn');
    if (foco) try { foco.focus({ preventScroll: true }); } catch (_) {}
  }

  /** La de esta publicación, una vez por carga, sin taparle otra hoja ni el onboarding. */
  function mostrarPendiente() {
    if (!ui.modelo || ui.yaPedida) return;
    const n = ui.modelo.pendiente;
    if (!n) return;
    ui.yaPedida = true;
    const intentar = (vueltas) => {
      if (!ui.modelo) return;
      if (document.visibilityState !== 'visible' || (ui.op.ocupado && ui.op.ocupado())) {
        if (vueltas > 0) setTimeout(() => intentar(vueltas - 1), 1500);
        else ui.yaPedida = false;
        return;
      }
      abrirHoja(n);
    };
    setTimeout(() => intentar(40), 1200);
  }

  /** La tarjeta arriba en Entreno, debajo de la de la guía y la del gimnasio. renderTrain rehace todo: se vuelve a poner. */
  function montarTarjeta(root, despuesDe) {
    let host = document.getElementById('novHost');
    const n = ui.modelo && ui.modelo.reciente;
    if (!root || !n) { if (host) host.remove(); return; }
    if (!host) {
      host = document.createElement('div');
      host.id = 'novHost';
      host.addEventListener('click', () => { const x = ui.modelo && ui.modelo.reciente; if (x) abrirHoja(x); });
    }
    const html = `<button type="button" class="nov-tarjeta${n.vista ? '' : ' is-nueva'}"><span class="nov-tarjeta-ic">${IC.chispas}</span>
      <span class="nov-tarjeta-txt"><span class="nov-tarjeta-ceja">${e(T.ceja)}</span><strong>${e(n.titular)}</strong><span>${e(n.resumen)}</span></span>
      <span class="md-chev">${IC.chev}</span></button>`;
    if (host.dataset.h !== html) { host.innerHTML = html; host.dataset.h = html; }
    const ancla = despuesDe && despuesDe.parentNode === root ? despuesDe : null;
    const sigue = ancla ? ancla.nextSibling : root.firstChild;
    if (sigue !== host) root.insertBefore(host, sigue);
  }

  /** La lista de Mis datos, en una hoja: la más nueva primero; tocar una la abre. */
  function abrirLista() {
    if (!ui.modelo || !ui.op) return;
    const h = ui.op.host();
    if (!h) return;
    const l = ui.modelo.lista;
    const filas = l.length ? l.map((n) => `<button type="button" class="nov-fila" data-nov-id="${e(n.id)}">
        <span class="nov-tarjeta-ic">${IC.chispas}</span><span class="nov-tarjeta-txt"><span class="nov-tarjeta-ceja">${e(cuando(n.fecha))}</span>
        <strong>${e(n.titular)}</strong><span>${e(n.resumen)}</span></span><span class="md-chev">${IC.chev}</span></button>`).join('')
      : `<div class="nov-vacio"><span class="nov-icono">${IC.chispas}</span><p>${e(T.vacio)}</p></div>`;
    h.innerHTML = `<div class="modal-back" id="novBack"><div class="modal-sheet nov-hoja" role="dialog" aria-modal="true" aria-labelledby="novListaTit">
      <div class="modal-handle"></div><h2 class="nov-titular" id="novListaTit">${e(T.ceja)}</h2>
      <div class="nov-lista">${filas}</div>
      <div class="nov-botones"><button class="btn-secondary nov-btn" data-nov-listo>${e(T.listo)}</button></div></div></div>`;
    const back = h.querySelector('#novBack');
    back.addEventListener('click', (ev) => {
      if (ev.target === back || ev.target.closest('[data-nov-listo]')) { cerrar(); return; }
      const f = ev.target.closest('[data-nov-id]');
      if (f) { const n = ui.modelo.lista.find((x) => x.id === f.getAttribute('data-nov-id')); if (n) abrirHoja(n); }
    });
  }

  global.NovedadesUI = {
    T, cuando, muestra, configurar, aplicarPalanca, usarMuestra, observar, mostrarPendiente, montarTarjeta, abrirHoja, abrirLista, cerrar,
    entradaVisible: () => !!(ui.prendida && ui.modelo),
    prendida: () => ui.prendida,
  };
})(typeof window !== 'undefined' ? window : globalThis);
