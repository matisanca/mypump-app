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
- Nunca push a `main`.
- Nunca tags `v*` ni `a*`.
- Las migraciones van como `supabase/migrations/nativa_NNN_*.sql`, solo con OK (G2).

## Fase actual: 0, lo que pide el §9

| Paso | Estado |
|---|---|
| Clon, hooks y estado | ✅ |
| Toolchain Android + runtimes de iOS 17 y 18 | 🟡 JDK 21 y cmdline-tools listos; SDK 36 y emulador bajando; iOS 17.5 bajando (lento) |
| Cuentas de prueba (`scripts/nativa/sembrar.mjs`) | ✅ `test-nativa-ios`. Falta la visible para el chat |
| `docs/NATIVA_CONTRATO.md` + `apps/shared/contrato.json` | ✅ verificado contra `pg_proc` |
| `docs/NATIVA_PARIDAD.md` | ⏳ |
| Prueba del almacenamiento viejo en iOS: v1.0.11, v1.0.12-b18 y main × iOS 17, 18 y 26 | 🟢 iOS 26.5 OK por las dos rutas y en las dos direcciones. Faltan 17 y 18 |
| Prueba del almacenamiento viejo en Android | ⏳ |
| Bocetos en el simulador → G1 | ⏳ |

## Compuertas

| Compuerta | Estado |
|---|---|
| G1 · bocetos, estimación y decisiones de paridad | pendiente (no frena el motor) |
| G2 · migraciones de esquema | ninguna pedida todavía |
| G5 · TestFlight externo | pendiente. Los internos ya están autorizados |
| G6 · mensajes a clientes | pendiente |
| G7 · revisión de tiendas | pendiente |

## Lo que solo puede hacer Mati

- Aceptar el contrato nuevo del Developer Program, que frena TestFlight y la 1.0.12.
- Publicar la 1.0.12 de iOS **antes** que la 2.0.0.

## Bitácora

- **13-oct:** plan aprobado y clon creado.
- **14-oct:** riesgo n.º 1 resuelto en iOS 26.5 (`NATIVA_SPIKE_ALMACENAMIENTO.md`). Contrato verificado contra la base: 50 RPC, ninguna duplicada; `push_pendientes` manda a cada dispositivo a propósito. Cuenta `test-nativa-ios` sembrada.
