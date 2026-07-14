# MyPump — Metadata para App Store Connect (copiar/pegar)

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
```

## Keywords (máx 100 caracteres, separadas por coma, sin espacios)
```
entrenamiento,gimnasio,dieta,macros,rutina,fitness,nutricion,progreso,coach,pump,musculacion,habitos
```

## URLs
- **Support URL:** `https://app.mypumpteam.com` (o una página de contacto).
- **Marketing URL** (opcional): `https://mypumpteam.com`
- **Privacy Policy URL:** `https://app.mypumpteam.com/privacidad`  ← ya publicada.

## App Privacy (Nutrition labels) — cómo declararlo
En App Store Connect → App Privacy, declarar:
- **Health & Fitness** → *Data Linked to You*, propósito "App Functionality".
  **NOT** Used for Tracking. **NOT** used for Third-Party Advertising.
- **Identifiers** (el token de acceso) → *Data Linked to You*, "App Functionality".
- **Fitness/Usage** (series, hábitos) → *Data Linked to You*, "App Functionality".
- Marcar que **no** se usa ningún dato para *tracking*.

## Review notes (para que Apple pueda entrar)
```
La app es para clientes de Pump Team; se accede con un enlace personal con token
(no hay registro con email/contraseña). Cuenta demo para revisión:

  https://app.mypumpteam.com/cliente?t=<<<TOKEN_DEMO>>>

Apple Health es opcional: en Mi Día → "Conectar Apple Health". Los datos de salud
solo se muestran al cliente y a su coach; no se comparten ni se usan para tracking.
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
