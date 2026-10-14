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

No personal data reaches a third-party AI. Chat replies are prepared by the
coach with AI tools (OpenAI and Anthropic); anything beyond a simple
acknowledgment is approved by him before it is sent. Before a conversation leaves our own server, a model that runs on that
server removes the client's name, phone, email and ID numbers; the name is put
back on our server, never by the provider. A meal or label photo is sent alone,
without the user's name or any other data, to estimate its nutrition values,
and it is deleted right after. The weekly report sent to Anthropic is
pseudonymized. All of this is described in the privacy policy, available inside
the app (Revisión → Mis datos).

PRIVACY

Privacy policy and data deletion are available inside the app (Revisión →
Mis datos), and at https://app.mypumpteam.com/privacidad.html.
```

**Antes de enviar, revisar:**
- **D7 se sacó el 14-oct (Mati): la IA no es algo que el cliente acepte.** En su lugar, nada identificable llega a una IA
  de terceros:
  - el chat va sin nombre ni datos de contacto, los tapa la IA local de la Mini (`pump-centinela/deid_chat.py`), tanto
    a Codex (borradores, `CHAT_IA_AUTO=0`) como a la sesión de Mensajes (`app_chat.py`, aprobación de Mati);
  - la foto del plato o de la etiqueta va sola, sin datos de la persona;
  - el informe semanal a Anthropic va seudonimizado.
  La política de privacidad lo dice así desde e171038 (publicada el 14-oct). **Riesgo que queda:** Apple podría pedir
  igual un permiso en la app. Si lo pide, la tabla `mypump_consentimiento_ia` (nativa_002) sigue en la base y la
  pantalla está en la historia de git (antes de 678c5a8).
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

La interfaz cambió entera, así que van capturas nuevas de 6,9" y 13", nunca de un cliente. Las sube Mati.

- **Listas desde el 14-oct:** `scripts/nativa/capturas-tienda-ios.sh` saca 20 capturas en los simuladores "Tienda 6,9"
  (iPhone 17 Pro Max, 1320×2868) y "Tienda 13" (iPad Pro 13" M5, 2064×2752), en claro y oscuro, con la barra a las
  9:41. Están en `nativa-evidencia/tienda/20261014-145803`.
  - Pantallas: Entreno, un ejercicio con 2 series, Dieta, Revisión con el check y Progreso con historial.
  - Datos: los bocetos, o sea la demo más las respuestas grabadas de la cuenta de prueba `test-nativa-real`. Nunca de
    un cliente.
  - `-captura YES` (solo DEBUG) saca el cartel "Estás viendo la demo".
  - La dieta de la demo ya no muestra el "−23 %" (f7aa713): eso también lo veía el revisor.
- Si cambia el diseño después de G1, se vuelven a sacar con el mismo script.

## Etiqueta de privacidad

Igual que hoy (salud y fitness, fotos, contenido del usuario e identificador, ligados al cliente, sin tracking). Se
suma **"Other Diagnostic Data"** cuando exista el recibo de la migración, que es la compuerta G2.

## Google Play (cuando esté Android)

Lo mismo en castellano, más la declaración de Health Connect con los 13 permisos de lectura y el historial. Rollout por
porcentaje.
