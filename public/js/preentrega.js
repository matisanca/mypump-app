/* =============================================================
 * preentrega.js — portada de la pre-entrega (obra pump-entregas)
 *
 * El cliente ya pagó y completó el formulario, tiene cuenta y token, pero su
 * plan todavía no está publicado. Antes esto caía en el modo demo y no podía
 * hacer nada. Ahora, si la base dice que está en pre-entrega, se monta esta
 * portada encima: instalar y activar avisos, el perfil del gimnasio (cuando
 * exista), los videos que Mati eligió para él, el check de la semana 0 con
 * fotos y el chat con las preguntas previas.
 *
 * QUÉ NO TOCA: DATA._isDemo sigue en true, así que el entrenamiento y la
 * dieta de ejemplo no escriben nada. Chat, check y fotos se llaman directo a
 * sus RPC desde acá, sin pasar por las guardas del modo demo.
 *
 * INTERRUPTOR: MYPUMP_CONFIG.PREENTREGA_ENABLED (apagado). En localhost se
 * puede probar con ?preentrega=1. La base además rechaza a los clientes
 * reales mientras entregas_config.preentrega.activo esté en false.
 * Cualquier error deja la app como hoy.
 * ============================================================= */
(function () {
  'use strict';

  const CFG = window.MYPUMP_CONFIG || {};
  const LOCAL = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);
  const habilitado = () => !!CFG.PREENTREGA_ENABLED ||
    (LOCAL && new URLSearchParams(location.search).get('preentrega') === '1');

  const plataforma = () => {
    const C = window.Capacitor;
    return C && typeof C.getPlatform === 'function' ? C.getPlatform() : 'web';
  };

  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  let TOKEN = null;
  let PRE = null;

  let _sb = null;
  async function rpc(fn, params) {
    if (!_sb) _sb = window.supabase.createClient(CFG.SUPABASE_URL, CFG.SUPABASE_ANON_KEY, { auth: { persistSession: false } });
    const r = await _sb.rpc(fn, params);
    if (r.error) throw r.error;
    return r.data;
  }

  function fechaLarga(iso) {
    if (!iso) return '';
    try {
      return new Date(iso).toLocaleDateString('es-AR', { weekday: 'long', day: 'numeric', month: 'long' }) +
        ' a las ' + new Date(iso).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit', hour12: false });
    } catch (e) { return ''; }
  }

  // ─── Consulta inicial (la llama cliente.html sin rutina usable) ─────
  async function consultar(token) {
    if (!habilitado() || !token || !window.supabase) return null;
    try {
      const d = await rpc('mypump_get_preentrega', { p_token: token });
      if (!d || !d.activa) return null;
      TOKEN = token; PRE = d;
      montar();
      return d;
    } catch (e) {
      console.warn('[preentrega] sin datos, sigue la app de siempre', e);
      return null;
    }
  }

  // ─── Estilos ───────────────────────────────────────────────────────
  const CSS = `
#preentrega{position:fixed;inset:0;z-index:55;overflow-y:auto;background:var(--color-bg-secondary,#0d0f0e);color:var(--color-text-primary,#f2f2f2);
  padding:calc(env(safe-area-inset-top) + 20px) 16px calc(env(safe-area-inset-bottom) + 28px);font-family:var(--font-sans,system-ui)}
#preentrega h1{font-size:24px;line-height:1.2;margin:4px 0 6px}
#preentrega .pe-sub{opacity:.8;margin:0 0 18px;font-size:15px;line-height:1.45}
#preentrega .pe-card{background:var(--color-bg-primary,#171a18);border-radius:16px;padding:16px;margin:0 0 12px;border:1px solid rgba(127,127,127,.18)}
#preentrega .pe-card h2{font-size:17px;margin:0 0 4px;display:flex;gap:8px;align-items:center}
#preentrega .pe-card p{margin:4px 0 10px;font-size:14px;line-height:1.45;opacity:.85}
#preentrega .pe-n{display:inline-flex;width:24px;height:24px;border-radius:12px;align-items:center;justify-content:center;font-size:13px;background:#2fbf71;color:#04140a;font-weight:700;flex:none}
#preentrega .pe-ok .pe-n{background:#2fbf71}
#preentrega button.pe-b{appearance:none;border:0;border-radius:12px;padding:12px 14px;font-size:15px;font-weight:600;background:#2fbf71;color:#04140a;width:100%;margin-top:4px}
#preentrega button.pe-b2,#preentrega label.pe-b2{appearance:none;border:1px solid rgba(127,127,127,.4);border-radius:12px;padding:10px 12px;font-size:14px;background:transparent;color:inherit;font-weight:600}
#preentrega .pe-video{display:flex;gap:10px;align-items:flex-start;padding:10px 0;border-top:1px solid rgba(127,127,127,.18)}
#preentrega .pe-video:first-of-type{border-top:0}
#preentrega .pe-video .pe-vt{flex:1;min-width:0}
#preentrega .pe-video .pe-vt b{display:block;font-size:15px}
#preentrega .pe-video .pe-vt small{display:block;opacity:.75;font-size:13px;line-height:1.4;margin-top:2px}
#preentrega .pe-tilde{color:#2fbf71;font-weight:700}
#preentrega .pe-escala{display:flex;gap:6px;margin:6px 0 10px}
#preentrega .pe-escala button{flex:1;padding:10px 0;border-radius:10px;border:1px solid rgba(127,127,127,.4);background:transparent;color:inherit;font-size:15px}
#preentrega .pe-escala button.sel{background:#2fbf71;color:#04140a;border-color:#2fbf71}
#preentrega textarea,#preentrega input[type=text]{width:100%;box-sizing:border-box;border-radius:10px;border:1px solid rgba(127,127,127,.4);background:transparent;color:inherit;padding:10px;font-size:15px;font-family:inherit}
#preentrega .pe-chat{max-height:260px;overflow-y:auto;display:flex;flex-direction:column;gap:6px;margin:6px 0 10px}
#preentrega .pe-msg{padding:8px 10px;border-radius:12px;font-size:14px;line-height:1.4;max-width:85%;white-space:pre-wrap}
#preentrega .pe-msg.yo{align-self:flex-end;background:#2fbf71;color:#04140a}
#preentrega .pe-msg.mati{align-self:flex-start;background:rgba(127,127,127,.16)}
#preentrega .pe-revela{text-align:center;padding:22px 16px}
#preentrega .pe-revela b{font-size:18px;display:block;margin-bottom:6px}
#preentrega .pe-pie{display:flex;justify-content:center;margin-top:10px}
#peVolver{position:fixed;right:16px;bottom:calc(env(safe-area-inset-bottom) + 84px);z-index:54;border:0;border-radius:22px;padding:10px 14px;background:#2fbf71;color:#04140a;font-weight:700;box-shadow:0 4px 16px rgba(0,0,0,.35)}
#peReproductor{position:fixed;inset:0;z-index:58;background:rgba(0,0,0,.92);display:flex;flex-direction:column;justify-content:center;padding:16px}
#peReproductor .pe-marco{position:relative;width:100%;padding-top:56.25%}
#peReproductor .pe-marco>div,#peReproductor iframe{position:absolute;inset:0;width:100%;height:100%;border:0}
#peReproductor button{margin-top:14px}
`;

  // ─── Portada ───────────────────────────────────────────────────────
  function montar() {
    if (!document.getElementById('peEstilos')) {
      const st = document.createElement('style'); st.id = 'peEstilos'; st.textContent = CSS;
      document.head.appendChild(st);
    }
    let el = document.getElementById('preentrega');
    if (!el) { el = document.createElement('div'); el.id = 'preentrega'; document.body.appendChild(el); }
    const v = document.getElementById('peVolver'); if (v) v.remove();
    render(el);
  }

  function render(el) {
    const nombre = PRE.nombre_pila ? esc(PRE.nombre_pila) : '';
    const fecha = fechaLarga(PRE.fecha_entrega);
    const pack = Array.isArray(PRE.pack) ? PRE.pack : [];
    const vistos = pack.filter((p) => p.visto).length;
    let n = 0;
    const paso = () => ++n;

    let h = `<h1>Hola${nombre ? ' ' + nombre : ''}, bienvenido a MyPump</h1>
<p class="pe-sub">${fecha ? 'Nuestra videollamada de comienzo es el ' + esc(fecha) + '. ' : ''}Antes de vernos dejá esto listo. Así en la llamada vamos directo a tu plan.</p>`;

    h += `<div class="pe-card"><h2><span class="pe-n">${paso()}</span>Instalá la app y activá los avisos</h2>
<p>Si estás en el navegador, agregala a la pantalla de inicio. Los avisos son para tus recordatorios y para cuando te escriba.</p>
<button class="pe-b" data-pe="avisos">Activar avisos</button></div>`;

    if (PRE.perfil_gimnasio) {
      h += `<div class="pe-card"><h2><span class="pe-n">${paso()}</span>Armá el perfil de tu gimnasio</h2>
<p>Sacale fotos a las máquinas de tu gimnasio. Con eso tu rutina sale de entrada con lo que tenés a mano.</p>
<button class="pe-b" data-pe="gimnasio">Armar el perfil</button></div>`;
    }

    if (pack.length) {
      h += `<div class="pe-card"><h2><span class="pe-n">${paso()}</span>Mirá estos videos (${vistos} de ${pack.length})</h2>
<p>Son cortos. Lo que ves acá no lo repetimos en la llamada y nos queda tiempo para lo tuyo.</p>`;
      for (const p of pack) {
        h += `<div class="pe-video"><div class="pe-vt"><b>${p.visto ? '<span class="pe-tilde">✓</span> ' : ''}${esc(p.titulo)}</b>
<small>${p.minutos ? esc(p.minutos) + ' min. ' : ''}${esc(p.linea || '')}</small></div>
<button class="pe-b2" data-pe="video" data-id="${esc(p.video_id)}">${p.visto ? 'Ver otra vez' : 'Ver'}</button></div>`;
      }
      h += `</div>`;
    }

    h += `<div class="pe-card"><h2><span class="pe-n">${paso()}</span>Tu check de la semana 0</h2>
<p>Es el mismo check que vas a hacer cada semana. Este es el punto de partida.</p>
${escala('energia', 'Energía', '1 muy baja, 5 muy buena')}
${escala('descanso', 'Descanso', '1 muy malo, 5 muy bueno')}
${escala('hambre', 'Hambre', '1 sin hambre, 5 mucha hambre')}
<label style="font-size:14px;opacity:.85">Algo que quieras contarme</label>
<textarea id="peNota" rows="2"></textarea>
<p style="margin-top:12px">Fotos de frente, de perfil y de espalda, con buena luz.</p>
<div style="display:flex;gap:6px">${['frente', 'perfil', 'espalda'].map((pose) =>
  `<label class="pe-b2" style="flex:1;text-align:center">${pose}<input type="file" accept="image/*" data-pose="${pose}" hidden></label>`).join('')}</div>
<p id="peFotosEstado" style="font-size:13px"></p>
<button class="pe-b" data-pe="check">Guardar el check</button></div>`;

    h += `<div class="pe-card" id="peForm" hidden><h2><span class="pe-n">${paso()}</span>Contestame unas preguntas</h2>
<p>Son pocas y me ahorran tiempo en la llamada.</p><div id="peFormCampos"></div>
<button class="pe-b" data-pe="form">Enviar respuestas</button><p id="peFormEstado" style="font-size:13px"></p></div>`;

    h += `<div class="pe-card"><h2><span class="pe-n">${paso()}</span>¿Alguna duda antes de vernos?</h2>
<p>Si te surge algo antes de la llamada, escribime acá.</p>
<div class="pe-chat" id="peChat"></div>
<textarea id="peMsg" rows="2" placeholder="Escribí tu mensaje"></textarea>
<button class="pe-b" data-pe="enviar">Enviar</button></div>`;

    h += `<div class="pe-card pe-revela"><b>Tu plan se revela en la videollamada${fecha ? ' del ' + esc(fecha) : ''}</b>
<p>La rutina y la dieta las armamos juntos en la llamada, con todo lo que me contaste.</p></div>
<div class="pe-pie"><button class="pe-b2" data-pe="explorar">Mirar la app de ejemplo</button></div>`;

    el.innerHTML = h;
    el.onclick = onClick;
    el.querySelectorAll('input[type=file]').forEach((i) => { i.onchange = onFoto; });
    cargarChat();
    cargarFormulario();
  }

  function escala(campo, titulo, ayuda) {
    return `<div><b style="font-size:14px">${titulo}</b> <small style="opacity:.7">${ayuda}</small>
<div class="pe-escala" data-campo="${campo}">${[1, 2, 3, 4, 5].map((v) => `<button data-v="${v}">${v}</button>`).join('')}</div></div>`;
  }

  const CHECK = {};

  async function onClick(ev) {
    const b = ev.target.closest('button');
    if (!b) return;
    const esc5 = b.parentElement && b.parentElement.classList.contains('pe-escala') ? b.parentElement : null;
    if (esc5) {
      CHECK[esc5.dataset.campo] = esc5.dataset.campo.startsWith('f:') ? b.dataset.v : Number(b.dataset.v);
      esc5.querySelectorAll('button').forEach((x) => x.classList.toggle('sel', x === b));
      return;
    }
    const a = b.dataset.pe;
    if (a === 'avisos') return activarAvisos(b);
    if (a === 'gimnasio') return abrirGimnasio(b);
    if (a === 'video') return abrirVideo(b.dataset.id);
    if (a === 'check') return guardarCheck(b);
    if (a === 'enviar') return enviar(b);
    if (a === 'form') return enviarFormulario(b);
    if (a === 'explorar') return explorar();
  }

  async function activarAvisos(b) {
    try {
      let r = null;
      if (window.MyPumpNotif && typeof window.MyPumpNotif.activar === 'function') r = await window.MyPumpNotif.activar();
      else if (typeof window.mostrarOnboardingPermisos === 'function') { await window.mostrarOnboardingPermisos(); r = { ok: true }; }
      b.textContent = r && r.ok ? 'Listo' : (r && r.motivo === 'denegado' ? 'Activalos desde Ajustes' : 'Acá no se pueden activar, hacelo desde la app');
    } catch (e) { b.textContent = 'No se pudo, probá desde Ajustes'; }
  }

  // El creador de perfiles de gimnasio es de MyPump Pro 2.0. Cuando exista,
  // expone window.abrirPerfilGimnasio y este paso lo abre.
  function abrirGimnasio(b) {
    if (typeof window.abrirPerfilGimnasio === 'function') return window.abrirPerfilGimnasio();
    b.textContent = 'Llega con la próxima actualización';
  }

  function explorar() {
    const el = document.getElementById('preentrega'); if (el) el.remove();
    const v = document.createElement('button'); v.id = 'peVolver'; v.textContent = 'Volver a mi inicio';
    v.onclick = montar; document.body.appendChild(v);
  }

  // ─── Videos ────────────────────────────────────────────────────────
  // iOS: el WebView solo navega los dominios propios, así que el iframe de
  // YouTube no carga. Se abre en el navegador interno y se cuenta el tiempo
  // que estuvo abierto, con «Ya lo vi». Web y Android: reproductor embebido
  // con el progreso real.
  async function abrirVideo(id) {
    const p = (PRE.pack || []).find((x) => x.video_id === id);
    if (!p) return;
    const url = (p.url && /^https:\/\//.test(p.url)) ? p.url : (p.yt_id ? 'https://www.youtube.com/watch?v=' + encodeURIComponent(p.yt_id) : '');
    if (plataforma() === 'ios' || !p.yt_id) return abrirAfuera(p, url);
    reproductor(p);
  }

  async function abrirAfuera(p, url) {
    if (!url) return;
    const t0 = Date.now();
    const B = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Browser;
    try {
      if (B && typeof B.open === 'function') await B.open({ url, presentationStyle: 'popover' });
      else window.open(url, '_blank', 'noopener');
    } catch (e) { window.open(url, '_blank', 'noopener'); }
    const host = document.createElement('div'); host.id = 'peReproductor';
    host.innerHTML = `<p style="text-align:center">¿Terminaste de verlo?</p>
<button class="pe-b" style="appearance:none;border:0;border-radius:12px;padding:12px;font-weight:700;background:#2fbf71;color:#04140a">Ya lo vi</button>
<button style="appearance:none;border:0;background:transparent;color:#fff;padding:10px">Todavía no</button>`;
    const [si, no] = host.querySelectorAll('button');
    const cerrar = async (visto) => {
      host.remove();
      await progreso(p, Math.round((Date.now() - t0) / 1000), visto);
    };
    si.onclick = () => cerrar(true); no.onclick = () => cerrar(false);
    document.body.appendChild(host);
  }

  function cargarApiYT() {
    if (window.YT && window.YT.Player) return Promise.resolve();
    return new Promise((ok, mal) => {
      const prev = window.onYouTubeIframeAPIReady;
      window.onYouTubeIframeAPIReady = () => { if (prev) prev(); ok(); };
      const s = document.createElement('script'); s.src = 'https://www.youtube.com/iframe_api'; s.onerror = mal;
      document.head.appendChild(s);
    });
  }

  async function reproductor(p) {
    const host = document.createElement('div'); host.id = 'peReproductor';
    host.innerHTML = `<div class="pe-marco"><div id="peYT"></div></div>
<button style="appearance:none;border:0;border-radius:12px;padding:12px;font-weight:700;background:#2fbf71;color:#04140a">Cerrar</button>`;
    document.body.appendChild(host);
    let player = null, max = p.segundos || 0, marcado = false, cerrado = false;
    const tick = setInterval(async () => {
      if (!player || typeof player.getCurrentTime !== 'function') return;
      const t = Math.round(player.getCurrentTime() || 0), d = player.getDuration() || 0;
      if (t > max) max = t;
      if (!marcado && d && max >= d * 0.8) { marcado = true; await progreso(p, max, true); }
    }, 5000);
    host.querySelector('button').onclick = async () => {
      cerrado = true; clearInterval(tick); host.remove();
      await progreso(p, max, marcado);
    };
    try {
      await cargarApiYT();
      player = new window.YT.Player('peYT', { videoId: p.yt_id, playerVars: { playsinline: 1, rel: 0 } });
    } catch (e) {
      clearInterval(tick); host.remove();
      if (!cerrado) abrirAfuera(p, p.url || 'https://www.youtube.com/watch?v=' + p.yt_id);
    }
  }

  async function progreso(p, segundos, visto) {
    try {
      await rpc('mypump_preentrega_progreso', { p_token: TOKEN, p_video: p.video_id, p_segundos: segundos, p_visto: !!visto });
      if (visto) p.visto = true;
      p.segundos = Math.max(p.segundos || 0, segundos);
      if (visto) {
        const btn = document.querySelector(`#preentrega [data-pe="video"][data-id="${CSS.escape(p.video_id)}"]`);
        const fila = btn && btn.closest('.pe-video');
        if (fila && !fila.querySelector('.pe-tilde')) fila.querySelector('b').insertAdjacentHTML('afterbegin', '<span class="pe-tilde">✓</span> ');
        if (btn) btn.textContent = 'Ver otra vez';
        const h2 = btn && btn.closest('.pe-card').querySelector('h2');
        const pack = PRE.pack || [];
        if (h2) h2.lastChild.textContent = 'Mirá estos videos (' + pack.filter((x) => x.visto).length + ' de ' + pack.length + ')';
      }
    } catch (e) { console.warn('[preentrega] progreso', e); }
  }

  // ─── Check y fotos ─────────────────────────────────────────────────
  async function guardarCheck(b) {
    const nota = (document.getElementById('peNota') || {}).value || '';
    if (!CHECK.energia || !CHECK.descanso || !CHECK.hambre) { b.textContent = 'Elegí energía, descanso y hambre'; return; }
    b.disabled = true; b.textContent = 'Guardando…';
    const hoy = new Date().toLocaleDateString('en-CA');
    const r = await window.mypumpDB.guardarCheckin(TOKEN, hoy,
      { energia: CHECK.energia, descanso: CHECK.descanso, hambre: CHECK.hambre, adherencia: null, nota: ('[semana 0] ' + nota).trim() });
    b.disabled = false;
    b.textContent = r && r.success ? 'Guardado. Gracias' : 'No se pudo guardar, probá de nuevo';
  }

  function onFoto(ev) {
    const f = ev.target.files && ev.target.files[0];
    const pose = ev.target.dataset.pose;
    const out = document.getElementById('peFotosEstado');
    if (!f || typeof window._subirFoto !== 'function' || typeof window._fotoAJpeg !== 'function') return;
    (async () => {
      try {
        if (out) out.textContent = 'Subiendo la foto de ' + pose + '…';
        const dataUrl = await window._fotoAJpeg(f);
        if (!dataUrl || dataUrl.length > 2.4e6) { if (out) out.textContent = 'La foto de ' + pose + ' es muy pesada, probá con otra'; return; }
        const r = await window._subirFoto(pose, dataUrl, new Date().toLocaleDateString('en-CA'));
        if (out) out.textContent = r && r.ok ? 'Foto de ' + pose + ' guardada' : 'No se pudo subir la de ' + pose + ', probá de nuevo';
      } catch (e) { if (out) out.textContent = 'No se pudo leer la foto de ' + pose; }
    })();
  }

  // ─── Formulario previo (uno por cliente, además del de inscripción) ─
  let FORM = null;
  const RESP = {};

  async function cargarFormulario() {
    const card = document.getElementById('peForm');
    if (!card) return;
    try {
      const f = await rpc('mypump_get_formulario_previo', { p_token: TOKEN });
      if (!f || !f.ok || !Array.isArray(f.preguntas) || !f.preguntas.length) return;
      FORM = f;
      Object.assign(RESP, f.respuestas || {});
      document.getElementById('peFormCampos').innerHTML = f.preguntas.map((q) => {
        const v = RESP[q.id];
        let h = `<div style="margin:10px 0"><b style="font-size:14px">${esc(q.texto)}</b>${q.ayuda ? ` <small style="opacity:.7">${esc(q.ayuda)}</small>` : ''}`;
        if (q.tipo === 'opcion' || q.tipo === 'escala') {
          const ops = q.tipo === 'escala' ? ['1', '2', '3', '4', '5'] : (Array.isArray(q.opciones) ? q.opciones : []);
          h += `<div class="pe-escala" data-campo="f:${esc(q.id)}" style="flex-wrap:wrap">${ops.map((o) =>
            `<button data-v="${esc(o)}"${String(v) === String(o) ? ' class="sel"' : ''}>${esc(o)}</button>`).join('')}</div>`;
        } else {
          h += `<textarea rows="2" data-fq="${esc(q.id)}" ${q.tipo === 'numero' ? 'inputmode="decimal"' : ''}>${esc(v == null ? '' : v)}</textarea>`;
        }
        return h + '</div>';
      }).join('');
      card.hidden = false;
      if (f.estado === 'respondido') document.getElementById('peFormEstado').textContent = 'Ya me las mandaste. Si querés, podés corregirlas.';
    } catch (e) { /* sin formulario: la tarjeta queda oculta */ }
  }

  async function enviarFormulario(b) {
    if (!FORM) return;
    const est = document.getElementById('peFormEstado');
    document.querySelectorAll('#peFormCampos textarea[data-fq]').forEach((t) => {
      const q = FORM.preguntas.find((x) => x.id === t.dataset.fq);
      const val = t.value.trim();
      if (!val) { delete RESP[t.dataset.fq]; return; }
      if (q && q.tipo === 'numero') { const n = Number(val.replace(',', '.')); RESP[t.dataset.fq] = Number.isFinite(n) ? n : val; }
      else RESP[t.dataset.fq] = val.slice(0, 2000);
    });
    Object.keys(CHECK).filter((k) => k.startsWith('f:')).forEach((k) => { RESP[k.slice(2)] = String(CHECK[k]); });
    const falta = FORM.preguntas.filter((q) => q.obligatoria && (RESP[q.id] === undefined || RESP[q.id] === ''));
    if (falta.length) { est.textContent = 'Te falta contestar ' + falta.length + (falta.length === 1 ? ' pregunta' : ' preguntas'); return; }
    if (!Object.keys(RESP).length) { est.textContent = 'Contestá al menos una'; return; }
    b.disabled = true; est.textContent = 'Enviando…';
    try {
      const ok = await rpc('entregas_form_responder', { p_clave: FORM.clave, p_respuestas: RESP });
      est.textContent = ok ? 'Listo, gracias. Ya lo tengo.' : 'No se pudo guardar, probá de nuevo';
    } catch (e) { est.textContent = 'No se pudo guardar, probá de nuevo'; }
    b.disabled = false;
  }

  // ─── Chat ──────────────────────────────────────────────────────────
  async function cargarChat() {
    const box = document.getElementById('peChat');
    if (!box || !window.mypumpDB || !window.mypumpDB.getChat) return;
    const msgs = (await window.mypumpDB.getChat(TOKEN, null, 30)) || [];
    const lista = Array.isArray(msgs) ? msgs.slice().reverse() : [];
    box.innerHTML = lista.map((m) => {
      const yo = m.autor === 'cliente' || m.es_cliente === true || m.de === 'cliente';
      return `<div class="pe-msg ${yo ? 'yo' : 'mati'}">${esc(m.contenido || m.texto || '')}</div>`;
    }).join('');
    box.scrollTop = box.scrollHeight;
  }

  async function enviar(b) {
    const t = document.getElementById('peMsg');
    const txt = t && t.value.trim();
    if (!txt) return;
    b.disabled = true;
    const r = await window.mypumpDB.enviarChat(TOKEN, txt);
    b.disabled = false;
    if (r && r.success) { t.value = ''; cargarChat(); } else b.textContent = 'No se pudo enviar, probá de nuevo';
  }

  window.MyPumpPreentrega = { consultar, montar, habilitado };
})();
