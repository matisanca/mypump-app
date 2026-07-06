-- ============================================================
-- 024 — Próximo macrociclo: datos de rendimiento + aviso semana 11/12
-- ============================================================
-- Soporta la feature "generar próximo macrociclo (semanas 13-24)":
--  1) mypump_get_progresion_cargas   → mejor set por sesión/ejercicio (el
--     Cerebro ya la llama desde mesociclo-engine.js: obtenerCargasMyPump()).
--  2) mypump_get_adherencia_macrociclo → sesiones finalizadas por semana.
--  3) mypump_reset_semana            → arrancar la fase nueva en semana 1
--     (mypump_publicar_cliente preserva semana_actual a propósito).
--  4) trg_mypump_notify_semana       → cuando el cliente ENTRA a semana 11 o
--     12, POST al bot (mismo patrón pg_net + Vault que 019) → WhatsApp a Mati.
--
-- Los 3 RPCs reciben cliente_id directo (no token): SOLO authenticated
-- (Cerebro). Nunca anon.
-- ============================================================

-- ── 1) Mejor set por sesión y ejercicio (ventana de p_semanas) ──
-- Forma de salida acoplada a mesociclo-engine.js → obtenerCargasMyPump():
--   fecha, ejercicio, peso_realizado, reps_realizadas  (+ extras para el
--   contexto de generación: ejercicio_id, rir_real, semana, e1rm).
CREATE OR REPLACE FUNCTION mypump_get_progresion_cargas(
  p_cliente_id TEXT,
  p_semanas    INTEGER DEFAULT 12
)
RETURNS TABLE(
  fecha           DATE,
  ejercicio       TEXT,
  ejercicio_id    TEXT,
  peso_realizado  NUMERIC,
  reps_realizadas INTEGER,
  rir_real        INTEGER,
  semana          INTEGER,
  e1rm            NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT ON (r.sesion_id, r.ejercicio_id)
         r.registrado_en::date                                   AS fecha,
         r.ejercicio_nombre                                      AS ejercicio,
         r.ejercicio_id,
         r.peso_kg                                               AS peso_realizado,
         r.reps_realizadas,
         r.rir_real,
         s.semana,
         ROUND(r.peso_kg * (1 + r.reps_realizadas / 30.0), 1)    AS e1rm
    FROM mypump_registros_carga r
    JOIN mypump_sesiones s ON s.id = r.sesion_id
   WHERE r.cliente_id = p_cliente_id
     AND r.registrado_en >= NOW() - make_interval(days => GREATEST(p_semanas, 1) * 7)
     AND r.peso_kg > 0
     AND r.reps_realizadas > 0
   ORDER BY r.sesion_id, r.ejercicio_id,
            (r.peso_kg * (1 + r.reps_realizadas / 30.0)) DESC;
$$;

REVOKE ALL ON FUNCTION mypump_get_progresion_cargas(TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION mypump_get_progresion_cargas(TEXT, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION mypump_get_progresion_cargas(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION mypump_get_progresion_cargas(TEXT, INTEGER) TO service_role;

-- ── 2) Adherencia: sesiones finalizadas por semana vs días del plan ──
CREATE OR REPLACE FUNCTION mypump_get_adherencia_macrociclo(
  p_cliente_id TEXT
)
RETURNS TABLE(
  semana                INTEGER,
  sesiones_finalizadas  INTEGER,
  dias_plan             INTEGER
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH rutina AS (
    SELECT id, estructura
      FROM mypump_rutinas
     WHERE cliente_id = p_cliente_id AND estado = 'activa'
     LIMIT 1
  ),
  dias AS (
    -- Días reales del plan (excluye comodines, que reemplazan a otros días)
    SELECT COUNT(*)::int AS n
      FROM rutina, jsonb_array_elements(rutina.estructura->'dias') d
     WHERE COALESCE((d->>'es_comodin')::boolean, FALSE) = FALSE
  )
  SELECT s.semana,
         COUNT(*) FILTER (WHERE s.finalizada_en IS NOT NULL)::int AS sesiones_finalizadas,
         (SELECT n FROM dias)                                     AS dias_plan
    FROM mypump_sesiones s
    JOIN rutina r ON r.id = s.rutina_id
   WHERE s.cliente_id = p_cliente_id
   GROUP BY s.semana
   ORDER BY s.semana;
$$;

REVOKE ALL ON FUNCTION mypump_get_adherencia_macrociclo(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION mypump_get_adherencia_macrociclo(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION mypump_get_adherencia_macrociclo(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION mypump_get_adherencia_macrociclo(TEXT) TO service_role;

-- ── 3) Reset de semana al publicar una fase nueva ──
CREATE OR REPLACE FUNCTION mypump_reset_semana(
  p_cliente_id TEXT,
  p_semana     INTEGER DEFAULT 1
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total INTEGER;
  v_nueva INTEGER;
BEGIN
  SELECT COALESCE((estructura->>'semanas_total')::int, 12)
    INTO v_total
    FROM mypump_rutinas
   WHERE cliente_id = p_cliente_id AND estado = 'activa'
   LIMIT 1;

  IF v_total IS NULL THEN
    RETURN NULL; -- sin rutina activa
  END IF;

  v_nueva := LEAST(GREATEST(COALESCE(p_semana, 1), 1), v_total);

  UPDATE mypump_rutinas
     SET semana_actual = v_nueva,
         updated_at    = NOW()
   WHERE cliente_id = p_cliente_id AND estado = 'activa';

  RETURN v_nueva;
END;
$$;

REVOKE ALL ON FUNCTION mypump_reset_semana(TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION mypump_reset_semana(TEXT, INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION mypump_reset_semana(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION mypump_reset_semana(TEXT, INTEGER) TO service_role;

-- ── 4) Aviso al bot cuando el cliente ENTRA a semana 11 o 12 ──
-- Mismo patrón que 019 (pg_net async + secreto en Vault). El POST es
-- best-effort: si el bot está caído, el avance de semana igual se guarda.
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION mypump_notify_coach_semana()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_secret TEXT;
  v_total  INTEGER;
BEGIN
  v_total := COALESCE((NEW.estructura->>'semanas_total')::int, 12);

  -- Solo al ENTRAR (cambio real) a las últimas 2 semanas del plan activo
  IF NEW.estado = 'activa'
     AND NEW.semana_actual IS DISTINCT FROM OLD.semana_actual
     AND NEW.semana_actual >= v_total - 1 THEN

    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets
     WHERE name = 'mypump_notify_secret'
     LIMIT 1;

    PERFORM net.http_post(
      url     := 'https://bot.mypumpteam.com/mypump/semana',
      headers := jsonb_build_object(
                   'Content-Type',    'application/json',
                   'X-Mypump-Secret', COALESCE(v_secret, '')
                 ),
      body    := jsonb_build_object(
                   'cliente_id',    NEW.cliente_id,
                   'semana_actual', NEW.semana_actual,
                   'semanas_total', v_total,
                   'version',       NEW.version
                 )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mypump_notify_semana ON mypump_rutinas;
CREATE TRIGGER trg_mypump_notify_semana
  AFTER UPDATE OF semana_actual ON mypump_rutinas
  FOR EACH ROW EXECUTE FUNCTION mypump_notify_coach_semana();
