# Beta externa de la 2.0.0 (compuertas G5 y G6)

Borrador del 14-oct, actualizado esa noche. Nada de esto se manda ni se configura sin el OK de Mati. Él elige los 3 a 5
clientes; Alan va seguro.

## Cómo sería

- **Grupo externo nuevo en TestFlight**, «Beta 2.0.0», con **link público**: se manda por WhatsApp y no hace falta el
  mail de cada uno.
  - El primer build externo pasa por la **revisión beta de Apple**, que suele tardar de unas horas a un día.
  - Los siguientes builds con el mismo número de versión casi nunca la necesitan.
- **Antes de abrirla:**
  - El TF-0 en el iPhone de Mati:
    - entró sola y dejó el recibo ✓;
    - un push real lo aceptó APNs el 14-oct a las 18:34, y falta que Mati confirme que lo vio;
    - el aviso del domingo, visto en lo que agenda el simulador, y en su iPhone se ve el domingo 18-oct a las 11:00;
    - falta el universal link en su iPhone.
  - Un build con lo arreglado después de la 101: el **103**, del 14-oct, con la pista de la última vez, sin el permiso
    de IA y con el aviso del domingo como mensaje de Mati.
- **Durante (≥ 7 días):** todos los días, `python3 scripts/nativa/beta_diario.py`.
  - Por cliente da el teléfono (versión, push), el último recibo de la migración y las sustituciones en el servidor.
  - Cualquier ⚠️ (una tabla que bajó, algo trabado en la cola o en fallidos, fotos sin subir) se mira ese mismo día.
  - La palanca remota (`mypump_app_config`) pausa la migración sin publicar nada.
  - Lo que reporten se arregla y sale en otro build `nios-2.0.0-<n>` al mismo grupo. **Mientras la 1.0.12 esté en
    revisión, nadie tagea `v*`.**
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

**Feedback email:** el de soporte de siempre, el mismo que la ficha de la tienda.

**What to Test** (en castellano, lo ven los testers):

```
Gracias por probar la nueva versión de MyPump.

Qué mirar
1. Que al abrirla entres sola a tu cuenta, sin pedirte el link.
2. Que veas tu rutina, tu dieta y tus datos de siempre.
3. Cargá series como siempre, y mandá el check de la semana.

Si algo no anda, mandale a Mati una captura por WhatsApp.
```

**Review notes de la beta:** las mismas de la tienda (`NATIVA_TIENDAS_2.0.0.md`), con la demo («Ver demo») para entrar
sin cuenta. Hay que sumar lo de la IA, porque desde el 14-oct no hay pantalla de permiso:

```
Chat replies are prepared by the coach with AI tools; anything beyond a simple
acknowledgment is approved by him before it is sent. Before any message leaves
our own server, a local model removes
the client's name and contact details; the name is put back on our server.
```

## Mensaje para los clientes de la beta (G6, borrador)

Lo manda la sesión de Mensajes con el OK de Mati. Va en el estilo de sus chats: sin dos puntos, sin guiones, sin
emojis, en varios mensajes cortos.

1. `buenas! te quería pedir una mano, estamos por sacar la nueva versión de la app de MyPump y me gustaría que la pruebes vos antes que nadie`
2. `es la misma app pero hecha de nuevo, más rápida y más prolija. tus datos pasan solos, no tenés que volver a entrar con el link`
3. `para instalarla bajate TestFlight de la App Store, que es la app de Apple para probar versiones nuevas, y después abrí este link [LINK PÚBLICO]`
4. `cualquier cosa rara que veas mandame una captura por acá y lo vemos. si en algún momento querés volver a la de siempre, la reinstalás desde la App Store y listo`

Si pregunta si es obligatorio: `para nada, si no te copa seguís con la de siempre`.

Para Alan puede ir más técnico:
- es SwiftUI nativo de punta a punta, y Kotlin en Android más adelante;
- trae la migración del almacenamiento de la app anterior;
- la idea es que la pruebe como cliente.

## Lo que decide Mati

- **Los 3 a 5 clientes.** Mejor con iPhone y iOS 17 o más nuevo. Si se puede:
  - uno con Apple Watch u otro reloj;
  - uno que cargue fotos y check todas las semanas;
  - uno que use el chat de la app, que desde el 14-oct contesta la sesión de Mensajes sin ver el nombre.
- **El envío del link:** a todos juntos o de a uno.
- **La fecha:** conviene un lunes o un martes, para tener la semana entera.
