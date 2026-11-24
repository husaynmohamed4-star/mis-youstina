-- Miss Youstina: free launch mode (no paid subscriptions / no Fawry gating)
-- Run this AFTER setup.sql, full_platform.sql, upgrade_live_payments.sql
-- and youtube_lessons_subscriptions.sql if those files were already applied.
-- Students still sign in; published content is limited to their own grade.

-- Lessons: published + scheduled + matching student grade; no subscription required.
drop policy if exists "subscribed students and admins read lessons" on public.lessons;
drop policy if exists "students read active lessons" on public.lessons;
create policy "students read published lessons free" on public.lessons
for select to authenticated
using (
  public.is_admin()
  or (
    published = true
    and (published_at is null or published_at <= now())
    and (expires_at is null or expires_at > now())
    and exists (select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=lessons.grade)
  )
);

-- Worksheets: same free grade-based access.
drop policy if exists "subscribed students and admins read worksheets" on public.worksheets;
drop policy if exists "students read active worksheets" on public.worksheets;
create policy "students read published worksheets free" on public.worksheets
for select to authenticated
using (
  public.is_admin()
  or (
    published = true
    and (published_at is null or published_at <= now())
    and (expires_at is null or expires_at > now())
    and exists (select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=worksheets.grade)
  )
);

-- Quizzes: published + in date range + matching grade; no subscription required.
drop policy if exists "subscribed students read active quizzes" on public.quizzes;
drop policy if exists "students read active quizzes" on public.quizzes;
create policy "students read published quizzes free" on public.quizzes
for select to authenticated
using (
  public.is_admin()
  or (
    is_published = true
    and (starts_at is null or starts_at <= now())
    and (ends_at is null or ends_at > now())
    and exists (select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=quizzes.grade)
  )
);

-- Quiz question view: preserve grade and publication checks, remove subscription condition.
create or replace view public.quiz_questions_public as
 select q.id, q.quiz_id, q.question_text, q.question_type, q.options, q.points, q.sort_order
 from public.quiz_questions q
 join public.quizzes z on z.id=q.quiz_id
 where z.is_published=true
   and (z.starts_at is null or z.starts_at<=now())
   and (z.ends_at is null or z.ends_at>now())
   and exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=z.grade);

grant select on public.lessons, public.worksheets, public.quizzes, public.quiz_questions_public to authenticated;

-- Quiz submission: no subscription check, but keep login, grade, and publication checks.
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
  ) then raise exception 'الاختبار غير متاح لصفك الدراسي حالياً'; end if;
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

-- Live classes: students of the matching grade can view upcoming/live classes free.
drop policy if exists "students read own live classes" on public.live_classes;
create policy "students read grade live classes free" on public.live_classes
for select to authenticated
using (
  public.is_admin()
  or exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=live_classes.grade)
);

notify pgrst, 'reload schema';
