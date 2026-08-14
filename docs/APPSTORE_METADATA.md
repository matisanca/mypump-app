# MyPump — Metadata para App Store Connect (copiar/pegar)

> **✅ Publicada el 27-jul-2026 — 1.0 (3)** · https://apps.apple.com/app/id6793259380
> Lo de acá abajo es lo que quedó cargado en la ficha (más el histórico de qué se
> corrigió en cada envío). Ver `APP_STORE_SUBMISSION.md` para el resumen.

> Todo en español rioplatense. Los límites de caracteres son los de Apple.
> Cuando crees la app en App Store Connect, pegás cada campo acá.

## Datos base
- **Nombre de la app** (máx 30): `MyPump`
- **Subtítulo** (máx 30): `Tu plan de Pump Team`
- **Bundle ID:** `com.pumpteam.mypump`
- **Categoría primaria:** Salud y forma física (Health & Fitness)
- **Categoría secundaria:** Estilo de vida (opcional)
- **Idioma principal:** Español (México) o Español (España) — cualquiera sirve.

## Texto promocional (máx 170, se puede cambiar sin re-review)
```
Tu rutina, tu dieta y tu progreso en un solo lugar. Lo que tu coach de Pump Team arma para vos, siempre a mano.
```

## Descripción (máx 4000)
```
MyPump es la app de tus asesoramientos con Pump Team. Todo lo que tu coach arma para vos, en tu teléfono y siempre actualizado.

ENTRENAMIENTO
• Tu rutina del día, ejercicio por ejercicio, con series, repes y descansos.
• Registrá tus cargas en un toque y mirá tu progreso real en cada ejercicio.
• Timer de descanso, sustitución de ejercicios y comentarios directos con tu coach.

NUTRICIÓN
• Tu plan de comidas con opciones para elegir.
• Medidas caseras para cada alimento (la "manito"): cuánto es una palma, un puño, una taza — sin balanza.
• Sustituí alimentos manteniendo tus macros y marcá qué comiste.

TU DÍA
• Seguí tus hábitos: entrenamiento, comidas, sueño, agua y cardio.
• Racha de constancia y adherencia de los últimos 30 días.

SALUD
• Conectá Apple Salud (opcional) y tus pasos y actividad se suman solos para que tu coach ajuste tu plan.

MyPump es para clientes de Pump Team: accedés con el enlace personal que te manda tu coach.

RESPALDO Y AVISO
Las recomendaciones de nutrición y entrenamiento de MyPump se apoyan en fuentes públicas y revisadas por pares (Mifflin-St Jeor, NASEM/Institute of Medicine, International Society of Sports Nutrition, American College of Sports Medicine, OMS, MedlinePlus/NIH y las Guías Alimentarias para la Población Argentina). Las referencias completas, con sus enlaces, están dentro de la app: Dieta → "Respaldo científico del plan".

MyPump es una herramienta de seguimiento, pensada para personas sanas. No es un dispositivo médico y no reemplaza la consulta con un profesional de la salud: consultá a tu médico antes de empezar o de cambiar tu plan.
```

## Keywords (máx 100 caracteres, separadas por coma, sin espacios)
```
entrenamiento,gimnasio,dieta,macros,rutina,fitness,nutricion,progreso,coach,pump,musculacion,habitos
```

## URLs
- **Support URL:** `https://app.mypumpteam.com` (o una página de contacto).
- **Marketing URL** (opcional): `https://mypumpteam.com`
- **Privacy Policy URL:** `https://app.mypumpteam.com/privacidad`  ← ya publicada.

## Clasificación por edades y dispositivo médico (build 1.0(3), 26-jul-2026)
En el cuestionario de clasificación por edades, paso 3 "Medicina o bienestar":
- **Información médica o sobre tratamientos = Poco frecuente** (antes: Ninguna).
  Es lo honesto: Apple rechazó la 1.0(2) diciendo que la app da "health or medical
  recommendations". → Apple recalcula la clasificación a **13+** (antes 9+).
- **Temas de salud o bienestar = Sí** (sin cambios).

En Información de la app → **Dispositivos médicos regulados**: declarado **No**
("no es un dispositivo médico regulado en ningún país ni región"). Obligatorio por
estar en la categoría "Salud y forma física".

## App Privacy (Nutrition labels) — cómo declararlo
En App Store Connect → App Privacy, declarar:
- **Health & Fitness** → *Data Linked to You*, propósito "App Functionality".
  **NOT** Used for Tracking. **NOT** used for Third-Party Advertising.
