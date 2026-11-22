-- Miss Youstina English Academy: full platform upgrade
-- Run once in Supabase SQL Editor AFTER the original setup.sql.
create extension if not exists pgcrypto;

alter table public.lessons
  add column if not exists description text,
  add column if not exists solution_url text,
  add column if not exists published_at timestamptz,
  add column if not exists expires_at timestamptz,
  add column if not exists sort_order integer not null default 0;
update public.lessons set published_at = coalesce(published_at, created_at) where published_at is null;

alter table public.worksheets
  add column if not exists description text,
  add column if not exists published_at timestamptz,
  add column if not exists expires_at timestamptz;
update public.worksheets set published_at = coalesce(published_at, created_at) where published_at is null;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  grade text not null default 'أولى ثانوي',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into public.profiles(user_id, full_name, grade, created_at)
select id, coalesce(raw_user_meta_data->>'full_name',''), coalesce(raw_user_meta_data->>'grade','أولى ثانوي'), created_at
from auth.users on conflict(user_id) do nothing;

create table if not exists public.quizzes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  grade text not null,
  lesson_id uuid references public.lessons(id) on delete set null,
  duration_minutes integer not null default 20 check(duration_minutes between 1 and 240),
  pass_mark integer not null default 50 check(pass_mark between 0 and 100),
  is_published boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  solution_video_url text,
  created_at timestamptz not null default now()
);
create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  question_text text not null,
  question_type text not null default 'mcq' check(question_type in ('mcq','true_false')),
  options jsonb not null default '[]'::jsonb,
  correct_answer text not null,
  explanation text,
  points integer not null default 1 check(points between 1 and 100),
  sort_order integer not null default 0
);
create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  score integer not null default 0,
  total_points integer not null default 0,
  percentage numeric(5,2) not null default 0,
  passed boolean not null default false,
  answers jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now()
);
create index if not exists quiz_attempts_user_idx on public.quiz_attempts(user_id, submitted_at desc);
create table if not exists public.lesson_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  completed boolean not null default false,
  last_watched_seconds integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key(user_id, lesson_id)
);
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  target_grade text,
  is_published boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

-- Create student profile automatically after signup.
create or replace function public.handle_new_student()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(user_id, full_name, grade)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), coalesce(new.raw_user_meta_data->>'grade','أولى ثانوي'))
  on conflict(user_id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users
for each row execute procedure public.handle_new_student();

alter table public.profiles enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.announcements enable row level security;

-- Replace earlier broad read policies so scheduled/expired content is respected.
drop policy if exists "public read published lessons" on public.lessons;
drop policy if exists "students read active lessons" on public.lessons;
create policy "students read active lessons" on public.lessons for select to anon, authenticated
using (published=true and (published_at is null or published_at <= now()) and (expires_at is null or expires_at > now()));
drop policy if exists "public read published worksheets" on public.worksheets;
drop policy if exists "students read active worksheets" on public.worksheets;
create policy "students read active worksheets" on public.worksheets for select to anon, authenticated
using (published=true and (published_at is null or published_at <= now()) and (expires_at is null or expires_at > now()));

-- Profiles: students can see/update only themselves; admins can manage all.
drop policy if exists "profile self read" on public.profiles;
create policy "profile self read" on public.profiles for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "profile self update" on public.profiles;
create policy "profile self update" on public.profiles for update to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
drop policy if exists "profile self insert" on public.profiles;
create policy "profile self insert" on public.profiles for insert to authenticated with check(user_id=auth.uid() or public.is_admin());

-- Quiz metadata and safe question view. Correct answers remain server-side.
drop policy if exists "students read active quizzes" on public.quizzes;
create policy "students read active quizzes" on public.quizzes for select to authenticated
using(is_published=true and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()) and exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=quizzes.grade));
drop policy if exists "admins manage quizzes" on public.quizzes;
create policy "admins manage quizzes" on public.quizzes for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "admins manage quiz questions" on public.quiz_questions;
create policy "admins manage quiz questions" on public.quiz_questions for all to authenticated using(public.is_admin()) with check(public.is_admin());
create or replace view public.quiz_questions_public as
 select q.id, q.quiz_id, q.question_text, q.question_type, q.options, q.points, q.sort_order
 from public.quiz_questions q join public.quizzes z on z.id=q.quiz_id
 where z.is_published=true and (z.starts_at is null or z.starts_at<=now()) and (z.ends_at is null or z.ends_at>now()) and exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=z.grade);
grant select on public.quiz_questions_public to authenticated;

-- Students can only read their own attempts and progress; admins can inspect all.
drop policy if exists "attempt self read" on public.quiz_attempts;
create policy "attempt self read" on public.quiz_attempts for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "progress self read" on public.lesson_progress;
create policy "progress self read" on public.lesson_progress for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "progress self write" on public.lesson_progress;
create policy "progress self write" on public.lesson_progress for all to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
drop policy if exists "students read active announcements" on public.announcements;
create policy "students read active announcements" on public.announcements for select to authenticated
using(is_published=true and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()) and (target_grade is null or exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=announcements.target_grade)));
drop policy if exists "admins manage announcements" on public.announcements;
create policy "admins manage announcements" on public.announcements for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Server-side grading: client submits question IDs and selected values, never receives answer keys.
create or replace function public.submit_quiz(p_quiz_id uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare q record; v_score integer:=0; v_total integer:=0; v_pct numeric(5,2):=0; v_pass boolean:=false; v_count integer:=0; v_attempt uuid;
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  if not exists(select 1 from public.quizzes z join public.profiles p on p.user_id=auth.uid() and p.grade=z.grade where z.id=p_quiz_id and z.is_published=true and (z.starts_at is null or z.starts_at<=now()) and (z.ends_at is null or z.ends_at>now())) then raise exception 'الاختبار غير متاح حالياً'; end if;
  for q in select id, correct_answer, points from public.quiz_questions where quiz_id=p_quiz_id loop
    v_count:=v_count+1; v_total:=v_total+q.points;
    if coalesce(p_answers->>q.id::text,'')=q.correct_answer then v_score:=v_score+q.points; end if;
  end loop;
  if v_count=0 then raise exception 'هذا الاختبار لا يحتوي على أسئلة'; end if;
  v_pct:=round((v_score::numeric/nullif(v_total,0))*100,2);
  select v_pct >= pass_mark into v_pass from public.quizzes where id=p_quiz_id;
  insert into public.quiz_attempts(quiz_id,user_id,score,total_points,percentage,passed,answers)
  values(p_quiz_id,auth.uid(),v_score,v_total,v_pct,v_pass,coalesce(p_answers,'{}'::jsonb)) returning id into v_attempt;
  return jsonb_build_object('attempt_id',v_attempt,'score',v_score,'total',v_total,'percentage',v_pct,'passed',v_pass);
end; $$;
revoke all on function public.submit_quiz(uuid,jsonb) from public;
grant execute on function public.submit_quiz(uuid,jsonb) to authenticated;

-- Keep student data private. Never expose admin roles or answer keys to anonymous users.

notify pgrst, 'reload schema';
