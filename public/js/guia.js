/* =============================================================
   guia.js — «Tu guía» en la web del cliente

   Port de la sección de la app nativa MyPump 2.1.0 (rama nativa-202):
   · apps/ios/MyPump/Guia/GuiaView.swift, GuiaDestacada.swift,
     ReproductorGuia.swift, AudioDudaView.swift (la interfaz);
   · apps/ios/MyPumpKit/Sources/MyPumpReglas/Guia.swift y AudioDuda.swift
     (las reglas, copiadas una por una);
   · MyPumpModelos/Guia.swift (la forma tolerante del JSON);
   · MyPumpDatos/Guia.swift, AudioDuda.swift y Escrituras.swift (las RPC).

   Módulo independiente: no depende de la estructura de cliente.html. Usa
   window.mypumpDB (supabase-client.js) y las variables de css/tokens.css.
   Inyecta su propio <style> (prefijo .gu-) y dibuja la guía en un overlay
   fijo propio.

   API (window.MyPumpGuia):
   · cargarResumen(token)            → Promise<resumen | null>
   · montarTarjeta(contenedor, token) → Promise<boolean> (si dibujó algo)
   · abrir(token)                    → abre la guía a pantalla completa
   · cerrar()
   · bienvenidaSiCorresponde(token, {nombre}) → Promise<boolean>
   · quitada(token), quitar(token), volverAMostrar(token)
   · mostrarFila(token), puedeVolverAMostrar(token)
   · alCambiar(fn)                   → función para desuscribirse
   ============================================================= */
