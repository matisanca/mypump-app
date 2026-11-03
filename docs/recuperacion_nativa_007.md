# nativa_007: correcciones del motor de recuperación (prueba antes de aplicar)

Estado: **sin aplicar**. Incluye la opción B (score con la información que
haya, más `confianza`) y las correcciones de las revisiones de d232c45 y 13c8505.

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

## Antes / después (tercera versión, 3-nov)

Cambios de esta versión: tope del sueño en 0 con noche corta, pisos al desvío
(FC 2 lpm, ln VFC 0,05), confianza baja achicada hacia 50 y el INTERRUPTOR
`baja_sin_score` al principio de calc (prendido por defecto: confianza baja =
sin score). Los datos de hoy cambiaron un poco respecto de la corrida anterior
(nueva sincronización), por eso «hoy» difiere levemente.

| | hoy | 007 interruptor PRENDIDO | 007 interruptor APAGADO |
|---|---|---|---|
| días con score | 133 | 72 | 143 |
| `calibrando` | 3 | 16 | 16 |
| `insuficiente` | 214 | 262 | 191 |
| confianza alta / media / baja | – | 36 / 36 / 71 (baja sin score) | 36 / 36 / 71 |
| días que ya tenían score y siguen | – | 72 | 132 |
| dif. media / mediana de la dif. absoluta / máx | – | −1,0 / 1 / 26 | −0,5 / 3 / 26 |
| dif. absoluta ≥ 10 / ≥ 15 / ≥ 20 | – | 7 / 2 / 2 | 32 / 14 / 8 |
| bandas iguales | – | 65 | 105 |
| bandas que cambian | – | 7 (4 media→baja, 3 media→alta) | 27 (13 alta→media, 6 baja→media, 4 media→alta, 4 media→baja) |
| pierden el score | – | 61 (todos de confianza baja) | 1 |
| días con HRV usada | 126 | 46 | 46 |
| discordancia: días / cambios día a día | 14 / 14 | 15 / 2 | 15 / 2 |

Con el interruptor apagado, ningún día de confianza baja queda ≤ 20 ni ≥ 80
(por construcción, el achique deja la confianza baja entre 25 y 75).

Caso sintético (cliente inexistente, dentro de la transacción; 30 días de FC
en reposo y hoy FC alta, componente autonómico = 10):

| | apagado | prendido |
|---|---|---|
| solo FC | 30 (baja, achicado) | sin score (baja) |
| FC + noche de 1 h | 5 (media, sueño 0) | 5 |
| FC + 1 h con 3 noches previas de 8 h | 5 (sueño 0) | 5 |

## Antes de aplicar

1. OK de Mati.
2. Aplicar `supabase/migrations/nativa_007_recuperacion_correcciones.sql`.
   Para volver atrás: `supabase/migrations/nativa_007_revert.sql`.
3. Regenerar `docs/ESQUEMA_PRODUCCION.txt` y el `devuelve` de
   `mypump_get_recuperacion` en `apps/shared/contrato.json`.
4. Las apps siguen andando sin cambios; mostrar `motivo_falta` y
   `confianza` es un cambio aparte.
