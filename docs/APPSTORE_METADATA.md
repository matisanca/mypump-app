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

## Review notes (para que Apple pueda entrar)
```
RESOLUTION FOR GUIDELINE 1.4.1 - CITATIONS (build 1.0(3))

Health and nutrition recommendations now carry citations inside the app,
reachable in 3 taps with no account and no credentials.

EXACT PATH:
1. Launch the app. On the start screen, tap "Ver demo" ("See demo"). This loads
   the complete app populated with sample data - no token, login or account is
   needed. (Direct URL if preferred: https://app.mypumpteam.com/cliente?demo=1)
2. Tap the "Dieta" (Diet) tab, second icon in the bottom tab bar. A fully
   populated diet plan is shown.
3. In the calorie/macro card at the top, right under the targets, there is this
   line: "Objetivos calculados con Mifflin-St Jeor - macros segun ISSN y NASEM -
   Ver fuentes". Tap "Ver fuentes" ("See sources").
   Equivalent alternative: scroll to the bottom of the Diet screen and tap the
   row "Respaldo cientifico del plan" ("Scientific backing of the plan").
4. The sources screen opens. Citations are grouped by the specific claim they
   support: how calories are calculated, carbohydrates and fats, protein, food
   choice and portions, hydration, training intensity/volume/progression, and
   local (Argentine) dietary guidelines. Each entry shows the full reference,
   the full URL as selectable text, and an "Abrir fuente" ("Open source")
   button that opens the source. Sources include PubMed, NIH/NIDDK, National
   Academies (NASEM/IOM), WHO, ODPHP Dietary Guidelines for Americans, ISSN
   position stands (PMC), MedlinePlus and the Argentine Ministry of Health.
5. At the bottom of that same screen there is the notice stating the app is not
   a medical device, does not replace a healthcare professional, and that users
   should consult their physician before starting or changing the plan.

The same "Respaldo cientifico del plan" row is also at the bottom of the
"Entreno" (Training) and "Mi Dia" (My Day) tabs.

MyPump is not a regulated medical device: it does not diagnose, measure or
treat. It displays a training and nutrition plan authored by the user's coach,
who is a licensed physician, plus data the user enters manually.

Access model (unchanged): clients enter through a personal link sent by their
coach; there is no username/password signup. The demo mode above exists
specifically for review.

Apple Health is optional: Mi Dia -> "Conectar Apple Health". Health data is only
shown to the client and their coach; it is never shared or used for tracking.

Contact: Salomon Matias Sancari - info@mypumpteam.com
```
> ⚠️ Completar `<<<TOKEN_DEMO>>>` con el token de un **cliente demo** (ficticio,
> con rutina + dieta publicadas). Ver más abajo: hay que crearlo antes del submit.

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
