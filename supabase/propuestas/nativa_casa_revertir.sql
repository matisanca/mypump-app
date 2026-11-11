-- Reverso de nativa_casa.sql. Para cortar sin borrar:
--   UPDATE mypump_app_config SET valor = 'false'::JSONB, actualizado_en = NOW() WHERE clave = 'casa';
--   UPDATE mypump_gimnasio SET lugar = 'gimnasio', actualizado_en = NOW() WHERE lugar = 'casa' AND estado = 'borrador';
--   (lo segundo, para que un borrador de casa no se termine enviando por fotos con la palanca apagada)
-- Orden: este reverso va ANTES que nativa_gimnasio_fotos_revertir.sql (mypump_casa_vista depende de la tabla).
-- Antes de este archivo: que no queden cargas de casa abiertas ni vigentes, porque al borrar la columna pasarían por
-- cargas de gimnasio. El DO de abajo frena si hay alguna; se cierran o se reemplazan primero (con EDITOR).
BEGIN;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM mypump_gimnasio WHERE lugar = 'casa' AND estado <> 'reemplazado') THEN
    RAISE EXCEPTION 'hay cargas de casa abiertas o vigentes: resolverlas antes de revertir';
  END IF;
END $$;
DROP FUNCTION IF EXISTS mypump_casa_enviar(TEXT, UUID, JSONB, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS mypump_casa_elegir(TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS mypump_casa_get(TEXT);
DROP FUNCTION IF EXISTS mypump_casa_vista(mypump_gimnasio);
DROP FUNCTION IF EXISTS mypump_casa_habilitada(TEXT);
ALTER TABLE mypump_gimnasio DROP COLUMN IF EXISTS casa;
ALTER TABLE mypump_gimnasio DROP COLUMN IF EXISTS lugar;
DROP FUNCTION IF EXISTS mypump_casa_tipos();
DELETE FROM mypump_app_config WHERE clave = 'casa';
NOTIFY pgrst, 'reload schema';
COMMIT;
