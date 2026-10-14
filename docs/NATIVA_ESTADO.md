# Estado de las apps nativas de MyPump

> Lo lee primero cualquier sesión que retome el trabajo. Plan aprobado el 13-oct-2026:
> `~/.claude/plans/planifica-la-ejecucion-de-atomic-crescent.md`. El pedido original está en
> `docs/PROMPT_SESION_APPS_NATIVAS.md`.

## Candado

**Trabaja:** sesión `7a9c6371` (MacBook), desde el 13-oct-2026 23:59.

Si el candado es de otra sesión y tiene menos de 6 h, no se toca este clon. Cuando una sesión termina, deja el
candado libre.

## Dónde

**Clon:** `~/Developer/mypump-nativa`, rama `nativa`. Está fuera de iCloud: el Escritorio sincroniza y ya generó
copias en conflicto.

**Hooks locales:**
- `pre-commit` rechaza commits que toquen `public/`, `ios/` o `android/`.
- `commit-msg` exige `[CF-Pages-Skip]` en el mensaje.

**Evidencias y volcados:** `~/Developer/nativa-evidencia/`. La subcarpeta `privado/` guarda datos reales y nunca se
commitea.

**Reglas fijas:**
- **El merge de `nativa` a `main` va squash.** El commit 2e64484 se llevó por error 182 MB de compilados de SwiftPM (sin secretos) y ya están en la historia de `nativa`, que no se reescribe.
- `swift test` siempre con `--scratch-path ~/Developer/nativa-evidencia/dd/kit`: sin eso deja `.build/` dentro del repo (ahora está en el `.gitignore`).
- Nunca push a `main`.
- Nunca tags `v*` ni `a*`.
- Las migraciones van como `supabase/migrations/nativa_NNN_*.sql`, solo con OK (G2).

## Fase actual: 0, lo que pide el §9

| Paso | Estado |
|---|---|
| Clon, hooks y estado | ✅ |
| Toolchain Android + runtimes de iOS 17 y 18 | ✅ JDK 21, SDK 36 con emulador e imagen arm64; iOS 17.5 y 18.6 (simuladores "Nativa iOS 17/18" en `simuladores-viejos.txt`) |
| Cuentas de prueba (`scripts/nativa/sembrar.mjs`) | ✅ `test-nativa-ios`. Falta la visible para el chat |
| `docs/NATIVA_CONTRATO.md` + `apps/shared/contrato.json` | ✅ verificado contra `pg_proc` |
| `docs/NATIVA_PARIDAD.md` | ✅ 145 ítems con ID y 9 decisiones para G1 |
| Prueba del almacenamiento viejo en iOS: v1.0.11, v1.0.12-b18 y main × iOS 17, 18 y 26 | ✅ 17.5, 18.6 y 26.5 por las dos rutas y en las dos direcciones (`scripts/nativa/spike-legado.sh`) |
| Prueba del almacenamiento viejo en Android | ✅ emulador Android 16 / WebView 133: la espía lee 23/23 claves y la marca sobrevive a un cierre forzado (`spike-legado-android.sh`) |
| Bocetos en el simulador → G1 | ⏳ |

## Fase 1-2 (en paralelo, desde el 14-oct)

