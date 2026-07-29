-- =============================================================
-- 050 — Las 4 funciones de análisis eran ejecutables con la anon key
--
-- La anon key es PÚBLICA: viaja en public/js/config.js y en panel.html, o sea
-- que la tiene cualquiera que abra la app. Estas cuatro funciones son de coach
-- y estaban abiertas:
--
--   mypump_get_analisis_pendientes  LEE   el análisis semanal de TODOS
--   mypump_get_analisis_cliente     LEE   el historial de cualquier cliente
--   mypump_resolver_analisis        ESCRIBE  marca un análisis como resuelto
--   mypump_upsert_analisis          ESCRIBE  crea o pisa el análisis de un cliente
--
-- VERIFICADO EN PRODUCCIÓN antes de arreglar: un POST a
-- /rest/v1/rpc/mypump_get_analisis_pendientes con la anon key devolvió
-- HTTP 200 y 9 filas, con cliente_id, nombre, mensaje_cliente,
-- sugerencia_coach y banderas. Nombres de clientes y material del coach,
-- legibles por cualquiera.
--
-- La más grave es mypump_upsert_analisis: no filtra datos, los INYECTA.
-- Permite escribir el texto de `sugerencia_coach` y `mensaje_ajuste` que Mati
-- lee en el panel y sobre el que decide ajustes. Una fuga se nota tarde; un
-- dato falso que parece propio, nunca.
--
-- POR QUÉ NO SALTÓ ANTES: la migración 041 cerró las funciones de salud
-- (mypump_ingest_salud_service, _mypump_upsert_salud) pero estas son de la 039
-- y quedaron afuera del barrido. `GRANT ... TO service_role` NO cierra nada:
-- es un no-op sobre un permiso que Postgres ya abrió a PUBLIC por default.
-- Hace falta el REVOKE explícito.
--
-- DOBLE CIERRE, a propósito:
--   1. REVOKE del rol anon (el ACL).
--   2. Guarda `auth.role()` DENTRO de la función.
-- El ACL solo no alcanza: un `DROP FUNCTION` futuro lo resetea a PUBLIC y
-- reabre el agujero en silencio — ya pasó con la 041. La guarda interna viaja
-- con el cuerpo de la función y sobrevive a eso.
--
-- Las dos primeras eran LANGUAGE sql, que no admite IF: pasan a plpgsql. El
-- cuerpo es el mismo, envuelto en RETURN QUERY.
--
-- service_role SÍ entra: la mini (centinela.py) llama a mypump_upsert_analisis
-- con la service key. El panel del coach entra como `authenticated` — exige
-- sesión de Supabase (panel.html:663 corta si no hay), así que no se rompe.
--
-- VERIFICACIÓN:
--   curl -X POST "$URL/rest/v1/rpc/mypump_get_analisis_pendientes" \
--        -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
--        -H "Content-Type: application/json" -d '{}'
--   antes: HTTP 200 + 9 filas    ahora: {"message":"Acceso denegado"}
--
-- ROLLBACK: no toca datos ni esquema, solo cuerpos de función y permisos.
-- Para volver atrás se re-aplica la mig 039.
-- =============================================================

CREATE OR REPLACE FUNCTION mypump_get_analisis_pendientes(p_semana_lunes DATE DEFAULT NULL)
RETURNS TABLE(cliente_id text, nombre text, semana_lunes date, balde text,
              motivos jsonb, banderas jsonb, senales jsonb, mensaje_cliente text,
              sugerencia_coach text, mensaje_ajuste text, corrida_el timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  RETURN QUERY
  SELECT a.cliente_id, c.nombre, a.semana_lunes, a.balde, a.motivos,
         a.banderas, a.senales, a.mensaje_cliente, a.sugerencia_coach,
         a.mensaje_ajuste, a.corrida_el
  FROM mypump_analisis_semanal a
  LEFT JOIN mypump_clientes c ON c.cliente_id = a.cliente_id
  WHERE a.resuelto_el IS NULL
    AND a.balde = 'ajustar'
    AND a.semana_lunes = COALESCE(
          p_semana_lunes,
          (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::int - 1)))
        )
  ORDER BY a.corrida_el DESC;
END;
$$;

