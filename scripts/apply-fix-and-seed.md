# Aplicar 003b + Seed — Instrucciones paso a paso

## Paso 1 — Aplicar migration 003b

1. Ir a **Supabase Dashboard** → proyecto `gydinputrtptqakdzyvc`
2. Ir a **SQL Editor** → New query
3. Copiar y pegar el contenido de `supabase/migrations/003b_fix_ejercicios_estado.sql`
4. Ejecutar (▶ Run)

**Qué hace:**
- Renombra columnas: `token → cliente_id`, `estado → status`, `updated_at → marcado_en`
- Agrega campos: `rutina_id`, `dia_id`, `series_objetivo`, `series_completadas`, `marcado_manualmente`
- Corrige el UNIQUE constraint a `(sesion_id, ejercicio_id)`
- Reemplaza las 2 RPCs con validación correcta del token (usa `mypump_get_cliente_id_from_token`)

**Resultado esperado:** `Success. No rows returned.`

---

## Paso 2 — Aplicar seed de datos de prueba

1. En **SQL Editor** → New query
2. Copiar y pegar el contenido de `supabase/seed/01_test_rutina.sql`
3. Ejecutar

**Qué hace:**
- Archiva rutina y dieta activa de `test-001` (si existen)
- Inserta una rutina activa con 2 días: `lun` (Tirón A) y `mar` (Empuje A)
- Inserta una dieta activa con 2 comidas (Formato A)

**Resultado esperado:** `Success. No rows returned.`

---

## Paso 3 — Confirmar y ejecutar tests

Una vez que ambos SQLs están aplicados, confirmá con:

> "ya apliqué los SQLs"

Y Claude correrá los tests automáticamente.

---

## Tests que se van a verificar

| Test | Qué verifica |
|------|-------------|
| T1 | `mypump_get_rutina_activa` devuelve 1 rutina |
| T2 | `mypump_iniciar_sesion` devuelve UUID válido |
| T3 | Token inválido → `null` (no error 42703) |
| T4 | 4 series registradas + marcado completo → UUID |
| T5 | `get_ejercicios_estado` → `series_completadas=4, marcado_manualmente=false` |
| T6 | Marcado manual sin datos → `series_completadas=0, marcado_manualmente=true` |
