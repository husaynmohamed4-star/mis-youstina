-- YouTube Unlisted lessons + subscription-gated content.
-- Run AFTER setup.sql, full_platform.sql and upgrade_live_payments.sql.

alter table public.lessons
  add column if not exists video_provider text not null default 'supabase',
  add column if not exists youtube_video_id text;

-- Existing lessons keep their current provider and links. New lessons are saved as YouTube.
update public.lessons
set video_provider = 'youtube',
    youtube_video_id = coalesce(
      youtube_video_id,
      substring(video_url from '[?&]v=([A-Za-z0-9_-]{11})'),
      substring(video_url from 'youtu\.be/([A-Za-z0-9_-]{11})'),
      substring(video_url from 'youtube\.com/embed/([A-Za-z0-9_-]{11})')
    )
where video_url like '%youtube.com/%' or video_url like '%youtu.be/%';

alter table public.lessons drop constraint if exists lessons_video_provider_check;
alter table public.lessons add constraint lessons_video_provider_check
  check (video_provider in ('supabase','youtube'));

create index if not exists lessons_grade_published_idx on public.lessons(grade,published,published_at,expires_at);

-- Lesson videos and worksheets are visible only to admins or authenticated students
-- with an active subscription matching the grade on their profile.
drop policy if exists "students read active lessons" on public.lessons;
drop policy if exists "public read published lessons" on public.lessons;
create policy "subscribed students and admins read lessons" on public.lessons
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
    and exists (
      select 1 from public.student_subscriptions s
      join public.subscription_plans sp on sp.id = s.plan_id
      where s.user_id = auth.uid()
        and s.status = 'active'
        and s.starts_at <= now()
        and s.ends_at > now()
        and sp.is_active = true
        and sp.grade = lessons.grade
    )
  )
);

drop policy if exists "students read active worksheets" on public.worksheets;
drop policy if exists "public read published worksheets" on public.worksheets;
create policy "subscribed students and admins read worksheets" on public.worksheets
for select to authenticated
using (
  public.is_admin()
  or (
    published = true
    and (published_at is null or published_at <= now())
    and (expires_at is null or expires_at > now())
    and exists (select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=worksheets.grade)
    and exists (
      select 1 from public.student_subscriptions s
      join public.subscription_plans sp on sp.id=s.plan_id
      where s.user_id=auth.uid() and s.status='active'
        and s.starts_at <= now() and s.ends_at > now()
        and sp.is_active=true and sp.grade=worksheets.grade
    )
  )
);

-- Tests follow the same grade + active-subscription rule.
drop policy if exists "students read active quizzes" on public.quizzes;
create policy "subscribed students read active quizzes" on public.quizzes
for select to authenticated
using (
  public.is_admin()
  or (
    is_published = true
    and (starts_at is null or starts_at <= now())
    and (ends_at is null or ends_at > now())
    and exists (select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=quizzes.grade)
    and exists (
      select 1 from public.student_subscriptions s
      join public.subscription_plans sp on sp.id=s.plan_id
      where s.user_id=auth.uid() and s.status='active'
        and s.starts_at <= now() and s.ends_at > now()
        and sp.is_active=true and sp.grade=quizzes.grade
    )
  )
);

-- Ensure client reads are possible only through the RLS policies above.
grant select on public.lessons, public.worksheets, public.quizzes to authenticated;
notify pgrst, 'reload schema';


-- Secure the question view and server-side quiz submission as well.
create or replace view public.quiz_questions_public as
 select q.id, q.quiz_id, q.question_text, q.question_type, q.options, q.points, q.sort_order
 from public.quiz_questions q
 join public.quizzes z on z.id=q.quiz_id
 where z.is_published=true
   and (z.starts_at is null or z.starts_at<=now())
   and (z.ends_at is null or z.ends_at>now())
   and exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=z.grade)
   and exists (
     select 1 from public.student_subscriptions s
     join public.subscription_plans sp on sp.id=s.plan_id
     where s.user_id=auth.uid() and s.status='active'
       and s.starts_at<=now() and s.ends_at>now()
       and sp.is_active=true and sp.grade=z.grade
   );

create or replace function public.submit_quiz(p_quiz_id uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare q record; v_score integer:=0; v_total integer:=0; v_pct numeric(5,2):=0; v_pass boolean:=false; v_count integer:=0; v_attempt uuid;
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  if not exists(
    select 1 from public.quizzes z
    join public.profiles p on p.user_id=auth.uid() and p.grade=z.grade
    where z.id=p_quiz_id and z.is_published=true
      and (z.starts_at is null or z.starts_at<=now())
      and (z.ends_at is null or z.ends_at>now())
      and exists(select 1 from public.student_subscriptions s join public.subscription_plans sp on sp.id=s.plan_id
        where s.user_id=auth.uid() and s.status='active' and s.starts_at<=now() and s.ends_at>now()
          and sp.is_active=true and sp.grade=z.grade)
  ) then raise exception 'الاختبار غير متاح أو يحتاج اشتراكاً فعالاً لصفك الدراسي'; end if;
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

notify pgrst, 'reload schema';
