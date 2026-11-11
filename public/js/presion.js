/* =============================================================
   presion.js — «Presión arterial»: textos y reglas puras.

   Implementa presion/PROTOCOLO.md y presion/CAMPOS.md (aprobados por Mati el 10/11/2026).
   Es la referencia de las reglas: el kit de iOS, el de Android y el servidor dan lo mismo
   contra scripts/vectores-app/presion.json (= apps/shared/vectores/presion.json).

   Invariantes:
   · El alumno no ve promedios, colores, categorías ni palabras como hipertensión, normal,
     alta o riesgo (PROTOCOLO §5.3). Lo que calcula `resumenSerie` no se muestra: solo el avance.
   · La presión nunca frena el entrenamiento: nada de acá toca la rutina.
   · El texto de guardia se decide acá, sin esperar al servidor.
   ============================================================= */
(function (raiz) {
  'use strict';

  const LIM = { sisMin: 60, sisMax: 260, diaMin: 30, diaMax: 160, pulMin: 25, pulMax: 220, difMin: 10 };
  const ESPERA_REPETICION_S = 300;
  const REPOSO_S = 300;
  const RECORDATORIO_MIN = 10;
  /** Minutos sin repetir una toma de 180/120 para que cuente como alta (el recordatorio sale a los 10). */
  const SIN_REPETIR_MIN = 15;

  const ALARMA = ['dolor_pecho', 'falta_aire', 'cefalea_fuerte_nueva', 'cambios_vista', 'debilidad_un_lado', 'dificultad_hablar', 'confusion', 'desmayo'];
  const OTROS = ['palpitaciones', 'mareo_al_pararse', 'vomitos_diarrea'];
  const SINTOMAS = {
    dolor_pecho: 'Dolor de pecho', falta_aire: 'Falta de aire', cefalea_fuerte_nueva: 'Dolor de cabeza fuerte y distinto',
    cambios_vista: 'Cambios en la vista', debilidad_un_lado: 'Debilidad u hormigueo de un lado del cuerpo',
    dificultad_hablar: 'Dificultad para hablar', confusion: 'Confusión', desmayo: 'Desmayo',
    palpitaciones: 'Palpitaciones', mareo_al_pararse: 'Mareo al pararse', vomitos_diarrea: 'Vómitos o diarrea',
  };

  const entero = (x) => typeof x === 'number' && Number.isFinite(x) && Math.floor(x) === x;
  /** Promedio redondeado al entero, la mitad para arriba, con cuentas enteras (igual en todos los lenguajes). */
  const media = (xs) => Math.floor((2 * xs.reduce((a, b) => a + b, 0) + xs.length) / (2 * xs.length));

  /** 'ok', 'imposible' (no se acepta) o 'confirmar' (valor de urgencia o de alta: se pide confirmar el número). */
  function validarToma(t) {
    if (!t || !entero(t.sis) || !entero(t.dia) || !entero(t.pulso)) return 'imposible';
    if (t.sis < LIM.sisMin || t.sis > LIM.sisMax || t.dia < LIM.diaMin || t.dia > LIM.diaMax || t.pulso < LIM.pulMin || t.pulso > LIM.pulMax) return 'imposible';
    if (t.sis - t.dia < LIM.difMin) return 'imposible';
    if (t.sis >= 160 || t.dia >= 100 || t.pulso >= 120 || t.pulso <= 40) return 'confirmar';
    return 'ok';
  }

  /** 'urgencia' (180 o 120), 'alta' (160 o 100) o 'comun'. */
  function nivelToma(t) {
    if (t.sis >= 180 || t.dia >= 120) return 'urgencia';
    if (t.sis >= 160 || t.dia >= 100) return 'alta';
    return 'comun';
  }

  function deAlarma(codigos) {
    return (codigos || []).some((c) => ALARMA.indexOf(c) !== -1 || c === 'desmayo_en_esfuerzo');
  }

  /** El tramo de la barra de talles. Justo en el límite, el de arriba. */
  function tramoBrazo(cm) {
    if (!(typeof cm === 'number' && cm > 0)) return null;
    if (cm < 22) return 'menos_22';
    if (cm < 32) return 'estandar';
    if (cm < 42) return 'grande';
    if (cm <= 52) return 'extra_grande';
    return 'mas_52';
  }

  /** true, false, o null si el aparato no trae ningún rango. Manda el validado; si no hay, el impreso. */
  function manguitoCalza(cm, a) {
    if (!a || !(typeof cm === 'number' && cm > 0)) return null;
    let min = a.manguito_validado_min_cm, max = a.manguito_validado_max_cm;
    if (typeof min !== 'number' || typeof max !== 'number') { min = a.manguito_min_cm; max = a.manguito_max_cm; }
    if (typeof min !== 'number' || typeof max !== 'number') return null;
    if (cm < min || cm > max) return false;
    // En el límite entre dos talles, el más grande: un manguito que termina en 32 o en 42 no calza justo ahí.
    if (cm === max && (max === 32 || max === 42)) return false;
    return true;
  }

  /** Qué lugar tiene el aparato con esa medida: brazo, muñeca provisoria o muñeca habitual (más de 52 cm). */
  function metodo(cm, a) {
    const r = { metodo: 'brazo', provisoria: false, pedir_brazo: false, pedir_validado: false, admite_tomas: true };
    if (!a) return r;
    if (a.tipo === 'reloj_anillo_otro') { r.metodo = 'no_sirve'; r.admite_tomas = false; r.pedir_brazo = true; return r; }
    if (a.tipo === 'muneca') {
      if (typeof cm === 'number' && cm > 52) { r.metodo = 'muneca_habitual'; r.pedir_validado = a.validado === 'no'; }
      else { r.metodo = 'muneca_provisoria'; r.provisoria = true; r.pedir_brazo = true; }
      return r;
    }
    if (a.validado === 'no') { r.provisoria = true; r.pedir_validado = true; }
    return r;
  }

  /** Mañana, de 4 a 11.59 hora local. */
  function momento(hora) { return hora >= 4 && hora < 12 ? 'manana' : 'otro'; }

  /** Los pasos guiados de una sesión: cada uno con su espera y la toma que pide. */
  function pasos(tipo, variante) {
    if (tipo === 'ortostatica') {
      const base = variante === 'sentado_parado' ? 'sentado' : 'acostado';
      return [
        { espera_s: 300, posicion: base, minutos_de_pie: null, brazo: null },
        { espera_s: 60, posicion: 'de_pie', minutos_de_pie: 1, brazo: null },
        { espera_s: 120, posicion: 'de_pie', minutos_de_pie: 3, brazo: null },
      ];
    }
    if (tipo === 'comparacion_brazos') {
      return ['izq', 'der', 'der', 'izq'].map((b, i) => ({ espera_s: i === 0 ? REPOSO_S : 60, posicion: 'sentado', minutos_de_pie: null, brazo: b }));
    }
    return [{ espera_s: REPOSO_S, posicion: 'sentado', minutos_de_pie: null, brazo: null }];
  }

  function ortostatica(tomas) {
    const base = (tomas || []).find((t) => t.posicion !== 'de_pie');
    const pie = (tomas || []).filter((t) => t.posicion === 'de_pie');
    if (!base || !pie.length) return null;
    const cs = Math.max.apply(null, pie.map((t) => base.sis - t.sis));
    const cd = Math.max.apply(null, pie.map((t) => base.dia - t.dia));
    const sp = Math.max.apply(null, pie.map((t) => t.pulso - base.pulso));
    const sube = Math.max.apply(null, pie.map((t) => t.sis - base.sis));
    return {
      caida_sis_max: cs, caida_dia_max: cd, subida_pulso_max: sp,
      hipotension: cs >= 20 || cd >= 10,
      hipertension_posible: sube >= 20 || pie.some((t) => t.sis >= 140 && t.sis > base.sis),
    };
  }

  const tiene = (xs, ys) => (xs || []).some((x) => ys.indexOf(x) !== -1);

  /**
   * Una sesión: qué hace la app ahora (`paso` y `texto`), si la toma cuenta para el promedio y qué reglas se cumplen.
   * La urgencia y la alta se evalúan siempre, también en las tomas que no cuentan. Solo con tomas sentado.
   */
  function evaluarSesion(s) {
    const tipo = s.tipo || 'estandar';
    const sint = s.sintomas || [];
    const S = (s.tomas || []).filter((t) => t.posicion === 'sentado' || !t.posicion).slice().sort((a, b) => a.orden - b.orden);
    const reglas = [];
    const niv = S.map(nivelToma);
    let conf180 = false, conf160 = false;
    for (let i = 1; i < S.length; i++) {
      if (niv[i] === 'urgencia' && niv[i - 1] === 'urgencia') conf180 = true;
      if (niv[i] !== 'comun' && niv[i - 1] !== 'comun') conf160 = true;
    }
    // La comparación de brazos y la ortostática son secuencias fijas: no piden repetición.
    const guiada = tipo === 'ortostatica' || tipo === 'comparacion_brazos';
    const ultimo = S.length ? niv[S.length - 1] : 'comun';
    const pendiente = !guiada && S.length > 0 && ((ultimo === 'urgencia' && !conf180) || (ultimo === 'alta' && !conf160));
    const min = typeof s.minutos_desde_ultima === 'number' ? s.minutos_desde_ultima : 0;

    let paso = 'listo', texto = 'ninguno';
    const alarma = deAlarma(sint);
    const pulso120 = S.some((t) => t.pulso >= 120) && tiene(sint, ['palpitaciones', 'dolor_pecho', 'falta_aire', 'mareo_al_pararse']);
    const pulso40 = S.some((t) => t.pulso <= 40) && tiene(sint, ['mareo_al_pararse', 'desmayo', 'desmayo_en_esfuerzo']);
    if (alarma) reglas.push(s.lista_espera === 'si' ? 'sintoma_alarma_en_espera' : 'sintoma_alarma');
    if (tiene(sint, ['desmayo', 'desmayo_en_esfuerzo'])) reglas.push('desmayo');
    if (pulso120) reglas.push('pulso_120_sintomas');
    if (pulso40) reglas.push('pulso_40_mareo');
    if (conf180) reglas.push('toma_180_120_confirmada');
    else if (conf160) reglas.push('alta_toma_160_100');
    if (pendiente && ultimo === 'urgencia' && min >= SIN_REPETIR_MIN) reglas.push('alta_180_120_sin_repetir');
    if (pendiente && ultimo === 'alta' && min >= RECORDATORIO_MIN) reglas.push('repetir_pendiente');

    const urgSintomas = alarma || pulso120 || pulso40;
    if (urgSintomas) { paso = 'guardia_sintomas'; texto = 'guardia_sintomas'; }
    else if (conf180) { paso = 'guardia_presion'; texto = 'guardia_presion'; }
    else if (pendiente) {
      paso = ultimo === 'urgencia' ? 'repetir_con_lista' : 'repetir';
      texto = min >= RECORDATORIO_MIN ? 'repetir_pendiente' : (ultimo === 'urgencia' ? 'lista_sintomas_espera' : 'quedate_sentado_5min');
    }

    const otros = sint.filter((c) => !deAlarma([c]));
    if (S.some((t) => t.sis < 90) && otros.length) { reglas.push('sistolica_menor_90_sintomas'); if (paso === 'listo') texto = 'sentate_agua'; }
    if (sint.indexOf('mareo_al_pararse') !== -1) { reglas.push('sintomas_al_pararse'); if (tipo === 'ortostatica' && paso === 'listo') texto = 'quedate_sentado_ortostatica'; }
    if (sint.indexOf('vomitos_diarrea') !== -1) reglas.push('sintoma_vomitos_diarrea');
    if (S.some((t) => t.pulso <= 40) && !sint.length) reglas.push('pulso_40_sin_sintomas');

    let orto = null;
    if (tipo === 'ortostatica') {
      orto = ortostatica(s.tomas);
      if (orto && orto.hipotension) reglas.push('ortostatica_positiva');
    }

    const valor = S.length ? { sis: media(S.map((t) => t.sis)), dia: media(S.map((t) => t.dia)), pulso: media(S.map((t) => t.pulso)) } : null;
    const p = s.previo || {};
    const incumplida = !!(p.cafeina || p.fumo || p.comida || p.ejercicio) || s.reposo_cumplido !== true || s.temporizador_salteado === true;
    let cuenta = false, motivo = null;
    if (!(s.tomas || []).length) motivo = 'error';
    else if (tipo === 'bajo_efecto') motivo = 'bajo_efecto';
    else if (tipo === 'ortostatica') motivo = 'ortostatica';
    else if (tipo === 'comparacion_brazos') motivo = 'comparacion_brazos';
    else if (tipo === 'suelta') motivo = 'otra';
    else if (!S.length) motivo = 'error';
    else if (incumplida) motivo = 'condicion_incumplida';
    else if (pendiente) motivo = 'otra';
    else cuenta = true;
    if (motivo === 'condicion_incumplida' && paso === 'listo' && texto === 'ninguno') texto = 'toma_no_cuenta';
    const validaBajoEfecto = tipo === 'bajo_efecto' && S.length > 0 && !pendiente && s.reposo_cumplido === true && s.temporizador_salteado !== true && s.entreno_entre_dosis_y_toma === false;
    if (tipo === 'bajo_efecto' && S.length > 0 && !validaBajoEfecto && paso === 'listo' && texto === 'ninguno') texto = 'toma_no_cuenta';
    // Una toma suelta de 135/85 o más no avisa: dispara una serie de 3 tomas.
    if (tipo === 'suelta' && valor && !pendiente && (valor.sis >= 135 || valor.dia >= 85)) reglas.push('suelta_135_85');

    return {
      paso, texto, cuenta, motivo_exclusion: motivo, valor, valida_bajo_efecto: validaBajoEfecto,
      urgencia: urgSintomas || conf180, ortostatica: orto, reglas: reglas.slice().sort(),
    };
  }

  function categoria(p) {
    if (p.sis >= 150 || p.dia >= 95) return 'hipertension_casa_estadio_2';
    if (p.sis >= 135 || p.dia >= 85) return 'hipertension_casa';
    if (p.sis >= 130 || p.dia >= 80) return 'limitrofe';
    if (p.sis >= 120) return 'elevada';
    return 'optima';
  }

  const sumarDias = (f, n) => { const d = new Date(f + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };

  /**
   * La serie: 3 tomas válidas, una por día, en 3 días distintos dentro de los 7 días del inicio.
   * `e.serie` = { tipo: 'estandar' | 'bajo_efecto', tomas_objetivo, fecha_inicio }; `e.sesiones` con `fecha` local.
   */
  function resumenSerie(e) {
    const serie = e.serie || {};
    const objetivo = serie.tomas_objetivo || 3;
    const deBajoEfecto = serie.tipo === 'bajo_efecto';
    const hasta = serie.fecha_inicio ? sumarDias(serie.fecha_inicio, 6) : null;
    const enPlazo = (f) => !serie.fecha_inicio || (f >= serie.fecha_inicio && f <= hasta);
    const ses = (e.sesiones || []).slice().sort((a, b) => (a.fecha < b.fecha ? -1 : a.fecha > b.fecha ? 1 : (a.orden || 0) - (b.orden || 0)));
    const reglas = [];
    const dias = [], valores = [], maxS = [], maxD = [];
    const beDias = [], beValores = [];
    let beN = 0, irregulares = 0;
    for (const s of ses) {
      const ev = evaluarSesion(s);
      ev.reglas.forEach((r) => reglas.push(r));
      irregulares += (s.tomas || []).filter((t) => t.latido_irregular === true).length;
      if (s.tipo === 'bajo_efecto') {
        beN++;
        if (ev.valida_bajo_efecto && enPlazo(s.fecha) && beDias.indexOf(s.fecha) === -1 && beDias.length < objetivo) { beDias.push(s.fecha); beValores.push(ev.valor); }
      }
      if (ev.cuenta && enPlazo(s.fecha) && dias.indexOf(s.fecha) === -1 && dias.length < objetivo) {
        dias.push(s.fecha); valores.push(ev.valor);
        (s.tomas || []).forEach((t) => { maxS.push(t.sis); maxD.push(t.dia); });
      }
    }
    const prom = (vs) => (vs.length ? { sis: media(vs.map((v) => v.sis)), dia: media(vs.map((v) => v.dia)), pulso: media(vs.map((v) => v.pulso)) } : null);
    const promedio = prom(valores);
    const validas = deBajoEfecto ? beDias.length : dias.length;
    const serieValida = validas >= objetivo;
    const soloUrg = e.solo_urgencias === true;

    if (!deBajoEfecto && serieValida && !soloUrg && (promedio.sis >= 135 || promedio.dia >= 85)) reglas.push('alta_promedio_135_85');
    if (valores.filter((v) => v.pulso >= 100).length >= 2) reglas.push('pulso_100_dos_tomas');
    if (!deBajoEfecto && serieValida && typeof e.basal_pulso === 'number' && promedio.pulso - e.basal_pulso >= 20) reglas.push('pulso_20_sobre_basal');
    if (irregulares >= 2) reglas.push('latido_irregular_2_tomas');

    const bp = prom(beValores);
    const beAlta = beValores.length >= 2 && (bp.sis >= 150 || bp.dia >= 95);
    const beAviso = beValores.length >= 2 && !beAlta && (bp.sis >= 135 || bp.dia >= 85);
    const bePulso = beValores.filter((v) => v.pulso >= 100).length;
    if (beAlta) reglas.push('alta_bajo_efecto_150_95');
    if (beAviso) reglas.push('bajo_efecto_135_85');
    if (bePulso >= 2) reglas.push('pulso_100_bajo_efecto');

    return {
      tomas_validas: validas, dias: deBajoEfecto ? beDias : dias, serie_valida: serieValida, faltan: Math.max(0, objetivo - validas),
      promedio, maximos: maxS.length ? { sis: Math.max.apply(null, maxS), dia: Math.max.apply(null, maxD) } : null,
      categoria: !deBajoEfecto && serieValida && !soloUrg ? categoria(promedio) : null,
      bajo_efecto: { n: beN, validas: beValores.length, promedio: beValores.length >= 2 ? bp : null, tomas_pulso_100_o_mas: bePulso, aviso: beAviso, alta: beAlta },
      reglas: reglas.filter((r, i) => reglas.indexOf(r) === i).sort(),
    };
  }

  // ── Textos. Los de PROTOCOLO, GRAFICOS y TENSIOMETROS van tal cual; los de `N` son de la app y esperan el OK de Mati. ──
  const T = {
    antes: [
      'Para esto necesitás un tensiómetro automático de brazo. El reloj no sirve. Si ya tenés uno de muñeca, por ahora lo usamos, pero vas a tener que comprar uno de brazo.',
      'Antes de comprarlo medite el brazo con un centímetro de costura. Medí en la mitad entre el hombro y el codo, con el brazo relajado al costado del cuerpo y sin haber entrenado ese día.',
      'Con esa medida la app te muestra qué aparatos sirven. El manguito trae impreso un rango en centímetros y tu medida tiene que entrar en ese rango. Si quedás justo en el límite entre dos talles, elegí el más grande.',
      'Sacale una foto al tensiómetro y otra a la etiqueta del manguito y subilas acá. Yo te confirmo si sirve.',
    ],
    medirBrazo: [
      'Usá un centímetro de costura, de los blandos.',
      'Medí el brazo en el que te vas a tomar la presión. Sacate la remera o subí bien la manga.',
      'Dejá el brazo relajado, colgando al costado del cuerpo, sin hacer fuerza.',
      'Buscá la mitad entre la punta del hombro y la punta del codo. Si podés, pedile a alguien que te ayude.',
      'Rodeá el brazo a esa altura, sobre la piel, derecho y sin apretar.',
      'Anotá los centímetros. Si dudás entre dos números, anotá el más alto.',
      'No te midas recién entrenado ni con el brazo hinchado. Hacelo un día de descanso o antes de entrenar.',
    ],
    medirDeNuevo: 'Antes de empezar, medite de nuevo el brazo y anotalo.',
    g3: [
      'Medí en la mitad entre el hombro y el codo', 'Brazo relajado y sin haber entrenado ese día',
      'Tu medida tiene que entrar en el rango que trae impreso el manguito', 'Si quedás justo entre dos talles, elegí el más grande',
    ],
    g3Alt: 'Brazo relajado con un centímetro alrededor, en la mitad entre el hombro y el codo. Abajo, una etiqueta de manguito con su rango en centímetros y una barra de talles de chico a extra grande.',
    tramos: { estandar: 'Estándar', grande: 'Grande', extra_grande: 'Extra grande', mas_52: 'Te indico yo' },
    tramosRango: { estandar: '22 a 32 cm', grande: '32 a 42 cm', extra_grande: '42 a 52 cm', mas_52: 'Más de 52 cm' },
    marca42: 'Más de 42 cm, manguito más grande, mejor si es cónico',
    verCuales: 'Ver cuáles sirven',
    fueraDeTalle: 'Ese manguito no es de tu talle. Mandame una foto de la etiqueta y lo vemos.',
    porTramo: {
      estandar: 'Con tu medida te sirve casi cualquier tensiómetro de brazo de esta lista. Fijate que el código de la caja sea igual al de la lista, con las letras del final.',
      grande: 'Con tu medida necesitás un manguito que llegue hasta 42. Te dejo cuáles sirven. Fijate que el código de la caja sea igual al de la lista, con las letras del final.',
      extra_grande: 'Con tu medida necesitás un manguito más grande, que en general se compra aparte. Te dejo cuáles sirven.',
      mas_52: 'Con tu medida te indico yo cuál usar. Si ya tenés un tensiómetro, subí las fotos y te digo.',
    },
    muneca: ['Por ahora usamos el de muñeca, pero necesito que compres uno de brazo.', 'Te dejo cuáles sirven según la medida de tu brazo.'],
    munecaNoValidada: 'Ese de muñeca no está entre los que miden bien. Te dejo cuáles sirven.',
    noValidado: ['Ese tensiómetro no está entre los que miden bien. Por ahora lo usamos, pero necesito que compres uno de la lista.', 'Te dejo cuáles sirven según la medida de tu brazo.'],
    cuandoTitulo: 'Cuándo',
    cuando: [
      'Son 3 tomas en total, una por día, en 3 días distintos de la misma semana.',
      'A la mañana, después de hacer pis y antes de desayunar, del mate o el café, del preentreno, de tus remedios y de entrenar.',
      'En la media hora previa nada de cigarrillo, vapeador, comida, café, mate, energizante ni preentreno.',
    ],
    comoTitulo: 'Cómo',
    como: (brazo) => [
      'Sentate en una silla con respaldo, al lado de una mesa, en un lugar tranquilo. Espalda apoyada, pies planos en el piso y piernas sin cruzar.',
      `Apoyá el brazo ${brazo === 'der' ? 'derecho' : 'izquierdo'} en la mesa, relajado y con la palma para arriba. El manguito va sobre la piel, nunca sobre la ropa. Si la manga te aprieta al subirla, sacate la remera.`,
      'La mitad del manguito tiene que quedar a la altura del corazón. Si la mesa es baja, poné un almohadón abajo del brazo.',
      'El borde de abajo del manguito va 2 o 3 centímetros arriba del pliegue del codo, con la marca de la arteria del lado de adentro del brazo. Ajustalo firme, que entre justo un dedo.',
      'Quedate 5 minutos quieto, sin hablar ni mirar el celular.',
      'Hacé la toma y anotá la alta, la baja y el pulso. Si el aparato muestra el símbolo de latido irregular, marcalo.',
      'Si sale error, revisá el manguito, esperá un minuto y repetí.',
      'Listo por hoy. La próxima, otro día.',
    ],
    g1: ['Espalda apoyada', 'Pies planos en el piso y piernas sin cruzar', 'Brazo apoyado en la mesa', 'La mitad del manguito a la altura del corazón', '5 minutos quieto y sin hablar'],
    g1Alt: 'Persona sentada de costado en una silla con respaldo, con la espalda apoyada, los pies en el piso, el brazo sobre la mesa y el manguito a la altura del corazón.',
    g2: [['Brazo colgando', 'Da más alto'], ['A la altura del corazón', 'Así sí'], ['Brazo levantado', 'Da más bajo']],
    g2Alt: 'Tres dibujos. Con el brazo colgando la presión da más alta, con el brazo levantado da más baja y con el manguito a la altura del corazón da bien.',
    g4: ['2 o 3 centímetros arriba del pliegue del codo', 'La marca de la arteria va del lado de adentro', 'Firme, que entre justo un dedo', 'Sobre la piel, nunca sobre la ropa'],
    g4Alt: 'Brazo visto del lado de adentro con el manguito sobre la piel, dos o tres centímetros arriba del pliegue del codo, con la marca de la arteria del lado de adentro y un dedo que entra justo debajo del borde.',
    queEvitar: 'Qué evitar',
    g5: [
      ['Hablar o mirar el celular', 'Ni antes ni durante la toma'], ['Piernas cruzadas', 'Pies planos en el piso'],
      ['Sobre la ropa', 'El manguito va sobre la piel'], ['Brazo colgando', 'Apoyalo en la mesa'],
      ['Medirte recién entrenado', 'Esperá al menos una hora'], ['Café, mate, energizante o preentreno', 'Nada en la media hora previa'],
      ['Cigarrillo o vapeador', 'Nada en la media hora previa'], ['Con ganas de hacer pis', 'Andá al baño antes'],
      ['Sillón blando o sin respaldo', 'Silla con respaldo recto'], ['Reloj o anillo para medir', 'Solo tensiómetro de brazo'],
    ],
    g5Alt: 'Diez cosas que hay que evitar al medirte la presión. Hablar o mirar el celular, cruzar las piernas, poner el manguito sobre la ropa, dejar el brazo colgando, medirte recién entrenado, tomar café, mate, energizante o preentreno, fumar o vapear, medirte con ganas de hacer pis, sentarte en un sillón blando y usar un reloj o un anillo para medir.',
    bien: 'Bien', asiNo: 'Así no',
    bajoEfecto: [
      'Estas 3 tomas son con el estimulante hecho efecto. Medite entre 1 y 2 horas después de tomarlo, en 3 días distintos.',
      'Hacé la toma antes de entrenar. Si entrenaste entre la dosis y la toma, esa no cuenta y la hacés otro día.',
      'Sentado, con la espalda apoyada y el brazo a la altura del corazón. Esperá 5 minutos sin hablar y medite, igual que en las otras tomas.',
      'Anotá a qué hora tomaste el estimulante.',
    ],
    brazos: ['Hoy hacé 4 tomas en este orden, izquierdo, derecho, derecho e izquierdo, con un minuto de descanso entre cada una.', 'Estas no cuentan para el promedio. Sirven para ver qué brazo usar.'],
    ortostatica: (sentado) => [
      'Hacela a la mañana, después de la toma sentado, con el mismo manguito puesto.',
      'Hacela al lado de la cama, sin nadie apurándote.',
      sentado ? 'Sentado 5 minutos y una toma' : 'Acostate boca arriba 5 minutos. Dejá el brazo apoyado sobre una almohada chica, a la altura del medio del pecho.',
      sentado ? null : 'Hacé una toma acostado.',
      'Parate al lado de la cama. Apoyá el antebrazo en un mueble alto o sostenelo con la otra mano, así el manguito queda a la altura del corazón. No dejes el brazo colgando.',
      'Cuando la app marque un minuto parado, hacé una toma.',
      'Cuando marque 3 minutos parado, hacé otra.',
      'Si te mareás, se te nubla la vista o sentís que te vas a desmayar, sentate o acostate enseguida y marcalo. No hace falta terminar.',
    ].filter(Boolean),
    g6: (sentado) => [sentado ? 'Sentado 5 minutos y una toma' : 'Acostado 5 minutos y una toma', 'Parado, toma al minuto 1', 'Parado, toma al minuto 3'],
    g6Mareo: 'Si te mareás, sentate o acostate enseguida',
    g6Antebrazo: 'Antebrazo apoyado, sin dejarlo colgando',
    g6Alt: 'Tres dibujos. Acostado cinco minutos con una toma, después parado con el antebrazo apoyado y tomas al minuto uno y al minuto tres. Si te mareás, sentate o acostate enseguida.',
    faltan: (n) => (n === 1 ? 'Te falta 1 toma' : `Te faltan ${n} tomas`),
    avanceAlt: (n, total) => `${total === 3 ? 'Tres' : total} círculos, uno por toma. Completaste ${['cero', 'una', 'dos', 'tres'][n] || n} de ${total === 3 ? 'tres' : total}.`,
    listoSerie: 'Listo, terminaste las 3 tomas. Gracias.',
    listoSerieCorto: 'Listo, terminaste las 3 tomas',
    marcarSintoma: 'Marcar un síntoma',
    esperaTitulo: 'Quedate sentado y tranquilo. En 5 minutos volvé a medirte.',
    esperaLista: 'Mientras esperás, decime si tenés alguno de estos.',
    esperaVoz: 'Faltan 5 minutos para volver a medirte.',
    si: 'Sí', no: 'No',
    repetirPendiente: 'Te quedó pendiente repetir la toma. Hacela sentado y tranquilo cuando puedas.',
    guardiaPresion: [
      'Con estos valores tiene que verte un médico hoy. Andá a una guardia.',
      'No tomes nada por tu cuenta para bajarla. Si ya tenés un remedio para la presión indicado, tomalo como siempre, sin doblarlo.',
      'Si aparece dolor de pecho, falta de aire, debilidad de un lado del cuerpo o te cuesta hablar, no vayas manejando y llamá a emergencias.',
    ],
    guardiaSintomas: [
      'Con lo que marcaste tiene que verte un médico ahora. Andá a una guardia.',
      'No vayas manejando. Si es dolor de pecho, falta de aire, debilidad de un lado del cuerpo o te cuesta hablar, llamá a emergencias.',
    ],
    sentateAgua: 'Sentate o acostate un rato y tomá agua. Escribime cuando puedas.',
    mareoOrtostatica: 'Quedate sentado o acostado hasta que se te pase.',
    latidoIrregular: 'Gracias, seguí como siempre.',
    revisarNumero: 'Revisá el número que anotaste. Si podés, sacale una foto a la pantalla del aparato.',
    revisarNumeroSinFoto: 'Revisá el número que anotaste.',
    noCuenta: 'Esta no cuenta. Hacé otra otro día, antes del café y del preentreno.',
    recordatorioManana: 'Buen día, te toca la presión antes de desayunar.',
  };

  /** Textos propios de la app (botones, títulos y preguntas). Esperan el OK de Mati: privado/TEXTOS_PARA_OK.md, «Presión». */
  const N = {
    titulo: 'Presión',
    entrada: 'Presión arterial',
    antesTitulo: 'Antes de la primera serie',
    medirBrazoTitulo: 'Cómo medirte el brazo',
    medida: 'Medida del brazo, en centímetros',
    tipoAparato: '¿Qué tensiómetro tenés?',
    tipos: { brazo: 'De brazo', muneca: 'De muñeca', reloj_anillo_otro: 'Reloj, anillo u otro', ninguno: 'Todavía no tengo' },
    marca: 'Marca', modelo: 'Modelo', codigo: 'Código de la etiqueta', codigoAyuda: 'Copialo tal cual, con las letras del final',
    rango: 'Rango impreso en el manguito, en centímetros', desde: 'Desde', hasta: 'Hasta',
    guardar: 'Guardar', seguir: 'Seguir', empezar: 'Empezar', cerrar: 'Cerrar', volver: 'Volver',
    tomaDeHoy: 'Hacer la toma de hoy', tomaSuelta: 'Anotar una toma', repetir: 'Repetir la toma',
    previas: 'Antes de medirte',
    previa: {
      cafeina: '¿Tomaste café, mate, energizante o preentreno en la última media hora?',
      fumo: '¿Fumaste o vapeaste en la última media hora?',
      comida: '¿Comiste en la última media hora?',
      ejercicio: '¿Entrenaste en la última hora?',
    },
    esperarMejor: 'Mejor esperá un rato y medite después.', esperar: 'Esperar', medirIgual: 'Medirme igual',
    reposo: 'Quedate 5 minutos quieto, sin hablar ni mirar el celular', saltear: 'Ya esperé',
    alta: 'Alta', baja: 'Baja', pulso: 'Pulso', irregular: 'El aparato mostró el símbolo de latido irregular',
    anotar: 'Anotar la toma', confirmar: 'Sí, es ese número', corregir: 'Corregir',
    horaDosis: '¿A qué hora tomaste el estimulante?', entrenoEntre: '¿Entrenaste entre la dosis y la toma?',
    alarma: 'Avisame si tenés alguno de estos', otros: 'Otros', nota: 'Si querés, contame algo más', enviar: 'Enviar',
    sintomaRecibido: 'Anotado.',
    tusTomas: 'Tus tomas', sinTomas: 'Todavía no anotaste ninguna toma',
    hoyListo: 'La de hoy ya está. La próxima, otro día.',
    relojNoSirve: 'El reloj y el anillo no sirven para esto. Hace falta un tensiómetro de brazo.',
    aparato: 'Tu tensiómetro', cambiarAparato: 'Cambiar', brazo: 'Brazo', cm: 'cm',
    brazoIzq: 'Brazo izquierdo', brazoDer: 'Brazo derecho',
    noGuardo: 'No se pudo guardar. Probá de nuevo.',
    sinSenal: 'Sin señal. Queda guardada y se manda sola.',
    tarjeta: 'Tu presión',
    tarjetaPreparar: 'Primero medí tu brazo y anotá tu tensiómetro',
    tarjetaSerie: 'Son 3 tomas, una por día',
    meMaree: 'Me mareé', minutoParado: (n) => (n === 1 ? 'Toma al minuto 1' : 'Toma al minuto 3'),
    sinLista: 'Todavía estamos armando la lista para tu país.',
    graficoAlt: (n) => `Gráfico con tus ${n} tomas, alta y baja, por día.`,
  };

  const API = {
    LIM, ESPERA_REPETICION_S, REPOSO_S, RECORDATORIO_MIN, SIN_REPETIR_MIN, ALARMA, OTROS, SINTOMAS, T, N,
    validarToma, nivelToma, deAlarma, tramoBrazo, manguitoCalza, metodo, momento, pasos, ortostatica, evaluarSesion, categoria, resumenSerie, media,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Presion = API;
})(typeof window !== 'undefined' ? window : globalThis);
