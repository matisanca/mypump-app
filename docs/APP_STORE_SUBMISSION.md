# MyPump — Checklist y metadata para App Store Connect

> Todo lo que hay que pegar/configurar en App Store Connect cuando se active la
> cuenta (Enrollment KN4AV357RA). Lo técnico de la app ya está listo (ver el
> final). Copiá cada bloque tal cual.

---

## 0. Estado técnico (ya resuelto en el repo)

- Bundle ID: `com.pumpteam.mypump` · Versión `1.0` · Build `1`
- Ícono 1024×1024 sin alfa ✓ · sin permisos faltantes ✓ (cámara, fototeca, Salud)
- `ITSAppUsesNonExemptEncryption = false` → **Export Compliance: NO** (usa solo HTTPS del sistema)
- Pipeline de build: `codemagic.yaml` (build + firma automática + TestFlight)
- **Modo demo para el revisor**: la app abre con `?demo=1` o el botón "Ver demo"
  en la pantalla de acceso — entra sin token, con datos de ejemplo, sin red.

---

## 1. App Information

| Campo | Valor |
|---|---|
| Name | **MyPump** |
| Subtitle | Entrenamiento y nutrición (máx 30 car.; "Tu plan de entrenamiento y nutrición" tiene 36 y NO entra) |
| Bundle ID | com.pumpteam.mypump |
| Primary Category | Health & Fitness |
| Secondary Category | (opcional) — Lifestyle |
| Content Rights | No usa contenido de terceros |
| Age Rating | 4+ (ver §6 — sin contenido sensible en la app del cliente) |

## 2. Privacy Policy URL

```
https://app.mypumpteam.com/privacidad
```
(ya publicada, en español, cubre datos de salud, sin tracking, base GDPR)

## 3. URLs

| Campo | Valor |
|---|---|
| Support URL | https://mypumpteam.com |
| Marketing URL | https://mypumpteam.com |

## 4. Descripción y keywords (español – ARG, idioma principal)

**Promotional text** (170 car., editable sin review):
```
Tu plan de Pump Team, siempre a mano: entrená guiado, registrá cargas, seguí tu dieta y mirá tu progreso semana a semana.
```

**Description**:
```
MyPump es la app con la que los clientes de Pump Team siguen su plan de entrenamiento y nutrición hecho a medida por su coach.

• Entrenamiento guiado: tu rutina de la semana con series, repeticiones y descanso. Registrá cada carga y confirmá tus series a medida que entrenás, con cronómetro de descanso y tu "última vez" en cada ejercicio.
• Nutrición: tu plan de comidas con macros y calorías. Marcá lo que comés, cambiá alimentos por equivalentes y sumá comidas libres.
• Mi Día: tus hábitos diarios (entrenamiento, descanso, agua) y —si querés— tus datos de actividad de Apple Salud.
• Revisión semanal: cargá tu peso, contá cómo venís en 4 toques y subí tus fotos de progreso, que solo ve tu coach.
• Progreso: la evolución de tu fuerza y tus cargas en el tiempo.

MyPump es para clientes activos de Pump Team: tu coach te da el acceso. ¿Querés verla por dentro? Tocá "Ver demo" en la pantalla de inicio.
```

**Keywords** (100 car., separadas por coma, sin espacios):
```
entrenamiento,gimnasio,rutina,fuerza,dieta,macros,fitness,nutricion,progreso,pesas,coach,musculacion
```

## 5. App Privacy — "Nutrition label" (Data Collection)

Respondé el cuestionario de privacidad así (coincide con la política publicada):

**¿Recopilás datos?** Sí.

| Tipo de dato | Se recopila | Linked to user | Usado para tracking | Propósito |
|---|---|---|---|---|
| **Health & Fitness** (entrenamientos, peso, actividad de Apple Salud) | Sí | Sí | **No** | App Functionality |
| **Photos** (fotos de progreso) | Sí | Sí | No | App Functionality |
| **User Content** (notas, hábitos, comentarios al coach) | Sí | Sí | No | App Functionality |
| **Identifiers** (token de acceso) | Sí | Sí | No | App Functionality |

