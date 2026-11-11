/* =============================================================
   fotos-inicio.js — «Fotos de inicio»: reglas puras, textos y siluetas.

   Sin red, sin pantalla y sin almacenamiento. Gemelo de FotosInicio.swift,
   TextosFotosInicio.swift y SiluetasFotosInicio.swift. Vectores comunes con las
   apps: scripts/vectores-app/fotos_inicio.json (copia exacta de
   apps/shared/vectores/fotos_inicio.json), que corre scripts/test-fotos-inicio.mjs.
   Contrato: docs/NATIVA_CONTRATO.md, sección 13.

   Las fotos son privadas: ningún texto nombra a otra cosa que a Mati.
   ============================================================= */
(function (raiz) {
  'use strict';

  // Todo lo que lee el alumno, en un solo lugar (las mismas claves que TextosFotosInicio).
  const T = {
    // Entrada
    tarjetaTitulo: 'Tus fotos de inicio',
    tarjetaBajada: 'Tres fotos para que Mati vea de dónde arrancás',
    tarjetaEmpezar: 'Empezar',
    tarjetaSeguir: 'Seguir',
    tarjetaLista: 'Listas. Mati ya las tiene',
    entradaMisDatos: 'Mis fotos de inicio',
    privacidad: 'Las ve solo Mati. No se publican',
    // Consejos
    consejosTitulo: 'Antes de sacarlas',
    consejoLuz: 'De frente a una ventana o con la luz prendida. Sin contraluz',
    consejoDistancia: 'El teléfono a unos 2 metros: tenés que entrar de la cabeza a los pies',
    consejoAltura: 'La cámara derecha, a la altura del pecho',
    consejoRopa: 'En short o ropa interior, y con top deportivo si usás',
    consejoFondo: 'Una pared lisa atrás, sin cosas en el medio',
    consejoEspejo: 'Mejor sin espejo: apoyá el teléfono o pedile a alguien que te la saque',
    consejoTemporizador: 'Si estás solo, usá el temporizador de la cámara y después elegí la foto de la galería',
    consejoPostura: 'Relajado, sin sacar músculo ni meter la panza',
    // Poses
    poseFrente: 'De frente',
    posePerfil: 'De perfil',
    poseEspalda: 'De espalda',
    instruccionFrente: 'Parate derecho mirando a la cámara, con los brazos un poco separados del cuerpo y los pies al ancho de la cadera',
    instruccionPerfil: 'De costado a la cámara, mirando al frente y con los brazos al costado del cuerpo',
    instruccionEspalda: 'De espaldas a la cámara, en la misma postura que de frente',
    falta: 'Falta',
    lista: 'Lista',
    subiendo: 'Subiendo…',
    esperandoSenal: 'Esperando señal',
    // Sacar y revisar
    botonFoto: 'Sacar o elegir foto',
    botonUsar: 'Usar esta foto',
    botonUsarIgual: 'Usar igual',
    botonOtra: 'Sacar otra',
    seVeBien: 'Se ve bien',
    problemaChica: 'Tiene poca resolución. Sacala de nuevo con la cámara del teléfono',
    problemaApaisada: 'Salió acostada. Sacala con el teléfono en vertical',
    problemaOscura: 'Salió oscura. Buscá más luz, de frente a una ventana',
    problemaMovida: 'Salió movida. Apoyá el teléfono o usá el temporizador',
    problemaVieja: (dias) => `Es de hace ${dias} días. Mati necesita una de esta semana`,
    ilegible: 'No se pudo leer esa foto. Probá con otra',
    fotoRechazada: 'Una foto no se pudo usar. Sacala de nuevo',
    noSeGuardo: 'No se pudo guardar la foto en el teléfono. Probá de nuevo',
    sinSenal: 'Sin señal: queda guardada y se sube sola',
    // Resumen
    cuenta: (n) => `${n} de 3`,
    faltan: (n) => (n === 1 ? 'Te falta 1 foto' : `Te faltan ${n} fotos`),
    listoTitulo: 'Listo, Mati ya tiene tus fotos',
    listoBajada: 'Si querés repetir alguna, tocala',
    repetir: 'Repetir',
    // El físico que te motiva
    motivacionTitulo: 'El físico que te motiva',
    opcional: 'Opcional',
    motivacionBajada: 'Si hay un físico al que te gustaría acercarte, sumá una o más fotos y contale a Mati qué te gusta',
    motivacionAgregar: 'Agregar foto',
    motivacionNota: 'Qué te gusta de ese físico',
    motivacionGuardar: 'Guardar nota',
    motivacionGuardada: 'Nota guardada',
    motivacionTope: 'Hasta 4 fotos',
    borrarFoto: 'Borrar foto',
    notaSinSenal: 'Sin señal: la nota queda guardada y se manda sola',
    notaError: 'No se pudo guardar la nota. Probá de nuevo',
    borrarSinSenal: 'Sin señal: no se pudo borrar. Probá de nuevo',
    // Botones
    cerrar: 'Cerrar',
    siguiente: 'Siguiente',
    listoBoton: 'Listo',
    listoTeclado: 'Listo',
  };

  // Las tres del cuerpo, en el orden en que se piden.
  const POSES = [
    { clave: 'frente', nombre: T.poseFrente, instruccion: T.instruccionFrente },
    { clave: 'perfil', nombre: T.posePerfil, instruccion: T.instruccionPerfil },
    { clave: 'espalda', nombre: T.poseEspalda, instruccion: T.instruccionEspalda },
  ];
  const MOTIVACION = 'motivacion';
  const CONSEJOS = [
    T.consejoLuz, T.consejoDistancia, T.consejoAltura, T.consejoRopa,
    T.consejoFondo, T.consejoEspejo, T.consejoTemporizador, T.consejoPostura,
  ];

  // El JPEG que sube: lado mayor ≤ 1600 px a 0,85, sin metadatos.
  const MAX_PX = 1600;
  const CALIDAD = 0.85;
  // Con menos, la lectura del físico se descarta (el servidor tampoco la deja entrar).
  const MIN_LADO = 1080;
  const MIN_LADO_MOTIVACION = 320;
  const MAX_MOTIVACION = 4;
  const MAX_NOTA = 300;
  const BRILLO_MINIMO = 45;
  const NITIDEZ_MINIMA = 25;
  const DIAS_VIEJA = 7;
  // El control mira la foto achicada a bloques, con el lado mayor cerca de este tamaño.
  const LADO_ANALISIS = 640;
  // El servidor no recibe más de 4 MB.
  const MAX_BYTES = 4 * 1024 * 1024;

  const PROBLEMAS = ['chica', 'apaisada', 'oscura', 'movida', 'vieja'];

  const pose = (clave) => POSES.find((p) => p.clave === clave) || null;

  // ── Control de calidad ──

  /* La luz de un píxel, de 0 a 255 (con enteros, como las apps). */
  const luma = (r, g, b) => Math.trunc((r * 299 + g * 587 + b * 114) / 1000);

  /* La media de los `k` valores más altos de un histograma. */
  function mediaDeLosMayores(histograma, k) {
    let faltan = k, suma = 0;
    for (let v = histograma.length - 1; v >= 0; v--) {
      if (histograma[v] <= 0) continue;
      const tomo = Math.min(faltan, histograma[v]);
      suma += tomo * v;
      faltan -= tomo;
      if (faltan === 0) break;
    }
    return suma / k;
  }

  /* Mide la luz y la nitidez sobre la luma de la foto (una por píxel, por filas). `paso`: el lado del bloque que se promedia
     antes de medir; sin indicarlo, el que deja el lado mayor cerca de LADO_ANALISIS. Todo con enteros, como Swift y Kotlin,
     para que las tres plataformas den lo mismo. */
  function medir(lumas, ancho, alto, paso) {
    if (!(ancho > 0) || !(alto > 0) || !lumas || lumas.length < ancho * alto) return { brillo: 0, nitidez: 0 };
    const n = Math.max(1, paso == null ? Math.trunc(Math.max(ancho, alto) / LADO_ANALISIS) : paso);
    const w = Math.trunc(ancho / n), h = Math.trunc(alto / n);
    if (w <= 0 || h <= 0) return { brillo: 0, nitidez: 0 };
    const l = new Int32Array(w * h);
    let total = 0;
    const nn = n * n;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let suma = 0;
        for (let dy = 0; dy < n; dy++) {
          const fila = (y * n + dy) * ancho + x * n;
          for (let dx = 0; dx < n; dx++) suma += lumas[fila + dx];
        }
        const v = Math.trunc(suma / nn);
        l[y * w + x] = v;
        total += v;
      }
    }
    const brillo = total / (w * h);
    if (w < 3 || h < 3) return { brillo, nitidez: 0 };
    const horizontal = new Int32Array(511), vertical = new Int32Array(511);
    for (let y = 1; y < h - 1; y++) {
      for (let x = 1; x < w - 1; x++) {
        const c = 2 * l[y * w + x];
        horizontal[Math.abs(c - l[y * w + x - 1] - l[y * w + x + 1])] += 1;
        vertical[Math.abs(c - l[(y - 1) * w + x] - l[(y + 1) * w + x])] += 1;
      }
    }
    const k = Math.max(1, Math.trunc(((w - 2) * (h - 2)) / 100));
    return { brillo, nitidez: Math.min(mediaDeLosMayores(horizontal, k), mediaDeLosMayores(vertical, k)) };
  }

  /* La luma de los píxeles RGBA de un canvas (getImageData().data), una por píxel. */
  function lumaDeRGBA(datos, ancho, alto) {
    const total = ancho * alto;
    const out = new Uint8Array(total);
    for (let i = 0, j = 0; i < total; i++, j += 4) out[i] = luma(datos[j], datos[j + 1], datos[j + 2]);
    return out;
  }

  /* Qué tiene de malo la foto, en el orden en que se muestra. `dias`: cuántos días hace que se sacó, si se sabe.
     En «el físico que te motiva» solo importa que no sea diminuta. */
  function problemas(clave, ancho, alto, medida, dias) {
    const lado = Math.max(ancho, alto);
    if (clave === MOTIVACION) return lado < MIN_LADO_MOTIVACION ? ['chica'] : [];
    const lista = [];
    if (lado < MIN_LADO) lista.push('chica');
    if (ancho > alto) lista.push('apaisada');
    // Una foto oscura también mide poca nitidez: se avisa una sola cosa.
    if (medida.brillo < BRILLO_MINIMO) lista.push('oscura');
    else if (medida.nitidez < NITIDEZ_MINIMA) lista.push('movida');
    if (dias != null && dias > DIAS_VIEJA) lista.push('vieja');
    return lista;
  }

  /* Con poca resolución no se puede usar: el servidor tampoco la recibe. Lo demás se avisa y el alumno decide. */
  const bloquea = (lista) => lista.includes('chica');

  function texto(problema, dias) {
    switch (problema) {
      case 'chica': return T.problemaChica;
      case 'apaisada': return T.problemaApaisada;
      case 'oscura': return T.problemaOscura;
      case 'movida': return T.problemaMovida;
      case 'vieja': return T.problemaVieja(dias == null ? DIAS_VIEJA + 1 : dias);
      default: return '';
    }
  }

  const aMs = (f) => (f instanceof Date ? f.getTime() : typeof f === 'number' ? f : Date.parse(f));

  /* Días enteros entre que se sacó y ahora (nunca negativo). */
  function dias(desde, hasta) {
    const d = Math.trunc((aMs(hasta) - aMs(desde)) / 86400000);
    return Number.isFinite(d) ? Math.max(0, d) : 0;
  }

  // ── Cuándo se sacó ──
  const DESDE_RAZONABLE = Date.UTC(2000, 0, 1);

  /* `tomada_en`: la fecha de captura del EXIF de la original si la tiene; si no, la del archivo (si es razonable: ni del
     futuro ni anterior a 2000); si no, ahora. En milisegundos. */
  function tomadaEn(exifMs, lastModified, ahora) {
    const ok = (v) => typeof v === 'number' && Number.isFinite(v) && v >= DESDE_RAZONABLE && v <= ahora + 60000;
    if (ok(exifMs)) return Math.min(exifMs, ahora);
    if (ok(lastModified)) return Math.min(lastModified, ahora);
    return ahora;
  }

  /* ISO 8601 con zona (UTC, sin milésimas), como el encabezado x-inicio-tomada. */
  const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

  /* La fecha de captura (DateTimeOriginal, o DateTime si no está) del EXIF de un JPEG, en milisegundos; null si no hay o no
     se entiende. Basta con el principio del archivo. La hora del EXIF no tiene zona: es la del teléfono que la sacó. */
  function fechaExif(entrada) {
    const b = entrada instanceof Uint8Array ? entrada : new Uint8Array(entrada);
    if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return null;
    let i = 2;
    while (i + 4 <= b.length) {
      if (b[i] !== 0xff) return null;
      const m = b[i + 1];
      if (m === 0xff) { i += 1; continue; }
      if (m === 0xda || m === 0xd9) return null;
      const largo = (b[i + 2] << 8) | b[i + 3];
      if (largo < 2) return null;
      if (m === 0xe1 && i + 10 <= b.length && b[i + 4] === 0x45 && b[i + 5] === 0x78 && b[i + 6] === 0x69 && b[i + 7] === 0x66 && b[i + 8] === 0 && b[i + 9] === 0) {
        return fechaTiff(b.subarray(i + 10, Math.min(b.length, i + 2 + largo)));
      }
      i += 2 + largo;
    }
    return null;
  }
  function fechaTiff(t) {
    if (t.length < 8) return null;
    const le = t[0] === 0x49 && t[1] === 0x49;
    if (!le && !(t[0] === 0x4d && t[1] === 0x4d)) return null;
    const u16 = (p) => (p + 2 > t.length ? -1 : le ? t[p] | (t[p + 1] << 8) : (t[p] << 8) | t[p + 1]);
    const u32 = (p) => (p + 4 > t.length ? -1 : le ? (t[p] | (t[p + 1] << 8) | (t[p + 2] << 16)) + t[p + 3] * 16777216 : t[p] * 16777216 + ((t[p + 1] << 16) | (t[p + 2] << 8) | t[p + 3]));
    const etiquetas = (ifd) => {
      const n = u16(ifd);
      const r = {};
      if (n < 0 || n > 500) return r;
      for (let k = 0; k < n; k++) {
        const e = ifd + 2 + k * 12;
        if (e + 12 > t.length) break;
        r[u16(e)] = { tipo: u16(e + 2), cuenta: u32(e + 4), valor: u32(e + 8) };
      }
      return r;
    };
    const texto20 = (e) => {
      if (!e || e.tipo !== 2 || e.cuenta < 19 || e.valor < 0 || e.valor + 19 > t.length) return null;
      let s = '';
      for (let k = 0; k < 19; k++) s += String.fromCharCode(t[e.valor + k]);
      const m = /^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(s);
      if (!m) return null;
      const [a, me, d, h, mi, se] = m.slice(1).map(Number);
      if (a < 1990 || me < 1 || me > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || se > 59) return null;
      return new Date(a, me - 1, d, h, mi, se).getTime();
    };
    const ifd0 = etiquetas(u32(4));
    const exif = ifd0[0x8769] ? etiquetas(ifd0[0x8769].valor) : {};
    return texto20(exif[0x9003]) ?? texto20(exif[0x9004]) ?? texto20(ifd0[0x0132]) ?? null;
  }

  // ── El set ──
  const comoSet = (x) => (x instanceof Set ? x : new Set(x || []));

  /* Las poses del cuerpo que faltan, contando las que esperan subir. */
  function faltan(enServidor, enCola) {
    const s = comoSet(enServidor), c = comoSet(enCola);
    return POSES.map((p) => p.clave).filter((k) => !s.has(k) && !c.has(k));
  }

  /* A qué pose se pasa después de usar una foto: la primera que falte después de esa, y si no la primera que falte. */
  function siguiente(despuesDe, lista) {
    const orden = POSES.map((p) => p.clave);
    const i = orden.indexOf(despuesDe);
    if (i < 0) return lista.length ? lista[0] : null;
    const despues = orden.slice(i + 1).find((k) => lista.includes(k));
    if (despues) return despues;
    const otra = lista.find((k) => k !== despuesDe);
    return otra === undefined ? null : otra;
  }

  const puedeAgregarMotivacion = (enServidor, enCola, maximo = MAX_MOTIVACION) => enServidor + enCola < maximo;

  /* La nota como la guarda el servidor: los caracteres de control son espacios, sin espacios en las puntas y hasta 300
     (contados como el servidor, por punto de código). */
  function notaRecortada(s) {
    const puntos = [];
    for (const c of String(s == null ? '' : s)) {
      const u = c.codePointAt(0);
      puntos.push(u < 0x20 || (u >= 0x7f && u <= 0x9f) ? ' ' : c);
    }
    let a = 0, z = puntos.length;
    while (a < z && puntos[a] === ' ') a++;
    while (z > a && puntos[z - 1] === ' ') z--;
    return puntos.slice(a, Math.min(z, a + MAX_NOTA)).join('');
  }
  const largoNota = (s) => Array.from(String(s == null ? '' : s)).length;

  // ── Subida ──
  /* Qué hace la cola con la respuesta de /inicio/upload. Todo 4xx salvo 429 es definitivo; 5xx y 429, reintentar. */
  function clasificarSubida(status, ok) {
    if (status >= 200 && status < 300) return ok ? { accion: 'ok' } : { accion: 'reintentar' };
    if (status === 429) return { accion: 'reintentar' };
    if (status === 403) return { accion: 'descartar', refrescar: true };    // el link ya no sirve, o se cerró la sección
    if (status === 409) return { accion: 'descartar' };
    if (status === 413) return { accion: 'descartar', aviso: 'tope' };
    if (status >= 400 && status < 500) return { accion: 'descartar', aviso: 'rechazada' };
    return { accion: 'reintentar' };
  }

  // ── Lo que contesta el servidor ──
  const esObjeto = (x) => !!x && typeof x === 'object' && !Array.isArray(x);

  function decodificarFoto(j) {
    if (!esObjeto(j) || typeof j.id !== 'string' || typeof j.pose !== 'string') return null;
    return {
      id: j.id, pose: j.pose,
      tomadaEn: typeof j.tomada_en === 'string' ? j.tomada_en : null,
      ancho: typeof j.ancho === 'number' && Number.isFinite(j.ancho) ? Math.trunc(j.ancho) : 0,
      alto: typeof j.alto === 'number' && Number.isFinite(j.alto) ? Math.trunc(j.alto) : 0,
    };
  }

  /* mypump_fotos_inicio_get con habilitado:true; null si no lo es (token caído o apagado). Un campo que no se entiende no
     rompe nada: queda lo de fábrica. */
  function decodificarEstado(j) {
    if (!esObjeto(j) || j.habilitado !== true) return null;
    const m = j.max_motivacion;
    return {
      fotos: Array.isArray(j.fotos) ? j.fotos.map(decodificarFoto).filter(Boolean) : [],
      nota: typeof j.nota === 'string' ? j.nota : '',
      completo: j.completo === true,
      completadoEn: typeof j.completado_en === 'string' ? j.completado_en : null,
      maxMotivacion: typeof m === 'number' && Number.isFinite(m) && m >= 0 && m <= 20 ? Math.trunc(m) : MAX_MOTIVACION,
    };
  }
  /* Las poses del cuerpo que ya están en el servidor. */
  const posesDe = (e) => new Set((e ? e.fotos : []).map((f) => f.pose).filter((p) => p !== MOTIVACION));
  const deMotivacion = (e) => (e ? e.fotos : []).filter((f) => f.pose === MOTIVACION);

  /* El canvas ya saca el EXIF al recodificar. Esto es la segunda llave: copia el JPEG sin los segmentos APP1 a APP15 (EXIF
     con GPS, XMP, IPTC, perfiles) ni comentarios. Si no entiende el archivo devuelve null: esa foto no se sube. */
  function quitarMetadatos(entrada) {
    const b = entrada instanceof Uint8Array ? entrada : new Uint8Array(entrada);
    if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return null;
    const trozos = [[0, 2]];
    let i = 2;
    while (i + 1 < b.length) {
      if (b[i] !== 0xff) return null;
      const m = b[i + 1];
      if (m === 0xff) { i += 1; continue; }
      if (m === 0xda) { trozos.push([i, b.length]); i = b.length; break; }
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

  /* Cuánto achicar para que el lado mayor no pase de MAX_PX, sin agrandar nunca. */
  function medidaReducida(ancho, alto) {
    const esc = Math.min(1, MAX_PX / Math.max(ancho, alto));
    return { ancho: Math.max(1, Math.round(ancho * esc)), alto: Math.max(1, Math.round(alto * esc)) };
  }

  // ── Las siluetas: trazos SVG (solo M, C y Z, absolutos) sobre una caja de 120 × 260, las mismas de las apps ──
  const SILUETAS = {
    frente: {
      contorno: 'M60 7 C66.1 7 71 12.8 71 20 C71 27.2 66.1 33 60 33 C53.9 33 49 27.2 49 20 C49 12.8 53.9 7 60 7 Z M65 33 C66.8 34.3 64.2 39.0 66 41 C67.8 43.0 72.7 43.8 76 45 C79.3 46.2 83.5 46.2 86 48 C88.5 49.8 89.8 52.3 91 56 C92.2 59.7 92.5 65.0 93 70 C93.5 75.0 93.3 80.3 94 86 C94.7 91.7 96.2 98.3 97 104 C97.8 109.7 98.5 115.5 99 120 C99.5 124.5 100.3 128.3 100 131 C99.7 133.7 98.2 135.7 97 136 C95.8 136.3 93.8 135.7 93 133 C92.2 130.3 92.7 124.8 92 120 C91.3 115.2 90.0 109.3 89 104 C88.0 98.7 86.8 93.3 86 88 C85.2 82.7 84.7 75.7 84 72 C83.3 68.3 82.5 65.0 82 66 C81.5 67.0 81.7 73.7 81 78 C80.3 82.3 78.8 87.7 78 92 C77.2 96.3 76.0 100.0 76 104 C76.0 108.0 77.2 112.0 78 116 C78.8 120.0 80.3 123.0 81 128 C81.7 133.0 82.2 140.0 82 146 C81.8 152.0 80.8 158.7 80 164 C79.2 169.3 77.2 173.0 77 178 C76.8 183.0 79.0 188.0 79 194 C79.0 200.0 77.8 207.0 77 214 C76.2 221.0 74.0 230.8 74 236 C74.0 241.2 76.2 242.7 77 245 C77.8 247.3 79.8 248.8 79 250 C78.2 251.2 74.5 251.8 72 252 C69.5 252.2 65.2 253.0 64 251 C62.8 249.0 64.7 244.8 65 240 C65.3 235.2 66.0 228.7 66 222 C66.0 215.3 65.2 207.0 65 200 C64.8 193.0 65.3 186.7 65 180 C64.7 173.3 63.7 166.7 63 160 C62.3 153.3 61.5 144.8 61 140 C60.5 135.2 60.3 131.0 60 131 C59.7 131.0 59.5 135.2 59 140 C58.5 144.8 57.7 153.3 57 160 C56.3 166.7 55.3 173.3 55 180 C54.7 186.7 55.2 193.0 55 200 C54.8 207.0 54.0 215.3 54 222 C54.0 228.7 54.7 235.2 55 240 C55.3 244.8 57.2 249.0 56 251 C54.8 253.0 50.5 252.2 48 252 C45.5 251.8 41.8 251.2 41 250 C40.2 248.8 42.2 247.3 43 245 C43.8 242.7 46.0 241.2 46 236 C46.0 230.8 43.8 221.0 43 214 C42.2 207.0 41.0 200.0 41 194 C41.0 188.0 43.2 183.0 43 178 C42.8 173.0 40.8 169.3 40 164 C39.2 158.7 38.2 152.0 38 146 C37.8 140.0 38.3 133.0 39 128 C39.7 123.0 41.2 120.0 42 116 C42.8 112.0 44.0 108.0 44 104 C44.0 100.0 42.8 96.3 42 92 C41.2 87.7 39.7 82.3 39 78 C38.3 73.7 38.5 67.0 38 66 C37.5 65.0 36.7 68.3 36 72 C35.3 75.7 34.8 82.7 34 88 C33.2 93.3 32.0 98.7 31 104 C30.0 109.3 28.7 115.2 28 120 C27.3 124.8 27.8 130.3 27 133 C26.2 135.7 24.2 136.3 23 136 C21.8 135.7 20.3 133.7 20 131 C19.7 128.3 20.5 124.5 21 120 C21.5 115.5 22.2 109.7 23 104 C23.8 98.3 25.3 91.7 26 86 C26.7 80.3 26.5 75.0 27 70 C27.5 65.0 27.8 59.7 29 56 C30.2 52.3 31.5 49.8 34 48 C36.5 46.2 40.7 46.2 44 45 C47.3 43.8 52.2 43.0 54 41 C55.8 39.0 53.2 34.3 55 33 C56.8 31.7 63.2 31.7 65 33 Z',
      detalle: 'M46 64 C46.8 64.8 49.0 68.3 51 69 C53.0 69.7 56.8 68.2 58 68 M62 68 C63.2 68.2 67.0 69.7 69 69 C71.0 68.3 73.2 64.8 74 64 M60 74 C60.0 76.3 60.0 83.0 60 88 C60.0 93.0 60.0 101.3 60 104 M54 84 C55.0 84.2 58.0 85.0 60 85 C62.0 85.0 65.0 84.2 66 84 M54 94 C55.0 94.2 58.0 95.0 60 95 C62.0 95.0 65.0 94.2 66 94',
    },
    perfil: {
      contorno: 'M60 7 C62.7 6.3 66.0 7.5 68 9 C70.0 10.5 71.2 13.8 72 16 C72.8 18.2 72.2 20.2 73 22 C73.8 23.8 77.0 25.8 77 27 C77.0 28.2 73.7 27.8 73 29 C72.3 30.2 73.7 32.5 73 34 C72.3 35.5 70.2 36.8 69 38 C67.8 39.2 66.3 39.7 66 41 C65.7 42.3 65.8 43.8 67 46 C68.2 48.2 71.3 51.0 73 54 C74.7 57.0 76.5 60.3 77 64 C77.5 67.7 76.5 72.0 76 76 C75.5 80.0 74.3 84.0 74 88 C73.7 92.0 74.2 96.0 74 100 C73.8 104.0 73.3 108.0 73 112 C72.7 116.0 71.7 119.0 72 124 C72.3 129.0 74.7 136.0 75 142 C75.3 148.0 74.5 154.3 74 160 C73.5 165.7 72.3 170.3 72 176 C71.7 181.7 72.3 187.7 72 194 C71.7 200.3 70.5 207.3 70 214 C69.5 220.7 68.0 229.3 69 234 C70.0 238.7 73.5 239.8 76 242 C78.5 244.2 82.8 245.3 84 247 C85.2 248.7 85.3 251.2 83 252 C80.7 252.8 74.3 252.0 70 252 C65.7 252.0 59.3 253.3 57 252 C54.7 250.7 55.7 247.0 56 244 C56.3 241.0 58.8 239.0 59 234 C59.2 229.0 57.5 220.0 57 214 C56.5 208.0 55.7 203.0 56 198 C56.3 193.0 58.3 188.0 59 184 C59.7 180.0 60.5 178.7 60 174 C59.5 169.3 57.5 161.7 56 156 C54.5 150.3 52.2 144.7 51 140 C49.8 135.3 48.8 132.3 49 128 C49.2 123.7 50.8 118.3 52 114 C53.2 109.7 56.2 106.7 56 102 C55.8 97.3 52.3 91.3 51 86 C49.7 80.7 48.2 75.0 48 70 C47.8 65.0 48.8 60.0 50 56 C51.2 52.0 54.0 48.7 55 46 C56.0 43.3 56.5 42.0 56 40 C55.5 38.0 53.2 36.7 52 34 C50.8 31.3 49.0 27.5 49 24 C49.0 20.5 50.2 15.8 52 13 C53.8 10.2 57.3 7.7 60 7 Z M56 50 C57.5 48.3 60.3 48.7 62 50 C63.7 51.3 65.2 54.0 66 58 C66.8 62.0 66.8 68.7 67 74 C67.2 79.3 66.5 84.7 67 90 C67.5 95.3 69.3 100.7 70 106 C70.7 111.3 71.2 117.7 71 122 C70.8 126.3 70.2 130.0 69 132 C67.8 134.0 65.2 135.0 64 134 C62.8 133.0 62.7 130.3 62 126 C61.3 121.7 60.8 114.0 60 108 C59.2 102.0 58.0 95.7 57 90 C56.0 84.3 54.7 79.0 54 74 C53.3 69.0 52.7 64.0 53 60 C53.3 56.0 54.5 51.7 56 50 Z',
      detalle: '',
    },
    // La espalda tiene el mismo contorno que el frente; cambian las líneas de adentro.
    espalda: {
      detalle: 'M60 40 C60.0 45.0 60.0 58.0 60 70 C60.0 82.0 60.0 105.0 60 112 M45 58 C45.8 59.7 48.2 65.7 50 68 C51.8 70.3 55.0 71.3 56 72 M75 58 C74.2 59.7 71.8 65.7 70 68 C68.2 70.3 65.0 71.3 64 72 M46 126 C47.2 126.8 50.7 130.8 53 131 C55.3 131.2 58.8 127.7 60 127 M74 126 C72.8 126.8 69.3 130.8 67 131 C64.7 131.2 61.2 127.7 60 127',
    },
  };
  SILUETAS.espalda = { contorno: SILUETAS.frente.contorno, detalle: SILUETAS.espalda.detalle };
  const silueta = (clave) => (clave === 'frente' || clave === 'perfil' || clave === 'espalda' ? SILUETAS[clave] : null);

  const API = {
    T, POSES, MOTIVACION, CONSEJOS, PROBLEMAS, SILUETAS,
    MAX_PX, CALIDAD, MIN_LADO, MIN_LADO_MOTIVACION, MAX_MOTIVACION, MAX_NOTA, BRILLO_MINIMO, NITIDEZ_MINIMA, DIAS_VIEJA,
    LADO_ANALISIS, MAX_BYTES,
    pose, luma, medir, lumaDeRGBA, problemas, bloquea, texto, dias, tomadaEn, iso, fechaExif,
    faltan, siguiente, puedeAgregarMotivacion, notaRecortada, largoNota, clasificarSubida,
    decodificarEstado, posesDe, deMotivacion, quitarMetadatos, medidaReducida, silueta,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.FotosInicio = API;
})(typeof window !== 'undefined' ? window : globalThis);
