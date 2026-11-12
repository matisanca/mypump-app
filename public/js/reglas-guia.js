/* =============================================================
   reglas-guia.js — Las reglas puras de «Tu guía» (sin DOM), compartidas
   por public/js/guia.js y las pruebas de node.

   Port de la app nativa MyPump 2.2.0 (rama nativa-220):
   · MyPumpModelos/Guia.swift y Agenda.swift (la lectura tolerante del JSON);
   · MyPumpReglas/Guia.swift (la guía, la novedad), Agenda.swift (los videos
     obligatorios y la agenda de la entrega) y FormatoVideo.swift (el cuadro
     de cada video y el recorte de las franjas negras metidas en el archivo).
   Vectores: scripts/test-guia-agenda.mjs, portados de AgendaTests.swift,
   GuiaTests.swift y FormatoVideoTests.swift.
   ============================================================= */
(function (raiz) {
  'use strict';

  const MAX_TEXTO = 1000;            // la base acepta de 1 a 1000 caracteres
  const MAX_SEGUNDOS = 36000;        // p_segundos de 0 a 36000
  const HORAS_TARJETA = 48;          // entregas_014: 48 h exactas
  const ZONA_BA = 'America/Argentina/Buenos_Aires';
  // Caracteres como los cuenta la base (puntos de código), no unidades UTF-16.
  const largo = s => Array.from(s || '').length;

  // ─── Lectura tolerante (MyPumpModelos/Guia.swift) ───────────────
  // Un campo que falta, viene null o con otro tipo no rompe el resto.
  function texto(v) {
    if (typeof v === 'string') return v;
    if (typeof v === 'number' && isFinite(v)) return String(v);
    return null;
  }
  function booleano(v) {
    if (typeof v === 'boolean') return v;
    if (v === 'true' || v === 1) return true;
    if (v === 'false' || v === 0) return false;
    return null;
  }
  function decimal(v) {
    const n = typeof v === 'number' ? v : (typeof v === 'string' && v.trim() !== '' ? Number(v) : NaN);
    return isFinite(n) ? n : null;
  }
  function entero(v) { const n = decimal(v); return n == null ? null : Math.trunc(n); }
  const lista = v => (Array.isArray(v) ? v : []);
  const esObjeto = v => !!v && typeof v === 'object' && !Array.isArray(v);
  const noVacio = s => (s == null || s === '' ? null : s);
  function textos(v) {
    if (typeof v === 'string') return [v];
    if (Array.isArray(v)) return v.map(texto).filter(x => x != null);
    return null;
  }
  const trimServidor = s => s.replace(/^[\s\u00a0\ufeff]+|[\s\u00a0\ufeff]+$/g, '');

  function normalizarClip(o) {
    if (!esObjeto(o)) return null;
    const id = (texto(o.id) || '').trim();
    // Sin id no se puede guardar el avance ni la duda: el clip no sirve.
    if (!id) return null;
    let url = null;
    const u = (texto(o.url) || '').trim();
    if (/^https?:\/\//i.test(u)) url = u;
    const m = decimal(o.minutos) || 0;
    const seg = decimal(o.segundos) || 0;
    return {
      id,
      titulo: texto(o.titulo) || '',
      url,                                   // sin url, el video todavía se está subiendo
      minutos: m > 0 ? m : 0,
      motivo: texto(o.motivo),
      bloque: texto(o.bloque),
      visto: booleano(o.visto) || false,
      segundos: Math.trunc(Math.min(MAX_SEGUNDOS, Math.max(0, seg))),
      duda: noVacio(texto(o.duda)),
      // 2.2.0: de la última tanda (va en el bloque «Novedad»).
      nuevo: booleano(o.nuevo) || false,
      // 2.2.0: cuenta para habilitar la agenda. null = el servidor no mandó el campo.
      obligatorio: booleano(o.obligatorio),
    };
  }

  function normalizarDudaLlamada(o) {
    // La web también acepta una lista de textos sueltos: se toleran las dos formas.
    if (typeof o === 'string') return { texto: o, en: null };
    if (!esObjeto(o)) return null;
    return { texto: texto(o.texto) || '', en: texto(o.en) };
  }

  function normalizarComprar(o) {
    if (typeof o === 'string') return o ? { buscar: o, donde: null, nota: null } : null;
    if (!esObjeto(o)) return null;
    const c = { buscar: noVacio(texto(o.buscar)), donde: noVacio(texto(o.donde)), nota: noVacio(texto(o.nota)) };
    return c.buscar || c.donde || c.nota ? c : null;
  }

  function normalizarItem(o) {
    if (!esObjeto(o)) return null;
    return {
      // Tal como viene (como la web y entregas_012): un nombre en blanco no es vacío.
      nombre: texto(o.nombre) || '',
      cantidad: texto(o.cantidad),
      momento: texto(o.momento),
      tomas: lista(o.tomas).filter(esObjeto).map(t => ({
        momento: texto(t.momento), cantidad: texto(t.cantidad), nota: texto(t.nota), nombre: texto(t.nombre),
      })),
      nota: texto(o.nota),
      detalle: (textos(o.detalle) || []).filter(x => x !== ''),
      estado: texto(o.estado),
      opcional: booleano(o.opcional) || false,
      porQue: noVacio(texto(o.por_que)),
      videoId: noVacio(texto(o.video_id)),
      dias: (textos(o.dias) || []).map(x => x.trim()).filter(Boolean),
      antes: noVacio(texto(o.antes)),
      cambio: noVacio(texto(o.cambio)),
      comprar: normalizarComprar(o.comprar),
    };
  }

  function normalizarSuplementacion(o) {
    if (!esObjeto(o)) return null;
    return {
      titulo: texto(o.titulo),
      dia: lista(o.dia).filter(esObjeto).map(m => ({ id: texto(m.id) || '', nombre: texto(m.nombre) })).filter(m => m.id),
      // Como la web (`if (!it || !it.nombre) return`): sin nombre no va.
      items: lista(o.items).map(normalizarItem).filter(it => it && it.nombre !== ''),
      sigueTexto: noVacio(texto(o.sigue_texto)),
      accion: noVacio(texto(o.accion)),
    };
  }

  const textoRecortado = v => { const t = texto(v); return t && t.trim() ? t : null; };

  // Lo que devuelve entregas_app_get. Todo lo que no sea un objeto con
  // ok:true es «no hay guía».
  // ─── «Lo que más te importa» (MyPumpReglas/GuiaDolor.swift, casos: apps/shared/fixtures/guia/dolor-casos.json) ───
  function leerDolor(v) {
    if (!esObjeto(v)) return null;
    const t = texto(v.texto) || '';
    return t ? { titulo: texto(v.titulo), texto: t } : null;
  }
  const ESP = '[\\s\\x0B\\p{Z}\\uFEFF]';
  const recortarD = s => s.replace(/^[\s\u0085\uFEFF]+|[\s\u0085\uFEFF]+$/g, '');
  const _reCache = new Map();
  function re(p, f) {
    const k = f + p;
    if (!_reCache.has(k)) {
      // Por constructor: un navegador sin lookbehind (Safari < 16.4) no puede tirar abajo el archivo entero.
      let r = null;
      try { r = new RegExp(p, f); } catch (_) { r = null; }
      _reCache.set(k, r);
    }
    return _reCache.get(k);
  }
  const quitarD = (p, s) => { const r = re(p, 'u'); return r ? s.replace(r, '') : s; };
  const INLINES = [
    '!?\\[([^\\]]+)\\]\\([^)\\s]+\\)',
    '\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*',
    '(?<![\\p{L}\\p{N}_])__(?=\\S)(.+?)(?<=\\S)__(?![\\p{L}\\p{N}_])',
    '~~(?=\\S)(.+?)(?<=\\S)~~',
    '(?<![\\p{L}\\p{N}_*])\\*(?=[^\\s*])(.+?)(?<=[^\\s*])\\*(?![\\p{L}\\p{N}_*])',
    '(?<![\\p{L}\\p{N}_])_(?=[^\\s_])(.+?)(?<=[^\\s_])_(?![\\p{L}\\p{N}_])',
    '`([^`\\n]+)`',
  ];
  function limpiarInlineD(s) {
    let t = s;
    for (const p of INLINES) { const r = re(p, 'gu'); if (r) t = t.replace(r, '$1'); }
    return recortarD(t);
  }
  const CITA = `^>(?!${ESP}*[0-9])${ESP}*`;
  const ENCAB = `^#{1,6}(?:${ESP}+|$)`;
  function tituloDeParte(t) {
    if (!t.startsWith('##') || /[\n\v\f\r\u0085\u2028\u2029]/.test(t) || !/^[\s\u0085\uFEFF]/.test(t.slice(2))) return null;
    return limpiarInlineD(recortarD(t.slice(2))) || null;
  }
  function limpiarParrafo(t) {
    let hayLista = false;
    const lineas = [];
    for (const cruda of t.split(/[\n\v\f\r\u0085\u2028\u2029]/)) {
      const s = quitarD(ENCAB, quitarD(CITA, recortarD(cruda)));
      const sep = re(`^([-*_])(?:${ESP}*\\1){2,}${ESP}*$`, 'u');
      if (sep && sep.test(s)) continue;
      const li = re(`^[-*+•]${ESP}+`, 'u');
      const m = li && s.match(li);
      if (m) {
        hayLista = true;
        const resto = s.slice(m[0].length);
        if (recortarD(resto)) lineas.push('• ' + resto);
      } else if (recortarD(s)) lineas.push(s);
    }
    if (!lineas.length) return null;
    // Sin lista, el párrafo entero: una marca puede abrir en una línea y cerrar en la otra.
    const limpio = hayLista ? lineas.map(limpiarInlineD).filter(Boolean).join('\n') : limpiarInlineD(lineas.join(' '));
    return limpio || null;
  }
  const RD = {
    TITULO_BLOQUE: 'Lo que más te importa',
    TITULO_VIDEOS: 'Tus videos sobre esto',
    esBloqueDolor: t => recortarD(t || '').toLowerCase().replace(/á/g, 'a') === 'lo que mas te importa',
    vista(dolor) {
      if (!dolor || !recortarD(dolor.texto || '')) return null;
      const principal = [], partes = [];
      const corte = re(`\\r?\\n${ESP}*?\\n`, 'u');
      for (const crudo of dolor.texto.split(corte)) {
        const t = recortarD(crudo);
        const titulo = tituloDeParte(t);
        if (titulo) { partes.push({ titulo, parrafos: [] }); continue; }
        const p = limpiarParrafo(t);
        if (p) (partes.length ? partes[partes.length - 1].parrafos : principal).push(p);
      }
      // Lo que había era solo markup: es lo mismo que vacío.
      if (!principal.length && !partes.length) return null;
      const st = dolor.titulo != null ? limpiarInlineD(quitarD(ENCAB, recortarD(dolor.titulo))) : '';
      return { subtitulo: !st || RD.esBloqueDolor(st) ? null : st, parrafos: principal, partes };
    },
    // Qué capítulo va en cada recuadro y cuáles siguen en la lista de siempre.
    reparto(bloques, v) {
      if (!v) return { principal: null, partes: [], resto: bloques };
      const usados = new Set();
      const tomar = cumple => {
        const b = bloques.find(x => !x.novedad && !usados.has(x.id) && cumple(x));
        if (!b) return null;
        usados.add(b.id);
        return b;
      };
      const principal = tomar(b => RD.esBloqueDolor(b.titulo));
      const partes = v.partes.map(p => tomar(b => b.titulo === p.titulo));
      return { principal, partes, resto: bloques.filter(b => !usados.has(b.id)) };
    },
    // Los videos del recuadro van primero también en el reproductor. Los `nuevo` no pasan por acá.
    conDolorPrimero(clips, dolor) {
      const v = RD.vista(dolor);
      if (!v) return clips;
      const rango = c => {
        const t = R.claveBloque(c);
        if (RD.esBloqueDolor(t)) return 0;
        const i = v.partes.findIndex(p => p.titulo === t);
        return i >= 0 ? i + 1 : Infinity;
      };
      return clips.map((c, i) => [c, i, rango(c)])
        .sort((a, b) => (a[2] !== b[2] ? (a[2] < b[2] ? -1 : 1) : a[1] - b[1])).map(x => x[0]);
    },
    // La línea y los pasos de arriba: solo con `dolor` y antes de la videollamada.
    introduccion(g, hayDudas, ahora) {
      if (!g || !RD.vista(g.dolor) || R.yaPaso(g.fechaEntrega, ahora)) return null;
      const f = R.fechaLlamada(g.fechaEntrega);
      const l = R.deLaLista(g);
      const vistos = l.length > 0 && l.every(c => c.visto);
      return {
        texto: `Antes de nuestra videollamada${f ? ` del ${f}` : ''}, hacé estos dos pasos.`,
        pasos: [
          { id: 'videos', numero: 1, titulo: 'Mirá tus videos', estado: vistos ? 'hecho' : 'ahora' },
          { id: 'dudas', numero: 2, titulo: 'Dejá tus dudas', estado: hayDudas ? 'hecho' : 'pendiente' },
        ],
      };
    },
    textoHablado(p, total) {
      return `Paso ${p.numero} de ${total}, ${p.titulo}${p.estado === 'hecho' ? ', hecho' : p.estado === 'ahora' ? ', es el que sigue' : ''}`;
    },
  };

  function normalizarGuia(j) {
    if (!esObjeto(j)) {
      return { ok: false, nombrePila: null, fechaEntrega: null, clips: [], dudasLlamada: [], suplementacion: null, fase: 1, novedadEn: null };
    }
    return {
      ok: booleano(j.ok) || false,
      nombrePila: texto(j.nombre_pila),
      fechaEntrega: texto(j.fecha_entrega),
      clips: lista(j.clips).map(normalizarClip).filter(Boolean),
      dudasLlamada: lista(j.dudas_llamada).map(normalizarDudaLlamada).filter(d => d && d.texto !== ''),
      suplementacion: normalizarSuplementacion(j.suplementacion),
      // Lo de la 2.2.0, todo opcional: sin los campos (servidor viejo), la guía es la de la 2.1.0.
      fase: entero(j.fase) === 2 ? 2 : 1,
      novedadEn: textoRecortado(j.novedad_en),
      // Lo de la 2.3.0: apagado por la palanca web_230 hasta que se abra; sin el campo, la guía de siempre.
      dolor: typeof raiz.web230 === 'function' && !raiz.web230() ? null : leerDolor(j.dolor),
    };
  }

  // Lo que devuelve entregas_app_resumen (entregas_011, 014 y 021).
  function normalizarResumen(j) {
    if (!esObjeto(j)) {
      return { ok: false, total: 0, vistos: 0, minutosRestantes: 0, fechaEntrega: null, mostrarTarjetaServidor: null,
               novedadEn: null, reserva: null, nuevosTotal: null, nuevosVistos: null };
    }
    const ok = booleano(j.ok) || false;
    const total = Math.max(0, entero(j.total) || 0);
    const m = decimal(j.minutos_restantes) || 0;
    const f = texto(j.fecha_entrega);
    const ntc = ok ? entero(j.nuevos_total) : null;
    const nt = ntc == null ? null : Math.max(0, ntc);
    return {
      ok,
      total,
      vistos: Math.min(Math.max(0, entero(j.vistos) || 0), total),
      minutosRestantes: m > 0 ? m : 0,
      fechaEntrega: f && f.trim() ? f : null,
      // Se lee primero ok: con false no hay tarjeta ni fila, venga lo que venga.
      mostrarTarjetaServidor: ok ? booleano(j.mostrar_tarjeta) : null,
      // 2.2.0, opcionales: la tanda nueva (hace volver la tarjeta ocultada), la
      // reserva de la entrega (el «Entrar» de Entreno sin pedir el get) y el
      // avance de lo nuevo (la tarjeta «NOVEDAD EN TU GUÍA»).
      novedadEn: ok ? textoRecortado(j.novedad_en) : null,
      reserva: ok ? normalizarReserva(j.reserva) : null,
      nuevosTotal: nt,
      nuevosVistos: nt == null ? null : (entero(j.nuevos_vistos) == null ? null : Math.min(Math.max(0, entero(j.nuevos_vistos)), nt)),
    };
  }

  // ─── La agenda de la entrega (MyPumpModelos/Agenda.swift) ───────
  // entregas_app_agenda → {ok, autorizada, habilitada, faltan, zona, franjas,
  // reserva, aviso_min, textos}. Todo tolerante: una franja rota se descarta,
  // no la agenda.
  const ESTADOS_RESERVA = ['pendiente', 'confirmada', 'fallo'];
  // De comienzo o de revisión (videollamada 2.3.0). Sin el campo, o con uno
  // que no se conoce, es la de comienzo (la única que existía).
  const tipoVideollamada = v => ((texto(v) || '').trim().toLowerCase() === 'revision' ? 'revision' : 'comienzo');
  // Si la reserva se puede cambiar desde la app (`cambio` de la agenda). Sin el objeto, no.
  function normalizarCambio(o) {
    if (!esObjeto(o)) return null;
    const n = entero(o.restantes);
    return {
      permitido: booleano(o.permitido) || false,
      restantes: n == null ? null : Math.max(0, n),
      hasta: textoRecortado(o.hasta),
    };
  }

  // Un horario libre. Sin id no se puede reservar; sin horas no se puede mostrar.
  function normalizarFranja(o) {
    if (!esObjeto(o)) return null;
    const id = (texto(o.id) || '').trim(), inicio = (texto(o.inicio) || '').trim(), fin = (texto(o.fin) || '').trim();
    return id && inicio && fin ? { id, inicio, fin } : null;
  }

  // La reserva: pendiente, confirmada o fallo. Un estado que no se conoce (uno
  // futuro, como «realizada») no se adivina: la reserva no se muestra.
  function normalizarReserva(o) {
    if (!esObjeto(o)) return null;
    const inicio = (texto(o.inicio) || '').trim(), fin = (texto(o.fin) || '').trim();
    const estado = (texto(o.estado) || '').trim().toLowerCase();
    if (!inicio || !fin || !ESTADOS_RESERVA.includes(estado)) return null;
    // Solo https con host (lo que no lo es no se abre).
    let meetUrl = null;
    const u = (texto(o.meet_url) || '').trim();
    try { const x = new URL(u); if (x.protocol === 'https:' && x.hostname) meetUrl = x.href; } catch (_) { /* no es un link */ }
    return {
      id: noVacio(texto(o.id)),
      inicio, fin, estado, meetUrl,
      motivo: noVacio(texto(o.motivo)),
      salaAbiertaEn: textoRecortado(o.sala_abierta_en),
      tipo: tipoVideollamada(o.tipo),
    };
  }
  // El p_id de la reserva (como las dudas y los audios): solo un uuid.
  const esUuid = s => typeof s === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
  const reservaVigente = r => !!r && (r.estado === 'pendiente' || r.estado === 'confirmada');

  function normalizarAgenda(j) {
    const nada = { ok: false, motivo: null, autorizada: false, habilitada: false, faltan: null, zona: null, franjas: [],
                   reserva: null, avisoMin: null, textos: {}, tipo: 'comienzo', cambio: null, entrarDesdeMin: null };
    if (!esObjeto(j)) return nada;
    const autorizada = booleano(j.autorizada) || false;
    // Sin autorización no hay agenda habilitada, diga lo que diga el campo.
    const habilitada = autorizada && (booleano(j.habilitada) || false);
    const reserva = normalizarReserva(j.reserva);
    const f = entero(j.faltan);
    const aviso = entero(j.aviso_min);
    const cambio = normalizarCambio(j.cambio);
    const desde = entero(j.entrar_desde_min);
    // Con una reserva vigente, las franjas solo valen si el servidor deja
    // cambiarla (`cambio.permitido`): son los horarios para el cambio.
    const paraCambio = !!reserva && reserva.estado === 'confirmada' && !!cambio && cambio.permitido;
    const vistas = new Set();
    const textos = {};
    if (esObjeto(j.textos)) {
      for (const [k, v] of Object.entries(j.textos)) if (typeof v === 'string' && v.trim()) textos[k] = v;
    }
    return {
      ok: booleano(j.ok) || false,
      motivo: texto(j.motivo),
      autorizada, habilitada,
      faltan: f == null ? null : Math.max(0, f),
      zona: noVacio(texto(j.zona)),
      // Las franjas solo valen con la agenda habilitada y sin una reserva vigente (o para el cambio).
      franjas: habilitada && (!reservaVigente(reserva) || paraCambio)
        ? lista(j.franjas).map(normalizarFranja).filter(x => x && !vistas.has(x.id) && vistas.add(x.id))
        : [],
      reserva,
      // Hasta un día antes; lo que no tiene sentido queda en los 30 de la app.
      avisoMin: aviso != null && aviso >= 0 && aviso <= 1440 ? aviso : null,
      textos,
      tipo: tipoVideollamada(j.tipo),
      cambio,
      // Desde cuántos minutos antes se habilita «Entrar» (1 a 60; si no, los 10 de la app).
      entrarDesdeMin: desde != null && desde >= 1 && desde <= 60 ? desde : null,
    };
  }

  // ─── Reglas (MyPumpReglas/Guia.swift) ───────────────────────────
  const MOMENTOS = [
    ['despertar', 'Al despertar'], ['ayunas', 'En ayunas'], ['desayuno', 'Desayuno'], ['media_manana', 'Media mañana'],
    ['almuerzo', 'Almuerzo'], ['merienda', 'Merienda'], ['pre', 'Antes de entrenar'], ['intra', 'Mientras entrenás'],
    ['post', 'Después de entrenar'], ['cena', 'Cena'], ['dormir', 'Antes de dormir'], ['noche', 'Si te despertás de noche'],
  ];
  const NOMBRES_MOMENTOS = Object.fromEntries(MOMENTOS);

  function mayuscula(s) {
    const t = (s || '').trim();
    if (!t) return null;
    const cs = Array.from(t);
    return cs[0].toUpperCase() + cs.slice(1).join('');
  }

  function diaBA(d) {
    const p = new Intl.DateTimeFormat('en-CA', { timeZone: ZONA_BA, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(d);
    const v = k => (p.find(x => x.type === k) || {}).value;
    return `${v('year')}-${v('month')}-${v('day')}`;
  }

  const R = {
    esBloqueApp: b => (b || '').trim().toLowerCase() === 'tu app',

    ordenados(clips) {
      return clips.filter(c => R.esBloqueApp(c.bloque)).concat(clips.filter(c => !R.esBloqueApp(c.bloque)));
    },

    // «Tu suplementación» como el regex de entregas_012, carácter por carácter
    // (una ó descompuesta no es la ó del regex).
    esBloqueSuplementacion(bloque) {
      if (bloque == null) return false;
      const e = Array.from(trimServidor(bloque));
      const base = Array.from('tu suplementaci');
      if (e.length !== base.length + 2) return false;
      for (let i = 0; i < base.length; i++) if (e[i].toLowerCase() !== base[i]) return false;
      const o = e[base.length];
      if (!(o === 'o' || o === 'O' || o === '\u00f3' || o === '\u00d3')) return false;
      return e[base.length + 1] === 'n' || e[base.length + 1] === 'N';
    },

    nombradoPor(it) {
      return it.nombre !== '' && it.estado !== 'sale' && it.videoId ? it.videoId : null;
    },

    nombradosPorSuplementos(s) {
      return new Set(((s && s.items) || []).map(R.nombradoPor).filter(Boolean));
    },

    // Los de la lista, de «Viste X de N» y del reproductor: los del bloque
    // «Tu suplementación» que nombra un suplemento se ven solo debajo de él.
    // 2.2.0: los `nuevo` van primero, en el orden del servidor (el bloque
    // «Novedad»); después, los de siempre. Sin ningún `nuevo`, el orden de la 2.1.0.
    deLaLista(g) {
      if (!g) return [];
      const nombrados = R.nombradosPorSuplementos(g.suplementacion);
      const l = g.clips.filter(c => !(R.esBloqueSuplementacion(c.bloque) && nombrados.has(c.id)));
      return l.filter(c => c.nuevo).concat(RD.conDolorPrimero(R.ordenados(l.filter(c => !c.nuevo)), g.dolor));
    },

    clipDeSuplemento(g, videoId) {
      if (!videoId || !g) return null;
      const c = g.clips.find(x => x.id === videoId);
      return c && c.url ? c : null;
    },

    rotuloVerPorQue: c => `Ver por qué (${Math.max(1, Math.round(c.minutos * 60))} s)`,

    nombreBloque: c => ((c.bloque || '').trim() || 'Videos'),

    // La clave del bloque «Novedad» (no choca con un bloque del servidor que se llame igual).
    ID_NOVEDAD: '_novedad',
    // La clave del bloque de un clip: «Novedad» si es nuevo; si no, su bloque o «Videos».
    claveBloque: c => (c.nuevo ? R.ID_NOVEDAD : R.nombreBloque(c)),

    // Agrupa por bloque en el orden en que aparece cada uno. Los `nuevo` van
    // juntos en «Novedad» (2.2.0).
    bloques(clips) {
      const claves = [];
      const indices = new Map();
      clips.forEach((c, i) => {
        const t = R.claveBloque(c);
        if (!indices.has(t)) { claves.push(t); indices.set(t, []); }
        indices.get(t).push(i);
      });
      return claves.map(t => {
        const ix = indices.get(t);
        const minutos = ix.reduce((a, i) => a + clips[i].minutos, 0);
        const novedad = t === R.ID_NOVEDAD;
        return { id: t, titulo: novedad ? 'Novedad' : t, indices: ix, minutos, novedad, esApp: !novedad && R.esBloqueApp(t) };
      });
    },

    // «4 videos, unos 2 minutos». El de «Novedad»: «3 videos nuevos para vos · 9 min».
    textoBloque(b) {
      const n = b.indices.length;
      const m = Math.max(1, Math.round(b.minutos));
      if (b.novedad) return `${n} ${n === 1 ? 'video nuevo' : 'videos nuevos'} para vos · ${m} min`;
      return `${n} ${n === 1 ? 'video' : 'videos'}, ${R.unos(m, false)}`;
    },

    // «unos 12 minutos» / «unos 12 min»; con 1, «1 minuto» / «1 min» (nunca «unos 1 minutos»).
    unos: (m, corto) => (m === 1 ? (corto ? '1 min' : '1 minuto') : `unos ${m} ${corto ? 'min' : 'minutos'}`),
    // «te quedan 12 min» / «te queda 1 min».
    teQuedan: (m, corto) => (m === 1 ? `te queda 1 ${corto ? 'min' : 'minuto'}` : `te quedan ${m} ${corto ? 'min' : 'minutos'}`),

    duracion(minutos) {
      const s = Math.round(minutos * 60);
      return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
    },

    duracionHablada(minutos) {
      const s = Math.round(minutos * 60);
      const m = Math.floor(s / 60), r = s % 60;
      const partes = [];
      if (m > 0) partes.push(m === 1 ? '1 minuto' : `${m} minutos`);
      if (r > 0 || m === 0) partes.push(r === 1 ? '1 segundo' : `${r} segundos`);
      return partes.join(' y ');
    },

    avance(clips) {
      return {
        total: clips.length,
        vistos: clips.filter(c => c.visto).length,
        minutosRestantes: clips.filter(c => !c.visto).reduce((a, c) => a + c.minutos, 0),
      };
    },
    completo: a => a.total > 0 && a.vistos >= a.total,
    fraccion: a => (a.total > 0 ? Math.min(1, a.vistos / a.total) : 0),

    textoAvance(a) {
      if (R.completo(a)) return 'Viste todos, nos vemos en la videollamada';
      const m = Math.max(1, Math.round(a.minutosRestantes));
      return `Viste ${a.vistos} de ${a.total}, ${m === 1 ? 'te queda 1 minuto' : `te quedan unos ${m} minutos`}`;
    },

    textoTarjeta(a) {
      if (R.completo(a)) return a.total === 1 ? 'Viste el video' : `Viste los ${a.total} videos`;
      const min = Math.max(1, Math.round(a.minutosRestantes));
      if (a.vistos === 0) return `${a.total} ${a.total === 1 ? 'video corto' : 'videos cortos'}, ${R.unos(min, true)}`;
      return `${a.vistos} de ${a.total} videos, ${R.teQuedan(min, true)}`;
    },

    botonTarjeta: a => (a.vistos === 0 ? 'Ver mi guía' : 'Seguir viendo'),

    // ── Novedad (2.2.0, fase 2 de la guía) ──
    // El avance de la tarjeta «NOVEDAD EN TU GUÍA»: con `novedad_en` (del
    // resumen o de la copia) y algún nuevo sin ver, cuenta solo los nuevos.
    // null = la tarjeta de la 2.1.0 tal cual. Si la copia todavía no sabe de
    // esa tanda (la tarjeta nunca pide el get), cuenta con el resumen mientras
    // falte algo: la tanda nueva es lo que falta.
    avanceNovedad(r, guia) {
      const n = (r && r.novedadEn) || (guia && guia.novedadEn) || null;
      if (!n) return null;
      const nuevos = R.deLaLista(guia).filter(c => c.nuevo);
      const deLaCopia = guia ? guia.novedadEn || null : null;
      const rNovedad = r ? r.novedadEn || null : null;
      if (r && r.ok && r.nuevosTotal != null && r.nuevosVistos != null) {
        const t = r.nuevosTotal, v = r.nuevosVistos;
        if (!(t > 0 && v < t)) return null;
        const copiaAlDia = nuevos.length > 0 && (deLaCopia === n || rNovedad == null);
        const min = copiaAlDia ? nuevos.filter(c => !c.visto).reduce((a, c) => a + c.minutos, 0) : r.minutosRestantes;
        return { total: t, vistos: v, minutosRestantes: min };
      }
      if (nuevos.length && (deLaCopia === n || rNovedad == null)) {
        const a = R.avance(nuevos);
        return R.completo(a) ? null : a;
      }
      if (guia && deLaCopia === n) return null;   // la copia está al día y no trae nuevos
      if (!(r && r.ok && r.total > 0 && r.vistos < r.total)) return null;
      return { total: r.total, vistos: r.vistos, minutosRestantes: r.minutosRestantes };
    },

    // «2 videos nuevos, unos 3 min» o «1 de 2 videos nuevos, te quedan 2 min».
    textoTarjetaNovedad(a) {
      const min = Math.max(1, Math.round(a.minutosRestantes));
      if (a.vistos === 0) return `${a.total} ${a.total === 1 ? 'video nuevo' : 'videos nuevos'}, ${R.unos(min, true)}`;
      return `${a.vistos} de ${a.total} videos nuevos, ${R.teQuedan(min, true)}`;
    },

    // La marca de «Ocultar» sigue valiendo: sin `novedad_en`, como en la
    // 2.1.0. Con una novedad posterior a la marca (o una marca de antes de la
    // 2.2.0, sin fecha), la tarjeta vuelve. `marca`: Date o null.
    quitadaVigente(quitada, marca, novedadEn) {
      if (!quitada) return false;
      const d = novedadEn ? R.instante(novedadEn) : null;
      if (!d) return true;
      if (!marca) return false;
      return d.getTime() <= marca.getTime();
    },

    // ── La tarjeta de la novedad: grande o en fila (2.3.0, TarjetaGuiaDestacada.vaEnFila) ──
    // Cuántos días va grande una novedad antes de pasar a la fila.
    DIAS_GRANDE: 7,
    // La tarjeta va GRANDE siempre que haya riesgo de que la pasen por alto, y en fila solo cuando se cumplen las dos:
    // · ya terminó la guía de base (lo único sin ver es la tanda nueva), y
    // · la novedad lleva más de DIAS_GRANDE días publicada (`novedad_en`, la fecha del servidor: vale igual en todos
    //   sus dispositivos y no se reinicia al reinstalar).
    // Sin fecha legible, grande. La primera vez («Empezá por acá», sin novedad) nunca pasa por acá: es siempre grande.
    // `n`: el avance de la novedad; `a`: el de toda la guía; `ahora`: Date.
    vaEnFila(n, a, novedadEn, ahora) {
      if (!n || !a) return false;
      const baseCompleta = (a.total - a.vistos) <= (n.total - n.vistos);
      const desde = novedadEn ? R.instante(novedadEn) : null;
      if (!baseCompleta || !desde || !(ahora instanceof Date) || isNaN(ahora.getTime())) return false;
      return ahora.getTime() - desde.getTime() > R.DIAS_GRANDE * 86400000;
    },

    mostrarBienvenida(r, yaVista, quitada, ahora) {
      if (yaVista || !r || r.vistos !== 0) return false;
      return R.tarjetaEnEntreno(r, quitada, ahora);
    },

    tituloBienvenida(nombrePila, nombreCuenta) {
      let n = (nombrePila || '').trim();
      if (!n) n = ((nombreCuenta || '').trim().split(/\s+/)[0]) || '';
      return n ? `Hola ${n}` : 'Hola';
    },

    textoBienvenida(a) {
      const min = Math.max(1, Math.round(a.minutosRestantes));
      const cuantos = a.total === 1 ? `Es un video corto que armé para vos, de ${R.unos(min, true)}.`
                                    : `Son ${a.total} videos cortos que armé para vos, ${R.unos(min, true)}.`;
      return `Antes de empezar, mirá tu guía. ${cuantos} Así en la videollamada vamos directo a lo tuyo.`;
    },

    // «indicación ||| motivo»: la indicación es «Qué hacer» y el motivo, «Para qué».
    partes(motivo) {
      const m = motivo || '';
      const i = m.indexOf('|||');
      if (i < 0) return { hacer: '', paraQue: m.trim() };
      return { hacer: m.slice(0, i).trim(), paraQue: m.slice(i + 3).trim() };
    },

    // Un instante del servidor: ISO con zona (con «T» o con espacio, como lo
    // escribe Postgres). Solo la fecha cuenta desde el principio de ese día en
    // Buenos Aires.
    instante(s) {
      let t = String(s || '').trim();
      if (!t) return null;
      if (t.length === 10) t += 'T00:00:00-03:00';
      if (t.length > 10 && t[10] === ' ') t = t.slice(0, 10) + 'T' + t.slice(11);
      t = t.replace(/\.(\d+)/, (_, f) => '.' + (f + '000').slice(0, 3));
      if (/[+-]\d{2}$/.test(t)) t += ':00';
      if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})$/.test(t)) return null;
      const d = new Date(t);
      return isNaN(d.getTime()) ? null : d;
    },

    // ¿Ya pasó la videollamada? Con hora, contra este instante; solo la fecha,
    // contra hoy en Buenos Aires.
    yaPaso(fecha, ahora) {
      const f = (fecha || '').trim();
      if (!f) return false;
      const now = ahora || new Date();
      if (f.length > 10) { const d = R.instante(f); return d ? d < now : false; }
      return f.slice(0, 10) < diaBA(now);
    },

    // «miércoles 4/11», en la hora de Buenos Aires.
    fechaLlamada(fecha) {
      if (!fecha) return null;
      const d = R.instante(fecha) || R.instante(String(fecha).slice(0, 10) + 'T12:00:00-03:00');
      if (!d) return null;
      const dia = new Intl.DateTimeFormat('es-AR', { timeZone: ZONA_BA, weekday: 'long' }).format(d);
      const p = new Intl.DateTimeFormat('en-US', { timeZone: ZONA_BA, day: 'numeric', month: 'numeric' }).formatToParts(d);
      const v = k => (p.find(x => x.type === k) || {}).value;
      return `${dia} ${v('day')}/${v('month')}`;
    },

    textoParaMandar(s) {
      const t = String(s || '').trim();
      if (!t || largo(t) > MAX_TEXTO) return null;
      return t;
    },

    renglones: duda => String(duda || '').split('\n').filter(x => x !== ''),

    // Cuántas veces está una duda en lo que trajo el servidor para un video.
    veces(textoDuda, duda) {
      if (!duda || !textoDuda) return 0;
      const todo = duda.split('\n'), buscado = textoDuda.split('\n');
      if (buscado.length > todo.length) return 0;
      let n = 0, i = 0;
      while (i + buscado.length <= todo.length) {
        let igual = true;
        for (let k = 0; k < buscado.length; k++) if (todo[i + k] !== buscado[k]) { igual = false; break; }
        if (igual) { n++; i += buscado.length; } else i++;
      }
      return n;
    },
    vecesLlamada: (t, dudas) => dudas.filter(d => d.texto === t).length,

    // `*negrita*` del PDF en tramos.
    negritas(s) {
      const out = [];
      let resto = String(s || '');
      for (;;) {
        const a = resto.indexOf('*');
        if (a < 0) break;
        const b = resto.indexOf('*', a + 1);
        if (b < 0 || b === a + 1) break;
        if (a > 0) out.push({ texto: resto.slice(0, a), negrita: false });
        out.push({ texto: resto.slice(a + 1, b), negrita: true });
        resto = resto.slice(b + 1);
      }
      if (resto) out.push({ texto: resto, negrita: false });
      return out;
    },

    inicial(clips) {
      let i = clips.findIndex(c => !c.visto && c.url);
      if (i < 0) i = clips.findIndex(c => c.url);
      return i < 0 ? null : i;
    },
    siguiente(clips, i) {
      for (let k = i + 1; k < clips.length; k++) if (clips[k].url) return k;
      return null;
    },
    anterior(clips, i) {
      if (i <= 0 || i > clips.length) return null;
      for (let k = i - 1; k >= 0; k--) if (clips[k].url) return k;
      return null;
    },

    // Retoma si no está visto y quedó entre el segundo 5 y 5 segundos antes del final.
    retomar(clip, duracion) {
      if (clip.visto || !isFinite(duracion) || duracion <= 0) return null;
      const s = clip.segundos;
      return s > 5 && s < duracion - 5 ? s : null;
    },
    estaAlFinal: (t, d) => isFinite(t) && isFinite(d) && d > 0 && t >= d - 0.5,

    velocidadSiguiente: v => (v < 1.1 ? 1.25 : v < 1.4 ? 1.5 : 1),
    textoVelocidad: v => `${String(v).replace('.', ',')}x`,
    textoPlaca: (i, total) => `Otro tema · Video ${i + 1} de ${total}`,
    textoNumero(i, total, bloque) {
      return `Video ${i + 1} de ${total}` + (bloque ? ` · ${bloque}` : '');
    },

    // mostrar_tarjeta con la regla de entregas_014.
    mostrarTarjeta(r, ahora) {
      if (!r || !r.ok) return false;
      if (r.mostrarTarjetaServidor != null) return r.mostrarTarjetaServidor;
      const d = r.fechaEntrega ? R.instante(r.fechaEntrega) : null;
      if (!d) return true;
      return (ahora || new Date()).getTime() < d.getTime() + HORAS_TARJETA * 3600 * 1000;
    },
    hayGuia: r => !!(r && r.ok && r.total > 0),
    tarjetaEnEntreno: (r, quitada, ahora) => R.hayGuia(r) && !quitada && R.mostrarTarjeta(r, ahora),
    filaEnMisDatos: (r, quitada, ahora) => !!(r && r.ok) && !R.tarjetaEnEntreno(r, quitada, ahora),
    puedeVolverAMostrar: (r, quitada, ahora) => !!quitada && R.tarjetaEnEntreno(r, false, ahora),

    // ── «Tu inicio con Mati» (simplificar, OK de Mati del 11/11; va con la palanca web_230) ──
    // Con todo visto, «Tu guía» queda como una fila discreta dentro de «Tu inicio con Mati» durante estos días desde que
    // se terminó; después sale de Entreno y queda en Mis datos («Ver mi guía»). Igual que ReglasGuia de iPhone y Android.
    DIAS_FILA_COMPLETA: 7,
    // La guía está terminada: todo visto y sin una tanda nueva sin ver. `novedad`: el avance de lo nuevo, o null.
    completa: (a, novedad) => !novedad && !!a && R.completo(a),
    // La fila discreta sigue: sin fecha (todavía no se anotó) o dentro de los 7 días. `completaEn`, `ahora`: Date.
    filaInicioVigente(completaEn, ahora) {
      if (!(completaEn instanceof Date) || isNaN(completaEn.getTime())) return true;
      const t = ahora instanceof Date && !isNaN(ahora.getTime()) ? ahora.getTime() : Date.now();
      return t - completaEn.getTime() < R.DIAS_FILA_COMPLETA * 86400000;
    },
  };

  // Cuándo guarda el avance un video que se está reproduciendo (AvanceVideo):
  // cada 10 s de diferencia con lo último guardado y al pasar el 80 % (ahí
  // con visto); al terminar; y al salir a mitad de video.
  const segundosGuardar = t => Math.trunc(Math.min(MAX_SEGUNDOS, Math.max(0, Math.round(t))));
  class AvanceVideo {
    constructor(visto, desde) {
      this.visto = !!visto;
      this.ultimo = isFinite(desde) ? Math.max(0, desde) : 0;
    }
    alAvanzar(t, duracion) {
      if (!isFinite(t) || t < 0) return null;
      const pasa80 = isFinite(duracion) && duracion > 0 && t / duracion >= 0.8;
      if (!(Math.abs(t - this.ultimo) >= 10 || (pasa80 && !this.visto))) return null;
      this.ultimo = t;
      if (pasa80) this.visto = true;
      return { segundos: segundosGuardar(t), visto: this.visto };
    }
    alTerminar(duracion) {
      this.visto = true;
      const d = isFinite(duracion) && duracion > 0 ? duracion : this.ultimo;
      this.ultimo = d;
      return { segundos: segundosGuardar(d), visto: true };
    }
    alSalir(t) {
      if (!isFinite(t) || t <= this.ultimo + 1) return null;
      this.ultimo = t;
      return { segundos: segundosGuardar(t), visto: this.visto };
    }
  }

  // «Tu suplementación» como «Tu día» del PDF (VistaSuplementacion).
  function tituloMomento(m, definido) {
    return (definido && noVacio(definido.nombre)) || NOMBRES_MOMENTOS[m] || mayuscula(m.replace(/_/g, ' ')) || m;
  }
  function vistaSuplementacion(s) {
    if (!s || !s.items.length) return null;
    const def = new Map();
    for (const m of s.dia) if (!def.has(m.id)) def.set(m.id, m);
    const tomas = new Map();
    const ordenAparicion = [], sueltos = [], sale = [];
    s.items.forEach((it, i) => {
      if (it.estado === 'sale') { sale.push({ nombre: it.nombre, porQue: it.porQue, detalle: it.detalle, item: i }); return; }
      let ts = null;
      if (it.tomas.length) ts = it.tomas.map(t => ({ item: i, nombre: t.nombre, cantidad: t.cantidad, nota: t.nota }));
      else if (it.momento) ts = [{ item: i, nombre: null, cantidad: it.cantidad, nota: it.nota }];
      if (!ts) { sueltos.push({ item: i, nombre: null, cantidad: it.cantidad, nota: it.nota }); return; }
      const momentos = it.tomas.length ? it.tomas.map(t => t.momento || '') : [it.momento || ''];
      ts.forEach((t, k) => {
        const m = momentos[k];
        if (!tomas.has(m)) { tomas.set(m, []); ordenAparicion.push(m); }
        tomas.get(m).push(t);
      });
    });
    let orden = s.dia.map(m => m.id);
    for (const [m] of MOMENTOS) if (tomas.has(m) && !orden.includes(m)) orden.push(m);
    for (const m of ordenAparicion) if (!orden.includes(m)) orden.push(m);
    if (!s.dia.length) {
      const pos = m => { const p = MOMENTOS.findIndex(x => x[0] === m); return p < 0 ? 98 : p; };
      orden = orden.map((m, o) => [m, o]).sort((a, b) => pos(a[0]) - pos(b[0]) || a[1] - b[1]).map(x => x[0]);
    }
    const vistos = new Set();
    const fila = (t, n, momento) => {
      const it = s.items[t.item];
      const primera = !vistos.has(t.item);
      vistos.add(t.item);
      return {
        id: `${momento}-${t.item}-${n}`,
        nombre: noVacio(t.nombre) || it.nombre,
        cantidad: noVacio(t.cantidad),
        nota: mayuscula(t.nota),
        nuevo: it.estado === 'nuevo',
        opcional: it.opcional,
        // El «por qué», el detalle y «Ver por qué» van solo en la primera toma.
        porQue: primera ? it.porQue : null,
        detalle: primera ? it.detalle : [],
        videoId: primera ? it.videoId : null,
        item: t.item,
      };
    };
    const grupos = [];
    for (const m of orden) {
      const ts = tomas.get(m);
      if (!ts) continue;
      grupos.push({ id: m, titulo: tituloMomento(m, def.get(m)), filas: ts.map((t, n) => fila(t, n, m)) });
    }
    if (sueltos.length) grupos.push({ id: '_ademas', titulo: 'Además', filas: sueltos.map((t, n) => fila(t, n, '_ademas')) });
    return { titulo: noVacio(s.titulo) || 'Tu suplementación', accion: s.accion, momentos: grupos, sigue: s.sigueTexto, sale };
  }

  // ─── Fechas en una zona (la del teléfono o la de Argentina) ─────
  // `zona`: un nombre IANA, o undefined para la del teléfono.
  const formatos = new Map();
  function formato(loc, zona, op) {
    const k = loc + '|' + (zona || '') + '|' + JSON.stringify(op);
    let f = formatos.get(k);
    if (!f) { f = new Intl.DateTimeFormat(loc, zona ? Object.assign({ timeZone: zona }, op) : op); formatos.set(k, f); }
    return f;
  }
  function partesDe(d, zona, loc, op) {
    const o = {};
    for (const p of formato(loc, zona, op).formatToParts(d)) o[p.type] = p.value;
    return o;
  }
  // Minutos que esa zona le suma a UTC en ese instante.
  function desfase(d, zona) {
    const p = partesDe(d, zona, 'en-US', { year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric', hourCycle: 'h23' });
    const enZona = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24, +p.minute, +p.second);
    return Math.round((enZona - Math.floor(d.getTime() / 1000) * 1000) / 60000);
  }

  // ─── Videos obligatorios y agenda (MyPumpReglas/Agenda.swift) ───
  // La app no calcula franjas: las muestra en la hora del teléfono, agrupadas
  // por día, y decide qué tarjeta va según lo que dijo el servidor.
  const TEXTO_AVISO = {
    tomada: 'Ese horario se ocupó recién, elegí otro.',
    vencida: 'Ese horario ya no está disponible, elegí otro.',
    error: 'No pudimos reservar ese horario, elegí otro.',
    demo: 'En la demo no se crea ninguna videollamada.',
    sinCambio: 'Ese cambio ya no se puede hacer desde la app. Escribinos por el chat.',
  };
  const CLAVES_TEXTOS = ['bloqueada', 'no_autorizada', 'titulo', 'encabezado', 'confirmar', 'pendiente', 'confirmada',
    'hoy_sin_sala', 'sala_abierta', 'fallo', 'sin_franjas', 'cambiar', 'entreno_aviso'];

  const RA = {
    MINUTOS_ANTES_ENTRAR: 30,   // la tarjeta de la entrega en Entreno, desde 30 min antes
    SALA_CADA_MS: 30000,        // en la franja, sin la sala abierta: la agenda cada 30 s
    SONDEO_CADA_MS: 5000,       // una reserva pendiente: cada 5 s…
    SONDEO_MAXIMO_MS: 60000,    // …durante 60 s (después, al volver a primer plano)
    ETIQUETA_OBLIGATORIO: 'Para ver antes de la videollamada',
    TEXTO_NO_AUTORIZADA: 'Cuando termines de ver todo te habilitamos la agenda.',
    TEXTO_SIN_FRANJAS: 'Ahora no hay horarios libres. Mirá de nuevo más tarde o escribinos por el chat.',
    TEXTO_RESERVANDO: 'Estamos reservando tu horario…',
    TEXTO_CAMBIAR: '¿Necesitás cambiarla? Escribinos por el chat.',
    TEXTO_ZONA_TELEFONO: 'Horario de tu teléfono',
    TEXTO_AVISO,
    CLAVES_TEXTOS,
    vigente: reservaVigente,

    // Los que cuentan para habilitar la agenda: los que traen `obligatorio:
    // true`. Si NINGÚN clip trae el campo (servidor viejo), todos los de la
    // lista que tienen url (como el resumen, sin los de los suplementos).
    obligatorios(g) {
      if (!g) return [];
      const l = R.deLaLista(g);
      if (g.clips.some(c => c.obligatorio != null)) return l.filter(c => c.obligatorio === true);
      return l.filter(c => c.url != null);
    },
    esObligatorio: (c, g) => RA.obligatorios(g).some(x => x.id === c.id),
    // `visto` ya incluye la tilde manual de la web.
    faltan: g => RA.obligatorios(g).filter(c => !c.visto).length,
    // El primero que falta, en el orden de la lista: el de «Ir al próximo video».
    primeroQueFalta: g => RA.obligatorios(g).find(c => !c.visto) || null,
    textoContador: n => (n === 1 ? 'Te falta 1 video para habilitar la agenda' : `Te faltan ${n} videos para habilitar la agenda`),

    // Qué se muestra. `faltanLocal`: lo que cuenta la guía en el teléfono, solo
    // de respaldo (si la agenda trae `faltan`, manda ese). `enCola`: hay una
    // reserva saliendo. `aviso`: lo último que dijo reservar.
    vista(a, faltanLocal, enCola, aviso) {
      if (!a || !a.ok) return { tipo: 'nada' };
      if (enCola) return { tipo: 'reservando' };
      const r = a.reserva;
      if (r && r.estado === 'confirmada') return { tipo: 'confirmada', reserva: r, aviso: aviso === 'demo' ? 'demo' : null };
      if (r && r.estado === 'pendiente') return { tipo: 'reservando' };
      const faltan = a.faltan != null ? a.faltan : (faltanLocal != null ? faltanLocal : 0);
      if (!a.autorizada) return { tipo: 'noAutorizada', faltan };
      if (!a.habilitada) return { tipo: 'bloqueada', faltan };
      const av = aviso || (r && r.estado === 'fallo' ? (r.motivo === 'tomada' ? 'tomada' : 'error') : null);
      return a.franjas.length ? { tipo: 'franjas', aviso: av } : { tipo: 'sinFranjas', aviso: av };
    },

    textoBloqueada(faltan) {
      return faltan > 0 ? `Cuando termines los videos de arriba se habilita la agenda. ${faltan === 1 ? 'Te falta 1' : `Te faltan ${faltan}`}.`
                        : 'Ya viste todo. Estamos habilitando tu agenda…';
    },

    // ── Horas ──
    hora(d, zona) { const p = partesDe(d, zona, 'en-GB', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }); return `${p.hour}:${p.minute}`; },
    diaLargo(d, zona) { const p = partesDe(d, zona, 'es-AR', { weekday: 'long', day: 'numeric', month: 'long' }); return `${p.weekday} ${p.day} de ${p.month}`; },
    diaCorto(d, zona) { const p = partesDe(d, zona, 'es-AR', { weekday: 'long', day: 'numeric' }); return `${p.weekday} ${p.day}`; },
    claveDia(d, zona) { const p = partesDe(d, zona, 'en-CA', { year: 'numeric', month: '2-digit', day: '2-digit' }); return `${p.year}-${p.month}-${p.day}`; },

    // Las franjas por día en la zona del teléfono, de la más temprana a la más
    // tardía. Las que no se entienden o ya empezaron (una copia vieja) no van.
    dias(franjas, zona, ahora) {
      const ya = ahora || new Date();
      const chips = [];
      for (const f of franjas || []) {
        const i = R.instante(f.inicio), fi = R.instante(f.fin);
        if (!i || !fi || !(fi > i) || !(i > ya)) continue;
        chips.push({ id: f.id, franja: f, inicio: i, fin: fi, texto: `${RA.hora(i, zona)} a ${RA.hora(fi, zona)}` });
      }
      chips.sort((a, b) => a.inicio - b.inicio);
      const orden = [], porDia = new Map();
      for (const c of chips) {
        const k = RA.claveDia(c.inicio, zona);
        if (!porDia.has(k)) { orden.push(k); porDia.set(k, []); }
        porDia.get(k).push(c);
      }
      return orden.map(k => ({ id: k, titulo: RA.diaLargo(porDia.get(k)[0].inicio, zona), chips: porDia.get(k) }));
    },

    // La zona del teléfono da otra hora que Argentina para alguna de estas fechas.
    difiereDeArgentina: (fechas, zona) => fechas.some(d => desfase(d, zona) !== desfase(d, ZONA_BA)),

    // Lo que va después de «Dura»: «unas 2 horas», «alrededor de 1 hora»,
    // «unos 45 minutos». A la media hora si pasa de 1 h; a los 15 min si no.
    duracion(inicio, fin) {
      const total = (fin - inicio) / 60000;
      if (!isFinite(total) || total <= 0) return null;
      if (total > 60) {
        const medias = Math.round(total / 30);
        const horas = Math.floor(medias / 2), media = medias % 2 === 1;
        if (horas === 1) return media ? 'alrededor de 1 hora y media' : 'alrededor de 1 hora';
        return `unas ${horas} horas${media ? ' y media' : ''}`;
      }
      const cuartos = Math.max(1, Math.round(total / 15));
      if (cuartos === 4) return 'alrededor de 1 hora';
      return `unos ${cuartos * 15} minutos`;
    },
    textoDuracion(inicio, fin) { const d = RA.duracion(inicio, fin); return d ? `Dura ${d}.` : null; },

    // «¿Confirmás tu videollamada de comienzo el jueves 12 a las 10:00? Dura
    // alrededor de 1 hora.» Si el teléfono está en otra zona, también la hora
    // de Argentina. La duración sale de la franja.
    textoConfirmar(c, zona, tipo) {
      const ar = RA.difiereDeArgentina([c.inicio], zona) ? ` (${RA.hora(c.inicio, ZONA_BA)} en Argentina)` : '';
      const dura = RA.textoDuracion(c.inicio, c.fin);
      return `¿Confirmás tu ${RA.nombre(tipo)} el ${RA.diaCorto(c.inicio, zona)} a las ${RA.hora(c.inicio, zona)}${ar}?${dura ? ' ' + dura : ''}`;
    },

    // El encabezado de las franjas, con la duración si todas duran lo mismo.
    textoElegir(chips) {
      const base = 'Elegí un horario para la videollamada.';
      const ds = new Set(chips.map(c => RA.textoDuracion(c.inicio, c.fin)));
      if (ds.size !== 1) return base;
      const d = ds.values().next().value;
      return d ? `${base} ${d}` : base;
    },

    // «Jueves 12 de noviembre, de 10:00 a 11:00» (sin dos puntos: regla de los textos del alumno).
    textoConfirmada(r, zona) {
      const i = R.instante(r.inicio), f = R.instante(r.fin);
      if (!i || !f) return null;
      return `${mayuscula(RA.diaLargo(i, zona))}, de ${RA.hora(i, zona)} a ${RA.hora(f, zona)}`;
    },

    // ── La videollamada (2.3.0): cómo se nombra, la tarjeta fija y la cuenta regresiva ──
    // Al alumno nunca se le dice «entrega»: «de comienzo» o «de revisión».
    nombre: t => (t === 'revision' ? 'videollamada de revisión' : 'videollamada de comienzo'),
    tituloTarjeta: t => `Tu ${RA.nombre(t)}`,
    // Desde cuántos minutos antes del inicio se habilita «Entrar» (Mati, 10/11:
    // Meet restringido, Mati lo admite y el alumno espera en la sala). El
    // servidor lo puede cambiar con `entrar_desde_min`.
    ENTRAR_DESDE_MIN: 10,
    TEXTO_DESDE_ACA: 'Vas a entrar a la videollamada desde acá.',
    TEXTO_ADMITE: 'Mati te admite en la sala. Si tarda un poco, esperá ahí sin salir.',
    // «¿Cómo entro?», en el orden en que pasan las cosas.
    AYUDA_ENTRAR: [
      'Tocás Entrar y se abre la reunión. Si te pide tu nombre, escribilo y tocá «Solicitar unirse».',
      'Mati te admite en la sala. Esperá ahí, no hace falta salir y volver a entrar.',
      'Si se abre Gmail o la portada de Meet, copiá el código de la reunión, que aparece junto a Entrar, y pegalo en «Unirse con un código».',
      'Si se corta, volvé a la app y tocá Entrar de nuevo.',
      'Si no podés entrar, escribinos por el chat.',
    ],
    // El código de la reunión (2.3.1): el respaldo de «Entrar».
    TITULO_CODIGO: 'Código de la reunión',
    TEXTO_COPIAR_CODIGO: 'Copiar código',
    TEXTO_CODIGO_COPIADO: 'Código copiado',
    // Solo en Android: sin la app de Meet, la web de Meet manda a Google Play (gemelo de Android).
    TEXTO_SIN_APP_MEET: 'Si te pide instalar Google Meet, instalala y volvé a tocar Entrar.',
    // Dónde se pega el código si «Entrar» no abre la reunión, en pasos cortos para gente mayor (Mati, 12/11).
    TITULO_PASOS_CODIGO: 'Si no se abre la reunión:',
    PASOS_CODIGO: [
      'Tocá «Copiar código».',
      'Abrí Google Meet.',
      'Tocá «Unirse con un código».',
      'Pegá el código y tocá «Unirse».',
    ],
    // El código de un link de Meet, «abc-defg-hij», o null (gemelo de iOS y Android). Acepta el código sin guiones y
    // lo devuelve con guiones; ignora mayúsculas, la barra final y lo que venga después (`?authuser`, `#`).
    codigoMeet: url => {
      if (typeof url !== 'string') return null;
      const m = /^https:\/\/(www\.)?meet\.google\.com(\/[^?#]*)?([?#].*)?$/i.exec(url.trim());
      if (!m) return null;
      const partes = (m[2] || '').split('/').filter(Boolean);
      if (partes.length !== 1) return null;
      const crudo = partes[0].toLowerCase();
      let letras;
      if (/^[a-z]{3}-[a-z]{4}-[a-z]{3}$/.test(crudo)) letras = crudo.replace(/-/g, '');
      else if (/^[a-z]{10}$/.test(crudo)) letras = crudo;
      else return null;
      return `${letras.slice(0, 3)}-${letras.slice(3, 7)}-${letras.slice(7)}`;
    },
    TEXTO_LISTO_AVISO: 'Mati te admite en la sala. Si tarda un poco, esperá ahí sin salir.',
    textoListoEntrar: desdeMin => `Vas a entrar a la videollamada desde la app, en Entreno. El botón se habilita ${desdeMin || RA.ENTRAR_DESDE_MIN} minutos antes.`,

    // En qué está «Entrar»: {tipo: 'falta', segundos} | {tipo: 'habilitado'} |
    // {tipo: 'preparando'} (en la ventana sin el link) | {tipo: 'nada'}.
    estadoEntrar(r, ahora, desdeMin) {
      if (!r || r.estado !== 'confirmada') return { tipo: 'nada' };
      const i = R.instante(r.inicio), f = R.instante(r.fin);
      const t = (ahora || new Date()).getTime();
      if (!i || !f || !(t < f.getTime())) return { tipo: 'nada' };
      const desde = i.getTime() - (desdeMin || RA.ENTRAR_DESDE_MIN) * 60000;
      // Si Mati ya abrió la sala, se puede entrar antes (espera en la sala igual).
      if (t < desde && (r.salaAbiertaEn == null || !r.meetUrl)) return { tipo: 'falta', segundos: (desde - t) / 1000 };
      return r.meetUrl ? { tipo: 'habilitado' } : { tipo: 'preparando' };
    },
    // Debajo del botón apagado: lejos, «Se habilita 10 minutos antes de
    // empezar»; a menos de un día, la cuenta regresiva.
    textoCuenta(e, desdeMin) {
      if (!e) return null;
      if (e.tipo === 'falta') {
        return e.segundos >= 24 * 3600 ? `Se habilita ${desdeMin || RA.ENTRAR_DESDE_MIN} minutos antes de empezar` : `Se habilita en ${RA.cuenta(e.segundos)}`;
      }
      if (e.tipo === 'preparando') return 'Estamos preparando la sala. El botón se activa en un momento.';
      return null;
    },
    // «2 h 15 min», «25 min», «menos de 1 min». Redondea para arriba: nunca dice 0 antes de tiempo.
    cuenta(segundos) {
      if (!isFinite(segundos) || segundos < 60) return 'menos de 1 min';
      const min = Math.ceil(segundos / 60);
      if (min < 60) return `${min} min`;
      const h = Math.floor(min / 60), m = min % 60;
      return m === 0 ? `${h} h` : `${h} h ${m} min`;
    },
    // La etiqueta de arriba de la tarjeta: «Hoy», «Mañana», «En 3 días» (por
    // día del calendario, en la zona del teléfono).
    cuando(r, zona, ahora) {
      const i = r && R.instante(r.inicio);
      if (!i) return null;
      const dia = d => { const [a, m, x] = RA.claveDia(d, zona).split('-').map(Number); return Date.UTC(a, m - 1, x) / 86400000; };
      const d = Math.round(dia(i) - dia(ahora || new Date()));
      if (d < 0) return null;
      return d === 0 ? 'Hoy' : d === 1 ? 'Mañana' : `En ${d} días`;
    },
    // «10:00 en Argentina», solo si el teléfono da otra hora.
    horaArgentina: (d, zona) => (RA.difiereDeArgentina([d], zona) ? `${RA.hora(d, ZONA_BA)} en Argentina` : null),
    // La reserva de la tarjeta fija de Entreno: confirmada (o reservándose) y que no terminó.
    paraTarjeta(r, ahora) {
      if (!reservaVigente(r)) return false;
      const f = R.instante(r.fin);
      return !!f && (ahora || new Date()).getTime() < f.getTime();
    },

    // ── Elegir y cambiar el horario (palanca `elegir_horario`) ──
    tituloElegir: t => `Elegí el horario de tu ${RA.nombre(t)}`,
    // «Dura alrededor de 1 hora y vas a entrar desde la app.»
    textoElegirPantalla(chips) {
      const ds = new Set(chips.map(c => RA.duracion(c.inicio, c.fin)));
      const d = ds.size === 1 ? ds.values().next().value : null;
      return d ? `Dura ${d} y vas a entrar desde la app.` : 'Vas a entrar desde la app.';
    },
    // «Confirmar jueves 12, 10:00» o «Cambiar al viernes 13, 12:00».
    textoBotonElegir(c, cambiando, zona) {
      const d = `${RA.diaCorto(c.inicio, zona)}, ${RA.hora(c.inicio, zona)}`;
      return cambiando ? `Cambiar al ${d}` : `Confirmar ${d}`;
    },
    // «Elegí el día y el horario. Hay lugar desde el jueves 12.»
    textoDesde(dias, zona) {
      const c = dias.length && dias[0].chips[0];
      return c ? `Elegí el día y el horario. Hay lugar desde el ${RA.diaCorto(c.inicio, zona)}.` : 'Elegí el día y el horario. Vas a entrar desde la app.';
    },
    // Se puede cambiar desde la app: lo dice el servidor, quedan cambios, no
    // pasó el plazo, no empezó y hay horarios.
    puedeCambiar(a, ahora) {
      if (!a || !a.ok || !a.reserva || a.reserva.estado !== 'confirmada' || !a.cambio || !a.cambio.permitido || !a.franjas.length) return false;
      const t = (ahora || new Date()).getTime();
      if (a.cambio.restantes != null && a.cambio.restantes <= 0) return false;
      const h = a.cambio.hasta ? R.instante(a.cambio.hasta) : null;
      if (h && t >= h.getTime()) return false;
      const i = R.instante(a.reserva.inicio);
      if (i && t >= i.getTime()) return false;
      return true;
    },
    // «Podés cambiarlo 1 vez, hasta el miércoles 11 a las 10:00.»
    textoTope(c, zona) {
      if (!c || !c.permitido) return null;
      const veces = c.restantes == null ? '' : c.restantes === 1 ? ' 1 vez' : ` ${c.restantes} veces`;
      const h = c.hasta ? R.instante(c.hasta) : null;
      return `Podés cambiarlo${veces}${h ? `, hasta el ${RA.diaCorto(h, zona)} a las ${RA.hora(h, zona)}` : ''}.`;
    },
    // «Ahora es el jueves 12 a las 10:00.»
    textoAhoraEs(r, zona) {
      const i = r && R.instante(r.inicio);
      return i ? `Ahora es el ${RA.diaCorto(i, zona)} a las ${RA.hora(i, zona)}.` : null;
    },
    mayuscula: s => mayuscula(s),

    // ── Entrar (Mati, 6/11: el cliente nunca entra directo) ──
    // La tarjeta de la entrega en Entreno: confirmada, desde `avisoMin` antes
    // (si no vino, 30) hasta el fin de la franja.
    enVentana(r, ahora, avisoMin) {
      if (!r || r.estado !== 'confirmada') return false;
      const i = R.instante(r.inicio), f = R.instante(r.fin);
      if (!i || !f) return false;
      const t = (ahora || new Date()).getTime();
      const antes = avisoMin != null ? avisoMin : RA.MINUTOS_ANTES_ENTRAR;
      return t >= i.getTime() - antes * 60000 && t < f.getTime();
    },
    // El botón para entrar (Mati, 10/11): confirmada, con link, desde
    // `desdeMin` (10) antes del inicio hasta el fin. El Meet es restringido:
    // Mati lo admite y el alumno espera en la sala, así que ya no se espera
    // `sala_abierta_en` (si viene, se puede entrar antes).
    puedeEntrar: (r, ahora, desdeMin) => RA.estadoEntrar(r, ahora, desdeMin).tipo === 'habilitado',
    // En la ventana y todavía sin el link o sin la sala abierta: la agenda
    // cada 30 s (para el link que falta y para «Mati ya está en la sala»).
    esperandoSala: (r, ahora, avisoMin) => RA.enVentana(r, ahora, avisoMin) && (!r.meetUrl || r.salaAbiertaEn == null),
    // Es el día de la entrega (en la zona del teléfono) y todavía no terminó.
    esHoy(r, zona, ahora) {
      const i = R.instante(r.inicio), f = R.instante(r.fin);
      const ya = ahora || new Date();
      if (!i || !f || !(ya < f)) return false;
      return RA.claveDia(i, zona) === RA.claveDia(ya, zona) || ya >= i;
    },
    // Con el botón: «Mati ya está en la sala» o «Ya podés entrar».
    textoEntrar: r => (r.salaAbiertaEn != null ? 'Mati ya está en la sala' : 'Ya podés entrar'),
    // El día de la videollamada, sin el botón todavía.
    textoEsperandoSala(r, zona, desdeMin) {
      const i = R.instante(r.inicio);
      return `Tu ${RA.nombre(r.tipo)} es hoy a las ${i ? RA.hora(i, zona) : ''}. El botón para entrar se habilita ${desdeMin || RA.ENTRAR_DESDE_MIN} minutos antes.`;
    },

    // ── Los textos que edita Mati (spec §7) ──
    // El de Mati si vino y no está vacío, con {hora}, {dia}, {duracion} y
    // {faltan} reemplazados; si no, el de la app. Si el de Mati pide un valor
    // que acá no hay, va el de la app: nunca se muestra una llave.
    textos(servidor) {
      const sv = servidor || {};
      // 2.3.0: las claves de la sala con la semántica vieja («cuando Mati abra la videollamada») no se usan, y un
      // texto del servidor que diga «entrega», WhatsApp, coach o entrenador no se muestra: va el de la app.
      const VIEJAS = ['hoy_sin_sala', 'sala_abierta', 'entreno_aviso'];
      const PROHIBIDO = /entrega|whatsapp|coach|entrenador/i;
      const texto = (clave, propio, v) => {
        const t0 = VIEJAS.includes(clave) ? null : sv[clave];
        if (typeof t0 !== 'string' || !t0.trim() || PROHIBIDO.test(t0)) return propio;
        let t = t0;
        const vals = v || {};
        for (const [llave, valor] of [['{hora}', vals.hora], ['{dia}', vals.dia], ['{duracion}', vals.duracion],
                                      ['{faltan}', vals.faltan == null ? null : String(vals.faltan)]]) {
          if (!t.includes(llave)) continue;
          if (valor == null) return propio;
          t = t.split(llave).join(valor);
        }
        return t;
      };
      const horaInicio = (r, zona) => { const i = R.instante(r.inicio); return i ? RA.hora(i, zona) : null; };
      const T = {
        titulo: texto('titulo', `Agendá tu ${RA.nombre('comienzo')}`),
        // El título de Mati es el de la de comienzo: la de revisión lleva el suyo.
        tituloDe: t => (t === 'revision' ? `Agendá tu ${RA.nombre(t)}` : texto('titulo', `Agendá tu ${RA.nombre(t)}`)),
        noAutorizada: texto('no_autorizada', RA.TEXTO_NO_AUTORIZADA),
        sinFranjas: texto('sin_franjas', RA.TEXTO_SIN_FRANJAS),
        pendiente: texto('pendiente', RA.TEXTO_RESERVANDO),
        cambiar: texto('cambiar', RA.TEXTO_CAMBIAR),
        // Con 0 («Ya viste todo…») no hay clave: el servidor todavía no se enteró.
        bloqueada: n => (n > 0 ? texto('bloqueada', RA.textoBloqueada(n), { faltan: n }) : RA.textoBloqueada(0)),
        // Tomada, vencida o error: el mismo texto de Mati para todas. La demo no se pisa.
        // «Ese cambio ya no se puede…» (tope o plazo) tampoco: no es «elegí otro».
        fallo: a => (a === 'demo' || a === 'sinCambio' ? TEXTO_AVISO[a] : texto('fallo', TEXTO_AVISO[a] || TEXTO_AVISO.error)),
        encabezado(chips) {
          const ds = new Set(chips.map(c => RA.duracion(c.inicio, c.fin)));
          const una = ds.size === 1 ? ds.values().next().value : null;
          return texto('encabezado', RA.textoElegir(chips), { duracion: una });
        },
        confirmar: (c, zona, tipo) => texto('confirmar', RA.textoConfirmar(c, zona, tipo),
          { hora: RA.hora(c.inicio, zona), dia: RA.diaCorto(c.inicio, zona), duracion: RA.duracion(c.inicio, c.fin) }),
        confirmada(r, zona) {
          const propio = RA.textoConfirmada(r, zona);
          const i = R.instante(r.inicio), f = R.instante(r.fin);
          if (!propio || !i || !f) return null;
          return texto('confirmada', propio, { hora: RA.hora(i, zona), dia: RA.diaLargo(i, zona), duracion: RA.duracion(i, f) });
        },
        // Con el botón: la clave `sala_abierta`, o el respaldo de la hora de inicio (que no se pisa).
        entrar(r, zona) { const p = RA.textoEntrar(r, zona); return r.salaAbiertaEn != null ? texto('sala_abierta', p) : p; },
        hoySinSala: (r, zona) => texto('hoy_sin_sala', RA.textoEsperandoSala(r, zona), { hora: horaInicio(r, zona) }),
        // La tarjeta de Entreno antes de que se abra la sala: `entreno_aviso` si vino; si no, el de la guía.
        entrenoAviso: (r, zona) => texto('entreno_aviso', T.hoySinSala(r, zona), { hora: horaInicio(r, zona) }),
      };
      return T;
    },
  };

  // ─── El cuadro de los videos (MyPumpReglas/FormatoVideo.swift) ──
  // Los clips vienen verticales (Mati en el cuadro del Meet), horizontales o
  // cuadrados. El cuadro toma la proporción real del clip; los verticales no
  // pasan del 60 % del alto visible. Hay clips que traen el negro dentro del
  // MP4 (una grabación vertical de 434 px en un 1280×720): se detecta la zona
  // útil y se muestra solo esa.
  const RV = {
    PROPORCION_DEFECTO: 16 / 9,
    ALTO_MAXIMO: 0.6,
    UMBRAL_NEGRO: 16,             // las franjas de un MP4 comprimido andan por 10-14
    MINIMO_SIN_RECORTE: 0.92,     // si lo útil ocupa esto o más en los dos sentidos, no se recorta
    BORDE_OSCURO_MAXIMO: 0.04,    // el marco del teléfono grabado o el halo de la compresión
    ENTERO: { x: 0, y: 0, ancho: 1, alto: 1 },

    // Ancho sobre alto. null si el tamaño no sirve (fuera de 0,25 a 4 está roto).
    proporcion(ancho, alto) {
      if (!isFinite(ancho) || !isFinite(alto) || ancho <= 0 || alto <= 0) return null;
      const p = ancho / alto;
      return p >= 0.25 && p <= 4 ? p : null;
    },

    // El cuadro para ese ancho disponible y ese alto de pantalla.
    cuadro(proporcion, anchoDisponible, altoPantalla) {
      const p = proporcion != null && proporcion >= 0.25 && proporcion <= 4 ? proporcion : RV.PROPORCION_DEFECTO;
      if (!(anchoDisponible > 0)) return { ancho: 0, alto: 0 };
      let ancho = anchoDisponible, alto = ancho / p;
      if (altoPantalla > 0 && alto > altoPantalla * RV.ALTO_MAXIMO) { alto = altoPantalla * RV.ALTO_MAXIMO; ancho = alto * p; }
      return { ancho: Math.round(ancho), alto: Math.round(alto) };
    },

    // Lo que no es negro en un cuadro en gris (`luma`, fila por fila). Una
    // columna (o fila) cuenta si al menos el 1 % de sus píxeles (y 2 o más)
    // pasa el umbral. Después se le sacan los bordes oscuros y parejos (media
    // < 40, desvío < 12) de hasta el 4 % de cada lado, y `margen` px más hacia
    // adentro. null si todo el cuadro es negro (un fundido).
    recuadro(luma, ancho, alto, umbral, margen) {
      const u = umbral == null ? RV.UMBRAL_NEGRO : umbral, mg = margen == null ? 1 : margen;
      if (!(ancho > 0) || !(alto > 0) || !luma || luma.length < ancho * alto) return null;
      const porColumna = new Array(ancho).fill(0), porFila = new Array(alto).fill(0);
      for (let y = 0; y < alto; y++) {
        const base = y * ancho;
        for (let x = 0; x < ancho; x++) if (luma[base + x] > u) { porColumna[x]++; porFila[y]++; }
      }
      const minCol = Math.max(2, Math.floor((alto + 99) / 100)), minFila = Math.max(2, Math.floor((ancho + 99) / 100));
      let x0 = porColumna.findIndex(v => v >= minCol), y0 = porFila.findIndex(v => v >= minFila);
      let x1 = -1, y1 = -1;
      for (let i = ancho - 1; i >= 0; i--) if (porColumna[i] >= minCol) { x1 = i; break; }
      for (let i = alto - 1; i >= 0; i--) if (porFila[i] >= minFila) { y1 = i; break; }
      if (x0 < 0 || x1 < 0 || y0 < 0 || y1 < 0) return null;
      const oscuroParejo = v => {
        if (!v.length) return false;
        const media = v.reduce((a, b) => a + b, 0) / v.length;
        const desvio = Math.sqrt(v.reduce((a, b) => a + (b - media) * (b - media), 0) / v.length);
        return media < 40 && desvio < 12;
      };
      const columna = x => { const o = []; for (let y = y0; y <= y1; y++) o.push(luma[y * ancho + x]); return o; };
      const fila = y => { const o = []; for (let x = x0; x <= x1; x++) o.push(luma[y * ancho + x]); return o; };
      const topeX = Math.max(1, Math.trunc(ancho * RV.BORDE_OSCURO_MAXIMO)), topeY = Math.max(1, Math.trunc(alto * RV.BORDE_OSCURO_MAXIMO));
      let n = 0;
      while (n < topeX && x0 < x1 && oscuroParejo(columna(x0))) { x0++; n++; }
      n = 0;
      while (n < topeX && x1 > x0 && oscuroParejo(columna(x1))) { x1--; n++; }
      n = 0;
      while (n < topeY && y0 < y1 && oscuroParejo(fila(y0))) { y0++; n++; }
      n = 0;
      while (n < topeY && y1 > y0 && oscuroParejo(fila(y1))) { y1--; n++; }
      // Hacia adentro solo donde hay franja (un borde que toca el cuadro no se come).
      if (x0 > 0) x0 = Math.min(x0 + mg, x1);
      if (x1 < ancho - 1) x1 = Math.max(x1 - mg, x0);
      if (y0 > 0) y0 = Math.min(y0 + mg, y1);
      if (y1 < alto - 1) y1 = Math.max(y1 - mg, y0);
      return { x: x0 / ancho, y: y0 / alto, ancho: (x1 - x0 + 1) / ancho, alto: (y1 - y0 + 1) / alto };
    },

    // La unión de los cuadros medidos: lo que en alguno tiene imagen.
    unir(rs) {
      if (!rs || !rs.length) return null;
      const p = rs[0];
      let x0 = p.x, y0 = p.y, x1 = p.x + p.ancho, y1 = p.y + p.alto;
      for (const r of rs.slice(1)) { x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y); x1 = Math.max(x1, r.x + r.ancho); y1 = Math.max(y1, r.y + r.alto); }
      return { x: x0, y: y0, ancho: x1 - x0, alto: y1 - y0 };
    },

    // El recorte que se aplica, o null si no hace falta. Queda centrado: el
    // video lo llena con object-fit: cover, que recorta parejo de los dos
    // lados. Si las franjas no son parejas, se achica del lado ancho (se
    // pierde un hilo de imagen): nunca negro a la vista.
    recorte(r) {
      if (!r || !(r.ancho > 0) || !(r.alto > 0) || !(r.ancho < RV.MINIMO_SIN_RECORTE || r.alto < RV.MINIMO_SIN_RECORTE)) return null;
      const mitadX = Math.min(0.5 - r.x, r.x + r.ancho - 0.5), mitadY = Math.min(0.5 - r.y, r.y + r.alto - 0.5);
      if (!(mitadX > 0) || !(mitadY > 0)) return null;
      const ancho = Math.min(1, 2 * mitadX), alto = Math.min(1, 2 * mitadY);
      if (!(ancho < RV.MINIMO_SIN_RECORTE || alto < RV.MINIMO_SIN_RECORTE)) return null;
      return { x: (1 - ancho) / 2, y: (1 - alto) / 2, ancho, alto };
    },

    // La proporción que se ve: la del archivo, achicada al recorte.
    conRecorte(archivo, recorte) {
      if (!recorte || !(recorte.ancho > 0) || !(recorte.alto > 0)) return archivo;
      const p = RV.proporcion(archivo * recorte.ancho, recorte.alto);
      return p == null ? archivo : p;
    },

    // Un cuadro RGBA (de un canvas) a luma, como Android (Rec. 601 entero).
    luma(rgba, n) {
      const l = new Uint8Array(n);
      for (let i = 0, j = 0; i < n; i++, j += 4) l[i] = Math.trunc((299 * rgba[j] + 587 * rgba[j + 1] + 114 * rgba[j + 2]) / 1000);
      return l;
    },
  };

  // ─── API ───────────────────────────────────────────────────────
  const API = {
    MAX_TEXTO, MAX_SEGUNDOS, HORAS_TARJETA, ZONA_BA, largo,
    texto, booleano, decimal, entero, lista, esObjeto, noVacio, textos, trimServidor,
    normalizarClip, normalizarGuia, normalizarResumen, normalizarAgenda, normalizarReserva, normalizarFranja,
    R, RD, RA, RV, AvanceVideo, vistaSuplementacion, diaBA, desfase, esUuid,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.ReglasGuia = API;
})(typeof window !== 'undefined' ? window : globalThis);
