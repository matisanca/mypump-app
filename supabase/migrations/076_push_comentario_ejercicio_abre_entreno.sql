-- 076_push_comentario_ejercicio_abre_entreno.sql
--
-- El push de un comentario de EJERCICIO abría el chat, donde ese comentario
-- no existe. Los comentarios de Mati sobre un ejercicio viven en la card del
-- ejercicio (escena 'train', con el badge del tab Entreno); el chat general
-- es otra tabla de mensajes. Desde la 057 el trigger mandaba destino='chat'
-- para TODO, así que el cliente tocaba "Mati comentó Press plano" y caía en
-- un chat vacío. Ahora: 'general' → chat, cualquier otro ámbito → train.
BEGIN;

CREATE OR REPLACE FUNCTION _mypump_push_on_comentario()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_titulo  text;
  v_destino text;
BEGIN
  IF NEW.autor <> 'coach' THEN RETURN NEW; END IF;

  IF NEW.ambito = 'general' THEN
    v_titulo  := 'Mati';
    v_destino := 'chat';
  ELSE
    v_destino := 'train';
    v_titulo := CASE
      WHEN NEW.referencia_nombre IS NOT NULL AND length(trim(NEW.referencia_nombre)) > 0
        THEN 'Mati comentó ' || left(NEW.referencia_nombre, 40)
      ELSE 'Mati te dejó un mensaje'
    END;
  END IF;

  BEGIN
    PERFORM mypump_encolar_push(
      NEW.cliente_id, v_titulo,
      left(COALESCE(NEW.contenido, 'Entrá a verlo'), 140),
      v_destino, 'com-' || NEW.id::text
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'push del comentario % fallo: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

COMMIT;

-- ROLLBACK: re-aplicar _mypump_push_on_comentario de la 057 (paso 10).
