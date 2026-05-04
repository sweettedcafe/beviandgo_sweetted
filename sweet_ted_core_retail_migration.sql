-- =====================================================================
-- Sweet Ted — Batch 3 (Core Retail) Migration
-- Tables: customers, suppliers, discounts, locations, app_settings
-- Run AFTER sweet_ted_hr_audit_migration.sql (relies on has_role())
-- =====================================================================

-- ── CUSTOMERS ───────────────────────────────────────────────────────
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  birthday date,
  notes text,
  points_balance integer not null default 0,
  lifetime_spend numeric not null default 0,
  last_visit timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists customers_name_idx on public.customers (lower(name));
create index if not exists customers_phone_idx on public.customers (phone);

alter table public.customers enable row level security;

drop policy if exists "customers admin all" on public.customers;
create policy "customers admin all" on public.customers
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin') or public.has_role(auth.uid(), 'manager'))
  with check (public.has_role(auth.uid(), 'admin') or public.has_role(auth.uid(), 'manager'));

drop policy if exists "customers staff read" on public.customers;
create policy "customers staff read" on public.customers
  for select to authenticated using (true);

-- ── SUPPLIERS ───────────────────────────────────────────────────────
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  lead_time_days integer,
  last_order_date date,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists suppliers_name_idx on public.suppliers (lower(name));

alter table public.suppliers enable row level security;

drop policy if exists "suppliers admin all" on public.suppliers;
create policy "suppliers admin all" on public.suppliers
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin') or public.has_role(auth.uid(), 'manager'))
  with check (public.has_role(auth.uid(), 'admin') or public.has_role(auth.uid(), 'manager'));

drop policy if exists "suppliers staff read" on public.suppliers;
create policy "suppliers staff read" on public.suppliers
  for select to authenticated using (true);

-- ── DISCOUNTS ───────────────────────────────────────────────────────
create table if not exists public.discounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  discount_type text not null check (discount_type in ('percent','amount','senior_pwd','bogo')),
  value numeric not null default 0,
  min_order_total numeric,
  usage_limit integer,
  uses_count integer not null default 0,
  expires_at date,
  is_active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists discounts_code_idx on public.discounts (upper(code));

alter table public.discounts enable row level security;

drop policy if exists "discounts admin all" on public.discounts;
create policy "discounts admin all" on public.discounts
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin') or public.has_role(auth.uid(), 'manager'))
  with check (public.has_role(auth.uid(), 'admin') or public.has_role(auth.uid(), 'manager'));

drop policy if exists "discounts staff read" on public.discounts;
create policy "discounts staff read" on public.discounts
  for select to authenticated using (true);

-- ── LOCATIONS ───────────────────────────────────────────────────────
create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text unique,
  address text,
  phone text,
  manager_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.locations enable row level security;

drop policy if exists "locations admin all" on public.locations;
create policy "locations admin all" on public.locations
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists "locations all read" on public.locations;
create policy "locations all read" on public.locations
  for select to authenticated using (true);

-- ── APP SETTINGS (singleton) ────────────────────────────────────────
create table if not exists public.app_settings (
  id uuid primary key default gen_random_uuid(),
  business_name text,
  tagline text,
  phone text,
  email text,
  address text,
  currency text not null default 'PHP',
  vat_percent numeric not null default 12,
  vat_inclusive boolean not null default true,
  tax_id text,
  service_charge_percent numeric not null default 0,
  receipt_header text,
  receipt_footer text,
  receipt_show_logo boolean not null default true,
  receipt_paper_width integer not null default 80,
  default_location_id uuid references public.locations(id) on delete set null,
  low_stock_alert_email text,
  week_start_day integer not null default 1,
  overtime_threshold_hours numeric not null default 40,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;

drop policy if exists "app_settings admin all" on public.app_settings;
create policy "app_settings admin all" on public.app_settings
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists "app_settings all read" on public.app_settings;
create policy "app_settings all read" on public.app_settings
  for select to authenticated using (true);

-- ── SEED DEFAULTS ────────────────────────────────────────────────────
insert into public.locations (name, code, address, is_active)
select 'Sweet Ted Main', 'STM', 'Main Branch', true
where not exists (select 1 from public.locations);

insert into public.app_settings (business_name, tagline, currency, vat_percent, vat_inclusive)
select 'Sweet Ted Cafe', 'Brewed with love ☕', 'PHP', 12, true
where not exists (select 1 from public.app_settings);

-- =====================================================================
-- DONE — Batch 3 schema ready
-- =====================================================================
