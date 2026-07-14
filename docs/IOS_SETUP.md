# MyPump iOS — Guía de build y publicación (Etapa D)

> Esta guía la ejecutás **vos en tu Mac** (Xcode). El código web ya está listo y
> es el MISMO que la web (no se bifurca): el wrapper solo lo empaqueta y le suma
> Apple Health nativo. Lo que ya quedó preparado en el repo:
> - `capacitor.config.json` (appId `com.pumpteam.mypump`, `webDir: public`)
> - deps de Capacitor + `@perfood/capacitor-healthkit` en `package.json`
> - `public/js/healthkit-bridge.js` (puente Apple Health → `mypump_ingest_salud`)
> - botón "Conectar Apple Health" en Mi Día (solo aparece en la app nativa)
>
> **Prerrequisito bloqueante:** cuenta **Apple Developer como Organización** con
> Pump Team LLC (necesita D-U-N-S, web corporativa y teléfono verificable).
> USD 99/año, trámite 2-7 días. **Arrancalo YA en paralelo**, es el camino crítico.

---

## 0. Requisitos
- Mac con **Xcode** (última estable) + Command Line Tools.
- **CocoaPods** (`sudo gem install cocoapods`).
- Node 18+.
- Un **iPhone físico** para probar HealthKit (el simulador NO sirve para background).

## 1. Instalar dependencias y generar el proyecto iOS
```bash
cd mypump-app
npm install
npx cap add ios          # genera la carpeta ios/ (proyecto Xcode)
npx cap sync ios         # copia public/ al bundle + instala pods
npx cap open ios         # abre Xcode
```
> Cada vez que cambie el código web: `npx cap sync ios` re-copia `public/`.
> Los DATOS (rutinas/dietas) siguen viniendo de Supabase en vivo — solo los
> cambios de **código JS** requieren re-sync + nueva build.

## 2. Xcode — Signing & Capabilities
En el target de la app → pestaña **Signing & Capabilities**:
1. **Team**: seleccioná el equipo de la Organización (Pump Team LLC).
2. **Bundle Identifier**: `com.pumpteam.mypump`.
3. **+ Capability → HealthKit**. Dentro de HealthKit, tildá **Background Delivery**.
4. **+ Capability → Background Modes** → tildá **Background fetch** (y *Background processing* si el plugin lo pide).

## 3. Info.plist — claves de privacidad (obligatorias, en español)
Agregá al `ios/App/App/Info.plist`:
```xml
<key>NSHealthShareUsageDescription</key>
<string>MyPump lee tus pasos y actividad para que tu coach ajuste tu plan de entrenamiento y nutrición.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>MyPump no escribe datos en Salud; este permiso solo se usa si en el futuro registrás datos manualmente.</string>
```
> Sin `NSHealthShareUsageDescription` la app **crashea** al pedir permisos y Apple
> la rechaza. Pedí SOLO los tipos que usás (guideline 2.5.1): pasos, energía
> activa, minutos de ejercicio.

## 4. Background delivery (sync automático real)
El `healthkit-bridge.js` ya sincroniza **al abrir y al volver a foco** (fallback).
Para el sync con la app cerrada hay que registrar el observer nativo en
`ios/App/App/AppDelegate.swift` siguiendo la doc del plugin
`@perfood/capacitor-healthkit` (habilitar `enableBackgroundDelivery` para cada
`HKQuantityType` y despertar un sync). Referencia: README del plugin.
> ⚠️ Verificá los **nombres de sample** que usa el bridge (`stepCount`,
> `appleExerciseTime`, `activeEnergyBurned`) y la forma de `resultData` contra el
> plugin instalado — están marcados con `⚠️ VERIFICAR` en el bridge.

## 5. Token del cliente en la app nativa
En el wrapper conviene guardar el token en **Keychain** (plugin
`capacitor-secure-storage-plugin`) en vez de localStorage, y una pantalla de
primer arranque "Pegá tu link de Mati" (o un Universal Link
`app.mypumpteam.com/t/*` que abra la app con el token). El resto del flujo es
idéntico a la web.

## 6. Probar en iPhone físico  ✋ (esto lo hacés vos, no hay atajo)
- Corré la app en tu iPhone desde Xcode.
- Tocá **Conectar Apple Health** → aceptá permisos → verificá que aparezcan los
  pasos en la card "Salud" de Mi Día.
- **Background sync**: dejá la app cerrada, caminá, y verificá 24-48h después que
  los datos llegaron solos (el SO decide cuándo despierta — es "best effort";
  por eso el fallback de sync-al-abrir).
- Revocá el permiso en Ajustes → Salud y confirmá que la app no crashea.
- Probá el **modo avión** en el gym real (service worker + Outbox drenando al
  volver la señal).

---

## 7. Checklist App Store Connect
- [ ] Apple Developer **Organización** activa (LLC + D-U-N-S).
- [ ] App creada en App Store Connect con bundle `com.pumpteam.mypump`.
- [ ] **Política de privacidad por URL** (ej. `app.mypumpteam.com/privacidad`) que cubra:
      datos de salud de HealthKit (qué se lee, que **NO** se comparte con terceros
      ni se usa para publicidad — guideline 5.1.3), datos de entrenamiento/dieta, y
      **GDPR** por clientes en España (base legal, derecho de acceso/borrado, y
      transferencias internacionales Supabase/Cloudflare con SCCs).
- [ ] **App Privacy** (nutrition labels): Health & Fitness → *linked to user*,
      *not used for tracking*.
- [ ] Metadata en español: nombre, subtítulo, descripción, keywords.
- [ ] **Screenshots** 6.7" y 6.1": Entreno, Dieta, Mi Día (con Salud), Progreso.
- [ ] **Review notes**: cuenta demo con un token de prueba (cliente ficticio con
      rutina + dieta publicadas) para que Apple pueda entrar.
- [ ] **TestFlight** interno primero (vos + 2-3 clientes) → después Review.

## 8. Orden recomendado
1. (En paralelo, ya) Trámite Apple Developer Org.
2. `npm install` + `cap add ios` + build en **simulador** (verifica UI/navegación/safe-areas).
3. Build en **iPhone físico** + HealthKit + background (sección 6).
4. Privacidad + metadata + screenshots + TestFlight.
5. Submit a Review.
