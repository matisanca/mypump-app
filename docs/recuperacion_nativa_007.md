# nativa_007: correcciones del motor de recuperación (prueba antes de aplicar)

Estado: **sin aplicar**. Se corrió en producción dentro de una transacción con
ROLLBACK (3-nov-2026). Después del ROLLBACK, las definiciones y los permisos de
las cinco funciones de recuperación son idénticos a los de antes (md5 de
`pg_get_functiondef` + ACL), y `motivo_falta` no existe en producción.

## Alcance de la prueba

- 25 clientes activos con FC en reposo, HRV o sueño en los últimos 90 días.
- Últimos 14 días: 350 días-cliente, antes y después.
- Dentro de la transacción, `get_recuperacion` (por token), `_cliente_coach`,
  `_resumen` y `_global` siguieron devolviendo filas sin error.

## Resultado agregado

| | antes | después |
|---|---|---|
| días con score (`ok`) | 131 | 108 |
| días `insuficiente` | 216 | 240 |
| días con HRV usada | 124 | 44 |
| días con componente de carga | 146 | 138 |
| días con discordancia | 14 | 15 |
| cambios de discordancia de un día al otro | 14 | 2 |

- Score con valor en los dos (n = 108): diferencia media +2,7; |dif| media 5,2;
  mediana 2; máxima 33; 18 días con |dif| ≥ 10 y 8 con ≥ 20.
- Bandas: 59 media→media, 30 alta→alta, 4 baja→baja, 10 media→alta,
  3 baja→media, 2 alta→media; 23 días pasan a sin banda (ok→insuficiente).
- Los 23 ok→insuficiente son días sin sueño cuyo score se apoyaba en HRV de
  día o de 1-2 lecturas: sin ella el bloque autonómico pesa 30 (solo FC) y
  30 + 8 (otros) no llega a 45. Ahora reciben `motivo_falta`.
- Variante con SDNN n ≥ 2 en vez de 3: 110 días con score (en vez de 108) y 59
  con HRV (en vez de 44). La pérdida grande viene de excluir la HRV de día.

## Ejemplos (id = md5 del cliente, 6 caracteres; score de los 14 días)

```
94177a antes   65 88 53 36 39 -  66 -  -  -  -  -  -  -
       después -  -  -  -  -  -  -  -  -  -  -  -  -  -     (solo HRV de día/madrugada n=1, sin sueño)
25bc56 antes   57 47 53 -  45 52 56 69 69 64 57 48 69 68
       después -  -  -  -  -  74 53 68 78 69 48 48 61 -
c811ec antes   27 -  47 46 36 41 41 30 50 26 40 55 74 -
       después -  -  -  72 -  71 54 57 53 43 70 63 90 -
925341 antes   76 64 77 -  -  34 42 65 65 69 82 71 -  -
       después 73 -  74 -  -  -  -  70 63 66 70 -  -  -
8ac1ef antes   58 61 42 42 40 41 44 34 36 39 40 -  -  -
       después 59 64 39 45 38 38 36 -  -  -  38 -  -  -     (noches < 3 h ya no cuentan)
```

## Antes de aplicar

1. OK de Mati.
2. Aplicar `supabase/migrations/nativa_007_recuperacion_correcciones.sql`.
3. Regenerar `docs/ESQUEMA_PRODUCCION.txt` y el `devuelve` de
   `mypump_get_recuperacion` en `apps/shared/contrato.json`.
4. Las apps no necesitan cambios para seguir andando; mostrar `motivo_falta`
   es un cambio aparte.
