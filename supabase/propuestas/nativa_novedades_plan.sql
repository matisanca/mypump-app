-- PROPUESTA, sin aplicar. Para aplicar hace falta el OK de Mati (compuerta G2).
--
-- «Novedades de tu plan» (app 2.3.0 y web): cuando Mati publica un cambio en la rutina, la dieta o la suplementación, la
-- app lo muestra una vez al abrir y lo deja en Entreno (7 días) y en Mis datos. No hace falta nada más del servidor:
--   * La versión anterior NO está en la base (desde la 013 `mypump_publicar_cliente` y `mypump_activar_siguiente` pisan la
--     fila con version+1), así que el plan que el alumno ya vio queda en el teléfono (novedades_base.json; en la web,
--     localStorage por token) y la comparación es determinística, en el teléfono, sin IA.
--   * Solo falta la palanca. Sin la clave, o con cualquier valor que no sea `true`, queda apagada: no se guarda ni se
--     muestra nada. Este archivo la crea APAGADA, para que quede a la vista en la tabla; prenderla es el UPDATE de abajo.
--
-- Ensayo (sin dejar nada), contra la base real con el OK de Mati o contra una copia:
--   BEGIN;
--   \i nativa_novedades_plan.sql   -- (o pegar el INSERT de abajo sin su BEGIN/COMMIT)
--   SELECT clave, valor, nota FROM mypump_app_config WHERE clave = 'novedades_plan';   -- 1 fila, valor false
--   SELECT (mypump_get_app_config())->'novedades_plan';                                  -- false
--   ROLLBACK;
--   SELECT count(*) FROM mypump_app_config WHERE clave = 'novedades_plan';              -- 0
--
-- Prender (cuando Mati diga):
--   UPDATE mypump_app_config SET valor = 'true'::jsonb, actualizado_en = NOW() WHERE clave = 'novedades_plan';
-- Apagar sin borrar: el mismo UPDATE con 'false'. Las apps dejan de mostrarla en la próxima lectura de la palanca.

BEGIN;

INSERT INTO mypump_app_config (clave, valor, nota)
VALUES ('novedades_plan', 'false'::jsonb,
        'Novedades de tu plan (2.3.0): mostrar qué cambió cuando Mati publica. true = prendida.')
ON CONFLICT (clave) DO NOTHING;

COMMIT;
