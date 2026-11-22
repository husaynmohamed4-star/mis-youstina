-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor
alter table public.profiles add column if not exists phone text;

create table if not exists public.visitors (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null,
  grade text not null,
  created_at timestamptz not null default now()
);
alter table public.visitors enable row level security;
grant insert on public.visitors to anon, authenticated;

drop policy if exists "anyone adds visitor" on public.visitors;
create policy "anyone adds visitor" on public.visitors for insert to anon, authenticated
with check (char_length(full_name) between 2 and 100 and phone ~ '^01[0-9]{9}$'
  and grade in ('أولى ثانوي','تانية ثانوي عام','تانية ثانوي بكالوريا','تالتة ثانوي'));
drop policy if exists "admins read visitors" on public.visitors;
create policy "admins read visitors" on public.visitors for select to authenticated using (public.is_admin());
drop policy if exists "admins delete visitors" on public.visitors;
create policy "admins delete visitors" on public.visitors for delete to authenticated using (public.is_admin());

create or replace function public.handle_new_student()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(user_id, full_name, grade, phone)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), coalesce(new.raw_user_meta_data->>'grade','أولى ثانوي'), new.raw_user_meta_data->>'phone')
  on conflict(user_id) do nothing;
  return new;
end; $$;
notify pgrst, 'reload schema';
