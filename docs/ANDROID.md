# MyPump en Android — Health Connect y Google Play

El 25% de los clientes usa Android. Este documento es cómo llega la app ahí y
qué falta para publicarla.

## Lo que ya está hecho

| | estado |
|---|---|
| Bridge multiplataforma (iOS + Android) | ✅ commit `48d8354` |
| Proyecto Android (`android/`) | ✅ commit `3e5c4ba` |
| Manifest recortado a 17 permisos de lectura | ✅ |
| Workflow de Codemagic (`android-play`) | ✅ |
| Banco de pruebas con modo Android | ✅ |
| Ficha de tienda redactada | ✅ `docs/PLAYSTORE_METADATA.md` |
| Gráficos de tienda (ícono + destacado 1024×500) | ✅ `store/play/` |
| Cuenta de Google Play | 🔄 alta en curso — **la terminás vos** |
| Keystore de subida | ❌ falta |
| SHA-256 en `assetlinks.json` | ❌ falta (sale del primer AAB) |

## De dónde salen los datos

**No es Google Fit.** Sus APIs se apagan a fin de 2026 y no aceptan altas
nuevas desde mayo de 2024. El reemplazo es **Health Connect**, que en Android
14+ viene en el sistema y en Android 9-13 es una app aparte de la Play Store.

Health Connect es un agregador: no mide nada, guarda lo que le escriben Samsung
Health, Mi Fitness, Fitbit, Garmin y compañía.

**Lo bueno:** su HRV es `HeartRateVariabilityRmssdRecord` — **rMSSD**.
HealthKit solo tiene SDNN. El motor de recuperación le da más peso al rMSSD (45
vs 40) porque el SDNN del Apple Watch se muestrea en momentos aleatorios y
tiene ~29% de error. **En Android el score sale más confiable que en iPhone.**

**Lo malo, y hay que saberlo antes de prometerlo:** Samsung Health **no
escribe** frecuencia cardíaca en reposo, HRV ni frecuencia respiratoria a
Health Connect — solo las lee. El usuario ve el dato en Samsung Health y la app
lee vacío. Sueño y pasos sí llegan. O sea que para un cliente con Galaxy Watch
el score puede quedar en `insuficiente` igual que un iPhone sin reloj. La card
ya explica eso honestamente (`renderMydayRecuperacion`).

## Los tres bugs que había, y por qué no se veían

Ninguno daba error. Los tres daban datos malos en silencio.

**1. Dos tipos que Android no conoce.** `exerciseTime` y
`appleSleepingWristTemperature` no están en el enum de Kotlin. El plugin valida
**todos** los tipos antes de tocar el sistema, así que uno desconocido tira el
pedido de permisos **entero**: el cliente conecta, la app dice que sincronizó,
y no llega nada. Es el mismo bug que `vo2Max` nos hizo en iOS. Van marcados
`soloIOS` y `check-healthkit-tipos.mjs` valida contra los dos enums.

**2. `basalCalories` era un factor 4x.** En iOS son muestras de energía y
sumarlas está bien. En Android el plugin devuelve
`BasalMetabolicRateRecord.inKilocaloriesPerDay` — una **tasa**, el mismo ~1.800
repetido en cada lectura. Sumarlo daba 7.200 kcal de metabolismo basal, y ese
número entra a `mypump_get_gasto_real` como "TDEE medido". Override
`comoAndroid: 'mediana'`.

**3. La fuente estaba hardcodeada.** Todo se grababa como `apple_health`,
incluso desde un Samsung. Y el `CHECK` de la tabla no conocía `health_connect`,
así que las filas se descartaban **una por una, en silencio**
(`_mypump_upsert_salud` hace `CONTINUE WHEN check_violation`). Migración 056.

## ⛔ El único bloqueante que queda del lado de la base

**La migración 056 NO está aplicada.** Verificado contra
`docs/ESQUEMA_PRODUCCION.txt`: el CHECK vigente de `mypump_salud_diaria.fuente`
acepta siete valores y `health_connect` no es ninguno.

Mientras siga así, un cliente de Android conecta Health Connect, la app le dice
que sincronizó, y **no se guarda una sola fila**. No hay error, ni log, ni fila
parcial: el `CONTINUE WHEN check_violation` las descarta de a una.

