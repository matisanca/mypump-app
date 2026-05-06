# Schema JSONB — `mypump_dietas.estructura`

Cuando Cerebro publica una dieta, el campo `estructura` de la tabla `mypump_dietas` debe respetar uno de estos dos formatos.

---

## Formato A — Plan único (el más común hoy)

Un solo conjunto de macros y comidas, igual para todos los días.

```json
{
  "macros_target": { "kcal": 3200, "prot": 220, "carb": 380, "fat": 90 },
  "comidas": [
    {
      "id": "c1",
      "name": "Desayuno",
      "options": [
        {
          "name": "A",
          "foods": [
            {
              "name": "Avena",
              "qty": 100,
              "unit": "g",
              "kcal": 380,
              "prot": 13,
              "carb": 67,
              "fat": 7,
              "category": "carbohidrato",
              "swappable": true
            }
          ]
        },
        {
          "name": "B",
          "foods": [...]
        }
      ]
    }
  ]
}
```

**Detección en MyPump:** si `estructura.tipos_dia` no existe → Formato A.

---

## Formato B — Diferenciado por tipo de día (futuro)

Permite macros y comidas distintos para días de entrenamiento vs. descanso.

```json
{
  "tipos_dia": [
    {
      "id": "entreno",
      "nombre": "Día de entrenamiento",
      "macros_target": { "kcal": 3200, "prot": 220, "carb": 380, "fat": 90 },
      "comidas": [...]
    },
    {
      "id": "descanso",
      "nombre": "Día de descanso",
      "macros_target": { "kcal": 2800, "prot": 220, "carb": 280, "fat": 90 },
      "comidas": [...]
    }
  ]
}
```

**Detección en MyPump:** si `estructura.tipos_dia` existe y tiene ≥ 2 elementos → mostrar segmented control. Si tiene 1 elemento → renderizar como Formato A sin selector.

---

## Shape de cada `food` en `options[].foods`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `name` | string | ✅ | Nombre del alimento |
| `qty` | number | ✅ | Cantidad en la unidad indicada |
| `unit` | string | ✅ | `"g"`, `"ml"`, `"unidad"`, `"rebanada"`, etc. |
| `kcal` | number | ✅ | Calorías por la porción indicada |
| `prot` | number | ✅ | Proteína en gramos por la porción |
| `carb` | number | ✅ | Carbohidratos en gramos por la porción |
| `fat` | number | ✅ | Grasa en gramos por la porción |
| `category` | string | ⬜ | Categoría para el sustitutor: `proteina`, `carbohidrato`, `grasa`, `lacteo`, `fruta_verdura`, `mixto`, `condimento`. Si no se envía, MyPump lo infiere por macros. |
| `swappable` | boolean | ⬜ | `false` para deshabilitar el botón de sustitución (ej: condimentos, agua). Default: `true`. |

---

## Notas para Prompt 3 (Cerebro → publicar dieta)

- Los `id` de comidas (`"c1"`, `"c2"`, etc.) deben ser **estables** entre versiones. El sustitutor y el historial de opciones usan esos IDs como key.
- Si publicás una nueva dieta (nuevo row en `mypump_dietas`), MyPump reseteará automáticamente los swaps del cliente porque el `DIETA_ID` cambia.
- El campo `category` es opcional pero **recomendado**: si no se envía, el algoritmo usa heurística por macros, lo cual puede dar resultados imprecisos para alimentos mixtos.
