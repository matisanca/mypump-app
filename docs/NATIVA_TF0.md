# Hito TF-0: la nativa encima de la app de la tienda, en tu iPhone

Es la prueba que no se puede hacer en el simulador: la actualización real desde MyPump de la App Store a la 2.0.0 nativa
por TestFlight, con tu iPhone, tu firma y el push de verdad. Dura unos 15 minutos.

## Lo que tenés que hacer antes (solo vos)

1. **Aceptar el contrato nuevo del Apple Developer Program** en <https://developer.apple.com/account> (aparece un aviso
   arriba). Sin eso Apple no deja subir builds a TestFlight. Tampoco puede salir la 1.0.12.
2. **Publicar la 1.0.12 antes que la 2.0.0.** La 2.0.0 pide iOS 17. Quien tenga iOS 15 o 16 se queda en la última que
   pueda instalar, y tiene que ser la 1.0.12, que trae el arreglo del push.
3. Avisarme que está aceptado. Yo disparo el build `nios-2.0.0-100` en Codemagic: sube a TestFlight solo para los
   testers internos, sin revisión de Apple.

## En tu iPhone

1. Tené MyPump de la App Store abierta con la **cuenta de prueba** (te paso el link aparte, por WhatsApp). Que tenga
   cargado algo de hoy: una serie, un hábito, el peso.
2. **Modo avión** y cargá dos cosas más: una serie y un vaso de agua. Quedan en la cola vieja, sin subir.
3. Instalá TestFlight y la 2.0.0 encima. Es una actualización: no borres la app.
4. Abrí la 2.0.0 todavía **en modo avión**. Tiene que:
   - entrar sola a la cuenta, sin pedir el link;
   - mostrar el plan (la copia guardada) con el aviso de "sin conexión".
5. Sacá el modo avión. En unos segundos:
   - la serie y el vaso de agua que cargaste sin señal aparecen en el panel de Mati (Cerebro), **una sola vez**;
   - Dieta, Revisión y Progreso muestran lo mismo que la web.
6. Tocá un link de acceso `app.mypumpteam.com/?t=…` en WhatsApp: tiene que abrir la app, no Safari.
7. Desde el Cerebro, dejale un comentario a la cuenta de prueba: tiene que llegar el push. Al tocarlo se abre la
   pestaña que corresponde.
8. Domingo a las 11: tiene que llegar "Tu revisión de la semana" **una sola vez**. Si llegan dos, quedó agendada la
   vieja.

## Cero pérdida (con la G2 aplicada)

Con `nativa_001` en la base, la 2.0.0 deja un recibo por corrida en `mypump_migracion_nativa`. Trae lo que leyó del
almacenamiento viejo, a dónde fue cada cosa y las filas del cliente en el servidor antes y después de mandar lo pendiente
(`servidorAntes` / `servidorDespues`). Yo lo leo desde la Mini con `_q.py`. La cuenta tiene que cerrar: las filas de
después son las de antes más lo que estaba en la cola. Sin la G2 aplicada, el recibo queda en el teléfono y se manda
solo el día que exista la RPC.

## Qué mirar si algo falla

- El informe de la migración está en **Mis datos → Informe de la actualización**, al pie, junto a la versión. Aparece
  solo en un teléfono que vino de la app vieja. No tiene tokens ni contenido, y se comparte con el botón de arriba.
- Si la migración hace algo raro en muchos teléfonos, la palanca remota (`mypump_app_config`, G2) pausa las ops
  viejas y la escritura de vuelta sin publicar otra versión.
- Se puede volver atrás: reinstalar la 1.0.12 desde la App Store. La migración se repite sola al volver a la 2.0.0, sin
  duplicar.

## Resultado (14-oct-2026)

- **Con la 2.0.0 (100): falló.** En el iPhone WebKit guarda en `Library/WebKit/WebsiteData`, no en
  `Library/WebKit/<bundle>/WebsiteData` como el simulador. La app no encontró nada y pidió el link. No se perdió nada:
  la Fase L no escribe ni borra si no encuentra el almacenamiento.
- **Con la 2.0.0 (101): OK.** Entró sola, recibo confirmado con los conteos iguales, escritura de vuelta confirmada en
  el arranque siguiente, push registrado sin duplicar. Detalle en la bitácora de `NATIVA_ESTADO.md`.
- **Apple Salud desde el iPhone real:** a las 17:25 UTC la 101 ya había escrito 22 filas de `mypump_salud_diaria`
  (pasos, distancia y pisos, los 7 días). Son los mismos tipos que mandaba la Capacitor: la cuenta de Mati nunca tuvo
  sueño, pulso ni variabilidad, porque no usa reloj.
- **Universal link:** en el simulador no se puede probar. El build local va firmado con `FAKETEAMID`, y el AASA del
  sitio habilita solo `7H22AXLUS4.com.pumpteam.mypump`, así que el link abre Safari. Queda para el iPhone: tocar el
  link de acceso en WhatsApp.
- **Herramientas que sirvieron:** `xcrun devicectl device info files` / `device copy from --domain-type
  appDataContainer` leen el contenedor de una app de TestFlight. `log collect` de un iPhone pide root. La
  invitación interna se acepta con el código de canje que muestra la página de Apple en la Mac, sin tocar el link
  del mail.

