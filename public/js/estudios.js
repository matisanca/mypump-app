/* =============================================================
   estudios.js — «Estudios y órdenes»: textos y reglas puras.

   Sigue estudios/CONTRATO_APP.md y da lo mismo que iOS y Android con los vectores
   de scripts/vectores-app/estudios.json. Acá no hay valores, rangos ni
   interpretación: documentos, fechas y estados. Lo que llega del servidor se
   decodifica campo por campo; «Mati lo vio» sale solo del `estado` del servidor.
   ============================================================= */
(function (raiz) {
  'use strict';

  const MAX_PX = 2400;
  const CALIDAD = 0.8;
  const TOPE_ARCHIVOS = 20;
  const TOPE_MB = 20;

  const T = {
    entradaMisDatos: 'Estudios y órdenes',
    subtituloEntrada: (n) => (!(n > 0) ? 'Todo al día' : n === 1 ? 'Te falta 1 estudio' : `Te faltan ${n} estudios`),
    titulo: 'Estudios',
    proximoControl: 'Próximo control',
    teFaltaHacer: 'Te falta hacer',
    subirResultado: 'Subir resultado',
    yaMeLoHice: 'Ya me lo hice',
    verOrden: 'Ver orden',
    deshacer: 'Deshacer',
    subirEstudio: 'Subir un estudio',
    tusOrdenes: 'Tus órdenes',
    tusEstudios: 'Tus estudios',
    ver: 'Ver',
    recibido: 'Recibido',
    matiLoVio: 'Mati lo vio',
    sinFecha: 'Sin fecha',
    ordenVencida: 'Vencida. Si la necesitás, pedísela a Mati por el chat.',
    notaRecibido: 'Recibido quiere decir que llegó. Mati lo revisa y te escribe. Si te sentís mal, no esperes: escribile o consultá a un médico.',
    vacio: 'Acá vas a ver los estudios que te pida Mati, tus órdenes y lo que nos mandes.',
    errorDeCarga: 'No se pudo cargar. Deslizá para reintentar.',
    cuandoTeLoHiciste: '¿Cuándo te lo hiciste?',
    guardar: 'Guardar',
    revisaLaFecha: 'Revisá la fecha.',
    guiaSubida: 'Subí todas las hojas juntas, en PDF o en fotos donde se lea bien.',
    sacarFotos: 'Sacar fotos',
    elegirFotos: 'Elegir fotos',
    elegirPDF: 'Elegir PDF',
    quitar: 'Quitar',
    enviarArchivos: (n) => (n === 1 ? 'Enviar 1 archivo' : `Enviar ${n} archivos`),
    topeArchivos: (n) => `Hasta ${n} archivos por envío.`,
    archivoMuyGrande: (mb) => `Ese archivo pesa más de ${mb} MB.`,
    subiendo: (i, n) => `Subiendo ${i} de ${n}`,
    sinSenal: 'Sin señal. Se envía solo cuando vuelva.',
    envioRecibido: 'Recibido. Mati lo revisa y te escribe.',
    topeDia: 'Ya mandaste varios envíos hoy. Probá mañana o escribile a Mati.',
    archivoRechazado: 'No pudimos leer ese archivo. Probá con una foto o un PDF.',
    comoPrepararte: 'Cómo prepararte',
    dondeHacerlo: 'Dónde hacerlo',
    noSePudoAbrir: 'No se pudo abrir. Probá de nuevo.',
    // Fuera del contrato: los mismos rótulos mínimos que usa la app (cierre, nombre de cada archivo, fallas de guardado y envío).
    cerrar: 'Cerrar',
    cancelar: 'Cancelar',
    foto: (n) => `Foto ${n}`,
    pdf: (n) => `PDF ${n}`,
    noSePudoGuardar: 'No se pudo guardar. Probá de nuevo.',
    noSePudoEnviar: 'No se pudo enviar. Probá de nuevo.',
    // Solo de la web: el botón que acompaña a «No se pudo…» (en la app es el gesto de deslizar). Ya aprobado en Técnica.
    probarDeNuevo: 'Probar de nuevo',
    noCierres: 'No cierres esta página.',
  };

  // ── Fechas: un día de calendario, sin hora ni zona ──
  const NOMBRES = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
  const dosCifras = (n) => String(n).padStart(2, '0');

  /* Acepta `AAAA-MM-DD` y lo que venga pegado detrás (una hora). null si no es una fecha que exista. */
  function dia(texto) {
    if (typeof texto !== 'string') return null;
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(texto);
    if (!m) return null;
    const anio = Number(m[1]), mes = Number(m[2]), d = Number(m[3]);
    if (anio < 1900 || mes < 1 || mes > 12 || d < 1) return null;
    const f = new Date(Date.UTC(anio, mes - 1, d));
    if (f.getUTCFullYear() !== anio || f.getUTCMonth() !== mes - 1 || f.getUTCDate() !== d) return null;
    return { anio, mes, dia: d };
  }

  /* El día de un instante (`enviado_en`) en la zona del teléfono. */
  function diaDeInstante(texto, zona) {
    if (typeof texto !== 'string' || !texto) return null;
    const t = Date.parse(texto);
    if (isNaN(t)) return null;
    try {
      const op = { year: 'numeric', month: '2-digit', day: '2-digit' };
      if (zona) op.timeZone = zona;
      const p = new Intl.DateTimeFormat('en-CA', op).formatToParts(new Date(t));
      const v = (k) => p.find((x) => x.type === k).value;
      return dia(`${v('year')}-${v('month')}-${v('day')}`);
    } catch (_) { return null; }
  }

  const numero = (d) => Math.round(Date.UTC(d.anio, d.mes - 1, d.dia) / 86400000);
  const antes = (a, b) => numero(a) < numero(b);
  const iso = (d) => `${String(d.anio).padStart(4, '0')}-${dosCifras(d.mes)}-${dosCifras(d.dia)}`;
  const corta = (d) => `${d.dia}/${d.mes}`;
  const conDia = (d) => `${NOMBRES[new Date(Date.UTC(d.anio, d.mes - 1, d.dia)).getUTCDay()]} ${corta(d)}`;

  /* Cuándo hay que hacer un pendiente. Sin fecha límite no se dice nada. `pasada` va en ámbar, nunca con tono de alarma. */
  function fechaPendiente(desde, hasta, hoy) {
    if (!hasta) return null;
    if (hoy && antes(hasta, hoy)) return { texto: `Era para el ${conDia(hasta)}`, pasada: true };
    if (desde && antes(desde, hasta)) return { texto: `Entre el ${conDia(desde)} y el ${conDia(hasta)}`, pasada: false };
    return { texto: `Antes del ${conDia(hasta)}`, pasada: false };
  }

  function fechaControl(desde, hasta) {
    if (desde && hasta) return numero(hasta) - numero(desde) <= 7 ? `Semana del ${corta(desde)}` : `Entre el ${conDia(desde)} y el ${conDia(hasta)}`;
    if (desde) return `Semana del ${corta(desde)}`;
    if (hasta) return `Antes del ${conDia(hasta)}`;
    return null;
  }

  const hecho = (f) => (f ? `Hecho el ${corta(f)}. Falta subir el resultado.` : 'Hecho. Falta subir el resultado.');
  const unir = (l) => l.filter(Boolean).join(' · ');
  const detalleOrden = (o) => unir([o.emitida && `Emitida el ${corta(o.emitida)}`, o.vence && `Vale hasta el ${corta(o.vence)}`]);
  const hojas = (n) => (typeof n === 'number' && n > 0 ? (n === 1 ? '1 hoja' : `${n} hojas`) : null);
  const archivos = (n) => (typeof n === 'number' && n > 0 ? (n === 1 ? '1 archivo' : `${n} archivos`) : null);
  const detalleEstudio = (x) => unir([x.fecha ? corta(x.fecha) : T.sinFecha, hojas(x.hojas)]);
  const tituloEnvio = (x) => (x.enviado ? `Envío del ${corta(x.enviado)}` : 'Envío');
  const lineaEnvio = (x) => unir([tituloEnvio(x), archivos(x.archivos), T.recibido]);

  // ── Lo que devuelve `mypump_estudios_get` ──
  const texto = (x) => (typeof x === 'string' && x.trim() ? x.trim() : null);
  const entero = (x) => (typeof x === 'number' && isFinite(x) && Math.round(x) === x && Math.abs(x) < 1000000 ? x : null);
  const objeto = (x) => !!x && typeof x === 'object' && !Array.isArray(x);
  const lista = (x) => (Array.isArray(x) ? x : []);
  const positivo = (x, d) => { const n = entero(x); return n !== null && n > 0 ? n : d; };

  /* Todo campo es opcional; un `tipo` o `estado` desconocido cae en el más prudente («pedido», «Recibido», «enviado»).
     null: no es una respuesta con `habilitado: true` (token caído, apagado o algo que no se entiende): no se muestra nada. */
  function decodificarEstado(j, zona) {
    if (!objeto(j) || j.habilitado !== true) return null;
    const topes = objeto(j.topes) ? j.topes : {};
    const pc = objeto(j.proximo_control) ? j.proximo_control : null;
    const conId = (x) => objeto(x) && !!texto(x.id);
    return {
      hoy: dia(j.hoy),
      topeArchivos: positivo(topes.archivos_por_envio, TOPE_ARCHIVOS),
      topeMB: positivo(topes.mb_por_archivo, TOPE_MB),
      proximoControl: pc ? { tipo: texto(pc.tipo), titulo: texto(pc.titulo) || 'Estudio', desde: dia(pc.desde), hasta: dia(pc.hasta) } : null,
      // Sin `id` no se puede hacer nada con un pendiente ni con una orden: no se muestran.
      pendientes: lista(j.pendientes).filter(conId).map((x) => ({
        id: texto(x.id), tipo: texto(x.tipo), titulo: texto(x.titulo) || 'Estudio', detalle: texto(x.detalle),
        desde: dia(x.desde), hasta: dia(x.hasta), hecho: x.estado === 'hecho', hechoFecha: dia(x.hecho_fecha), ordenId: texto(x.orden_id),
      })),
      ordenes: lista(j.ordenes).filter(conId).map((x) => ({
        id: texto(x.id), tipo: texto(x.tipo), titulo: texto(x.titulo) || 'Estudio', emitida: dia(x.emitida), vence: dia(x.vence),
        vigente: x.vigente !== false,       // solo un `false` explícito la cierra
      })),
      estudios: lista(j.estudios).map((x, i) => (objeto(x) ? {
        id: texto(x.id) || `sin-id-${i}`, tipo: texto(x.tipo), titulo: texto(x.titulo) || 'Estudio', fecha: dia(x.fecha), hojas: entero(x.hojas),
        visto: x.estado === 'visto',        // cualquier otro estado, conocido o no, es «Recibido»
        sePuedeAbrir: !!texto(x.id) && x.se_puede_abrir === true,
      } : null)).filter(Boolean),
      envios: lista(j.envios).map((x, i) => (objeto(x) ? {
        id: texto(x.id) || `sin-id-${i}`, borrador: x.estado === 'borrador', archivos: entero(x.archivos), pedidoId: texto(x.pedido_id),
        enviado: diaDeInstante(x.enviado_en, zona),
      } : null)).filter(Boolean),
    };
  }

  /* Los `borrador` son restos de una subida a medias: no se muestran. */
  const enviosVisibles = (e) => e.envios.filter((x) => !x.borrador);

  function bloques(e) {
    const b = { proximoControl: !!e.proximoControl, pendientes: e.pendientes.length > 0, ordenes: e.ordenes.length > 0, estudios: e.estudios.length > 0 || enviosVisibles(e).length > 0 };
    b.vacio = !b.proximoControl && !b.pendientes && !b.ordenes && !b.estudios;
    return b;
  }

  // ── Preparación y dónde: textos fijos por tipo (no salen de la orden) ──
  const CARDIO = new Set(['ecocardiograma', 'electrocardiograma', 'ergometria', 'eco_estres', 'mapa']);
  const PREPARACION = {
    laboratorio: [
      'Ayuno de 8 a 12 horas. Podés tomar agua, y andá bien hidratado.',
      'Extracción entre las 7 y las 10 de la mañana.',
      '48 horas antes: sin entrenar y sin alcohol.',
      '3 días antes: sin biotina (viene en suplementos para pelo y uñas y en algunos multivitamínicos).',
      'Si te piden orina, la primera de la mañana.',
      'Si estás enfermo o pasaste la noche sin dormir, mejor pasalo a otro día.',
    ],
    ecografia: ['Si es abdominal, ayuno de 6 a 8 horas.', 'Para otras ecografías, seguí lo que te indique el centro al sacar el turno.'],
    ecocardiograma: ['No necesita preparación.'],
    electrocardiograma: ['No necesita preparación.'],
    ergometria: ['Comida liviana 2 horas antes.', 'Ese día, sin café, mate ni tabaco.', 'Llevá ropa y zapatillas para hacer ejercicio.'],
    eco_estres: ['Comida liviana 2 horas antes.', 'Ese día, sin café, mate ni tabaco.', 'Llevá ropa y zapatillas para hacer ejercicio.'],
    mapa: ['Elegí un día común de semana.', 'En cada toma, dejá el brazo quieto y relajado.', 'Anotá lo que vas haciendo: comidas, entreno y sueño.', 'Con el aparato puesto no te podés duchar.'],
  };

  function preparacion(tipo) {
    const propio = Object.prototype.hasOwnProperty.call(PREPARACION, tipo) ? PREPARACION[tipo] : ['Seguí lo que te indique el centro al sacar el turno.'];
    const l = propio.slice();
    if (CARDIO.has(tipo)) l.push('Si tenés dolor de pecho, falta de aire o palpitaciones, avisale a Mati antes de hacerlo.');
    l.push('Si Mati te dio una indicación propia, vale esa.', 'No dejes ninguna medicación sin que Mati te lo diga.');
    return l;
  }

  function donde(tipo) {
    if (tipo === 'laboratorio') {
      return ['En cualquier laboratorio de análisis clínicos. Si tenés obra social o prepaga, en uno de tu cartilla: llevá la orden, tu credencial y tu DNI.',
        'Si podés, siempre en el mismo laboratorio: así los resultados se comparan mejor.'];
    }
    return ['En un centro de diagnóstico o de cardiología, con turno. Si tenés obra social o prepaga, en uno de tu cartilla: llevá la orden, tu credencial y tu DNI.'];
  }

  // ── Subida ──
  const MIME = { pdf: 'application/pdf', jpeg: 'image/jpeg' };

  /* Lo único que acepta el servidor: un PDF (`%PDF-`) o un JPEG. null = otra cosa. Alcanza con los primeros 5 bytes. */
  function formato(b) {
    if (!b || b.length < 3) return null;
    if (b.length >= 5 && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46 && b[4] === 0x2d) return 'pdf';
    if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'jpeg';
    return null;
  }

  /* ¿Entra este archivo en el envío que se está armando? → 'ok' | 'tope' | 'muyGrande' | 'ilegible' */
  function puedeAgregar({ bytes, formato: f, yaHay, topeArchivos = TOPE_ARCHIVOS, topeMB = TOPE_MB }) {
    if (yaHay >= topeArchivos) return 'tope';
    if (!f || !(bytes > 0)) return 'ilegible';
    if (bytes > topeMB * 1024 * 1024) return 'muyGrande';
    return 'ok';
  }

  /* 200 con `ok` es hecho (también con `ya`); 429 y 5xx, más tarde; cualquier otro 4xx es definitivo para ese archivo. */
  function clasificarSubida(status, ok) {
    if (status >= 200 && status < 300) return ok === true ? 'ok' : 'reintentar';
    if (status === 429) return 'reintentar';
    if (status >= 400 && status < 500) return 'descartar';
    return 'reintentar';
  }

  /* «Subiendo 2 de 5»: el que está subiendo ahora, sin pasarse del total. */
  function progreso(subidos, total) {
    const n = Math.max(total, 1);
    return T.subiendo(Math.min(Math.max(subidos + 1, 1), n), n);
  }

  const API = {
    MAX_PX, CALIDAD, TOPE_ARCHIVOS, TOPE_MB, MIME, T,
    dia, diaDeInstante, iso, corta, conDia, fechaPendiente, fechaControl, hecho,
    detalleOrden, detalleEstudio, hojas, archivos, tituloEnvio, lineaEnvio,
    decodificarEstado, enviosVisibles, bloques, preparacion, donde,
    formato, puedeAgregar, clasificarSubida, progreso,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Estudios = API;
})(typeof window !== 'undefined' ? window : globalThis);
