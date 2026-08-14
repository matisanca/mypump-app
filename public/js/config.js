/* =============================================================
   config.js — Credenciales de MyPump
   La SUPABASE_ANON_KEY es una clave pública por diseño (anon role,
   protegida por RLS). Es seguro commitear este archivo.
   Si en el futuro se agregan keys privadas, moverlas a env vars
   de Cloudflare Pages (nunca aquí).
   ============================================================= */

window.MYPUMP_CONFIG = {
  SUPABASE_URL:      'https://gydinputrtptqakdzyvc.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd5ZGlucHV0cnRwdHFha2R6eXZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxODk4NDgsImV4cCI6MjA5MTc2NTg0OH0.22TnFVwkRt2817RhmA1Vze8pgZSX-6I42PPTAEwb3Hk',
  // Servicio de visión (Codex en la Mini): escanear etiqueta / foto del plato.
  // Auth por token del cliente (validado contra Supabase); sin secretos acá.
  VISION_URL:        'https://vision.mypumpteam.com',
  // Base pública del sitio, para armar URLs que se abren FUERA del WebView
  // (el OAuth de los wearables). NO usar location.origin para eso: en la app
  // nativa vale `capacitor://localhost`, y una URL con ese esquema no la puede
  // abrir Safari — el cliente veía "no se puede conectar con el servidor".
  // Tiene que coincidir con OAUTH_REDIRECT_BASE de Cloudflare Pages.
  APP_URL:           'https://app.mypumpteam.com',

  // Clave PÚBLICA de VAPID para Web Push. Es pública de verdad: viaja al
  // navegador en cada suscripción y no sirve para mandar nada por sí sola —
  // la privada, que es la que firma, vive SOLO en la mini.
  //
  // Vacía = Web Push apagado. La app entera sigue funcionando igual: sin
  // clave, `suscribirWebPush()` devuelve null y no se registra ninguna
  // suscripción. Preferimos eso a un try/catch que registre suscripciones que
  // después nadie puede usar.
  //
  // Para generarlas, en la mini:
  //   node -e "const w=require('web-push');const k=w.generateVAPIDKeys();console.log(k.publicKey);console.log(k.privateKey)"
  // La primera línea va acá. La segunda va al .env de la mini como
  // VAPID_PRIVATE_KEY y NO se commitea nunca.
  VAPID_PUBLIC_KEY:  '',
};
