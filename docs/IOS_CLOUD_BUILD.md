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
- En `codemagic.yaml` hay una línea con `APP_STORE_APPLE_ID: "<<<APP_STORE_APPLE_ID>>>"`.
- Reemplazá ese `<<<...>>>` por el número que copiaste en el paso 1.
- **Decime el número y yo te lo dejo puesto y commiteado** — no hace falta que
  toques el archivo vos.

### 5. Correr la build
- En Codemagic, elegí el repo → workflow **"MyPump iOS → TestFlight"** →
  **Start new build**.
- Tarda ~10-20 min. Al terminar, el build aparece solo en **TestFlight**
  (App Store Connect → tu app → TestFlight).
- Instalá **TestFlight** en tu iPhone (App Store), entrá con tu Apple ID y ya
  podés abrir MyPump nativo para probar Apple Health.

## Después de la primera vez
Cada vez que quieras una build nueva: entrás a Codemagic y tocás **Start new
build** (o se puede configurar que se dispare solo con cada push a `main`).
Nunca más Xcode.

## Si algo falla
Copiame el log de Codemagic (lo muestra en la misma pantalla de la build) y lo
resuelvo. Los puntos típicos: el nombre de la API key no coincide con
`PumpTeam_ASC`, o falta completar el `APP_STORE_APPLE_ID`.
