# Ajustes de porciones: cómo leerlos (para el Cerebro o el brief)

Desde la 2.0.1 de las apps, el cliente puede ajustar una comida del día. Puede:
- sumarle o restarle kcal (las porciones se recalculan);
- poner la cantidad de un alimento a mano;
- marcar «Hoy no la como»;
- compensar la diferencia en la comida siguiente.

Pedido de Mati, 20-oct: «que Mati vea cómo juega con las calorías».

Las apps lo guardan en la base. **La web y el Cerebro todavía no lo leen**: este documento es para la sesión que se
encargue de mostrarlo. Las apps no se tocan para eso.

## Dónde está

La tabla `mypump_ajustes_dieta` (migración `supabase/migrations/nativa_004_ajustes_dieta.sql`, **aplicada el 20-oct**
con el OK de Mati). Hay una fila por cliente y por día:

| Columna | Qué es |
|---|---|
| `cliente_id`, `fecha` | La clave. La fecha es la del teléfono del cliente |
| `dieta_id` | La dieta activa ese día (la de `mypump_dietas`) |
| `tipo_dia` | El tipo de día elegido (entreno/descanso) en dietas con `tipos_dia`; si no, null |
| `ajustes` | `{comida_id: {deltaKcal, compensar, omitida, opcion, cantidades, anclas}}`. `{}` = volvió al plan (la fila no se borra) |
| `resumen` | `[{comida_id, nombre, kcal_plan, kcal_dia, omitida}]`, cómo le quedó cada comida. null si `ajustes` es `{}` |
| `kcal_plan`, `kcal_dia` | El total del día: el plan y lo que quedó con los ajustes |
| `actualizado_en` | El último cambio del día |

Lo que significa cada campo de `ajustes`:
- `deltaKcal` son las kcal que sumó (+) o restó (−) a esa comida, de a 50.
- `compensar`: si es true, la diferencia de esa comida pasa a la siguiente.
- `omitida`: «Hoy no la como».
- `opcion` es la opción elegida (0 = A).
- `cantidades` son los gramos o unidades puestos a mano por posición del alimento (`anclas` dice a qué alimento va cada
  una).

## Lectura sugerida

En el Cerebro (rol `authenticated`, con RLS) se lee directo de la tabla. Ejemplo para la semana de un cliente:

```sql
SELECT fecha, kcal_plan, kcal_dia, resumen, ajustes
  FROM mypump_ajustes_dieta
 WHERE cliente_id = $1 AND fecha >= CURRENT_DATE - 7 AND ajustes <> '{}'::jsonb
 ORDER BY fecha;
```

Para un brief alcanza con:
- cuántos días ajustó;
- la diferencia promedio del día (`kcal_dia − kcal_plan`);
- qué comidas saltea seguido (`omitida`, por ejemplo el pre-entreno);
- dónde suma y dónde resta (`deltaKcal` por comida).

Con la app, `mypump_get_ajustes_dieta(p_token, p_desde, p_hasta)` devuelve lo mismo de a 31 días como mucho. Es la
que usa el teléfono del cliente.

## Lo que no hay que suponer

- **No es «Comí / Salté».** Es el plan del día ajustado por el cliente, no lo que comió.
- **Solo desde la 2.0.1 de las apps.** Los que se hicieron antes de la migración (en un TestFlight) suben solos la
  próxima vez que se abre la app.
- **Las kcal del resumen ya vienen redondeadas** a porciones servibles. Pueden diferir en unas pocas kcal de lo pedido.
