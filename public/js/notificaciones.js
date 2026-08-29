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
  const K_PUSH_WEB = 'mypump_push_web_endpoint';   // último endpoint web registrado

  /* IDs fijos por recordatorio. Fijos y no aleatorios porque reprogramar tiene
     que PISAR lo anterior: con ids nuevos cada vez, el cliente terminaría con
     siete copias del mismo aviso. */
  /* UN SOLO recordatorio, a propósito.
   *
   * Antes eran cuatro (entrenar, check, pesarse, cerrar el día). Cuatro avisos
   * por semana de una app de coaching es ruido, y el que se vuelve ruido lo
   * primero que recibe es un "desactivar todas" — y ahí se pierde también el
   * único que importa. Queda la revisión sola para que cuando suene, el cliente
   * sepa que es eso. */
  const IDS = {
    check: 1002,
  };

  /* Los tres que se eliminaron ya están AGENDADOS en el sistema operativo de
   * todo cliente que abrió la app antes de este cambio. Sacar el código no los
   * cancela: los seguiría recibiendo para siempre. Hay que pedirle al sistema
   * que los borre, una vez, por id. */
  const IDS_ELIMINADOS = [1001, 1003, 1004];   // entreno, peso, racha

  const DEFAULTS = {
    check: { on: true, hora: 11, min: 0 },   // domingo a media mañana
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
    check: {
      title: 'Tu revisión de la semana',
      body:  'Contale a Mati cómo venís: 1 minuto y ya está.',
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
      // Los propios Y los eliminados: un cliente que instaló antes del cambio
      // tiene los tres viejos agendados en el sistema y nadie más los va a
      // borrar.
      const aBorrar = Object.values(IDS).concat(IDS_ELIMINADOS);
      const mios = ((pend && pend.notifications) || [])
        .filter(n => aBorrar.indexOf(Number(n.id)) !== -1)
        .map(n => ({ id: Number(n.id) }));
      if (mios.length) await ln.cancel({ notifications: mios });
    } catch (e) { console.warn('[notif] cancel', e); }

    const lista = [];

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

    /* En Android el push depende de que el BINARIO traiga Firebase.
     *
     * Si el APK no tiene google-services.json, PushNotifications.register()
     * levanta "Default FirebaseApp is not initialized" EN EL HILO NATIVO y se
     * lleva puesto el proceso: la app se cierra sola, sin diálogo. Un try/catch
     * de JS no lo atrapa. En Android 8-12 pasa apenas abre con el link del
     * coach; en 13+ cuando el cliente acepta las notificaciones, y desde ahí en
     * cada arranque.
     *
     * Antes esto era `if (android) return null` a secas, y tenía el problema
     * opuesto: el día que Firebase existiera, había que ACORDARSE de sacarlo.
     * Ahora lo decide el build — `fcm-flag.js` se reescribe con true si y solo
     * si google-services.json estaba presente al compilar. Sin acordarse de
     * nada, y sin poder crashear.
     *
     * Las notificaciones LOCALES sí andan igual en Android: las arma el
     * teléfono y no dependen de nada de esto. */
    const esAndroid = typeof Cap.getPlatform === 'function' && Cap.getPlatform() === 'android';
    if (esAndroid && !window.MYPUMP_FCM) return null;

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
            // La plataforma REAL. Antes no se pasaba y la RPC usa 'ios' por
            // defecto: todo device entraba como iOS, así que el día que entre
            // un Android por FCM el sender lo mandaría por APNs y fallaría con
            // un BadDeviceToken que no explica nada.
            const plat = (window.Capacitor && window.Capacitor.getPlatform && window.Capacitor.getPlatform()) || 'ios';
            const r = await window.mypumpDB.registrarPush(tokenAcceso(), dev, plat);
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
  /* ── WEB PUSH ────────────────────────────────────────────────────────────
   *
   * Es el camino que cubre a los 62. Hoy `mypump_push_devices` está vacía
   * porque el plugin nativo solo existe adentro de la app, y todos abren MyPump
   * como un link del navegador. Web Push funciona ahí — con una condición que
   * no se puede saltear: en iOS SOLO anda si la app está agregada a la pantalla
   * de inicio. Safari no deja suscribirse desde una pestaña común. Por eso el
   * pop-up de descarga y esto son la misma pelea.
   *
   * Devuelve null (y no lanza) en todos los casos en que no corresponde: sin
   * clave configurada, sin service worker, sin permiso, o navegador viejo.
   */
  async function suscribirWebPush() {
    try {
      const cfg = window.MYPUMP_CONFIG || {};
      const clave = cfg.VAPID_PUBLIC_KEY;
      // Sin clave pública, Web Push está apagado a propósito. Se sale en
      // silencio: no es un error, es una feature sin configurar.
      if (!clave) return null;
      if (!('serviceWorker' in navigator) || !('PushManager' in window)) return null;
      if (!tokenAcceso() || !window.mypumpDB || !window.mypumpDB.registrarPushWeb) return null;
      if (Notification.permission !== 'granted') return null;

      const reg = await navigator.serviceWorker.ready;

      // Reusar la suscripción existente. Cada `subscribe` nuevo invalida el
      // anterior, así que llamarlo en cada arranque dejaría la tabla llena de
      // endpoints muertos que el sender intenta y falla.
      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          // Obligatorio en Chrome: sin esto, subscribe() rechaza. Y es honesto
          // — un push silencioso que no muestra nada es justamente lo que
          // hace que la gente revoque el permiso.
          userVisibleOnly: true,
          applicationServerKey: _b64UrlABytes(clave),
        });
      }

      const j = sub.toJSON();
      if (!j || !j.endpoint || !j.keys) return null;

      const previo = localStorage.getItem(K_PUSH_WEB);
      if (j.endpoint === previo) return { ok: true, yaEstaba: true };

      const r = await window.mypumpDB.registrarPushWeb(tokenAcceso(), j.endpoint, j.keys.p256dh, j.keys.auth);
      if (r && r.success && r.data) { try { localStorage.setItem(K_PUSH_WEB, j.endpoint); } catch (e) {} }
      return { ok: !!(r && r.success) };
    } catch (e) {
      console.warn('[push-web]', e);
      return null;
    }
  }

  // La clave VAPID viaja en base64url y `applicationServerKey` pide bytes.
  // Sin la conversión, subscribe() tira un InvalidCharacterError que no dice
  // ni una palabra sobre la clave.
  function _b64UrlABytes(s) {
    const pad = '='.repeat((4 - (s.length % 4)) % 4);
    const b64 = (s + pad).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(b64);
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  async function activarPushSiCorresponde() {
    if ((await permisoEstado()) !== 'granted') return { ok: false, motivo: 'sin_permiso' };
    cablearTapsPush();
    // Nativo y web no compiten: adentro de la app corre APNs y `PUSH()` existe;
    // en el navegador `PUSH()` devuelve null y queda Web Push. Se intentan los
    // dos porque preguntar "¿cuál soy?" acá duplicaría la lógica de plataforma
    // que ya vive en cada uno.
    const [nativo] = await Promise.all([registrarPush(), suscribirWebPush()]);
    return nativo;
  }

  window.MyPumpNotif = {
    estado,
    activar,
    desactivarTodo,
    setPref,
    prefs,
    reprogramar,
    registrarPush: activarPushSiCorresponde,
    suscribirWebPush,
    TEXTOS,
  };

  // Al arrancar con permiso ya dado, re-registrar: el device token de APNs
  // puede cambiar (restore de backup, reinstalación) y si no lo actualizamos
  // el push deja de llegar sin ningún error visible en ningún lado.
  //
  // Ahora corre TAMBIÉN en el navegador, que es donde están los 62. Antes la
  // guarda de Capacitor lo dejaba fuera y por eso `mypump_push_devices` estaba
  // vacía: el único registro que existía vivía detrás de una condición que en
  // la web nunca se cumple.
  window.addEventListener('load', () => { activarPushSiCorresponde().catch(() => {}); });
})();
