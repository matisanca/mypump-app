/* =============================================================
   tecnica.js — «Técnica por video»: textos y reglas puras.

   Sigue tecnica/CONTRATO_APP.md. Todo texto que ve el alumno está acá y sale de
   TEXTOS_PARA_OK.md. El alumno nunca lee que hubo un análisis automático: la única
   mención es el aviso de terceros. Lo que llega del servidor se decodifica campo
   por campo: confianza, códigos, ángulos o mediciones no pasan aunque vengan.
   ============================================================= */
(function (raiz) {
  'use strict';

  const G = (typeof module !== 'undefined' && module.exports) ? require('./gimnasio.js') : raiz.Gimnasio;

  const RECHAZOS = {
    corto: 'El video es muy corto. Grabá al menos 2 o 3 repeticiones completas.',
    largo: 'El video es muy largo. Mandá una sola serie, de hasta 75 segundos.',
    pesado: 'El video pesa demasiado. Probá con uno más corto.',
    ilegible: 'No pudimos abrir el video. Probá grabarlo de nuevo.',
    sinPersona: 'No te vemos en el video. Apoyá el teléfono a unos 3 metros, con todo el cuerpo adentro del cuadro.',
    oscuro: 'El video quedó muy oscuro. Grabá con más luz.',
    quemado: 'El video quedó quemado por la luz. Evitá grabar contra una ventana.',
    movido: 'El video está muy movido o fuera de foco. Apoyá el teléfono y grabá de nuevo.',
  };

  const T = {
    avisoBreve: 'Mati revisa tu video antes de que te llegue la devolución. El video se borra a los 90 días y lo podés sacar cuando quieras.',
    mandar: 'Mandar mi técnica',
    titulo: 'Mi técnica',
    consejo: 'Apoyá el teléfono a unos 3 metros, a la altura de la cadera. De costado es lo mejor para casi todos los ejercicios. Que entre todo tu cuerpo. Una serie, de hasta 75 segundos. No grabes a otras personas.',
    notaPlaceholder: '¿Querés que mire algo en particular?',
    enviar: 'Enviar a Mati',
    subiendo: 'Subiendo tu video',
    recibido: 'Recibido. Mati lo va a mirar y te llega la devolución en 1 a 2 días.',
    tituloDevolucion: (ej) => `Tu técnica en ${ej}`,
    credito: 'Lo revisó Mati',
    creditoEl: (f) => `Lo revisó Mati el ${f}`,
    bien: 'Lo que está bien',
    corregir: 'Para corregir',
    queSeVe: 'Qué se ve',
    porQue: 'Por qué importa',
    como: 'Cómo hacerlo',
    verEnVideo: 'Ver en el video',
    noSePudoVer: 'Lo que no se pudo ver',
    otroVideo: 'Mandame otro video',
    sinCorrecciones: 'Mati miró tu serie y no hay nada para corregir. Seguí así.',
    topeSemana: (n) => `Ya mandaste ${n} videos esta semana. Vas a poder mandar otro en unos días.`,
    enRevision: 'Ya tenés un video en revisión.',
    // Reusados de la sección de Gimnasio, ya en la lista.
    esperandoSenal: 'Esperando señal',
    sinSenal: 'Se cortó la conexión. Probá de nuevo cuando tengas señal.',
    errorGenerico: 'No se pudo enviar. Probá de nuevo',
    cerrar: 'Cerrar',
    grabarAhora: 'Grabar ahora',
    elegirGaleria: 'Elegir de la galería',
    cancelar: 'Cancelar',
    // Nuevos de la web, agregados a TEXTOS_PARA_OK.md.
    elegirEjercicio: 'Elegí el ejercicio',
    grabarOElegir: 'Grabar o elegir un video',
    cambiarVideo: 'Cambiar el video',
    preparandoVideo: 'Preparando el video',
    noSubio: 'No se pudo subir tu video. Revisá la conexión y probá de nuevo.',
    probarDeNuevo: 'Probar de nuevo',
    sinEnvios: 'Todavía no mandaste ningún video.',
    sacarVideo: 'Sacar mi video',
    sacarConfirma: '¿Sacás tu video? Si todavía no te llegó la devolución, el envío se cancela.',
    videoSacado: 'Listo, sacamos tu video.',
    enAnalisis: 'Mati está mirando este video. Probá sacarlo en un rato.',
    noCargoVideo: 'No se pudo cargar el video. Probá de nuevo.',
    rechazos: RECHAZOS,
  };

  const ESTADOS = new Set(['borrador', 'enviado', 'publicado', 'rechazado']);
  const TOPES_BASE = { duracionMin: 4, duracionMax: 75, bytesMax: 62914560, porSemana: 3 };
  const MAX_NOTA = 300;
  const SIETE_DIAS_MS = 7 * 24 * 3600 * 1000;

  const texto = (x) => (typeof x === 'string' && x.trim() ? x.trim() : null);
  const positivo = (x, d) => (typeof x === 'number' && isFinite(x) && x > 0 ? x : d);

  function decodificarDevolucion(d) {
    if (!d || typeof d !== 'object' || Array.isArray(d)) return null;
    const lista = (x) => (Array.isArray(x) ? x : []);
    const correcciones = lista(d.correcciones).map((c, i) => {
      if (!c || typeof c !== 'object' || !texto(c.titulo)) return null;
      return {
        orden: typeof c.prioridad === 'number' && isFinite(c.prioridad) ? c.prioridad : 1000 + i,
        titulo: texto(c.titulo), queSeVe: texto(c.que_se_ve), porQue: texto(c.por_que), como: texto(c.como_corregir),
        momento: typeof c.momento_s === 'number' && isFinite(c.momento_s) && c.momento_s >= 0 ? c.momento_s : null,
      };
    }).filter(Boolean).sort((a, b) => a.orden - b.orden);
    const otro = d.pedir_otro_video && typeof d.pedir_otro_video === 'object' ? d.pedir_otro_video : null;
    return {
      ejercicio: texto(d.ejercicio),
      bien: lista(d.bien).map(texto).filter(Boolean),
      correcciones,
      noEvaluable: lista(d.no_evaluable).map((n) => (n && typeof n === 'object' && texto(n.que) ? { que: texto(n.que), motivo: texto(n.motivo) } : null)).filter(Boolean),
      pedirOtro: otro && otro.necesario === true ? { como: texto(otro.como) } : null,
    };
  }

  function decodificarEnvio(x) {
    if (!x || typeof x !== 'object' || typeof x.id !== 'string' || !ESTADOS.has(x.estado)) return null;
    const devolucion = x.estado === 'publicado' ? decodificarDevolucion(x.devolucion) : null;
    return {
      id: x.id.toLowerCase(), estado: x.estado, ejercicioSlug: texto(x.ejercicio_slug), ejercicioNombre: texto(x.ejercicio_nombre),
      nota: texto(x.nota_alumno), enviadoEn: texto(x.enviado_en), tieneVideo: x.tiene_video === true,
      rechazoTexto: texto(x.rechazo_texto), publicadoEn: texto(x.publicado_en), devolucion,
    };
  }

  /* null: token caído, apagado o una respuesta que no se entiende. En todos esos casos no se muestra nada. */
  function decodificarEstado(j) {
    if (!j || typeof j !== 'object' || j.habilitado !== true) return null;
    const t = j.topes && typeof j.topes === 'object' ? j.topes : {};
    return {
      topes: {
        duracionMin: positivo(t.duracion_min_s, TOPES_BASE.duracionMin),
        duracionMax: positivo(t.duracion_max_s, TOPES_BASE.duracionMax),
        bytesMax: positivo(t.bytes_max, TOPES_BASE.bytesMax),
        porSemana: positivo(t.por_semana, TOPES_BASE.porSemana),
      },
      envios: (Array.isArray(j.envios) ? j.envios : []).map(decodificarEnvio).filter(Boolean),
    };
  }

  /* Un publicado sin devolución legible se muestra como «en camino»: nunca una pantalla vacía. */
  const conDevolucion = (e) => e.estado === 'publicado' && !!e.devolucion;

  /* Solo salen textos aprobados: si el servidor manda otra cosa (un código, por ejemplo), va el genérico. */
  function textoRechazo(s) {
    return Object.values(RECHAZOS).includes(s) ? s : RECHAZOS.ilegible;
  }

  /* MP4 y MOV empiezan con la caja `ftyp`. El contrato pide H.264 o HEVC: lo demás el servidor lo va a rechazar, mejor no gastar los datos. */
  function esMp4OMov(bytes) {
    if (!bytes || bytes.length < 8) return false;
    return bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70;
  }

  /* → null si puede salir, o la clave del rechazo. Duración desconocida (el navegador no decodifica ese códec): decide el servidor. */
  function validarVideo({ bytes, duracion, contenedorOk }, topes) {
    if (!bytes || !contenedorOk) return 'ilegible';
    if (bytes > topes.bytesMax) return 'pesado';
    if (typeof duracion === 'number' && isFinite(duracion)) {
      if (duracion > topes.duracionMax) return 'largo';
      if (duracion < topes.duracionMin) return 'corto';
    }
    return null;
  }

  /* Contrato: 4xx definitivo; 429 y 5xx, reintentar. El texto del rechazo sale del `error` que manda el servidor. */
  function clasificarSubida(status, json) {
    if (status >= 200 && status < 300) return json && json.ok === true ? { accion: 'ok' } : { accion: 'reintentar' };
    if (status === 429 || status >= 500 || status < 400) return { accion: 'reintentar' };
    const error = String((json && json.error) || '').toLowerCase();
    if (status === 413) return { accion: 'descartar', aviso: RECHAZOS.pesado };
    if (status === 400) {
      if (/muy corto/.test(error)) return { accion: 'descartar', aviso: RECHAZOS.corto };
      if (/muy largo/.test(error)) return { accion: 'descartar', aviso: RECHAZOS.largo };
      if (/pesado/.test(error)) return { accion: 'descartar', aviso: RECHAZOS.pesado };
      if (/leer|mp4|mov|largo incorrecto|ilegible|cuerpo/.test(error)) return { accion: 'descartar', aviso: RECHAZOS.ilegible };
    }
    return { accion: 'descartar', aviso: T.errorGenerico, refrescar: true };
  }

  /* Lo que frena antes de grabar. El servidor es el que decide; esto evita que alguien filme para nada. */
  function bloqueo(estado, enCola, ahora) {
    if (!estado) return null;
    if (enCola > 0 || estado.envios.some((e) => e.estado === 'enviado')) return 'enRevision';
    const desde = ahora - SIETE_DIAS_MS;
    const ultimos = estado.envios.filter((e) => {
      if (e.estado === 'rechazado' || e.estado === 'borrador' || !e.enviadoEn) return false;
      const t = Date.parse(e.enviadoEn);
      return !isNaN(t) && t > desde;
    }).length;
    return ultimos >= estado.topes.porSemana ? 'tope' : null;
  }

  const notaRecortada = (s) => Array.from(String(s == null ? '' : s)).slice(0, MAX_NOTA).join('');

  function slugDe(nombre) {
    return String(nombre || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
      .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 120);
  }

  /* La lista para elegir: cada ejercicio de la rutina una sola vez, sin cardio, con los sustitutos ya aplicados. */
  function ejerciciosDeRutina(dias, efectivo, esCardio) {
    const vistos = new Set();
    const salida = [];
    for (const d of Array.isArray(dias) ? dias : []) {
      for (const b of (d && d.bloques) || []) {
        for (const crudo of (b && b.ejercicios) || []) {
          const ex = efectivo ? efectivo(crudo) : crudo;
          const nombre = ex && texto(ex.nombre);
          if (!nombre || (esCardio && esCardio(ex))) continue;
          const clave = nombre.toLowerCase();
          if (vistos.has(clave)) continue;
          vistos.add(clave);
          salida.push(ejercicioDe(ex));
        }
      }
    }
    return salida;
  }

  function ejercicioDe(ex) {
    const nombre = String(ex.nombre).trim().slice(0, 120);
    const slug = texto(ex._swapSlug) || texto(ex._origSlug) || texto(ex.catalogo_slug) || slugDe(nombre);
    return { slug: String(slug).slice(0, 120), nombre };
  }

  const API = {
    T, MAX_NOTA, TOPES_BASE, decodificarEstado, decodificarEnvio, decodificarDevolucion, conDevolucion, textoRechazo,
    esMp4OMov, validarVideo, clasificarSubida, bloqueo, notaRecortada, slugDe, ejerciciosDeRutina, ejercicioDe, fechaCorta: G.fechaCorta,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Tecnica = API;
})(typeof window !== 'undefined' ? window : globalThis);
