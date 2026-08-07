# MyPump — Metadata para Google Play Console (copiar/pegar)

> Todo listo para pegar en cuanto la cuenta de desarrollador esté verificada.
> Los límites de caracteres son los de Google, que **no** son los de Apple:
> el título va a 30, la descripción corta a 80 (Apple no tiene ese campo) y la
> larga a 4000.
>
> El texto está calcado del de la App Store (`APPSTORE_METADATA.md`) a
> propósito: es el mismo producto y no queremos dos versiones de la verdad. Lo
> que cambia está marcado y explicado.

## Datos base

| campo | valor |
|---|---|
| **Nombre de la app** (máx 30) | `MyPump` |
| **Nombre del desarrollador** (público) | `Pump Team` |
| **Package name** | `com.pumpteam.mypump` |
| **Categoría** | Salud y bienestar |
| **Etiquetas** | Fitness, Entrenamiento, Nutrición |
| **Idioma principal** | Español (Latinoamérica) |
| **Tipo** | Aplicación · Gratis |
| **Email de contacto** | `info@mypumpteam.com` |
| **Sitio web** | `https://mypumpteam.com` |
| **Política de privacidad** | `https://app.mypumpteam.com/privacidad` |

> **Gratis y no se puede cambiar después.** Google no deja pasar una app de
> pago a gratis ni al revés una vez publicada. MyPump es gratis: el cliente
> paga el asesoramiento, no la app. Igual que en iOS.

## Descripción corta (máx 80)

Campo que Apple no tiene. Es lo que se ve en el listado de búsqueda, debajo del
nombre, antes de que nadie abra la ficha.

```
Tu rutina, tu dieta y tu progreso de Pump Team, siempre a mano.
```

## Descripción completa (máx 4000)

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

SALUD Y RECUPERACIÓN
• Conectá Health Connect (opcional) y tus pasos, sueño y pulso se suman solos para que tu coach ajuste tu plan.
• Un número de recuperación del 0 al 100, calculado con tus propios datos: se compara con tu línea de base, no con un promedio ajeno.
• Funciona con lo que ya usás: Samsung Health, Mi Fitness, Fitbit y cualquier app que escriba en Health Connect.

MyPump es para clientes de Pump Team: accedés con el enlace personal que te manda tu coach.

RESPALDO Y AVISO
Las recomendaciones de nutrición y entrenamiento de MyPump se apoyan en fuentes públicas y revisadas por pares (Mifflin-St Jeor, NASEM/Institute of Medicine, International Society of Sports Nutrition, American College of Sports Medicine, OMS, MedlinePlus/NIH y las Guías Alimentarias para la Población Argentina). Las referencias completas, con sus enlaces, están dentro de la app: Dieta → "Respaldo científico del plan".

MyPump es una herramienta de seguimiento, pensada para personas sanas. No es un dispositivo médico y no reemplaza la consulta con un profesional de la salud: consultá a tu médico antes de empezar o de cambiar tu plan.
```

**Qué cambió respecto de iOS y por qué:** el bloque de SALUD dice Health
Connect en vez de Apple Salud, y suma dos líneas sobre el score de recuperación
y sobre qué apps funcionan. Lo segundo es deliberado: la duda número uno de un
cliente de Android va a ser *"¿anda con mi Samsung?"*.

## Gráficos que Google pide

Todo lo que hay que subir está en **`store/play/`**. Esa carpeta es hermana de
`public/`, no está adentro: Cloudflare Pages sirve `public/` y solo `public/`,
así que los assets de tienda quedan versionados sin quedar publicados.

| recurso | requisito | archivo |
|---|---|---|
| Ícono | 512×512, PNG 32 bits | `store/play/icon-512.png` ✅ |
| **Gráfico destacado** | **1024×500, PNG/JPG sin alfa** | `store/play/featured-graphic-1024x500.png` ✅ |
| Capturas de teléfono | mín 2, máx 8 · 16:9 o 9:16 · lado corto ≥320 px | reusar las 4 de iOS |
| Capturas de tablet | opcional | omitir |

**El gráfico destacado** es el banner de arriba de la ficha, es obligatorio y
Apple no lo pide, así que no había ninguno. Está hecho: fondo `#0a0a0a` con el
resplandor esmeralda de la marca, el ícono real de la app (no una copia), el
wordmark y la franja `#10b981 → #b8f060` abajo, que es el acento de
`tokens.css`. Sale de `featured-graphic.source.html`, que se rasteriza con
Chrome headless:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --force-device-scale-factor=1 --window-size=1024,500 \
  --default-background-color=0a0a0aff \
  --screenshot=store/play/featured-graphic-1024x500.png \
  "file://$PWD/store/play/featured-graphic.source.html"
