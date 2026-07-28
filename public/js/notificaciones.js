/* =============================================================
   notificaciones.js — recordatorios locales de MyPump

   POR QUÉ EXISTE
   Hasta acá la app no tenía NINGUNA notificación. El cliente se enteraba de
   algo nuevo solo si Mati le escribía por WhatsApp a mano, o si abría la app
   por su cuenta. Los badges (comentarios sin leer, check pendiente) se
   calculan al abrir: si no abre, no se entera, y si no se entera no vuelve.

   POR QUÉ LOCALES Y NO PUSH
   Push necesita certificado APNs, servidor de envío y una tabla de tokens de
   dispositivo — y sobre todo, necesita que alguien decida MANDAR cada mensaje.
   Los recordatorios que mueven la aguja acá no son eventos del servidor sino
   rutinas del cliente: entrenar, hacer el check del domingo, pesarse. Todo eso
   se puede programar en el propio teléfono, funciona sin conexión, no gasta
   infraestructura y no depende de que la app esté abierta.
   El push queda para lo que sí es un evento remoto ("Mati te dejó un
   comentario"); ver notas al pie.

   REGLA DE ORO DEL PRODUCTO
   Una notificación que no sirve se convierte en una notificación desactivada, y
   de ahí a app borrada hay un paso. Por eso: pocas, en horario humano, y todas
   apagables por separado.
   ============================================================= */
