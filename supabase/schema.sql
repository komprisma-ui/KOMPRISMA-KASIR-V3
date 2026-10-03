-- KASIRA multi-tenant database foundation
-- Run in a fresh Supabase/Postgres project.

create extension if not exists pgcrypto;

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  created_at timestamptz not null default now()
);

create table if not exists public.outlets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  code text not null,
  address text,
  created_at timestamptz not null default now(),
  unique (business_id, code)
);

create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','manager','cashier','warehouse')),
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sku text not null,
  barcode text,
  name text not null,
  category text not null default 'Umum',
  buy_price numeric(14,2) not null default 0,
  sell_price numeric(14,2) not null default 0,
  min_stock integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, sku)
);

create table if not exists public.product_stocks (
  id uuid primary key default gen_random_uuid(),
  outlet_id uuid not null references public.outlets(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity numeric(14,3) not null default 0,
  updated_at timestamptz not null default now(),
  unique (outlet_id, product_id)
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  points integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  address text,
  created_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  outlet_id uuid not null references public.outlets(id),
  cashier_id uuid references auth.users(id),
  customer_id uuid references public.customers(id),
  invoice_no text not null,
  subtotal numeric(14,2) not null default 0,
  discount numeric(14,2) not null default 0,
  tax numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  payment_method text not null default 'cash',
  paid_amount numeric(14,2) not null default 0,
  change_amount numeric(14,2) not null default 0,
  status text not null default 'paid',
  created_at timestamptz not null default now(),
  unique (business_id, invoice_no)
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity numeric(14,3) not null,
  unit_price numeric(14,2) not null,
  discount numeric(14,2) not null default 0,
  total numeric(14,2) not null
);

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  outlet_id uuid not null references public.outlets(id),
  supplier_id uuid references public.suppliers(id),
  invoice_no text not null,
  total numeric(14,2) not null default 0,
  status text not null default 'received',
  created_at timestamptz not null default now(),
  unique (business_id, invoice_no)
);

create table if not exists public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity numeric(14,3) not null,
  unit_cost numeric(14,2) not null,
  total numeric(14,2) not null
);

create table if not exists public.cash_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  outlet_id uuid not null references public.outlets(id),
  user_id uuid references auth.users(id),
  type text not null check (type in ('in','out')),
  amount numeric(14,2) not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid references auth.users(id),
  action text not null,
  entity text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_memberships_user on public.memberships(user_id);
create index if not exists idx_outlets_business on public.outlets(business_id);
create index if not exists idx_products_business on public.products(business_id);
create index if not exists idx_stocks_outlet on public.product_stocks(outlet_id);
create index if not exists idx_sales_business_created on public.sales(business_id, created_at desc);
create index if not exists idx_purchases_business_created on public.purchases(business_id, created_at desc);

alter table public.businesses enable row level security;
alter table public.outlets enable row level security;
alter table public.memberships enable row level security;
alter table public.products enable row level security;
alter table public.product_stocks enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.cash_transactions enable row level security;
alter table public.audit_logs enable row level security;

create or replace function public.is_business_member(target_business uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists (
  select 1 from public.memberships m
  where m.business_id=target_business and m.user_id=auth.uid()
); $$;

create or replace function public.is_business_manager(target_business uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists (
  select 1 from public.memberships m
  where m.business_id=target_business and m.user_id=auth.uid()
  and m.role in ('owner','manager')
); $$;

drop policy if exists business_member_read on public.businesses;
create policy business_member_read on public.businesses for select using (public.is_business_member(id));

drop policy if exists outlet_member_all on public.outlets;
create policy outlet_member_all on public.outlets for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists membership_self_read on public.memberships;
create policy membership_self_read on public.memberships for select using (user_id=auth.uid());

drop policy if exists product_member_all on public.products;
create policy product_member_all on public.products for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists stock_member_all on public.product_stocks;
create policy stock_member_all on public.product_stocks for all using (
  exists(select 1 from public.outlets o where o.id=outlet_id and public.is_business_member(o.business_id))
) with check (
  exists(select 1 from public.outlets o where o.id=outlet_id and public.is_business_member(o.business_id))
);

drop policy if exists customer_member_all on public.customers;
create policy customer_member_all on public.customers for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists supplier_member_all on public.suppliers;
create policy supplier_member_all on public.suppliers for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists sale_member_all on public.sales;
create policy sale_member_all on public.sales for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists purchase_member_all on public.purchases;
create policy purchase_member_all on public.purchases for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists cash_member_all on public.cash_transactions;
create policy cash_member_all on public.cash_transactions for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists audit_member_read on public.audit_logs;
create policy audit_member_read on public.audit_logs for select using (public.is_business_member(business_id));
