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
    var params = new URLSearchParams(location.search);
    if (/cliente/.test(location.pathname) && params.get('t') === tok) return;
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
