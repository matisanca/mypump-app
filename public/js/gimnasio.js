/* =============================================================
   gimnasio.js — «Gimnasio por fotos»: reglas puras y textos.

   Sin red, sin pantalla y sin almacenamiento. Gemelo de Gimnasio.swift y
   TextosGimnasio.swift (rama nativa-gimnasio). Vectores comunes con las apps:
   scripts/vectores-app/gimnasio.json, que corre scripts/test-gimnasio.mjs.
   Contrato con el servidor: gimnasio/CONTRATO_APP.md.
   ============================================================= */
(function (raiz) {
  'use strict';

  const ZONAS = [
    { clave: 'poleas', nombre: 'Poleas', pedido: 'Cada torre y cruce, entero. El peso máximo de la pila' },
    { clave: 'accesorios_polea', nombre: 'Accesorios de polea', pedido: 'Sogas, barras V, rectas, agarres, tobilleras, todos juntos en el piso o colgados' },
    { clave: 'piernas', nombre: 'Máquinas de piernas', pedido: 'Prensa, hack, péndulo, extensora, femorales, aductores, abductores, gemelos, hip thrust' },
    { clave: 'empuje', nombre: 'Máquinas de empuje', pedido: 'Pecho, inclinado, hombros, pec deck, fondos' },
    { clave: 'tiron', nombre: 'Máquinas de tirón', pedido: 'Dorsalera, remos, dominadas asistidas, bíceps, tríceps' },
    { clave: 'barras_racks', nombre: 'Barras y racks', pedido: 'Barras olímpicas y Z, smith, racks, paralelas, barra de dominadas' },
    { clave: 'discos', nombre: 'Discos', pedido: 'Todo el soporte, de cerca: que se lean los números. Incluí los más chicos' },
    { clave: 'mancuernas', nombre: 'Mancuernas', pedido: 'El rack entero, de punta a punta: que se lea hasta cuánto llega' },
    { clave: 'bancos', nombre: 'Bancos', pedido: 'Planos, regulables, Scott' },
    { clave: 'otros', nombre: 'Otros', pedido: 'Bandas, kettlebells, TRX, lo que haya' },
  ];
  const ZONA_OPCIONAL = 'otros';
  const TOPE_FOTOS = 80;
  const MAX_NOTA = 300;
  const MAX_PX = 1600;
  const CALIDAD = 0.8;
  const MAX_BYTES = 8 * 1024 * 1024;
  const KILOS_MAXIMO = 400;

  const T = {
    tarjetaTitulo: 'Tu gimnasio',
    entradaMisDatos: 'Mi gimnasio',
    confirmarTarjeta: 'Confirmanos qué de esto hay en tu gimnasio',
    inicioBajada: 'Sacale fotos a lo que hay y adaptamos tu plan a tus máquinas',
    botonReintentar: 'Probar de nuevo',
    consejoPermiso: 'Si tu gimnasio no deja, pedí permiso o sacalas en un horario tranquilo',
    noHay: 'No hay en mi gimnasio',
    noHayCorto: 'No hay',
    sinFotos: 'Sin fotos',
    opcional: 'Opcional',
    consejoCamara: 'La máquina entera, de costado. Si hay alguien, esperá a que se vaya: no sacamos fotos con gente',
    agregarFoto: 'Sacar o elegir foto',
    borrarFoto: 'Borrar foto',
    subiendo: 'Subiendo…',
    esperandoSenal: 'Esperando señal',
    revisarYEnviar: 'Revisar y enviar',
    tope: 'Llegaste al máximo de 80 fotos',
    fotoRechazada: 'Una foto no se pudo usar. Sacala de nuevo',
    noSeGuardo: 'No se pudo guardar la foto en el teléfono. Probá de nuevo',
    sinSenal: 'Se cortó la conexión. Probá de nuevo cuando tengas señal.',
    revisarTitulo: 'Revisar y enviar',
    notaPlaceholder: 'Algo que no se vea en las fotos',
    botonEnviar: 'Enviar a Mati',
    enviandoSeguir: 'Queda guardado y se envía solo cuando vuelva la señal',
    sinNovedad: 'Sumá una foto o marcá algo que ya no esté',
    errorGenerico: 'No se pudo enviar. Probá de nuevo',
    recibido: 'Recibido. Mati lo está viendo. Te avisamos por WhatsApp',
    sinCambios: 'Mati revisó tu gimnasio y tu rutina encaja tal cual',
    anterior: 'Anterior',
    siguiente: 'Siguiente',
    noSe: 'No sé',
    si: 'Sí',
    no: 'No',
    noPuedoFoto: 'No puedo sacarla',
    marcarTodas: 'Marcá todas las que haya: lo que no marques cuenta como que no está',
    elegirKilos: 'Kilos',
    kilosInvalidos: 'Poné un número entre 1 y 400',
    faltaAlgo: 'Falta algo',
    yaNoEsta: 'Esto ya no está',
    cambieDeGimnasio: 'Cambié de gimnasio',
    marcarLoQueNoEsta: 'Marcá lo que ya no está',
    volverAEditar: 'Volver a editar',
    cerrar: 'Cerrar',
    listoTeclado: 'Listo',
    kg: 'kg',
    cuentaFotos: (n) => (n === 1 ? '1 foto' : `${n} fotos`),
    faltanZonas: (n) => (n === 1 ? 'Te falta 1 zona' : `Te faltan ${n} zonas`),
    subiendoFotos: (h, t) => `Subiendo tus fotos: ${h} de ${t}`,
    adaptadoPorMati: (f) => `Adaptado por Mati el ${f}`,
    necesitamosFotos: (n) => (n === 1 ? 'Necesitamos 1 foto más' : `Necesitamos ${n} fotos más`),
    preguntaDe: (i, n) => `Pregunta ${i} de ${n}`,
  };

  const nombreZona = (clave) => (ZONAS.find((z) => z.clave === clave) || {}).nombre || clave;
  const comoSet = (x) => (x instanceof Set ? x : new Set(x || []));

  // ── Zonas y tope ──
  function zonasFaltantes(conFotos, noHay, modo = 'completa') {
    if (modo !== 'completa') return [];
    const con = comoSet(conFotos), no = comoSet(noHay);
    return ZONAS.map((z) => z.clave).filter((c) => c !== ZONA_OPCIONAL && !con.has(c) && !no.has(c));
  }
  function puedeEnviar(modo, conFotos, noHay, quitar) {
    if (modo === 'completa') return zonasFaltantes(conFotos, noHay).length === 0;
    return comoSet(conFotos).size > 0 || comoSet(quitar).size > 0;
  }
  const restan = (enServidor, enCola) => Math.max(0, TOPE_FOTOS - enServidor - enCola);
  const puedeAgregar = (enServidor, enCola) => restan(enServidor, enCola) > 0;
  const notaRecortada = (s) => Array.from(String(s == null ? '' : s)).slice(0, MAX_NOTA).join('');

  // ── Pantallas ──
  function pantalla(abierta, hayVigente) {
    if (abierta == null || abierta === 'reemplazado' || abierta === 'listo') return hayVigente ? 'listo' : 'inicio';
    if (abierta === 'borrador') return 'zonas';
    if (abierta === 'a_confirmar') return 'preguntas';
    return 'recibido';
  }
  const tarjetaVisible = (habilitado, abierta, hayVigente) => !!habilitado && (!hayVigente || abierta === 'a_confirmar');
  const entradaVisible = (habilitado, hayVigente) => !!habilitado && !!hayVigente;

  // ── Cola de subida: todo 4xx salvo 429 es definitivo; 5xx y 429, reintentar ──
  function clasificarSubida(status, ok) {
    if (status >= 200 && status < 300) return ok ? { accion: 'ok' } : { accion: 'reintentar' };
    if (status === 429) return { accion: 'reintentar' };
    if (status === 403) return { accion: 'descartar' };
    if (status === 404 || status === 409) return { accion: 'descartar', refrescar: true };
    if (status === 413) return { accion: 'descartar', aviso: 'tope' };
    if (status >= 400 && status < 500) return { accion: 'descartar', aviso: 'rechazada' };
    return { accion: 'reintentar' };
  }

  // ── Respuestas ──
  function respuestaValida(p, v) {
    if (v === 'no_se') return p.clase !== 'foto';
    switch (p.clase) {
      case 'elegir': {
        const validos = new Set((p.opciones || []).map((o) => o.valor));
        if (p.multiple) return Array.isArray(v) && v.every((x) => typeof x === 'string' && validos.has(x));
        return typeof v === 'string' && validos.has(v);
      }
      case 'numero':
        return typeof v === 'number' && Number.isFinite(v) && v > 0 && v <= KILOS_MAXIMO;
      case 'confirmar': {
        if (!v || typeof v !== 'object' || Array.isArray(v)) return false;
        const tipos = new Set((p.items || []).map((i) => i.tipo));
        return Object.entries(v).every(([k, x]) => tipos.has(k) && (x === 'si' || x === 'no' || x === 'no_se'));
      }
      case 'foto':
        return v === 'subida' || v === 'no_puedo';
      default:
        return false;
    }
  }
  // vistas: las preguntas que el alumno tuvo en pantalla. Una de opción múltiple que vio y no marcó va como []
  // («lo que no marques cuenta como que no está», 2.3.1); «No sé» sigue yendo como duda.
  function respuestasParaEnviar(preguntas, borrador, vistas) {
    const r = {};
    const vio = new Set(Array.isArray(vistas) ? vistas : []);
    for (const p of preguntas || []) {
      const v = (borrador || {})[p.id];
      if (v !== undefined && v !== null && respuestaValida(p, v)) r[p.id] = v;
      else if (p.clase === 'elegir' && p.multiple && vio.has(p.id)) r[p.id] = [];
    }
    return r;
  }
  const fotosPedidas = (preguntas, borrador) =>
    (preguntas || []).filter((p) => p.clase === 'foto' && (borrador || {})[p.id] == null).length;

  function kilos(s) {
    const t = String(s == null ? '' : s).trim().replace(',', '.');
    if (!/^\d*\.?\d+$/.test(t)) return null;
    const n = Number(t);
    return Number.isFinite(n) && n > 0 && n <= KILOS_MAXIMO ? n : null;
  }

  function fechaCorta(iso, zona) {
    if (typeof iso !== 'string' || !iso) return null;
    const s = iso.replace(/\.\d+/, '').replace(' ', 'T').replace(/([+-]\d{2})$/, '$1:00');
    const d = new Date(s);
    if (isNaN(d)) return null;
    try {
      const op = { day: '2-digit', month: '2-digit' };
      if (zona) op.timeZone = zona;
      const p = new Intl.DateTimeFormat('en-GB', op).formatToParts(d);
      return `${p.find((x) => x.type === 'day').value}/${p.find((x) => x.type === 'month').value}`;
    } catch (_) { return null; }
  }

  // ── Lo que contesta el servidor: lo que falta es opcional y lo desconocido no rompe ──
  const texto = (v) => (typeof v === 'string' ? v : null);
  const lista = (v) => (Array.isArray(v) ? v : []);
  const CLASES = new Set(['elegir', 'numero', 'confirmar', 'foto']);

  function decodificarPregunta(j) {
    if (!j || typeof j !== 'object') return null;
    const id = texto(j.id);
    const t = texto(j.texto) || (j.clase === 'confirmar' ? T.confirmarTarjeta : null);
    if (!id || !t) return null;
    return {
      id, texto: t,
      clase: CLASES.has(j.clase) ? j.clase : 'desconocida',
      multiple: j.multiple === true,
      zona: texto(j.zona),
      unidad: texto(j.unidad),
      opciones: lista(j.opciones).filter((o) => o && texto(o.valor) != null && texto(o.texto) != null)
        .map((o) => ({ valor: o.valor, texto: o.texto })),
      items: lista(j.items).filter((o) => o && texto(o.tipo) != null && texto(o.texto) != null)
        .map((o) => ({ tipo: o.tipo, texto: o.texto, fotos: lista(o.fotos).filter((f) => typeof f === 'string') })),
      fotos: lista(j.fotos).filter((f) => typeof f === 'string'),
    };
  }

  function decodificarCarga(j) {
    if (!j || typeof j !== 'object' || !texto(j.id) || !texto(j.estado)) return null;
    return {
      id: j.id,
      estado: j.estado,
      modo: texto(j.modo) || 'completa',
      resultado: texto(j.resultado),
      publicadoEn: texto(j.publicado_en),
      // Las de clase desconocida no se muestran: esta versión no sabe contestarlas.
      preguntas: lista(j.preguntas).map(decodificarPregunta).filter((p) => p && p.clase !== 'desconocida'),
      fotos: lista(j.fotos).filter((f) => f && texto(f.id) && texto(f.zona))
        .map((f) => ({ id: f.id, zona: f.zona, ronda: Number.isInteger(f.ronda) ? f.ronda : 0 })),
      zonasNoHay: lista(j.zonas_no_hay).filter((z) => typeof z === 'string'),
      equipos: lista(j.equipos).filter((e) => e && texto(e.tipo)).map((e) => ({
        tipo: e.tipo,
        nombre: texto(e.nombre) || e.tipo.replace(/_/g, ' '),
        zona: texto(e.zona) || ZONA_OPCIONAL,
        cantidad: typeof e.cantidad === 'number' && e.cantidad >= 1 ? Math.floor(e.cantidad) : 1,
      })),
    };
  }

  /* null: no es una respuesta con habilitado:true. */
  function decodificarEstado(j) {
    if (!j || typeof j !== 'object' || j.habilitado !== true) return null;
    return {
      abierta: decodificarCarga(j.abierta),
      vigente: decodificarCarga(j.vigente),
    };
  }

  /* El canvas ya saca el EXIF al recodificar. Esto es la segunda llave, y lo que se puede probar sin navegador: copia el
     JPEG sin los segmentos APP1 a APP15 (EXIF con GPS, XMP, IPTC, perfiles) ni comentarios. Si no entiende el archivo
     devuelve null: esa foto no se sube. */
  function quitarMetadatos(entrada) {
    const b = entrada instanceof Uint8Array ? entrada : new Uint8Array(entrada);
    if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return null;
    const trozos = [[0, 2]];
    let i = 2;
    while (i + 1 < b.length) {
      if (b[i] !== 0xff) return null;
      const m = b[i + 1];
      if (m === 0xff) { i += 1; continue; }            // relleno entre segmentos
      if (m === 0xda) { trozos.push([i, b.length]); i = b.length; break; }   // de acá en más, la imagen
      if (m === 0xd9) { trozos.push([i, i + 2]); i = b.length; break; }
      if (i + 3 >= b.length) return null;
      const largo = (b[i + 2] << 8) | b[i + 3];
      if (largo < 2 || i + 2 + largo > b.length) return null;
      const metadato = (m >= 0xe1 && m <= 0xef) || m === 0xfe;
      if (!metadato) trozos.push([i, i + 2 + largo]);
      i += 2 + largo;
    }
    const total = trozos.reduce((s, [a, z]) => s + (z - a), 0);
    const out = new Uint8Array(total);
    let p = 0;
    for (const [a, z] of trozos) { out.set(b.subarray(a, z), p); p += z - a; }
    return out;
  }

  const API = {
    ZONAS, ZONA_OPCIONAL, TOPE_FOTOS, MAX_NOTA, MAX_PX, CALIDAD, MAX_BYTES, KILOS_MAXIMO, T,
    nombreZona, zonasFaltantes, puedeEnviar, restan, puedeAgregar, notaRecortada,
    pantalla, tarjetaVisible, entradaVisible, clasificarSubida,
    respuestaValida, respuestasParaEnviar, fotosPedidas, kilos, fechaCorta,
    decodificarPregunta, decodificarCarga, decodificarEstado, quitarMetadatos,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Gimnasio = API;
})(typeof window !== 'undefined' ? window : globalThis);
