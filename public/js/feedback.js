/* =============================================================
   feedback.js — «Feedback del alumno» (2.3.0): textos y reglas puras.

   Gemelo de Feedback.swift, FiguraCuerpo.swift y TextosFeedback.swift de la app.
   «Me duele» por ejercicio y «¿Ya lo tenés?» en Suplementación. Los valores son
   los del servidor (supabase/propuestas/nativa_feedback_alumno.sql). Lo que llega
   se decodifica campo por campo y lo desconocido se descarta. Los casos de
   scripts/vectores-app/feedback.json (copia de apps/shared/fixtures/feedback/casos.json)
   hacen fallar el test si esto difiere de las apps.
   ============================================================= */
(function (raiz) {
  'use strict';

  /* Los textos, los mismos de la app. Sin dos puntos, sin guiones y sin emojis. */
  const T = {
    dueleBoton: 'Me duele',
    dueleTitulo: 'Me duele',
    dueleIntro: 'Contame dónde y cómo, y te cambio el ejercicio.',
    dueleDonde: '¿Dónde te duele?',
    dueleDondeAyuda: 'Tocá la zona en el dibujo.',
    dueleFrente: 'Frente',
    dueleEspalda: 'Espalda',
    dueleLado: '¿De qué lado?',
    dueleLadoDerecho: 'Derecho',
    dueleLadoIzquierdo: 'Izquierdo',
    dueleLadoAmbos: 'Los dos',
    dueleDesde: '¿Desde cuándo?',
    dueleCuando: '¿En qué parte del movimiento?',
    dueleTipo: '¿Cómo es?',
    dueleCuanto: '¿Cuánto te duele?',
    dueleNota: 'Algo más que quieras contarme',
    dueleEnviar: 'Avisarle a Mati',
    dueleCorregir: 'Guardar cambios',
    dueleFalta: 'Completá lo que falta para avisarme.',
    dueleListoTitulo: 'Ya me llegó',
    dueleListo: 'Lo veo y te ajusto el ejercicio.',
    dueleListoFuerte: 'Por hoy dejá este ejercicio y seguí con el resto.',
    dueleAvisada: 'Molestia avisada',
    dueleResuelta: 'Ya lo revisé',
    dueleCambiar: 'Cambiar',
    dueleSinRed: 'No se pudo enviar. Revisá la conexión y probá de nuevo.',
    dueleTope: 'Hoy ya me avisaste varias veces. Si es urgente, escribime por el chat.',
    dueleError: 'No se pudo enviar. Probá de nuevo en un rato.',
    cerrar: 'Cerrar',
    listo: 'Listo',
    supleTitulo: '¿Ya lo tenés?',
    supleAyuda: 'Marcalo una sola vez. Si algo cambia, lo actualizás acá.',
    supleMarcar: 'Marcar',
    supleNoConsigoAviso: 'Te escribo con opciones que se consigan donde vivís.',
    supleError: 'No se pudo guardar. Probá de nuevo.',
  };

  const texto = (v) => (typeof v === 'string' ? v : null);
  const esObjeto = (v) => !!v && typeof v === 'object' && !Array.isArray(v);

  // ───────────────────────── «Me duele» ─────────────────────────
  const MAX_NOTA = 500;

  /* Zona → nombre, si es femenino y lo que va después del lado («Muslo derecho adelante»). */
  const ZONAS = [
    ['cuello', 'Cuello', false, ''], ['hombro', 'Hombro', false, ''], ['pecho', 'Pecho', false, ''], ['brazo', 'Brazo', false, ''],
    ['codo', 'Codo', false, ''], ['antebrazo', 'Antebrazo', false, ''], ['muneca', 'Muñeca o mano', true, ''],
    ['abdomen', 'Abdomen', false, ''], ['espalda_alta', 'Espalda alta', true, ''], ['espalda_baja', 'Espalda baja', true, ''],
    ['cadera', 'Cadera', true, ''], ['gluteo', 'Glúteo', false, ''], ['muslo_frente', 'Muslo', false, ' adelante'],
    ['muslo_atras', 'Muslo', false, ' atrás'], ['rodilla', 'Rodilla', true, ''], ['pantorrilla', 'Pantorrilla', true, ''],
    ['tobillo', 'Tobillo o pie', false, ''],
  ].map(([id, nombre, femenino, cola]) => ({ id, nombre, femenino, cola }));
  const LADOS = ['izquierdo', 'derecho', 'ambos', 'centro'];
  const op = (id, t) => ({ id, texto: t });
  const DESDE = [op('hoy', 'Hoy'), op('esta_semana', 'Esta semana'), op('semanas', 'Hace unas semanas'), op('mas_de_un_mes', 'Más de un mes')];
  const CUANDO = [op('al_bajar', 'Al bajar'), op('al_subir', 'Al subir'), op('todo_el_recorrido', 'En todo el recorrido'),
    op('despues', 'Después de entrenar'), op('al_dia_siguiente', 'Al día siguiente')];
  const TIPO = [op('punzante', 'Punzante'), op('sordo', 'Sordo, de fondo'), op('hormigueo', 'Hormigueo')];
  const LADOS_ELEGIBLES = [op('derecho', T.dueleLadoDerecho), op('izquierdo', T.dueleLadoIzquierdo), op('ambos', T.dueleLadoAmbos)];
  /* La escala simple: cuatro escalones que se guardan como 2, 5, 7 y 9 de 10. */
  const NIVELES = [op(2, 'Poco'), op(5, 'Bastante'), op(7, 'Mucho'), op(9, 'No puedo seguir')];

  /* El escalón de una intensidad guardada (0 a 10): hasta 3 poco, hasta 5 bastante, hasta 7 mucho. */
  function nivel(intensidad) {
    return intensidad <= 3 ? NIVELES[0] : intensidad <= 5 ? NIVELES[1] : intensidad <= 7 ? NIVELES[2] : NIVELES[3];
  }
  /* Desde «Mucho» se suma la línea de dejar el ejercicio por hoy. No es un diagnóstico: es no seguir cargando algo que duele. */
  const esFuerte = (intensidad) => intensidad >= 7;
  const zonaValida = (z) => ZONAS.some((x) => x.id === z);

  /* «Hombro derecho», «Muñeca o mano izquierda», «Muslo derecho adelante», «Rodilla, los dos lados», «Espalda baja». */
  function nombreZona(zona, lado) {
    const z = ZONAS.find((x) => x.id === zona);
    if (!z) return '';
    if (lado === 'izquierdo') return `${z.nombre} ${z.femenino ? 'izquierda' : 'izquierdo'}${z.cola}`;
    if (lado === 'derecho') return `${z.nombre} ${z.femenino ? 'derecha' : 'derecho'}${z.cola}`;
    if (lado === 'ambos') return `${z.nombre}${z.cola}, los dos lados`;
    return z.nombre + z.cola;
  }

  /* Por puntos de código, como cuenta el SQL. */
  const nota = (s) => Array.from(String(s == null ? '' : s)).slice(0, MAX_NOTA).join('');

  /* Lo que se manda. */
  const borradorVacio = () => ({ zona: null, lado: null, desde: null, cuando: null, tipo: null, intensidad: null, nota: '' });
  function borradorDe(m) {
    return { zona: m.zona, lado: m.lado, desde: m.desde, cuando: m.cuando, tipo: m.tipo,
      intensidad: m.intensidad == null ? null : nivel(m.intensidad).id, nota: m.nota || '' };
  }
  /* ¿Se puede avisar? */
  function completa(b) {
    return !!b && zonaValida(b.zona) && LADOS.includes(b.lado) && DESDE.some((x) => x.id === b.desde)
      && CUANDO.some((x) => x.id === b.cuando) && TIPO.some((x) => x.id === b.tipo)
      && Number.isInteger(b.intensidad) && b.intensidad >= 0 && b.intensidad <= 10;
  }
  const nombreZonaBorrador = (b) => (b && b.zona && b.lado ? nombreZona(b.zona, b.lado) : null);

  /* Tocar una pieza del dibujo: da la zona y el lado de una vez. Con «los dos» elegido, tocar el otro lado de la misma zona no lo deshace. */
  function tocarPieza(b, p) {
    if (!p || !p.zona || !p.lado) return b;
    if (b.zona === p.zona && b.lado === 'ambos' && p.lado !== 'centro') return b;
    return { ...b, zona: p.zona, lado: p.lado };
  }

  /* Una molestia como la devuelve mypump_feedback_get. null = no se entiende (estado o zona de un servidor más nuevo) y se descarta. */
  function decodificarMolestia(j) {
    if (!esObjeto(j)) return null;
    const id = texto(j.id), ej = texto(j.ejercicio_id), zona = texto(j.zona), estado = texto(j.estado);
    if (!id || !ej || !zonaValida(zona) || (estado !== 'avisada' && estado !== 'resuelta')) return null;
    const lado = texto(j.lado);
    const n = j.intensidad;
    const notaM = texto(j.nota);
    return {
      id, ejercicioId: ej, ejercicioNombre: texto(j.ejercicio_nombre) || '', zona, lado: LADOS.includes(lado) ? lado : 'centro',
      desde: texto(j.desde), cuando: texto(j.cuando), tipo: texto(j.tipo),
      intensidad: (typeof n === 'number' && isFinite(n) && n >= 0 && n <= 10) ? Math.trunc(n) : null,
      nota: notaM || null, estado, abierta: estado === 'avisada',
    };
  }

  /* El nombre que se avisa: con un sustituto, «Sustituto (en lugar de Original)». */
  function nombreParaAvisar(nombre, original) {
    const n = String(nombre == null ? '' : nombre);
    return (original && original !== n) ? `${n} (en lugar de ${original})` : n;
  }

  /* Los parámetros de mypump_molestia_registrar. `id` lo pone quien llama y lo repite en cada reintento: el servidor no duplica. */
  function parametrosMolestia(token, id, ejercicioId, ejercicioNombre, diaId, b, version) {
    if (!completa(b)) return null;
    const n = nota(String(b.nota || '').trim());
    const corta = (s, tope) => Array.from(String(s)).slice(0, tope).join('');
    return {
      p_token: token, p_id: id, p_ejercicio_id: corta(ejercicioId, 160), p_ejercicio_nombre: corta(ejercicioNombre, 160),
      p_dia_id: diaId ? corta(diaId, 80) : null, p_zona: b.zona, p_lado: b.lado, p_desde: b.desde, p_cuando: b.cuando, p_tipo: b.tipo,
      p_intensidad: b.intensidad, p_nota: n || null, p_plataforma: 'web', p_version: version ? corta(version, 40) : null,
    };
  }

  // ───────────────────────── La figura ─────────────────────────
  /* Dibujo propio de cápsulas, elipses y cajas en un lienzo de 200 × 420. Copia exacta de apps/shared/fixtures/feedback/cuerpo.json
     (sale de scripts/nativa/generar-cuerpo.py): no se edita a mano. cápsula: x1, y1, x2, y2, radio · elipse: cx, cy, rx, ry ·
     caja: x, y, ancho, alto, radio. zona null = la cabeza, que es solo dibujo. */
  const CUERPO = {
    "ancho": 200, "alto": 420,
    "vistas": {
    "frente": [
      {"zona": null, "lado": null, "forma": "elipse", "a": [100, 27, 17, 21]},
      {"zona": "cuello", "lado": "centro", "forma": "caja", "a": [90, 52, 20, 16, 7]},
      {"zona": "pecho", "lado": "centro", "forma": "caja", "a": [76, 70, 48, 40, 14]},
      {"zona": "abdomen", "lado": "centro", "forma": "caja", "a": [79, 112, 42, 50, 12]},
      {"zona": "hombro", "lado": "derecho", "forma": "elipse", "a": [64, 84, 15, 14]},
      {"zona": "hombro", "lado": "izquierdo", "forma": "elipse", "a": [136, 84, 15, 14]},
      {"zona": "cadera", "lado": "derecho", "forma": "elipse", "a": [86, 180, 14, 15]},
      {"zona": "cadera", "lado": "izquierdo", "forma": "elipse", "a": [114, 180, 14, 15]},
      {"zona": "muslo_frente", "lado": "derecho", "forma": "capsula", "a": [84, 208, 83, 262, 14.5]},
      {"zona": "muslo_frente", "lado": "izquierdo", "forma": "capsula", "a": [116, 208, 117, 262, 14.5]},
      {"zona": "brazo", "lado": "derecho", "forma": "capsula", "a": [57, 106, 52, 138, 10.5]},
      {"zona": "brazo", "lado": "izquierdo", "forma": "capsula", "a": [143, 106, 148, 138, 10.5]},
      {"zona": "codo", "lado": "derecho", "forma": "elipse", "a": [49, 156, 10, 10]},
      {"zona": "codo", "lado": "izquierdo", "forma": "elipse", "a": [151, 156, 10, 10]},
      {"zona": "antebrazo", "lado": "derecho", "forma": "capsula", "a": [46, 174, 41, 202, 8.5]},
      {"zona": "antebrazo", "lado": "izquierdo", "forma": "capsula", "a": [154, 174, 159, 202, 8.5]},
      {"zona": "muneca", "lado": "derecho", "forma": "elipse", "a": [38, 222, 9, 12]},
      {"zona": "muneca", "lado": "izquierdo", "forma": "elipse", "a": [162, 222, 9, 12]},
      {"zona": "rodilla", "lado": "derecho", "forma": "elipse", "a": [83, 290, 13, 13]},
      {"zona": "rodilla", "lado": "izquierdo", "forma": "elipse", "a": [117, 290, 13, 13]},
      {"zona": "pantorrilla", "lado": "derecho", "forma": "capsula", "a": [83, 314, 84, 358, 10.5]},
      {"zona": "pantorrilla", "lado": "izquierdo", "forma": "capsula", "a": [117, 314, 116, 358, 10.5]},
      {"zona": "tobillo", "lado": "derecho", "forma": "elipse", "a": [84, 388, 10, 13]},
      {"zona": "tobillo", "lado": "izquierdo", "forma": "elipse", "a": [116, 388, 10, 13]}
    ],
    "espalda": [
      {"zona": null, "lado": null, "forma": "elipse", "a": [100, 27, 17, 21]},
      {"zona": "cuello", "lado": "centro", "forma": "caja", "a": [90, 52, 20, 16, 7]},
      {"zona": "espalda_alta", "lado": "centro", "forma": "caja", "a": [76, 70, 48, 46, 14]},
      {"zona": "espalda_baja", "lado": "centro", "forma": "caja", "a": [79, 118, 42, 44, 12]},
      {"zona": "hombro", "lado": "izquierdo", "forma": "elipse", "a": [64, 84, 15, 14]},
      {"zona": "hombro", "lado": "derecho", "forma": "elipse", "a": [136, 84, 15, 14]},
      {"zona": "gluteo", "lado": "izquierdo", "forma": "elipse", "a": [86, 180, 14, 15]},
      {"zona": "gluteo", "lado": "derecho", "forma": "elipse", "a": [114, 180, 14, 15]},
      {"zona": "muslo_atras", "lado": "izquierdo", "forma": "capsula", "a": [84, 208, 83, 262, 14.5]},
      {"zona": "muslo_atras", "lado": "derecho", "forma": "capsula", "a": [116, 208, 117, 262, 14.5]},
      {"zona": "brazo", "lado": "izquierdo", "forma": "capsula", "a": [57, 106, 52, 138, 10.5]},
      {"zona": "brazo", "lado": "derecho", "forma": "capsula", "a": [143, 106, 148, 138, 10.5]},
      {"zona": "codo", "lado": "izquierdo", "forma": "elipse", "a": [49, 156, 10, 10]},
      {"zona": "codo", "lado": "derecho", "forma": "elipse", "a": [151, 156, 10, 10]},
      {"zona": "antebrazo", "lado": "izquierdo", "forma": "capsula", "a": [46, 174, 41, 202, 8.5]},
      {"zona": "antebrazo", "lado": "derecho", "forma": "capsula", "a": [154, 174, 159, 202, 8.5]},
      {"zona": "muneca", "lado": "izquierdo", "forma": "elipse", "a": [38, 222, 9, 12]},
      {"zona": "muneca", "lado": "derecho", "forma": "elipse", "a": [162, 222, 9, 12]},
      {"zona": "rodilla", "lado": "izquierdo", "forma": "elipse", "a": [83, 290, 13, 13]},
      {"zona": "rodilla", "lado": "derecho", "forma": "elipse", "a": [117, 290, 13, 13]},
      {"zona": "pantorrilla", "lado": "izquierdo", "forma": "capsula", "a": [83, 314, 84, 358, 10.5]},
      {"zona": "pantorrilla", "lado": "derecho", "forma": "capsula", "a": [117, 314, 116, 358, 10.5]},
      {"zona": "tobillo", "lado": "izquierdo", "forma": "elipse", "a": [84, 388, 10, 13]},
      {"zona": "tobillo", "lado": "derecho", "forma": "elipse", "a": [116, 388, 10, 13]}
    ]
    }
  };
  const VISTAS = ['frente', 'espalda'];
  const piezas = (vista) => CUERPO.vistas[vista === 'espalda' ? 'espalda' : 'frente'];
  const idPieza = (p) => `${p.zona || 'cabeza'}-${p.lado || ''}`;

  function centro(p) {
    const a = p.a;
    if (p.forma === 'capsula') return { x: (a[0] + a[2]) / 2, y: (a[1] + a[3]) / 2 };
    if (p.forma === 'elipse') return { x: a[0], y: a[1] };
    return { x: a[0] + a[2] / 2, y: a[1] + a[3] / 2 };
  }
  /* ¿El punto cae en la pieza? `margen` agranda el blanco: un codo de 20 puntos es chico para un dedo. */
  function contiene(p, x, y, margen) {
    const a = p.a, m = margen || 0;
    if (p.forma === 'elipse') {
      const dx = (x - a[0]) / (a[2] + m), dy = (y - a[1]) / (a[3] + m);
      return dx * dx + dy * dy <= 1;
    }
    if (p.forma === 'caja') return x >= a[0] - m && x <= a[0] + a[2] + m && y >= a[1] - m && y <= a[1] + a[3] + m;
    const vx = a[2] - a[0], vy = a[3] - a[1];
    const largo2 = vx * vx + vy * vy;
    const t = largo2 === 0 ? 0 : Math.max(0, Math.min(1, ((x - a[0]) * vx + (y - a[1]) * vy) / largo2));
    const px = a[0] + t * vx - x, py = a[1] + t * vy - y;
    const r = a[4] + m;
    return px * px + py * py <= r * r;
  }
  /* La pieza tocada. Primero sin margen (lo que el dedo tapa de verdad) y después con margen, la de centro más cercano. */
  function piezaEn(vista, x, y, margen) {
    const m = margen === undefined ? 7 : margen;
    const tocables = piezas(vista).filter((p) => p.zona);
    for (let i = tocables.length - 1; i >= 0; i--) if (contiene(tocables[i], x, y, 0)) return tocables[i];
    let mejor = null, d = Infinity;
    for (const p of tocables) {
      if (!contiene(p, x, y, m)) continue;
      const c = centro(p);
      const dd = (c.x - x) * (c.x - x) + (c.y - y) * (c.y - y);
      if (dd < d) { d = dd; mejor = p; }
    }
    return mejor;
  }
  /* La vista donde se ve una zona, para abrir el dibujo del lado correcto al corregir un aviso. */
  const vistaDe = (zona) => (CUERPO.vistas.frente.some((p) => p.zona === zona) ? 'frente' : 'espalda');
  const piezaElegida = (p, b) => !!p.zona && !!b && p.zona === b.zona && (b.lado === 'ambos' || p.lado === b.lado);

  // ───────────────────────── «¿Ya lo tenés?» ─────────────────────────
  /* accion = lo que elige el alumno · marcado = cómo queda. */
  const ESTADOS_SUPLE = [
    { id: 'comprado', accion: 'Lo compré', marcado: 'Comprado' },
    { id: 'tomando', accion: 'Lo estoy tomando', marcado: 'Lo estás tomando' },
    { id: 'no_lo_consigo', accion: 'No lo consigo', marcado: 'No lo conseguís' },
    { id: 'lo_deje', accion: 'Lo dejé', marcado: 'Lo dejaste' },
  ];
  const estadoSuple = (id) => ESTADOS_SUPLE.find((e) => e.id === id) || null;

  /* La clave de un ítem, la misma cuenta que mypump_suple_clave: minúsculas, sin tildes y con un solo espacio. */
  const TILDES = { á: 'a', à: 'a', ä: 'a', â: 'a', é: 'e', è: 'e', ë: 'e', ê: 'e', í: 'i', ì: 'i', ï: 'i', î: 'i',
    ó: 'o', ò: 'o', ö: 'o', ô: 'o', ú: 'u', ù: 'u', ü: 'u', û: 'u', ñ: 'n' };
  function clave(nombre) {
    const plano = Array.from(String(nombre == null ? '' : nombre).normalize('NFC').toLowerCase()).map((c) => TILDES[c] || c).join('');
    return plano.split(/\s+/).filter(Boolean).join(' ');
  }

  /* Tolerante como las apps y el servidor: true, 1 o el texto. Ante la duda, es un protector y no se marca. */
  function esProtector(v) {
    return v === true || v === 1 || (typeof v === 'string' && ['true', 't', '1', 'si', 'sí', 'yes'].includes(v.trim().toLowerCase()));
  }

  /* Lo que se puede marcar: cada suplemento una vez, en el orden del plan. Los protectores (fármacos) no van nunca; lo que
     «sale» tampoco, salvo que ya tenga una marca. `marcas` = { clave: estado }. */
  function filas(items, marcas) {
    const vistos = new Set();
    const salen = [];
    for (const it of (Array.isArray(items) ? items : [])) {
      if (!esObjeto(it) || esProtector(it.protector) || typeof it.nombre !== 'string') continue;
      const k = clave(it.nombre);
      if (!k || vistos.has(k)) continue;
      vistos.add(k);
      const marca = (marcas && estadoSuple(marcas[k])) ? marcas[k] : null;
      if (it.estado === 'sale' && !marca) continue;
      salen.push({ id: k, nombre: it.nombre.trim(), estado: marca });
    }
    return salen;
  }
  /* «2 de 5 marcados», para el encabezado. */
  const resumen = (fs) => `${fs.filter((f) => f.estado).length} de ${fs.length} marcados`;

  // ───────────────────────── El estado ─────────────────────────
  /* Lo que devuelve mypump_feedback_get. null = no es un objeto (no se muestra nada). */
  function decodificarEstado(j) {
    if (!esObjeto(j)) return null;
    const e = { dueleHabilitado: false, molestias: [], supleHabilitado: false, marcas: {} };
    const d = esObjeto(j.me_duele) ? j.me_duele : {};
    const s = esObjeto(j.suple_estado) ? j.suple_estado : {};
    if (typeof d.habilitado === 'boolean') e.dueleHabilitado = d.habilitado;
    if (Array.isArray(d.molestias)) e.molestias = d.molestias.map(decodificarMolestia).filter(Boolean);
    if (typeof s.habilitado === 'boolean') e.supleHabilitado = s.habilitado;
    if (Array.isArray(s.items)) {
      for (const x of s.items) {
        if (esObjeto(x) && texto(x.item) && estadoSuple(x.estado)) e.marcas[x.item] = x.estado;
      }
    }
    return e;
  }
  /* La molestia que se muestra en un ejercicio: la abierta, o la última cerrada. */
  function molestiaDe(estado, ejercicioId) {
    if (!estado) return null;
    const suyas = estado.molestias.filter((m) => m.ejercicioId === ejercicioId);
    return suyas.find((m) => m.abierta) || suyas[0] || null;
  }

  const API = {
    T, MAX_NOTA, ZONAS, LADOS, DESDE, CUANDO, TIPO, LADOS_ELEGIBLES, NIVELES, nivel, esFuerte, zonaValida, nombreZona, nota,
    borradorVacio, borradorDe, completa, nombreZonaBorrador, tocarPieza, decodificarMolestia, nombreParaAvisar, parametrosMolestia,
    CUERPO, VISTAS, piezas, idPieza, centro, contiene, piezaEn, vistaDe, piezaElegida,
    ESTADOS_SUPLE, estadoSuple, clave, filas, resumen, decodificarEstado, molestiaDe,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Feedback = API;
})(typeof window !== 'undefined' ? window : globalThis);
