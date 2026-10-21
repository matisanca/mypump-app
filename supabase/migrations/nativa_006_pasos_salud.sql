-- =============================================================================
-- nativa_006 — los pasos de Salud de la app, una sola cuenta para la ficha y el brief
--
-- Mati (21-oct-2026): «los que usan la app pump team y conectaron con salud
-- tienen los pasos actuales, esos deberían figurar en la ficha de cada uno y en
-- sus briefs siempre». Eligió el promedio de los últimos 7 días COMPLETOS (el de
-- hoy siempre está a medias), con cuántos de esos días tienen dato y la fecha del
-- último. Si no hay datos de la semana, la ficha y el brief usan los pasos del
-- formulario.
--
-- Solo lectura: una vista sobre mypump_salud_diaria, que escriben las apps cada
-- vez que se abren (Apple Salud en iPhone, Health Connect en Android). Con
-- security_invoker, quien la lee ve lo que su rol ve de la tabla: el Cerebro
-- como authenticated y el bot con la service key. anon no la lee.
--
-- Volver atrás: DROP VIEW public.mypump_pasos_salud;
-- =============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.mypump_pasos_salud WITH (security_invoker = true) AS
WITH hoy AS (
  SELECT (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS d
), dias AS (
  -- Un valor por día. Si un día llegó de dos fuentes (cambió de teléfono), el mayor.
  SELECT s.cliente_id, s.fecha, max(s.valor) AS pasos,
         string_agg(DISTINCT s.fuente, ',' ORDER BY s.fuente) AS fuente,
         max(s.updated_at) AS escrito
  FROM mypump_salud_diaria s, hoy
  WHERE s.tipo = 'pasos'
    AND s.fuente <> 'manual'
    AND s.fecha >= hoy.d - 30
    AND s.fecha < hoy.d          -- hoy no: está a medias
  GROUP BY s.cliente_id, s.fecha
)
SELECT d.cliente_id,
       round(avg(d.pasos) FILTER (WHERE d.fecha >= hoy.d - 7))::integer AS promedio_7d,
       count(*) FILTER (WHERE d.fecha >= hoy.d - 7)::integer           AS dias_7d,
       max(d.fecha)                                                     AS ultima_fecha,
       (array_agg(d.pasos ORDER BY d.fecha DESC))[1]::integer          AS ultimo_dia,
       (array_agg(d.fuente ORDER BY d.fecha DESC))[1]                  AS fuente,
       max(d.escrito)                                                   AS ultima_sync
FROM dias d, hoy
GROUP BY d.cliente_id, hoy.d;

COMMENT ON VIEW public.mypump_pasos_salud IS
  'Pasos de Salud por cliente: promedio de los últimos 7 días completos (promedio_7d), cuántos tienen dato (dias_7d), '
  'el último día completo (ultima_fecha, ultimo_dia) y cuándo sincronizó la app (ultima_sync). Mira 30 días. nativa_006.';

REVOKE ALL ON public.mypump_pasos_salud FROM PUBLIC, anon;
GRANT SELECT ON public.mypump_pasos_salud TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
