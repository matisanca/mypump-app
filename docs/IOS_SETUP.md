# MyPump iOS — Guía de build y publicación (Etapa D)

> **El proyecto iOS ya está GENERADO y configurado a nivel de archivos.** Lo que
> falta es lo que necesita **tu Mac con Xcode.app** y la **cuenta Apple Developer
> aceptada**: firmar, buildear en device y subir. El código web es el MISMO que la
> web (no se bifurca); el wrapper solo lo empaqueta y le suma Apple Health.
>
> Ya hecho de forma autónoma (commiteado):
> - `capacitor.config.json` (appId `com.pumpteam.mypump`, `webDir: public`).
> - Capacitor **8** + plugin `@capgo/capacitor-health` (Cap 8 usa **Swift Package
>   Manager**, NO CocoaPods → no hace falta `pod install`).
> - Proyecto Xcode en `ios/` con el bundle id ya seteado.
> - `ios/App/App/Info.plist`: `NSHealthShareUsageDescription` +
>   `NSHealthUpdateUsageDescription` (en español).
> - `ios/App/App/App.entitlements`: capability HealthKit, ya cableada en el
>   `project.pbxproj` (CODE_SIGN_ENTITLEMENTS en Debug y Release).
> - `public/js/healthkit-bridge.js`: puente Apple Health → `mypump_ingest_salud`.
> - Botón "Conectar Apple Health" en Mi Día (solo aparece en la app nativa).

## Modelo de sincronización (importante)
Se sincroniza **cada vez que el cliente abre la app / la trae a foco** (que para
una app de entreno + dieta es a diario). Permiso **una sola vez**; después, cada
apertura sube los pasos / minutos de ejercicio / kcal activas de los últimos 7
días. **No hay background delivery "con la app cerrada"**: el plugin mantenido
(`@capgo/capacitor-health`) no lo soporta, y declarar `UIBackgroundModes` sin
usarlos de verdad es causa de rechazo de Apple (guideline 2.5.4). Si en el futuro
se quiere sync con la app cerrada, requiere Swift nativo custom
(`HKObserverQuery` + `enableBackgroundDelivery`) — anotado como mejora futura.

---

## 0. Requisitos (tu Mac)
- **Xcode.app** (última estable del App Store — NO alcanza con Command Line Tools).
- **Cuenta Apple Developer como Organización** (Pump Team LLC + D-U-N-S) **aceptada**.
- Un **iPhone físico** para probar HealthKit (el simulador no tiene datos de Salud).
- Node 18+ (ya usás Node en el repo).

## 1. Preparar el proyecto en tu Mac
```bash
cd mypump-app
npm install              # instala Capacitor + el plugin (ya está en package.json)
npx cap sync ios         # re-copia public/ al bundle (corré esto tras cada cambio web)
npx cap open ios         # abre el proyecto en Xcode
```
> No hace falta `cap add ios` (ya está generado) ni CocoaPods (Cap 8 usa SPM).
> Cada vez que cambie el **código JS/HTML/CSS**: `npx cap sync ios` + nueva build.
> Los DATOS (rutinas/dietas) siguen viniendo de Supabase en vivo, sin rebuild.

## 2. Xcode — Signing
Target **App** → pestaña **Signing & Capabilities**:
1. **Team**: seleccioná el equipo de la Organización (Pump Team LLC).
2. **Bundle Identifier**: ya está en `com.pumpteam.mypump`.
3. La capability **HealthKit** ya viene por el `App.entitlements`. Verificá que
   aparezca en la lista de capabilities; con *Automatic signing*, Xcode habilita
   HealthKit en el App ID del portal solo. (Si no aparece, tocá **+ Capability →
   HealthKit** y Xcode la reconcilia con el entitlements existente.)

## 3. Verificaciones rápidas ya hechas (no toques salvo que rompa)
- `Info.plist`: strings de privacidad de Salud presentes (obligatorio: sin
  `NSHealthShareUsageDescription` la app crashea al pedir permisos).
- `App.entitlements`: `com.apple.developer.healthkit = true`.
- Pedimos SOLO los tipos que usamos (guideline 2.5.1): pasos, minutos de
  ejercicio, energía activa. Están en `healthkit-bridge.js` (const `MAP`).

## 4. Token del cliente en la app nativa (recomendado, no bloqueante)
Hoy el token vive en localStorage (funciona). Mejora: guardarlo en **Keychain**
(`capacitor-secure-storage-plugin`) + pantalla de primer arranque "Pegá tu link
de Mati", o un Universal Link `app.mypumpteam.com/t/*`. El resto del flujo es
idéntico a la web.

## 5. Probar en iPhone físico  ✋ (esto lo hacés vos)
- Corré la app en tu iPhone desde Xcode (Product → Run).
- Andá a **Mi Día** → **Conectar Apple Health** → aceptá los permisos.
- Verificá que aparezcan tus pasos en la card "Salud".
- Cerrá y reabrí la app tras caminar un rato → los pasos deben actualizarse (sync
  al abrir).
- Revocá el permiso en Ajustes → Salud → MyPump y confirmá que la app no crashea.
- Probá el **modo avión** en el gym real (service worker + Outbox drenando).

---

## 6. Checklist App Store Connect
- [ ] Apple Developer **Organización** activa (LLC + D-U-N-S).
- [ ] App creada en App Store Connect con bundle `com.pumpteam.mypump`.
- [ ] **Política de privacidad por URL** (ej. `app.mypumpteam.com/privacidad`) que cubra:
      datos de salud de HealthKit (qué se lee, que **NO** se comparte con terceros
      ni se usa para publicidad — guideline 5.1.3), datos de entrenamiento/dieta, y
      **GDPR** por clientes en España (base legal, derecho de acceso/borrado,
      transferencias internacionales Supabase/Cloudflare con SCCs).
- [ ] **App Privacy** (nutrition labels): Health & Fitness → *linked to user*,
      *not used for tracking*.
- [ ] Metadata en español: nombre, subtítulo, descripción, keywords.
- [ ] **Screenshots** 6.7" y 6.1": Entreno, Dieta, Mi Día (con Salud), Progreso.
- [ ] **Review notes**: cuenta demo con un token de prueba (cliente ficticio con
      rutina + dieta publicadas) para que Apple pueda entrar.
- [ ] **TestFlight** interno primero (vos + 2-3 clientes) → después Review.

## 7. Orden recomendado
1. (Bloqueante) Que Apple acepte la cuenta Developer Org.
2. Instalar Xcode.app → `npm install` → `npx cap open ios`.
3. Signing (Team) + build en **simulador** (verifica UI/navegación/safe-areas).
4. Build en **iPhone físico** + probar Apple Health (sección 5).
5. Privacidad + metadata + screenshots + TestFlight.
6. Submit a Review.
