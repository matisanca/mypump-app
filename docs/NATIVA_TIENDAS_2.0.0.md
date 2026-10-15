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

Clients never talk to an AI: every message in Chat comes from the coach. The
coach uses AI tools from OpenAI and Anthropic, through their APIs, to draft
chat replies and his weekly review of each plan; anything beyond a simple
acknowledgment is approved by him before it is sent. What these tools receive
is de-identified: before any text leaves our server, a model that runs on our
own server removes the client's name, phone, email and ID numbers (the weekly
review uses a meaningless label such as "c1"), and the name is put back on our
server, never by the provider. Depending on the message, that text can include
the client's plan summary and logs. Progress photos are never sent. A meal or
nutrition-label photo is sent alone, with no other data, to estimate its
nutrition values, and it is deleted right after. All of this is described in
the privacy policy, available inside the app (Revisión → Mis datos).

PRIVACY

Privacy policy and data deletion are available inside the app (Revisión →
Mis datos), and at https://app.mypumpteam.com/privacidad.html.
```

**Antes de enviar, revisar:**
- **D7 se sacó el 14-oct (Mati): la IA no es algo que el cliente acepte.** En su lugar, a una IA de terceros llega todo
  desidentificado, sin nombre ni datos de contacto. Las notas de arriba lo dicen así desde el 15-oct: antes decían «No
  personal data reaches a third-party AI», que no era exacto (va contenido del plan y de los registros) y contradecía el
  renglón del informe semanal seudonimizado.
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

- **Las vigentes son del 15-oct a las 02:36**, con la app del TestFlight 104 (Mis datos sin IA ni recordatorios, la pista
  de la última vez como botón): `nativa-evidencia/tienda/20261015-023657`. Las del 14-oct quedaron viejas.
- `scripts/nativa/capturas-tienda-ios.sh` saca 20 capturas en los simuladores "Tienda 6,9" (iPhone 17 Pro Max, 1320×2868)
  y "Tienda 13" (iPad Pro 13" M5, 2064×2752), en claro y oscuro, con la barra a las 9:41 (con
  `APP=…/dd/mypump/Build/Products/Debug-iphonesimulator/MyPump.app`, la del último XCUITest).
  - Pantallas: Entreno, un ejercicio con 2 series, Dieta, Revisión con el check y Progreso con historial.
  - Datos: los bocetos, o sea la demo más las respuestas grabadas de la cuenta de prueba `test-nativa-real`. Nunca de
    un cliente.
  - `-captura YES` (solo DEBUG) saca el cartel "Estás viendo la demo".
  - La dieta de la demo ya no muestra el "−23 %" (f7aa713): eso también lo veía el revisor.
- Si cambia el diseño después de G1, se vuelven a sacar con el mismo script.

## Etiqueta de privacidad

Igual que hoy (salud y fitness, fotos, contenido del usuario e identificador, ligados al cliente, sin tracking). Se
suma **"Other Diagnostic Data"**: el recibo de la migración ya existe (`nativa_001` está aplicada). Son cuántas filas
hay por tabla y un UUID, sin contenido, ligado al cliente y sin tracking. Lo toca Mati en App Store Connect con el
envío (G7).

## Google Play

La 2.0.0 nativa sube como update de `com.pumpteam.mypump`.
- **El AAB.** Lo arma el workflow `android-nativa` de Codemagic (tag `nand-2.0.0-<versionCode>`, desde 101; la
  Capacitor publicada es el 18). Va firmado con `mypump-upload`, la misma clave de subida, y Play lo vuelve a firmar con
  la de la app.
- **La subida es manual:** no hay cuenta de servicio de Google Cloud.

### "Novedades de esta versión" (es-419, hasta 500 caracteres)

```
MyPump ahora es una app nativa de Android: más rápida, más fluida y con el modo oscuro de tu teléfono.

• Entreno: cargá tus series con un toque, con descanso integrado y aviso al terminar.
• Dieta: reemplazá alimentos con equivalentes reales y mirá la porción con la mano.
• Revisión: check, fotos, peso y hábitos en un solo lugar.
• Funciona sin señal: lo que cargás se guarda y se sube solo.

Tu cuenta y tu historial siguen intactos: actualizá y seguí entrenando.
```

### Lo que hay que tocar en la consola (Mati, o yo con su sesión y su OK)

1. **Data safety** (`docs/PLAYSTORE_METADATA.md` tiene lo de hoy). Hay que sumar lo que la tabla no lista:
   - **Información y rendimiento de la app → Diagnóstico.** Es el recibo de la migración: cuántas filas hay por tabla
     y un UUID, sin contenido.
   - **ID de dispositivo u otros.** Es el token de FCM de los avisos; la 1.0.12 ya lo mandaba.
   - **Mensajes → Otros mensajes en la app.** Es el chat con el coach.

   Los tres son de funcionalidad de la app y no se comparten: la IA del chat procesa por cuenta de MyPump, sin el nombre.
   Si alguno ya figuraba, se deja como está.
2. **Health apps declaration.** Pide los mismos 14 permisos que la 1.0.12 (13 de lectura y el historial), sin escritura
   ni segundo plano, así que no cambia. Pero su texto todavía menciona «saturación de oxígeno», que se sacó el 28-ago:
   hay que corregir ese renglón. Queda «Frecuencia respiratoria: se compara contra la línea de base del propio usuario
   para detectar desvíos».
3. **Capturas: listas** en `nativa-evidencia/tienda-android/20261015-034014`, 5 pantallas en claro y en oscuro:
   - teléfono en 1080×1920 y tablet de 10" en 1440×2560;
   - Play no acepta un lado mayor que el doble del otro, y la pantalla entera del teléfono (1080×2400) lo es;
   - salen con `scripts/nativa/capturas-tienda-android.sh` (`CapturasTiendaTest`, solo con `-e tienda 1`), con las
     respuestas grabadas de `test-nativa-real`, nunca de un cliente.

   Detalle menor: las claras muestran «3G» en la barra de estado y las oscuras no.
4. **Producción por porcentaje.** Primero 10 %, después 50 % y 100 %, mirando cada día los recibos de la migración y los
   fallidos (`scripts/nativa/beta_diario.py`). El porcentaje se puede frenar, pero no volver atrás.
5. **Permisos que la app NO pide**, por si Play pregunta: alarmas exactas, servicios en primer plano, leer salud en
   segundo plano y escritura de salud. Las notificaciones (Android 13+) se piden en la hoja de la primera vez.