CREATE OR REPLACE FUNCTION mypump_get_analisis_cliente(p_cliente_id TEXT, p_limite INTEGER DEFAULT 8)
RETURNS SETOF mypump_analisis_semanal
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  RETURN QUERY
  SELECT * FROM mypump_analisis_semanal
  WHERE cliente_id = p_cliente_id
  ORDER BY semana_lunes DESC
  LIMIT GREATEST(1, p_limite);
END;
$$;

CREATE OR REPLACE FUNCTION mypump_resolver_analisis(p_cliente_id TEXT, p_semana_lunes DATE)
RETURNS mypump_analisis_semanal
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row mypump_analisis_semanal;
BEGIN
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  UPDATE mypump_analisis_semanal
    SET resuelto_el = NOW()
    WHERE cliente_id = p_cliente_id AND semana_lunes = p_semana_lunes
    RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION mypump_upsert_analisis(
  p_cliente_id TEXT, p_semana_lunes DATE, p_balde TEXT,
  p_motivos JSONB DEFAULT '[]'::jsonb, p_banderas JSONB DEFAULT '[]'::jsonb,
  p_senales JSONB DEFAULT '{}'::jsonb, p_mensaje_cliente TEXT DEFAULT NULL,
  p_sugerencia_coach TEXT DEFAULT NULL, p_mensaje_ajuste TEXT DEFAULT NULL
) RETURNS mypump_analisis_semanal
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row mypump_analisis_semanal;
BEGIN
  -- La que más importa cerrar: escribe el texto que el coach lee y sobre el
  -- que decide. La llama el centinela desde la mini, con la service key.
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  INSERT INTO mypump_analisis_semanal (
    cliente_id, semana_lunes, balde, motivos, banderas, senales,
    mensaje_cliente, sugerencia_coach, mensaje_ajuste, corrida_el
  ) VALUES (
    p_cliente_id, p_semana_lunes, p_balde, p_motivos, p_banderas, p_senales,
    p_mensaje_cliente, p_sugerencia_coach, p_mensaje_ajuste, NOW()
  )
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE SET
    balde            = EXCLUDED.balde,
    motivos          = EXCLUDED.motivos,
    banderas         = EXCLUDED.banderas,
    senales          = EXCLUDED.senales,
    mensaje_cliente  = EXCLUDED.mensaje_cliente,
    sugerencia_coach = EXCLUDED.sugerencia_coach,
    mensaje_ajuste   = EXCLUDED.mensaje_ajuste,
    corrida_el       = NOW(),
    resuelto_el      = CASE
                         WHEN mypump_analisis_semanal.balde = EXCLUDED.balde
                           THEN mypump_analisis_semanal.resuelto_el
                         ELSE NULL
                       END
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- ── Permisos ─────────────────────────────────────────────────
REVOKE ALL ON FUNCTION mypump_get_analisis_pendientes(DATE)         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION mypump_get_analisis_cliente(TEXT, INTEGER)   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION mypump_resolver_analisis(TEXT, DATE)         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION mypump_get_analisis_pendientes(DATE)       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_get_analisis_cliente(TEXT, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_resolver_analisis(TEXT, DATE)       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION mypump_upsert_analisis(TEXT, DATE, TEXT, JSONB, JSONB, JSONB, TEXT, TEXT, TEXT)
  TO authenticated, service_role;

-- Estas dos ya tenían la guarda interna `auth.role()`, así que no estaban
-- expuestas. Se les saca anon igual para que la regla quede pareja: NINGUNA
-- función de coach es ejecutable con la anon key. Depender de una sola línea
-- adentro de la función es cómodo hasta que alguien la toca.
REVOKE ALL ON FUNCTION mypump_coach_comentar(TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_coach_comentar(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION mypump_get_adherencia_global() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_get_adherencia_global() TO authenticated, service_role;

-- Auditoría: toda función de coach debería quedar SIN anon en su ACL.
--   SELECT proname, array_to_string(proacl,' | ') FROM pg_proc
--    WHERE proname ~ 'global|coach|analisis' AND array_to_string(proacl,'') LIKE '%anon=%'
--      AND prorettype <> 'trigger'::regtype::oid;
