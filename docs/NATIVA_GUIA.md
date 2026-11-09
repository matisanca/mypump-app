# «Tu guía» en las apps nativas: informe

Se hizo la noche del 3 al 4 de noviembre de 2026. Lo coordinó la sesión MYPUMP PRO, con subagentes opus para iOS, Android, la revisión y la integración. La especificación es `~/pump-entregas/docs/ESPEC-APP-PUMP-TEAM.md`.

## Qué es
Es la página de videos previos a la videollamada (`pack.html`), ahora dentro de la app.

- **Dónde aparece:** solo si el cliente tiene una guía aprobada. Si no tiene, no se ve nada.
- **Tarjeta en Entreno:** muestra el avance, por ejemplo «4 de 13 videos, te quedan 7 min». La barra de pestañas no cambia.
- **Sección «Tu guía»:**
  - La cabecera.
  - El reproductor nativo: AVPlayer en iOS y Media3 en Android, con la placa de 2,6 s, Anterior y Siguiente, la velocidad 1 → 1,25 → 1,5, el paso solo al video siguiente y que retome donde quedó.
  - Los capítulos plegables.
  - El «para qué» de cada video, plegado.
  - Las dudas por video.
  - Las dudas para la videollamada, con tope de 30.
  - La suplementación por momento del día, con «Ver por qué», que abre el video debajo del suplemento.
  - Funciona sin red.
  - En iPad y tablet se ve a dos columnas.
- **Cómo se guarda:** el avance y las dudas van por la cola de la app, así no se pierden sin red. La web y la app escriben en las mismas tablas.

## Ramas
- `nativa-guia-ios` y `nativa-guia-and`: el trabajo de cada plataforma, que se unió en `nativa-guia`.
- `nativa-guia-202`: `nativa-guia` con la 2.1.0 de `nativa-202` mergeada adentro. Esta es la que pasa a `nativa-202` por fast-forward.

## Contrato con el servidor
Todo lo aplicó la sesión de entregas, que es la dueña de los RPC.
- `entregas_010`: get, avance, duda y duda para la llamada.
- `entregas_011`: `entregas_app_resumen`, para la tarjeta. Solo lee: no marca `abierto_en`.
- `entregas_012`: el resumen cuenta como la web. Saca los clips de «Tu suplementación» que nombra un suplemento. Las dos apps replican exactamente esa regla.
- `entregas_013`: `p_id` idempotente en las dudas, para que no se dupliquen cuando la cola reintenta.
- `entregas_app_get` se llama solo cuando el cliente abre la sección, nunca en segundo plano.

## Pruebas
- **Rama integrada (fbc6f94):**
  - contratos 59/59;
  - kit de iOS 791/791;
  - interfaz de iOS sin la guía: 50 pasan y 0 fallan;
  - EntrenoUITests 6/6;
  - Android: 816 tests sin fallas, 252 de interfaz sin fallas y las 19 de la guía.
- **Guía en iOS:** 65 tests propios y 4 de integración contra el cliente de prueba. XCUITest 7/7 en 17 Pro, SE y iPad antes del merge.
- **Guía en Android:** GuiaUiTest 12/12 y GuiaRealUiTest 7/7 en un teléfono chico con Android 9, un teléfono grande y una tablet.
- **Lado a lado con la web:** en Android coinciden lo visto, los tildes y las dudas. En iOS no se hizo, porque el sistema de permisos negó leer la clave de la web.
- **Revisión adversarial con opus:** 15 hallazgos en iOS y 12 en Android, todos arreglados. Entre ellos:
  - fugas del reproductor;
  - dudas que podían ir a otro video;
  - el video que volvía a sonar en segundo plano;
  - el giro de pantalla;
  - dudas perdidas o duplicadas.

## Capturas
- Maqueta: `~/Developer/nativa-evidencia/guia/maqueta/`, con `ios-*` y `and-*` en claro, oscuro y letra grande.
- Pruebas de punta a punta: `.../guia/e2e/`.
- Lado a lado: `.../guia/lado-a-lado/`.

## Después de la entrega y en la demo (4-nov, decisión de Mati)
- `entregas_014`: el resumen trae `fecha_entrega` y `mostrar_tarjeta` (null o hasta 48 h después de la entrega). Si el servidor no lo manda, la app hace el mismo cálculo.
- Pasado el plazo, la tarjeta sale de Entreno y queda la fila «Ver mi guía», primera en «Tu información» de Mis datos. «Quitar de Entreno» la saca antes; se guarda en el teléfono.
- Modo demo (revisión de Apple): con «Ver demo» se ve la guía con 8 videos genéricos de uso de la app (`apps/shared/demo/guia.json`), sin escribir en el servidor.
- Ramas: `nativa-guia-pe-ios` y `nativa-guia-pe-and`, mergeadas en `nativa-guia-202`.

## Decisiones de diseño que tomé, para que Mati las confirme
- La placa sale solo con Anterior, Siguiente o al terminar un video, como en la web. Tocar una fila arranca directo.
- «Ver por qué» abre un solo video a la vez. En la web pueden quedar varios abiertos.
- El recuadro de la web «Entrá a la app…» no va en la app. Lo confirmó la sesión de entregas.

## Pendientes conocidos, todos menores
- Si una duda idéntica a otra que está en la cola es rechazada, se puede ver doble en el teléfono hasta la próxima apertura. En la base queda una sola.
- En el chat de Android, el campo de texto tiene el mismo detalle de TalkBack que se arregló en la guía. Queda fuera de este trabajo.
- Las pruebas contra el servidor ensucian los clientes de prueba (vistos y dudas). La sesión de entregas los limpia cuando se le pide.
- Al revisor de Apple la guía solo le aparece si la cuenta demo tiene una aprobada. Lo decide Mati.

## «Lo que más te importa» (rama `nativa-guia-dolor`, para la 2.3.0)
- **Qué hace:** con `dolor` en `entregas_app_get`, arriba del reproductor va el recuadro del caso, sus partes «## Título» y los videos del bloque del mismo título, con la misma lógica que `pack.html`. Sin `dolor`, o con el texto en blanco, la guía es la de la 2.2.0.
- **Forma:** `"dolor": {"titulo": string|null, "texto": string}`. Reglas en `GuiaDolor.swift` y `GuiaDolor.kt`; casos compartidos en `apps/shared/fixtures/guia/dolor-casos.json`.
- **Introducción:** «Antes de nuestra videollamada del <fecha>, hacé estos dos pasos» (videos y dudas; el de entrar a la app no va). Solo con `dolor` y antes de la llamada. La fecha es `fecha_entrega` en hora de Argentina; si es null, va sin fecha.

## Versión
Sale dentro de la 2.1.0 unificada, junto con la 2.0.3, Salud, volumen, código de barras y el Apple Watch. La compila y la envía «MyPump Pro 2.0», con el OK de Mati.
