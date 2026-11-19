-- 080_agentes_base.sql
-- Obra «agentes que cierran el ciclo» (3/11/2026). Todo aditivo: tablas,
-- funciones y una vista nuevas, más el cuerpo nuevo de
-- mypump_get_analisis_cliente (misma firma; la vieja queda en
-- REVERTIR-agentes.sql). Las tablas nuevas tienen RLS y ninguna política:
-- entran solo la clave de servicio y las funciones de este archivo.
-- Con los arreglos de la revisión (REVISION-080.md): B1, B2, C1 a C8, M1 y
-- M3 a M7. Interruptor global de ensayo en agentes_config.modo_global: para
-- activar hacen falta config.yaml y además esa clave en «activo».

begin;

-- ---------------------------------------------------------------------------
-- 1. Tablas
-- ---------------------------------------------------------------------------

create table if not exists public.agentes_config (
  clave          text primary key,
  valor          jsonb not null,
  actualizado_en timestamptz not null default now()
);

insert into public.agentes_config (clave, valor) values
  ('director_uid', to_jsonb('f7a52482-9073-4f5e-896d-08cd066489bf'::text)),
  ('zona_horaria', to_jsonb('America/Argentina/Buenos_Aires'::text)),
  ('escala_check', jsonb_build_object(
     'version', 1,
     'hambre', '1 sin hambre, 5 mucha hambre. Alto es malo.',
     'energia', '1 muy baja, 5 excelente. Alto es bueno.',
     'descanso', '1 dormí mal, 5 dormí bien. Alto es bueno.',
     'adherencia', '1 me costó, 5 la seguí. Alto es bueno.',
     'fuente', 'public/cliente.html de mypump-app, verificado el 3/11/2026')),
  ('modo_global', to_jsonb('ensayo'::text))
on conflict (clave) do nothing;

create table if not exists public.agentes_corridas (
  id           bigint generated always as identity primary key,
  tarea        text not null,
  modo         text not null default 'ensayo' check (modo in ('ensayo','activo')),
  estado       text not null default 'en_curso'
               check (estado in ('en_curso','ok','con_errores','limite','error','sin_novedades','frenada')),
  iniciada_en  timestamptz not null default now(),
  terminada_en timestamptz,
  casos        integer not null default 0,
  ok           integer not null default 0,
  errores      integer not null default 0,
  segundos     numeric,
  costo_usd    numeric(12,4) not null default 0,
  tokens       jsonb not null default '{}'::jsonb,
  modelos      jsonb not null default '{}'::jsonb,
  detalle      jsonb not null default '{}'::jsonb
);
create index if not exists agentes_corridas_tarea_idx on public.agentes_corridas (tarea, iniciada_en desc);

create table if not exists public.agentes_devoluciones (
  id               uuid primary key default gen_random_uuid(),
  cliente_id       text not null,
  semana_lunes     date not null,
  check_id         uuid,
  check_updated_at timestamptz,
  coach_id         uuid,
  modo             text not null default 'ensayo' check (modo in ('ensayo','activo')),
  estado           text not null default 'pendiente'
                   check (estado in ('pendiente','en_curso','lista','revisar','aprobada','descartada',
                                     'desactualizada','error','limite')),
  carril           text check (carril in ('verde','amarillo','rojo')),
  texto            text,
  texto_final      text,
  ajustes          jsonb not null default '[]'::jsonb,
  eval_fotos       jsonb,
  analisis         jsonb,
  senales          jsonb not null default '{}'::jsonb,
  motivos          jsonb not null default '[]'::jsonb,
  banderas         jsonb not null default '[]'::jsonb,
  senales_clinicas jsonb not null default '[]'::jsonb,
  verificador      jsonb,
  modelos          jsonb not null default '{}'::jsonb,
  costo_usd        numeric(12,4) not null default 0,
  tiempos          jsonb not null default '{}'::jsonb,
  intentos         integer not null default 0,
  corrida_id       bigint references public.agentes_corridas (id),
  creada_en        timestamptz not null default now(),
  actualizada_en   timestamptz not null default now(),
  aprobada_en      timestamptz,
  unique (cliente_id, semana_lunes),
  check (jsonb_typeof(ajustes) = 'array' and jsonb_typeof(motivos) = 'array'
         and jsonb_typeof(banderas) = 'array' and jsonb_typeof(senales) = 'object'
         and jsonb_typeof(senales_clinicas) = 'array')
);
create index if not exists agentes_devoluciones_estado_idx on public.agentes_devoluciones (estado, semana_lunes desc);

create table if not exists public.mesa_items (
  id                     bigint generated always as identity primary key,
  coach_id               uuid not null,
  cliente_id             text,
  origen                 text not null,
  origen_ref             text not null,
  tipo                   text not null,
  prioridad              smallint not null default 3 check (prioridad between 1 and 4),
  resumen                text not null,
  contenido              jsonb not null default '{}'::jsonb,
  estado                 text not null default 'pendiente'
                         check (estado in ('pendiente','aprobado','aprobado_en_ensayo','ejecutado',
                                           'descartado','error','vencido','reemplazado')),
  modo                   text not null default 'ensayo' check (modo in ('ensayo','activo')),
  tiene_pregunta_cliente boolean not null default false,
  vence_en               timestamptz,
  pospuesto_hasta        timestamptz,
  decision               text check (decision in ('aprobar','editar','descartar')),
  respuesta              jsonb,
  texto_editado          text,
  decidido_por           uuid,
  decidido_via           text check (decidido_via in ('mesa','whatsapp')),
  decidido_en            timestamptz,
  ejecucion              jsonb,
  ejecutado_en           timestamptz,
  creado_en              timestamptz not null default now(),
  actualizado_en         timestamptz not null default now(),
  unique (origen, origen_ref),
  check (jsonb_typeof(contenido) = 'object')
);
create index if not exists mesa_items_coach_estado_idx on public.mesa_items (coach_id, estado, prioridad, creado_en);
create index if not exists mesa_items_cliente_idx on public.mesa_items (cliente_id, creado_en desc);

create table if not exists public.agentes_auditoria (
  id           bigint generated always as identity primary key,
  en           timestamptz not null default now(),
  actor        text not null,
  operacion    text not null,
  tabla        text,
  ref          text,
  cliente_id   text,
  mesa_item_id bigint,
  antes        jsonb,
  despues      jsonb,
  detalle      jsonb
);
create index if not exists agentes_auditoria_en_idx on public.agentes_auditoria (en desc);
create index if not exists agentes_auditoria_cliente_idx on public.agentes_auditoria (cliente_id, en desc);

