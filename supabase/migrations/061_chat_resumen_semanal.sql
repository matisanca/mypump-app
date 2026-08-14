-- =============================================================
-- 061_chat_resumen_semanal.sql — lo que el cliente dijo deja de ser un log
--
-- POR QUÉ EXISTE
-- Con las fases 0-4, el cliente ahora escribe. Pero eso vive solo en el hilo del
-- chat: para saber qué le pasó a alguien en la semana hay que abrir su
-- conversación y leerla. Con 62 clientes, eso no se hace, y lo que dijeron se
-- pierde exactamente igual que se perdía en WhatsApp.
--
-- Acá cierra el círculo: lo que el cliente escribió pasa a ser una entrada más
-- del seguimiento semanal, al lado del check y del peso — insumo del análisis y
-- de la programación del próximo bloque, no un registro que nadie mira.
--
-- POR QUÉ UNA TABLA APARTE Y NO UNA COLUMNA EN mypump_analisis_semanal
-- `persist_analisis` (centinela.py) PISA la fila de análisis en cada corrida, y
-- corre de lunes a jueves. Si el resumen del chat viviera ahí, la corrida del
-- jueves borraría lo que el cliente escribió el martes. La tabla separada es lo
-- único que garantiza que no se pierda.
--
-- IDEMPOTENTE.
-- =============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS mypump_chat_resumen (
  cliente_id    text        NOT NULL,
  semana_lunes  date        NOT NULL,
  -- Lo escribe el centinela con Codex, igual que el resto del análisis. Puede
  -- quedar NULL: entonces el panel muestra los mensajes crudos, que ya es
  -- muchísimo más que nada.
  resumen       text,
  mensajes      integer     NOT NULL DEFAULT 0,
  del_cliente   integer     NOT NULL DEFAULT 0,
  escalados     integer     NOT NULL DEFAULT 0,
  creado_en     timestamptz NOT NULL DEFAULT now(),
  actualizado   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_id, semana_lunes)
);

ALTER TABLE mypump_chat_resumen ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin all mypump_chat_resumen" ON mypump_chat_resumen;
CREATE POLICY "admin all mypump_chat_resumen" ON mypump_chat_resumen
  FOR ALL USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ── La conversación de la semana, cruda ──────────────────────────────────
