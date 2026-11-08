-- ═══════════════════════════════════════════════════════════════════════════
-- MD Pro Training — configuración de Supabase (seguridad, videos, orden, avatar)
-- Correr en Supabase: SQL Editor → New query → pegar TODO → Run.
-- Se puede correr más de una vez. No borra datos.
--
-- Qué hace:
--   1. Seguridad (RLS): solo el profe ve y modifica todo; cada alumno ve solo lo suyo
--      y únicamente puede marcar sus ejercicios, cargar sus series y sus archivos.
--      La clave pública de la app ya no alcanza para leer datos: hace falta estar logueado.
--   2. Alta automática del alumno en "clientes" cuando se registra.
--   3. Columna "orden" en ejercicios (el alumno ve el orden que arma el profe).
--   4. Columna "avatar" en clientes (solo guarda el avatar/emoji elegido, nunca fotos).
--   5. Espacio PRIVADO para videos (bucket "sesion-archivos", máx. 50 MB por archivo).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Columnas nuevas ─────────────────────────────────────────────────────────
alter table public.ejercicios add column if not exists orden integer;
alter table public.clientes  add column if not exists avatar text;

-- ── Quién es quién ──────────────────────────────────────────────────────────
-- El profe se reconoce por el email de su cuenta (el mismo que usa la app).
create or replace function public.es_profe() returns boolean
language sql stable as $$
  select coalesce(lower(auth.jwt() ->> 'email'), '') = 'matiasdinardi10@gmail.com'
$$;

-- id del alumno logueado (según su email)
create or replace function public.mi_cliente_id() returns bigint
language sql stable security definer set search_path = public as $$
  select id from public.clientes where lower(email) = lower(auth.jwt() ->> 'email') limit 1
$$;

-- ── Activar RLS ─────────────────────────────────────────────────────────────
alter table public.clientes              enable row level security;
alter table public.biblioteca_ejercicios enable row level security;
alter table public.rutinas               enable row level security;
alter table public.ejercicios            enable row level security;
alter table public.logs_entrenamiento    enable row level security;
alter table public.sesiones              enable row level security;
alter table public.plantillas            enable row level security;
alter table public.sesion_archivos       enable row level security;

-- Borrar TODAS las políticas viejas de estas tablas (incluidas las que dejaban leer a cualquiera)
do $$
declare p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('clientes','biblioteca_ejercicios','rutinas','ejercicios','logs_entrenamiento','sesiones','plantillas','sesion_archivos')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- clientes: el profe todo; el alumno ve su ficha y puede darse de alta (registro)
create policy app_clientes_ver    on public.clientes for select to authenticated using (public.es_profe() or lower(email) = lower(auth.jwt() ->> 'email'));
create policy app_clientes_alta   on public.clientes for insert to authenticated with check (public.es_profe() or lower(email) = lower(auth.jwt() ->> 'email'));
create policy app_clientes_editar on public.clientes for update to authenticated using (public.es_profe() or lower(email) = lower(auth.jwt() ->> 'email'));
create policy app_clientes_borrar on public.clientes for delete to authenticated using (public.es_profe());

-- biblioteca: solo el profe
create policy app_biblioteca_profe on public.biblioteca_ejercicios for all to authenticated using (public.es_profe()) with check (public.es_profe());

-- rutinas: el alumno ve las suyas; modifica solo el profe
create policy app_rutinas_ver   on public.rutinas for select to authenticated using (public.es_profe() or cliente_id = public.mi_cliente_id());
create policy app_rutinas_profe on public.rutinas for all    to authenticated using (public.es_profe()) with check (public.es_profe());

-- ejercicios: el alumno ve los suyos y solo puede marcar completado / dejar comentario (ver trigger abajo)
create policy app_ejercicios_ver on public.ejercicios for select to authenticated
  using (public.es_profe() or rutina_id in (select id from public.rutinas where cliente_id = public.mi_cliente_id()));
create policy app_ejercicios_marcar on public.ejercicios for update to authenticated
  using (public.es_profe() or rutina_id in (select id from public.rutinas where cliente_id = public.mi_cliente_id()));
create policy app_ejercicios_alta   on public.ejercicios for insert to authenticated with check (public.es_profe());
create policy app_ejercicios_borrar on public.ejercicios for delete to authenticated using (public.es_profe());

-- registros de entrenamiento: cada alumno los suyos; el profe todos
create policy app_logs on public.logs_entrenamiento for all to authenticated
  using (public.es_profe() or cliente_id = public.mi_cliente_id())
  with check (public.es_profe() or cliente_id = public.mi_cliente_id());

