-- ============================================================================
-- Sweet Ted × Bevi&Go — Batch 2: Staff / HR / Audit modules
-- Tables: app_role enum, user_roles, staff_profiles, assignments,
--         payroll_periods, payroll_entries, audit_log
-- Plus: has_role() security-definer function (avoids recursive RLS)
-- Run AFTER Batch 1 in your Supabase SQL editor.
-- ============================================================================

-- ─── ROLE ENUM + USER_ROLES (canonical pattern, NOT on profiles) ────────────
do $$ begin
  create type public.app_role as enum ('admin','manager','barista');
exception when duplicate_object then null; end $$;

create table if not exists public.user_roles (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role    app_role not null,
  unique (user_id, role)
);
alter table public.user_roles enable row level security;

create or replace function public.has_role(_user_id uuid, _role app_role)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role)
$$;

drop policy if exists "users_read_own_roles" on public.user_roles;
create policy "users_read_own_roles" on public.user_roles
  for select to authenticated using (user_id = auth.uid() or public.has_role(auth.uid(),'admin'));

drop policy if exists "admins_manage_roles" on public.user_roles;
create policy "admins_manage_roles" on public.user_roles
  for all to authenticated
  using (public.has_role(auth.uid(),'admin'))
  with check (public.has_role(auth.uid(),'admin'));

-- ─── STAFF PROFILES (NO role column here — roles live in user_roles) ────────
create table if not exists public.staff_profiles (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid unique references auth.users(id) on delete set null,
  full_name     text not null,
  email         text,
  phone         text,
  position      text default 'Barista',
  hourly_rate   numeric(10,2) not null default 0,
  hire_date     date,
  is_active     boolean not null default true,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ─── ASSIGNMENTS (daily tasks per staff/station) ────────────────────────────
create table if not exists public.assignments (
  id            uuid primary key default gen_random_uuid(),
  staff_id      uuid references public.staff_profiles(id) on delete set null,
  shift_date    date not null default current_date,
  station       text not null default 'Bar',  -- Bar, Register, Prep, Cleaning, Restock
  task          text not null,
  status        text not null default 'pending' check (status in ('pending','in_progress','done')),
  notes         text,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now()
);

-- ─── PAYROLL ────────────────────────────────────────────────────────────────
create table if not exists public.payroll_periods (
  id            uuid primary key default gen_random_uuid(),
  period_start  date not null,
  period_end    date not null,
  status        text not null default 'draft' check (status in ('draft','finalized','paid')),
  created_at    timestamptz not null default now(),
  finalized_at  timestamptz,
  unique (period_start, period_end)
);

create table if not exists public.payroll_entries (
  id            uuid primary key default gen_random_uuid(),
  period_id     uuid not null references public.payroll_periods(id) on delete cascade,
  staff_id      uuid not null references public.staff_profiles(id) on delete cascade,
  hours_regular numeric(10,2) not null default 0,
  hours_overtime numeric(10,2) not null default 0,
  hourly_rate   numeric(10,2) not null default 0,
  gross_pay     numeric(10,2) not null default 0,
  deductions    numeric(10,2) not null default 0,
  net_pay       numeric(10,2) not null default 0,
  notes         text,
  unique (period_id, staff_id)
);

-- ─── AUDIT LOG ──────────────────────────────────────────────────────────────
create table if not exists public.audit_log (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete set null,
  user_email    text,
  action        text not null,        -- 'create','update','delete','login','void','refund', etc.
  entity        text not null,        -- table/module name e.g. 'orders','menu_items'
  entity_id     text,
  summary       text,
  metadata      jsonb,
  created_at    timestamptz not null default now()
);

-- ─── INDEXES ────────────────────────────────────────────────────────────────
create index if not exists idx_staff_active   on public.staff_profiles(is_active);
create index if not exists idx_assign_date    on public.assignments(shift_date);
create index if not exists idx_assign_staff   on public.assignments(staff_id);
create index if not exists idx_pay_period     on public.payroll_entries(period_id);
create index if not exists idx_audit_created  on public.audit_log(created_at desc);
create index if not exists idx_audit_entity   on public.audit_log(entity);

-- ─── RLS ────────────────────────────────────────────────────────────────────
alter table public.staff_profiles    enable row level security;
alter table public.assignments       enable row level security;
alter table public.payroll_periods   enable row level security;
alter table public.payroll_entries   enable row level security;
alter table public.audit_log         enable row level security;

-- Staff profiles: admins/managers manage; baristas can read all, edit only their own row.
drop policy if exists "staff_read"        on public.staff_profiles;
drop policy if exists "staff_admin_write" on public.staff_profiles;
drop policy if exists "staff_self_update" on public.staff_profiles;
create policy "staff_read"        on public.staff_profiles for select to authenticated using (true);
create policy "staff_admin_write" on public.staff_profiles for all    to authenticated
  using (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'manager'))
  with check (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'manager'));
create policy "staff_self_update" on public.staff_profiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Assignments: everyone authenticated can read; admins/managers create/edit;
-- staff can update their own to mark done.
drop policy if exists "assign_read"   on public.assignments;
drop policy if exists "assign_write"  on public.assignments;
drop policy if exists "assign_self"   on public.assignments;
create policy "assign_read"  on public.assignments for select to authenticated using (true);
create policy "assign_write" on public.assignments for all    to authenticated
  using (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'manager'))
  with check (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'manager'));
create policy "assign_self"  on public.assignments for update to authenticated
  using (staff_id in (select id from public.staff_profiles where user_id = auth.uid()))
  with check (staff_id in (select id from public.staff_profiles where user_id = auth.uid()));

-- Payroll: admins/managers only.
drop policy if exists "pay_period_admin"  on public.payroll_periods;
drop policy if exists "pay_entries_admin" on public.payroll_entries;
create policy "pay_period_admin"  on public.payroll_periods for all to authenticated
  using (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'manager'))
  with check (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'manager'));
create policy "pay_entries_admin" on public.payroll_entries for all to authenticated
  using (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'manager'))
  with check (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'manager'));

-- Audit log: anyone authenticated can write (so the app can log actions);
-- only admins read.
drop policy if exists "audit_insert" on public.audit_log;
drop policy if exists "audit_read"   on public.audit_log;
create policy "audit_insert" on public.audit_log for insert to authenticated with check (true);
create policy "audit_read"   on public.audit_log for select to authenticated using (public.has_role(auth.uid(),'admin'));
