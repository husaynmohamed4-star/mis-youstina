-- Miss Youstina: subscriptions, Fawry payments and Google Meet classes
-- Run once AFTER setup.sql and full_platform.sql in Supabase SQL Editor.
alter table public.profiles add column if not exists phone text;

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  grade text not null,
  price numeric(10,2) not null check(price > 0),
  duration_days integer not null default 30 check(duration_days between 1 and 366),
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.student_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null default 'pending' check(status in ('pending','active','expired','cancelled')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists student_subscriptions_user_status_idx on public.student_subscriptions(user_id,status,ends_at desc);

create table if not exists public.payment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subscription_id uuid references public.student_subscriptions(id) on delete set null,
  merchant_ref_num text not null unique,
  fawry_reference text,
  amount numeric(10,2) not null,
  status text not null default 'PENDING' check(status in ('PENDING','PAID','EXPIRED','CANCELLED','FAILED','REFUNDED')),
  raw_response jsonb,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table if not exists public.activation_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  plan_id uuid not null references public.subscription_plans(id),
  redeemed_by uuid references auth.users(id),
  redeemed_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.live_classes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  grade text not null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  meet_space_name text,
  meet_url text,
  status text not null default 'scheduled' check(status in ('scheduled','live','ended','cancelled')),
  conference_record_name text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists live_classes_grade_start_idx on public.live_classes(grade,starts_at desc);

create table if not exists public.live_attendance (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.live_classes(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  participant_name text,
  joined_at timestamptz,
  left_at timestamptz,
  source text not null default 'manual' check(source in ('manual','meet_api')),
  unique(class_id,participant_name)
);

alter table public.subscription_plans enable row level security;
alter table public.student_subscriptions enable row level security;
alter table public.payment_orders enable row level security;
alter table public.activation_codes enable row level security;
alter table public.live_classes enable row level security;
alter table public.live_attendance enable row level security;

drop policy if exists "active plans readable" on public.subscription_plans;
create policy "active plans readable" on public.subscription_plans for select to anon,authenticated using(is_active=true or public.is_admin());
drop policy if exists "admins manage plans" on public.subscription_plans;
create policy "admins manage plans" on public.subscription_plans for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "student subscriptions read own" on public.student_subscriptions;
create policy "student subscriptions read own" on public.student_subscriptions for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "admin manage subscriptions" on public.student_subscriptions;
create policy "admin manage subscriptions" on public.student_subscriptions for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "student payments read own" on public.payment_orders;
create policy "student payments read own" on public.payment_orders for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "admin manage payments" on public.payment_orders;
create policy "admin manage payments" on public.payment_orders for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "admins manage activation codes" on public.activation_codes;
create policy "admins manage activation codes" on public.activation_codes for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "students read own live classes" on public.live_classes;
create policy "students read own live classes" on public.live_classes for select to authenticated using(public.is_admin() or exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.grade=live_classes.grade and exists(select 1 from public.student_subscriptions s where s.user_id=auth.uid() and s.status='active' and s.ends_at>now())));
drop policy if exists "admins manage live classes" on public.live_classes;
create policy "admins manage live classes" on public.live_classes for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "attendance own read" on public.live_attendance;
create policy "attendance own read" on public.live_attendance for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "admins manage attendance" on public.live_attendance;
create policy "admins manage attendance" on public.live_attendance for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Server-only APIs use service_role; no client-side writes to payments or activation codes.
grant select on public.subscription_plans, public.student_subscriptions, public.payment_orders, public.live_classes, public.live_attendance to authenticated;
grant select on public.subscription_plans to anon;

-- Optional starter plans: change prices before publishing.
-- insert into public.subscription_plans(name,grade,price,duration_days,description) values
-- ('اشتراك شهري - أولى ثانوي','أولى ثانوي',250,30,'الوصول لدروس الصف والاختبارات'),
-- ('اشتراك شهري - تانية ثانوي عام','تانية ثانوي عام',250,30,'الوصول لدروس الصف والاختبارات'),
-- ('اشتراك شهري - تانية ثانوي بكالوريا','تانية ثانوي بكالوريا',250,30,'الوصول لدروس الصف والاختبارات'),
-- ('اشتراك شهري - تالتة ثانوي','تالتة ثانوي',300,30,'الوصول لدروس الصف والاختبارات');

notify pgrst,'reload schema';

-- One-time activation code redemption. Only a logged-in student can redeem a valid unused code.
create or replace function public.redeem_activation_code(p_code text)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_code public.activation_codes%rowtype; v_days integer; v_sub uuid;
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  update public.activation_codes set redeemed_by=auth.uid(),redeemed_at=now()
  where code_hash=encode(digest(upper(trim(p_code)),'sha256'),'hex') and redeemed_by is null and (expires_at is null or expires_at>now())
  returning * into v_code;
  if v_code.id is null then raise exception 'كود التفعيل غير صحيح أو مستخدم أو منتهي الصلاحية'; end if;
  select duration_days into v_days from public.subscription_plans where id=v_code.plan_id and is_active=true;
  if v_days is null then raise exception 'الباقة المرتبطة بالكود غير متاحة'; end if;
  insert into public.student_subscriptions(user_id,plan_id,status,starts_at,ends_at)
  values(auth.uid(),v_code.plan_id,'active',now(),now()+make_interval(days=>v_days)) returning id into v_sub;
  return jsonb_build_object('subscription_id',v_sub,'ends_at',now()+make_interval(days=>v_days));
end; $$;
revoke all on function public.redeem_activation_code(text) from public;
grant execute on function public.redeem_activation_code(text) to authenticated;

-- Keep phone from signup metadata available for Fawry checkout.
create or replace function public.handle_new_student()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(user_id,full_name,grade,phone)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),coalesce(new.raw_user_meta_data->>'grade','أولى ثانوي'),coalesce(new.raw_user_meta_data->>'phone',''))
  on conflict(user_id) do update set phone=coalesce(nullif(excluded.phone,''),public.profiles.phone);
  return new;
end; $$;

do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='live_classes') then
    alter publication supabase_realtime add table public.live_classes;
  end if;
end $$;
