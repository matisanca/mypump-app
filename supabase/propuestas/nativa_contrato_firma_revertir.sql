-- Reverso de nativa_contrato_firma.sql. EN ESTE ORDEN (ver pump-firma/RUNBOOK.md, «Volver atrás»):
--   1. Apps Script: volver a la versión anterior (la de BoldSign), para que no nazcan documentos nuevos.
--   2. Bajar el servicio: launchctl bootout gui/$(id -u)/com.pump.firma  (y sacar el hostname del túnel).
--   3. RESPALDO OBLIGATORIO antes de borrar nada: `python -m firma.tareas respaldo` y guardar aparte la carpeta
--      ~/pump-firma-datos (PDF firmados, cadena de eventos y sellos). Son contratos firmados: NO se pierden.
--   4. Este archivo. Se niega a correr si hay documentos firmados o revocados, salvo que antes se ejecute, en la
--      misma sesión:  SET contrato.confirmo_borrar_firmados = 'si';
--   5. El bucket `contratos` NO se borra acá: queda como copia. Se vacía a mano, con OK de Mati, si corresponde.
BEGIN;
DO $$
DECLARE v_n INTEGER;
BEGIN
  IF to_regclass('contrato.documentos') IS NULL THEN RETURN; END IF;
  SELECT count(*) INTO v_n FROM contrato.documentos WHERE estado IN ('firmado', 'revocado');
  IF v_n > 0 AND coalesce(current_setting('contrato.confirmo_borrar_firmados', true), '') <> 'si' THEN
    RAISE EXCEPTION 'Hay % documentos firmados. Respaldalos y confirmá con SET contrato.confirmo_borrar_firmados = ''si''.', v_n;
  END IF;
END $$;
DROP FUNCTION IF EXISTS public.mypump_contrato_get(TEXT);
DROP FUNCTION IF EXISTS public.contrato_estado(BIGINT, TEXT, TEXT);
DROP SCHEMA IF EXISTS contrato CASCADE;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'firma_srv') THEN
    EXECUTE format('REVOKE firma_srv FROM %I', current_user);
    DROP ROLE firma_srv;
  END IF;
END $$;
NOTIFY pgrst, 'reload schema';
COMMIT;
