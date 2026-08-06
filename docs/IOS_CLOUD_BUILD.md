# MyPump iOS — Build en la nube (Codemagic) SIN Xcode

> Este es el camino para llevar la app a tu iPhone (TestFlight) **sin instalar
> Xcode ni usar la terminal**. La compilación y la firma corren en las Mac de
> Codemagic. El pipeline ya está definido en `codemagic.yaml` (en la raíz del
> repo). Vos solo hacés unos clics en la web de Codemagic, **una sola vez**.
>
> ⚠️ Nada de esto funciona hasta que **Apple acepte tu cuenta Developer**
> (el mail que estás esperando). Es un bloqueo total: sin cuenta no se firma nada.

## Qué necesitás tener antes
- Cuenta **Apple Developer Organización** ACEPTADA (Pump Team LLC).
- El repo ya está en GitHub: `matisanca/mypump-app`.

## Pasos (una sola vez, todo en el navegador)

### 1. Crear la app en App Store Connect
- Entrá a https://appstoreconnect.apple.com → **Apps** → **+** → **New App**.
- Platform: iOS · Name: MyPump · Bundle ID: `com.pumpteam.mypump` (elegilo de la
  lista; si no aparece, se crea solo al firmar) · SKU: `mypump` · idioma: Español.
- Cuando quede creada, entrá a **App Information** y copiá el **Apple ID**
  (un número, ej. `6748291023`). Lo vas a necesitar en el paso 4.

### 2. Generar la API key de App Store Connect
- En App Store Connect → **Users and Access** → pestaña **Integrations** →
  **App Store Connect API** → **+** para generar una key.
- Rol: **App Manager** (alcanza). Descargá el archivo `.p8` (⚠️ se baja UNA vez).
- Anotá también el **Issuer ID** y el **Key ID** que muestra esa pantalla.

### 3. Codemagic: crear cuenta y conectar
- Entrá a https://codemagic.io → **Sign up with GitHub** (plan free: ~500 min/mes,
  suficiente para varias builds).
- Autorizá el acceso al repo `matisanca/mypump-app` y agregalo.
- **Teams → Integrations → App Store Connect → Connect** (o **Add key**):
  subí el `.p8` del paso 2 + pegá el Issuer ID y el Key ID.
  **Poné de nombre de la key exactamente:** `PumpTeam_ASC`
  (así coincide con lo que dice `codemagic.yaml`; si usás otro nombre, avisame y
  lo cambio en el archivo).

### 4. Completar el número de la app en el repo
- ✅ **HECHO.** `APP_STORE_APPLE_ID: "6793259380"` ya está en `codemagic.yaml`.

### 5. El certificado de distribución
✅ **HECHO el 5-ago-2026.** Queda documentado porque es el paso que más veces
rompió el pipeline y hay que rehacerlo cuando el certificado venza
(**5-ago-2027**).

- **Codemagic → Settings → Code signing identities → iOS certificates →
  "Generate certificate"**, tipo **Apple Distribution**, con la key
  `PumpTeam_ASC`. Nombre de referencia: `mypump-dist-2026`.
- La clave privada queda del lado de Codemagic. **No hay nada que descargar ni
  que pegar en ninguna variable de entorno.**

> **Por qué no se hace de otra forma:** un certificado de Apple no sirve sin la
> clave privada con la que se pidió. Antes el pipeline generaba la clave dentro
> del build (`openssl genrsa`), así que moría con la máquina y el certificado
> quedaba huérfano. Se juntaron 3 y Apple empezó a devolver
> `409: You already have a current Distribution certificate` — eso volteó el
> build #14 el 28-jul-2026, y los 24 commits siguientes nunca compilaron.
> Generándolo desde Codemagic el problema no puede volver.

### 6. Correr la build
El disparador es un **tag de git**, no un botón:

```bash
git tag v1.0.4 && git push origin v1.0.4
```

- Tarda ~10-20 min. Al terminar, el build aparece solo en **TestFlight**
  (App Store Connect → tu app → TestFlight).
- Instalá **TestFlight** en tu iPhone (App Store), entrá con tu Apple ID y ya
  podés abrir MyPump nativo para probar Apple Health.

> Es por tag y no por push a main a propósito, por dos razones: no todo commit
> merece un build de Mac ni una subida a TestFlight, y cuando el dashboard de
> Codemagic se degrada (pasó el 27 y el 28 de julio: el diálogo de "Start new
> build" no abre) el tag sigue funcionando porque no depende de su web.

## Si algo falla
Copiame el log de Codemagic y lo resuelvo. Los puntos típicos:
- el nombre de la API key no coincide con `PumpTeam_ASC`;
- **`Code signing identities` quedó vacío** → rehacer el paso 5;
- `"App" requires a provisioning profile with the X feature` → agregaste una
  capability al App ID. Con la firma automática de hoy se arregla solo en el
  build siguiente; si no, borrá los perfiles "Invalid" en developer.apple.com.
