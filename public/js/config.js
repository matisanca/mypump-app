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
};
