-- ============================================================
-- 019 — Notificar al bot (WhatsApp a Mati) cuando un cliente comenta
-- ============================================================
-- Trigger AFTER INSERT en mypump_comentarios: si el comentario es del cliente,
-- hace un POST HTTP a PumpBot, que le manda un WhatsApp a Mati.
--
-- SEGURIDAD DEL SECRETO (repo PÚBLICO):
--   El X-Mypump-Secret NO se hardcodea acá. Se guarda en Supabase Vault con el
--   nombre 'mypump_notify_secret' y la función lo lee de vault.decrypted_secrets.
--   ⚠️ ANTES de que funcione, hay que cargarlo UNA vez (NO se commitea):
--
--     SELECT vault.create_secret(
--       '<MYPUMP_NOTIFY_SECRET>',   -- = el mismo valor que tiene el bot (NO commitear)
--       'mypump_notify_secret',
--       'Secreto X-Mypump-Secret para notificar comentarios al bot PumpBot'
--     );
--
--   Si el secreto rota: SELECT vault.update_secret(<uuid>, 'nuevo_valor');
--
-- best-effort: net.http_post es ASÍNCRONO. Si el bot no responde, el INSERT del
-- comentario NO falla ni se bloquea — el comentario igual se guarda. La
-- notificación se intenta una sola vez (sin reintentos en la DB).
--
-- La notificación sale del lado DB (trigger), NUNCA del frontend del cliente.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION mypump_notify_coach_comentario()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  IF NEW.autor = 'cliente' THEN
    -- Secreto desde Vault (no está en el repo). Si no se cargó todavía, queda
    -- NULL → el POST sale sin secreto y el bot lo rechaza, pero el comentario
    -- igual se guarda (best-effort).
    SELECT decrypted_secret INTO v_secret
      FROM vault.decrypted_secrets
     WHERE name = 'mypump_notify_secret'
     LIMIT 1;

    PERFORM net.http_post(
      url     := 'https://bot.mypumpteam.com/mypump/comentario',
      headers := jsonb_build_object(
                   'Content-Type',   'application/json',
                   'X-Mypump-Secret', COALESCE(v_secret, '')
                 ),
      body    := jsonb_build_object(
                   'comentario_id',     NEW.id,
                   'cliente_id',        NEW.cliente_id,
                   'ambito',            NEW.ambito,
                   'referencia_id',     NEW.referencia_id,
                   'referencia_nombre', NEW.referencia_nombre,
                   'contenido',         NEW.contenido,
                   'autor',             NEW.autor
                 )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mypump_notify_comentario ON mypump_comentarios;
CREATE TRIGGER trg_mypump_notify_comentario
  AFTER INSERT ON mypump_comentarios
  FOR EACH ROW EXECUTE FUNCTION mypump_notify_coach_comentario();