Por eso `npm test` está **en rojo a propósito**:
`check-fuentes-salud.mjs` cruza toda `fuente` que el código puede escribir
contra la lista blanca real de producción, y falla mientras falte una. Si el
workflow de Codemagic corre los tests, el AAB tampoco sale — que es lo que se
busca: no publicar en Play una app cuyos datos la base descarta.

Se destraba en dos pasos:

1. Aplicar `supabase/migrations/056_fuente_health_connect.sql` en el editor SQL.
2. Regenerar el volcado, o el chequeo sigue rojo aunque ya esté arreglado:

```bash
ssh mini "~/agentkit-coach/venv/bin/python3 ~/esquema.py" > docs/ESQUEMA_PRODUCCION.txt
```

> La 056 agrega el CHECK de `mypump_entrenos_health` como **`NOT VALID`** a
> propósito. Esa tabla hoy no tiene ningún CHECK, así que ahí no hay nada roto;
> y un `ADD CONSTRAINT` normal valida las filas existentes, de modo que una sola
> fila con una fuente rara abortaría la transacción entera — llevándose puesto
> el arreglo de `mypump_salud_diaria`, que es el que importa.

## Probarlo desde la Mac, sin un Android

```bash
npm run dev
open "http://localhost:8790/cliente?demo=1&mockhealth=1&mockplataforma=android&mockescenario=normal&mockreset=1"
```

> **Usá `/cliente`, sin `.html`.** El servidor de desarrollo (`npx serve`) hace
> un 301 de `/cliente.html` a `/cliente` y **se come el query string**. En
> producción (Cloudflare Pages) no pasa.

El mock se hace pasar por Health Connect y **rechaza los dos tipos prohibidos
igual que el sistema real**, así que si alguien los reintroduce se ve acá y no
en el teléfono de un cliente.

Verificado el 7-ago-2026: 17 tipos pedidos, 0 prohibidos, 517 filas todas con
`fuente: health_connect`, HRV como `rmssd`.

Los tests automáticos:

```bash
node scripts/test-bridge-android.mjs      # 8 tests del bridge como Android
node scripts/check-android-permisos.mjs   # manifest ↔ bridge
npm test                                  # todo
```

## Los permisos: por qué son exactamente 17

El plugin declara **43** en su manifest: 22 de lectura y **21 de escritura**,
o sea todo lo que sabe hacer, lo use la app o no. El manifest merger los suma
solos.

MyPump **solo lee**. Y Google hace justificar **cada permiso, uno por uno**, en
la *Health apps declaration* de Play Console — uno declarado sin uso es una
pregunta sin buena respuesta. Los 26 que sobran se sacan con
`tools:node="remove"`.

`check-android-permisos.mjs` cuida los dos modos de falla, que son silenciosos
de maneras opuestas:

- **pedir un permiso no declarado** → `SecurityException`, y no se ve ni en el
  build ni en los tests: se ve en el teléfono del cliente, la primera vez que
  toca "Conectar".
- **declarar uno que no se usa** → se lo tenés que justificar a Google.

El paso de Codemagic además inspecciona el manifest **mergeado** —el que queda
adentro del AAB— porque el fuente puede estar limpio y el merger igual dejar
pasar algo.

## Lo que falta, en orden

### 1. Cuenta de Google Play — te toca a vos

- **US$25, pago único** (no anual como Apple).
- **Cuenta de ORGANIZACIÓN**, no personal. Google la exige para apps de salud,
  y además es lo que te salva de los **12 testers × 14 días** que le imponen a
  las cuentas personales creadas después del 13-nov-2023.
- **D-U-N-S**: el mismo de PUMP TEAM LLC que usaste en Apple sirve tal cual.
- ⚠️ **La app tiene que NACER en esa cuenta.** El único modo de falla
  documentado es "nació personal → se migró a organización → la consola sigue
  pidiendo los 14 días y soporte no lo destraba".
- ⚠️ Cargá los datos con cuidado la primera vez: hay muchos reportes de gente
  que pagó, quedó trabada, y Google no reembolsa.

