-- ============================================================
-- Sweet Ted × Bevi&Go — Barista HR module migration
-- Run this in the Supabase SQL editor.
-- Includes: shifts, shift_breaks, leave_requests + RLS policies.
-- ============================================================

-- ─── 1. SHIFTS (clock in / out) ──────────────────────────────
create table if not exists public.shifts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  clock_in    timestamptz not null default now(),
  clock_out   timestamptz,
  notes       text,
  created_at  timestamptz not null default now()
);

create index if not exists shifts_user_idx       on public.shifts(user_id);
create index if not exists shifts_clock_in_idx   on public.shifts(clock_in desc);
create index if not exists shifts_open_idx       on public.shifts(user_id) where clock_out is null;

alter table public.shifts enable row level security;

drop policy if exists "shifts_select_own"  on public.shifts;
drop policy if exists "shifts_insert_own"  on public.shifts;
drop policy if exists "shifts_update_own"  on public.shifts;

create policy "shifts_select_own" on public.shifts
  for select to authenticated using (user_id = auth.uid());
create policy "shifts_insert_own" on public.shifts
  for insert to authenticated with check (user_id = auth.uid());
create policy "shifts_update_own" on public.shifts
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ─── 2. SHIFT BREAKS ─────────────────────────────────────────
create table if not exists public.shift_breaks (
  id           uuid primary key default gen_random_uuid(),
  shift_id     uuid not null references public.shifts(id) on delete cascade,
  break_start  timestamptz not null default now(),
  break_end    timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists shift_breaks_shift_idx on public.shift_breaks(shift_id);

alter table public.shift_breaks enable row level security;

drop policy if exists "breaks_select_own" on public.shift_breaks;
drop policy if exists "breaks_insert_own" on public.shift_breaks;
drop policy if exists "breaks_update_own" on public.shift_breaks;

create policy "breaks_select_own" on public.shift_breaks
  for select to authenticated
  using (exists (select 1 from public.shifts s where s.id = shift_id and s.user_id = auth.uid()));
create policy "breaks_insert_own" on public.shift_breaks
  for insert to authenticated
  with check (exists (select 1 from public.shifts s where s.id = shift_id and s.user_id = auth.uid()));
create policy "breaks_update_own" on public.shift_breaks
  for update to authenticated
  using (exists (select 1 from public.shifts s where s.id = shift_id and s.user_id = auth.uid()));

-- ─── 3. LEAVE / EMERGENCY REQUESTS ───────────────────────────
create table if not exists public.leave_requests (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  leave_type  text not null check (leave_type in ('vacation','sick','emergency','personal','other')),
  start_date  date not null,
  end_date    date not null,
  reason      text,
  status      text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists leave_user_idx   on public.leave_requests(user_id);
create index if not exists leave_status_idx on public.leave_requests(status);

alter table public.leave_requests enable row level security;

drop policy if exists "leave_select_own" on public.leave_requests;
drop policy if exists "leave_insert_own" on public.leave_requests;
drop policy if exists "leave_update_own" on public.leave_requests;

create policy "leave_select_own" on public.leave_requests
  for select to authenticated using (user_id = auth.uid());
create policy "leave_insert_own" on public.leave_requests
  for insert to authenticated with check (user_id = auth.uid());
-- Allow user to cancel their own pending request:
create policy "leave_update_own" on public.leave_requests
  for update to authenticated
  using (user_id = auth.uid() and status = 'pending')
  with check (user_id = auth.uid());

-- ─── 4. ADMIN VIEW (optional) ────────────────────────────────
-- If you want admin (sweetted20@gmail.com) to see / approve everyone's
-- shifts and leave requests, add these extra policies:
--
-- create policy "shifts_admin_all" on public.shifts
--   for all to authenticated
--   using ((select email from auth.users where id = auth.uid()) = 'sweetted20@gmail.com')
--   with check (true);
--
-- create policy "leave_admin_all" on public.leave_requests
--   for all to authenticated
--   using ((select email from auth.users where id = auth.uid()) = 'sweetted20@gmail.com')
--   with check (true);