-- sesiones: el alumno ve las suyas; modifica el profe
create policy app_sesiones_ver   on public.sesiones for select to authenticated using (public.es_profe() or cliente_id = public.mi_cliente_id());
create policy app_sesiones_profe on public.sesiones for all    to authenticated using (public.es_profe()) with check (public.es_profe());

-- plantillas: el alumno ve las que tiene asignadas; modifica el profe
create policy app_plantillas_ver   on public.plantillas for select to authenticated using (public.es_profe() or public.mi_cliente_id() = any (cliente_ids));
create policy app_plantillas_profe on public.plantillas for all    to authenticated using (public.es_profe()) with check (public.es_profe());

-- fotos/videos adjuntos: cada alumno los suyos; el profe todos
create policy app_archivos on public.sesion_archivos for all to authenticated
  using (public.es_profe() or cliente_id = public.mi_cliente_id())
  with check (public.es_profe() or cliente_id = public.mi_cliente_id());

-- ── El alumno no puede cambiar su rutina ni su ficha (solo marcar/comentar y su avatar) ──
create or replace function public.app_limitar_cambios_alumno() returns trigger
language plpgsql as $$
begin
  -- profe, o cambios hechos desde el panel de Supabase: sin límite
  if coalesce(auth.role(), '') <> 'authenticated' or public.es_profe() then
    return new;
  end if;
  if tg_table_name = 'ejercicios' then
    if (to_jsonb(new) - 'completado' - 'devolucion') is distinct from (to_jsonb(old) - 'completado' - 'devolucion') then
      raise exception 'Solo el profe puede modificar la rutina';
    end if;
  elsif tg_table_name = 'clientes' then
    if (to_jsonb(new) - 'avatar') is distinct from (to_jsonb(old) - 'avatar') then
      raise exception 'Solo el profe puede modificar los datos del alumno';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists app_limitar_ejercicios on public.ejercicios;
create trigger app_limitar_ejercicios before update on public.ejercicios
  for each row execute function public.app_limitar_cambios_alumno();
drop trigger if exists app_limitar_clientes on public.clientes;
create trigger app_limitar_clientes before update on public.clientes
  for each row execute function public.app_limitar_cambios_alumno();

-- ── Alta automática del alumno al registrarse ───────────────────────────────
create or replace function public.app_alta_cliente() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if lower(new.email) <> 'matiasdinardi10@gmail.com'
     and not exists (select 1 from public.clientes where lower(email) = lower(new.email)) then
    insert into public.clientes (nombre, email, edad, objetivo, estado, fecha_alta)
    values (
      coalesce(nullif(new.raw_user_meta_data ->> 'nombre', ''), split_part(new.email, '@', 1)),
      lower(new.email),
      nullif(new.raw_user_meta_data ->> 'edad', '')::int,
      nullif(new.raw_user_meta_data ->> 'objetivo', ''),
      'nuevo',
      (now() at time zone 'America/Montevideo')::date
    );
  end if;
  return new;
exception when others then
  return new; -- nunca bloquear un registro por esto
end $$;

drop trigger if exists app_alta_cliente on auth.users;
create trigger app_alta_cliente after insert on auth.users
  for each row execute function public.app_alta_cliente();

-- ── Videos: bucket privado ──────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sesion-archivos', 'sesion-archivos', false, 52428800, array['video/*', 'image/*'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Cada alumno solo puede ver/subir/borrar dentro de su carpeta (<su id>/...); el profe en todas.
drop policy if exists "sesion-archivos ver"    on storage.objects;
drop policy if exists "sesion-archivos subir"  on storage.objects;
drop policy if exists "sesion-archivos borrar" on storage.objects;
create policy "sesion-archivos ver" on storage.objects for select to authenticated
  using (bucket_id = 'sesion-archivos' and (public.es_profe() or (storage.foldername(name))[1] = public.mi_cliente_id()::text));
create policy "sesion-archivos subir" on storage.objects for insert to authenticated
  with check (bucket_id = 'sesion-archivos' and (public.es_profe() or (storage.foldername(name))[1] = public.mi_cliente_id()::text));
create policy "sesion-archivos borrar" on storage.objects for delete to authenticated
  using (bucket_id = 'sesion-archivos' and (public.es_profe() or (storage.foldername(name))[1] = public.mi_cliente_id()::text));
