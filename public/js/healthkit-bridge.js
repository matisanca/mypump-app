/* =============================================================
   healthkit-bridge.js — Puente Apple Health → backend (Vía B)

   SOLO corre dentro del wrapper nativo iOS (Capacitor). En la web es no-op
   total: window.MyPumpHealth.isAvailable() === false y no se muestra nada.

   ── POR QUÉ SE REESCRIBIÓ (dos bugs que lo tuvieron muerto desde el día 1) ──

   BUG 1 — `window.TOKEN` era SIEMPRE undefined.
     cliente.html declara `const TOKEN = (...)()` en un <script> clásico, y
     `const` en top-level NO crea propiedad en window (a diferencia de `var` o
     de una declaración de función). El sync cortaba en la primera guarda y
     devolvía {ok:false, reason:'no-token'} sin escribir nunca nada.

   BUG 2 — `queryAggregated` RECHAZA en nativo casi todo lo que se le pedía.
     Verificado en el fuente del plugin (Health.swift:1447-1490): sleep,
     heartRateVariability, respiratoryRate y oxygenSaturation se rechazan
     explícitamente, y `exerciseTime` cae en el `default:` que también falla.
     Solo pasan steps/distance/calories (sum) y heartRate/weight/
     restingHeartRate (average|min|max). Los errores caían en un console.warn.

     O sea: aunque el token hubiera funcionado, HRV y sueño —los insumos del
     motor de recuperación— nunca iban a llegar.

   Por eso ahora hay DOS caminos: queryAggregated para los 3 tipos que el
   plugin realmente agrega, y readSamples + agregación en JS para el resto.
   ============================================================= */
