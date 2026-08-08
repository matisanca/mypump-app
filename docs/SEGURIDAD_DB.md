# Qué puede hacer un desconocido con la anon key

La anon key de Supabase está en `public/js/config.js`, commiteada, y **tiene que
estarlo**: es la que usa la app en el navegador de cada cliente. O sea que
cualquiera que abra las DevTools la tiene.

Lo único que separa los datos de tus clientes de internet son tres capas:

1. **RLS** activo en la tabla,
2. **GRANTs** de la tabla al rol `anon`,
3. la **guarda dentro de cada función** `SECURITY DEFINER`.

Las tres se pueden desalinear de a una, y ninguna avisa cuando se desalinea. Los
avisos de *"RLS disabled"* del panel de Supabase no alcanzan para saber si hay un
problema real: una tabla sin RLS es inofensiva si `anon` no tiene GRANT, y una
tabla **con** RLS puede estar abierta de par en par si una política dice
`USING (true)` para `public`.

## El chequeo

```bash
scp scripts/auditar_seguridad_db.py mini:~/
ssh mini "~/agentkit-coach/venv/bin/python3 ~/auditar_seguridad_db.py"
```

Corre en la mini porque necesita la conexión directa a Postgres
(`SUPABASE_DB_URL` en `~/agentkit-coach/.env`). Es **solo lectura**. Sale con 1
si encuentra algo.

## Resultado de la última corrida — 8-ago-2026

**✓ Ningún agujero.** Con la anon key sola no se llega a datos de clientes.

| | |
|---|---|
| Tablas alcanzables por `anon` | 66, **todas con RLS y con políticas** |
| Funciones `SECURITY DEFINER` que `anon` puede llamar | 61 |
| … con guarda (token o rol) | 57 |
| … que son triggers, no invocables por RPC | 3 |
| … sin guarda | 1, de solo lectura |

### Las dos cosas que el chequeo marca, y por qué están bien

Las dos son el **catálogo de ejercicios**, que es público a propósito:
`mypump_ejercicios_catalogo` tiene 873 filas de nombre, músculo, equipamiento e
imágenes, y **cero columnas con datos de cliente** (verificado contra
`information_schema`). La migración 051 se llama justamente
`catalogo_sin_escritura_anonima`: le sacó la escritura a `anon` y le dejó la
lectura. La política `read_all_catalogo` es `[SELECT]` únicamente; la escritura
va por `admin_write_catalogo`, restringida a `authenticated` y `service_role`.

`mypump_match_ejercicio_por_nombre` busca sobre esa misma tabla pública.

## Dos cosas que aprendí auditando, y que conviene no olvidar

**`nutriplan_data` está protegida, aunque el GRANT diga lo contrario.** `anon`
tiene `SELECT` y `UPDATE` sobre esa tabla —el blob entero del Cerebro— y eso
asusta al leerlo. Pero RLS está activo y su única política es para el rol
`authenticated`. El GRANT sobra, no abre nada. Esta era una duda abierta desde
hacía semanas y ahora está respondida con evidencia, no con una suposición.

**"Validar por token" no es la única guarda válida.** La primera versión de este
script marcaba como sospechosa cualquier función `SECURITY DEFINER` que no
mencionara un token, y así flaggeó `mypump_revocar_acceso` y
`mypump_set_ejercicio_imagen` — las dos perfectamente protegidas, pero **por
rol**:

```sql
IF auth.role() <> 'authenticated' THEN RAISE EXCEPTION 'Acceso denegado'; END IF;
```

Son las funciones del coach, no las del cliente: se protegen por quién sos, no
por qué token traés. El script ahora acepta las dos formas.
