-- Miss Youstina: one-time migration for the EXISTING Supabase project.
-- Assumes the current project already has the core tables shown in Table Editor:
-- profiles, lessons, worksheets, quizzes, quiz_questions, quiz_attempts,
-- lesson_progress, announcements, user_roles.
-- This script does NOT create, drop, or truncate those tables or their data.
-- It adds YouTube Unlisted lesson support, free grade-based access, and Google Meet classes.

begin;

-- 1) YouTube metadata. Existing video_url values are preserved.
alter table public.lessons
  add column if not exists video_provider text not null default 'supabase',
  add column if not exists youtube_video_id text;

update public.lessons
set video_provider = 'youtube',
    youtube_video_id = coalesce(
      youtube_video_id,
      substring(video_url from '[?&]v=([A-Za-z0-9_-]{11})'),
      substring(video_url from 'youtu\.be/([A-Za-z0-9_-]{11})'),
      substring(video_url from 'youtube\.com/embed/([A-Za-z0-9_-]{11})')
    )
where video_url like '%youtube.com/%' or video_url like '%youtu.be/%';

drop index if exists public.lessons_grade_published_idx;
create index if not exists lessons_grade_published_idx
  on public.lessons (grade, published, published_at, expires_at);

-- 2) Free access: students must sign in and can only see published content
-- belonging to the grade stored in their own profile. Admins retain access.
alter table public.lessons enable row level security;
alter table public.worksheets enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_questions enable row level security;

-- Remove the original broad/public and any subscription-gated policies created
-- by earlier iterations, then install the intended free policies.
drop policy if exists "public read published lessons" on public.lessons;
drop policy if exists "students read active lessons" on public.lessons;
drop policy if exists "subscribed students and admins read lessons" on public.lessons;
drop policy if exists "students read published lessons free" on public.lessons;
create policy "students read published lessons free" on public.lessons
for select to authenticated
using (
  public.is_admin()
  or (
    published = true
    and (published_at is null or published_at <= now())
    and (expires_at is null or expires_at > now())
    and exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid() and p.grade = lessons.grade
    )
  )
);

drop policy if exists "public read published worksheets" on public.worksheets;
drop policy if exists "students read active worksheets" on public.worksheets;
drop policy if exists "subscribed students and admins read worksheets" on public.worksheets;
drop policy if exists "students read published worksheets free" on public.worksheets;
create policy "students read published worksheets free" on public.worksheets
for select to authenticated
using (
  public.is_admin()
  or (
    published = true
    and (published_at is null or published_at <= now())
    and (expires_at is null or expires_at > now())
    and exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid() and p.grade = worksheets.grade
    )
  )
);

drop policy if exists "students read active quizzes" on public.quizzes;
drop policy if exists "subscribed students read active quizzes" on public.quizzes;
drop policy if exists "students read published quizzes free" on public.quizzes;
create policy "students read published quizzes free" on public.quizzes
for select to authenticated
using (
  public.is_admin()
  or (
    is_published = true
    and (starts_at is null or starts_at <= now())
    and (ends_at is null or ends_at > now())
    and exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid() and p.grade = quizzes.grade
    )
  )
);

-- Public-safe question view: never exposes correct_answer or explanation.
create or replace view public.quiz_questions_public as
select q.id, q.quiz_id, q.question_text, q.question_type, q.options, q.points, q.sort_order
from public.quiz_questions q
join public.quizzes z on z.id = q.quiz_id
where z.is_published = true
  and (z.starts_at is null or z.starts_at <= now())
  and (z.ends_at is null or z.ends_at > now())
  and (
    public.is_admin()
    or exists (
      select 1 from public.profiles p
      where p.user_id = auth.uid() and p.grade = z.grade
    )
  );

grant select on public.lessons, public.worksheets, public.quizzes,
  public.quiz_questions_public to authenticated;

-- Quiz grading remains server-side and does not require a paid subscription.
create or replace function public.submit_quiz(p_quiz_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  q record;
  v_score integer := 0;
  v_total integer := 0;
  v_pct numeric(5,2) := 0;
  v_pass boolean := false;
  v_count integer := 0;
  v_attempt uuid;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  if not exists (
    select 1
    from public.quizzes z
    join public.profiles p on p.user_id = auth.uid() and p.grade = z.grade
    where z.id = p_quiz_id
      and z.is_published = true
      and (z.starts_at is null or z.starts_at <= now())
      and (z.ends_at is null or z.ends_at > now())
  ) then
    raise exception 'الاختبار غير متاح لصفك الدراسي حالياً';
  end if;

  for q in
    select id, correct_answer, points
    from public.quiz_questions
    where quiz_id = p_quiz_id
  loop
    v_count := v_count + 1;
    v_total := v_total + q.points;
    if coalesce(p_answers ->> q.id::text, '') = q.correct_answer then
      v_score := v_score + q.points;
    end if;
  end loop;

  if v_count = 0 then
    raise exception 'هذا الاختبار لا يحتوي على أسئلة';
  end if;

  v_pct := round((v_score::numeric / nullif(v_total, 0)) * 100, 2);
  select v_pct >= pass_mark into v_pass
  from public.quizzes where id = p_quiz_id;

  insert into public.quiz_attempts
    (quiz_id, user_id, score, total_points, percentage, passed, answers)
  values
    (p_quiz_id, auth.uid(), v_score, v_total, v_pct, v_pass, coalesce(p_answers, '{}'::jsonb))
  returning id into v_attempt;

  return jsonb_build_object(
    'attempt_id', v_attempt,
    'score', v_score,
    'total', v_total,
    'percentage', v_pct,
    'passed', v_pass
  );
end;
$$;
revoke all on function public.submit_quiz(uuid, jsonb) from public;
grant execute on function public.submit_quiz(uuid, jsonb) to authenticated;

-- 3) Google Meet schedule and attendance. No payment/subscription tables needed.
create table if not exists public.live_classes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  grade text not null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  meet_space_name text,
  meet_url text,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'live', 'ended', 'cancelled')),
  conference_record_name text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists live_classes_grade_start_idx
  on public.live_classes (grade, starts_at desc);

create table if not exists public.live_attendance (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.live_classes(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  participant_name text,
  joined_at timestamptz,
  left_at timestamptz,
  source text not null default 'manual'
    check (source in ('manual', 'meet_api')),
  unique (class_id, participant_name)
);

alter table public.live_classes enable row level security;
alter table public.live_attendance enable row level security;

drop policy if exists "students read own live classes" on public.live_classes;
drop policy if exists "students read grade live classes free" on public.live_classes;
create policy "students read grade live classes free" on public.live_classes
for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.profiles p
    where p.user_id = auth.uid() and p.grade = live_classes.grade
  )
);

drop policy if exists "admins manage live classes" on public.live_classes;
create policy "admins manage live classes" on public.live_classes
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "attendance own read" on public.live_attendance;
create policy "attendance own read" on public.live_attendance
for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "admins manage attendance" on public.live_attendance;
create policy "admins manage attendance" on public.live_attendance
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

grant select on public.live_classes, public.live_attendance to authenticated;

-- Enable realtime updates so the student page can react when a class ends.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'live_classes'
     ) then
    alter publication supabase_realtime add table public.live_classes;
  end if;
end
$$;

notify pgrst, 'reload schema';
commit;

-- Note: This SQL creates the database structure and access rules only.
-- Google Meet API credentials/OAuth configuration are configured separately in Vercel.
-- YouTube videos must be uploaded as Unlisted; the app stores their video IDs in lessons.
