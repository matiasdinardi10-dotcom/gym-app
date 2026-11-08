-- MD Pro Training — activar videos adjuntos y orden de ejercicios
-- Correr UNA vez en Supabase: SQL Editor → New query → pegar todo → Run.
-- Es seguro correrlo más de una vez (no borra datos).

-- 1) Orden de ejercicios: el alumno ve el orden que arma el profe con las flechas.
alter table public.ejercicios add column if not exists orden integer;

-- 2) Espacio para videos (bucket público "sesion-archivos", máximo 50 MB por archivo).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sesion-archivos', 'sesion-archivos', true, 52428800, array['video/*', 'image/*'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 3) Permisos para que la app pueda ver, subir y borrar archivos SOLO de ese bucket.
drop policy if exists "sesion-archivos ver" on storage.objects;
drop policy if exists "sesion-archivos subir" on storage.objects;
drop policy if exists "sesion-archivos borrar" on storage.objects;

create policy "sesion-archivos ver" on storage.objects
  for select to anon, authenticated using (bucket_id = 'sesion-archivos');
create policy "sesion-archivos subir" on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'sesion-archivos');
create policy "sesion-archivos borrar" on storage.objects
  for delete to anon, authenticated using (bucket_id = 'sesion-archivos');