(function () {
  'use strict';

  const Cap = window.Capacitor;
  const isNative = !!(Cap && typeof Cap.isNativePlatform === 'function' && Cap.isNativePlatform());
  const HEALTH = () => (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Health) || null;

  // ── Camino A: queryAggregated. SOLO estos 3 — es todo lo que el plugin
  //    agrega en iOS sin rechazar la llamada.
  const AGG = [
    { dataType: 'steps',            tipo: 'pasos',        agg: 'sum' },
    { dataType: 'calories',         tipo: 'kcal_activas', agg: 'sum' },
    { dataType: 'restingHeartRate', tipo: 'fc_reposo',    agg: 'average' },
  ];

  // ── Camino B: readSamples + agregación propia.
  //    'como' define cómo se colapsan las muestras de un día:
  //      sum      → volúmenes (minutos de ejercicio)
  //      mediana  → métricas puntuales; robusta ante un outlier suelto, que es
  //                 lo que pasa con el muestreo aleatorio de Apple
  const SAMPLES = [
    { dataType: 'exerciseTime',                  tipo: 'actividad_min',  como: 'sum' },
    { dataType: 'respiratoryRate',               tipo: 'respiracion_rpm', como: 'mediana' },
    { dataType: 'oxygenSaturation',              tipo: 'spo2_pct',        como: 'mediana', escala: 100 },
    { dataType: 'appleSleepingWristTemperature', tipo: 'temp_muneca_c',   como: 'mediana', minIOS: 16 },
    { dataType: 'bodyFat',                       tipo: 'grasa_pct',       como: 'mediana', escala: 100 },
    // ── Ampliación de cobertura ──
    // El peso ya lo aceptaba la DB y lo mostraba el panel, pero nadie lo leía
    // de acá: quien tiene balanza inteligente lo estaba tipeando a mano al
    // pedo. Va 'ultimo' y no mediana — el peso del día es la última pesada.
    { dataType: 'weight',          tipo: 'peso_kg',         como: 'ultimo' },
    { dataType: 'distance',        tipo: 'distancia_km',    como: 'sum', escala: 0.001 }, // m → km
    { dataType: 'flightsClimbed',  tipo: 'pisos',           como: 'sum' },
    // Basales + totales = TDEE medido. Hoy sale de Mifflin-St Jeor, que tiene
    // ±10% de error individual; esto es el gasto de ESTA persona.
    { dataType: 'basalCalories',   tipo: 'kcal_basales',    como: 'sum' },
    { dataType: 'totalCalories',   tipo: 'kcal_totales',    como: 'sum' },
    { dataType: 'vo2Max',          tipo: 'vo2max',          como: 'mediana' },
    { dataType: 'bodyTemperature', tipo: 'temp_corporal_c', como: 'mediana' },
    { dataType: 'bloodGlucose',    tipo: 'glucosa_mg_dl',   como: 'mediana' },
    { dataType: 'mindfulness',     tipo: 'mindful_min',     como: 'sum' },
    { dataType: 'heartRate',       tipo: 'fc_media',        como: 'mediana' },
  ];

  // Versión de iOS. Existe por un motivo puntual: pedir un tipo que el sistema
  // del cliente no conoce hace que el plugin tire error ANTES de mostrar la
  // hoja de permisos, así que un solo tipo iOS16+ dejaba a todo iOS 15 sin
  // poder conectar nunca — sin hoja, sin error visible, sin explicación.
  function iosMajor() {
    const m = /OS (\d+)[_.]/.exec(navigator.userAgent || '');
    return m ? parseInt(m[1], 10) : 0;
  }
  const soportado = (m) => !m.minIOS || iosMajor() === 0 || iosMajor() >= m.minIOS;

  const ymd = (d) => {
    const x = (d instanceof Date) ? d : new Date(d);
    return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
  };
  const mediana = (xs) => {
    if (!xs.length) return null;
    const s = xs.slice().sort((a, b) => a - b), m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
  };

  // El token: window.TOKEN si cliente.html lo expuso, y si no localStorage,
  // que el IIFE de cliente.html deja escrito sí o sí en cuanto hay token
  // válido. Dos patas porque son dos archivos distintos y el SW cachea el
  // bridge: no quiero que este modo de falla vuelva por desincronización.
  function getToken() {
    if (window.TOKEN) return window.TOKEN;
    try { return localStorage.getItem('mypump_token') || ''; } catch (e) { return ''; }
  }

  async function hkAvailable() {
    if (!isNative) return false;
    const h = HEALTH();
    if (!h) return false;
    try { const r = await h.isAvailable(); return !!(r && r.available); }
    catch { return false; }
  }

  // Núcleo: lo que sostiene el score de recuperación. Si esto no entra, la
  // función no tiene sentido, así que va en la primera tanda y solo.
  const NUCLEO = ['steps', 'calories', 'restingHeartRate', 'sleep', 'heartRateVariability', 'weight'];

  function tiposLectura() {
    return AGG.map(m => m.dataType)
      .concat(SAMPLES.filter(soportado).map(m => m.dataType))
      .concat(['sleep', 'heartRateVariability']);
  }

  /* PEDIDO POR TANDAS — no es paranoia, arregla un bug que dejaba iOS 15 muerto.
   *
   * El plugin valida los tipos ANTES de abrir la hoja de Apple: si uno solo no
   * existe en esa versión de iOS, tira y no se muestra NADA. Con
   * appleSleepingWristTemperature (iOS 16+) en la lista, todo iPhone en iOS 15
   * tocaba "Conectar", no pasaba nada, y no había forma de saber por qué.
   *
   * Ahora: primero el núcleo (existe desde iOS 8) para que la hoja aparezca sí
   * o sí; después el resto en una tanda aparte que puede fallar sin arrastrar
   * a la primera. Peor caso: el cliente conecta igual y pierde los tipos
   * exóticos, en vez de perder todo.
   */
  async function requestPermission() {
    const h = HEALTH();
    if (!h) return { ok: false, motivo: 'sin_plugin' };

    let alguna = false;
    try {
      await h.requestAuthorization({ read: NUCLEO, write: [] });
      alguna = true;
    } catch (e) {
      console.warn('[health] falló la tanda núcleo:', e);
      // Reintento pelado: si hasta el núcleo falla, probamos con lo mínimo
      // indispensable antes de darnos por vencidos.
      try { await h.requestAuthorization({ read: ['steps', 'sleep'], write: [] }); alguna = true; }
      catch (e2) { return { ok: false, motivo: 'error_nativo', detalle: String(e2 && e2.message || e2) }; }
    }

    const resto = tiposLectura().filter(t => NUCLEO.indexOf(t) === -1);
    if (resto.length) {
      try { await h.requestAuthorization({ read: resto, write: [] }); }
      catch (e) { console.warn('[health] tanda secundaria falló (sigue igual):', e); }
    }

    // requestAuthorization resuelve OK aunque el cliente destilde todo: en
    // HealthKit "success" significa "se mostró la hoja", no "me dieron
    // permiso". Acá no hay veredicto posible — ver estadoPermisos().
    const est = await estadoPermisos();
    return { ok: alguna, preguntados: est.preguntados, total: est.total, errEstado: est.error };
  }

  /* Lo único que HealthKit deja saber, que es MENOS de lo que parece.
   *
   * checkAuthorization corre por debajo getRequestStatusForAuthorization, que
   * devuelve `.unnecessary` cuando YA SE PREGUNTÓ — le haya dicho el cliente
   * que sí o que no. Apple NUNCA revela si hay permiso de LECTURA, y es a
   * propósito: si lo revelara, la app podría deducir que el cliente le esconde
   * algo, y esconder datos dejaría de servir de defensa.
   *
   * O sea que de acá sale "ya preguntamos" vs "falta preguntar", nada más. El
   * campo se llamaba `autorizados` y eso era una mentira que además se le
   * mostraba al cliente en pantalla ("12 de 20 permisos dados"): eran los que
   * ya se habían preguntado.
   *
   * Saber si hay permiso real tiene una sola vía: leer y ver si viene algo. De
   * eso se encarga registrarCosecha(). */
  async function estadoPermisos() {
    const h = HEALTH();
    const tipos = tiposLectura();
    const vacio = { conocido: false, preguntados: null, total: tipos.length, pendientes: [], error: null };
    if (!h || typeof h.checkAuthorization !== 'function') return vacio;
    try {
      const r = await h.checkAuthorization({ read: tipos, write: [] });
      // Se toleran las dos formas de respuesta: no quiero que un cambio de
      // shape del plugin vuelva a dejar esto mintiendo en silencio.
      const ya     = (r && (r.readAuthorized || r.authorized)) || null;
      const faltan = (r && (r.readDenied || r.denied)) || [];
      if (!Array.isArray(ya)) return vacio;
      return {
        conocido: true,
        preguntados: ya.length,
        total: tipos.length,
        pendientes: Array.isArray(faltan) ? faltan.slice() : [],
        error: null,
      };
    } catch (e) {
      // El error textual importa: es lo que dice si falló por un tipo que esta
      // versión de iOS no conoce o por otra cosa.
      return Object.assign({}, vacio, { error: String((e && e.message) || e) });
    }
  }

  /* Sospecha de "no tenemos permiso", deducida de los datos.
   *
   * Es la única detección posible (ver estadoPermisos). La señal: pedimos, y no
   * viene NADA de ningún tipo, varias veces seguidas. Un iPhone real siempre
   * tiene pasos — los cuenta el coprocesador de movimiento, sin reloj ni nada.
   * Así que cero muestras de todo, tres veces, es permiso denegado y no un día
   * tranquilo.
   *
   * Se cuenta lo que entregó HealthKit, NO lo que aceptó el servidor: si falla
   * la subida es un problema de red, y hacerlo pasar por falta de permiso
   * mandaría al cliente a Ajustes a tocar algo que ya estaba bien. */
  const K_RACHA = 'mypump_health_racha_vacia';
  const RACHA_PARA_SOSPECHAR = 3;
  function registrarCosecha(nRecolectados) {
    try {
      if (nRecolectados > 0) {
        localStorage.setItem(K_RACHA, '0');
        localStorage.removeItem(K_DENEG);
        return;
      }
      const r = (parseInt(localStorage.getItem(K_RACHA), 10) || 0) + 1;
      localStorage.setItem(K_RACHA, String(r));
      if (r >= RACHA_PARA_SOSPECHAR) localStorage.setItem(K_DENEG, '1');
    } catch (e) {}
  }

  // ── readSamples con detección de truncamiento ──────────────────────────
  // readSamples NO tiene paginación por anchor (solo queryWorkouts la tiene),
  // así que `limit` es el único freno. Si vuelven exactamente `limit`
  // muestras, es casi seguro que quedaron más afuera: se parte la ventana al
  // medio y se reintenta. Sin esto el backfill queda incompleto EN SILENCIO y
  // el baseline sale mal, que es peor que no tener baseline.
  const LIMITE = 5000;
  async function leerMuestras(dataType, desde, hasta, prof) {
    const h = HEALTH();
    if (!h || typeof h.readSamples !== 'function') return [];
    let res;
    try {
      res = await h.readSamples({
        dataType, startDate: desde.toISOString(), endDate: hasta.toISOString(),
        limit: LIMITE, ascending: true,
      });
    } catch (e) {
      if (window.__MYPUMP_DIAG) window.__MYPUMP_DIAG.push({ dataType, error: String(e && e.message || e) });
      return [];
    }
    const arr = (res && (res.samples || res.data)) || [];
    if (arr.length >= LIMITE && (prof || 0) < 4 && (hasta - desde) > 36e5) {
      const medio = new Date((desde.getTime() + hasta.getTime()) / 2);
      const a = await leerMuestras(dataType, desde, medio, (prof || 0) + 1);
      const b = await leerMuestras(dataType, medio, hasta, (prof || 0) + 1);
      return a.concat(b);
    }
    return arr;
  }

  // ── Sueño: de muestras crudas a UNA fila por noche ─────────────────────
  // Tres problemas reales que resuelve esta función:
  //  1. iPhone y Watch escriben AMBOS: sumar todo duplica las horas. Se elige
  //     la fuente que más minutos de sueño real aportó esa noche y se descarta
  //     el resto.
  //  2. 'inBed' SOLAPA con las etapas de sueño. Si hay etapas, inBed se ignora
  //     por completo; si es lo único que hay (usuario sin reloj), se estima
  //     al 90% y se marca detalle.estimado para que el motor le baje el peso.
  //  3. Muestras superpuestas de la misma fuente: se fusionan los intervalos
  //     antes de sumar.
  const ETAPAS = { light: 'sueno_ligero_min', deep: 'sueno_profundo_min', rem: 'sueno_rem_min' };
  function procesarSueno(muestras) {
    const evs = muestras.map(s => ({
      ini: new Date(s.startDate).getTime(),
      fin: new Date(s.endDate).getTime(),
      st: String(s.sleepState || s.value || '').toLowerCase(),
      src: s.sourceId || s.sourceName || '?',
    })).filter(e => e.fin > e.ini).sort((a, b) => a.ini - b.ini);
    if (!evs.length) return [];

    // Agrupar en noches: corte cuando hay más de 60 min sin nada.
    const noches = []; let cur = [evs[0]];
    for (let i = 1; i < evs.length; i++) {
      if (evs[i].ini - cur[cur.length - 1].fin > 60 * 60000) { noches.push(cur); cur = [evs[i]]; }
      else cur.push(evs[i]);
    }
    noches.push(cur);

    const fusionar = (ivs) => {
      const s = ivs.slice().sort((a, b) => a.ini - b.ini), out = [];
      for (const iv of s) {
        const u = out[out.length - 1];
        if (u && iv.ini <= u.fin) u.fin = Math.max(u.fin, iv.fin);
        else out.push({ ini: iv.ini, fin: iv.fin });
      }
      return out;
    };
    const mins = (ivs) => fusionar(ivs).reduce((t, i) => t + (i.fin - i.ini), 0) / 60000;

    const filas = [];
    for (const noche of noches) {
      // Fuente ganadora = la que más minutos de sueño REAL aportó.
      const porSrc = {};
      noche.forEach(e => { (porSrc[e.src] = porSrc[e.src] || []).push(e); });
      let mejor = null, mejorMin = -1;
      for (const src of Object.keys(porSrc)) {
        const dormido = porSrc[src].filter(e => e.st && e.st !== 'inbed' && e.st !== 'awake');
        const m = dormido.length ? mins(dormido) : 0;
        if (m > mejorMin) { mejorMin = m; mejor = src; }
      }
      const evsN = porSrc[mejor] || [];
      const dormido = evsN.filter(e => e.st && e.st !== 'inbed' && e.st !== 'awake');
      const enCama  = evsN.filter(e => e.st === 'inbed');

      let total, estimado = false;
      if (dormido.length) { total = mins(dormido); }
      else if (enCama.length) { total = mins(enCama) * 0.90; estimado = true; }
      else continue;
      if (!(total > 0)) continue;

      // La noche se imputa al día del DESPERTAR — es la convención que ya
      // asume la card ("dormiste anoche" se lee a la mañana).
      const fin = Math.max(...evsN.map(e => e.fin));
      const ini = Math.min(...evsN.map(e => e.ini));
      const fecha = ymd(new Date(fin));

      filas.push({ fecha, tipo: 'sueno_min', valor: Math.round(total),
                   detalle: estimado ? { estimado: true, fuente_id: mejor } : { fuente_id: mejor } });

      // Punto medio del sueño, en minutos desde medianoche: insumo de la
      // REGULARIDAD (su desvío en 7 días dice si los horarios son estables).
      const medio = new Date((ini + fin) / 2);
      filas.push({ fecha, tipo: 'sueno_medio_min',
                   valor: Math.round(medio.getHours() * 60 + medio.getMinutes()) });

      if (enCama.length && dormido.length) {
        const cama = mins(enCama);
        if (cama > 0) filas.push({ fecha, tipo: 'sueno_eficiencia_pct',
                                   valor: Math.round(Math.min(100, total / cama * 100)) });
      }
      for (const st of Object.keys(ETAPAS)) {
        const e = evsN.filter(x => x.st === st);
        if (e.length) filas.push({ fecha, tipo: ETAPAS[st], valor: Math.round(mins(e)) });
      }
      // Guardado aparte: el intervalo de la noche sirve para filtrar la HRV.
      filas._noches = filas._noches || [];
      filas._noches.push({ fecha, ini, fin });
    }
    return filas;
  }

  // ── HRV: mediana de la ventana NOCTURNA ───────────────────────────────
  // El Apple Watch escribe SDNN en momentos aleatorios del día (después de un
  // café, en el trabajo, etc.) y esas lecturas no son comparables entre sí. Se
  // filtra a las que caen dentro del sueño de esa noche; si no se conoce el
  // sueño, a la franja 00:00-10:00. `detalle.metrica` y `detalle.ventana` son
  // lo que después le permite al motor pesar este dato menos que un rMSSD.
  function procesarHRV(muestras, noches) {
    const porFecha = {};
    for (const s of muestras) {
      const t = new Date(s.startDate).getTime();
      const v = Number(s.value);
      if (!(v > 0)) continue;
      let fecha = null, ventana = 'dia';
      const n = (noches || []).find(x => t >= x.ini && t <= x.fin);
      if (n) { fecha = n.fecha; ventana = 'nocturna'; }
      else {
        const d = new Date(t);
        if (d.getHours() < 10) { fecha = ymd(d); ventana = 'madrugada'; }
        else fecha = ymd(d);
      }
      const k = fecha + '|' + ventana;
      (porFecha[k] = porFecha[k] || []).push(v);
    }
    // Si una fecha tiene lecturas nocturnas, se descartan las diurnas.
    const mejor = {};
    for (const k of Object.keys(porFecha)) {
      const [fecha, ventana] = k.split('|');
      const rank = ventana === 'nocturna' ? 0 : ventana === 'madrugada' ? 1 : 2;
      if (!mejor[fecha] || rank < mejor[fecha].rank) {
        mejor[fecha] = { rank, ventana, vals: porFecha[k] };
      }
    }
    return Object.keys(mejor).map(fecha => {
      const m = mejor[fecha];
      return { fecha, tipo: 'hrv_ms', valor: Math.round(mediana(m.vals)),
               detalle: { metrica: 'sdnn', ventana: m.ventana, n: m.vals.length } };
    });
  }

  // ── Recolección de un rango ───────────────────────────────────────────
  async function recolectar(desde, hasta) {
    const h = HEALTH();
    if (!h) return [];
    const registros = [];

    for (const { dataType, tipo, agg } of AGG) {
      try {
        const res = await h.queryAggregated({
          dataType, startDate: desde.toISOString(), endDate: hasta.toISOString(),
          bucket: 'day', aggregation: agg,
        });
        for (const s of (res && res.samples) || []) {
          const val = Number(s.value);
          if (!(val > 0)) continue;
          registros.push({ fecha: ymd(s.startDate), tipo, valor: Math.round(val), fuente: 'apple_health' });
        }
      } catch (e) {
        if (window.__MYPUMP_DIAG) window.__MYPUMP_DIAG.push({ dataType, error: String(e && e.message || e) });
        console.warn('[health] agg err', dataType, e);
      }
    }

    // .filter(soportado): saltea los tipos que esta versión de iOS no conoce.
    // Sin esto se pierde tiempo en llamadas que el nativo va a rechazar igual.
    for (const { dataType, tipo, como, escala, factor } of SAMPLES.filter(soportado)) {
      const ms = await leerMuestras(dataType, desde, hasta);
      const porFecha = {};
      for (const s of ms) {
        let v = Number(s.value);
        if (!isFinite(v)) continue;
        if (escala && v <= 1) v = v * escala;   // SpO2/grasa a veces vienen 0-1
        if (factor) v = v * factor;             // conversión fija de unidad (m → km)
        // Se guarda con su hora: 'ultimo' necesita saber cuál vino después.
        (porFecha[ymd(s.startDate)] = porFecha[ymd(s.startDate)] || []).push({ v, t: +new Date(s.startDate) });
      }
      for (const fecha of Object.keys(porFecha)) {
        const xs = porFecha[fecha];
        let val;
        if (como === 'sum') {
          val = xs.reduce((a, b) => a + b.v, 0);
        } else if (como === 'ultimo') {
          // Peso: el del día es la última pesada, no el promedio. Si se pesó
          // antes y después de entrenar, vale la de después.
          val = xs.slice().sort((a, b) => a.t - b.t).pop().v;
        } else {
          val = mediana(xs.map(x => x.v));
        }
        if (!(val > 0)) continue;
        // Peso y distancia necesitan 1 decimal; el resto redondea igual.
        registros.push({ fecha, tipo, valor: Math.round(val * 10) / 10, fuente: 'apple_health' });
      }
    }

    const msSueno = await leerMuestras('sleep', desde, hasta);
    const filasSueno = procesarSueno(msSueno);
    const noches = filasSueno._noches || [];
    filasSueno.forEach(f => registros.push(Object.assign({ fuente: 'apple_health' }, f)));

    const msHrv = await leerMuestras('heartRateVariability', desde, hasta);
    procesarHRV(msHrv, noches).forEach(f => registros.push(Object.assign({ fuente: 'apple_health' }, f)));

    return registros;
  }

  async function postear(registros) {
    const token = getToken();
    if (!token || !window.mypumpDB || !window.mypumpDB.ingestSalud) return 0;
    let ok = 0;
    for (let i = 0; i < registros.length; i += 300) {   // lotes: evita payloads gigantes
      const r = await window.mypumpDB.ingestSalud(token, registros.slice(i, i + 300));
      if (r && r.success) ok += Number(r.data) || 0;
    }
    return ok;
  }

  /* ── Entrenamientos ────────────────────────────────────────────────────
   * queryWorkouts existía en el plugin desde el día uno y no se llamaba nunca.
   * Es lo que hace visible el cardio, el fútbol de los jueves, la bici: todo
   * lo que el cliente entrena FUERA de la app y que hoy se le calculaba como
   * si no existiera. Va a su propia tabla porque son eventos (varios por día,
   * con tipo y duración), no una serie diaria. */
  async function recolectarEntrenos(desde, hasta) {
    const h = HEALTH();
    if (!h || typeof h.queryWorkouts !== 'function') return [];
    let ws = [];
    try {
      const r = await h.queryWorkouts({ startDate: desde.toISOString(), endDate: hasta.toISOString() });
      ws = (r && (r.workouts || r.samples)) || [];
    } catch (e) {
      console.warn('[health] queryWorkouts:', e);
      return [];
    }
    const out = [];
    for (const w of ws) {
      const ini = w.startDate || w.start;
      if (!ini) continue;
      const fin = w.endDate || w.end || null;
      const dur = (w.duration != null)
        ? Number(w.duration) / 60                      // el plugin da segundos
        : (fin ? (new Date(fin) - new Date(ini)) / 60000 : null);
      const km = (w.totalDistance != null) ? Number(w.totalDistance) / 1000 : null;
      out.push({
        inicio: new Date(ini).toISOString(),
        fin: fin ? new Date(fin).toISOString() : null,
        tipo: String(w.workoutType || w.type || 'other'),
        duracion_min: (dur != null && isFinite(dur)) ? Math.round(dur * 10) / 10 : null,
        kcal: (w.totalEnergyBurned != null && isFinite(+w.totalEnergyBurned)) ? Math.round(+w.totalEnergyBurned) : null,
        distancia_km: (km != null && isFinite(km) && km > 0) ? Math.round(km * 100) / 100 : null,
        fc_media: (w.averageHeartRate != null) ? Math.round(+w.averageHeartRate) : null,
        fc_max: (w.maxHeartRate != null) ? Math.round(+w.maxHeartRate) : null,
        fuente: 'apple_health',
      });
    }
    return out;
  }

  async function postearEntrenos(entrenos) {
    const token = getToken();
    if (!token || !entrenos.length) return 0;
    if (!window.mypumpDB || !window.mypumpDB.ingestEntrenos) return 0;
    let ok = 0;
    for (let i = 0; i < entrenos.length; i += 200) {
      const r = await window.mypumpDB.ingestEntrenos(token, entrenos.slice(i, i + 200));
      if (r && r.success) ok += Number(r.data) || 0;
    }
    return ok;
  }

  // ── Sync incremental (últimos 7 días) ─────────────────────────────────
  async function sync() {
    if (!isNative) return { ok: false, reason: 'no-native' };
    if (!getToken()) return { ok: false, reason: 'no-token' };
    const hasta = new Date(), desde = new Date();
    desde.setDate(desde.getDate() - 7);
    const registros = await recolectar(desde, hasta);
    registrarCosecha(registros.length);
    const n = registros.length ? await postear(registros) : 0;
    // Los entrenos van por su propia vía: si esa falla, las métricas diarias
    // ya quedaron guardadas igual.
    let nEnt = 0;
    try { nEnt = await postearEntrenos(await recolectarEntrenos(desde, hasta)); }
    catch (e) { console.warn('[health] entrenos:', e); }
    marcarSync();
    if (typeof window.loadSalud === 'function') window.loadSalud();
    if (typeof window.loadRecuperacion === 'function') window.loadRecuperacion();
    return { ok: true, ingresados: n, entrenos: nEnt };
  }

  // ── Backfill de 60 días, una sola vez ─────────────────────────────────
  // El motor no da score con menos de 14 días de historia. Sin backfill, un
  // cliente que conecta hoy tendría que esperar dos semanas para ver algo;
  // con él, ve su score el primer día.
  const FLAG_BACKFILL = 'mypump_health_backfill_v1';
  async function backfill(onProgreso) {
    if (!isNative || !getToken()) return { ok: false };
    try { if (localStorage.getItem(FLAG_BACKFILL) === '1') return { ok: true, saltado: true }; } catch (e) {}
    let total = 0, cosechados = 0;
    for (let off = 60; off > 0; off -= 5) {
      const hasta = new Date(); hasta.setDate(hasta.getDate() - (off - 5));
      const desde = new Date(); desde.setDate(desde.getDate() - off);
      try {
        const regs = await recolectar(desde, hasta);
        cosechados += regs.length;
        total += await postear(regs);
        await postearEntrenos(await recolectarEntrenos(desde, hasta));
      } catch (e) { console.warn('[health] backfill ventana', off, e); }
      if (typeof onProgreso === 'function') onProgreso(60 - off + 5, 60);
    }
    // 60 días sin una sola muestra: se avisa ya, sin esperar la racha.
    //
    // Un iPhone estrenado hoy da el mismo cero y se lleva el aviso sin
    // merecerlo — son indistinguibles en ese instante y no hay forma de
    // separarlos. Se acepta a propósito: el texto describe el síntoma ("todavía
    // no llegó ningún dato") en vez de acusar a nadie, y se borra solo apenas
    // entra el primer dato. El caso caro es el otro: el que denegó y se va
    // convencido de que quedó andando.
    if (cosechados === 0) { try { localStorage.setItem(K_DENEG, '1'); } catch (e) {} }
    try { localStorage.setItem(FLAG_BACKFILL, '1'); } catch (e) {}
    if (typeof window.loadSalud === 'function') window.loadSalud();
    if (typeof window.loadRecuperacion === 'function') window.loadRecuperacion();
    return { ok: true, ingresados: total };
  }

  function isConnected() {
    return localStorage.getItem('mypump_health_connected') === '1';
  }

  const K_ULTIMA = 'mypump_health_last_sync';
  const K_DENEG  = 'mypump_health_denegado';

  function ultimaSync() {
    try { return localStorage.getItem(K_ULTIMA) || null; } catch (e) { return null; }
  }
  function marcarSync() {
    try { localStorage.setItem(K_ULTIMA, new Date().toISOString()); } catch (e) {}
  }
  function fueDenegado() {
    try { return localStorage.getItem(K_DENEG) === '1'; } catch (e) { return false; }
  }

  /* Devuelve un OBJETO, no un booleano: la UI necesita distinguir "no conectó"
   * de "denegó" para poder mandarlo a Ajustes. Antes devolvía false para los
   * dos casos y el cliente que denegaba podía tocar el botón cien veces sin
   * que pasara nada — iOS no reabre la hoja de un tipo ya respondido. */
  /* Rastro del último intento de conexión.
   *
   * Cuando esto falla, el cliente ve "no se pudo activar" y nosotros no
   * teníamos NADA para saber por qué: ni el motivo, ni si el plugin estaba
   * presente, ni qué versión de iOS. Sin eso, un cliente que reporta "no me
   * anda la salud" es imposible de ayudar sin tenerle el teléfono en la mano.
   * Queda en localStorage (no viaja a ningún lado) y se muestra en Mis datos. */
  const K_DIAG = 'mypump_health_diag';
  function anotarIntento(datos) {
    try {
      localStorage.setItem(K_DIAG, JSON.stringify(Object.assign({
        cuando: new Date().toISOString(),
        ios: iosMajor(),
        nativo: isNative,
        plugin: !!HEALTH(),
      }, datos)));
    } catch (e) {}
  }

  async function connect(onProgreso) {
    if (!isNative) {
      anotarIntento({ paso: 'plataforma', motivo: 'no_nativo' });
      return { ok: false, motivo: 'no_disponible' };
    }
    if (!HEALTH()) {
      // El plugin no está registrado: es un problema de build, no del cliente.
      anotarIntento({ paso: 'plugin', motivo: 'plugin_ausente' });
      return { ok: false, motivo: 'no_disponible' };
    }
    let disp = false, errDisp = null;
    try { const r0 = await HEALTH().isAvailable(); disp = !!(r0 && r0.available); }
    catch (e) { errDisp = String((e && e.message) || e); }
    if (!disp) {
      anotarIntento({ paso: 'isAvailable', motivo: 'no_disponible', error: errDisp });
      return { ok: false, motivo: 'no_disponible', detalle: errDisp };
    }

    const r = await requestPermission();
    if (!r.ok) {
      anotarIntento({ paso: 'permiso', motivo: r.motivo, error: r.detalle || null });
      return r;
    }
    anotarIntento({ paso: 'ok', preguntados: r.preguntados, total: r.total, errEstado: r.errEstado || null });
    // Se arranca de cero: si antes sospechábamos que no había permiso y el
    // cliente volvió a pasar por la hoja, la sospecha se descarta y se vuelve a
    // juzgar por los datos que lleguen de acá en más.
    try { localStorage.removeItem(K_DENEG); localStorage.setItem(K_RACHA, '0'); } catch (e) {}
    localStorage.setItem('mypump_health_connected', '1');
    await sync();
    marcarSync();
    await backfill(onProgreso);   // trae la historia para que el score arranque ya
    // Pasó por la hoja pero no vino ni una muestra en 60 días: casi seguro
    // destildó todo. Se avisa acá para que el cliente no tenga que descubrirlo
    // solo tres días después.
    return { ok: true, preguntados: r.preguntados, total: r.total, sinDatos: fueDenegado() };
  }

  function disconnect() {
    // Solo local: los datos ya subidos quedan (son del cliente y el coach los
    // usa). Esto corta la sincronización, no borra la historia.
    try {
      localStorage.removeItem('mypump_health_connected');
      localStorage.removeItem(K_ULTIMA);
      localStorage.removeItem(FLAG_BACKFILL);
    } catch (e) {}
  }

  // Estado completo para la pantalla de conexión.
  async function estado() {
    const disp = await hkAvailable();
    const est  = disp ? await estadoPermisos() : { conocido: false, preguntados: null, total: 0, pendientes: [], error: null };
    return {
      nativo: isNative,
      disponible: disp,
      conectado: isConnected(),
      // "sinDatos" y no "denegado": es una sospecha por falta de datos, no un
      // veredicto de HealthKit, que nunca lo da (ver estadoPermisos).
      sinDatos: fueDenegado(),
      preguntados: est.preguntados,
      total: est.total,
      pendientes: est.pendientes,
      errEstado: est.error,
      ultimaSync: ultimaSync(),
      ios: iosMajor(),
    };
  }

  // ── Diagnóstico: ?diag=health ─────────────────────────────────────────
  // Vuelca qué trajo cada tipo y el error nativo textual si falló. Existe para
  // poder verificar HealthKit desde el iPhone sin Xcode conectado — el
  // simulador no tiene datos de salud, así que sin esto cada iteración
  // requeriría cable.
  async function diagnostico() {
    window.__MYPUMP_DIAG = [];
    const out = { nativo: isNative, disponible: await hkAvailable(), token: !!getToken(), tipos: [], noches: [] };
    if (!out.disponible) return out;
    const hasta = new Date(), desde = new Date(); desde.setDate(desde.getDate() - 14);

    for (const { dataType, tipo, agg } of AGG) {
      try {
        const r = await HEALTH().queryAggregated({ dataType, startDate: desde.toISOString(),
          endDate: hasta.toISOString(), bucket: 'day', aggregation: agg });
        const s = (r && r.samples) || [];
        out.tipos.push({ tipo, dataType, via: 'aggregated', n: s.length,
          primero: s.length ? ymd(s[0].startDate) : null, ultimo: s.length ? ymd(s[s.length - 1].startDate) : null });
      } catch (e) { out.tipos.push({ tipo, dataType, via: 'aggregated', n: 0, error: String(e && e.message || e) }); }
    }
    for (const { dataType, tipo } of SAMPLES.concat([{ dataType: 'heartRateVariability', tipo: 'hrv_ms' }])) {
      const ms = await leerMuestras(dataType, desde, hasta);
      out.tipos.push({ tipo, dataType, via: 'samples', n: ms.length,
        primero: ms.length ? ymd(ms[0].startDate) : null, ultimo: ms.length ? ymd(ms[ms.length - 1].startDate) : null });
    }
    // Sueño con el detalle por fuente: es lo que decide si la heurística de
    // dedup está bien calibrada para los datos REALES de este usuario.
    const msS = await leerMuestras('sleep', desde, hasta);
    const porNoche = {};
    for (const s of msS) {
      const k = ymd(s.endDate), src = s.sourceName || s.sourceId || '?';
      const st = String(s.sleepState || s.value || '').toLowerCase();
      const min = (new Date(s.endDate) - new Date(s.startDate)) / 60000;
      porNoche[k] = porNoche[k] || {};
      porNoche[k][src] = porNoche[k][src] || {};
      porNoche[k][src][st] = Math.round((porNoche[k][src][st] || 0) + min);
    }
    out.noches = Object.keys(porNoche).sort().map(f => ({ fecha: f, fuentes: porNoche[f] }));
    out.errores = window.__MYPUMP_DIAG;
    return out;
  }

  // Fallback del background delivery: sincronizar al abrir y al volver a foco.
  // El plugin no soporta background real con la app cerrada (ver docs/IOS_SETUP.md).
  if (isNative) {
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden && isConnected()) sync();
    });
    window.addEventListener('load', () => { if (isConnected()) sync(); });
  }

  window.MyPumpHealth = {
    isAvailable: () => isNative,
    isConnected,
    connect,
    disconnect,
    estado,          // estado real: conectado / denegado / cuántos permisos / última sync
    ultimaSync,
    sync,
    backfill,
    diagnostico,
  };
})();
