-- ============================================================================
-- Sweet Ted × Bevi&Go — Batch 1: Sales-Facing Modules
-- Tables: menu_categories, menu_items, orders, order_items, register_sessions,
--         register_movements, dining_tables, rewards_program, customer_points,
--         points_ledger
-- Run this in your Supabase SQL editor.
-- ============================================================================

-- ─── MENU ────────────────────────────────────────────────────────────────────
create table if not exists public.menu_categories (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  category_type text not null default 'pastry' check (category_type in ('coffee','pastry','other')),
  sort_order    int  not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

create table if not exists public.menu_items (
  id            uuid primary key default gen_random_uuid(),
  category_id   uuid references public.menu_categories(id) on delete set null,
  name          text not null,
  description   text,
  price         numeric(10,2) not null default 0,
  cost          numeric(10,2) not null default 0,
  sku           text,
  image_url     text,
  is_active     boolean not null default true,
  show_in_pos   boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ─── ORDERS ──────────────────────────────────────────────────────────────────
create table if not exists public.orders (
  id            uuid primary key default gen_random_uuid(),
  order_number  serial unique,
  table_id      uuid,
  customer_id   uuid,
  cashier_id    uuid references auth.users(id) on delete set null,
  status        text not null default 'pending' check (status in ('pending','preparing','ready','completed','voided','refunded')),
  subtotal      numeric(10,2) not null default 0,
  discount      numeric(10,2) not null default 0,
  tax           numeric(10,2) not null default 0,
  total         numeric(10,2) not null default 0,
  payment_method text default 'cash',
  notes         text,
  created_at    timestamptz not null default now(),
  completed_at  timestamptz
);

create table if not exists public.order_items (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders(id) on delete cascade,
  menu_item_id  uuid references public.menu_items(id) on delete set null,
  name_snapshot text not null,
  qty           int  not null default 1,
  unit_price    numeric(10,2) not null default 0,
  line_total    numeric(10,2) not null default 0,
  notes         text
);

-- ─── REGISTER ────────────────────────────────────────────────────────────────
create table if not exists public.register_sessions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  opened_at       timestamptz not null default now(),
  closed_at       timestamptz,
  opening_float   numeric(10,2) not null default 0,
  closing_count   numeric(10,2),
  expected_total  numeric(10,2),
  variance        numeric(10,2),
  notes           text,
  status          text not null default 'open' check (status in ('open','closed'))
);

create table if not exists public.register_movements (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.register_sessions(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete set null,
  kind        text not null check (kind in ('cash_in','cash_out','payout','tip','refund')),
  amount      numeric(10,2) not null,
  reason      text,
  created_at  timestamptz not null default now()
);

-- ─── TABLES (dining) ─────────────────────────────────────────────────────────
create table if not exists public.dining_tables (
  id          uuid primary key default gen_random_uuid(),
  label       text not null,
  seats       int  not null default 2,
  area        text default 'Main',
  status      text not null default 'available' check (status in ('available','occupied','reserved','cleaning')),
  pos_x       int default 0,
  pos_y       int default 0,
  current_order_id uuid references public.orders(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- ─── REWARDS ─────────────────────────────────────────────────────────────────
create table if not exists public.rewards_program (
  id                uuid primary key default gen_random_uuid(),
  name              text not null default 'Sweet Ted Rewards',
  points_per_peso   numeric(8,4) not null default 1,
  peso_per_point    numeric(8,4) not null default 0.10,
  signup_bonus      int not null default 0,
  birthday_bonus    int not null default 50,
  is_active         boolean not null default true,
  updated_at        timestamptz not null default now()
);

create table if not exists public.customer_points (
  customer_id       uuid primary key,
  points_balance    int not null default 0,
  lifetime_points   int not null default 0,
  updated_at        timestamptz not null default now()
);

create table if not exists public.points_ledger (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid not null,
  order_id      uuid references public.orders(id) on delete set null,
  delta         int not null,
  reason        text,
  created_at    timestamptz not null default now()
);

-- ─── INDEXES ─────────────────────────────────────────────────────────────────
create index if not exists idx_menu_items_category on public.menu_items(category_id);
create index if not exists idx_orders_status       on public.orders(status);
create index if not exists idx_orders_created      on public.orders(created_at desc);
create index if not exists idx_order_items_order   on public.order_items(order_id);
create index if not exists idx_reg_sessions_user   on public.register_sessions(user_id);
create index if not exists idx_reg_movements_sess  on public.register_movements(session_id);
create index if not exists idx_points_ledger_cust  on public.points_ledger(customer_id);

-- ─── RLS ─────────────────────────────────────────────────────────────────────
alter table public.menu_categories     enable row level security;
alter table public.menu_items          enable row level security;
alter table public.orders              enable row level security;
alter table public.order_items         enable row level security;
alter table public.register_sessions   enable row level security;
alter table public.register_movements  enable row level security;
alter table public.dining_tables       enable row level security;
alter table public.rewards_program     enable row level security;
alter table public.customer_points     enable row level security;
alter table public.points_ledger       enable row level security;

-- Authenticated staff can read & write all sales data.
-- (Tighten later with a has_role('admin'/'barista') function if needed.)
do $$
declare t text;
begin
  for t in select unnest(array[
    'menu_categories','menu_items','orders','order_items',
    'register_sessions','register_movements','dining_tables',
    'rewards_program','customer_points','points_ledger'
  ]) loop
    execute format('drop policy if exists "auth_all_%s" on public.%I', t, t);
    execute format('create policy "auth_all_%s" on public.%I for all to authenticated using (true) with check (true)', t, t);
  end loop;
end $$;

-- ─── SEED DEFAULTS ───────────────────────────────────────────────────────────
insert into public.rewards_program (name, points_per_peso, peso_per_point, signup_bonus, birthday_bonus)
select 'Sweet Ted Rewards', 1, 0.10, 0, 50
where not exists (select 1 from public.rewards_program);

insert into public.menu_categories (name, category_type, sort_order)
select * from (values
  ('Espresso Bar','coffee',1),
  ('Specialty Drinks','coffee',2),
  ('Cookies','pastry',3),
  ('Cakes','pastry',4),
  ('Pastries','pastry',5)
) as v(name, category_type, sort_order)
where not exists (select 1 from public.menu_categories where name = v.name);
