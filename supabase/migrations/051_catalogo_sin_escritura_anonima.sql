-- =============================================================
-- 051 — Cualquiera podía borrar el catálogo de ejercicios
--
-- En producción hay una política RLS sobre mypump_ejercicios_catalogo que
-- NO ESTÁ EN NINGUNA MIGRACIÓN:
--
--   anon_write_catalogo   FOR ALL   USING (true)   WITH CHECK (true)
--
-- FOR ALL es INSERT, UPDATE **y DELETE**. Con USING(true) no filtra nada, y
-- Supabase le da a `anon` los permisos DML de tabla por default. O sea que
-- cualquiera con la anon key —que viaja en public/js/config.js, es pública—
-- podía vaciar el catálogo entero o reescribirlo.
--
-- No es una tabla lateral: de ahí salen los nombres, el músculo, el patrón de
-- movimiento y las URLs de las imágenes de los ejercicios de TODAS las rutinas.
-- Vaciarla deja a cada cliente sin imágenes ni sustituciones. Y como la app
-- renderiza image_eccentric / image_concentric como <img src>, reescribir esas
-- URLs es además una vía para mostrarle cualquier imagen a los clientes.
--
-- DE DÓNDE SALIÓ: no de las migraciones. La 012 creó las dos correctas —
-- `read_all_catalogo` (SELECT, USING true: el catálogo es de lectura pública a
-- propósito, no tiene datos de nadie) y `admin_write_catalogo` (FOR ALL con
-- auth.role() = 'authenticated'). Esta tercera se agregó a mano en el
-- dashboard, seguramente para destrabar una escritura que fallaba, y quedó.
-- Por eso no aparecía en ninguna revisión del repo: el repo no la tiene.
--
-- POR QUÉ ES SEGURO SACARLA — se verificó quién escribe de verdad:
--   · La app del cliente (supabase-client.js:464) solo hace SELECT.
--   · El Cerebro (index.html:8590+) escribe, pero entra con
--     signInWithPassword (index.html:19837) → es 'authenticated' →
--     ya lo cubre admin_write_catalogo.
--   · La mini y las Pages Functions no tocan esta tabla.
--   · service_role saltea RLS de todos modos.
-- Sacarla no le quita permiso a nadie que lo estuviera usando.
--
-- La lectura pública NO se toca: el catálogo es material de referencia
-- compartido y la app lo baja sin token, igual que la tabla de alimentos.
--
-- VERIFICACIÓN:
--   Con la anon key, un DELETE contra
--   /rest/v1/mypump_ejercicios_catalogo?slug_en=eq.<algo>
--   antes: borraba.   ahora: 0 filas afectadas (la política ya no lo permite).
--   Un SELECT tiene que seguir devolviendo el catálogo completo.
--
-- ROLLBACK:
--   CREATE POLICY "anon_write_catalogo" ON mypump_ejercicios_catalogo
--     FOR ALL USING (true) WITH CHECK (true);
--   (no hacerlo salvo que aparezca un escritor anónimo legítimo, que no existe)
-- =============================================================

DROP POLICY IF EXISTS "anon_write_catalogo" ON mypump_ejercicios_catalogo;

-- Se re-declara la correcta por si en algún momento se borró junto con la otra.
DROP POLICY IF EXISTS "admin_write_catalogo" ON mypump_ejercicios_catalogo;
CREATE POLICY "admin_write_catalogo"
  ON mypump_ejercicios_catalogo FOR ALL
  USING (auth.role() IN ('authenticated', 'service_role'))
  WITH CHECK (auth.role() IN ('authenticated', 'service_role'));

-- Auditoría: ninguna política debería dejar pasar todo salvo la de lectura
-- del catálogo, que es intencional.
--   SELECT tablename, policyname, cmd, qual, with_check FROM pg_policies
--    WHERE schemaname='public' AND tablename LIKE 'mypump%'
--      AND (qual = 'true' OR with_check = 'true');