```

> El `--force-device-scale-factor=1` no es opcional: en una Mac con pantalla
> Retina, sin eso Chrome saca 2048×1000 y Play lo rechaza por dimensiones.
> `--default-background-color` con los 8 dígitos deja el PNG **sin canal alfa**,
> que es como lo quiere Google.

---

# Data safety

El formulario más largo y el que más rebota. Las respuestas, decididas contra
lo que la app hace de verdad:

**¿La app recopila o comparte datos de usuario?** → **Sí, recopila. No comparte
con terceros.**

| Tipo de dato | ¿Se recopila? | Propósito | ¿Obligatorio? |
|---|---|---|---|
| Info de salud (pasos, sueño, pulso, HRV, peso) | Sí | Funcionalidad de la app | **Opcional** — el cliente puede no conectar Health Connect |
| Info de actividad física | Sí | Funcionalidad de la app | Opcional |
| Fotos | Sí | Funcionalidad de la app | Opcional (fotos de progreso) |
| ID de usuario | Sí | Funcionalidad de la app | Obligatorio (el token del enlace) |
| Otro contenido generado | Sí | Funcionalidad de la app | Obligatorio (cargas, comidas, check) |

**Prácticas de seguridad, las tres:**
- ✅ Los datos se cifran en tránsito (HTTPS a Supabase, sin excepciones).
- ✅ El usuario puede pedir que se borren sus datos → `info@mypumpteam.com`.
- ❌ **NO** marcar "los datos no se pueden borrar": sí se pueden.

**Lo que hay que responder NO, y es importante que sea NO de verdad:**
- ¿Se comparten con terceros? **No.** No hay analytics, no hay ad SDK, no hay
  nada. Se puede afirmar sin asterisco.
- ¿Se usan para publicidad o marketing? **No.**
- ¿Se usan para personalización fuera de la app? **No.**

> Si alguna vez se suma un SDK de analytics, esta declaración queda falsa y eso
> es una suspensión, no un rechazo. Cambiarla **antes** de agregarlo.

---

# Health apps declaration

Es la que decide si la app puede leer Health Connect. Hay que justificar los
**14 permisos** uno por uno, y el manifest está recortado para que sean
exactamente los que la app usa — ni uno de más. `check-android-permisos.mjs`
falla si el manifest y el bridge dejan de coincidir.

> Eran 17. Glucosa en sangre, temperatura corporal y mindfulness se cortaron a
> propósito **solo en Android**: aportan al componente "otros" del score, que
> vale 8 de 100, y `READ_BLOOD_GLUCOSE` en una app de coaching fitness es de lo
> que un revisor mira dos veces. En iOS se siguen leyendo. Ver `docs/ANDROID.md`.

**Justificación (sirve la misma para los 14):**

```
MyPump es una app de coaching personalizado 1 a 1. El cliente accede con un enlace privado que le envía su entrenador, quien ajusta su plan de entrenamiento y su nutrición semana a semana.

La app lee de Health Connect —siempre con permiso explícito y siempre de forma opcional— para calcular un puntaje diario de recuperación (0 a 100) que el cliente ve en la pantalla "Mi Día" y que su entrenador usa para decidir si aumentar la carga de entrenamiento o programar una semana de descarga.

USO DE CADA CATEGORÍA
• Pasos, distancia, pisos, calorías activas y basales, ejercicio: volumen de actividad diaria y gasto energético real, que determinan el objetivo calórico del plan.
• Frecuencia cardíaca, frecuencia cardíaca en reposo y variabilidad (HRV): son el componente autonómico del puntaje de recuperación, el de mayor peso.
• Sueño: duración, etapas y regularidad; segundo componente del puntaje.
• Frecuencia respiratoria y saturación de oxígeno: se comparan contra la línea de base del propio usuario para detectar desvíos.
• Peso, porcentaje de grasa: seguimiento de composición corporal contra el rango objetivo del plan.