| Pieza | Estado |
|---|---|
| Motor: modelos, cliente RPC, cola, ModeloApp, copia offline | ✅ con integración real (`test-nativa-real`) |
| Reglas con vectores de la web | ✅ progresión, clave, porción casera, anclaje e hidratación de swaps, sustitución de alimentos (2.510 casos) y de ejercicios (323 + 3.232 privados), alimento propio, comida libre |
| **Dieta (iPhone)** | ✅ datos reales, sin Comí/Salté (D10), mano, reemplazo, alimento propio con escaneo, comidas libres. XCUITest en 17.5 y 26.5. Falta: dieta de ejemplo (DIE-17), recarga al cambiar el día (DIE-18) |
| Modelos de Chat, Revisión/Mi Día, fotos de progreso y Progreso | ✅ con tests y backend real (falta conectar las pantallas: lo hace el agente de diseño) |
| Bienvenida, demo, sin conexión, aviso de guardado, volver a primer plano | ✅ (XCUITest de acceso) |
| Notificaciones (local del domingo, push, destinos) | ✅ código; falta probar el push en un iPhone (TF-0) |
| Respaldo científico (14 fuentes), entitlements, PrivacyInfo, workflow `ios-nativa` | ✅ (el workflow no se dispara hasta que Mati acepte el contrato de Apple) |
| Migración del almacenamiento viejo (Fase L/R + write-back) | ✅ mergeada; simulador 26.5 23/23 y 17.5 22/22 (`scripts/nativa/sim-migracion.sh`). Pendiente G2: recibo, conteos, swaps de ejercicio en el servidor |
| Motor de Entreno (`ModeloEntreno` + reglas) | ✅ mergeado: 4.546 vectores públicos y 80.461 privados, integración real |
| Revisión adversarial del código iOS (19 hallazgos) | ✅ 18 arreglados con regresiones (`RegresionesRevisionTests`); el 19 (entitlement de HealthKit sin código, badges fijos) lo cierran Salud y diseño |
| `normalizarDieta` | ✅ igual a la web en 11 casos públicos y las 90 dietas reales |
| Diseño "pro" + conectar Entreno, Chat, Revisión, Progreso y Mis datos a los modelos | ✅ mergeado (1ad2484); Dieta, Acceso y Salud con el mismo sistema (86f28e4); 8 XCUITest. Revisión adversarial de las escrituras en curso |
| Salud (HealthKit, recuperación, relojes) | ✅ mergeada: 35 casos de la web + banco en simulador 1.091/1.091 registros; el historial ya no pisa la noche de hoy (desvío a propósito, ver `NATIVA_PROPUESTAS_WEB.md`) |
| Hoja de permisos de la primera vez (GEN-06), aviso de fin de descanso (D8), aviso de plan incompleto (GEN-05) | ✅ (XCUITest del onboarding) |
| Android: base + reglas (122 tests con los mismos vectores) | ✅ mergeado; la capa de datos está en curso (cuenta `test-nativa-android`) |
| Migración del almacenamiento viejo (Fase L/R) | 🟡 agente en curso |
| Motor de Entreno (sugeridos, topes, variantes, sesiones, historial) | 🟡 agente en curso |


**Herramientas nuevas:** `scripts/nativa/lanzar-sim.sh` (abre la app con una cuenta de prueba sin que el token pase por
la terminal), `probar-ui.sh` (XCUITest con `TEST_RUNNER_MYPUMP_TOKEN`), `spike-legado.sh`.

## Compuertas

| Compuerta | Estado |
|---|---|
| G1 · bocetos, estimación y decisiones de paridad | pendiente (no frena el motor) |
| G2 · migraciones de esquema | ✅ **`nativa_001` y `nativa_002` aplicadas** (14-oct, OK de Mati; las corrió él). Verificado por la API pública. Auditoría de seguridad sin agujeros: `mypump_get_app_config` es pública a propósito. Esquema regenerado. Pendiente para otra tanda: sustituciones de ejercicio en el servidor y `mypump_borrar_serie` |
| G5 · TestFlight externo | pendiente. Los internos ya están autorizados |
| G6 · mensajes a clientes | pendiente |
| G7 · revisión de tiendas | pendiente |

## Decisiones tomadas en autónomo (13/14-oct, Mati: "seguí sin mi intervención")

