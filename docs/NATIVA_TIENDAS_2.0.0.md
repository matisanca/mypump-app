# MyPump 2.0.0 (nativa): material para las tiendas (G7)

Borrador para cuando toque enviar. Nada de esto se manda sin el OK de Mati (compuerta G7).

## App Store: notas para el revisor (en inglés, como las de 1.0.x)

```
WHAT IS NEW IN 2.0.0

MyPump was rebuilt as a fully native iOS app (SwiftUI). Same features, same
account system and same data: existing users update and keep everything,
without logging in again.

HOW TO TEST WITHOUT AN ACCOUNT

MyPump has no signup: clients enter through a personal link their coach sends
them. For review, the app has a built-in demo.

1. Launch the app. On the welcome screen tap "Ver demo" ("See demo"). The app
   loads with sample data. No token, login or account is needed.
2. The five tabs are Entreno (training), Dieta (nutrition), Chat, Revisión
   (weekly check-in, progress photos, weight, daily habits) and Progreso.
3. In the demo, Chat and the photo-based features are disabled because they
   need a real client account.

HEALTH DATA (HealthKit)

MyPump only READS Health data (steps, sleep, resting heart rate, heart rate
variability, workouts and related types) to show the client and their coach
how they are recovering. It never writes to Health. The permission is asked
after a screen that explains why, and "Not now" skips it.

SCIENTIFIC SOURCES (Guideline 1.4.1)

Every number in Dieta (calorie and macro targets) has a "Ver fuentes" link
right next to it, and Entreno, Dieta and Mi Día end with "Respaldo científico
del plan". Both open the full list of sources (ISSN, NASEM, ACSM, WHO, NIH,
Argentine dietary guidelines) with links, plus a medical disclaimer.

THIRD-PARTY AI (Guideline 5.1.2(i))

Before the first chat message, the first photo analysis and the first weekly
check, the app asks for explicit permission to use third-party AI (OpenAI and
Anthropic) and explains what each one reads. If the user declines, no AI
processes their data: the coach answers the chat himself, photos are not
analyzed and the weekly review is prepared without AI. The choice can be
changed at any time in Revisión → Mis datos → Asistente de IA.

PRIVACY

Privacy policy and data deletion are available inside the app (Revisión →
Mis datos), and at https://app.mypumpteam.com/privacidad.html.
```

**Antes de enviar, revisar:**
- **D7 decidido (14-oct): permiso con un "no" real que cubre TODO** (chat, fotos y la ronda del domingo). Está hecho en la app y en el servidor, y espera que se aplique `nativa_002` y se desplieguen `chat_worker`, `sugerir_pendientes` y `centinela` en la Mini. **Falta (G3, web):** `privacidad.html` ya nombra a OpenAI y a Anthropic. Hay que sumarle el párrafo del permiso (propuesta 4 de `NATIVA_PROPUESTAS_WEB.md`).
- **Antecedentes de D7 (IA de terceros, 5.1.2(i)):** Apple pide decir con quién se comparten los datos (también una IA de terceros) y
  pedir permiso explícito antes. Lo que hay hoy (verificado en `origin/main` el 14-oct):
  - **Chat:** `pump-centinela/chat_worker.py` corre Codex (OpenAI, con la cuenta de ChatGPT de la Mini). Ve el hilo y
    un resumen del check de la semana, peso incluido. No ve las métricas de salud (HRV, sueño). Tiene dos modos:
    - **sombra:** deja un borrador que Mati manda, edita o descarta;
    - **automático** (`CHAT_IA_AUTO=1`): las respuestas "simples" salen solas, con demora humana.
  - **Foto del plato y etiqueta:** `mini-vision/server.mjs` manda la imagen a Codex (OpenAI) y devuelve los valores.
  - **Las opciones:**
    - **(a)** Consentimiento único antes del primer mensaje o de la primera foto, con un "no" que el servidor respete.
      Hace falta un campo en la base (G2) y que `chat_worker` saltee a quien no aceptó: lo contesta Mati a mano. La
      foto sin aceptar no se analiza. Es lo más seguro para la revisión: la app ~1 h, el servidor ~1 h.
    - **(b)** Pantalla informativa sin opción de decir que no. Más simple, pero no es el "permiso explícito" que pide
      la guía.
    - **(c)** Explicarlo solo en estas notas y arriesgar el rechazo. En modo sombra la respuesta la manda Mati, y eso
      ayuda a defenderlo.
- **iOS mínimo 17.** Hay que publicar antes la 1.0.12: es la última que van a poder instalar quienes tengan iOS 15 o 16.
- **Lanzamiento:** `release_type: MANUAL` con phased release de 7 días. Nunca con `cancel_previous_submissions`.

## App Store: "Novedades de esta versión" (es-419)

```
MyPump ahora es una app nativa de iPhone: más rápida, más fluida y con el modo oscuro de tu teléfono.

• Entreno: cargá tus series con un toque, con descanso integrado y avisos aunque salgas de la app.
• Dieta: reemplazá alimentos con equivalentes reales y mirá la porción con la mano.
• Revisión: check, fotos, peso y hábitos en un solo lugar.
• Funciona sin señal: lo que cargás se guarda y se sube solo.

Tu cuenta y tu historial siguen intactos: actualizá y seguí entrenando.
```

## Capturas

La interfaz cambió entera. Hay que sacar capturas nuevas de 6,9" y 13" con la cuenta visible de prueba, nunca de un
cliente: `scripts/capturas-tienda.mjs` es la referencia, adaptada al simulador. Las sube Mati.

## Etiqueta de privacidad

Igual que hoy (salud y fitness, fotos, contenido del usuario e identificador, ligados al cliente, sin tracking). Se
suma **"Other Diagnostic Data"** cuando exista el recibo de la migración, que es la compuerta G2.

## Google Play (cuando esté Android)

Lo mismo en castellano, más la declaración de Health Connect con los 13 permisos de lectura y el historial. Rollout por
porcentaje.