COMPROMISOS
• SOLO LECTURA. La app no escribe ningún dato en Health Connect. Los permisos de escritura están explícitamente removidos del manifest.
• Los datos se muestran únicamente al propio cliente y a su entrenador asignado.
• No se venden, no se usan para publicidad, no se usan para construir perfiles y no se comparten con terceros. Ningún servicio de analítica los recibe.
• Se almacenan por cliente, aislados por un token individual: un cliente solo puede acceder a sus propios datos.
• El cliente puede revocar el permiso en cualquier momento desde Health Connect, y pedir el borrado de sus datos por email.
```

**Video de demostración:** Google suele pedirlo. Grabar la pantalla mostrando:
abrir la app → "Mi Día" → tocar "Conectar" → aparece la hoja de permisos de
Health Connect → aceptar → la tarjeta de Recuperación se llena. 30 segundos
alcanzan.

---

# Contenido de la app — el resto

| sección | respuesta |
|---|---|
| **Clasificación de contenido** | Cuestionario IARC. Todo "No". Queda apta para todo público. En iOS quedó 13+ por las menciones de salud; acá el cuestionario no pregunta lo mismo. |
| **Público objetivo** | 18+. **No** marcar que apunta a menores: activa Families Policy y triplica los requisitos. |
| **App de noticias** | No |
| **COVID-19** | No |
| **Datos financieros** | No |
| **Anuncios** | **No contiene anuncios** |
| **Acceso a la app** | ⚠️ **"Todas o algunas funciones tienen acceso restringido"** — hay que dar credenciales de prueba. Poner la URL del demo: `https://app.mypumpteam.com/cliente?demo=1`, con la instrucción "tocar Ver demo en la pantalla de inicio; no requiere usuario ni contraseña". Es exactamente lo que resolvió el rechazo 2.1 de Apple. |
| **Government apps** | No |

---

# El alta de la cuenta — las respuestas que no son datos personales

Queda acá porque si el alta se traba y hay que rehacerla, esto no se reescribe
de memoria.

| pantalla | campo | valor |
|---|---|---|
| Nombre del programador | nombre público | `Pump Team` |
| Tu organización | tamaño | 1 - 10 |
| Tu organización | sitio web | `https://mypumpteam.com` (**sin `www`** — el www da 522) |
| Perfil público | email del desarrollador | `info@mypumpteam.com` (no el de Gmail; el dominio recibe mail por Yandex) |
| Acerca de ti | otras cuentas de Google | lo contesta Mati: es una declaración sobre su historial |

**Acerca de ti — texto libre** (solo lo ve él, admite links de respaldo):

```
Soy el fundador de Pump Team, un servicio de asesoramiento personalizado de entrenamiento y nutrición. Desarrollé MyPump, la app que usan mis clientes para ver su rutina, su plan de comidas y su progreso.

MyPump ya está publicada en la App Store de Apple desde julio de 2026:
https://apps.apple.com/app/id6793259380

Es mi primera app en Android y no tengo experiencia previa con Play Console.

Detalles técnicos: la app está construida con Capacitor (una base web empaquetada como app nativa), con backend en Supabase y hosting en Cloudflare Pages. Los builds de iOS y Android se compilan y firman en Codemagic. El proyecto Android ya está generado y produce un Android App Bundle.

En Android la app se integra con Health Connect, solo con permisos de lectura y siempre opcionales, para calcular un puntaje diario de recuperación que el cliente ve en la app y que yo uso como su entrenador para ajustarle la carga de entrenamiento semana a semana.
```

---

# Orden de carga

1. Crear la app en Play Console (nombre, idioma, gratis).
2. **Ficha de Play Store** — todo lo de arriba + los gráficos.
3. **Contenido de la app** — Data safety, clasificación, público, acceso.
4. **Health apps declaration** — la justificación y el video.
5. Crear el **track interno** e invitar testers (tu mail alcanza).
6. `git tag a1.0.5 && git push origin a1.0.5` → Codemagic sube el AAB.
7. Con el AAB arriba: copiar el SHA-256 de **Integridad de la app** y pegarlo
   en `public/.well-known/assetlinks.json`. Sin eso el enlace del coach abre el
   navegador en lugar de la app, sin ningún aviso.
8. Probar en un Android real.
9. Promover de interno a producción.

> Los pasos 2, 3 y 4 se pueden hacer **antes** de que exista el primer AAB. El
> 7 no.
