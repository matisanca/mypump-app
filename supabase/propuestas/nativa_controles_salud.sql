-- nativa_controles_salud.sql — PROPUESTA, SIN APLICAR.
--
-- «Tu próximo control de salud» (pedido de Mati, 11/11): el alumno ve en la app cuándo le toca el próximo control y,
-- desde `avisar_desde`, una tarjeta arriba de todo que lo lleva a Estudios. La app solo LEE. Escriben el servidor y sus
-- dueños (el vigía y Entregas de AUTOMATIZAR ENTREGAS, Sistema base, Mati), con la clave de servicio o como dueño de la base.
-- Diseño: nativa-evidencia/privado/CONTROLES_SALUD.md.
--
-- Sale APAGADO: `controles_app` en false. Prendida, la app además necesita `estudios_app` (la tarjeta lleva a Estudios).
-- Se puede aplicar antes o después de nativa_estudios.sql: si `mypump_estudios_pedidos` ya existe, `pedido_estudio_id`
-- queda con su clave foránea; si no, la suma una segunda pasada de este mismo archivo (es idempotente).
--
-- Invariantes:
--   · El `cliente_id` sale siempre del token. La app recibe solo titulo_alumno, fecha_objetivo, avisar_desde y estado:
--     nunca el tipo crudo, ni la nota de Mati, ni ids, ni el origen.
--   · `titulo_alumno` no puede nombrar el ciclo, fármacos ni «IA» (CHECK). La app igual cae a «Control de salud».
--   · Una fila por (cliente_id, tipo, fecha_objetivo): el vigía hace upsert por esa clave.
--   · `avisar_desde` <= `fecha_objetivo`.
BEGIN;

-- ── Palanca: apagada ──
INSERT INTO mypump_app_config (clave, valor, nota) VALUES
  ('controles_app', 'false'::JSONB, 'Controles de salud en la app. true = el alumno ve su próximo control (la app además necesita estudios_app)')
ON CONFLICT (clave) DO NOTHING;

-- ── El título que ve el alumno: corto y sin nada del ciclo ──
-- Sin tildes ni mayúsculas para comparar. Palabras enteras: «ciclo», «posciclo», «fármaco», hormonas, siglas, «IA», dosis.
CREATE OR REPLACE FUNCTION mypump_controles_titulo_ok(p TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT p IS NOT NULL
     AND length(btrim(p)) BETWEEN 1 AND 60
     AND translate(lower(p), 'áéíóúüñ', 'aeiouun') !~ (
       '\m(ciclos?|posciclos?|post ?ciclos?|pct|trt|blast|cruise|farmac[a-z]*|testo[a-z]*|esteroid[a-z]*|anabolic[a-z]*|'
       || 'androgen[a-z]*|hormona[a-z]*|nandrolona|trembolona|oxandrolona|estanozolol|primobolan|boldenona|masteron|sarms?|'
       || 'peptidos?|dosis|mg|ml|ui|ia|inteligencia artificial)\M');
$$;

-- ── Tabla ──
CREATE TABLE IF NOT EXISTS mypump_controles_salud (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id        TEXT        NOT NULL CHECK (length(btrim(cliente_id)) > 0),
  tipo              TEXT        NOT NULL CHECK (tipo IN ('ciclo_intra', 'fin_posciclo', 'fin_trt_pre_ciclo', 'otro')),   -- interno
  titulo_alumno     TEXT        NOT NULL DEFAULT 'Control de salud' CHECK (mypump_controles_titulo_ok(titulo_alumno)),
  fecha_objetivo    DATE        NOT NULL,
  avisar_desde      DATE        NOT NULL,
  estado            TEXT        NOT NULL DEFAULT 'programado'
                                CHECK (estado IN ('programado', 'ordenes_enviadas', 'resultado_subido', 'revisado', 'cancelado')),
  pedido_estudio_id UUID,       -- el pedido de mypump_estudios_pedidos que lo cumple (FK abajo, si la tabla existe)
  resultado_en      TIMESTAMPTZ,  -- lo escribe el bot cuando el pedido queda completo y pasa a 'resultado_subido' (no se expone)
  origen            TEXT        NOT NULL CHECK (origen IN ('vigia', 'mati', 'entregas')),
  creado_en         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actualizado_en    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  nota_mati         TEXT        CHECK (char_length(nota_mati) <= 2000),                                                   -- solo Mati
  CONSTRAINT controles_ventana CHECK (avisar_desde <= fecha_objetivo),
  CONSTRAINT controles_clave UNIQUE (cliente_id, tipo, fecha_objetivo)
);
CREATE INDEX IF NOT EXISTS idx_mypump_controles_salud_abiertos ON mypump_controles_salud (cliente_id, fecha_objetivo)
  WHERE estado IN ('programado', 'ordenes_enviadas');

CREATE OR REPLACE FUNCTION mypump_controles_tocado()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  NEW.actualizado_en := NOW();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_mypump_controles_tocado ON mypump_controles_salud;
CREATE TRIGGER trg_mypump_controles_tocado BEFORE UPDATE ON mypump_controles_salud
  FOR EACH ROW EXECUTE FUNCTION mypump_controles_tocado();

-- La clave foránea al pedido de estudios, solo si Estudios ya está aplicado (y una sola vez).
DO $$
BEGIN
  IF to_regclass('public.mypump_estudios_pedidos') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'controles_pedido_fk'
                       AND conrelid = 'public.mypump_controles_salud'::regclass) THEN
    ALTER TABLE mypump_controles_salud ADD CONSTRAINT controles_pedido_fk
      FOREIGN KEY (pedido_estudio_id) REFERENCES mypump_estudios_pedidos (id) ON DELETE SET NULL;
  END IF;
END;
$$;