- **Identifiers** (el token de acceso) → *Data Linked to You*, "App Functionality".
- **Fitness/Usage** (series, hábitos) → *Data Linked to You*, "App Functionality".
- Marcar que **no** se usa ningún dato para *tracking*.

## Review notes — 1.0.6 (build 10)

> Reemplazan a las de 1.0(3). Aquéllas mandaban al revisor a la pestaña "Mi Día",
> que en esta versión dejó de existir: sus contenidos se movieron adentro de
> "Revisión" y su lugar en la barra lo tomó "Chat". Unas review notes que
> describen una pantalla que no está es un rechazo por 2.1 servido en bandeja.

```
WHAT IS NEW IN 1.0.6

1. In-app chat between the client and their coach ("Chat" tab).
2. The bottom tab bar changed: "Mi Dia" (My Day) was removed as a tab and its
   content now lives at the bottom of the "Revision" tab. "Chat" took its place.
3. Web Push notifications, in addition to the existing APNs ones.

HOW TO TEST WITHOUT AN ACCOUNT

MyPump has no signup: clients enter through a personal link their coach sends
them. For review, the app has a built-in demo.

1. Launch the app. On the start screen, tap "Ver demo" ("See demo"). The full
   app loads with sample data - no token, login or account needed.
   (Direct URL if preferred: https://app.mypumpteam.com/cliente?demo=1)
2. Tap "Chat", the third icon in the bottom tab bar. The conversation screen
   opens with its composer.
3. "Revision" (fourth icon) now contains the weekly check, progress photos,
   body weight AND the daily habits that used to live in "Mi Dia".

ABOUT AUTOMATED REPLIES IN THE CHAT — please read

Some replies in the chat are drafted automatically and reviewed before sending.
We are declaring this explicitly rather than leaving it implicit:

- Automated replies are strictly limited to acknowledgements: confirming that a
  message arrived, thanking the client, or letting them know their coach will
  answer. They are one or two sentences.
- They NEVER contain training, nutrition, supplementation or health guidance -
  not even generic advice. This is enforced by a deterministic filter that runs
  before anything is sent: it blocks any numeric quantity paired with a unit
  (grams, calories, sets, reps, hours), a domain blocklist, and any text that
  looks like guidance. Blocked messages are not rewritten or retried - they are
  escalated to the human coach.
- Anything that is a question, a request for a change, or mentions a symptom is
  escalated to the coach and receives no automated reply at all.
- Messages suggesting a medical emergency (chest pain, fainting, acute injury)
  receive NO automated reply whatsoever; the coach is alerted immediately.
- The coach can turn automation off globally or per client at any time.
- Chat messages are processed by a third-party AI provider. This is disclosed in
  the privacy policy at https://app.mypumpteam.com/privacidad.html

MyPump is not a regulated medical device: it does not diagnose, measure or
treat. It displays a training and nutrition plan authored by the user's coach,
who is a licensed physician, plus data the user enters manually.

Health and nutrition recommendations still carry citations, reachable in 3 taps
with no account: demo -> "Dieta" tab -> "Ver fuentes" in the macro card at the
top, or "Respaldo cientifico del plan" at the bottom of the screen. Sources
include PubMed, NIH/NIDDK, NASEM/IOM, WHO, ODPHP, ISSN position stands,
MedlinePlus and the Argentine Ministry of Health. The same screen carries the
notice that the app is not a medical device and does not replace a healthcare
professional.

Apple Health is optional: "Revision" tab -> "Conectar Apple Health". Health data
is shown only to the client and their coach; it is never shared or used for
tracking.

Contact: Salomon Matias Sancari - info@mypumpteam.com
```

## Screenshots (necesarios para el submit)
Tamaños: 6.7" (iPhone 15/16 Pro Max) y 6.1". Capturas sugeridas (4-5):
1. Entreno — un día con ejercicios.
2. Dieta — una comida con medidas caseras (la "manito").
3. Mi Día — hábitos + racha (+ card de Salud si hay datos).
4. Progreso — sparkline de un ejercicio con 🏆 PR.
> Se sacan corriendo la app en el simulador/iPhone (o desde TestFlight). Se hacen
> cuando ya tengamos build.

---

## Pendiente antes del submit: CLIENTE DEMO para Apple
Apple necesita entrar a la app. Como el acceso es por token, hay que darles uno.
Opción simple: desde el Cerebro, publicá un **cliente ficticio** ("Demo Apple")
con una rutina y una dieta de ejemplo, y usá ESE token en las review notes.
(Si preferís, puedo prepararte el SQL para crear el cliente demo directo en
Supabase — avisame.)
