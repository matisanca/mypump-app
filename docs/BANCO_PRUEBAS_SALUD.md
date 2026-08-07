# Banco de pruebas de salud — probar todo desde la Mac

> Sirve para ver el pipeline completo de salud (HealthKit → ingest → motor de
> recuperación → cards) **sin iPhone, sin reloj y sin esperar días**, con datos
> que tienen la forma de los reales.

## Por qué existe

Hasta la 1.0.4 esto solo se podía probar con un teléfono en la mano, un reloj
puesto y semanas de historia acumulada. El costo de eso se pagó en producción:
un botón que no hacía nada durante semanas y un onboarding que se colgaba
minutos llegaron a la App Store porque nadie podía recorrer el flujo entero.

Son dos herramientas que se usan juntas o por separado:

| | Qué hace | Cuándo |
|---|---|---|
| `scripts/seed-salud.mjs` | Carga 60 días de datos en un cliente de prueba, vía el RPC real | Ver cómo queda una card en un escenario dado |
| `?mockhealth=1` | Se hace pasar por el plugin de HealthKit en el navegador | Recorrer el flujo: onboarding → permisos → sync → backfill |

---

## 0. Una sola vez: cliente de prueba

```sql
INSERT INTO mypump_clientes (cliente_id, nombre, perfil, access_token)
VALUES ('test-001', 'Banco de pruebas', 'natural', 'TOKEN_DE_PRUEBA_32CHARS_ACA');
```

El token tiene que matchear `/^[a-zA-Z0-9_-]{16,64}$/` (`cliente.html:1085`) o la
app lo rechaza antes de pedirlo. Rutina y dieta salen de
`supabase/seed/01_test_rutina.sql` si las querés.

---

## 1. Ver una card en un escenario

```bash
npm run dev     # sirve public/ en localhost:3000
node scripts/seed-salud.mjs --token TOKEN --escenario sin-reloj
```

Después abrí `http://localhost:3000/cliente?t=TOKEN`.

> **Ojo con la URL:** `serve` limpia `.html` y en la redirección se come el query
> string. Usá `/cliente?...`, no `/cliente.html?...`.

### Qué esperar de cada escenario

| `--escenario` | Qué simula | Card de Recuperación |
|---|---|---|
| `normal` | 60 días sanos | Score con banda **alta/media** |
| `fatiga` | Pulso subiendo, HRV bajando, sueño corto | Banda **baja**, "fatiga acumulada" |
| `maladaptacion` | Ídem + oscilación día a día | Banda baja, estado autonómico **maladaptación** |
| `sin-reloj` | iPhone pelado: solo pasos y actividad | **Sin score y SIN botón** — explica que hace falta un reloj |
| `recien-conectado` | 3 días de historia | **Calibrando**, "3 / 14 días" |

`sin-reloj` es el caso que reportó Mati en la 1.0.4 y el que hay que mirar
primero después de tocar la card: es donde estaba el botón muerto.

Otras opciones: `--dias N`, `--seed N` (misma semilla = misma serie),
`--fuente oura|whoop|…`, `--dry-run` (no postea, solo muestra).

---

## 2. Recorrer el flujo nativo entero, en el navegador

```
http://localhost:3000/cliente?t=TOKEN&mockhealth=1&mockreset=1&mockescenario=normal
```

Con eso el bridge se cree nativo y corre **el código real de punta a punta**:
el onboarding, la hoja de permisos, el sync de 7 días, el backfill de 60 con su
progreso, y el ingest de verdad contra Supabase.

| Parámetro | Para qué |
|---|---|
| `mockhealth=1` | Enciende el mock (obligatorio) |
| `mockreset=1` | Borra el estado local de salud y el onboarding: se vuelve a ver desde cero |
| `mockescenario=` | Mismos nombres que el seeder |
| `mockdias=` / `mockseed=` | Cuánta historia y con qué semilla |
| `mockdeny=1` | "Acepta" la hoja pero no llega ningún dato → camino del aviso de Ajustes |
| `mocklento=1` | 700 ms por lectura: sirve para **ver** el progreso y confirmar que la UI no se traba |

### Qué mirar

1. El cartel de onboarding aparece ~1,2 s después de cargar.
2. **"Ahora no" nunca queda deshabilitado**, ni siquiera mientras conecta. Si se
   deshabilita, volvió el bug que congeló la app de Mati.
3. Con `mocklento=1`, `connect()` vuelve **antes** de que termine el backfill, y
   las cards muestran "Trayendo tu historial… N/60 días" mientras la app sigue
   navegable.
4. Con `mockdeny=1`, al terminar el backfill aparece el aviso de Ajustes **bajo
   la card desde la que tocaste conectar** (no bajo la otra).

### Que no se active en producción

El loader de `cliente.html` tiene triple compuerta: hace falta `?mockhealth=1`
**y** que no exista un Capacitor real **y** que el host sea `localhost`. Dentro
de la app nativa no se activa nunca, y un cliente en `app.mypumpteam.com`
tampoco puede prenderlo. Los archivos del banco no están en el SHELL del
service worker.

---

## 3. Diagnóstico

`http://localhost:3000/cliente?t=TOKEN&diag=health` — o cinco toques sobre el
título "Salud de Apple" en Revisión → Mis datos. Muestra, por tipo, cuántas
muestras entraron, el primer y último día, el error nativo textual, y el detalle
del sueño por noche y por fuente.

---

## 4. La hoja de permisos REAL (simulador de iOS)

El mock no prueba la hoja de Apple ni las entitlements. Para eso:

```bash
./scripts/sim.sh
```

El simulador de iOS 26.5 **sí** trae Health.app y HealthKit. Los datos se cargan
a mano (Health → Explorar → agregar).

> **Nunca** compilar con `CODE_SIGNING_ALLOWED=NO`: sin firma no se inyectan las
> entitlements y HealthKit falla con `Missing com.apple.developer.healthkit
> entitlement`. Está documentado en la cabecera de `sim.sh`.

---

## 5. Limpiar al terminar

```
scripts/cleanup-test-data.sql     (pegar en el SQL editor de Supabase)
```

**No es opcional.** El centinela y el panel del coach leen **todos** los
clientes, `test-001` incluido: los datos sintéticos aparecen en el radar del
domingo y en los briefs pre-call hasta que se borren.

---

## Tests automáticos relacionados

```bash
npm test
```

- `scripts/test-bridge.mjs` — el contrato de `connect()`: que vuelva antes del
  backfill, que el progreso avance, que la firma vieja siga andando.
- `scripts/test-salud-sintetica.mjs` — que el generador no se vaya de los rangos
  de plausibilidad. **Los rangos se parsean de la migración 047**, así que si
  alguien los cambia en SQL, el test se entera solo.

Lo que NO cubren: el gateo de las cards y el onboarding viven en las 8000 líneas
de `cliente.html` y no hay harness de DOM. Eso se verifica a mano con el paso 2
— para eso está el banco.