(function () {
  'use strict';

  const Cap = window.Capacitor;
  const isNative = !!(Cap && typeof Cap.isNativePlatform === 'function' && Cap.isNativePlatform());
  const LN = () => (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.LocalNotifications) || null;

  const K_PREFS  = 'mypump_notif_prefs';
  const K_PEDIDO = 'mypump_notif_pedido';   // ya se le mostró la hoja de permiso

  /* IDs fijos por recordatorio. Fijos y no aleatorios porque reprogramar tiene
     que PISAR lo anterior: con ids nuevos cada vez, el cliente terminaría con
     siete copias del mismo aviso. */
  const IDS = {
    entreno:  1001,
    check:    1002,
    peso:     1003,
    racha:    1004,
  };

  const DEFAULTS = {
    entreno: { on: true,  hora: 18, min: 0 },   // antes de la hora pico del gym
    check:   { on: true,  hora: 11, min: 0 },   // domingo a media mañana
    peso:    { on: false, hora: 8,  min: 0 },   // opt-in: pesarse a diario no le sirve a todos
    racha:   { on: true,  hora: 20, min: 30 },  // solo si el día viene vacío
  };

  function prefs() {
    try {
      const raw = JSON.parse(localStorage.getItem(K_PREFS) || '{}');
      const out = {};
      for (const k of Object.keys(DEFAULTS)) out[k] = Object.assign({}, DEFAULTS[k], raw[k] || {});
      return out;
    } catch (e) { return JSON.parse(JSON.stringify(DEFAULTS)); }
  }

  function guardarPrefs(p) {
    try { localStorage.setItem(K_PREFS, JSON.stringify(p)); } catch (e) {}
  }

  async function permisoEstado() {
    const ln = LN();
    if (!ln) return 'no_disponible';
    try {
      const r = await ln.checkPermissions();
      return (r && r.display) || 'prompt';
    } catch (e) { return 'prompt'; }
  }

  async function pedirPermiso() {
    const ln = LN();
    if (!ln) return false;
    try {
      const r = await ln.requestPermissions();
      try { localStorage.setItem(K_PEDIDO, '1'); } catch (e) {}
      return !!(r && r.display === 'granted');
    } catch (e) { return false; }
  }

  /* Los textos. Cortos, en la voz de Mati, y ninguno culpabiliza: "hoy te toca
     pierna" mueve; "no entrenaste" hace que la desactive. */
  const TEXTOS = {
    entreno: {
      title: 'Hoy toca entrenar 💪',
      body:  'Abrí MyPump y fijate qué te toca hoy.',
    },
    check: {
      title: 'Check de la semana',
      body:  'Contale a Mati cómo venís: 1 minuto y ya está.',
    },
    peso: {
      title: 'Pesate',
      body:  'En ayunas, después del baño. Cargalo en Mi Día.',
    },
    racha: {
      title: 'Te falta cerrar el día',
      body:  'Marcá lo que hiciste hoy para no perder la racha.',
    },
  };

  /* Programación. Todo repetitivo: iOS mantiene un máximo de 64 notificaciones
     pendientes por app, así que se usan schedules con `repeats` en vez de
     precalcular fechas — una entrada por recordatorio, no 30. */
  async function reprogramar() {
    const ln = LN();
    if (!ln || !isNative) return { ok: false, motivo: 'no_nativo' };
    if ((await permisoEstado()) !== 'granted') return { ok: false, motivo: 'sin_permiso' };

    const p = prefs();

    // Se cancela TODO lo nuestro antes de reprogramar: si el cliente apagó un
    // recordatorio, la entrada vieja tiene que desaparecer de verdad.
    try {
      const pend = await ln.getPending();
      const mios = ((pend && pend.notifications) || [])
        .filter(n => Object.values(IDS).indexOf(Number(n.id)) !== -1)
        .map(n => ({ id: Number(n.id) }));
      if (mios.length) await ln.cancel({ notifications: mios });
    } catch (e) { console.warn('[notif] cancel', e); }

    const lista = [];

    if (p.entreno.on) {
      lista.push({
        id: IDS.entreno,
        title: TEXTOS.entreno.title,
        body: TEXTOS.entreno.body,
        schedule: { on: { hour: p.entreno.hora, minute: p.entreno.min }, allowWhileIdle: true },
        extra: { destino: 'entreno' },
      });
    }

    if (p.check.on) {
      lista.push({
        id: IDS.check,
        title: TEXTOS.check.title,
        body: TEXTOS.check.body,
        // weekday 1 = domingo en iOS. El check se pide el domingo porque es
        // cuando el centinela arma la ronda: si llega el lunes, llega tarde.
        schedule: { on: { weekday: 1, hour: p.check.hora, minute: p.check.min }, allowWhileIdle: true },
        extra: { destino: 'revision' },
      });
    }

    if (p.peso.on) {
      lista.push({
        id: IDS.peso,
        title: TEXTOS.peso.title,
        body: TEXTOS.peso.body,
        schedule: { on: { hour: p.peso.hora, minute: p.peso.min }, allowWhileIdle: true },
        extra: { destino: 'myday' },
      });
    }

    if (p.racha.on) {
      lista.push({
        id: IDS.racha,
        title: TEXTOS.racha.title,
        body: TEXTOS.racha.body,
        schedule: { on: { hour: p.racha.hora, minute: p.racha.min }, allowWhileIdle: true },
        extra: { destino: 'myday' },
      });
    }

    if (!lista.length) return { ok: true, programadas: 0 };
    try {
      await ln.schedule({ notifications: lista });
      return { ok: true, programadas: lista.length };
    } catch (e) {
      console.warn('[notif] schedule', e);
      return { ok: false, motivo: 'error', detalle: String(e && e.message || e) };
    }
  }

  /* Activar: pide permiso y programa. Devuelve objeto (no booleano) por lo
     mismo que en HealthKit — hay que poder distinguir "denegó" para mandarlo
     a Ajustes, porque iOS no vuelve a mostrar la hoja. */
  async function activar() {
    if (!isNative) return { ok: false, motivo: 'no_nativo' };
    const est = await permisoEstado();
    if (est === 'denied') return { ok: false, motivo: 'denegado' };
    if (est !== 'granted') {
      const ok = await pedirPermiso();
      if (!ok) return { ok: false, motivo: 'denegado' };
    }
    const r = await reprogramar();
    return r.ok ? { ok: true, programadas: r.programadas } : r;
  }

  async function desactivarTodo() {
    const p = prefs();
    for (const k of Object.keys(p)) p[k].on = false;
    guardarPrefs(p);
    return await reprogramar();
  }

  async function setPref(clave, cambios) {
    const p = prefs();
    if (!p[clave]) return { ok: false };
    Object.assign(p[clave], cambios);
    guardarPrefs(p);
    // Si prendió algo y todavía no dio permiso, se lo pide ahora: es el momento
    // en que la intención está clara.
    if (cambios && cambios.on === true && (await permisoEstado()) !== 'granted') {
      return await activar();
    }
    return await reprogramar();
  }

  /* Cuando toca la notificación, abrir donde corresponde. Sin esto la
     notificación abre la app en la pantalla que estuviera y el cliente tiene
     que buscar solo qué era. */
  function cablearTaps() {
    const ln = LN();
    if (!ln || typeof ln.addListener !== 'function') return;
    ln.addListener('localNotificationActionPerformed', (ev) => {
      const dest = ev && ev.notification && ev.notification.extra && ev.notification.extra.destino;
      if (dest && typeof window.setScene === 'function') {
        try { window.setScene(dest); } catch (e) {}
      }
    });
  }

  async function estado() {
    return {
      nativo: isNative,
      disponible: !!LN(),
      permiso: await permisoEstado(),
      yaPedido: (function () { try { return localStorage.getItem(K_PEDIDO) === '1'; } catch (e) { return false; } })(),
      prefs: prefs(),
    };
  }

  // Al abrir: si ya tiene permiso, reprogramar. Las notificaciones repetitivas
  // de iOS sobreviven al reinicio, pero si el cliente cambió de teléfono o
  // reinstaló, esto las repone sin que tenga que tocar nada.
  if (isNative) {
    window.addEventListener('load', async () => {
      cablearTaps();
      if ((await permisoEstado()) === 'granted') reprogramar();
    });
  }

  window.MyPumpNotif = {
    estado,
    activar,
    desactivarTodo,
    setPref,
    prefs,
    reprogramar,
    TEXTOS,
  };

  /* PENDIENTE (push real, requiere infra que hoy no existe):
     para "Mati te dejó un comentario" o "tenés rutina nueva" hace falta
     @capacitor/push-notifications + una key APNs de Apple + tabla de tokens de
     dispositivo + envío desde la mini. Es la otra mitad del problema y no se
     resuelve del lado del cliente. */
})();