--
-- Lo que el panel muestra abajo del check. Sin resumen de IA todavía, esto solo
-- ya sirve: son las cinco líneas que el cliente escribió, en un lugar donde
-- Mati las va a ver mientras decide el ajuste.
--
-- `p_semana` en NULL = la semana actual. Se pasa explícito para poder mirar
-- hacia atrás desde el panel sin tener que calcular el lunes en el front, que
-- es donde ya se rompió una vez por zona horaria (ver mig 020/026/028).
CREATE OR REPLACE FUNCTION mypump_chat_semana(
  p_cliente_id text,
  p_semana     date DEFAULT NULL
)
RETURNS TABLE (
  autor      text,
  contenido  text,
  origen     text,
  created_at timestamptz
)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT m.autor, m.contenido, m.origen, m.created_at
  FROM mypump_comentarios m
  WHERE m.cliente_id = p_cliente_id
    AND m.ambito = 'general'
    AND m.created_at >= COALESCE(p_semana,
          (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date)
    AND m.created_at < COALESCE(p_semana,
          (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date) + 7
  -- El `, m.id` desempata. Dos mensajes con el MISMO created_at ordenarian
  -- distinto en cada llamada, y el panel mostraria la conversacion en un orden
  -- que cambia al refrescar. Pasa poco, pero cuando pasa se ve como un bug de
  -- la app y no hay forma de reproducirlo.
  ORDER BY m.created_at, m.id
  LIMIT 200;
$$;

REVOKE ALL ON FUNCTION mypump_chat_semana(text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_semana(text, date) TO authenticated, service_role;

-- ── Guardar el resumen ───────────────────────────────────────────────────
--
-- Los contadores se calculan ACÁ y no los manda quien llama: si el centinela
-- corre dos veces, o si alguna vez lo llama otra cosa, los números salen de la
-- misma fuente y no de lo que cada llamador creyó contar.
CREATE OR REPLACE FUNCTION mypump_chat_resumen_guardar(
  p_cliente_id text,
  p_resumen    text,
  p_semana     date DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_sem date := COALESCE(p_semana,
    (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date);
  v_tot int; v_cli int; v_esc int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE autor = 'cliente')
    INTO v_tot, v_cli
  FROM mypump_comentarios
  WHERE cliente_id = p_cliente_id AND ambito = 'general'
    AND created_at >= v_sem AND created_at < v_sem + 7;

  SELECT count(*) INTO v_esc FROM mypump_chat_estado
   WHERE cliente_id = p_cliente_id AND escalado;

  INSERT INTO mypump_chat_resumen
    (cliente_id, semana_lunes, resumen, mensajes, del_cliente, escalados)
  VALUES (p_cliente_id, v_sem, p_resumen, v_tot, v_cli, v_esc)
  ON CONFLICT (cliente_id, semana_lunes) DO UPDATE SET
    -- El resumen viejo NO se pisa con NULL. Una corrida que falló al generar no
    -- puede borrar lo que la corrida anterior sí había escrito.
    resumen     = COALESCE(EXCLUDED.resumen, mypump_chat_resumen.resumen),
    mensajes    = EXCLUDED.mensajes,
    del_cliente = EXCLUDED.del_cliente,
    escalados   = EXCLUDED.escalados,
    actualizado = now();
END;
$$;

REVOKE ALL ON FUNCTION mypump_chat_resumen_guardar(text, text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_resumen_guardar(text, text, date) TO authenticated, service_role;

-- ── Quién habló esta semana ──────────────────────────────────────────────
--
-- Para que la ronda del jueves reciba el chat como una entrada más, sin tener
-- que pedir 62 hilos de a uno.
CREATE OR REPLACE FUNCTION mypump_chat_actividad_semana(p_semana date DEFAULT NULL)
RETURNS TABLE (
  cliente_id  text,
  nombre      text,
  del_cliente integer,
  del_coach   integer,
  de_la_ia    integer,
  escalado    boolean,
  ultimo      text
)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  WITH sem AS (
    SELECT COALESCE(p_semana,
      (date_trunc('week', now() AT TIME ZONE 'America/Argentina/Buenos_Aires'))::date) AS d
  )
  SELECT
    c.cliente_id,
    c.nombre,
    count(*) FILTER (WHERE m.autor = 'cliente')::integer,
    count(*) FILTER (WHERE m.autor = 'coach')::integer,
    count(*) FILTER (WHERE m.origen = 'ia')::integer,
    COALESCE(e.escalado, FALSE),
    (SELECT x.contenido FROM mypump_comentarios x
      WHERE x.cliente_id = c.cliente_id AND x.ambito = 'general' AND x.autor = 'cliente'
      ORDER BY x.created_at DESC, x.id DESC LIMIT 1)
  -- CROSS JOIN explícito y no `FROM a, sem`: mezclar la coma con un JOIN deja
  -- a `sem` fuera del alcance del ON, y Postgres rechaza la función entera con
  -- un "invalid reference to FROM-clause entry" que no dice cuál es el problema.
  FROM mypump_comentarios m
  JOIN mypump_clientes c ON c.cliente_id = m.cliente_id
  LEFT JOIN mypump_chat_estado e ON e.cliente_id = m.cliente_id
  CROSS JOIN sem
  WHERE m.ambito = 'general'
    AND m.created_at >= sem.d AND m.created_at < sem.d + 7
  GROUP BY c.cliente_id, c.nombre, e.escalado
  HAVING count(*) FILTER (WHERE m.autor = 'cliente') > 0
  ORDER BY count(*) FILTER (WHERE m.autor = 'cliente') DESC;
$$;

REVOKE ALL ON FUNCTION mypump_chat_actividad_semana(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mypump_chat_actividad_semana(date) TO authenticated, service_role;

COMMIT;
