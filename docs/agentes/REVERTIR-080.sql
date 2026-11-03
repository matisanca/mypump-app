-- REVERTIR-agentes.sql: deshace 080_agentes_base.sql sin borrar datos.
-- 1) Vuelve la definición original de mypump_get_analisis_cliente.
-- 2) Saca las funciones, los triggers y la vista nuevos.
-- 3) Saca la clave modo_global (el interruptor de ensayo de la base).
-- 4) Las tablas nuevas NO se borran: se renombran con el sufijo _rvAAMMDDHHMI
--    junto con sus índices y secuencias, quedan sin permisos para nadie y con
--    una guarda que no deja modificarlas, borrarlas ni vaciarlas.
--    _agentes_no_se_borra() queda a propósito: es la guarda de los archivos.

begin;

CREATE OR REPLACE FUNCTION public.mypump_get_analisis_cliente(p_cliente_id text, p_limite integer DEFAULT 8)
 RETURNS SETOF mypump_analisis_semanal
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.role() NOT IN ('authenticated', 'service_role') THEN
    RAISE EXCEPTION 'Acceso denegado';
  END IF;

  RETURN QUERY
  SELECT * FROM mypump_analisis_semanal
  WHERE cliente_id = p_cliente_id
  ORDER BY semana_lunes DESC
  LIMIT GREATEST(1, p_limite);
END;
$function$;

drop view if exists public.agentes_ejemplos_voz;

drop trigger if exists mesa_items_guardia on public.mesa_items;
drop trigger if exists agentes_auditoria_inmutable on public.agentes_auditoria;
drop trigger if exists agentes_devoluciones_guardia on public.agentes_devoluciones;
do $$
declare t text;
begin
  foreach t in array array['mesa_items','agentes_devoluciones','agentes_auditoria','agentes_corridas','agentes_config'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists %I on public.%I', t || '_sin_truncate', t);
      execute format('drop trigger if exists %I on public.%I', t || '_sin_borrar', t);
    end if;
  end loop;
  if to_regclass('public.agentes_config') is not null then
    delete from public.agentes_config where clave = 'modo_global';
  end if;
end $$;

drop function if exists public.mesa_listar(text, boolean);
drop function if exists public.mesa_decidir(bigint, text, text, jsonb);
drop function if exists public.agentes_ejecutar_publicar(bigint);
drop function if exists public.agentes_ejecutar_swap(bigint);
drop function if exists public.agentes_ejecutar_leido(bigint);
drop function if exists public._agentes_item_para_ejecutar(bigint, text);
drop function if exists public.pump_paquete_semanal(text, date);
drop function if exists public._mesa_items_guardia();
drop function if exists public._agentes_auditoria_inmutable();
drop function if exists public._agentes_devoluciones_guardia();
drop function if exists public.agentes_quien_soy();
drop function if exists public.agentes_es_director(uuid);
drop function if exists public.agentes_coach_de(text);
drop function if exists public.agentes_director();
drop function if exists public.agentes_modo_global();
drop function if exists public._agentes_tapar_nombre(text, text);
drop function if exists public._agentes_solo_servicio();
drop function if exists public.agentes_es_prueba(text);

do $$
declare
  t   text;
  i   text;
  sq  text;
  suf text := '_rv' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYMMDDHH24MI');
begin
  foreach t in array array['mesa_items','agentes_devoluciones','agentes_auditoria','agentes_corridas','agentes_config'] loop
    if to_regclass('public.' || t) is not null then
      for i in select c.relname from pg_index x join pg_class c on c.oid = x.indexrelid
                where x.indrelid = ('public.' || t)::regclass loop
        execute format('alter index public.%I rename to %I', i, left(i, 63 - length(suf)) || suf);
      end loop;
      sq := null;
      select pg_get_serial_sequence('public.' || t, a.attname) into sq
        from pg_attribute a where a.attrelid = ('public.' || t)::regclass and a.attidentity <> '' and not a.attisdropped limit 1;
      if sq is not null then
        execute format('alter sequence %s rename to %I', sq, left(t, 63 - length(suf) - 7) || '_id_seq' || suf);
      end if;
      execute format('alter table public.%I rename to %I', t, t || suf);
      execute format('revoke all on table public.%I from public, anon, authenticated, service_role', t || suf);
      execute format('create trigger %I before update or delete on public.%I for each row execute function public._agentes_no_se_borra()',
                     'archivo' || suf, t || suf);
      execute format('create trigger %I before truncate on public.%I for each statement execute function public._agentes_no_se_borra()',
                     'archivo_trunc' || suf, t || suf);
    end if;
  end loop;
end $$;

commit;
