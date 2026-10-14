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

## Qué mirar si algo falla

- El informe de la migración queda en el teléfono (Ajustes de la app → diagnóstico) y en la base. El recibo con conteos
  necesita la RPC nueva, que es la compuerta G2 y te la pido aparte.
- Se puede volver atrás: reinstalar la 1.0.12 desde la App Store. La migración se repite sola al volver a la 2.0.0, sin
  duplicar.