| # | Decisión | Por qué |
|---|---|---|
| D1 | Comodín: como hoy (un día más) | Paridad por defecto |
| D2 | `mensajes_semana` y el título de la progresión: como hoy (no se muestran) | Paridad por defecto |
| D3 | Entrada fija a **Mis datos** (recordatorios, Salud, diagnóstico, privacidad, "Eliminar mis datos") | La exige Apple 5.1.1(i) para el link de privacidad; sin score no se llegaba |
| D4 | Textos corregidos (recordatorio de entreno inexistente; "11:00", no "mediodía") | Que la app no mienta |
| D5 | Tema: sigue al sistema salvo que el cliente haya guardado `'dark'` | `theme.js` escribe `'light'` siempre, así que no es una elección |
| D6 | Lima en la interfaz; el ícono no cambia | Identidad actual |
| D7 | IA de terceros (5.1.2(i)): **permiso con un "no" real que cubre todo** (chat, fotos y ronda del domingo). Decisión de Mati, 14-oct | App y servidor hechos. Falta aplicar `nativa_002` y desplegar `chat_worker`, `sugerir_pendientes` y `centinela` en la Mini (comandos en la bitácora) |
| D8 | Aviso local de fin de descanso con la app en segundo plano | Mejora sin riesgo |
| D9 | Borrado: link a `eliminar-datos.html` desde Mis datos, sin RPC | No hace falta tocar la base |
| D10 | **Sin "Comí / Salté" en Dieta** (pedido de Mati, 14-oct). Se va también el consumo parcial; el anillo muestra el objetivo y cuánto suman las opciones elegidas | Le resultaba molesto al cliente. El coach deja de recibir esas marcas de los clientes con la nativa (la web las sigue teniendo) |
| D11 | **Sin dieta usable: "Todavía no hay plan de comidas"** (la web mostraba la dieta de ejemplo de 3.200 kcal como si fuera del cliente) | Engañaba al cliente; la demo sigue mostrando el ejemplo |
| T1 | Cola, caché y swaps en **JSON con escritura atómica**, sin GRDB | Volumen chico; cero dependencias de terceros |
| T2 | Cliente RPC propio (URLSession), sin supabase-swift | Hace falta el código HTTP para clasificar errores (aprobado 13-oct) |

## Limitaciones conocidas (igual que la web)

- **Desconfirmar una serie no la borra del servidor** (revisión del 14-oct, hallazgo 9). Si el cliente la deja sin
  volver a confirmarla, Mati la sigue viendo. Arreglo propuesto para una tanda de G2: una RPC
  `mypump_borrar_serie(p_token, p_sesion_id, p_ejercicio_id, p_serie)` y un kind `carga_del` en la cola de las dos apps.

## Lo que solo puede hacer Mati

- Aceptar el contrato nuevo del Developer Program, que frena TestFlight y la 1.0.12.
- Publicar la 1.0.12 de iOS **antes** que la 2.0.0.

## Bitácora

- **14-oct (tarde, 2):**
  - **Revisión adversarial de las pantallas:** 14 hallazgos, arreglados 13 con tests. El 9 queda como limitación,
    igual que en la web.
  - **D7:** el permiso para la IA, en la app y en el servidor.
  - **G2:** OK de Mati. El ensayo de `nativa_001` y `nativa_002` dio OK, pero aplicarlas lo frenó el clasificador:
    las corre Mati.
  - **Desplegado por Mati (14-oct 13:13):** las dos migraciones y los tres scripts, con el md5 igual al del repo. Lo que se corrió:
    1. Las migraciones, que ya están en la Mini:
       `ssh mini 'cd ~/agentkit-coach && venv/bin/python ~/_aplicar.py /tmp/nativa_001_recibo_conteos_palanca.sql && venv/bin/python ~/_aplicar.py /tmp/nativa_002_consentimiento_ia.sql'`
    2. Los scripts, con backup:
       `ssh mini 'cd ~/pump-centinela && for f in chat_worker.py sugerir_pendientes.py centinela.py; do cp $f $f.bak-pre-d7; done' && scp pump-centinela/{chat_worker.py,sugerir_pendientes.py,centinela.py} mini:pump-centinela/`
    - Si los scripts llegan antes que la `nativa_002`, igual andan: "nadie dijo que no".
    - **Ojo:** esos tres scripts están cambiados solo en `nativa`. Si otra sesión despliega desde `main` antes del
      merge, se pierde el filtro.

- **14-oct (tarde):**
  - **iOS:**
    - El diseño "pro" quedó mergeado, con todas las pantallas conectadas a los modelos.
    - La demo de Release ya no lleva datos de la cuenta de prueba (`Muestras.bundle` fuera de Release).
    - Salud sin títulos repetidos y con coma decimal.
    - Dieta, Acceso y Salud con el sistema de diseño.
  - **G2, tanda 1:** preparada sin aplicar (recibo, conteos y palanca remota). La app ya funciona con y sin la migración.
  - **Android:** la prueba del almacenamiento viejo dio OK. El agente de datos sigue con Entreno, Salud y la migración
    pura.