-- RLS prendido, ninguna política y sin permisos para anon ni authenticated.
do $$
declare t text;
begin
  foreach t in array array['agentes_config','agentes_corridas','agentes_devoluciones','mesa_items','agentes_auditoria'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;
-- Las secuencias, por su nombre real (si se re-aplica después de REVERTIR).
do $$
declare t text; s text;
begin
  foreach t in array array['agentes_corridas','mesa_items','agentes_auditoria'] loop
    s := pg_get_serial_sequence('public.' || t, 'id');
    execute format('revoke all on sequence %s from public, anon, authenticated', s);
    execute format('grant usage, select on sequence %s to service_role', s);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Identidad y coach
-- ---------------------------------------------------------------------------

create or replace function public.agentes_es_prueba(p_cliente text)
returns boolean language sql immutable set search_path = public as $$
  select coalesce(p_cliente like 'test-%', false)
$$;

create or replace function public._agentes_solo_servicio()
returns void language plpgsql set search_path = public as $$
begin
  -- Con la clave de servicio auth.role() es service_role; por conexión
  -- directa (postgres) no hay JWT y vale null. Cualquier otro rol, afuera,
  -- y por la API (authenticator) sin rol en los claims, también.
  if coalesce(auth.role(), case when session_user::text = 'authenticator' then 'anon' else 'service_role' end)
     <> 'service_role' then
    raise exception 'solo servicio' using errcode = '42501';
  end if;
end $$;

create or replace function public.agentes_director()
returns uuid language sql stable security definer set search_path = public as $$
  select nullif(valor #>> '{}', '')::uuid from public.agentes_config where clave = 'director_uid'
$$;

-- Interruptor global de la base: sin la clave, o con cualquier otro valor, ensayo.
create or replace function public.agentes_modo_global()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select valor #>> '{}' from public.agentes_config where clave = 'modo_global'), 'ensayo')
$$;

-- Coach del cliente. Cuando la externalización aplique coach_de(text), se usa
-- esa; mientras tanto, el director.
create or replace function public.agentes_coach_de(p_cliente text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if p_cliente is not null and to_regprocedure('public.coach_de(text)') is not null then
    begin
      execute 'select public.coach_de($1)' into v using p_cliente;
    exception when others then
      v := null;
    end;
  end if;
  return coalesce(v, public.agentes_director());
end $$;

-- El usuario logueado, si es coach. Con la tabla equipo de la externalización:
-- activo y con rol director, medico o prueba. Sin ella: solo el director.
create or replace function public.agentes_quien_soy()
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_ok  boolean := false;
begin
  if v_uid is null then
    return null;
  end if;
  if v_uid = public.agentes_director() then
    return v_uid;
  end if;
  if to_regclass('public.equipo') is not null then
    begin
      execute 'select exists (select 1 from public.equipo where user_id = $1 and activo and rol in (''director'',''medico'',''prueba''))'
        into v_ok using v_uid;
    exception when others then
      v_ok := false;
    end;
    if v_ok then
      return v_uid;
    end if;
  end if;
  return null;
end $$;

create or replace function public.agentes_es_director(p_uid uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v boolean := false;
begin
  if p_uid is null then
    return false;
  end if;
  if p_uid = public.agentes_director() then
    return true;
  end if;
  if to_regclass('public.equipo') is not null then
    begin
      execute 'select exists (select 1 from public.equipo where user_id = $1 and activo and rol = ''director'')'
        into v using p_uid;
    exception when others then
      v := false;
    end;
  end if;
  return coalesce(v, false);
end $$;

-- ---------------------------------------------------------------------------
-- 3. Guardas de las tablas
-- ---------------------------------------------------------------------------

create or replace function public._mesa_items_guardia()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_decidiendo boolean := coalesce(current_setting('agentes.decidiendo', true), '') = 'on';
begin
  if tg_op = 'DELETE' then
    raise exception 'los ítems de la Mesa no se borran';
  end if;

  if tg_op = 'INSERT' then
    if new.coach_id is null then
      new.coach_id := case when new.tipo in ('senal_clinica','dolor') then public.agentes_director()
                           else public.agentes_coach_de(new.cliente_id) end;
    end if;
    if new.coach_id is null then
      raise exception 'ítem sin coach';
    end if;
    if new.estado <> 'pendiente' or new.decision is not null or new.decidido_por is not null
       or new.decidido_en is not null or new.texto_editado is not null or new.respuesta is not null
       or new.decidido_via is not null or new.ejecutado_en is not null then
      raise exception 'un ítem nuevo entra pendiente y sin decisión';
    end if;
    return new;
  end if;

  -- UPDATE
  if new.modo is distinct from old.modo then
    raise exception 'el modo de un ítem no cambia';
  end if;
  if new.cliente_id is distinct from old.cliente_id or new.origen is distinct from old.origen
     or new.origen_ref is distinct from old.origen_ref or new.creado_en is distinct from old.creado_en then
    raise exception 'cliente, origen y fecha de un ítem no cambian';
  end if;
  if row(new.decision, new.decidido_por, new.decidido_en, new.texto_editado, new.decidido_via, new.respuesta)
     is distinct from row(old.decision, old.decidido_por, old.decidido_en, old.texto_editado, old.decidido_via, old.respuesta)
     and not v_decidiendo then
    raise exception 'la decisión se escribe solo con mesa_decidir';
  end if;
  if new.estado is distinct from old.estado then
    if not (
         (old.estado = 'pendiente' and new.estado in ('aprobado','aprobado_en_ensayo','descartado') and v_decidiendo)
      or (old.estado = 'pendiente' and new.estado in ('vencido','reemplazado','error') and not v_decidiendo)
      or (old.estado = 'aprobado' and new.estado in ('ejecutado','error') and not v_decidiendo)
      or (old.estado = 'error' and old.decision in ('aprobar','editar') and new.estado = 'aprobado' and not v_decidiendo)
      or (old.estado = 'error' and old.decision is null and new.estado = 'pendiente' and not v_decidiendo)
    ) then
      raise exception 'transición no permitida: % a %', old.estado, new.estado;
    end if;
  end if;
  if new.estado = 'aprobado' and old.estado is distinct from 'aprobado' and not public.agentes_es_prueba(new.cliente_id)
     and (new.modo = 'ensayo' or public.agentes_modo_global() <> 'activo') then
    raise exception 'en ensayo, la aprobación sobre un cliente real queda aprobado_en_ensayo';
  end if;
  -- Lo decidido no cambia de contenido, ni siquiera pasando por error.
  if (old.estado not in ('pendiente', 'error') or old.decision is not null)
     and (new.contenido is distinct from old.contenido or new.resumen is distinct from old.resumen) then
    raise exception 'el ítem ya está cerrado o decidido: contenido y resumen no cambian';
  end if;
  new.actualizado_en := now();
  return new;
end $$;

drop trigger if exists mesa_items_guardia on public.mesa_items;
create trigger mesa_items_guardia before insert or update or delete on public.mesa_items
  for each row execute function public._mesa_items_guardia();

create or replace function public._agentes_auditoria_inmutable()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'la auditoría no se modifica ni se borra';
end $$;

drop trigger if exists agentes_auditoria_inmutable on public.agentes_auditoria;
create trigger agentes_auditoria_inmutable before update or delete on public.agentes_auditoria
  for each row execute function public._agentes_auditoria_inmutable();

create or replace function public._agentes_devoluciones_guardia()
returns trigger language plpgsql set search_path = public as $$
declare
  v_decidiendo boolean := coalesce(current_setting('agentes.decidiendo', true), '') = 'on';
begin
  if tg_op = 'DELETE' then
    raise exception 'las devoluciones no se borran';
  end if;
  if tg_op = 'INSERT' then
    if new.estado in ('aprobada', 'descartada') or new.texto_final is not null or new.aprobada_en is not null then
      raise exception 'una devolución nueva no entra decidida';
    end if;
    return new;
  end if;
  if new.modo is distinct from old.modo then
    raise exception 'el modo de una devolución no cambia';
  end if;
  if new.cliente_id is distinct from old.cliente_id or new.semana_lunes is distinct from old.semana_lunes then
    raise exception 'cliente y semana de una devolución no cambian';
  end if;
  if not v_decidiendo and (
       (new.estado in ('aprobada', 'descartada') and new.estado is distinct from old.estado)
    or new.texto_final is distinct from old.texto_final
    or new.aprobada_en is distinct from old.aprobada_en) then
    raise exception 'la aprobación de una devolución se escribe solo con mesa_decidir';
  end if;
  if old.estado in ('aprobada', 'descartada') and not v_decidiendo
     and (new.estado not in (old.estado, 'desactualizada')
          or new.texto is distinct from old.texto or new.carril is distinct from old.carril) then
    raise exception 'la devolución ya está decidida: primero desactualizada';
  end if;
  new.actualizada_en := now();
  return new;
end $$;

drop trigger if exists agentes_devoluciones_guardia on public.agentes_devoluciones;
create trigger agentes_devoluciones_guardia before insert or update or delete on public.agentes_devoluciones
  for each row execute function public._agentes_devoluciones_guardia();

-- TRUNCATE no dispara los triggers de fila: se frena aparte. Corridas y
-- config tampoco se borran fila por fila.
create or replace function public._agentes_no_se_borra()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'en % no se borra ni se vacía nada', tg_table_name;
end $$;

do $$
declare t text;
begin
  foreach t in array array['mesa_items','agentes_devoluciones','agentes_auditoria','agentes_corridas','agentes_config'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_sin_truncate', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public._agentes_no_se_borra()',
                   t || '_sin_truncate', t);
    execute format('revoke truncate on table public.%I from service_role', t);
  end loop;
  foreach t in array array['agentes_corridas','agentes_config'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_sin_borrar', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public._agentes_no_se_borra()',
                   t || '_sin_borrar', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Mesa de entrada: leer y decidir (usuario logueado y coach)
-- ---------------------------------------------------------------------------

create or replace function public.mesa_listar(p_vista text default 'pendientes', p_todos boolean default false)
returns table (
  id bigint, cliente_id text, cliente_nombre text, es_prueba boolean, origen text, tipo text,
  prioridad smallint, prioridad_efectiva smallint, resumen text, contenido jsonb, estado text, modo text,
  tiene_pregunta_cliente boolean, vence_en timestamptz, pospuesto_hasta timestamptz, decision text,
  texto_editado text, decidido_en timestamptz, creado_en timestamptz, horas numeric, coach_id uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := public.agentes_quien_soy();
  v_dir boolean;
begin
  if v_uid is null then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  v_dir := public.agentes_es_director(v_uid);
  return query
  select i.id, i.cliente_id,
         coalesce((select c.nombre from public.mypump_clientes c where c.cliente_id = i.cliente_id limit 1),
                  (select d.nombre from public.client_plan_dates d where d.nutriplan_id = i.cliente_id limit 1),
                  i.cliente_id),
         public.agentes_es_prueba(i.cliente_id), i.origen, i.tipo, i.prioridad,
         (case when i.estado = 'pendiente' and i.creado_en < now() - interval '24 hours'
               then greatest(1, i.prioridad - 1) else i.prioridad end)::smallint,
         i.resumen, i.contenido, i.estado, i.modo, i.tiene_pregunta_cliente, i.vence_en, i.pospuesto_hasta,
         i.decision, i.texto_editado, i.decidido_en, i.creado_en,
         round((extract(epoch from now() - i.creado_en) / 3600.0)::numeric, 1), i.coach_id
    from public.mesa_items i
   where (i.coach_id = v_uid or (v_dir and p_todos))
     and case p_vista
           when 'pendientes' then i.estado = 'pendiente' and (i.pospuesto_hasta is null or i.pospuesto_hasta <= now())
           when 'pospuestos' then i.estado = 'pendiente' and i.pospuesto_hasta > now()
           when 'decididos'  then i.estado <> 'pendiente' and i.decidido_en > now() - interval '14 days'
           else false
         end
   order by 8, i.creado_en
   limit 500;
end $$;

create or replace function public.mesa_decidir(p_item bigint, p_decision text, p_texto text default null,
                                               p_respuesta jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := public.agentes_quien_soy();
  v_it     public.mesa_items;
  v_estado text;
  v_texto  text := nullif(btrim(coalesce(p_texto, '')), '');
  v_dev    text;
begin
  if v_uid is null then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  select * into v_it from public.mesa_items where id = p_item for update;
  if not found then
    raise exception 'ítem inexistente' using errcode = 'P0002';
  end if;
  if v_it.coach_id <> v_uid and not public.agentes_es_director(v_uid) then
    raise exception 'no autorizado' using errcode = '42501';
  end if;
  if v_it.estado <> 'pendiente' then
    raise exception 'el ítem ya no está pendiente (%)', v_it.estado;
  end if;
  if p_respuesta is not null and (jsonb_typeof(p_respuesta) <> 'object' or length(p_respuesta::text) > 4000) then
    raise exception 'respuesta inválida';
  end if;

  if p_decision = 'posponer' then
    update public.mesa_items set pospuesto_hasta = now() + interval '24 hours' where id = p_item;
    insert into public.agentes_auditoria (actor, operacion, tabla, ref, cliente_id, mesa_item_id, detalle)
    values (v_uid::text, 'mesa_posponer', 'mesa_items', p_item::text, v_it.cliente_id, p_item,
            jsonb_build_object('hasta', now() + interval '24 hours'));
    return jsonb_build_object('id', p_item, 'estado', 'pendiente', 'pospuesto', true);
  end if;

  if p_decision is null or p_decision not in ('aprobar','editar','descartar') then
    raise exception 'decisión inválida';
  end if;
  if p_decision = 'editar' and v_texto is null then
    raise exception 'falta el texto editado';
  end if;
  if v_texto is not null and length(v_texto) > 4000 then
    raise exception 'texto demasiado largo';
  end if;

  v_estado := case
    when p_decision = 'descartar' then 'descartado'
    when public.agentes_es_prueba(v_it.cliente_id) then 'aprobado'
    when v_it.modo = 'activo' and public.agentes_modo_global() = 'activo' then 'aprobado'
    else 'aprobado_en_ensayo'
  end;

  perform set_config('agentes.decidiendo', 'on', true);
  update public.mesa_items
     set estado = v_estado,
         decision = p_decision,
         texto_editado = case when p_decision = 'editar' then v_texto end,
         respuesta = p_respuesta,
         decidido_por = v_uid,
         decidido_via = 'mesa',
         decidido_en = now()
   where id = p_item;

  -- La devolución tiene que ser del mismo cliente y estar para decidir; si no,
  -- el error deshace todo y el ítem sigue pendiente.
  if v_it.origen = 'devolucion' then
    v_dev := v_it.contenido->>'devolucion_id';
    if coalesce(v_dev, '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'ítem de devolución sin devolucion_id válido';
    end if;
    update public.agentes_devoluciones d
       set estado = case when p_decision = 'descartar' then 'descartada' else 'aprobada' end,
           texto_final = case when p_decision = 'descartar' then null
                              when p_decision = 'editar' then v_texto
                              else d.texto end,
           aprobada_en = case when p_decision = 'descartar' then null else now() end
     where d.id = v_dev::uuid and d.cliente_id = v_it.cliente_id and d.estado in ('lista', 'revisar');
    if not found then
      raise exception 'la devolución no es de este cliente o ya no está para decidir';
    end if;
  end if;
  perform set_config('agentes.decidiendo', 'off', true);

  insert into public.agentes_auditoria (actor, operacion, tabla, ref, cliente_id, mesa_item_id, antes, despues)
  values (v_uid::text, 'mesa_decidir', 'mesa_items', p_item::text, v_it.cliente_id, p_item,
          jsonb_build_object('estado', v_it.estado),
          jsonb_build_object('estado', v_estado, 'decision', p_decision, 'texto_editado', v_texto,
                             'respuesta', p_respuesta));
  return jsonb_build_object('id', p_item, 'estado', v_estado, 'decision', p_decision);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Ejecución de lo aprobado (solo servicio). Exige ítem aprobado por un
-- coach y, además, agente en activo o cliente de prueba.
-- ---------------------------------------------------------------------------

create or replace function public._agentes_item_para_ejecutar(p_item bigint, p_tipo text)
returns public.mesa_items language plpgsql security definer set search_path = public as $$
declare v public.mesa_items;
begin
  perform public._agentes_solo_servicio();
  select * into v from public.mesa_items where id = p_item for update;
  if not found then
    raise exception 'ítem inexistente';
  end if;
  if v.estado <> 'aprobado' or v.decision not in ('aprobar','editar') or v.decidido_por is null then
    raise exception 'el ítem % no está aprobado para ejecutar (%)', p_item, v.estado;
  end if;
  if not public.agentes_es_prueba(v.cliente_id) and (v.modo <> 'activo' or public.agentes_modo_global() <> 'activo') then
    raise exception 'ítem en ensayo sobre un cliente real: no se ejecuta';
  end if;
  if coalesce(v.contenido->'accion'->>'tipo', '') <> p_tipo then
    raise exception 'la acción del ítem no es %', p_tipo;
  end if;
  return v;
end $$;

create or replace function public.agentes_ejecutar_publicar(p_item bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v       public.mesa_items;
  v_texto text;
  v_nombre text;
  v_id    bigint;
begin
  v := public._agentes_item_para_ejecutar(p_item, 'publicar_chat');
  v_texto := btrim(coalesce(v.texto_editado, v.contenido->'accion'->>'texto', ''));
  if v_texto = '' then
    raise exception 'texto vacío';
  end if;
  select split_part(btrim(c.nombre), ' ', 1) into v_nombre from public.mypump_clientes c where c.cliente_id = v.cliente_id;
  if not found then
    raise exception 'el cliente no tiene la app';
  end if;
  if position('{nombre}' in v_texto) > 0 then
    if coalesce(v_nombre, '') = '' then
      raise exception 'falta el nombre para reemplazar {nombre}';
    end if;
    v_texto := replace(v_texto, '{nombre}', v_nombre);
  end if;
  if v_texto ~ '[{}]' or v_texto ~ '\[\[?[A-ZÁÉÍÓÚÑ_]{3,}[0-9]*\]?\]' then
    raise exception 'quedó un marcador sin reemplazar';
  end if;
  v_id := public.mypump_chat_programar(v.cliente_id, v_texto, now(), 'agentes:' || v.id, 'ia',
            jsonb_build_object('agentes_item', v.id, 'origen', v.origen, 'tipo', v.tipo));
  if v_id is null then
    raise exception 'no se pudo programar (duplicado)';
  end if;
  update public.mesa_items
     set estado = 'ejecutado', ejecutado_en = now(),
         ejecucion = jsonb_build_object('programado_id', v_id, 'via', 'mypump_chat_programar')
   where id = v.id;
  insert into public.agentes_auditoria (actor, operacion, tabla, ref, cliente_id, mesa_item_id, despues)
  values ('servicio', 'publicar_chat', 'mypump_chat_programados', v_id::text, v.cliente_id, v.id,
          jsonb_build_object('contenido', v_texto));
  return v_id;
end $$;

create or replace function public.agentes_ejecutar_swap(p_item bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v        public.mesa_items;
  a        jsonb;
  v_rutina uuid;
  v_ex     text;
  v_swap   jsonb;
  v_ts     bigint;
  v_n      integer;
  v_antes  jsonb;
begin
  v := public._agentes_item_para_ejecutar(p_item, 'swap');
  a := v.contenido->'accion';
  v_ex := a->>'ex_id';
  v_swap := a->'swap';
  if coalesce(a->>'rutina_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'rutina_id inválido';
  end if;
  v_rutina := (a->>'rutina_id')::uuid;
  if v_swap is null or jsonb_typeof(v_swap) <> 'object' then
    raise exception 'swap inválido';
  end if;
  if not exists (
    select 1 from public.mypump_rutinas r,
                  jsonb_array_elements(r.estructura->'dias') d,
                  jsonb_array_elements(d->'bloques') b,
                  jsonb_array_elements(b->'ejercicios') e
     where r.id = v_rutina and r.cliente_id = v.cliente_id and r.estado = 'activa' and e->>'id' = v_ex) then
    raise exception 'el ejercicio no está en la rutina activa del cliente';
  end if;
  if jsonb_typeof(v_swap->'current') <> 'object' or coalesce(v_swap->'current'->>'slug', '') = ''
     or coalesce(v_swap->'current'->>'nombre', '') = '' then
    raise exception 'al swap le falta current con slug y nombre';
  end if;
  if not (v_swap ?& array['original','current','diaId','semana','fijado'])
     or not (v_swap->'current' ?& array['slug','nombre','equipment','images']) then
    raise exception 'al swap le faltan claves que usa la app';
  end if;
  v_ts := least((extract(epoch from clock_timestamp()) * 1000)::bigint, public.mypump_sustitucion_tope());
  v_swap := jsonb_set(v_swap, '{_ts}', to_jsonb(v_ts));
  if not public.mypump_sustitucion_valida(v_ex, v_swap) then
    raise exception 'sustitución inválida';
  end if;
  select to_jsonb(s) into v_antes from public.mypump_exercise_swaps s
   where s.cliente_id = v.cliente_id and s.rutina_id = v_rutina and s.ex_id = v_ex;
  if v_antes is null then
    select count(*) into v_n from public.mypump_exercise_swaps s
     where s.cliente_id = v.cliente_id and s.rutina_id = v_rutina;
    if v_n >= 300 then
      raise exception 'demasiadas sustituciones en esta rutina';
    end if;
  end if;
  insert into public.mypump_exercise_swaps (cliente_id, rutina_id, ex_id, swap, cambiado_en)
  values (v.cliente_id, v_rutina, v_ex, v_swap, v_ts)
  on conflict (cliente_id, rutina_id, ex_id) do update
     set swap = excluded.swap, cambiado_en = excluded.cambiado_en, actualizado_en = now()
   where excluded.cambiado_en >= public.mypump_exercise_swaps.cambiado_en;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'el cliente cambió ese ejercicio después: el swap aprobado no se aplicó';
  end if;
  update public.mesa_items
     set estado = 'ejecutado', ejecutado_en = now(),
         ejecucion = jsonb_build_object('rutina_id', v_rutina, 'ex_id', v_ex, 'ts', v_ts)
   where id = v.id;
  insert into public.agentes_auditoria (actor, operacion, tabla, ref, cliente_id, mesa_item_id, antes, despues)
  values ('servicio', 'aplicar_swap', 'mypump_exercise_swaps', v_rutina::text || '/' || v_ex, v.cliente_id, v.id,
          v_antes, jsonb_build_object('swap', v_swap, 'cambiado_en', v_ts));
  return jsonb_build_object('rutina_id', v_rutina, 'ex_id', v_ex, 'ts', v_ts);
end $$;

create or replace function public.agentes_ejecutar_leido(p_item bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v     public.mesa_items;
  v_ids uuid[];
  v_n   integer;
begin
  v := public._agentes_item_para_ejecutar(p_item, 'marcar_leido');
  if jsonb_typeof(v.contenido->'accion'->'comentario_ids') <> 'array' then
    raise exception 'faltan los comentarios';
  end if;
  if exists (select 1 from jsonb_array_elements_text(v.contenido->'accion'->'comentario_ids') x
              where x !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'id de comentario inválido';
  end if;
  select array_agg(x::uuid) into v_ids from jsonb_array_elements_text(v.contenido->'accion'->'comentario_ids') x;
  -- Solo comentarios del cliente fuera del chat general: el chat tiene su contador propio.
  update public.mypump_comentarios c
     set leido_por_coach = true, updated_at = now()
   where c.id = any(v_ids) and c.cliente_id = v.cliente_id and c.autor = 'cliente'
     and c.ambito <> 'general' and not c.leido_por_coach;
  get diagnostics v_n = row_count;
  update public.mesa_items
     set estado = 'ejecutado', ejecutado_en = now(), ejecucion = jsonb_build_object('marcados', v_n)
   where id = v.id;
  insert into public.agentes_auditoria (actor, operacion, tabla, ref, cliente_id, mesa_item_id, despues)
  values ('servicio', 'marcar_leido', 'mypump_comentarios', array_to_string(v_ids, ','), v.cliente_id, v.id,
          jsonb_build_object('marcados', v_n));
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Paquete semanal (solo servicio). Sin nombre, contacto ni plata. La
-- química entra solo como categoría sin dosis, calculada siempre y con aviso
-- si no coincide con el perfil de la app. Cuatro textos libres salen con el
-- nombre del cliente tapado como primera capa, pero sin deid: check.nota,
-- comentarios[].texto, devoluciones_previas[].texto y perfil.objetivo.
-- paquete.py los pasa por deid antes de la IA y, si no se pueden tapar, no van.
-- ---------------------------------------------------------------------------

create or replace function public._agentes_tapar_nombre(p_texto text, p_nombre text)
returns text language plpgsql immutable set search_path = public as $$
declare
  v text := p_texto;
  t text;
begin
  if p_texto is null or coalesce(btrim(p_nombre), '') = '' then
    return p_texto;
  end if;
  foreach t in array regexp_split_to_array(btrim(p_nombre), '\s+') loop
    t := regexp_replace(t, '[^[:alpha:]áéíóúüñÁÉÍÓÚÜÑ]', '', 'g');
    if length(t) >= 3 then
      v := regexp_replace(v, '\m' || t || '\M', '{nombre}', 'gi');
    end if;
  end loop;
  return v;
end $$;

create or replace function public.pump_paquete_semanal(p_cliente text, p_semana date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  tz         constant text := 'America/Argentina/Buenos_Aires';
  v_hoy      date := (now() at time zone tz)::date;
  v_sem      date;
  v_ref      date;
  v_ini      date;
  v_cli      record;
  v_np       jsonb;
  v_rut      record;
  v_quim     text;
  v_sem_plan integer;
  v_edad     integer;
  v_alt      numeric;
  v_check    jsonb;
  v_res      jsonb;
  v_quim_rev  boolean;
  v_quim_conf text;
  v_cat       text;
  v_nombre    text;
begin
  perform public._agentes_solo_servicio();
  if p_cliente is null or btrim(p_cliente) = '' then
    raise exception 'falta el cliente';
  end if;
  v_sem := coalesce(p_semana, v_hoy);
  v_sem := v_sem - (extract(isodow from v_sem)::integer - 1);

  select c.cliente_id, c.perfil, c.created_at, c.last_accessed_at into v_cli
    from public.mypump_clientes c where c.cliente_id = p_cliente;
  select n.payload->'clients'->p_cliente into v_np from public.nutriplan_data n where n.id = 'main';
  -- Solo para tapar el nombre en los textos libres; no sale en el paquete.
  v_nombre := coalesce((select c.nombre from public.mypump_clientes c where c.cliente_id = p_cliente limit 1),
                       (select d.nombre from public.client_plan_dates d where d.nutriplan_id = p_cliente limit 1),
                       v_np->>'nombre');
  select r.id, r.semana_actual, r.fecha_inicio, r.fecha_fin, r.estructura, (r.estructura_siguiente is not null) as hay_sig
    into v_rut
    from public.mypump_rutinas r
   where r.cliente_id = p_cliente and r.estado = 'activa'
   order by r.updated_at desc nulls last limit 1;

  select jsonb_build_object('id', ck.id, 'semana_lunes', ck.semana_lunes, 'energia', ck.energia,
           'descanso', ck.descanso, 'hambre', ck.hambre, 'adherencia', ck.adherencia,
           'nota', public._agentes_tapar_nombre(ck.nota, v_nombre),
           'cargado', ck.created_at, 'actualizado', ck.updated_at,
           'fecha_carga', (ck.created_at at time zone tz)::date)
    into v_check
    from public.mypump_checkin_semanal ck where ck.cliente_id = p_cliente and ck.semana_lunes = v_sem;

  -- Ventana evaluada: los 7 días previos a la carga del check («contame cómo
  -- venís»). Sin check: la semana del lunes pedido, hasta hoy como mucho.
  v_ref := coalesce((v_check->>'fecha_carga')::date, least(v_sem + 7, v_hoy));
  v_ini := v_ref - 7;

  select max(s.semana) into v_sem_plan from public.mypump_sesiones s
   where s.cliente_id = p_cliente and coalesce(s.semana, 1) <> 0
     and (s.iniciada_en at time zone tz)::date between v_ini and v_ref
     and (v_rut.id is null or s.rutina_id = v_rut.id);
  if v_sem_plan is null and v_rut.id is not null and v_ref >= v_hoy - 1 then
    v_sem_plan := v_rut.semana_actual;
  end if;

  begin
    if (v_np->>'fechaNacimiento') ~ '^\d{4}-\d{2}-\d{2}' then
      v_edad := extract(year from age(v_ref, left(v_np->>'fechaNacimiento', 10)::date))::integer;
    elsif (v_np->>'fechaNacimiento') ~ '^\d{1,2}/\d{1,2}/\d{4}$' then
      v_edad := extract(year from age(v_ref, to_date(v_np->>'fechaNacimiento', 'DD/MM/YYYY')))::integer;
    end if;
  exception when others then
    v_edad := null;
  end;
  if v_edad is null and (v_np->>'edad') ~ '^\d{1,3}(\.\d+)?$' then
    v_edad := round((v_np->>'edad')::numeric)::integer;
  end if;
  if v_edad is not null and (v_edad < 14 or v_edad > 90) then
    v_edad := null;
  end if;
  if (v_np->>'altura') ~ '^\d{1,3}(\.\d+)?$' then
    v_alt := (v_np->>'altura')::numeric;
    if v_alt between 1.2 and 2.3 then v_alt := v_alt * 100; end if;
    if v_alt not between 120 and 230 then v_alt := null; end if;
  end if;

  -- Se calcula siempre: hay clientes con perfil natural en la app que están en TRT o en ciclo.
  select q.fase, q.revisado, q.confianza into v_quim, v_quim_rev, v_quim_conf
    from public.mypump_quimica q where q.cliente_id = p_cliente;
  v_cat := case
      when v_quim is null then null
      when v_quim ~* '(pct|posciclo|post-?ciclo|^off)' then 'post_ciclo'
      when v_quim ~* 'trt' then 'trt'
      when v_quim ~* '(en ciclo|on-?cycle)' then 'en_ciclo'
      when v_quim ~* '^(natural|sin ciclo)' and v_quim !~* '(tirzepatid|semaglutid|retatrutid|tesamorelin)' then 'natural'
      else 'otro' end;

  v_res := jsonb_build_object(
    'version', 1,
    'cliente_id', p_cliente,
    'semana_lunes', v_sem,
    'ventana', jsonb_build_object('desde', v_ini, 'hasta', v_ref - 1, 'dia_del_check', v_ref,
                                  'criterio', '7 días previos a la carga del check'),
    'generado_en', now(),
    'escala', (select valor from public.agentes_config where clave = 'escala_check'),
    'perfil', jsonb_build_object(
      'sexo', case upper(coalesce(v_np->>'sexo', '')) when 'M' then 'M' when 'F' then 'F' end,
      'edad', v_edad,
      'altura_cm', v_alt,
      'objetivo', public._agentes_tapar_nombre(coalesce(v_rut.estructura->'perfil'->>'objetivo', v_np->>'objetivo'), v_nombre),
      'programa', v_cli.perfil,
      'categoria_farmacologia', v_cat,
      'quimica_revisada', v_quim_rev,
      'quimica_confianza', v_quim_conf,
      'perfil_y_quimica_no_coinciden', coalesce(v_cli.perfil = 'natural' and v_cat <> 'natural', false),
      'coach_id', public.agentes_coach_de(p_cliente),
      'estado_cerebro', v_np->>'estado',
      'tiene_app', v_cli.cliente_id is not null,
      'alta_app', v_cli.created_at,
      'ultimo_acceso_app', v_cli.last_accessed_at,
      'es_prueba', public.agentes_es_prueba(p_cliente)),
    'plan_fechas', (select jsonb_build_object('fecha_entrega', d.fecha_entrega, 'plan_meses', d.plan_meses,
                                              'plan_vencimiento', d.plan_vencimiento, 'estimado', d.estimado)
                      from public.client_plan_dates d where d.nutriplan_id = p_cliente limit 1),
    'check', v_check,
    'checks_8_semanas', (
      select coalesce(jsonb_agg(jsonb_build_object('semana', ck.semana_lunes, 'energia', ck.energia,
               'descanso', ck.descanso, 'hambre', ck.hambre, 'adherencia', ck.adherencia,
               'con_nota', coalesce(btrim(ck.nota), '') <> '') order by ck.semana_lunes), '[]'::jsonb)
        from public.mypump_checkin_semanal ck
       where ck.cliente_id = p_cliente and ck.semana_lunes between v_sem - 49 and v_sem),
    'plan', case when v_rut.id is null then null else jsonb_build_object(
      'rutina_id', v_rut.id,
      'fase', coalesce(v_rut.estructura->'perfil'->>'fase', v_rut.estructura->>'fase'),
      'objetivo_fase', v_rut.estructura->'perfil'->>'objetivoFase',
      'nivel', v_rut.estructura->'perfil'->>'nivel',
      'split', v_rut.estructura->'perfil'->>'split',
      'dias_semana', v_rut.estructura->'perfil'->'diasSemana',
      'ajuste_volumen', v_rut.estructura->'perfil'->'ajusteVolumen',
      'semanas_total', v_rut.estructura->'semanas_total',
      'semana_actual', v_rut.semana_actual,
      'semana_del_plan_evaluada', v_sem_plan,
      'fecha_inicio', v_rut.fecha_inicio,
      'fecha_fin', v_rut.fecha_fin,
      'dias_plan', coalesce(jsonb_array_length(case when jsonb_typeof(v_rut.estructura->'dias') = 'array'
                                                    then v_rut.estructura->'dias' end), 0),
      'hay_bloque_siguiente', v_rut.hay_sig,
      'dias', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'id', dd.d->>'id', 'nombre', dd.d->>'nombre',
                 'ejercicios', (
                   select coalesce(jsonb_agg(jsonb_build_object(
                            'id', x.e->>'id', 'nombre', x.e->>'nombre', 'tipo', x.e->>'tipo',
                            'slug', coalesce(x.e->>'catalogo_slug', x.e->>'_matched_slug'),
                            'prescripcion', (
                              select jsonb_build_object('series', p->'series', 'reps', p->'reps', 'rir', p->'rir',
                                                        'titulo', p->>'titulo')
                                from jsonb_array_elements(case when jsonb_typeof(x.e->'progresion') = 'array'
                                                               then x.e->'progresion' else '[]'::jsonb end) p
                               where p->>'semana' = v_sem_plan::text limit 1))
                          order by b.bo, x.eo), '[]'::jsonb)
                     from jsonb_array_elements(case when jsonb_typeof(dd.d->'bloques') = 'array'
                                                    then dd.d->'bloques' else '[]'::jsonb end) with ordinality b(bv, bo),
                          jsonb_array_elements(case when jsonb_typeof(b.bv->'ejercicios') = 'array'
                                                    then b.bv->'ejercicios' else '[]'::jsonb end) with ordinality x(e, eo)))
               order by dd.o), '[]'::jsonb)
          from jsonb_array_elements(case when jsonb_typeof(v_rut.estructura->'dias') = 'array'
                                         then v_rut.estructura->'dias' else '[]'::jsonb end) with ordinality dd(d, o)
         where coalesce(dd.d->>'es_comodin', 'false') <> 'true')) end,
    'sesiones', jsonb_build_object(
      'en_ventana', (select jsonb_build_object(
                        'iniciadas', count(*),
                        'finalizadas', count(*) filter (where s.finalizada_en is not null),
                        'minutos_medios', round(avg(s.duracion_segundos) filter (where s.finalizada_en is not null) / 60.0))
                       from public.mypump_sesiones s
                      where s.cliente_id = p_cliente and coalesce(s.semana, 1) <> 0
                        and (s.iniciada_en at time zone tz)::date between v_ini and v_ref - 1),
      'por_semana', (
        select coalesce(jsonb_agg(jsonb_build_object('semana', q.sem, 'iniciadas', q.n, 'finalizadas', q.f) order by q.sem), '[]'::jsonb)
          from (select date_trunc('week', s.iniciada_en at time zone tz)::date sem, count(*) n,
                       count(*) filter (where s.finalizada_en is not null) f
                  from public.mypump_sesiones s
                 where s.cliente_id = p_cliente and coalesce(s.semana, 1) <> 0
                   and (s.iniciada_en at time zone tz)::date between v_sem - 49 and v_ref
                 group by 1) q)),
    'series', (
      with rc as (
        select rc.ejercicio_clave clave, rc.ejercicio_id, rc.ejercicio_nombre, rc.peso_kg kg,
               rc.reps_realizadas reps, rc.rir_real rir, rc.registrado_en,
               date_trunc('week', rc.registrado_en at time zone tz)::date sem
          from public.mypump_registros_carga rc
          join public.mypump_sesiones s on s.id = rc.sesion_id
         where rc.cliente_id = p_cliente and coalesce(s.semana, 1) <> 0 and coalesce(rc.verosimil, false)
           and coalesce(rc.ejercicio_clave, '') <> '' and rc.reps_realizadas > 0
           and (rc.registrado_en at time zone tz)::date between v_ref - 28 and v_ref),
      comp as (
        select distinct e->>'id' id
          from public.mypump_rutinas r,
               jsonb_array_elements(case when jsonb_typeof(r.estructura->'dias') = 'array' then r.estructura->'dias' else '[]'::jsonb end) d,
               jsonb_array_elements(case when jsonb_typeof(d->'bloques') = 'array' then d->'bloques' else '[]'::jsonb end) b,
               jsonb_array_elements(case when jsonb_typeof(b->'ejercicios') = 'array' then b->'ejercicios' else '[]'::jsonb end) e
         where r.cliente_id = p_cliente and e->>'tipo' = 'compuesto'),
      por_sem as (
        select clave, sem, count(*) series,
               round(max(case when reps <= 15 and kg > 0 then kg * reps / 30.0 + kg end), 1) e1rm,
               round(avg(reps), 1) reps_media,
               round(avg(rir), 1) rir_medio,
               round(sum(case when kg > 0 then kg * reps end)) tonelaje,
               (array_agg(jsonb_build_object('kg', kg, 'reps', reps, 'rir', rir)
                          order by (case when reps <= 15 and kg > 0 then kg * reps / 30.0 + kg end) desc nulls last,
                                   kg desc nulls last, reps desc))[1] mejor_serie
          from rc group by clave, sem),
      rot as (select distinct on (clave) clave, ejercicio_nombre from rc order by clave, registrado_en desc),
      esc as (select distinct rc.clave from rc join comp on comp.id = rc.ejercicio_id)
      select coalesce(jsonb_agg(jsonb_build_object(
               'clave', p.clave, 'nombre', rot.ejercicio_nombre, 'compuesto', esc.clave is not null,
               'semanas', p.semanas) order by p.clave), '[]'::jsonb)
        from (select clave, jsonb_agg(jsonb_build_object('semana', sem, 'series', series, 'e1rm', e1rm,
                       'reps_media', reps_media, 'rir_medio', rir_medio, 'tonelaje', tonelaje,
                       'mejor_serie', mejor_serie) order by sem) semanas
                from por_sem group by clave) p
        left join rot on rot.clave = p.clave
        left join esc on esc.clave = p.clave),
    'peso', (
      with pz as (
        select sd.fecha, sd.valor from public.mypump_salud_diaria sd
         where sd.cliente_id = p_cliente and sd.tipo = 'peso_kg' and sd.valor between 30 and 300
           and sd.fecha between v_sem - 49 and v_ref)
      select jsonb_build_object(
        'promedio_7d', (select round(avg(valor), 2) from pz where fecha between v_ref - 7 and v_ref),
        'dias_7d', (select count(*) from pz where fecha between v_ref - 7 and v_ref),
        'tendencia_kg_semana_4s', (select round(regr_slope(valor, (fecha - v_ref)::numeric / 7.0)::numeric, 2)
                                     from pz where fecha between v_ref - 28 and v_ref
                                    having count(*) >= 4 and max(fecha) - min(fecha) >= 10),
        'ultimo', (select jsonb_build_object('fecha', fecha, 'kg', valor) from pz order by fecha desc limit 1),
        'por_semana', (select coalesce(jsonb_agg(jsonb_build_object('semana', w.sem, 'kg', w.kg, 'dias', w.n) order by w.sem), '[]'::jsonb)
                         from (select date_trunc('week', fecha::timestamp)::date sem, round(avg(valor), 2) kg, count(*) n
                                 from pz group by 1) w))),
    'actividad', (
      with sd as (
        select sd.fecha, sd.tipo, sd.valor from public.mypump_salud_diaria sd
         where sd.cliente_id = p_cliente and sd.tipo in ('pasos','fc_reposo','hrv_ms','sueno_min')
           and sd.fecha between v_ref - 28 and v_ref and sd.valor > 0)
      select jsonb_build_object(
        'pasos_7d', (select round(avg(valor)) from sd where tipo = 'pasos' and fecha between v_ref - 7 and v_ref - 1),
        'pasos_dias_7d', (select count(*) from sd where tipo = 'pasos' and fecha between v_ref - 7 and v_ref - 1),
        'pasos_4s', (select round(avg(valor)) from sd where tipo = 'pasos'),
        'fc_reposo_7d', (select round(avg(valor), 1) from sd where tipo = 'fc_reposo' and fecha between v_ref - 7 and v_ref - 1),
        'fc_reposo_4s', (select round(avg(valor), 1) from sd where tipo = 'fc_reposo'),
        'hrv_7d', (select round(avg(valor), 1) from sd where tipo = 'hrv_ms' and fecha between v_ref - 7 and v_ref - 1),
        'hrv_4s', (select round(avg(valor), 1) from sd where tipo = 'hrv_ms'),
        'sueno_min_7d', (select round(avg(valor)) from sd where tipo = 'sueno_min' and fecha between v_ref - 7 and v_ref - 1),
        'pasos_vista_app', (select jsonb_build_object('promedio_7d', ps.promedio_7d, 'dias_7d', ps.dias_7d, 'fuente', ps.fuente)
                              from public.mypump_pasos_salud ps where ps.cliente_id = p_cliente limit 1))),
    'entrenos_health', (
      select coalesce(jsonb_agg(jsonb_build_object('tipo', q.tipo, 'veces', q.n, 'minutos', q.m, 'kcal', q.k) order by q.n desc), '[]'::jsonb)
        from (select eh.tipo, count(*) n, round(sum(eh.duracion_min)) m, round(sum(eh.kcal)) k
                from public.mypump_entrenos_health eh
               where eh.cliente_id = p_cliente and eh.fecha between v_ini and v_ref - 1
               group by eh.tipo) q),
    'habitos', (
      select jsonb_build_object(
        'dias_registrados', count(*),
        'entrene', count(*) filter (where h.entrenamiento = 'entrene'),
        'falte', count(*) filter (where h.entrenamiento = 'falte'),
        'descanso', count(*) filter (where h.entrenamiento = 'descanso'),
        'comio_segun_plan_si', count(*) filter (where h.comio_segun_plan),
        'comio_segun_plan_no', count(*) filter (where h.comio_segun_plan = false),
        'durmio_bien_si', count(*) filter (where h.durmio_bien),
        'durmio_bien_no', count(*) filter (where h.durmio_bien = false),
        'cardio_si', count(*) filter (where h.cardio),
        'agua_vasos_media', round(avg(h.vasos_agua) filter (where h.vasos_agua > 0), 1))
        from public.mypump_habitos_diarios h
       where h.cliente_id = p_cliente and h.fecha between v_ini and v_ref - 1),
    'comidas', jsonb_build_object(
      'marcadas', (select jsonb_build_object('total', count(*), 'comido', count(*) filter (where m.estado = 'comido'),
                                             'saltado', count(*) filter (where m.estado = 'saltado'),
                                             'dias', count(distinct m.fecha))
                     from public.mypump_comidas_marcadas m
                    where m.cliente_id = p_cliente and m.fecha between v_ini and v_ref - 1),
      'libres', (select jsonb_build_object('cantidad', count(*), 'kcal', round(sum(l.kcal)))
                   from public.mypump_comidas_libres l
                  where l.cliente_id = p_cliente and l.fecha between v_ini and v_ref - 1)),
    'dieta', (select jsonb_build_object('macros_target', d.estructura->'macros_target',
                                        'comidas_por_dia', case when jsonb_typeof(d.estructura->'comidas') = 'array'
                                                                then jsonb_array_length(d.estructura->'comidas') end,
                                        'actualizada', d.updated_at)
                from public.mypump_dietas d
               where d.cliente_id = p_cliente and d.estado = 'activa'
               order by d.updated_at desc nulls last limit 1),
    'fotos', jsonb_build_object(
      'esta_semana', (select coalesce(jsonb_agg(distinct f.pose), '[]'::jsonb) from public.mypump_fotos_progreso f
                       where f.cliente_id = p_cliente and f.semana_lunes = v_sem),
      'semana_0', (select min(f.semana_lunes) from public.mypump_fotos_progreso f where f.cliente_id = p_cliente),
      'semanas_con_fotos', (select count(distinct f.semana_lunes) from public.mypump_fotos_progreso f
                             where f.cliente_id = p_cliente and f.semana_lunes <= v_sem),
      'recientes', (select coalesce(jsonb_agg(jsonb_build_object('semana', w.semana_lunes, 'poses', w.poses) order by w.semana_lunes desc), '[]'::jsonb)
                      from (select f.semana_lunes, jsonb_agg(distinct f.pose) poses
                              from public.mypump_fotos_progreso f
                             where f.cliente_id = p_cliente and f.semana_lunes between v_sem - 56 and v_sem
                             group by f.semana_lunes) w)),
    'comentarios', (
      select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'ambito', c.ambito, 'referencia', c.referencia_nombre,
               'texto', public._agentes_tapar_nombre(left(c.contenido, 600), v_nombre), 'en', c.created_at, 'leido_por_coach', c.leido_por_coach)
               order by c.created_at), '[]'::jsonb)
        from (select * from public.mypump_comentarios c
               where c.cliente_id = p_cliente and c.autor = 'cliente' and not c.oculto
                 and (c.created_at at time zone tz)::date between v_ini and v_ref
               order by c.created_at desc limit 30) c),
    'app', jsonb_build_object(
      'notificaciones', exists (select 1 from public.mypump_push_devices pd where pd.cliente_id = p_cliente and pd.activo),
      'reemplazos_activos', (select count(*) from public.mypump_exercise_swaps s
                              where s.cliente_id = p_cliente and s.rutina_id = v_rut.id and s.swap is not null)),
    -- modo y enviada: en ensayo nada le llegó al cliente.
    'devoluciones_previas', (
      select coalesce(jsonb_agg(jsonb_build_object('semana', d.semana_lunes, 'carril', d.carril, 'estado', d.estado,
               'modo', d.modo,
               'enviada', exists (select 1 from public.mesa_items i where i.origen = 'devolucion'
                                   and i.contenido->>'devolucion_id' = d.id::text and i.estado = 'ejecutado'),
               'texto', public._agentes_tapar_nombre(coalesce(d.texto_final, d.texto), v_nombre))
               order by d.semana_lunes desc), '[]'::jsonb)
        from (select * from public.agentes_devoluciones d
               where d.cliente_id = p_cliente and d.semana_lunes < v_sem
                 and d.estado in ('lista','revisar','aprobada')
               order by d.semana_lunes desc limit 3) d)
  );
  return v_res;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Generador de macrociclo: misma firma, ahora también lee las devoluciones.
-- Una semana con fila vieja del centinela (que no sea sin_check) gana; una
-- semana sin_check del centinela cede ante una devolución. En ensayo entra
-- solo lo que aprobaste en la Mesa y nunca el texto; en activo, también lo
-- listo, y el texto solo si se aprobó. Las devoluciones las ven el servicio,
-- el director y el coach del cliente; para cualquier otro logueado la función
-- devuelve lo mismo que antes.
-- ---------------------------------------------------------------------------

create or replace function public.mypump_get_analisis_cliente(p_cliente_id text, p_limite integer default 8)
returns setof public.mypump_analisis_semanal
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := public.agentes_quien_soy();
  v_ve_dev boolean;
begin
  if auth.role() not in ('authenticated', 'service_role') then
    raise exception 'Acceso denegado';
  end if;
  v_ve_dev := coalesce(auth.role(), 'service_role') = 'service_role'
              or public.agentes_es_director(v_uid)
              or (v_uid is not null and public.agentes_coach_de(p_cliente_id) = v_uid);
  return query
  with dev as (
    select d.* from public.agentes_devoluciones d
     where v_ve_dev
       and d.cliente_id = p_cliente_id and d.carril is not null
       and (d.estado = 'aprobada' or (d.modo = 'activo' and d.estado = 'lista'))
       and not exists (select 1 from public.mypump_analisis_semanal a
                        where a.cliente_id = d.cliente_id and a.semana_lunes = d.semana_lunes
                          and a.balde <> 'sin_check')
  ),
  u as (
    select a.* from public.mypump_analisis_semanal a
     where a.cliente_id = p_cliente_id
       and not (a.balde = 'sin_check' and exists (select 1 from dev where dev.semana_lunes = a.semana_lunes))
    union all
    select (jsonb_populate_record(null::public.mypump_analisis_semanal, jsonb_build_object(
             'id', dev.id,
             'cliente_id', dev.cliente_id,
             'semana_lunes', dev.semana_lunes,
             'balde', case dev.carril
                        when 'verde' then 'bien'
                        when 'rojo' then 'ajustar'
                        else case when jsonb_array_length(dev.ajustes) > 0 then 'ajustar' else 'observar' end
                      end,
             'motivos', dev.motivos,
             'banderas', case when dev.carril = 'rojo' and not dev.banderas ? 'rojo'
                              then dev.banderas || '["rojo"]'::jsonb else dev.banderas end,
             'senales', dev.senales,
             'mensaje_cliente', case when dev.estado = 'aprobada' and dev.modo = 'activo' then dev.texto_final end,
             'sugerencia_coach', case when dev.estado = 'aprobada' and dev.modo = 'activo' and jsonb_array_length(dev.ajustes) > 0
                                      then (select string_agg(coalesce(x->>'resumen', x->>'texto', x::text), '; ')
                                              from jsonb_array_elements(dev.ajustes) x) end,
             'corrida_el', dev.creada_en,
             'resuelto_el', dev.aprobada_en,
             'created_at', dev.creada_en))).*
      from dev
  )
  select * from u order by semana_lunes desc limit greatest(1, p_limite);
end $$;

-- ---------------------------------------------------------------------------
-- 8. Vista de tus ediciones (aprendizaje de voz). Con security_invoker, y sin
-- permisos para anon ni authenticated.
-- ---------------------------------------------------------------------------

create or replace view public.agentes_ejemplos_voz with (security_invoker = true) as
select i.id, i.tipo, i.origen, i.cliente_id, i.decidido_en,
       coalesce(i.contenido->'accion'->>'texto', i.contenido->>'texto') as antes,
       i.texto_editado as despues
  from public.mesa_items i
 where i.decision = 'editar' and i.texto_editado is not null;

revoke all on public.agentes_ejemplos_voz from public, anon, authenticated;
grant select on public.agentes_ejemplos_voz to service_role;

-- ---------------------------------------------------------------------------
-- 9. Permisos de las funciones
-- ---------------------------------------------------------------------------

do $$
declare f text;
begin
  foreach f in array array[
    'public.agentes_es_prueba(text)',
    'public._agentes_solo_servicio()',
    'public.agentes_director()',
    'public.agentes_modo_global()',
    'public.agentes_coach_de(text)',
    'public.agentes_quien_soy()',
    'public.agentes_es_director(uuid)',
    'public._mesa_items_guardia()',
    'public._agentes_auditoria_inmutable()',
    'public._agentes_devoluciones_guardia()',
    'public._agentes_no_se_borra()',
    'public._agentes_tapar_nombre(text, text)',
    'public.mesa_listar(text, boolean)',
    'public.mesa_decidir(bigint, text, text, jsonb)',
    'public._agentes_item_para_ejecutar(bigint, text)',
    'public.agentes_ejecutar_publicar(bigint)',
    'public.agentes_ejecutar_swap(bigint)',
    'public.agentes_ejecutar_leido(bigint)',
    'public.pump_paquete_semanal(text, date)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- La Mesa la usa el coach logueado: solo estas dos (y quién soy).
grant execute on function public.mesa_listar(text, boolean) to authenticated;
grant execute on function public.mesa_decidir(bigint, text, text, jsonb) to authenticated;
grant execute on function public.agentes_quien_soy() to authenticated;

commit;
