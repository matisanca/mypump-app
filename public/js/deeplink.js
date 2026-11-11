/* =============================================================
   deeplink.js — el link de acceso abre la app, no el navegador.

   Sin esto, un Universal Link levanta la app pero el WebView carga el bundle
   local (index.html) sin el ?t=… : el cliente ve la landing y queda igual de
   afuera que antes. Capacitor entrega la URL real por dos vías distintas y hay
   que escuchar las dos:
     · appUrlOpen  → la app ya estaba abierta en segundo plano.
     · getLaunchUrl → arranque en frío; el evento ya pasó cuando corre este JS.

   Solo actúa si la URL trae un token válido. Es no-op en la web (ahí el ?t=
   llega en la URL de verdad y lo resuelve el script de cada página).
   ============================================================= */
(function () {
  var TOKEN_KEY = 'mypump_token';
  var TOKEN_RE  = /^[a-zA-Z0-9_-]{16,64}$/;

  // Lo que pega el cliente: el link entero, a medias, adentro del mensaje o el token solo. Le saca lo que agrega el copiar y
  // pegar (marcas invisibles de WhatsApp, puntuación de la frase), como FormatoToken.extraer de las apps.
  var INVISIBLES = (function () {
    try { return new RegExp('\\p{Cf}', 'gu'); } catch (e) { return /[\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]/g; }
  })();
  var BORDES = /^[\s\u0085.,;:!()\[\]{}<>"'«»“”‘’]+|[\s\u0085.,;:!()\[\]{}<>"'«»“”‘’]+$/g;
  function extraerToken(texto) {
    var t = String(texto == null ? '' : texto).replace(INVISIBLES, '').replace(BORDES, '');
    if (!t) return null;
    if (TOKEN_RE.test(t)) return t;
    try {
      var q = new URL(/^http/.test(t) ? t : 'https://' + t).searchParams.get('t');
      if (q && TOKEN_RE.test(q)) return q;
    } catch (e) {}
    // Sin omitir el tramo vacío: «…/?TOKEN» no es un link.
    var ultimo = t.split('/').filter(Boolean).pop();
    ultimo = ultimo ? ultimo.split('?')[0] : '';
    if (TOKEN_RE.test(ultimo)) return ultimo;
    // El mensaje entero de WhatsApp, con un espacio o un salto alrededor del t= (nunca adentro del token).
    var m = t.match(/[?&]\s*t\s*=\s*([a-zA-Z0-9_-]{16,64})/);
    if (m) return m[1];
    m = t.match(/\/acceso\/([a-zA-Z0-9_-]{16,64})/);
    return m ? m[1] : null;
  }
  window.MyPumpLink = { extraerToken: extraerToken };

  function tokenDe(url) {
    if (!url) return null;
    try {
      var t = new URL(url).searchParams.get('t');
      return t && TOKEN_RE.test(t) ? t : null;
    } catch (e) { return null; }
  }

  function entrar(tok) {
    if (!tok) return;
    // Ya estamos adentro con ese mismo token → no recargar (evita el loop si
    // iOS reentrega la URL al volver del background).
    // Desde la auditoría del 10/11 (F21) la web saca el ?t= de la dirección apenas lo guarda: «ya adentro» también es tenerlo
    // guardado. Sin esto, cada apertura volvía a cargar la página con el link de arranque, para siempre.
    var params = new URLSearchParams(location.search);
    var guardado = null; try { guardado = localStorage.getItem(TOKEN_KEY); } catch (e) {}
    if (/cliente/.test(location.pathname) && (params.get('t') === tok || guardado === tok)) return;
    try { localStorage.setItem(TOKEN_KEY, tok); } catch (e) {}
    location.replace('/cliente.html?t=' + encodeURIComponent(tok));
  }

  var C = window.Capacitor;
  var App = C && C.Plugins && C.Plugins.App;
  if (!App) return;                       // web o plugin ausente → nada que hacer

  try { App.addListener('appUrlOpen', function (ev) { entrar(tokenDe(ev && ev.url)); }); } catch (e) {}
  if (typeof App.getLaunchUrl === 'function') {
    App.getLaunchUrl().then(function (r) { entrar(tokenDe(r && r.url)); }).catch(function () {});
  }
})();
