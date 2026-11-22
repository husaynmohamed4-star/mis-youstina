-- 1) Run this script in Supabase SQL Editor.
-- 2) Create a user in Authentication > Users, then grant admin role using the INSERT below.

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin'))
);

create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  grade text not null,
  unit text,
  video_url text not null,
  storage_path text not null,
  published boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.worksheets (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  grade text not null,
  file_url text not null,
  storage_path text not null,
  published boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.user_roles enable row level security;
alter table public.lessons enable row level security;
alter table public.worksheets enable row level security;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = 'admin'
  );
$$;

drop policy if exists "admins read own role" on public.user_roles;
create policy "admins read own role" on public.user_roles
for select to authenticated using (user_id = auth.uid());

drop policy if exists "public read published lessons" on public.lessons;
create policy "public read published lessons" on public.lessons
for select to anon, authenticated using (published = true);

drop policy if exists "admins manage lessons" on public.lessons;
create policy "admins manage lessons" on public.lessons
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "public read published worksheets" on public.worksheets;
create policy "public read published worksheets" on public.worksheets
for select to anon, authenticated using (published = true);

drop policy if exists "admins manage worksheets" on public.worksheets;
create policy "admins manage worksheets" on public.worksheets
for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('videos', 'videos', true, 2147483648, array['video/mp4','video/quicktime','video/webm','video/x-m4v']),
  ('worksheets', 'worksheets', true, 52428800, array['application/pdf'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "public view videos" on storage.objects;
create policy "public view videos" on storage.objects
for select to anon, authenticated using (bucket_id in ('videos','worksheets'));

drop policy if exists "admins upload files" on storage.objects;
create policy "admins upload files" on storage.objects
for insert to authenticated with check (bucket_id in ('videos','worksheets') and public.is_admin());

drop policy if exists "admins update files" on storage.objects;
create policy "admins update files" on storage.objects
for update to authenticated using (bucket_id in ('videos','worksheets') and public.is_admin())
with check (bucket_id in ('videos','worksheets') and public.is_admin());

drop policy if exists "admins delete files" on storage.objects;
create policy "admins delete files" on storage.objects
for delete to authenticated using (bucket_id in ('videos','worksheets') and public.is_admin());

-- After creating the admin user in Supabase Auth, run this with their actual UUID:
-- insert into public.user_roles (user_id, role) values ('PASTE_AUTH_USER_UUID_HERE', 'admin');
