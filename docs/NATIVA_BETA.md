# Beta externa de la 2.0.0 (compuertas G5 y G6)

Borrador del 14-oct. Nada de esto se manda ni se configura sin el OK de Mati. Él elige los 3-5 clientes, y Alan va
seguro.

## Cómo sería

- **Grupo externo nuevo en TestFlight**, "Beta 2.0.0", con **link público** (se manda por WhatsApp; no hace falta el
  mail de cada uno). El primer build externo pasa por la **revisión beta de Apple**, que suele tardar de unas horas a
  un día. Los siguientes builds del mismo número de versión casi nunca la necesitan.
- **Antes de abrirla:**
  - el TF-0 completo en el iPhone de Mati: ya entró sola y dejó el recibo; faltan el universal link, un push real y el
    aviso del domingo;
  - un build con lo arreglado después de la 101.
- **Durante (≥ 7 días):** todos los días miro recibos y conteos de cada beta en `mypump_migracion_nativa`, los
  dispositivos por `app_version` en `mypump_push_devices` y los fallidos. La palanca remota (`mypump_app_config`) pausa
  la migración sin publicar nada.
- **Volver atrás:** quien reinstala MyPump desde la App Store vuelve a la 1.0.x. Lo que hizo en la 2.0.0 ya está en el
  servidor, y la migración se repite sola si vuelve a la beta.

## Texto para TestFlight (Test Information)

**Beta App Description** (en inglés, la lee Apple):

```
MyPump 2.0.0 is the native rewrite (SwiftUI) of the MyPump coaching app. Clients
get their training plan, nutrition plan, weekly check-in, progress photos and
chat with their coach. This beta checks that existing users update from the
App Store version without logging in again and without losing data.
```

**Feedback email:** el de soporte de siempre (el mismo que la ficha de la tienda).

**What to Test** (en castellano, lo ven los testers):

```
Gracias por probar la nueva versión de MyPump.

Qué mirar
1. Que al abrirla entres sola a tu cuenta, sin pedirte el link.
2. Que veas tu rutina, tu dieta y tus datos de siempre.
3. Cargá series como siempre, y mandá el check de la semana.

Si algo no anda, mandale a Mati una captura por WhatsApp.
```

**Review notes de la beta:** las mismas de la tienda (`NATIVA_TIENDAS_2.0.0.md`), con la demo ("Ver demo") para entrar
sin cuenta.

## Mensaje para los clientes de la beta (G6, borrador)

Va en el estilo de los chats de Mati: sin dos puntos, sin guiones, sin emojis, en varios mensajes cortos.

1. `buenas! te quería pedir una mano, estamos por sacar la nueva versión de la app de MyPump y me gustaría que la pruebes vos antes que nadie`
2. `es la misma app pero hecha de nuevo, más rápida y más prolija. tus datos pasan solos, no tenés que volver a entrar con el link`
3. `para instalarla bajate TestFlight de la App Store, que es la app de Apple para probar versiones nuevas, y después abrí este link [LINK PÚBLICO]`
4. `cualquier cosa rara que veas mandame una captura por acá y lo vemos. si en algún momento querés volver a la de siempre, la reinstalás desde la App Store y listo`

Para Alan puede ir más técnico: que es SwiftUI nativo de punta a punta (y Kotlin en Android, más adelante), con la
migración del almacenamiento de la app anterior, y que la idea es que la pruebe como cliente.

## Lo que decide Mati

- Los 3-5 clientes. Mejor con iPhone y iOS 17 o más nuevo. Si puede ser, que uno use Apple Watch u otro reloj, y uno
  cargue fotos y check todas las semanas.
- Si el link va a todos juntos o de a uno.
- La fecha: conviene un lunes o un martes, para tener la semana entera.
