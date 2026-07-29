-- =============================================================
-- 053 — Un aviso ya entregado volvía a 'pendiente' y se repetía
--
-- mypump_push_pendientes hace JOIN de la cola contra los dispositivos, así que
-- un cliente con iPhone + iPad devuelve DOS FILAS CON EL MISMO c.id. El sender
-- manda a los dos y reporta dos veces sobre el MISMO id de cola:
--
--   iPhone entrega OK   → push_resultado(id, true)  → estado = 'enviado'
--   iPad falla (timeout)→ push_resultado(id, false) → estado = 'pendiente'
--
-- El segundo pisa al primero: un aviso YA ENTREGADO vuelve a la cola y en la
-- corrida siguiente se manda de nuevo — a los dos dispositivos. El cliente
-- recibe el mismo mensaje repetido, que es de las cosas que más molestan de
-- una app.
--
-- FIX, en dos partes:
--
-- 1. UN ENVÍO POR AVISO. push_pendientes devuelve una sola fila por item de
--    cola: la del dispositivo VISTO MÁS RECIENTEMENTE. Con eso el sender no
--    puede reportar dos veces sobre el mismo id, y el bug se vuelve imposible
--    en vez de quedar mitigado.
--
--    Se elige el más reciente y no "todos" a propósito: un recordatorio de
--    entrenar tiene que llegar UNA vez, al teléfono que la persona está
--    usando — no también al iPad que quedó en un cajón. Si algún día se
--    quiere fan-out real, hace falta una tabla de envíos por (cola, device);
--    no se puede representar con un solo estado por aviso, que es justo lo
--    que rompía acá.
--
-- 2. CINTURÓN Y TIRADORES: la rama de fallo ya no toca una fila que quedó en
--    'enviado'. Aunque algún día vuelvan dos filas por otro camino, un envío
--    exitoso no se puede degradar.
--
-- VERIFICACIÓN:
--   Cliente con 2 devices activos y 1 aviso en cola:
--     antes:  push_pendientes() → 2 filas con el mismo id
--     ahora:  1 fila
--   Y sobre un aviso ya en 'enviado', push_resultado(id, false) lo deja en
--   'enviado' (antes lo devolvía a 'pendiente').
--
-- ROLLBACK: re-aplicar la mig 048.
-- =============================================================

CREATE OR REPLACE FUNCTION mypump_push_pendientes(p_limite integer DEFAULT 50)
RETURNS TABLE (
  id bigint, cliente_id text, titulo text, cuerpo text, destino text,
  device_token text, plataforma text, intentos integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  -- DISTINCT ON (c.id): una fila por AVISO, no por dispositivo.
  SELECT DISTINCT ON (c.id)
         c.id, c.cliente_id, c.titulo, c.cuerpo, c.destino,
         d.token, d.plataforma, c.intentos
  FROM mypump_push_cola c
  JOIN mypump_push_devices d ON d.cliente_id = c.cliente_id AND d.activo
  WHERE c.estado = 'pendiente'
    AND c.intentos < 4          -- 4 intentos y se da por perdido
  -- c.id primero porque DISTINCT ON lo exige; dentro de cada aviso gana el
  -- dispositivo visto más recientemente (NULLS LAST: uno sin visto_en es de
  -- antes de que se registrara la columna, y pierde contra cualquiera).
  ORDER BY c.id, d.visto_en DESC NULLS LAST
  LIMIT LEAST(GREATEST(COALESCE(p_limite, 50), 1), 500);
END;
$$;

REVOKE ALL ON FUNCTION mypump_push_pendientes(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_push_pendientes(integer) TO service_role;

CREATE OR REPLACE FUNCTION mypump_push_resultado(
  p_id           bigint,
  p_ok           boolean,
  p_error        text DEFAULT NULL,
  p_device_token text DEFAULT NULL,
  p_baja_device  boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_ok THEN
    UPDATE mypump_push_cola
       SET estado = 'enviado', enviado_en = now(), intentos = intentos + 1, error = NULL
     WHERE id = p_id;
  ELSE
    UPDATE mypump_push_cola
       SET intentos = intentos + 1,
           error = left(COALESCE(p_error,''), 300),
           -- Al 4º intento deja de ser 'pendiente' y sale de la cola.
           estado = CASE WHEN intentos + 1 >= 4 THEN 'error' ELSE 'pendiente' END
     -- `estado <> 'enviado'`: un aviso que YA se entregó no se degrada nunca,
     -- pase lo que pase con otro envío. Sin esto, un fallo posterior lo
     -- devolvía a la cola y el cliente recibía el mensaje repetido.
     WHERE id = p_id AND estado <> 'enviado';
  END IF;

  -- APNs 410 Gone = la app ya no está en ese dispositivo. Se apaga para no
  -- seguir intentando contra un token muerto para siempre.
  IF p_baja_device AND p_device_token IS NOT NULL THEN
    UPDATE mypump_push_devices
       SET activo = false, ultimo_error = left(COALESCE(p_error,'410'), 200)
     WHERE token = p_device_token;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION mypump_push_resultado(bigint, boolean, text, text, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION mypump_push_resultado(bigint, boolean, text, text, boolean)
  TO service_role;
