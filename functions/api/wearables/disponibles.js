/* =============================================================
   functions/api/wearables/disponibles.js — qué proveedores están vivos HOY

   POR QUÉ EXISTE
   La app mostraba la sección "Mi reloj" con botones Conectar para Oura y
   WHOOP siempre, aunque las credenciales OAuth de esos proveedores no
   estuvieran cargadas. El cliente tocaba Conectar y le aparecía "Todavía no
   está habilitado": una función muerta en producción. Apple rechaza eso por
   la guideline 2.1 (ya rechazó esta app una vez por un botón que no hacía
   nada).

   La alternativa obvia — una constante en config.js — obliga a un build de
   iOS nuevo el día que Mati cargue las credenciales. Esto no: el HTML ya
   embebido pregunta, y la respuesta cambia sola en cuanto aparecen las env
   vars en Cloudflare.

   No expone secretos: solo dice si existen, nunca su valor. Sin auth a
   propósito — la respuesta es idéntica para todo el mundo y no depende del
   cliente.
   ============================================================= */
import { PROVEEDORES } from './_lib.js';

export async function onRequestGet({ env }) {
  const proveedores = Object.entries(PROVEEDORES)
    .filter(([, p]) => env[p.idEnv] && env[p.secretEnv])
    // OAUTH_ENC_KEY guarda los refresh tokens cifrados. Sin ella el callback
    // muere DESPUÉS de que el cliente ya autorizó en el sitio del proveedor,
    // que es el peor momento posible para fallar.
    .filter(() => !!env.OAUTH_ENC_KEY)
    .map(([id, p]) => ({ id, nombre: p.nombre }));

  return new Response(JSON.stringify({ proveedores }), {
    headers: {
      'content-type': 'application/json',
      // Corto a propósito: el día que se carguen las credenciales, la app
      // tiene que enterarse sin esperar un cache largo.
      'cache-control': 'public, max-age=300',
    },
  });
}