(function () {
  'use strict';
  if (window.MyPumpGuia) return;

  // ─── Constantes (ReglasGuia y ReglasAudioDuda) ─────────────────
  const MAX_TEXTO = 1000;            // la base acepta de 1 a 1000 caracteres
  const MAX_DUDAS_LLAMADA = 30;      // compartido con la web y la app
  const PLACA_MS = 2600;             // la placa al cambiar de video
  const MAX_SEGUNDOS = 36000;        // p_segundos de 0 a 36000
  const HORAS_TARJETA = 48;          // entregas_014: 48 h exactas
  const INTENTOS_MAX = 8;            // la cola abandona después de 8 rechazos
  const AUDIO_TOPE = 300;            // corta solo a los 5 minutos
  const AUDIO_AVISO = 270;           // «Te quedan 30 segundos.»
  const AUDIO_MINIMO = 2;            // menos de esto no se manda
  const AUDIO_BITRATE = 64000;
  const SONDEO_CADA_MS = 15000;      // la lista de audios, cada 15 s
  const SONDEO_MAX_MS = 180000;      // como mucho 3 minutos
  const ZONA_BA = 'America/Argentina/Buenos_Aires';

  // ─── Utilidades ─────────────────────────────────────────────────
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // Un hash corto del token para las claves de localStorage (no se guarda el
  // token en la clave). FNV-1a de 32 bits, dos pasadas para 64 bits de largo.
  function hashToken(t) {
    let a = 0x811c9dc5, b = 0x01000193 ^ 0x5bd1e995;
    for (let i = 0; i < t.length; i++) {
      const c = t.charCodeAt(i);
      a ^= c; a = Math.imul(a, 0x01000193) >>> 0;
      b ^= c; b = Math.imul(b, 0x01000193 + 0x9e) >>> 0;
    }
    return a.toString(36) + b.toString(36);
  }

  const almacen = {
    leer(k, def) {
      try { const v = localStorage.getItem(k); return v == null ? def : JSON.parse(v); } catch (_) { return def; }
    },
    guardar(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (_) { /* lleno o privado */ } },
    borrar(k) { try { localStorage.removeItem(k); } catch (_) { /* nada */ } },
  };

  function uuid() {
    if (window.crypto && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
    const b = new Uint8Array(16);
    crypto.getRandomValues(b);
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  function esDemo() {
    try { return new URLSearchParams(location.search).get('demo') === '1'; } catch (_) { return false; }
  }
  const db = () => window.mypumpDB || null;
  const tokenValido = t => typeof t === 'string' && t.length > 0;
  const reducirMovimiento = () => !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
  // Caracteres como los cuenta la base (puntos de código), no unidades UTF-16.
  const largo = s => Array.from(s || '').length;
  const fmtNum = n => Number(n).toLocaleString('es-AR');

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

  // Lo que devuelve entregas_app_get. Todo lo que no sea un objeto con
  // ok:true es «no hay guía».
  function normalizarGuia(j) {
    if (!esObjeto(j)) return { ok: false, nombrePila: null, fechaEntrega: null, clips: [], dudasLlamada: [], suplementacion: null };
    return {
      ok: booleano(j.ok) || false,
      nombrePila: texto(j.nombre_pila),
      fechaEntrega: texto(j.fecha_entrega),
      clips: lista(j.clips).map(normalizarClip).filter(Boolean),
      dudasLlamada: lista(j.dudas_llamada).map(normalizarDudaLlamada).filter(d => d && d.texto !== ''),
      suplementacion: normalizarSuplementacion(j.suplementacion),
    };
  }

  // Lo que devuelve entregas_app_resumen (entregas_011 y 014).
  function normalizarResumen(j) {
    if (!esObjeto(j)) return { ok: false, total: 0, vistos: 0, minutosRestantes: 0, fechaEntrega: null, mostrarTarjetaServidor: null };
    const ok = booleano(j.ok) || false;
    const total = Math.max(0, entero(j.total) || 0);
    const m = decimal(j.minutos_restantes) || 0;
    const f = texto(j.fecha_entrega);
    return {
      ok,
      total,
      vistos: Math.min(Math.max(0, entero(j.vistos) || 0), total),
      minutosRestantes: m > 0 ? m : 0,
      fechaEntrega: f && f.trim() ? f : null,
      // Se lee primero ok: con false no hay tarjeta ni fila, venga lo que venga.
      mostrarTarjetaServidor: ok ? booleano(j.mostrar_tarjeta) : null,
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
    deLaLista(g) {
      if (!g) return [];
      const nombrados = R.nombradosPorSuplementos(g.suplementacion);
      return R.ordenados(g.clips.filter(c => !(R.esBloqueSuplementacion(c.bloque) && nombrados.has(c.id))));
    },

    clipDeSuplemento(g, videoId) {
      if (!videoId || !g) return null;
      const c = g.clips.find(x => x.id === videoId);
      return c && c.url ? c : null;
    },

    rotuloVerPorQue: c => `Ver por qué (${Math.max(1, Math.round(c.minutos * 60))} s)`,

    nombreBloque: c => ((c.bloque || '').trim() || 'Videos'),

    bloques(clips) {
      const titulos = [];
      const indices = new Map();
      clips.forEach((c, i) => {
        const t = R.nombreBloque(c);
        if (!indices.has(t)) { titulos.push(t); indices.set(t, []); }
        indices.get(t).push(i);
      });
      return titulos.map(t => {
        const ix = indices.get(t);
        return { titulo: t, indices: ix, minutos: ix.reduce((a, i) => a + clips[i].minutos, 0), esApp: R.esBloqueApp(t) };
      });
    },

    textoBloque(b) {
      const n = b.indices.length;
      const m = Math.max(1, Math.round(b.minutos));
      return `${n} ${n === 1 ? 'video' : 'videos'}, unos ${m} ${m === 1 ? 'minuto' : 'minutos'}`;
    },

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
      return `Viste ${a.vistos} de ${a.total}, te quedan unos ${Math.max(1, Math.round(a.minutosRestantes))} minutos`;
    },

    textoTarjeta(a) {
      if (R.completo(a)) return a.total === 1 ? 'Viste el video' : `Viste los ${a.total} videos`;
      const min = Math.max(1, Math.round(a.minutosRestantes));
      if (a.vistos === 0) return `${a.total} ${a.total === 1 ? 'video corto' : 'videos cortos'}, unos ${min} min`;
      return `${a.vistos} de ${a.total} videos, te quedan ${min} min`;
    },

    botonTarjeta: a => (a.vistos === 0 ? 'Ver mi guía' : 'Seguir viendo'),

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
      const cuantos = a.total === 1 ? `Es un video corto que armé para vos, de unos ${min} min.`
                                    : `Son ${a.total} videos cortos que armé para vos, unos ${min} min.`;
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

  // ─── Textos del audio (ReglasAudioDuda) ─────────────────────────
  // El cliente no se entera de que el audio se pasa a texto (Mati, 4-nov).
  const TA = {
    invitacion: '¿Te es más fácil hablarlo? Mandame un audio, como por WhatsApp. Hasta 5 minutos cada uno.',
    grabar: 'Grabar un audio',
    terminar: 'Terminar',
    terminarAccesible: 'Terminar de grabar',
    antesDelPermiso: 'Te va a pedir permiso para usar el micrófono, aceptalo así te escucho.',
    mandar: 'Mandar',
    grabarDeNuevo: 'Grabar de nuevo',
    borrar: 'Borrar',
    mandando: 'Mandando tu audio…',
    noSeMando: 'No se pudo mandar.',
    reintentar: 'Reintentar',
    errorTranscripcion: 'No pude escuchar bien este audio, ¿me lo mandás de nuevo o lo escribís?',
    subido: despues => (despues ? 'Listo, me llegó tu audio, te contesto por WhatsApp.'
                                : 'Listo, me llegó tu audio, lo escucho antes de la videollamada.'),
    grabaste: s => `Grabaste ${contador(s)}`,
    avisos: {
      // En el navegador no hay «Ajustes, MyPump»: va el texto de la web (pack.html).
      permisoNegado: 'Tu celu no me dio permiso para el micrófono. En iPhone andá a Ajustes, Safari, Micrófono y ponelo en Permitir. En Android tocá el candado al lado de la dirección y habilitá el micrófono. O escribime la duda acá arriba.',
      sinMicrofono: 'No encontré un micrófono en este dispositivo. Escribime la duda acá arriba.',
      ocupado: 'El micrófono lo está usando otra app. Cerrala y probá de nuevo.',
      muyCorto: 'No se escuchó nada, probá de nuevo.',
      quedan30: 'Te quedan 30 segundos.',
      tope: 'Ya me mandaste 10 audios. Lo que te falte escribímelo o lo vemos en la llamada.',
      pendientes: 'Esperá un toque que se terminen de mandar los otros audios.',
      largo: 'Es muy largo, mandámelo en audios de hasta 5 minutos.',
      formato: 'Este audio está en un formato que no puedo recibir. Escribime la duda acá arriba.',
      noSeMando: 'No se pudo mandar.',
      yaFallo: 'No pude escuchar bien este audio, ¿me lo mandás de nuevo o lo escribís?',
    },
  };
  function contador(seg) {
    const s = Math.max(0, Math.trunc(isFinite(seg) ? seg : 0));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }
  function avisoDeMotivo(m) {
    switch (m) {
      case 'tope': return 'tope';
      case 'pendientes': return 'pendientes';
      case 'tamano': case 'largo': return 'largo';
      case 'formato': return 'formato';
      case 'error': return 'yaFallo';
      default: return 'noSeMando';
    }
  }

  // ─── Dudas en audio (ModeloAudioDuda) ───────────────────────────
  // En la web el audio queda en memoria hasta que sube (como pack.html): si
  // falla, «No se pudo mandar» con «Reintentar» y el mismo p_id.
  function soportaAudio() {
    return !!(window.isSecureContext && navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder);
  }
  function elegirMime() {
    const ok = t => { try { return MediaRecorder.isTypeSupported(t); } catch (_) { return false; } };
    const webkit = /Apple/.test(navigator.vendor || '') && !/CriOS|FxiOS|EdgiOS/.test(navigator.userAgent || '');
    // Safari graba en audio/mp4 (AAC); Chrome y Android en audio/webm (opus).
    const orden = webkit ? ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm']
                         : ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];
    return orden.find(ok) || '';
  }

  class Audios {
    constructor(modelo) {
      this.m = modelo;
      this.soporte = soportaAudio();
      this.disponible = false;     // entregas_app_audios respondió alguna vez
      this.fase = 'reposo';        // reposo | pidiendo | grabando | revisando
      this.aviso = null;
      this.avisoDado = false;
      this.segundos = 0;
      this.permiso = 'sinPreguntar';
      this.servidor = [];
      this.locales = [];
      this.blob = null; this.url = null; this.mime = '';
      this._rec = null; this._stream = null; this._chunks = []; this._inicio = 0; this._tics = null;
      this._cancelado = false;
      this._sondeo = null; this._sondeoInicio = 0;
      this.seccionAbierta = false;
      this.escucha = null;         // el Audio de la revisión
      this.alEmpezar = null;       // la vista pausa los videos
      this.alAnunciar = null;
      this.alTic = null;
      this._consultarPermiso();
    }

    async _consultarPermiso() {
      try {
        if (!navigator.permissions || !navigator.permissions.query) return;
        const p = await navigator.permissions.query({ name: 'microphone' });
        const poner = () => { this.permiso = p.state === 'granted' ? 'dado' : p.state === 'denied' ? 'negado' : 'sinPreguntar'; };
        poner();
        p.onchange = () => { poner(); this.m.avisar(); };
      } catch (_) { /* Safari viejo o Firefox: queda «sin preguntar» */ }
    }

    get mostrar() { return this.soporte && this.disponible; }
    get mandandoAlguno() { return this.locales.some(l => l.estado === 'mandando'); }
    get haySubidos() { return this.servidor.some(a => a.estado === 'subido') || this.locales.some(l => l.estado === 'subido'); }
    get transcriptos() {
      return new Set(this.servidor.filter(a => a.estado === 'transcripto' && a.texto).map(a => a.texto.trim()).filter(Boolean));
    }
    // Lo del servidor primero; lo local que todavía no está, después.
    get filas() {
      const out = this.servidor.map(a => ({ id: a.id, estado: a.estado === 'error' ? 'error' : 'subido' }));
      for (const l of this.locales) if (!out.some(o => o.id === l.id)) out.push({ id: l.id, estado: l.estado, aviso: l.aviso });
      return out;
    }

    anunciar(t) { if (this.alAnunciar) this.alAnunciar(t); }

    // Al abrir la guía: la lista y, si hay alguno en «subido», el sondeo.
    async abrirSeccion() {
      this.seccionAbierta = true;
      await this.cargarLista();
      this._sondear();
    }
    cerrarSeccion() {
      this.seccionAbierta = false;
      clearTimeout(this._sondeo); this._sondeo = null;
    }

    async cargarLista() {
      if (!this.soporte || !db()) return;
      const d = await db().getAudiosGuia(this.m.token);
      if (!Array.isArray(d)) return;       // sin la 019 el botón no aparece
      this.disponible = true;
      this.servidor = d.filter(esObjeto).map(a => ({
        id: texto(a.id) || '', estado: texto(a.estado), texto: texto(a.texto),
      })).filter(a => a.id && ['subido', 'transcripto', 'error'].includes(a.estado));
      this.locales = this.locales.filter(l => !(l.estado === 'subido' && this.servidor.some(s => s.id === l.id)));
      this.m.avisar();
    }

    _sondear() {
      if (!this.seccionAbierta || !this.haySubidos || this._sondeo) return;
      this._sondeoInicio = Date.now();
      const vuelta = async () => {
        this._sondeo = null;
        if (!this.seccionAbierta || Date.now() - this._sondeoInicio > SONDEO_MAX_MS) return;
        await this.cargarLista();
        // Mientras se esperaba la lista pudo arrancar otro sondeo: no se duplica.
        if (!this._sondeo && this.haySubidos && this.seccionAbierta) this._sondeo = setTimeout(vuelta, SONDEO_CADA_MS);
      };
      this._sondeo = setTimeout(vuelta, SONDEO_CADA_MS);
    }

    // ── El grabador (MaquinaAudio) ──
    async tocarGrabar() {
      if (this.fase !== 'reposo' && this.fase !== 'revisando') return;
      this._descartar();
      this.aviso = null;
      this.fase = 'pidiendo';
      this._cancelado = false;
      this.m.avisar();
      let stream;
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      } catch (e) {
        const n = e && e.name;
        let a = 'ocupado';
        if (n === 'NotAllowedError' || n === 'SecurityError') { a = 'permisoNegado'; this.permiso = 'negado'; }
        else if (n === 'NotFoundError' || n === 'OverconstrainedError') a = 'sinMicrofono';
        this.fase = 'reposo';
        this.aviso = a;
        this.anunciar(TA.avisos[a]);
        this.m.avisar();
        return;
      }
      this.permiso = 'dado';
      // Se fue a segundo plano con el cartel del permiso: nada que revisar.
      if (this._cancelado || this.fase !== 'pidiendo') {
        stream.getTracks().forEach(t => t.stop());
        this.fase = 'reposo';
        this.m.avisar();
        return;
      }
      const elegido = elegirMime();
      let rec;
      try {
        rec = elegido ? new MediaRecorder(stream, { mimeType: elegido, audioBitsPerSecond: AUDIO_BITRATE })
                      : new MediaRecorder(stream);
      } catch (_) {
        try { rec = new MediaRecorder(stream); } catch (__) {
          stream.getTracks().forEach(t => t.stop());
          this.fase = 'reposo'; this.aviso = 'formato'; this.anunciar(TA.avisos.formato); this.m.avisar();
          return;
        }
      }
      if (this.alEmpezar) this.alEmpezar();
      this._stream = stream;
      this._rec = rec;
      this._chunks = [];
      this.mime = (rec.mimeType || elegido || 'audio/webm').split(';')[0];
      rec.ondataavailable = ev => { if (ev.data && ev.data.size) this._chunks.push(ev.data); };
      // Si el micrófono se corta (otra app, se desconectó) o el grabador falla, se cierra lo grabado.
      rec.onerror = () => { if (this.fase === 'grabando') this._parar(); };
      stream.getTracks().forEach(tr => { tr.onended = () => { if (this.fase === 'grabando' && this._rec === rec) this._parar(); }; });
      rec.onstop = () => {
        // Sin timeslice: el Blob se arma acá (con timeslice Safari armaba mp4 rotos).
        if (this.fase === 'revisando' && this._chunks.length) {
          this.blob = new Blob(this._chunks, { type: this.mime });
          this.url = URL.createObjectURL(this.blob);
          this.m.avisar();
        }
        this._chunks = [];
      };
      try { rec.start(); } catch (_) {
        stream.getTracks().forEach(t => t.stop());
        this._rec = null; this._stream = null;
        this.fase = 'reposo'; this.aviso = 'ocupado'; this.anunciar(TA.avisos.ocupado); this.m.avisar();
        return;
      }
      this._inicio = performance.now();
      this.segundos = 0;
      this.avisoDado = false;
      this.fase = 'grabando';
      this._tics = setInterval(() => this._tic(), 500);
      this.m.avisar();
    }

    _transcurrido() { return Math.min(AUDIO_TOPE, Math.max(0, (performance.now() - this._inicio) / 1000)); }

    _tic() {
      if (this.fase !== 'grabando') return;
      const s = (performance.now() - this._inicio) / 1000;
      this.segundos = Math.min(AUDIO_TOPE, s);
      if (s >= AUDIO_TOPE) { this._parar(); return; }
      if (s >= AUDIO_AVISO && !this.avisoDado) {
        this.avisoDado = true;
        this.aviso = 'quedan30';
        this.anunciar(TA.avisos.quedan30);
        this.m.avisar();
        return;
      }
      if (this.alTic) this.alTic(this.segundos);
    }

    terminar() { if (this.fase === 'grabando') this._parar(); }

    // Segundo plano, otro video que arranca o cerrar la guía: si graba, se
    // frena y pasa a revisar.
    cortar() {
      if (this.fase === 'grabando') this._parar();
      else if (this.fase === 'pidiendo') this._cancelado = true;
      if (this.escucha) this.escucha.pause();
    }

    _parar() {
      const s = this._transcurrido();
      clearInterval(this._tics); this._tics = null;
      if (s < AUDIO_MINIMO) {
        this.fase = 'reposo';
        this.aviso = 'muyCorto';
        this._chunks = [];
        this._soltarGrabador();
        this.anunciar(TA.avisos.muyCorto);
      } else {
        this.fase = 'revisando';
        this.segundos = s;
        if (this.aviso === 'quedan30') this.aviso = null;
        this._soltarGrabador();
        this.anunciar(TA.grabaste(s));
      }
      this.m.avisar();
    }

    _soltarGrabador() {
      try { if (this._rec && this._rec.state !== 'inactive') this._rec.stop(); } catch (_) { /* nada */ }
      if (this._stream) this._stream.getTracks().forEach(t => t.stop());
      this._rec = null; this._stream = null;
    }

    _descartar() {
      if (this.escucha) { this.escucha.pause(); this.escucha = null; }
      if (this.url) URL.revokeObjectURL(this.url);
      this.url = null; this.blob = null;
    }

    grabarDeNuevo() { if (this.fase === 'revisando') { this.fase = 'reposo'; this.tocarGrabar(); } }

    borrar() {
      if (this.fase !== 'revisando') return;
      this._descartar();
      this.fase = 'reposo'; this.aviso = null; this.segundos = 0;
      this.m.avisar();
    }

    alternarEscucha() {
      if (!this.url) return;
      if (!this.escucha) {
        this.escucha = new Audio(this.url);
        this.escucha.addEventListener('timeupdate', () => { if (this.alTic) this.alTic(null); });
        this.escucha.addEventListener('ended', () => this.m.avisar());
        this.escucha.addEventListener('pause', () => this.m.avisar());
        this.escucha.addEventListener('play', () => this.m.avisar());
      }
      if (this.escucha.paused) this.escucha.play().catch(() => {}); else this.escucha.pause();
    }

    mandar() {
      if (this.fase !== 'revisando' || !this.blob) return;
      const local = { id: uuid(), estado: 'mandando', aviso: null, blob: this.blob, mime: this.mime,
                      segundos: Math.round(this.segundos), intentada: false, nuevoId: false, esperas: 0 };
      if (this.escucha) { this.escucha.pause(); this.escucha = null; }
      if (this.url) URL.revokeObjectURL(this.url);
      this.url = null; this.blob = null;
      this.fase = 'reposo'; this.aviso = null; this.segundos = 0;
      this.locales.push(local);
      this.m.avisar();
      this._enviar(local);
    }

    reintentar(id) {
      const l = this.locales.find(x => x.id === id);
      if (!l || l.estado === 'mandando' || !l.blob) return;
      if (l.nuevoId) { l.id = uuid(); l.nuevoId = false; l.intentada = false; }
      l.estado = 'mandando'; l.aviso = null; l.esperas = 0;
      this.m.avisar();
      this._enviar(l);
    }

    // iniciar → subir → subido, con el mismo p_id en cada intento.
    async _enviar(l) {
      const d = db();
      const fallo = () => { l.estado = 'noSeMando'; this.m.avisar(); };
      if (!d) return fallo();
      for (let vuelta = 0; vuelta < 2; vuelta++) {
        const r = await d.iniciarAudioGuia(this.m.token, l.mime, l.blob.size, l.segundos, l.id);
        if (!r.success || !esObjeto(r.data)) return fallo();
        const t = r.data;
        if (t.ok !== true) {
          const motivo = texto(t.motivo);
          if (motivo === 'pendientes' && l.esperas < 12) {
            // Otros audios a medio mandar (hasta 3 a la vez): más tarde, solo.
            l.esperas++;
            setTimeout(() => this._enviar(l), SONDEO_CADA_MS);
            return;
          }
          if (motivo === 'id') { l.nuevoId = true; return fallo(); }
          if (motivo === 'token' || motivo == null) return fallo();
          l.estado = 'rechazado';
          l.aviso = avisoDeMotivo(motivo);
          this.m.avisar();
          return;
        }
        const bucket = texto(t.bucket), ruta = texto(t.ruta);
        if (!bucket || !ruta) return fallo();
        const quizasYaSubio = l.intentada;
        l.intentada = true;
        const up = await d.subirAudioGuia(bucket, ruta, l.blob, texto(t.mime) || l.mime);
        if (!up.ok && !(up.existe && quizasYaSubio)) return fallo();
        const s = await d.subidoAudioGuia(this.m.token, l.id);
        if (!s.success) {
          // El archivo subió: el worker lo ve igual (pack.html). Se muestra «Listo».
          if (s.transitorio) return this._listo(l);
          return fallo();
        }
        if (esObjeto(s.data) && s.data.ok === true) return this._listo(l);
        const m = esObjeto(s.data) ? texto(s.data.motivo) : null;
        if (m === 'sin_archivo' || m === 'vencido' || m === 'no_existe') { l.intentada = m !== 'sin_archivo'; continue; }
        if (m === 'token' || m == null) return fallo();
        l.estado = 'rechazado'; l.aviso = avisoDeMotivo(m);
        this.m.avisar();
        return;
      }
      fallo();
    }

    _listo(l) {
      l.estado = 'subido';
      l.blob = null;
      this.m.avisar();
      this.cargarLista().then(() => this._sondear());
    }
  }

  // ─── El modelo de un cliente (ModeloGuia) ───────────────────────
  class Modelo {
    constructor(token) {
      this.token = token;
      const h = hashToken(token);
      this.k = n => `mypump_guia_${n}_${h}`;
      const g = almacen.leer(this.k('guia'), null);
      this.guia = g && g.ok === true && Array.isArray(g.clips) ? g : null;
      const r = almacen.leer(this.k('resumen'), null);
      this.resumen = esObjeto(r) && typeof r.ok === 'boolean' ? r : null;
      this.estado = this.guia ? 'lista' : 'cargando';   // cargando | lista | oculta | sinRed
      this.desdeCache = false;
      // «Quitar de Entreno»: solo en este navegador, por cliente (guia_quitada.json).
      this.quitada = !!almacen.leer(this.k('quitada'), false);
      this.bienvenidaVista = !!almacen.leer(this.k('bienvenida'), false);
      const tv = !!almacen.leer(this.k('tarjeta_vista'), false);
      this.primeraSesionTarjeta = !tv;
      this._tarjetaVista = tv;
      this.cola = lista(almacen.leer(this.k('cola'), [])).filter(op => esObjeto(op) && esObjeto(op.payload));
      this.cola.forEach(op => { op.enVuelo = false; });
      this.envios = {};          // por video (id) y '' para la videollamada
      this.borradores = {};
      this.confirmadas = [];
      this.cargas = 0;
      this.oyentes = new Set();
      this.audios = new Audios(this);
      this._procesando = false;
      this._reintento = null;
      this._espera = 0;
      if (this.guia) this.superponer();
    }

    avisar() {
      for (const f of Array.from(this.oyentes)) { try { f(); } catch (e) { console.warn('[guia]', e); } }
      for (const f of Array.from(oyentesGlobales)) { try { f(); } catch (e) { console.warn('[guia]', e); } }
    }

    // ── Tarjeta y fila (nunca llaman al get) ──
    get mostrarTarjeta() { return R.tarjetaEnEntreno(this.resumen, this.quitada); }
    get mostrarFila() { return R.filaEnMisDatos(this.resumen, this.quitada); }
    get puedeQuitar() { return this.mostrarTarjeta; }
    get puedeVolverAMostrar() { return R.puedeVolverAMostrar(this.resumen, this.quitada); }
    get avanceTarjeta() {
      const r = this.resumen || {};
      return { total: r.total || 0, vistos: r.vistos || 0, minutosRestantes: r.minutosRestantes || 0 };
    }
    get tarjetaDestacada() { return this.mostrarTarjeta && !R.completo(this.avanceTarjeta); }
    get mostrarBienvenida() { return R.mostrarBienvenida(this.resumen, this.bienvenidaVista, this.quitada); }

    ponerQuitada(q) {
      this.quitada = !!q;
      if (q) almacen.guardar(this.k('quitada'), true); else almacen.borrar(this.k('quitada'));
      this.avisar();
    }
    marcarBienvenidaVista() { this.bienvenidaVista = true; almacen.guardar(this.k('bienvenida'), true); }
    marcarTarjetaVista() {
      if (this._tarjetaVista) return;
      this._tarjetaVista = true;
      almacen.guardar(this.k('tarjeta_vista'), true);
    }

    aplicarResumen(r) { this.resumen = r; almacen.guardar(this.k('resumen'), r); }
    guardarGuia() { if (this.guia) almacen.guardar(this.k('guia'), this.guia); }
    guardarCola() {
      almacen.guardar(this.k('cola'), this.cola.map(op => ({ id: op.id, kind: op.kind, payload: op.payload, intentos: op.intentos || 0 })));
    }

    // entregas_app_resumen: solo lee. Sin red queda lo guardado.
    actualizarResumen() {
      if (this._resumenEnCurso) return this._resumenEnCurso;
      this._resumenEnCurso = (async () => {
        const d = db();
        if (!d) return;
        const j = await d.getGuiaResumen(this.token);
        // null = no respondió (red o servidor): queda lo guardado. La base
        // responde {ok:false} o false cuando no hay guía.
        if (j === null || j === undefined) return;
        const r = normalizarResumen(j);
        if (!r.ok) { this.ocultar(); return; }
        // Con avances todavía en la cola, el servidor cuenta menos de lo que el
        // cliente ya vio: la tarjeta no retrocede.
        const enCola = this.cola.some(op => op.kind === 'avance' && op.payload.visto === true);
        const conFechas = (c, de) => Object.assign({}, c, { fechaEntrega: de.fechaEntrega, mostrarTarjetaServidor: de.mostrarTarjetaServidor });
        if (enCola && this.guia) {
          this.resumen = conFechas(this.resumen && this.resumen.ok ? this.resumen : r, r);
          this.superponer();
        } else if (enCola && this.resumen && this.resumen.ok && this.resumen.total === r.total && this.resumen.vistos > r.vistos) {
          this.aplicarResumen(conFechas(this.resumen, r));
        } else {
          this.aplicarResumen(r);
        }
        this.avisar();
        if (this.cola.length) this.procesarCola();
      })().finally(() => { this._resumenEnCurso = null; });
      return this._resumenEnCurso;
    }

    // entregas_app_get: SOLO al abrir la guía.
    abrir() {
      if (this._carga) return this._carga;
      this._carga = this._traer().finally(() => { this._carga = null; });
      return this._carga;
    }

    async _traer() {
      const carga = ++this.cargas;
      const d = db();
      const j = d ? await d.getGuia(this.token) : null;
      if (j === null || j === undefined) {
        // Sin red o el servidor caído: lo guardado, si hay.
        if (this.guia) { this.desdeCache = true; this.estado = 'lista'; this.superponer(); } else this.estado = 'sinRed';
        this.avisar();
        return;
      }
      const g = normalizarGuia(j);
      if (!g.ok) { this.ocultar(); return; }
      // Lo confirmado después de que salió este get todavía no viene.
      for (const c of this.confirmadas) if (c.carga >= carga) asegurar(c, g);
      this.confirmadas = this.confirmadas.filter(c => c.carga >= carga);
      this.guia = g;
      this.desdeCache = false;
      this.guardarGuia();
      this.superponer();
      this.estado = 'lista';
      this.avisar();
      if (this.cola.length) this.procesarCola();
    }

    // ok:false (token revocado o sin página aprobada): la sección desaparece sin mensaje.
    ocultar() {
      this.guia = null;
      this.estado = 'oculta';
      this.desdeCache = false;
      this.aplicarResumen(normalizarResumen({ ok: false }));
      almacen.borrar(this.k('guia'));
      this.avisar();
    }

    // Lo pendiente gana sobre lo que trajo el servidor: el avance en la cola
    // marca visto y suma segundos.
    superponer() {
      for (const op of this.cola) {
        if (op.kind === 'avance') this._avanceLocal(op.payload.video, op.payload.segundos, op.payload.visto === true, false);
      }
      this.recalcularResumen();
    }

    recalcularResumen() {
      const g = this.guia;
      if (!g || !g.ok) return;
      // Como entregas_012: sin los videos de los suplementos.
      const a = R.avance(R.deLaLista(g));
      const base = this.resumen && this.resumen.ok ? this.resumen : null;
      this.aplicarResumen({
        ok: true, total: a.total, vistos: a.vistos, minutosRestantes: Math.round(a.minutosRestantes * 10) / 10,
        fechaEntrega: base ? base.fechaEntrega : g.fechaEntrega,
        mostrarTarjetaServidor: base ? base.mostrarTarjetaServidor : null,
      });
    }

    clipVisto(id) { const c = this.guia && this.guia.clips.find(x => x.id === id); return !!(c && c.visto); }

    _avanceLocal(video, segundos, visto, guardar) {
      const g = this.guia;
      if (!g) return false;
      const c = g.clips.find(x => x.id === video);
      if (!c) return false;
      const s = Math.max(c.segundos, Number(segundos) || 0), v = c.visto || !!visto;
      if (s === c.segundos && v === c.visto) return false;
      const cambioVisto = v !== c.visto;
      c.segundos = s; c.visto = v;
      if (guardar) {
        this.guardarGuia();
        if (cambioVisto) this.recalcularResumen();
      }
      return true;
    }

    // El avance de un video por la cola. Una sola op por video (la que no
    // está en vuelo): el mayor de los segundos y visto si alguna lo tenía.
    avance(video, segundos, visto) {
      const s = Math.min(MAX_SEGUNDOS, Math.max(0, Math.round(segundos)));
      const v = !!visto || this.clipVisto(video);
      const cambio = this._avanceLocal(video, s, v, true);
      const previa = this.cola.find(op => op.kind === 'avance' && op.payload.video === video && !op.enVuelo);
      if (previa) {
        previa.payload.segundos = Math.max(previa.payload.segundos || 0, s);
        previa.payload.visto = previa.payload.visto === true || v;
      } else {
        this.cola.push({ id: uuid(), kind: 'avance', payload: { video, segundos: s, visto: v }, intentos: 0 });
      }
      this.guardarCola();
      if (cambio) this.avisar();
      this.procesarCola();
    }

    // ── Dudas ──
    get pendientes() {
      return this.cola.filter(op => op.kind === 'duda' || op.kind === 'llamada').map(op => ({
        id: op.id, video: op.kind === 'duda' ? op.payload.video : null, texto: op.payload.texto, previas: op.payload.previas || 0,
      }));
    }
    vecesEnGuia(t, video) {
      const g = this.guia;
      if (!g) return 0;
      if (video != null) { const c = g.clips.find(x => x.id === video); return R.veces(t, c && c.duda); }
      return R.vecesLlamada(t, g.dudasLlamada);
    }
    // Las de la cola que el servidor todavía no trae.
    get pendientesSinLlegar() { return this.pendientes.filter(p => this.vecesEnGuia(p.texto, p.video) <= p.previas); }
    get dudasLlamadaContadas() {
      return ((this.guia && this.guia.dudasLlamada.length) || 0) + this.pendientesSinLlegar.filter(p => p.video == null).length;
    }
    get puedeSumarDudaLlamada() { return this.dudasLlamadaContadas < MAX_DUDAS_LLAMADA; }
    // Sin las que ya se ven como transcripción de un audio.
    get dudasLlamadaVisibles() {
      const tr = this.audios.transcriptos;
      const ds = ((this.guia && this.guia.dudasLlamada) || []).map(d => d.texto);
      return tr.size ? ds.filter(d => !tr.has(d.trim())) : ds;
    }
    previasDe(t, video) {
      return this.vecesEnGuia(t, video) + this.pendientes.filter(p => p.video === video && p.texto === t).length;
    }

    enviarDuda(video) {
      const t = R.textoParaMandar(this.borradores[video] || '');
      if (!t) return false;
      this.borradores[video] = '';
      this.envios[video] = 'enviando';
      const previas = this.previasDe(t, video);
      // p_id (entregas_013): un uuid al azar, armado una sola vez.
      const id = uuid();
      this.cola.push({ id, kind: 'duda', payload: { video, texto: t, previas, id }, intentos: 0 });
      this.guardarCola();
      this.avisar();
      this.procesarCola();
      return true;
    }

    enviarDudaLlamada() {
      if (!this.puedeSumarDudaLlamada) return false;
      const t = R.textoParaMandar(this.borradores[''] || '');
      if (!t) return false;
      this.borradores[''] = '';
      this.envios[''] = 'enviando';
      const previas = this.previasDe(t, null);
      const id = uuid();
      this.cola.push({ id, kind: 'llamada', payload: { texto: t, previas, id }, intentos: 0 });
      this.guardarCola();
      this.avisar();
      this.procesarCola();
      return true;
    }

    _devolver(t, clave) {
      const actual = this.borradores[clave] || '';
      this.borradores[clave] = actual ? t + '\n' + actual : t;
      this.envios[clave] = 'noSeGuardo';
    }

    // ── La cola ──
    async _ejecutar(op) {
      const d = db();
      if (!d) return { red: true };
      const p = op.payload;
      let r;
      if (op.kind === 'avance') r = await d.guardarAvanceGuia(this.token, p.video, p.segundos, p.visto === true);
      else if (op.kind === 'duda') r = await d.enviarDudaGuia(this.token, p.video, p.texto, p.id);
      else if (op.kind === 'llamada') r = await d.enviarDudaLlamadaGuia(this.token, p.texto, p.id);
      else return { hecho: false };
      if (!r || !r.success) return r && r.transitorio ? { red: true } : { hecho: false };
      // El avance: FALSE = token caído o sin guía, no hay nada que guardar.
      if (op.kind === 'avance') return { hecho: true, data: r.data };
      // Una duda sin respuesta (null) no se da por guardada.
      if (r.data === null || r.data === undefined) return { hecho: false };
      return { hecho: true, data: r.data };
    }

    async procesarCola() {
      if (this._procesando) { this._otraVez = true; return; }
      if (!db() || !this.cola.length) return;
      if (navigator.onLine === false) { this._programar(true); return; }
      this._procesando = true;
      this._otraVez = false;
      clearTimeout(this._reintento); this._reintento = null;
      let red = false, cambio = false;
      try {
        for (const op of this.cola.slice()) {
          if (!this.cola.includes(op)) continue;
          op.enVuelo = true;
          let r;
          try { r = await this._ejecutar(op); } catch (_) { r = { red: true }; } finally { op.enVuelo = false; }
          if (r.red) { red = true; break; }   // sin red: corta la pasada sin gastar intento
          if (r.hecho) {
            this.cola = this.cola.filter(x => x !== op);
            this._alGuardar(op, r.data);
            cambio = true;
          } else {
            op.intentos = (op.intentos || 0) + 1;
            if (op.intentos >= INTENTOS_MAX) {
              this.cola = this.cola.filter(x => x !== op);
              this._alAbandonar(op);
              cambio = true;
            }
          }
          this.guardarCola();
        }
      } finally {
        this._procesando = false;
      }
      if (cambio) this.avisar();
      // Entró algo mientras salía la pasada: otra pasada enseguida.
      if (this._otraVez && !red && this.cola.length) { this._otraVez = false; setTimeout(() => this.procesarCola(), 0); return; }
      if (this.cola.length) this._programar(red); else this._espera = 0;
    }

    _programar(red) {
      if (this._reintento) return;
      this._espera = Math.min(60000, this._espera ? this._espera * 2 : (red ? 5000 : 3000));
      this._reintento = setTimeout(() => { this._reintento = null; this.procesarCola(); }, this._espera);
    }

    _alGuardar(op, data) {
      if (op.kind !== 'duda' && op.kind !== 'llamada') return;
      const video = op.kind === 'duda' ? op.payload.video : null;
      const clave = video == null ? '' : video;
      if (data === false) { this._devolver(op.payload.texto, clave); return; }
      const c = { video, texto: op.payload.texto, esperadas: (op.payload.previas || 0) + 1, carga: this.cargas };
      this.confirmadas.push(c);
      if (this.guia && asegurar(c, this.guia)) this.guardarGuia();
      this.envios[clave] = 'listo';
    }

    _alAbandonar(op) {
      if (op.kind !== 'duda' && op.kind !== 'llamada') return;
      this._devolver(op.payload.texto, op.kind === 'duda' ? op.payload.video : '');
    }
  }

  // Que la duda confirmada se vea, sin repetirla si un get ya la trajo.
  function asegurar(c, g) {
    if (!c.texto) return false;
    let vueltas = 0, cambio = false;
    if (c.video != null) {
      const clip = g.clips.find(x => x.id === c.video);
      if (!clip) return false;
      while (R.veces(c.texto, clip.duda) < c.esperadas && vueltas < 5) {
        vueltas++;
        clip.duda = clip.duda ? clip.duda + '\n' + c.texto : c.texto;
        cambio = true;
      }
      return cambio;
    }
    while (R.vecesLlamada(c.texto, g.dudasLlamada) < c.esperadas && vueltas < 5) {
      vueltas++;
      g.dudasLlamada.push({ texto: c.texto, en: null });
      cambio = true;
    }
    return cambio;
  }

  const modelos = new Map();
  const oyentesGlobales = new Set();
  function modelo(token) {
    let m = modelos.get(token);
    if (!m) { m = new Modelo(token); modelos.set(token, m); }
    return m;
  }

  // Volvió la señal o la pestaña: se vacían las colas.
  window.addEventListener('online', () => { for (const m of modelos.values()) { m._espera = 0; m.procesarCola(); } });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    for (const m of modelos.values()) {
      if (m.cola.length) m.procesarCola();
      // Al volver a primer plano, el resumen de nuevo (como la app), a lo sumo cada 5 minutos.
      if (!m._resumenAlVolver || Date.now() - m._resumenAlVolver > 300000) {
        m._resumenAlVolver = Date.now();
        Promise.resolve(m.actualizarResumen()).then(() => m.avisar()).catch(() => {});
      }
    }
  });

  // ─── Íconos ─────────────────────────────────────────────────────
  const svg = (d, extra) => `<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" ${extra || ''}>${d}</svg>`;
  const I = {
    play: svg('<path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.2-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z" fill="currentColor"/>'),
    check: svg('<path d="M5 12.5l4.2 4.2L19 7" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'),
    chevron: svg('<path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'),
    cerrar: svg('<path d="M6 6l12 12M18 6L6 18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>'),
    reloj: svg('<circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 7.5V12l3 2" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    parlante: svg('<path d="M4 9.5h3.5L12 6v12l-4.5-3.5H4z" fill="currentColor"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    stop: svg('<rect x="6.5" y="6.5" width="11" height="11" rx="2" fill="currentColor"/>'),
    pausa: svg('<rect x="6.5" y="5.5" width="4" height="13" rx="1.2" fill="currentColor"/><rect x="13.5" y="5.5" width="4" height="13" rx="1.2" fill="currentColor"/>'),
    mic: svg('<rect x="9" y="3.5" width="6" height="11" rx="3" fill="currentColor"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    ojo: svg('<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="12" r="3" fill="currentColor"/>'),
    ojoTachado: svg('<path d="M2.5 12S6 5.5 12 5.5c1.6 0 3 .45 4.2 1.1M21.5 12S18 18.5 12 18.5c-1.6 0-3-.45-4.2-1.1" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M4 20L20 4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    sinRed: svg('<path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.2a9.5 9.5 0 0 1 13 0M8.6 15.4a5 5 0 0 1 6.8 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="19" r="1.4" fill="currentColor"/><path d="M4 4l16 16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
    lista: svg('<path d="M9 7h11M9 12h11M9 17h11" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="4.5" cy="7" r="1.3" fill="currentColor"/><circle cx="4.5" cy="12" r="1.3" fill="currentColor"/><circle cx="4.5" cy="17" r="1.3" fill="currentColor"/>'),
    alerta: svg('<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 7.5v5.5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="16.5" r="1.3" fill="currentColor"/>'),
    subiendo: svg('<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 16.5V8M8.5 11.5L12 8l3.5 3.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'),
    listo: svg('<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M8 12.3l2.8 2.8L16.2 9.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'),
  };

  // ─── Estilos ────────────────────────────────────────────────────
  const ESTILOS = `
.gu-overlay,.gu-bienvenida{position:fixed;inset:0;z-index:9000;display:flex;flex-direction:column;background:var(--color-bg-secondary);color:var(--color-text-primary);font-family:var(--font-sans);-webkit-font-smoothing:antialiased}
.gu-overlay *,.gu-bienvenida *,.gu-tarjeta *,.gu-aviso-oculta *{box-sizing:border-box}
.gu-overlay [hidden],.gu-tarjeta[hidden]{display:none!important}
.gu-overlay button,.gu-bienvenida button,.gu-tarjeta button,.gu-aviso-oculta button{font-family:inherit;-webkit-tap-highlight-color:transparent}
.gu-barra{display:flex;align-items:center;justify-content:center;position:relative;min-height:52px;padding:calc(env(safe-area-inset-top,0px)) 56px 0;background:var(--color-bg-primary);border-bottom:1px solid var(--color-border);flex:0 0 auto}
.gu-barra-titulo{font-weight:600;font-size:17px}
.gu-cerrar{position:absolute;right:6px;bottom:4px;width:44px;height:44px;border:0;background:transparent;color:var(--color-text-secondary);border-radius:var(--radius-full);display:flex;align-items:center;justify-content:center;cursor:pointer}
.gu-cerrar svg{width:22px;height:22px}
.gu-cerrar:focus-visible,.gu-overlay button:focus-visible,.gu-overlay textarea:focus-visible,.gu-tarjeta button:focus-visible,.gu-bienvenida button:focus-visible{outline:2px solid var(--color-brand);outline-offset:2px}
.gu-banner{display:flex;gap:8px;align-items:center;justify-content:center;padding:8px 16px;font-size:13px;font-weight:600;color:var(--color-alerta);background:var(--color-bg-primary);border-bottom:1px solid var(--color-border)}
.gu-banner svg{width:16px;height:16px}
.gu-scroll{flex:1 1 auto;overflow-y:auto;-webkit-overflow-scrolling:touch;overscroll-behavior:contain}
.gu-contenido{max-width:640px;margin:0 auto;padding:16px 16px calc(32px + env(safe-area-inset-bottom,0px));display:flex;flex-direction:column;gap:16px}
.gu-card{background:var(--color-bg-primary);border-radius:var(--radius-lg);box-shadow:var(--shadow-sm);overflow:hidden}
.gu-pad{padding:20px}
.gu-sub{font-size:14px;color:var(--color-text-secondary);line-height:1.4}
.gu-nota{font-size:13px;color:var(--color-text-secondary);line-height:1.4;margin:0}
.gu-peligro{color:var(--color-danger)!important}
.gu-marca-t{color:var(--color-brand-text);font-weight:600}
.gu-cab{position:relative;padding:26px 20px 20px}
.gu-cab::before{content:"";position:absolute;top:0;left:0;right:0;height:6px;background:var(--color-brand)}
.gu-cab h2{margin:0 0 6px;font-family:var(--font-display);font-size:24px;font-weight:700;line-height:1.15}
.gu-cab p{margin:0 0 6px;font-size:16px;line-height:1.45}
.gu-firma{font-size:14px;color:var(--color-text-secondary)}
.gu-progreso{height:6px;border-radius:3px;background:var(--color-bg-tertiary);overflow:hidden;margin-top:6px}
.gu-progreso>span{display:block;height:100%;background:var(--color-brand);border-radius:3px;transition:width var(--transition-base)}
.gu-cuadro{position:relative;width:100%;aspect-ratio:16/9;max-height:78vh;margin:0 auto;background:#000}
.gu-cuadro video{position:absolute;inset:0;width:100%;height:100%;background:transparent;object-fit:contain}
.gu-cuadro.gu-ajustado,.gu-vpq-cuadro.gu-ajustado{background:transparent}
.gu-capa{position:absolute;inset:0;display:flex}
.gu-capa:empty{pointer-events:none}
.gu-portada,.gu-placa,.gu-sinvideo{flex:1;border:0;margin:0;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;padding:16px 20px;text-align:center;cursor:pointer}
.gu-portada{background:linear-gradient(180deg,#0a0a0a,#121c14)}
.gu-portada-titulo{font-family:var(--font-display);font-size:19px;font-weight:700;line-height:1.2;max-width:90%}
.gu-linea-verde{width:56px;height:3px;border-radius:2px;background:#5cba73}
.gu-portada-play{width:58px;height:58px;border-radius:50%;background:rgba(255,255,255,.16);display:flex;align-items:center;justify-content:center;margin-top:4px}
.gu-portada-play svg{width:26px;height:26px;margin-left:3px}
.gu-placa{background:#111814;align-items:flex-start;text-align:left;justify-content:center;padding:20px 24px}
.gu-placa-ceja{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:#a8d9b5}
.gu-placa-bloque{font-size:14px;color:#dbdbdb}
.gu-placa-titulo{font-family:var(--font-display);font-size:20px;font-weight:700;line-height:1.2}
.gu-placa-barra{width:100%;height:3px;background:rgba(255,255,255,.14);border-radius:2px;overflow:hidden;margin-top:6px}
.gu-placa-barra>span{display:block;height:100%;width:0;background:#5cba73;border-radius:2px;animation:gu-llenar ${PLACA_MS}ms linear forwards}
@keyframes gu-llenar{to{width:100%}}
.gu-sinvideo{background:#111;cursor:default}
.gu-sinvideo svg{width:28px;height:28px;opacity:.8}
.gu-sinvideo span{font-size:15px;font-weight:600}
.gu-banda{background:var(--color-brand-subtle);padding:16px}
.gu-ceja{font-size:12px;font-weight:600;letter-spacing:.05em;text-transform:uppercase;color:var(--color-brand-text)}
.gu-banda h3{margin:4px 0 0;font-size:17px;font-weight:600;line-height:1.3}
.gu-botones{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.gu-boton-chico{min-height:44px;padding:0 16px;border:0;border-radius:var(--radius-full);background:var(--color-bg-primary);color:var(--color-brand-text);font-size:15px;font-weight:600;cursor:pointer}
.gu-boton-chico:active{opacity:.6}
.gu-actual{padding:16px;display:flex;flex-direction:column;gap:12px}
.gu-motivo{font-size:15px;line-height:1.45;color:var(--color-text-secondary);display:flex;flex-direction:column;gap:4px}
.gu-motivo p{margin:0}
.gu-motivo .gu-hacer{color:var(--color-text-primary)}
.gu-duda{display:flex;flex-direction:column;gap:8px}
.gu-duda-titulo{font-size:15px;font-weight:600}
.gu-ya{background:var(--color-bg-tertiary);border-radius:var(--radius-sm);padding:10px 12px;display:flex;flex-direction:column;gap:4px;font-size:15px}
.gu-ya-titulo{font-size:12px;font-weight:600;color:var(--color-text-secondary)}
.gu-ya p{margin:0;white-space:pre-wrap;overflow-wrap:anywhere}
.gu-encola{display:flex;gap:6px;align-items:flex-start;color:var(--color-text-secondary);font-size:15px}
.gu-encola svg{width:16px;height:16px;flex:0 0 16px;margin-top:2px}
.gu-encola span{white-space:pre-wrap;overflow-wrap:anywhere}
.gu-campo{display:flex;flex-direction:column;align-items:flex-end;gap:4px}
.gu-campo textarea{width:100%;min-height:56px;max-height:160px;resize:none;border:1.5px solid transparent;border-radius:var(--radius-md);background:var(--color-bg-tertiary);color:var(--color-text-primary);font:inherit;font-size:16px;line-height:1.4;padding:10px 12px;outline:none}
.gu-campo textarea:focus{border-color:var(--color-brand)}
.gu-campo textarea::placeholder{color:var(--color-text-muted)}
.gu-contador{font-size:12px;color:var(--color-text-secondary)}
.gu-envio{display:flex;align-items:center;gap:8px;justify-content:space-between}
.gu-envio-estado{font-size:13px;color:var(--color-text-secondary);line-height:1.35}
.gu-boton-marca{min-height:44px;padding:0 18px;border:0;border-radius:var(--radius-full);background:var(--color-brand);color:var(--color-on-brand);font-size:15px;font-weight:600;cursor:pointer;flex:0 0 auto}
.gu-boton-marca:disabled{opacity:.4;cursor:default}
.gu-boton-sec{min-height:44px;padding:0 16px;border:1px solid var(--color-brand-text);border-radius:var(--radius-full);background:transparent;color:var(--color-brand-text);font-size:15px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;gap:6px}
.gu-boton-sec svg{width:16px;height:16px}
.gu-boton-sec:disabled{opacity:.4;cursor:default}
.gu-boton-sec.gu-rojo{border-color:var(--color-danger);color:var(--color-danger)}
.gu-bloque-cab{width:100%;min-height:56px;border:0;background:transparent;color:inherit;display:flex;align-items:center;gap:12px;padding:12px 20px;text-align:left;cursor:pointer}
.gu-bloque-cab>span{flex:1;display:flex;flex-direction:column;gap:2px}
.gu-bloque-titulo{font-size:17px;font-weight:600}
.gu-chev{width:18px;height:18px;color:var(--color-text-secondary);transition:transform var(--transition-base);flex:0 0 18px}
[aria-expanded="true"]>.gu-chev{transform:rotate(180deg)}
.gu-filas{padding-bottom:6px}
.gu-fila.gu-fila-actual{background:var(--color-brand-subtle)}
.gu-fila-linea{display:flex;align-items:stretch}
.gu-fila-boton{flex:1;min-height:48px;border:0;background:transparent;color:var(--color-text-primary);display:flex;align-items:center;gap:12px;padding:10px 4px 10px 20px;text-align:left;font-size:16px;cursor:pointer;line-height:1.3}
.gu-fila-boton:disabled{opacity:.5;cursor:default}
.gu-fila-titulo{flex:1}
.gu-dur{font-size:14px;color:var(--color-text-secondary);font-variant-numeric:tabular-nums;flex:0 0 auto}
.gu-motivo-boton{width:48px;border:0;background:transparent;color:var(--color-text-secondary);display:flex;align-items:center;justify-content:center;cursor:pointer}
.gu-fila .gu-motivo{padding:0 20px 12px 54px;font-size:14px}
.gu-icono{width:22px;height:22px;flex:0 0 22px;border-radius:50%;border:2px solid var(--color-text-muted);display:flex;align-items:center;justify-content:center;color:var(--color-brand)}
.gu-icono svg{width:12px;height:12px}
.gu-icono.gu-visto{background:var(--color-brand);border-color:var(--color-brand);color:var(--color-on-brand)}
.gu-icono.gu-sonando,.gu-icono.gu-es-actual{border-color:var(--color-brand)}
.gu-llamada{position:relative;padding:20px 20px 20px 24px;display:flex;flex-direction:column;gap:10px}
.gu-llamada::before{content:"";position:absolute;left:0;top:0;bottom:0;width:4px;background:var(--color-brand)}
.gu-llamada h3{margin:0;font-family:var(--font-display);font-size:20px;font-weight:700;line-height:1.2}
.gu-recuadro{background:var(--color-brand-subtle);border-radius:var(--radius-sm);padding:10px 12px;font-size:15px;line-height:1.4;margin:0}
.gu-lista-dudas{display:flex;flex-direction:column}
.gu-lista-dudas>p{margin:0;padding:8px 0;border-top:1px solid var(--color-border);font-size:15px;white-space:pre-wrap;overflow-wrap:anywhere}
.gu-lista-dudas>.gu-encola{padding:8px 0;border-top:1px solid var(--color-border)}
.gu-audio{display:flex;flex-direction:column;gap:8px;padding-top:8px;border-top:1px solid var(--color-border);margin-top:4px}
.gu-grabando{display:flex;align-items:center;gap:12px}
.gu-terminar{min-height:44px;padding:0 18px;border:0;border-radius:var(--radius-full);background:var(--color-danger);color:#fff;font-size:15px;font-weight:600;display:inline-flex;align-items:center;gap:6px;cursor:pointer}
.gu-terminar svg{width:16px;height:16px}
.gu-punto{width:10px;height:10px;border-radius:50%;background:var(--color-danger);animation:gu-latir 1.4s ease-in-out infinite}
@keyframes gu-latir{0%,100%{opacity:1}50%{opacity:.25}}
.gu-cuenta{font-size:17px;font-weight:600;font-variant-numeric:tabular-nums}
.gu-revision{display:flex;align-items:center;gap:12px}
.gu-escuchar{width:44px;height:44px;border:0;border-radius:50%;background:var(--color-brand-subtle);color:var(--color-brand-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex:0 0 44px}
.gu-escuchar svg{width:18px;height:18px}
.gu-escuchar:disabled{opacity:.4}
.gu-barra-audio{flex:1;height:4px;border-radius:2px;background:var(--color-bg-tertiary);overflow:hidden}
.gu-barra-audio>span{display:block;height:100%;width:0;background:var(--color-brand)}
.gu-cuenta-chica{font-size:13px;color:var(--color-text-secondary);font-variant-numeric:tabular-nums}
.gu-fila-audio{display:flex;gap:8px;align-items:flex-start;font-size:15px;line-height:1.35;color:var(--color-text-secondary)}
.gu-fila-audio svg{width:18px;height:18px;flex:0 0 18px;margin-top:1px}
.gu-fila-audio .gu-ok{color:var(--color-brand)}
.gu-fila-audio>div{display:flex;flex-direction:column;gap:6px;align-items:flex-start}
.gu-supl h3{margin:0 0 4px;font-size:17px;font-weight:600}
.gu-momento{border-top:1px solid var(--color-border);padding-top:10px;margin-top:10px;display:flex;flex-direction:column;gap:8px}
.gu-momento-titulo{font-size:14px;font-weight:600;color:var(--color-brand-text)}
.gu-item{display:flex;flex-direction:column;gap:3px;padding:4px 0}
.gu-item-linea{display:flex;align-items:baseline;gap:8px}
.gu-item-nombre{flex:1;font-weight:600;font-size:16px}
.gu-etq{font-size:12px;font-weight:600;color:var(--color-brand-text);margin-left:6px}
.gu-etq.gu-gris{color:var(--color-text-secondary);font-weight:400}
.gu-cant{font-weight:600;font-variant-numeric:tabular-nums;text-align:right}
.gu-item p{margin:0;font-size:14px;line-height:1.4}
.gu-detalle{padding-left:10px;border-left:2px solid var(--color-border);color:var(--color-text-secondary)}
.gu-vpq{display:flex;flex-direction:column;gap:10px;margin-top:6px}
.gu-vpq-boton{align-self:flex-start;min-height:36px;padding:0 14px;border:1px solid var(--color-brand-text);border-radius:var(--radius-full);background:transparent;color:var(--color-brand-text);font-size:14px;font-weight:600;display:inline-flex;align-items:center;gap:6px;cursor:pointer;margin:4px 0}
.gu-vpq-boton svg{width:14px;height:14px}
.gu-vpq-boton .gu-visto-t{color:var(--color-brand)}
.gu-vpq-cuadro{position:relative;width:100%;aspect-ratio:16/9;max-height:78vh;margin:0 auto;background:#000;border-radius:var(--radius-md);overflow:hidden}
.gu-vpq-cuadro video{position:absolute;inset:0;width:100%;height:100%;object-fit:contain;background:transparent}
.gu-vpq-cuadro .gu-sinvideo{position:absolute;inset:0}
.gu-pie{font-size:14px;color:var(--color-text-secondary);line-height:1.45;padding:16px 20px;margin:0}
.gu-accion{align-self:center;min-height:44px;padding:0 16px;border:0;background:transparent;color:var(--color-text-secondary);font-size:14px;display:inline-flex;align-items:center;gap:6px;cursor:pointer}
.gu-accion svg{width:16px;height:16px}
.gu-estado{min-height:50vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;text-align:center;padding:24px}
.gu-estado svg{width:36px;height:36px;color:var(--color-text-secondary)}
.gu-estado h3{margin:0;font-size:18px}
.gu-girando{width:32px;height:32px;border-radius:50%;border:3px solid var(--color-bg-tertiary);border-top-color:var(--color-brand);animation:gu-girar .9s linear infinite}
@keyframes gu-girar{to{transform:rotate(360deg)}}
.gu-oculto{position:absolute!important;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
/* La tarjeta de Entreno */
.gu-tarjeta{font-family:var(--font-sans);color:var(--color-text-primary)}
.gu-destacada{background:#17852b;color:#fff;border-radius:var(--radius-lg);padding:16px;display:flex;flex-direction:column;gap:12px;box-shadow:0 8px 16px rgba(23,133,43,.28)}
[data-theme="dark"] .gu-destacada{background:#157a28;box-shadow:0 8px 16px rgba(21,122,40,.28)}
.gu-dest-cab{display:flex;align-items:center;justify-content:space-between;gap:8px;margin:-8px -8px 0 0}
.gu-dest-ceja{font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase}
.gu-ocultar{min-width:44px;min-height:44px;padding:0 8px;border:0;background:transparent;color:#fff;font-size:15px;font-weight:600;cursor:pointer}
.gu-dest-fila{display:flex;align-items:center;gap:12px}
.gu-dest-titulo{font-family:var(--font-display);font-size:26px;font-weight:700;line-height:1.1}
.gu-dest-sub{font-size:15px;font-weight:500}
.gu-icono-play{position:relative;width:52px;height:52px;flex:0 0 52px;border-radius:50%;background:rgba(255,255,255,.2);display:flex;align-items:center;justify-content:center;color:#fff}
.gu-icono-play svg{width:20px;height:20px;margin-left:2px;position:relative}
.gu-icono-play.gu-pulso::before{content:"";position:absolute;inset:0;border-radius:50%;border:2px solid currentColor;animation:gu-halo 1.8s ease-out .4s 4 both}
@keyframes gu-halo{from{transform:scale(1);opacity:.7}to{transform:scale(1.5);opacity:0}}
.gu-barra-blanca{height:6px;border-radius:3px;background:rgba(255,255,255,.28);overflow:hidden}
.gu-barra-blanca>span{display:block;height:100%;background:#fff;border-radius:3px}
.gu-boton-blanco{min-height:50px;width:100%;border:0;border-radius:var(--radius-full);background:#fff;color:#157a28;font-size:17px;font-weight:600;display:flex;align-items:center;justify-content:center;gap:8px;cursor:pointer}
.gu-boton-blanco svg{width:16px;height:16px}
.gu-boton-blanco:active{transform:scale(.97);opacity:.9}
.gu-compacta{width:100%;border:0;background:var(--color-bg-primary);border-radius:var(--radius-lg);box-shadow:var(--shadow-sm);padding:14px 16px;display:flex;align-items:center;gap:12px;text-align:left;cursor:pointer}
.gu-anillo{position:relative;width:44px;height:44px;flex:0 0 44px;color:var(--color-brand)}
.gu-anillo>svg{width:44px;height:44px;transform:rotate(-90deg)}
.gu-anillo>span{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
.gu-anillo>span svg{width:18px;height:18px}
.gu-compacta-texto{flex:1;display:flex;flex-direction:column;gap:2px}
.gu-compacta-texto b{font-size:17px;font-weight:600}
.gu-aviso-oculta{position:fixed;left:16px;right:16px;bottom:calc(16px + env(safe-area-inset-bottom,0px));z-index:9100;max-width:480px;margin:0 auto;display:flex;align-items:center;gap:12px;padding:2px 8px 2px 16px;border-radius:30px;background:var(--color-bg-primary);color:var(--color-text-primary);box-shadow:var(--shadow-lg);font-family:var(--font-sans);border:1px solid var(--color-border)}
.gu-aviso-oculta>span{flex:1;display:flex;align-items:center;gap:8px;font-size:15px;font-weight:600}
.gu-aviso-oculta svg{width:18px;height:18px}
.gu-aviso-oculta button{min-width:44px;min-height:44px;padding:0 8px;border:0;background:transparent;color:var(--color-brand-text);font-size:15px;font-weight:700;cursor:pointer}
/* La bienvenida */
.gu-bienvenida{background:var(--color-bg-secondary);overflow-y:auto}
.gu-bv-cuerpo{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:24px;padding:calc(32px + env(safe-area-inset-top,0px)) 24px 16px;text-align:center;max-width:520px;margin:0 auto;width:100%}
.gu-bv-halo{width:146px;height:146px;border-radius:50%;background:var(--color-brand-subtle);display:flex;align-items:center;justify-content:center}
.gu-bv-halo .gu-icono-play{width:104px;height:104px;flex-basis:104px;background:var(--color-brand);color:var(--color-on-brand);box-shadow:0 8px 18px rgba(29,147,48,.35)}
.gu-bv-halo .gu-icono-play svg{width:40px;height:40px;margin-left:4px}
.gu-bv-cuerpo h2{margin:0;font-family:var(--font-display);font-size:34px;font-weight:700;line-height:1.1}
.gu-bv-cuerpo p{margin:0;font-size:20px;line-height:1.4;color:var(--color-text-secondary)}
.gu-bv-botones{display:flex;flex-direction:column;gap:4px;padding:8px 24px calc(12px + env(safe-area-inset-bottom,0px));max-width:520px;margin:0 auto;width:100%}
.gu-bv-botones .gu-boton-marca{min-height:52px;width:100%;font-size:17px;display:flex;align-items:center;justify-content:center;gap:8px}
.gu-bv-botones .gu-boton-marca svg{width:16px;height:16px}
.gu-mas-tarde{min-height:48px;border:0;background:transparent;color:var(--color-brand-text);font-size:17px;font-weight:600;cursor:pointer}
@media (prefers-reduced-motion: reduce){.gu-punto,.gu-icono-play.gu-pulso::before,.gu-girando{animation:none}.gu-placa-barra>span{animation:none;width:100%}}
`;

  function inyectarEstilos() {
    if (document.getElementById('gu-estilos')) return;
    const s = document.createElement('style');
    s.id = 'gu-estilos';
    s.textContent = ESTILOS;
    document.head.appendChild(s);
  }

  // ─── Piezas de HTML ─────────────────────────────────────────────
  // Las claves de los recuadros: «v:<id>» por video y «l» para la videollamada.
  const claveCampo = video => (video == null || video === '' ? 'l' : 'v:' + video);
  const videoDeClave = k => (k === 'l' ? '' : k.slice(2));

  function htmlMotivo(motivo) {
    const { hacer, paraQue } = R.partes(motivo);
    if (!hacer && !paraQue) return '';
    return `<div class="gu-motivo">${paraQue ? `<p><span class="gu-marca-t">Para qué.</span> ${esc(paraQue)}</p>` : ''}${hacer ? `<p class="gu-hacer"><span class="gu-marca-t">Qué hacer.</span> ${esc(hacer)}</p>` : ''}</div>`;
  }

  function htmlContador(n) {
    if (n <= 800) return '';
    return n > MAX_TEXTO ? `Te pasaste: ${fmtNum(n)} de 1.000 caracteres` : `${fmtNum(n)} de 1.000 caracteres`;
  }

  // El valor del recuadro no va en el HTML: se pone después (así repintar no
  // depende de lo que se escribe).
  function htmlCampo(k, placeholder) {
    return `<div class="gu-campo"><textarea data-gu-campo="${esc(k)}" rows="2" placeholder="${esc(placeholder)}" aria-label="${esc(placeholder)}"></textarea><div class="gu-contador" data-gu-contador="${esc(k)}" aria-live="polite"></div></div>`;
  }

  function htmlEstadoEnvio(envio, listo, enCola) {
    let t = '', cls = '';
    if (envio === 'noSeGuardo') { t = 'No se pudo guardar, probá de nuevo o escribime por el chat.'; cls = ' gu-peligro'; }
    else if (envio === 'listo' && !enCola) t = listo;
    else if (envio === 'enviando' || envio === 'listo') t = enCola ? 'Se envía sola apenas tengas señal.' : listo;
    return `<span class="gu-envio-estado${cls}" role="status">${esc(t)}</span>`;
  }

  function htmlEncola(t) {
    return `<div class="gu-encola" aria-label="${esc('Enviando: ' + t)}">${I.reloj}<span>${esc(t)}</span></div>`;
  }

  function htmlDudaVideo(m, clip, despues) {
    const ya = R.renglones(clip.duda);
    const enCola = m.pendientesSinLlegar.filter(p => p.video === clip.id);
    const k = claveCampo(clip.id);
    let h = '<div class="gu-duda"><div class="gu-duda-titulo">¿Te quedó alguna duda de este video?</div>';
    if (ya.length || enCola.length) {
      h += '<div class="gu-ya">';
      if (ya.length) h += '<div class="gu-ya-titulo">Ya me dejaste</div>' + ya.map(d => `<p>${esc(d)}</p>`).join('');
      h += enCola.map(p => htmlEncola(p.texto)).join('');
      h += '</div>';
    }
    h += htmlCampo(k, despues ? 'Escribila acá y me llega' : 'Escribila acá y me llega antes de la videollamada');
    h += `<div class="gu-envio">${htmlEstadoEnvio(m.envios[clip.id], despues ? 'Listo, me llega y te contesto.' : 'Listo, me llega antes de la videollamada.', enCola.length > 0)}`;
    h += `<button type="button" class="gu-boton-marca" data-gu="enviar" data-k="${esc(k)}" disabled>Enviar duda</button></div></div>`;
    return h;
  }

  function htmlIconoClip(visto, actual, sonando) {
    if (visto) return `<span class="gu-icono gu-visto">${I.check}</span>`;
    if (actual) return `<span class="gu-icono ${sonando ? 'gu-sonando' : 'gu-es-actual'}">${sonando ? I.parlante : I.play}</span>`;
    return '<span class="gu-icono"></span>';
  }

  // ─── La vista de la guía (GuiaView + ControlReproductor) ────────
  let vistaAbierta = null;

  class Vista {
    constructor(m) {
      this.m = m;
      this.velocidad = 1;
      this.abiertos = new Set();
      this.motivos = new Set();
      this.volverA = null;
      this.portada = true;
      this.actualId = null;
      this.videoCargado = null;
      this.placaId = null;
      this.tPlaca = null;
      this.sinConexion = false;
      this.avance = new AvanceVideo(false);
      this.retomado = false;
      this.vpq = { abierto: null, video: null, avance: null, retomado: false, sinConexion: false };
      this.previo = {};
      this._rafId = 0;
      this._oyente = () => this.programar();
      this._foco = document.activeElement;
      this._overflow = document.documentElement.style.overflow;
      this.construir();
      m.oyentes.add(this._oyente);
      m.audios.alEmpezar = () => { this.pausar(); this.vpqPausar(); };
      m.audios.alAnunciar = t => { if (this.vivo) { this.vivo.textContent = ''; setTimeout(() => { if (this.vivo) this.vivo.textContent = t; }, 50); } };
      m.audios.alTic = () => this.pintarTicAudio();
    }

    get despues() { return R.yaPaso(this.m.guia && this.m.guia.fechaEntrega); }
    clips() { return R.deLaLista(this.m.guia); }
    get actual() {
      if (this.actualId == null) return null;
      const i = this.clips().findIndex(c => c.id === this.actualId);
      return i < 0 ? null : i;
    }
    get clipActual() { const i = this.actual; return i == null ? null : this.clips()[i]; }
    get hayAnterior() { const i = this.actual; return i != null && R.anterior(this.clips(), i) != null; }
    get haySiguiente() { const i = this.actual; return i != null && R.siguiente(this.clips(), i) != null; }
    get reproduciendo() { return !!this.video && !this.video.paused && !this.video.ended; }
    get pantallaCompleta() { return document.fullscreenElement === this.video || !!(this.video && this.video.webkitDisplayingFullscreen); }

    // ── El DOM ──
    construir() {
      inyectarEstilos();
      const root = document.createElement('div');
      root.className = 'gu-overlay';
      root.setAttribute('role', 'dialog');
      root.setAttribute('aria-modal', 'true');
      root.setAttribute('aria-label', 'Tu guía');
      root.innerHTML = `
        <div class="gu-barra"><span class="gu-barra-titulo">Tu guía</span>
          <button type="button" class="gu-cerrar" data-gu="cerrar" aria-label="Cerrar la guía">${I.cerrar}</button></div>
        <div class="gu-banner" data-gu-zona="banner" hidden>${I.sinRed}<span>Sin conexión: ves lo último que guardaste</span></div>
        <div class="gu-scroll" data-gu-zona="scroll"><div class="gu-contenido">
          <div data-gu-zona="estado"></div>
          <div class="gu-card" data-gu-zona="cabecera"></div>
          <section class="gu-card" data-gu-zona="reproductor" aria-label="Reproductor">
            <div class="gu-cuadro"><video playsinline webkit-playsinline controls preload="metadata" controlslist="nodownload"></video><div class="gu-capa" data-gu-zona="capa"></div></div>
            <div class="gu-banda" data-gu-zona="banda"></div>
            <div class="gu-actual" data-gu-zona="actual"></div>
          </section>
          <div data-gu-zona="resto" style="display:flex;flex-direction:column;gap:16px"></div>
        </div></div>
        <div class="gu-oculto" aria-live="polite" data-gu-zona="vivo"></div>`;
      this.root = root;
      this.z = {};
      root.querySelectorAll('[data-gu-zona]').forEach(el => { this.z[el.dataset.guZona] = el; });
      this.vivo = this.z.vivo;
      this.video = root.querySelector('video');
      this.conectarVideo();
      root.addEventListener('click', e => this.alClic(e));
      root.addEventListener('input', e => this.alEscribir(e));
      root.addEventListener('keydown', e => { if (e.key === 'Escape' && !this.pantallaCompleta) { e.preventDefault(); cerrarGuia(); } });
      this._visibilidad = () => {
        if (document.visibilityState === 'hidden') {
          this.pausar(); this.vpqPausar(); this.m.audios.cortar(); this.m.audios.cerrarSeccion();
        } else if (this.m.estado === 'lista') {
          this.m.audios.abrirSeccion();
        }
      };
      this._salida = () => { this.guardarAlSalir(); this.vpqGuardar(); };
      document.addEventListener('visibilitychange', this._visibilidad);
      window.addEventListener('pagehide', this._salida);
      document.body.appendChild(root);
      document.documentElement.style.overflow = 'hidden';
      setTimeout(() => { const b = root.querySelector('.gu-cerrar'); if (b) b.focus({ preventScroll: true }); }, 0);
    }

    destruir() {
      this.pausar();
      this.vpqCerrar(true);
      clearTimeout(this.tPlaca);
      cancelAnimationFrame(this._rafId); clearTimeout(this._tRespaldo); this._rafId = 0;
      this.m.audios.cortar();
      this.m.audios.cerrarSeccion();
      this.m.audios.alEmpezar = null; this.m.audios.alAnunciar = null; this.m.audios.alTic = null;
      this.m.oyentes.delete(this._oyente);
      document.removeEventListener('visibilitychange', this._visibilidad);
      window.removeEventListener('pagehide', this._salida);
      try { this.video.removeAttribute('src'); this.video.load(); } catch (_) { /* nada */ }
      this.root.remove();
      document.documentElement.style.overflow = this._overflow;
      if (this._foco && this._foco.focus && this._foco.isConnected) { try { this._foco.focus({ preventScroll: true }); } catch (_) { /* nada */ } }
    }

    conectarVideo() {
      const v = this.video;
      v.addEventListener('timeupdate', () => this.avanzo(v.currentTime));
      v.addEventListener('ended', () => this.termino());
      v.addEventListener('loadedmetadata', () => { ajustarCuadro(v); this.listo(); });
      v.addEventListener('error', () => {
        if (!v.getAttribute('src')) return;
        if (!this.portada || this.placaId) { this.sinConexion = true; this.programar(); }
      });
      v.addEventListener('play', () => {
        // Un solo video a la vez, y si grababa un audio, se frena.
        this.vpqPausar();
        this.m.audios.cortar();
        if (this.placaId) { clearTimeout(this.tPlaca); this.placaId = null; }
        this.portada = false;
        this.programar();
      });
      v.addEventListener('pause', () => this.programar());
    }

    // ── El reproductor ──
    prepararInicial() {
      if (this.actual != null) return;
      const i = R.inicial(this.clips());
      if (i == null) return;
      if (this.actualId != null) this.portada = true;
      this.cargar(i, false, false);
    }

    reproducir(i) { this.cargar(i, true, false); }
    siguiente() { const a = this.actual; if (a == null) return; const i = R.siguiente(this.clips(), a); if (i != null) this.cargar(i, true, true); }
    anterior() { const a = this.actual; if (a == null) return; const i = R.anterior(this.clips(), a); if (i != null) this.cargar(i, true, true); }

    empezar() {
      if (this.actual == null) { this.prepararInicial(); return; }
      this.portada = false;
      this.arrancar();
      this.programar();
    }

    cambiarVelocidad() {
      this.velocidad = R.velocidadSiguiente(this.velocidad);
      this.video.defaultPlaybackRate = this.velocidad;
      this.video.playbackRate = this.velocidad;
      this.programar();
    }

    cerrarPlaca() {
      if (!this.placaId) return;
      clearTimeout(this.tPlaca);
      this.placaId = null;
      this.arrancar();
      this.programar();
    }

    reintentar() {
      const i = this.actual;
      if (i == null) return;
      this.videoCargado = null;
      this.cargar(i, true, false);
    }

    guardarAlSalir() {
      const id = this.videoCargado;
      if (!id || !this.video.getAttribute('src')) return;
      const g = this.avance.alSalir(this.video.currentTime);
      if (g) this.m.avance(id, g.segundos, g.visto);
    }

    pausar() {
      this.guardarAlSalir();
      if (this.video && !this.video.paused) this.video.pause();
    }

    // Arrancó el «Ver por qué»: este se frena y, si estaba la placa, se va sin arrancar.
    frenarPorOtro() {
      clearTimeout(this.tPlaca);
      this.placaId = null;
      if (!this.video.paused) this.pausar();
      this.programar();
    }

    cargar(i, reproducir, conPlaca) {
      const lista = this.clips();
      const clip = lista[i];
      if (!clip || !clip.url) return;
      this.guardarAlSalir();
      clearTimeout(this.tPlaca);
      this.placaId = null;
      this.actualId = clip.id;
      this.abiertos.add(R.nombreBloque(clip));
      if (reproducir) this.portada = false;
      this.sinConexion = false;
      const v = this.video;
      if (this.videoCargado !== clip.id) {
        this.videoCargado = clip.id;
        this.avance = new AvanceVideo(clip.visto);
        this.retomado = false;
        if (navigator.onLine === false) {
          v.removeAttribute('src');
          try { v.load(); } catch (_) { /* nada */ }
          this.sinConexion = reproducir;
          this.programar();
          return;
        }
        v.src = clip.url;
        try { v.load(); } catch (_) { /* nada */ }
      }
      v.defaultPlaybackRate = this.velocidad;
      v.playbackRate = this.velocidad;
      // En pantalla completa la placa no se ve: ahí pasa directo.
      if (conPlaca && !this.pantallaCompleta) {
        v.pause();
        this.placaId = clip.id;
        this.tPlaca = setTimeout(() => this.cerrarPlaca(), PLACA_MS);
      } else if (reproducir) {
        this.arrancar();
      } else {
        v.pause();
      }
      this.programar();
    }

    arrancar() {
      const v = this.video;
      if (navigator.onLine === false && !v.getAttribute('src')) { this.sinConexion = true; this.programar(); return; }
      if (!v.getAttribute('src')) { const i = this.actual; if (i != null) { this.videoCargado = null; this.cargar(i, true, false); } return; }
      // Si ya había terminado, tocarlo de nuevo lo arranca desde el principio.
      if (R.estaAlFinal(v.currentTime, v.duration)) v.currentTime = 0;
      this.vpqPausar();
      this.m.audios.cortar();
      v.defaultPlaybackRate = this.velocidad;
      v.playbackRate = this.velocidad;
      const p = v.play();
      if (p && p.catch) {
        p.catch(err => {
          // El navegador no dejó arrancar solo (sin un toque): vuelve la portada.
          if (err && err.name === 'NotAllowedError') { this.portada = true; this.programar(); }
        });
      }
    }

    // Retoma donde quedó, una vez por carga.
    listo() {
      const v = this.video;
      v.playbackRate = this.velocidad;
      if (this.retomado) return;
      this.retomado = true;
      const c = this.m.guia && this.m.guia.clips.find(x => x.id === this.videoCargado);
      if (!c) return;
      const desde = R.retomar(c, v.duration);
      if (desde != null) {
        this.avance = new AvanceVideo(c.visto, desde);
        try { v.currentTime = desde; } catch (_) { /* nada */ }
      }
    }

    avanzo(t) {
      const v = this.video;
      if (this.placaId || v.paused || !this.videoCargado) return;
      const g = this.avance.alAvanzar(t, v.duration);
      if (g) this.m.avance(this.videoCargado, g.segundos, g.visto);
    }

    termino() {
      const id = this.videoCargado;
      if (!id) return;
      const g = this.avance.alTerminar(this.video.duration);
      this.m.avance(id, g.segundos, g.visto);
      // Pasa solo al siguiente, con su placa. Con una duda a medio escribir, no.
      if (this.haySiguiente && !R.textoParaMandar(this.m.borradores[id] || '')) this.siguiente();
      else this.programar();
    }

    // ── «Ver por qué» de un suplemento ──
    vpqVideo() {
      if (this.vpq.video) return this.vpq.video;
      const v = document.createElement('video');
      v.setAttribute('playsinline', ''); v.setAttribute('webkit-playsinline', '');
      v.controls = true; v.preload = 'metadata';
      v.setAttribute('controlslist', 'nodownload');
      v.addEventListener('timeupdate', () => {
        if (v.paused || !this.vpq.abierto || !this.vpq.avance) return;
        const g = this.vpq.avance.alAvanzar(v.currentTime, v.duration);
        if (g) this.m.avance(this.vpq.abierto, g.segundos, g.visto);
      });
      v.addEventListener('ended', () => {
        if (!this.vpq.abierto || !this.vpq.avance) return;
        const g = this.vpq.avance.alTerminar(v.duration);
        this.m.avance(this.vpq.abierto, g.segundos, g.visto);
      });
      v.addEventListener('loadedmetadata', () => {
        ajustarCuadro(v);
        if (this.vpq.retomado) return;
        this.vpq.retomado = true;
        const c = R.clipDeSuplemento(this.m.guia, this.vpq.abierto);
        const desde = c ? R.retomar(c, v.duration) : null;
        if (desde != null) { this.vpq.avance = new AvanceVideo(c.visto, desde); try { v.currentTime = desde; } catch (_) { /* nada */ } }
      });
      v.addEventListener('play', () => { this.frenarPorOtro(); this.m.audios.cortar(); });
      v.addEventListener('error', () => { if (v.getAttribute('src')) { this.vpq.sinConexion = true; this.programar(); } });
      this.vpq.video = v;
      return v;
    }

    vpqGuardar() {
      const v = this.vpq.video;
      if (!v || !this.vpq.abierto || !this.vpq.avance || !v.getAttribute('src')) return;
      const g = this.vpq.avance.alSalir(v.currentTime);
      if (g) this.m.avance(this.vpq.abierto, g.segundos, g.visto);
    }

    vpqPausar() {
      const v = this.vpq.video;
      if (!v || !this.vpq.abierto) return;
      this.vpqGuardar();
      if (!v.paused) v.pause();
    }

    vpqCerrar(sinPintar) {
      this.vpqPausar();
      this.vpq.abierto = null;
      const v = this.vpq.video;
      if (v) { v.removeAttribute('src'); try { v.load(); } catch (_) { /* nada */ } }
      if (!sinPintar) this.programar();
    }

    vpqAlternar(id) {
      if (this.vpq.abierto === id) { this.vpqCerrar(); return; }
      this.vpqCerrar(true);
      const c = R.clipDeSuplemento(this.m.guia, id);
      if (!c) { this.programar(); return; }
      this.vpq.abierto = id;
      this.vpq.avance = new AvanceVideo(c.visto);
      this.vpq.retomado = false;
      this.vpq.sinConexion = false;
      const v = this.vpqVideo();
      if (navigator.onLine === false) {
        this.vpq.sinConexion = true;
      } else {
        v.src = c.url;
        try { v.load(); } catch (_) { /* nada */ }
        this.frenarPorOtro();
        this.m.audios.cortar();
        const p = v.play();
        if (p && p.catch) p.catch(() => {});
      }
      this.programar();
    }

    vpqReintentar() {
      const id = this.vpq.abierto;
      if (!id) return;
      this.vpq.abierto = null;
      this.vpqAlternar(id);
    }

    // ── Eventos ──
    alClic(e) {
      const b = e.target.closest('[data-gu]');
      if (!b || !this.root.contains(b) || b.disabled) return;
      const a = b.dataset.gu;
      const m = this.m;
      switch (a) {
        case 'cerrar': cerrarGuia(); break;
        case 'reintentar-get': m.estado = m.guia ? 'lista' : 'cargando'; this.programar(); m.abrir().then(() => this.alLlegarGuia()); break;
        case 'empezar': this.empezar(); break;
        case 'placa': this.cerrarPlaca(); break;
        case 'reintentar-video': this.reintentar(); break;
        case 'anterior': this.anterior(); break;
        case 'siguiente': this.siguiente(); break;
        case 'velocidad': this.cambiarVelocidad(); break;
        case 'volver-lista': {
          const id = this.volverA;
          this.volverA = null;
          const fila = id && this.root.querySelector(`[data-gu-fila="${cssEsc(id)}"]`);
          if (fila) fila.scrollIntoView({ behavior: reducirMovimiento() ? 'auto' : 'smooth', block: 'center' });
          this.programar();
          break;
        }
        case 'bloque': {
          const t = b.dataset.b;
          if (this.abiertos.has(t)) this.abiertos.delete(t); else this.abiertos.add(t);
          this.programar();
          break;
        }
        case 'fila': {
          const i = Number(b.dataset.i);
          const c = this.clips()[i];
          if (!c) break;
          this.reproducir(i);
          this.volverA = c.id;
          this.z.reproductor.scrollIntoView({ behavior: reducirMovimiento() ? 'auto' : 'smooth', block: 'start' });
          break;
        }
        case 'motivo': {
          const id = b.dataset.id;
          if (this.motivos.has(id)) this.motivos.delete(id); else this.motivos.add(id);
          this.programar();
          break;
        }
        case 'enviar': {
          const k = b.dataset.k;
          if (k === 'l') m.enviarDudaLlamada(); else m.enviarDuda(videoDeClave(k));
          break;
        }
        case 'vpq': this.vpqAlternar(b.dataset.id); break;
        case 'vpq-reintentar': this.vpqReintentar(); break;
        case 'quitar': m.ponerQuitada(true); break;
        case 'volver-mostrar': m.ponerQuitada(false); break;
        case 'grabar': if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); m.audios.tocarGrabar(); break;
        case 'terminar': m.audios.terminar(); break;
        case 'escuchar': m.audios.alternarEscucha(); break;
        case 'mandar-audio': m.audios.mandar(); break;
        case 'regrabar': m.audios.grabarDeNuevo(); break;
        case 'borrar-audio': m.audios.borrar(); break;
        case 'reintentar-audio': m.audios.reintentar(b.dataset.id); break;
        default: break;
      }
    }

    alEscribir(e) {
      const t = e.target;
      if (!t || t.tagName !== 'TEXTAREA' || t.dataset.guCampo == null) return;
      const k = t.dataset.guCampo;
      this.m.borradores[videoDeClave(k)] = t.value;
      this.ajustarCampo(t, k);
    }

    ajustarCampo(t, k) {
      const c = this.root.querySelector(`[data-gu-contador="${cssEsc(k)}"]`);
      const n = largo(t.value);
      if (c) { c.textContent = htmlContador(n); c.classList.toggle('gu-peligro', n > MAX_TEXTO); }
      const b = this.root.querySelector(`[data-gu="enviar"][data-k="${cssEsc(k)}"]`);
      if (b) b.disabled = !R.textoParaMandar(t.value);
      t.style.height = 'auto';
      t.style.height = Math.min(t.scrollHeight + 3, 160) + 'px';
    }

    // Llegó una guía: el reproductor se prepara si su video ya no está.
    alLlegarGuia() {
      if (this.m.estado !== 'lista') return;
      this.prepararInicial();
      const c = this.clipActual;
      if (c) this.abiertos.add(R.nombreBloque(c));
      this.programar();
    }

    // ── Pintar ──
    // Un repintado por cuadro. Con la pestaña en segundo plano el navegador
    // frena requestAnimationFrame: el setTimeout lo cubre.
    programar() {
      if (this._rafId) return;
      const hacer = () => {
        if (!this._rafId) return;
        cancelAnimationFrame(this._rafId); clearTimeout(this._tRespaldo);
        this._rafId = 0;
        this.pintar();
      };
      this._rafId = requestAnimationFrame(hacer);
      this._tRespaldo = setTimeout(hacer, 120);
    }

    // Cada zona se reemplaza solo si cambió, y el foco y lo escrito se conservan.
    zona(nombre, html) {
      if (this.previo[nombre] === html) return false;
      this.previo[nombre] = html;
      const el = this.z[nombre];
      const a = document.activeElement;
      const campo = a && a.tagName === 'TEXTAREA' && el.contains(a) ? a.dataset.guCampo : null;
      const sel = campo != null ? [a.selectionStart, a.selectionEnd] : null;
      el.innerHTML = html;
      el.querySelectorAll('textarea[data-gu-campo]').forEach(t => {
        const k = t.dataset.guCampo;
        t.value = this.m.borradores[videoDeClave(k)] || '';
        this.ajustarCampo(t, k);
        if (campo != null && k === campo) {
          try { t.focus({ preventScroll: true }); t.setSelectionRange(sel[0], sel[1]); } catch (_) { /* nada */ }
        }
      });
      return true;
    }

    pintar() {
      const m = this.m;
      if (m.estado === 'oculta') { cerrarGuia(); return; }
      const lista = m.estado === 'lista' && m.guia;
      this.z.banner.hidden = !(lista && m.desdeCache);
      ['cabecera', 'reproductor', 'resto'].forEach(n => { this.z[n].hidden = !lista; });
      if (!lista) {
        this.zona('estado', m.estado === 'sinRed'
          ? `<div class="gu-estado">${I.sinRed}<h3>No pudimos traer tu guía</h3><p class="gu-sub">Se cortó la conexión. Probá de nuevo cuando tengas señal.</p><button type="button" class="gu-boton-sec" data-gu="reintentar-get">Reintentar</button></div>`
          : '<div class="gu-estado" aria-busy="true"><div class="gu-girando" role="progressbar" aria-label="Cargando tu guía"></div></div>');
        return;
      }
      this.zona('estado', '');
      const clips = this.clips();
      if (this.actual == null) this.prepararInicial();
      const despues = this.despues;
      this.zona('cabecera', this.htmlCabecera(clips, despues));
      this.zona('capa', this.htmlCapa(clips));
      this.zona('banda', this.htmlBanda(clips));
      const c = this.clipActual;
      this.zona('actual', c ? htmlMotivo(c.motivo) + htmlDudaVideo(m, c, despues) : '');
      this.z.actual.hidden = !c;
      if (this.zona('resto', this.htmlResto(clips, despues))) this.ubicarVpq();
      else if (this.vpq.abierto && this.vpq.video && !this.vpq.video.isConnected) this.ubicarVpq();
      this.pintarTicAudio();
    }

    // El video del «Ver por qué» vive fuera del HTML: se mueve a su lugar en
    // la misma tarea (así no se pausa).
    ubicarVpq() {
      const slot = this.z.resto.querySelector('[data-gu-slot="vpq"]');
      if (slot && this.vpq.video) { slot.insertBefore(this.vpq.video, slot.firstChild); ajustarCuadro(this.vpq.video); }
    }

    pintarTicAudio() {
      const a = this.m.audios;
      const c = this.root.querySelector('[data-gu-cuenta]');
      if (c && a.fase === 'grabando') c.textContent = contador(a.segundos);
      if (a.fase === 'revisando') {
        const e = a.escucha;
        const t = e && !e.paused ? e.currentTime : a.segundos;
        const cc = this.root.querySelector('[data-gu-cuenta-rev]');
        if (cc) cc.textContent = contador(t);
        const bar = this.root.querySelector('[data-gu-barra-rev]');
        if (bar) bar.style.width = `${Math.min(100, (e ? e.currentTime : 0) / Math.max(a.segundos, 0.1) * 100)}%`;
      }
    }

    htmlCabecera(clips, despues) {
      const g = this.m.guia;
      const a = R.avance(clips);
      const cuando = R.fechaLlamada(g.fechaEntrega);
      const hola = g.nombrePila ? `Hola ${g.nombrePila}` : 'Hola';
      const txt = despues
        ? 'Te dejo estos videos según lo que hablamos en la videollamada. Miralos con calma, te van a servir para arrancar bien.'
        : `Armé estos videos para vos${cuando ? `, antes de nuestra videollamada del ${cuando}` : ''}, según lo que me contaste. Si llegás a ver el primer bloque, en la llamada vamos directo a lo tuyo.`;
      return `<div class="gu-cab"><h2>${esc(hola)}</h2><p>${esc(txt)}</p><div class="gu-firma">Mati</div>
        <div style="margin-top:12px"><div class="gu-sub">${esc(R.textoAvance(a))}</div>
        <div class="gu-progreso" aria-hidden="true"><span style="width:${(R.fraccion(a) * 100).toFixed(1)}%"></span></div></div></div>`;
    }

    htmlCapa(clips) {
      const total = clips.length;
      if (this.placaId) {
        const i = clips.findIndex(c => c.id === this.placaId);
        const c = clips[i];
        if (c) {
          return `<button type="button" class="gu-placa" data-gu="placa" aria-label="${esc(c.titulo)}, tocá para empezar ya">
            <span class="gu-placa-ceja">${esc(R.textoPlaca(i, total))}</span>
            ${c.bloque ? `<span class="gu-placa-bloque">${esc(c.bloque)}</span>` : ''}
            <span class="gu-placa-titulo">${esc(c.titulo)}</span>
            <span class="gu-placa-barra"><span></span></span></button>`;
        }
      }
      if (this.sinConexion) {
        return `<div class="gu-sinvideo">${I.sinRed}<span>Necesitás conexión para ver el video</span><button type="button" class="gu-boton-sec" style="color:#fff;border-color:#fff" data-gu="reintentar-video">Reintentar</button></div>`;
      }
      const c = this.clipActual;
      if (this.portada && c) {
        const i = this.actual;
        return `<button type="button" class="gu-portada" data-gu="empezar" aria-label="${esc('Reproducir ' + c.titulo)}" title="${esc(`Video ${i + 1} de ${total}, ${R.duracionHablada(c.minutos)}`)}">
          <span class="gu-portada-titulo">${esc(c.titulo)}</span><span class="gu-linea-verde"></span>
          <span class="gu-portada-play">${I.play}</span></button>`;
      }
      return '';
    }

    htmlBanda(clips) {
      const c = this.clipActual, i = this.actual;
      let h = '';
      if (c) h += `<div class="gu-ceja">${esc(R.textoNumero(i, clips.length, c.bloque))}</div><h3>${esc(c.titulo)}</h3>`;
      h += '<div class="gu-botones">';
      if (this.hayAnterior) h += '<button type="button" class="gu-boton-chico" data-gu="anterior">Anterior</button>';
      if (this.haySiguiente) h += '<button type="button" class="gu-boton-chico" data-gu="siguiente">Siguiente</button>';
      const vel = R.textoVelocidad(this.velocidad);
      h += `<button type="button" class="gu-boton-chico" data-gu="velocidad" aria-label="Velocidad ${esc(vel)}" title="Cambia entre 1x, 1,25x y 1,5x">Velocidad ${esc(vel)}</button>`;
      if (this.volverA) h += '<button type="button" class="gu-boton-chico" data-gu="volver-lista">Volver a la lista</button>';
      return h + '</div>';
    }

    htmlBloque(b, clips) {
      const abierto = this.abiertos.has(b.titulo);
      const vistos = b.indices.filter(i => clips[i] && clips[i].visto).length;
      const sub = R.textoBloque(b) + (vistos > 0 ? `, ${vistos === b.indices.length ? 'todos vistos' : `${vistos} ${vistos === 1 ? 'visto' : 'vistos'}`}` : '');
      let h = `<div class="gu-card"><button type="button" class="gu-bloque-cab" data-gu="bloque" data-b="${esc(b.titulo)}" aria-expanded="${abierto}">
        <span><span class="gu-bloque-titulo">${esc(b.titulo)}</span><span class="gu-sub">${esc(sub)}</span></span>${I.chevron.replace('<svg', '<svg class="gu-chev"')}</button>`;
      if (abierto) {
        h += '<div class="gu-filas">';
        for (const i of b.indices) if (clips[i]) h += this.htmlFila(clips[i], i);
        h += '</div>';
      }
      return h + '</div>';
    }

    htmlFila(c, i) {
      const actual = this.actualId === c.id;
      const { hacer, paraQue } = R.partes(c.motivo);
      const tieneMotivo = !!(hacer || paraQue);
      const abierto = this.motivos.has(c.id);
      const sonando = actual && this.reproduciendo;
      const valor = [c.visto ? 'Visto' : 'Sin ver', actual ? 'Es el video actual' : null,
                     c.url ? R.duracionHablada(c.minutos) : 'Lo estoy subiendo'].filter(Boolean).join(', ');
      let h = `<div class="gu-fila${actual ? ' gu-fila-actual' : ''}" data-gu-fila="${esc(c.id)}"><div class="gu-fila-linea">
        <button type="button" class="gu-fila-boton" data-gu="fila" data-i="${i}" ${c.url ? '' : 'disabled'} aria-label="${esc(c.titulo + ', ' + valor)}">
          ${htmlIconoClip(c.visto, actual, sonando)}<span class="gu-fila-titulo">${esc(c.titulo)}</span>
          <span class="gu-dur">${esc(c.url ? R.duracion(c.minutos) : 'Lo estoy subiendo')}</span></button>`;
      if (tieneMotivo) {
        h += `<button type="button" class="gu-motivo-boton" data-gu="motivo" data-id="${esc(c.id)}" aria-label="Para qué sirve" aria-expanded="${abierto}">${I.chevron.replace('<svg', '<svg class="gu-chev"')}</button>`;
      }
      h += '</div>';
      if (abierto) h += htmlMotivo(c.motivo);
      return h + '</div>';
    }

    htmlLlamada(despues) {
      const m = this.m;
      const ya = m.dudasLlamadaVisibles;
      const enCola = m.pendientesSinLlegar.filter(p => p.video == null);
      let h = `<section class="gu-card gu-llamada" aria-label="Dudas para la videollamada">
        <h3>${despues ? '¿Te quedó algo para preguntarme?' : '¿Qué querés que hablemos en la videollamada?'}</h3>
        <p class="gu-recuadro">${despues ? 'Recorré tu plan con calma y si te surge alguna duda, anotala acá y te contesto.'
                                        : 'Recorré tu plan con calma y anotá acá todas las dudas que te surjan, así las vemos en la videollamada.'}</p>
        <p class="gu-nota">${despues ? 'Me llega y te contesto. Podés dejar varias.' : 'Me llega antes de la videollamada. Podés dejar varias.'}</p>`;
      if (ya.length || enCola.length) {
        h += '<div class="gu-lista-dudas">';
        if (ya.length) h += `<div class="gu-ya-titulo" style="padding-bottom:4px">${ya.length === 1 ? 'Ya me dejaste esta' : `Ya me dejaste estas ${ya.length}`}</div>`;
        h += ya.map(d => `<p>${esc(d)}</p>`).join('');
        h += enCola.map(p => htmlEncola(p.texto)).join('');
        h += '</div>';
      }
      if (m.puedeSumarDudaLlamada) {
        h += htmlCampo('l', despues ? 'Tu pregunta' : 'Por ejemplo, algo que no entendiste del plan o que querés cambiar');
        h += `<div class="gu-envio">${htmlEstadoEnvio(m.envios[''], despues ? 'Listo, me llega y te contesto.' : 'Listo, la vemos en la videollamada.', enCola.length > 0)}
          <button type="button" class="gu-boton-marca" data-gu="enviar" data-k="l" disabled>Enviar</button></div>`;
      } else {
        h += '<p class="gu-nota">Ya dejaste 30, que es el máximo. Si te queda algo, escribime por el chat.</p>';
      }
      if (m.audios.mostrar) h += this.htmlAudio(despues);
      return h + '</section>';
    }

    htmlAudio(despues) {
      const a = this.m.audios;
      let h = `<div class="gu-audio"><p class="gu-nota">${esc(TA.invitacion)}</p>`;
      if (a.fase === 'reposo' || a.fase === 'pidiendo') {
        h += `<div><button type="button" class="gu-boton-sec" data-gu="grabar" ${a.fase === 'pidiendo' || a.mandandoAlguno ? 'disabled' : ''}>${I.mic}${esc(TA.grabar)}</button></div>`;
        if (a.permiso === 'sinPreguntar') h += `<p class="gu-nota" style="font-size:12px">${esc(TA.antesDelPermiso)}</p>`;
      } else if (a.fase === 'grabando') {
        h += `<div class="gu-grabando"><button type="button" class="gu-terminar" data-gu="terminar" aria-label="${esc(TA.terminarAccesible)}" aria-pressed="true">${I.stop}${esc(TA.terminar)}</button>
          <span class="gu-punto" aria-hidden="true"></span><span class="gu-cuenta" data-gu-cuenta aria-hidden="true">${contador(a.segundos)}</span></div>`;
      } else if (a.fase === 'revisando') {
        const sonando = a.escucha && !a.escucha.paused;
        h += `<div class="gu-revision"><button type="button" class="gu-escuchar" data-gu="escuchar" ${a.url ? '' : 'disabled'} aria-label="${sonando ? 'Pausar tu audio' : 'Escuchar tu audio'}">${sonando ? I.pausa : I.play}</button>
          <span class="gu-barra-audio" aria-hidden="true"><span data-gu-barra-rev></span></span>
          <span class="gu-cuenta-chica" data-gu-cuenta-rev aria-label="${esc('Dura ' + contador(a.segundos))}">${contador(a.segundos)}</span></div>
          <div class="gu-botones" style="margin-top:0"><button type="button" class="gu-boton-marca" data-gu="mandar-audio" ${a.blob ? '' : 'disabled'}>${esc(TA.mandar)}</button>
          <button type="button" class="gu-boton-sec" data-gu="regrabar">${esc(TA.grabarDeNuevo)}</button>
          <button type="button" class="gu-boton-sec gu-rojo" data-gu="borrar-audio">${esc(TA.borrar)}</button></div>`;
      }
      if (a.aviso) {
        const gris = a.aviso === 'quedan30';
        h += `<p class="gu-nota${gris ? '' : ' gu-peligro'}">${esc(TA.avisos[a.aviso] || '')}</p>`;
      }
      for (const f of a.filas) {
        let ic = I.subiendo, cls = '', t = '', extra = '';
        if (f.estado === 'mandando') t = TA.mandando;
        else if (f.estado === 'noSeMando') { ic = I.alerta; cls = ' gu-peligro'; t = TA.noSeMando; extra = `<button type="button" class="gu-boton-sec" data-gu="reintentar-audio" data-id="${esc(f.id)}">${esc(TA.reintentar)}</button>`; }
        else if (f.estado === 'rechazado') { ic = I.alerta; cls = ' gu-peligro'; t = TA.avisos[f.aviso] || TA.noSeMando; }
        else if (f.estado === 'subido') { ic = I.listo.replace('<svg', '<svg class="gu-ok"'); t = TA.subido(despues); }
        else if (f.estado === 'error') { ic = I.alerta; cls = ' gu-peligro'; t = TA.errorTranscripcion; }
        h += `<div class="gu-fila-audio${cls}">${ic}<div><span>${esc(t)}</span>${extra}</div></div>`;
      }
      return h + '</div>';
    }

    htmlSupl(despues) {
      const s = vistaSuplementacion(this.m.guia.suplementacion);
      if (!s) return '';
      const neg = t => R.negritas(t).map(x => (x.negrita ? `<strong>${esc(x.texto)}</strong>` : esc(x.texto))).join('');
      let h = `<section class="gu-card gu-pad gu-supl" aria-label="${esc(s.titulo)}"><h3>${esc(s.titulo)}</h3>`;
      if (s.accion) h += `<p class="gu-sub" style="margin:0">${esc(s.accion)}</p>`;
      for (const mo of s.momentos) {
        h += `<div class="gu-momento"><div class="gu-momento-titulo" role="heading" aria-level="4">${esc(mo.titulo)}</div>`;
        for (const f of mo.filas) {
          h += `<div class="gu-item"><div class="gu-item-linea"><span class="gu-item-nombre">${esc(f.nombre)}${f.nuevo ? '<span class="gu-etq">nuevo</span>' : ''}${f.opcional ? '<span class="gu-etq gu-gris">opcional</span>' : ''}</span>${f.cantidad ? `<span class="gu-cant">${esc(f.cantidad)}</span>` : ''}</div>`;
          if (f.nota) h += `<p class="gu-sub">${esc(f.nota)}</p>`;
          if (f.porQue) h += `<p><span class="gu-marca-t">Por qué.</span> ${esc(f.porQue)}</p>`;
          for (const d of f.detalle) h += `<p class="gu-detalle">${neg(d)}</p>`;
          const c = R.clipDeSuplemento(this.m.guia, f.videoId);
          if (c) h += this.htmlVerPorQue(c, f.nombre, despues);
          h += '</div>';
        }
        h += '</div>';
      }
      if (s.sigue) h += `<div class="gu-momento"><p style="margin:0;font-size:14px"><strong>Sigue igual.</strong> ${esc(s.sigue)}</p></div>`;
      if (s.sale.length) {
        h += `<div class="gu-momento"><p style="margin:0;font-size:14px"><strong>Dejás de tomar.</strong> ${esc(s.sale.map(x => x.nombre).join(', '))}</p>`;
        for (const x of s.sale) if (x.porQue) h += `<p class="gu-nota">${esc(`${x.nombre}: ${x.porQue}`)}</p>`;
        h += '</div>';
      }
      return h + '</section>';
    }

    htmlVerPorQue(c, nombre, despues) {
      const abierto = this.vpq.abierto === c.id;
      const icono = abierto ? I.stop : c.visto ? I.listo.replace('<svg', '<svg class="gu-visto-t"') : I.play;
      const label = abierto ? `Cerrar el video de ${nombre}` : `${R.rotuloVerPorQue(c)}, ${nombre}${c.visto ? ', visto' : ''}`;
      let h = `<div class="gu-vpq"><button type="button" class="gu-vpq-boton" data-gu="vpq" data-id="${esc(c.id)}" aria-expanded="${abierto}" aria-label="${esc(label)}">${icono}${esc(abierto ? 'Cerrar el video' : R.rotuloVerPorQue(c))}</button>`;
      if (abierto) {
        h += '<div class="gu-vpq-cuadro" data-gu-slot="vpq">';
        if (this.vpq.sinConexion) h += `<div class="gu-sinvideo">${I.sinRed}<span>Necesitás conexión para ver el video</span><button type="button" class="gu-boton-sec" style="color:#fff;border-color:#fff" data-gu="vpq-reintentar">Reintentar</button></div>`;
        h += '</div>';
        h += htmlDudaVideo(this.m, c, despues);
      }
      return h + '</div>';
    }

    htmlResto(clips, despues) {
      const bloques = R.bloques(clips);
      let h = bloques.filter(b => b.esApp).map(b => this.htmlBloque(b, clips)).join('');
      h += this.htmlLlamada(despues);
      h += bloques.filter(b => !b.esApp).map(b => this.htmlBloque(b, clips)).join('');
      h += this.htmlSupl(despues);
      h += `<p class="gu-card gu-pie">${despues ? 'Si algún video no te carga o tenés algo para contarme, escribime por el chat.'
                                               : 'Si algún video no te carga o tenés algo para contarme antes de la llamada, escribime por el chat.'}</p>`;
      if (this.m.puedeQuitar) h += `<button type="button" class="gu-accion" data-gu="quitar" title="La guía queda en Mis datos">${I.ojoTachado}Quitar de Entreno</button>`;
      else if (this.m.puedeVolverAMostrar) h += `<button type="button" class="gu-accion" data-gu="volver-mostrar">${I.ojo}Volver a mostrar en Entreno</button>`;
      return h;
    }
  }

  function cssEsc(s) {
    return window.CSS && window.CSS.escape ? window.CSS.escape(s) : String(s).replace(/["\\]/g, '\\$&');
  }

  function cerrarGuia() {
    const v = vistaAbierta;
    if (!v) return;
    vistaAbierta = null;
    v.destruir();
    repintarTarjetas();
    window.dispatchEvent(new CustomEvent('mypump:guia', { detail: { tipo: 'cerrada' } }));
  }

  async function abrirGuia(token) {
    if (!tokenValido(token) || esDemo() || !db()) return false;
    if (vistaAbierta) return true;
    const m = modelo(token);
    if (m.estado === 'oculta') m.estado = m.guia ? 'lista' : 'cargando';
    const v = new Vista(m);
    vistaAbierta = v;
    v.pintar();
    v.alLlegarGuia();
    // El get, una vez por apertura.
    await m.abrir();
    if (vistaAbierta !== v) return true;
    v.alLlegarGuia();
    if (m.estado === 'lista') m.audios.abrirSeccion();
    if (m.cola.length) m.procesarCola();
    return true;
  }

  // ─── La tarjeta de Entreno (TarjetaGuia y TarjetaGuiaDestacada) ──
  const tarjetas = [];

  function htmlTarjeta(m) {
    if (m.tarjetaDestacada) {
      const a = m.avanceTarjeta;
      const t = R.textoTarjeta(a);
      const pulso = m.primeraSesionTarjeta && !reducirMovimiento();
      return `<div class="gu-tarjeta gu-destacada" role="group" aria-label="Tu guía">
        <div class="gu-dest-cab"><span class="gu-dest-ceja">Empezá por acá</span>
          <button type="button" class="gu-ocultar" data-gu-t="ocultar" title="La guía queda en Mis datos">Ocultar</button></div>
        <div class="gu-dest-fila"><span class="gu-icono-play${pulso ? ' gu-pulso' : ''}" aria-hidden="true">${I.play}</span>
          <div><div class="gu-dest-titulo">Tu guía</div><div class="gu-dest-sub">${esc(t)}</div></div></div>
        <div class="gu-barra-blanca" aria-hidden="true"><span style="width:${R.fraccion(a) > 0 ? Math.max(3, R.fraccion(a) * 100).toFixed(1) : 0}%"></span></div>
        <button type="button" class="gu-boton-blanco" data-gu-t="abrir">${I.play}${esc(R.botonTarjeta(a))}</button></div>`;
    }
    if (m.mostrarTarjeta) {
      const a = m.avanceTarjeta;
      const t = R.textoTarjeta(a);
      const r = 18, circ = 2 * Math.PI * r, f = R.fraccion(a);
      return `<button type="button" class="gu-tarjeta gu-compacta" data-gu-t="abrir" aria-label="${esc('Tu guía, ' + t)}">
        <span class="gu-anillo" aria-hidden="true"><svg viewBox="0 0 44 44"><circle cx="22" cy="22" r="${r}" fill="none" stroke="var(--color-bg-tertiary)" stroke-width="4"/>
          <circle cx="22" cy="22" r="${r}" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-dasharray="${(circ * f).toFixed(2)} ${circ.toFixed(2)}"/></svg>
          <span>${R.completo(a) ? I.check : I.play}</span></span>
        <span class="gu-compacta-texto" aria-hidden="true"><b>Tu guía</b><span class="gu-sub">${esc(t)}</span></span>
        ${I.chevron.replace('<svg', '<svg class="gu-chev" style="transform:rotate(-90deg)"')}</button>`;
    }
    return '';
  }

  function pintarTarjeta(reg) {
    const m = modelo(reg.token);
    const html = esDemo() ? '' : htmlTarjeta(m);
    if (reg.previo === html) return !!html;
    reg.previo = html;
    reg.contenedor.innerHTML = html;
    reg.contenedor.hidden = !html;
    if (html && m.tarjetaDestacada) m.marcarTarjetaVista();
    return !!html;
  }

  function repintarTarjetas() {
    for (let i = tarjetas.length - 1; i >= 0; i--) {
      if (!tarjetas[i].contenedor.isConnected) { tarjetas.splice(i, 1); continue; }
      pintarTarjeta(tarjetas[i]);
    }
  }
  oyentesGlobales.add(() => repintarTarjetas());

  function avisoOculta(token) {
    inyectarEstilos();
    const previo = document.querySelector('.gu-aviso-oculta');
    if (previo) previo.remove();
    const el = document.createElement('div');
    el.className = 'gu-aviso-oculta';
    el.setAttribute('role', 'status');
    el.innerHTML = `<span>${I.ojoTachado}La encontrás en Mis datos</span><button type="button" title="Vuelve a poner la guía en Entreno">Deshacer</button>`;
    let t = null;
    const sacar = () => { clearTimeout(t); el.remove(); };
    el.querySelector('button').addEventListener('click', () => { modelo(token).ponerQuitada(false); sacar(); });
    document.body.appendChild(el);
    t = setTimeout(sacar, 5000);
  }

  // ─── La bienvenida (BienvenidaGuia) ─────────────────────────────
  function mostrarBienvenida(m, nombreCuenta) {
    inyectarEstilos();
    const a = m.avanceTarjeta;
    const el = document.createElement('div');
    el.className = 'gu-bienvenida';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    el.setAttribute('aria-label', 'Tu guía');
    const titulo = R.tituloBienvenida(m.guia && m.guia.nombrePila, nombreCuenta);
    el.innerHTML = `<div class="gu-bv-cuerpo"><div class="gu-bv-halo"><span class="gu-icono-play${reducirMovimiento() ? '' : ' gu-pulso'}" aria-hidden="true">${I.play}</span></div>
      <div style="display:flex;flex-direction:column;gap:12px"><h2>${esc(titulo)}</h2><p>${esc(R.textoBienvenida(a))}</p></div></div>
      <div class="gu-bv-botones"><button type="button" class="gu-boton-marca" data-bv="ver">${I.play}Ver mi guía</button>
      <button type="button" class="gu-mas-tarde" data-bv="tarde" title="La guía te queda arriba de Entreno">Más tarde</button></div>`;
    const overflow = document.documentElement.style.overflow;
    const cerrar = () => { el.remove(); document.documentElement.style.overflow = overflow; };
    el.addEventListener('click', e => {
      const b = e.target.closest('[data-bv]');
      if (!b) return;
      cerrar();
      if (b.dataset.bv === 'ver') abrirGuia(m.token);
    });
    el.addEventListener('keydown', e => { if (e.key === 'Escape') cerrar(); });
    document.body.appendChild(el);
    document.documentElement.style.overflow = 'hidden';
    m.marcarBienvenidaVista();
    setTimeout(() => { const b = el.querySelector('[data-bv="ver"]'); if (b) b.focus({ preventScroll: true }); }, 0);
  }

  // ─── API pública ────────────────────────────────────────────────
  function resumenPublico(m) {
    const r = m.resumen;
    if (!r || !r.ok) return null;
    return {
      ok: true,
      total: r.total,
      vistos: r.vistos,
      minutos_restantes: r.minutosRestantes,
      fecha_entrega: r.fechaEntrega,
      mostrar_tarjeta: r.mostrarTarjetaServidor,
      // Lo que ya resolvieron las reglas de la app:
      tarjeta_en_entreno: m.mostrarTarjeta,
      fila_en_mis_datos: m.mostrarFila,
      quitada: m.quitada,
    };
  }

  // El cuadro de un video toma la proporción real del clip, con el alto topeado
  // en 78vh (el ancho baja en proporción): el video lo llena entero, sin franjas.
  function ajustarCuadro(v) {
    const c = v && v.parentElement;
    if (!c || !v.videoWidth || !v.videoHeight) return;
    const r = v.videoWidth / v.videoHeight;
    c.style.aspectRatio = `${v.videoWidth} / ${v.videoHeight}`;
    c.style.width = `min(100%, ${(78 * r).toFixed(2)}vh)`;
    c.classList.add('gu-ajustado');
  }

  window.MyPumpGuia = {
    // El resumen para la tarjeta (entregas_app_resumen, solo lee). null si no
    // hay guía, si falla sin nada guardado o en la demo.
    async cargarResumen(token) {
      if (!tokenValido(token) || esDemo() || !db()) return null;
      try {
        const m = modelo(token);
        await m.actualizarResumen();
        return resumenPublico(m);
      } catch (e) {
        console.warn('[guia] cargarResumen', e);
        return null;
      }
    },

    // Dibuja en `contenedor` la tarjeta verde, la compacta o nada. Se vuelve a
    // dibujar sola cuando cambia algo (el avance, Ocultar, Deshacer).
    async montarTarjeta(contenedor, token) {
      if (!contenedor) return false;
      inyectarEstilos();
      if (!tokenValido(token) || esDemo() || !db()) { contenedor.innerHTML = ''; contenedor.hidden = true; return false; }
      let reg = tarjetas.find(t => t.contenedor === contenedor);
      if (!reg) {
        reg = { contenedor, token, previo: null };
        tarjetas.push(reg);
        contenedor.addEventListener('click', e => {
          const b = e.target.closest('[data-gu-t]');
          if (!b || !contenedor.contains(b)) return;
          if (b.dataset.guT === 'abrir') abrirGuia(reg.token);
          else if (b.dataset.guT === 'ocultar') { modelo(reg.token).ponerQuitada(true); avisoOculta(reg.token); }
        });
      } else if (reg.token !== token) {
        reg.token = token; reg.previo = null;
      }
      pintarTarjeta(reg);
      try { await modelo(token).actualizarResumen(); } catch (_) { /* queda lo guardado */ }
      return pintarTarjeta(reg);
    },

    abrir(token) { return abrirGuia(token); },
    cerrar() { cerrarGuia(); },
    abierta() { return !!vistaAbierta; },

    // La bienvenida de la primera vez: con la tarjeta en Entreno, sin ningún
    // video visto y una sola vez por cliente. `opciones.nombre`: el nombre de
    // la cuenta, si la guía guardada no trae nombre_pila.
    async bienvenidaSiCorresponde(token, opciones) {
      if (!tokenValido(token) || esDemo() || !db() || vistaAbierta) return false;
      const m = modelo(token);
      if (m.bienvenidaVista) return false;
      try { await m.actualizarResumen(); } catch (_) { /* lo guardado */ }
      if (!m.mostrarBienvenida || vistaAbierta || document.querySelector('.gu-bienvenida')) return false;
      mostrarBienvenida(m, opciones && opciones.nombre);
      return true;
    },

    // Para la fila «Ver mi guía» de Mis datos (con el resumen ya cargado).
    quitada(token) { return tokenValido(token) ? modelo(token).quitada : false; },
    mostrarFila(token) { return tokenValido(token) && !esDemo() ? modelo(token).mostrarFila : false; },
    puedeVolverAMostrar(token) { return tokenValido(token) && !esDemo() ? modelo(token).puedeVolverAMostrar : false; },
    quitar(token) { if (tokenValido(token)) modelo(token).ponerQuitada(true); },
    volverAMostrar(token) {
      if (!tokenValido(token)) return false;
      const m = modelo(token);
      m.ponerQuitada(false);
      return m.mostrarTarjeta;
    },

    // Avisa cada vez que cambia algo de la guía (resumen, quitada, avance).
    alCambiar(fn) {
      if (typeof fn !== 'function') return () => {};
      oyentesGlobales.add(fn);
      return () => oyentesGlobales.delete(fn);
    },

    // Para pruebas: las reglas puras y los normalizadores.
    _reglas: R,
    _AvanceVideo: AvanceVideo,
    _vistaSuplementacion: vistaSuplementacion,
    _normalizarGuia: normalizarGuia,
    _normalizarResumen: normalizarResumen,
  };
})();