- **14-oct (~11 h, corte por límite de uso):**
  - **Cierres arreglados** (522c871): un número absurdo de la base, la cola o el almacenamiento viejo ya no cierra la
    app. Además, `food_data` falso no se aplica.
  - **Regex** (fe2070d): `.` y `\s` iguales a los de JS, en un solo lugar, con vectores nuevos.
  - **D7 documentado** (1805ad2): opciones en `NATIVA_TIENDAS_2.0.0.md`.
  - Release compila sin advertencias (9,9 MB). 279 tests.
  - **Para retomar:**
    1. **Diseño:** el agente quedó frenado en `.claude/worktrees/agent-a7c9f396d6e2eff0b` con 5 archivos sin commitear
       (Entreno y Mis datos). Hay 150 capturas en `nativa-evidencia/diseno/r4`. Hay que commitear, revisar el diff
       (lo que escribe datos), mergear, correr los XCUITest y sacar `Muestras` del build si ya no se usa.
    2. **Android:** el agente quedó en `.claude/worktrees/agent-a3be09f4e786973f9`, recién arrancado con Entreno,
       Salud y la migración pura. Se retoma con SendMessage.
    3. **Tildar en PARIDAD:** DIE-18 y GEN-07, que ya están cubiertos.
  - **Nunca `git stash` pelado:** el stash se comparte con los worktrees de los agentes.

- **13-oct:** plan aprobado y clon creado.
- **14-oct (madrugada):** MyPumpKit con modelos, reglas portadas con vectores (progresión, clave, porción casera, anclaje e hidratación de swaps), cliente RPC + cola offline + ModeloApp con integración real contra `test-nativa-real`. Agentes en paralelo: motor de sustitutos de alimentos, motor de sustitutos de ejercicios y pulido visual.
- **14-oct (mañana):** Salud mergeada; `ModeloApp.entreno` con el catálogo del servidor; onboarding de permisos; borradores para las tiendas (`NATIVA_TIENDAS_2.0.0.md`) y cambios propuestos para la web (`NATIVA_PROPUESTAS_WEB.md`). 266 tests + 8 de interfaz.
- **14-oct (5-6 h):** merges de migración y motor de Entreno (214 → 228 tests). Revisión adversarial: 4 altos (carrera del link que borraba la sesión, cola trabada, plan que desaparecía con poca señal, cola congelada sin sesión), 9 medios y 6 bajos, todos arreglados con regresiones salvo los de Salud/diseño. Android: base mergeada, sigue con datos.
- **14-oct (4-5 h):** se reanudó tras el corte por límite: los 4 agentes retomaron con su contexto (el de diseño tenía 5 commits). Modelos nuevos con tests contra el backend: chat (con el arreglo n.º 4 que no duplica mensajes), Revisión/Mi Día, fotos de progreso (cola propia), Progreso, notificaciones; respaldo científico; entitlements y PrivacyInfo; workflow `ios-nativa`. Agente nuevo: Salud.
- **14-oct (~2 h):** bienvenida nativa (pegar link con PasteButton, link vencido, sin conexión con reintento automático, universal links) y modo demo sin red; XCUITest de acceso pasan. **Corte por límite de uso:** los agentes de diseño, migración, motor de Entreno y Android quedaron en sus worktrees (`.claude/worktrees/agent-*`, ramas `worktree-agent-*`) con lo que hayan commiteado; retomar revisando cada rama y mergeando a `nativa`.
- **14-oct (1-2 h):** Dieta nativa terminada salvo la dieta de ejemplo: el reemplazo da las mismas 55 opciones que la web para "Huevo entero" (lado a lado con la web local de `origin/main` y la misma cuenta). Spike del almacenamiento viejo OK en 17.5 y 18.6. Merge de los motores de sustitución (alimentos y ejercicios). Agentes nuevos: migración, motor de Entreno, Android.
- **14-oct:** riesgo n.º 1 resuelto en iOS 26.5 (`NATIVA_SPIKE_ALMACENAMIENTO.md`). Contrato verificado contra la base: 50 RPC, ninguna duplicada; `push_pendientes` manda a cada dispositivo a propósito. Cuenta `test-nativa-ios` sembrada.
