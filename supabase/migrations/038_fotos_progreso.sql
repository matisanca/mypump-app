-- ============================================================
-- 038 - Fotos de progreso subidas desde la app (PRIVADAS)
-- ============================================================
-- Hasta ahora las fotos llegaban por WhatsApp y las guardaba el bot en el
-- bucket PUBLICO 'analisis'. A partir de aca el cliente las sube desde la
-- app y viven en un bucket PRIVADO: solo Mati (rol authenticated) y el
-- propio cliente (via su token, con URLs firmadas por mini-vision) pueden
-- verlas. Nunca hay una URL publica de una foto de fisico.
--
-- REGLA DEL SCHEMA: la columna `path` guarda el path RELATIVO al bucket
-- ({cliente_id}/{semana_lunes}/{pose}.jpg), NUNCA una URL absoluta. Guardar
-- la URL entera fue justo el bug que rompio las fotos viejas en el Cerebro.
--
-- SEGURIDAD: no existe RPC de ESCRITURA por token a proposito. Si el cliente
-- pudiera insertar su propio `path`, podria apuntar a un objeto ajeno y luego
-- pedir que se lo firmen. Solo escribe mini-vision con service_role, y arma
-- el path con el cliente_id que sale del token (nunca del body).
--
-- OJO: el bloque de storage.buckets/storage.objects necesita permisos sobre
-- el schema `storage`. Si el runner no los tiene, correr ESTA migracion desde
-- el SQL editor del dashboard (que corre como owner).
-- ============================================================

-- ---- 1) Bucket privado ----
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('progreso', 'progreso', false, 3145728, ARRAY['image/jpeg'])
ON CONFLICT (id) DO NOTHING;

-- Mati (Cerebro/panel, rol authenticated) puede LEER para poder firmar URLs
-- con sb.storage.createSignedUrl() sin pasos extra. anon no tiene policy = no ve nada.
DROP POLICY IF EXISTS "coach lee progreso" ON storage.objects;
CREATE POLICY "coach lee progreso"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'progreso' AND auth.role() = 'authenticated');

-- ---- 2) Tabla de registro ----
CREATE TABLE IF NOT EXISTS mypump_fotos_progreso (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id   TEXT        NOT NULL,
  semana_lunes DATE        NOT NULL,   -- mismo anclaje que mypump_checkin_semanal
  pose         TEXT        NOT NULL CHECK (pose IN ('frente','perfil','espalda')),
  path         TEXT        NOT NULL,   -- RELATIVO al bucket. Nunca URL absoluta.
  bytes        INTEGER,
  tomada_el    DATE,                   -- fecha local que informo el device
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (cliente_id, semana_lunes, pose)   -- re-subir la misma pose pisa
);

CREATE INDEX IF NOT EXISTS idx_mypump_fotos_cliente_semana
  ON mypump_fotos_progreso (cliente_id, semana_lunes DESC);

ALTER TABLE mypump_fotos_progreso ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin all mypump_fotos_progreso"
  ON mypump_fotos_progreso FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- ---- 3) RPC de lectura para la app: SOLO METADATA ----
-- Devuelve que semanas/poses tiene, sin `path` ni URL. Con esto la app arma
-- todo el timeline y el estado de los slots aunque mini-vision este caido;
-- los pixeles se piden aparte (URLs firmadas) solo cuando hacen falta.
CREATE OR REPLACE FUNCTION mypump_get_fotos_progreso(
  p_token TEXT,
  p_desde DATE DEFAULT NULL
)
RETURNS TABLE (
  semana_lunes DATE,
  pose         TEXT,
  tomada_el    DATE,
  created_at   TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cliente_id TEXT;
BEGIN
  v_cliente_id := mypump_get_cliente_id_from_token(p_token);
  IF v_cliente_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
    SELECT f.semana_lunes, f.pose, f.tomada_el, f.created_at
    FROM mypump_fotos_progreso f
    WHERE f.cliente_id = v_cliente_id
      AND (p_desde IS NULL OR f.semana_lunes >= p_desde)
    ORDER BY f.semana_lunes DESC, f.pose;
END;
$$;

GRANT EXECUTE ON FUNCTION mypump_get_fotos_progreso(TEXT, DATE) TO anon, authenticated;

-- ============================================================
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS mypump_get_fotos_progreso(TEXT, DATE);
--   DROP TABLE IF EXISTS mypump_fotos_progreso;
--   DROP POLICY IF EXISTS "coach lee progreso" ON storage.objects;
--   DELETE FROM storage.buckets WHERE id = 'progreso';  -- solo si esta vacio
-- ============================================================
