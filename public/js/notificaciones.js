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

    // Registrar el dispositivo para push APENAS se concede el permiso.
    //
    // Sin esto había un agujero que se comía avisos: el único registro vivía
    // en el listener de 'load', que corre cuando la app arranca — o sea ANTES
    // de que el cliente acepte, la primera vez. Entonces aceptaba, las locales
    // quedaban programadas, y el device NO se registraba hasta el próximo
    // arranque. Y mientras tanto `mypump_encolar_push` descarta lo que se
    // encole (no hay dispositivo activo), así que un comentario del coach en
    // esa ventana se perdía para siempre, en silencio.
    //
    // Va sin await a propósito: el registro depende de que APNs conteste y no
    // tiene por qué demorar el onboarding. Si falla, no rompe nada.
    activarPushSiCorresponde().catch(() => {});

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

  /* ── PUSH: los avisos que nacen del lado del coach ────────────────────
   *
   * Las locales de arriba las arma el teléfono solo y cubren lo previsible por
   * calendario. Esto cubre lo otro: "Mati te dejó un comentario", "tenés rutina
   * nueva" — lo que pasa cuando el cliente no está mirando la app.
   *
   * El registro es deliberadamente silencioso: si falla, la app sigue igual y
   * el cliente ni se entera. Push es un extra; que se caiga no puede romper
   * nada de lo que ya funciona.
   */
  const K_PUSH_TOKEN = 'mypump_push_token';

  function PUSH() {
    const Cap = window.Capacitor;
    const P = Cap && Cap.Plugins;
    if (!P || !P.PushNotifications) return null;

    /* En Android, APAGADO A PROPÓSITO. No es prudencia: push en Android hoy no
     * podría funcionar aunque no crasheara.
     *
     * Lo que pasa si se deja prendido: el proyecto no tiene
     * android/app/google-services.json, así que el plugin de Gradle nunca se
     * aplica (build.gradle:51 se traga la ausencia en un try/catch y el build
     * sale VERDE) y en el teléfono no existe el recurso google_app_id. Entonces
     * PushNotifications.register() levanta "Default FirebaseApp is not
     * initialized" en el hilo principal y se lleva puesto el proceso: la app se
     * cierra sola, sin diálogo, sin mensaje. En Android 8-12 apenas abre con el
     * link del coach; en 13+ en el momento en que el cliente acepta las
     * notificaciones, y desde ahí en cada arranque.
     *
     * Y aun con Firebase configurado no serviría todavía: push.py manda por
     * APNs. FCM es un envío distinto que del lado del servidor no está escrito.
     *
     * Las notificaciones LOCALES (las de arriba) sí andan en Android: las arma
     * el teléfono solo y no dependen de nada de esto.
     *
     * Para prenderlo: crear el proyecto Firebase con package com.pumpteam.mypump,
     * commitear google-services.json, sumar el envío FCM en push.py, y sacar
     * estas tres líneas. */
    if (typeof Cap.getPlatform === 'function' && Cap.getPlatform() === 'android') return null;

    return P.PushNotifications;
  }

  function tokenAcceso() {
    if (window.TOKEN) return window.TOKEN;
    try { return localStorage.getItem('mypump_token') || ''; } catch (e) { return ''; }
  }

  async function registrarPush() {
    const P = PUSH();
    if (!P || !tokenAcceso()) return { ok: false, motivo: 'no_disponible' };

    return new Promise((resolve) => {
      let listo = false;
      // Si APNs no contesta, no dejamos la promesa colgada para siempre.
      const cortar = setTimeout(() => {
        if (!listo) { listo = true; resolve({ ok: false, motivo: 'timeout' }); }
      }, 15000);

      P.addListener('registration', async (t) => {
        if (listo) return;
        listo = true; clearTimeout(cortar);
        const dev = t && t.value;
        try {
          // Se recuerda el último token enviado para no repetir la RPC en cada
          // arranque: APNs devuelve el mismo salvo reinstalación o restore.
          const previo = localStorage.getItem(K_PUSH_TOKEN);
          if (dev && dev !== previo && window.mypumpDB && window.mypumpDB.registrarPush) {
            const r = await window.mypumpDB.registrarPush(tokenAcceso(), dev);
            if (r && r.success) localStorage.setItem(K_PUSH_TOKEN, dev);
          }
        } catch (e) { console.warn('[push] registrar:', e); }
        resolve({ ok: true });
      });

      P.addListener('registrationError', (e) => {
        if (listo) return;
        listo = true; clearTimeout(cortar);
        console.warn('[push] registrationError:', e);
        resolve({ ok: false, motivo: 'error_apns' });
      });

      P.register().catch((e) => {
        if (listo) return;
        listo = true; clearTimeout(cortar);
        resolve({ ok: false, motivo: String((e && e.message) || e) });
      });
    });
  }

  // Tocar la notificación tiene que llevar a donde dice, no solo abrir la app.
  function cablearTapsPush() {
    const P = PUSH();
    if (!P) return;
    P.addListener('pushNotificationActionPerformed', (ev) => {
      const d = ev && ev.notification && ev.notification.data;
      const destino = d && d.destino;
      if (destino && typeof window.setScene === 'function') {
        try { window.setScene(destino); } catch (e) {}
      }
    });
  }

  /* Se engancha al permiso que YA se pide para las locales: iOS usa el mismo
   * permiso para ambas, así que pedirlo aparte sería pedirle al cliente lo
   * mismo dos veces. */
  async function activarPushSiCorresponde() {
    if ((await permisoEstado()) !== 'granted') return { ok: false, motivo: 'sin_permiso' };
    cablearTapsPush();
    return registrarPush();
  }

  window.MyPumpNotif = {
    estado,
    activar,
    desactivarTodo,
    setPref,
    prefs,
    reprogramar,
    registrarPush: activarPushSiCorresponde,
    TEXTOS,
  };

  // Al arrancar con permiso ya dado, re-registrar: el device token de APNs
  // puede cambiar (restore de backup, reinstalación) y si no lo actualizamos
  // el push deja de llegar sin ningún error visible en ningún lado.
  if (window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()) {
    window.addEventListener('load', () => { activarPushSiCorresponde().catch(() => {}); });
  }
})();