- **Tracking: NO** en todos. La app no hace seguimiento entre apps ni publicidad.
- No se recopila: nombre real (opcional, lo carga el coach), email, contraseña,
  ubicación, datos de pago, contactos, historial de navegación.
- Los datos de Apple Salud se leen **solo con permiso explícito** y se usan
  exclusivamente para mostrar el progreso al cliente y su coach.

## 6. Age Rating

La **app del cliente (MyPump)** es una app de fitness estándar: entrenamiento,
dieta, hábitos, fotos de progreso. **No contiene** contenido médico, de
farmacología, ni recomendaciones de sustancias — eso vive del lado del coach,
fuera de esta app.

> **Cargado el 21-jul → rating = 9+** (no 4+). Todo el cuestionario en None/No,
> EXCEPTO **"Temas de salud o bienestar (health & wellness topics) = Sí"**,
> respondido con honestidad porque la app sí da recomendaciones de dieta y
> entrenamiento (estilo de vida). Eso solo, sube el cálculo a 9+ (Apple: 172
> países 9+, 12+ Vietnam, A10 Brasil). Es correcto y no bloquea nada.

## 7. App Review Information (⚠️ lo más importante para no ser rechazado)

La app usa acceso por enlace personal (sin usuario/contraseña), así que el
revisor **no puede crear una cuenta**. Por eso hay modo demo. En el campo
**Notes** pegá:

```
La app es para clientes de un servicio de coaching de fitness (Pump Team). El acceso normal es por un enlace personal que el coach le envía a cada cliente; no hay registro con usuario y contraseña dentro de la app.

Para revisar la app SIN necesidad de credenciales:
1. Abrí la app.
2. En la pantalla de inicio, tocá "Ver demo".
   (o abrí directamente https://app.mypumpteam.com/cliente?demo=1)
Eso carga la app completa con datos de ejemplo: entrenamiento, dieta, hábitos, revisión semanal y progreso. No requiere conexión a ninguna cuenta.

La app no vende nada ni tiene compras dentro. El contenido es un plan de entrenamiento y nutrición estándar; no hay contenido médico ni de otro tipo restringido.
```

- **Sign-In required?** No (gracias al modo demo).
- **Contact:** Salomón Matías Sancari · info@mypumpteam.com · +54 9 11 5482-2840

## 8. Screenshots (los tomás vos con el simulador o un iPhone)

Tamaños que pide Apple (subí al menos el de 6.7"):
- 6.7" (iPhone 15/16 Pro Max): 1290×2796
- 6.5" (opcional): 1242×2688

Pantallas recomendadas (todas se ven con `?demo=1`):
1. **Entreno** — la rutina del día con ejercicios.
2. **Un ejercicio abierto** — registrando series y cargas.
3. **Dieta** — plan de comidas con macros.
4. **Revisión** — check semanal + fotos.
5. **Progreso** — evolución de fuerza.

---

## 9. Lo que falta cuando la cuenta se active (orden)

1. **App Store Connect** → *My Apps* → **+** → New App: plataforma iOS, nombre
   MyPump, bundle `com.pumpteam.mypump`, idioma principal Español (ARG).
2. Copiá de acá: descripción, keywords, URLs, privacy label, age rating, review notes.
3. **App Information → Apple ID** (número que asigna Apple) → pegalo en
   `codemagic.yaml` (`APP_STORE_APPLE_ID`).
4. En Codemagic UI: subir la **App Store Connect API key** (App Store Connect →
   Users and Access → Integrations → generar key) y nombrarla `PumpTeam_ASC`.
5. Correr el build en Codemagic → sube a **TestFlight**.
6. Probar en TestFlight (con el modo demo y con un token real).
7. Subir screenshots + "Submit for Review".

> Como la app es **gratis y sin compras**, NO hace falta el acuerdo Paid Apps ni
> datos bancarios. Si en el futuro se cobra, ahí sí se completa con el EIN de la LLC.