-- ── Propuestas de suplementación a partir de un estudio (solo el servidor) ──
-- La escribe el runner de BOT MINI y la lee el brief de AUTOMATIZAR ENTREGAS. La app no la toca: RLS prendido, sin RPC
-- para el alumno y sin GRANT a anon ni authenticated. `estudio_id` es el id del estudio en el bot (texto, sin clave foránea).
CREATE TABLE IF NOT EXISTS salud_suplementos_propuestas (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id        TEXT        NOT NULL CHECK (length(btrim(cliente_id)) > 0),
  estudio_id        TEXT        NOT NULL CHECK (length(btrim(estudio_id)) > 0),
  control_id        UUID        REFERENCES mypump_controles_salud (id) ON DELETE SET NULL,   -- el control que la originó, si hay
  pedido_id         UUID,       -- el pedido de mypump_estudios_pedidos (FK abajo, si la tabla existe)
  propuesta         JSONB       NOT NULL CHECK (jsonb_typeof(propuesta) IN ('object', 'array')),
  requiere_farmaco  BOOLEAN     NOT NULL DEFAULT FALSE,
  aviso_farmaco     TEXT        CHECK (char_length(aviso_farmaco) <= 2000),
  estado            TEXT        NOT NULL DEFAULT 'propuesta' CHECK (estado IN ('propuesta', 'sin_cambios', 'aplicada', 'descartada')),
  creado_en         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT propuestas_clave UNIQUE (estudio_id, cliente_id)
);
CREATE INDEX IF NOT EXISTS idx_salud_suplementos_propuestas_cliente ON salud_suplementos_propuestas (cliente_id, creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_salud_suplementos_propuestas_control ON salud_suplementos_propuestas (control_id) WHERE control_id IS NOT NULL;
-- La clave foránea al pedido, solo si Estudios ya está aplicado (y una sola vez), como la de los controles.
DO $$
BEGIN
  IF to_regclass('public.mypump_estudios_pedidos') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'propuestas_pedido_fk'
                       AND conrelid = 'public.salud_suplementos_propuestas'::regclass) THEN
    ALTER TABLE salud_suplementos_propuestas ADD CONSTRAINT propuestas_pedido_fk
      FOREIGN KEY (pedido_id) REFERENCES mypump_estudios_pedidos (id) ON DELETE SET NULL;
  END IF;
END;
$$;
ALTER TABLE salud_suplementos_propuestas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON salud_suplementos_propuestas FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON salud_suplementos_propuestas TO service_role;

ALTER TABLE mypump_controles_salud ENABLE ROW LEVEL SECURITY;
-- Sin políticas: ni anon ni authenticated la leen. Escribe el servidor.
REVOKE ALL ON mypump_controles_salud FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON mypump_controles_salud TO service_role;

REVOKE ALL ON FUNCTION mypump_controles_titulo_ok(TEXT), mypump_controles_tocado() FROM PUBLIC, anon, authenticated;
-- El CHECK corre con los permisos de quien escribe: el servidor la necesita.
GRANT EXECUTE ON FUNCTION mypump_controles_titulo_ok(TEXT) TO service_role;

-- ── La app, por token (anon y authenticated). NULL = token caído ──
-- {"habilitado": false} con la palanca apagada. Prendida:
-- {"habilitado": true, "hoy": "AAAA-MM-DD", "proximo": {...} | null, "ultimos": [{...}, …hasta 3]}
-- Cada control: {"titulo_alumno", "fecha_objetivo", "avisar_desde", "estado"}. Nada más.
-- `proximo`: el programado u órdenes_enviadas de fecha más cercana. `ultimos`: los resultado_subido o revisado, del más
-- nuevo al más viejo. Los cancelados no se ven.
CREATE OR REPLACE FUNCTION mypump_controles_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cliente_id TEXT;
  v_hoy        DATE := (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN NULL; END IF;
  IF NOT COALESCE((SELECT valor = 'true'::JSONB FROM mypump_app_config WHERE clave = 'controles_app'), FALSE) THEN
    RETURN jsonb_build_object('habilitado', FALSE);
  END IF;
  RETURN jsonb_build_object(
    'habilitado', TRUE,
    'hoy', v_hoy,
    'proximo', (
      SELECT jsonb_build_object('titulo_alumno', c.titulo_alumno, 'fecha_objetivo', c.fecha_objetivo,
                                'avisar_desde', c.avisar_desde, 'estado', c.estado)
        FROM mypump_controles_salud c
       WHERE c.cliente_id = v_cliente_id AND c.estado IN ('programado', 'ordenes_enviadas')
       -- Uno vencido hace más de 30 días (nunca se lo hizo) no tapa al siguiente: va último y solo sale si no hay otro.
       ORDER BY (c.fecha_objetivo < v_hoy - 30), c.fecha_objetivo, c.creado_en, c.id
       LIMIT 1),
    'ultimos', COALESCE((
      SELECT jsonb_agg(x.fila ORDER BY x.fecha_objetivo DESC, x.creado_en DESC, x.id)
        FROM (SELECT jsonb_build_object('titulo_alumno', c.titulo_alumno, 'fecha_objetivo', c.fecha_objetivo,
                                        'avisar_desde', c.avisar_desde, 'estado', c.estado) AS fila,
                     c.fecha_objetivo, c.creado_en, c.id
                FROM mypump_controles_salud c
               WHERE c.cliente_id = v_cliente_id AND c.estado IN ('resultado_subido', 'revisado')
               ORDER BY c.fecha_objetivo DESC, c.creado_en DESC, c.id
               LIMIT 3) x), '[]'::JSONB));
END;
$$;

REVOKE ALL ON FUNCTION mypump_controles_get(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_controles_get(TEXT) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