**Los valores que van en el alta** (los que no son datos personales tuyos):

| campo | valor |
|---|---|
| Nombre del programador (público) | `Pump Team` |
| Tamaño de la organización | 1 - 10 |
| Sitio web de la organización | `https://mypumpteam.com` — **sin `www`** |

> El `www` **no anda**: `www.mypumpteam.com` devuelve 522 y el apex 200. Google
> te va a hacer verificar la propiedad de ese dominio antes de publicar, así que
> si ponés el que no resuelve, el bloqueo aparece varios pasos después, sin
> relación aparente.

#### El error mudo del formulario de alta

*"Para continuar, corrige los errores"* sin decir cuál campo. Pasó con el
teléfono: el valor era `+5491154822840` **más un `U+202C` invisible** al final
(POP DIRECTIONAL FORMATTING), de copiarlo desde WhatsApp o Contactos. En
pantalla se ve idéntico; el validador lo lee como "esto no es un dígito".

Le pasa a cualquier campo de cualquier formulario de Google. Para verlo, en la
consola del navegador:

```js
[...document.querySelector('input[type=text]').value]
  .map(c => c.codePointAt(0) > 126 ? `<<U+${c.codePointAt(0).toString(16)}>>` : c).join('')
```

Se arregla escribiendo el número **a mano**, sin pegar.

### 2. Keystore

Codemagic → Settings → Code signing identities → Android keystores → *Generate
keystore*. Referencia: `mypump-upload`.

Con Play App Signing esta es solo la clave de **subida**; Google guarda la de
firma real. Si se pierde, se resetea — no es el drama irreversible que fue el
certificado de Apple.

### 3. Cuenta de servicio para publicar

Play Console → Configuración → Acceso a la API → crear cuenta de servicio →
bajar el JSON → Codemagic → Integrations → Google Play.

### 4. El primer build

```bash
git tag a1.0.5 && git push origin a1.0.5
```

Va al track **internal**, que llega a los testers en minutos y sin revisión.

### 5. Después del primer AAB: cerrar los App Links

Play Console → Integridad de la app → copiar el SHA-256 del *certificado de
firma de la app* → pegarlo en `public/.well-known/assetlinks.json`.

**Sin eso, el link del coach abre el navegador en vez de la app**, sin ningún
error visible. `check-android-permisos.mjs` avisa mientras siga el placeholder.

### 6. Health apps declaration

Play Console → Contenido de la app. Hay que justificar los 17 permisos. El
manifest ya está recortado para que sean exactamente los que la app usa, así
que la justificación es la misma para todos: *calcular un score de recuperación
que el cliente ve y su coach usa para ajustar el plan; lectura únicamente; no
se comparte con terceros ni se usa para publicidad*.

## Tres permisos cortados a propósito (17 → 14)

**Glucosa en sangre**, **temperatura corporal** y **mindfulness** se leen en
iOS pero **no** en Android. Van con `soloIOS: true` en el bridge y con
`tools:node="remove"` en el manifest.

El motivo es de revisión, no técnico: Google hace justificar cada permiso de
salud **uno por uno**, y `READ_BLOOD_GLUCOSE` en una app de coaching fitness es
de las cosas que un revisor mira dos veces. Los tres pesan dentro del
componente "otros" del score, que vale 8 puntos de 100, y en la práctica casi
nadie tiene un sensor que los escriba a Health Connect. Un rechazo de una app
de salud cuesta semanas; el dato no cuesta nada.

En iOS quedan igual que siempre: Apple ya los aprobó y ahí no hay que
justificar permiso por permiso.

**Para revertirlo:** sacar `soloIOS` de esas tres líneas en
`healthkit-bridge.js` y volver a declarar los tres permisos en el manifest.
`check-android-permisos.mjs` falla si te olvidás de una de las dos mitades.

## Lo que Android no tiene y iOS sí

- `exerciseTime` → en iOS alimenta `actividad_min`. En Android hay que
  derivarlo de los workouts o dejarlo vacío. Hoy queda vacío.
- `appleSleepingWristTemperature` → `temp_muneca_c`. No existe fuera de Apple.

Los dos entran en el componente "otros" del score. Nada crítico.
