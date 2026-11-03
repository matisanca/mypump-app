# nativa_007: correcciones del motor de recuperación (prueba antes de aplicar)

Estado: **sin aplicar**. Incluye la opción B (score con la información que
haya, más `confianza`) y las correcciones de la revisión de d232c45.

Prueba (3-nov-2026), en producción dentro de una transacción con ROLLBACK:
- 007 aplicada → comparación → `nativa_007_revert.sql` aplicado en la misma
  transacción → md5 de `pg_get_functiondef` y ACL de las cinco funciones
  idénticos a los de hoy, y calc vuelve a devolver exactamente lo mismo.
- Después del ROLLBACK, producción quedó igual a antes (md5 + ACL) y sin
  `motivo_falta`/`confianza`.
- Dentro de la transacción `get_recuperacion` (por token), `_cliente_coach`,
  `_resumen` y `_global` devolvieron filas sin error.

## Alcance

25 clientes activos con FC en reposo, HRV o sueño en los últimos 90 días;
últimos 14 días = 350 días-cliente.

## Antes / después (opción B)

| | hoy | con 007 |
|---|---|---|
| días con score | 131 | 141 |
| `calibrando` | 3 | 16 |
| `insuficiente` (ni FC en reposo ni sueño) | 216 | 193 |
| días con HRV usada | 124 | 44 |
| días con componente de carga | 146 | 138 |
| días con discordancia | 14 | 15 |
| cambios de discordancia de un día al otro | 14 | 2 |

Confianza de los 141 días con score: alta 34, media 36, baja 71. Los 11
días que hoy no tienen score y pasan a tenerlo son todos de confianza baja.

Días que ya tenían score (n = 130):
- diferencia media +2,0; |dif| media 5,6; mediana 3; máxima 38.
- |dif| ≥ 10: 26; **|dif| ≥ 15: 13**; |dif| ≥ 20: 10.
- histograma (tramos de 5): −35:1, −15:4, −10:13, −5:21, 0:63, +5:9,
  +10:7, +15:3, +20:3, +25:2, +30:3, +35:1.
- bandas: 69 media→media, 32 alta→alta, 4 baja→baja; 14 media→alta,
  4 baja→media, 3 alta→media, 4 media→baja; 1 media→sin score.

Noche real de menos de 3 h sin otra fuente (caso de la revisión, 24-oct):
ahora cuenta como sueño corto (componente sueño 0); el score queda en 65
(hoy 55; la versión anterior de 007 daba 88). La diferencia restante viene de
la HRV descartada.

## Ejemplos (id = md5 del cliente, 6 caracteres; score de los 14 días)

```
20887d hoy  -  -  -  -  -  -  -  -  -  -  -  -  -  -
       007  71 61 63 59 24 69 45 -  -  -  -  -  -  -    (solo FC + otros: confianza baja)
c811ec hoy  27 -  47 46 36 41 41 30 50 26 40 55 74 -
       007  40 -  77 72 74 71 54 57 53 43 70 63 90 -
9eabfa hoy  -  -  -  -  -  -  -  -  -  -  -  -  49 -
       007  -  -  -  -  -  -  -  -  -  -  71 66 46 -
25bc56 hoy  57 47 53 -  45 52 56 69 69 64 57 48 69 68
       007  72 50 50 5  35 74 53 68 78 69 48 48 61 36
5fa3cd hoy  29 51 62 79 49 77 32 65 33 64 50 80 86 -
       007  29 51 85 79 63 77 43 60 24 58 64 70 83 -
```

## Antes de aplicar

1. OK de Mati.
2. Aplicar `supabase/migrations/nativa_007_recuperacion_correcciones.sql`.
   Para volver atrás: `supabase/migrations/nativa_007_revert.sql`.
3. Regenerar `docs/ESQUEMA_PRODUCCION.txt` y el `devuelve` de
   `mypump_get_recuperacion` en `apps/shared/contrato.json`.
4. Las apps siguen andando sin cambios; mostrar `motivo_falta` y
   `confianza` es un cambio aparte.
