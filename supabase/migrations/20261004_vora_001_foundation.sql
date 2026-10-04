-- VORA foundation
-- Branch: vora-foundation
-- Purpose: member/network/commerce reward foundation.
-- This migration is additive and does not remove existing KASIRA/POS tables.

create extension if not exists pgcrypto;

-- ============================================================
-- MEMBERS
-- ============================================================

create table if not exists public.vora_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_code text not null,
  display_name text not null,
  phone text,
  email text,
  status text not null default 'active'
    check (status in ('pending','active','suspended','blocked','inactive')),
  sponsor_member_id uuid references public.vora_members(id) on delete set null,
  placement_parent_id uuid references public.vora_members(id) on delete set null,
  placement_side text check (placement_side in ('left','right')),
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, member_code),
  unique (business_id, user_id)
);

create index if not exists idx_vora_members_business_status
  on public.vora_members(business_id,status);
create index if not exists idx_vora_members_sponsor
  on public.vora_members(sponsor_member_id);
create index if not exists idx_vora_members_parent
  on public.vora_members(placement_parent_id);

-- Prevent self/cyclic direct relationships at row level.
alter table public.vora_members
  drop constraint if exists vora_member_no_self_sponsor;
alter table public.vora_members
  add constraint vora_member_no_self_sponsor
  check (sponsor_member_id is null or sponsor_member_id <> id);

alter table public.vora_members
  drop constraint if exists vora_member_no_self_parent;
alter table public.vora_members
  add constraint vora_member_no_self_parent
  check (placement_parent_id is null or placement_parent_id <> id);

-- ============================================================
-- NETWORK CLOSURE
-- Materialized ancestor/descendant paths for fast reporting.
-- Direct tree relationships remain in vora_members.
-- ============================================================

create table if not exists public.vora_network_paths (
  business_id uuid not null references public.businesses(id) on delete cascade,
  ancestor_member_id uuid not null references public.vora_members(id) on delete cascade,
  descendant_member_id uuid not null references public.vora_members(id) on delete cascade,
  depth integer not null check (depth >= 0),
  path_type text not null default 'placement'
    check (path_type in ('placement','sponsor')),
  created_at timestamptz not null default now(),
  primary key (ancestor_member_id, descendant_member_id, path_type)
);

create index if not exists idx_vora_paths_ancestor
  on public.vora_network_paths(business_id,ancestor_member_id,path_type,depth);
create index if not exists idx_vora_paths_descendant
  on public.vora_network_paths(business_id,descendant_member_id,path_type,depth);

-- ============================================================
-- RANKS / PV / CV
-- ============================================================

create table if not exists public.vora_rank_rules (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  code text not null,
  name text not null,
  rank_order integer not null check (rank_order >= 0),
  min_personal_pv numeric(18,2) not null default 0 check (min_personal_pv >= 0),
  min_group_pv numeric(18,2) not null default 0 check (min_group_pv >= 0),
  min_direct_active integer not null default 0 check (min_direct_active >= 0),
  max_depth integer check (max_depth is null or max_depth >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id,code),
  unique (business_id,rank_order)
);

create table if not exists public.vora_member_periods (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  member_id uuid not null references public.vora_members(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  personal_pv numeric(18,2) not null default 0 check (personal_pv >= 0),
  personal_cv numeric(18,2) not null default 0 check (personal_cv >= 0),
  group_pv numeric(18,2) not null default 0 check (group_pv >= 0),
  group_cv numeric(18,2) not null default 0 check (group_cv >= 0),
  direct_active integer not null default 0 check (direct_active >= 0),
  rank_id uuid references public.vora_rank_rules(id) on delete set null,
  status text not null default 'open'
    check (status in ('open','calculated','locked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_end >= period_start),
  unique (business_id,member_id,period_start,period_end)
);

-- ============================================================
-- ORDERS / ORDER ITEMS
-- Commerce source for qualification and commission.
-- ============================================================

create table if not exists public.vora_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  order_no text not null,
  customer_user_id uuid references auth.users(id) on delete set null,
  customer_member_id uuid references public.vora_members(id) on delete set null,
  seller_member_id uuid references public.vora_members(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','paid','processing','completed','cancelled','refunded','partially_refunded')),
  currency text not null default 'IDR',
  subtotal numeric(18,2) not null default 0 check (subtotal >= 0),
  discount numeric(18,2) not null default 0 check (discount >= 0),
  tax numeric(18,2) not null default 0 check (tax >= 0),
  shipping numeric(18,2) not null default 0 check (shipping >= 0),
  total numeric(18,2) not null default 0 check (total >= 0),
  qualified_amount numeric(18,2) not null default 0 check (qualified_amount >= 0),
  pv numeric(18,2) not null default 0 check (pv >= 0),
  cv numeric(18,2) not null default 0 check (cv >= 0),
  paid_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  idempotency_key text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,order_no)
);

create unique index if not exists uq_vora_orders_idempotency
  on public.vora_orders(business_id,idempotency_key)
  where idempotency_key is not null;

create index if not exists idx_vora_orders_member
  on public.vora_orders(business_id,seller_member_id,status,created_at desc);

create table if not exists public.vora_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.vora_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_price numeric(18,2) not null check (unit_price >= 0),
  discount numeric(18,2) not null default 0 check (discount >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  pv numeric(18,2) not null default 0 check (pv >= 0),
  cv numeric(18,2) not null default 0 check (cv >= 0),
  metadata jsonb not null default '{}'::jsonb
);

-- ============================================================
-- COMMISSION RULES + IMMUTABLE LEDGER
-- ============================================================

create table if not exists public.vora_commission_rules (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  code text not null,
  name text not null,
  rule_type text not null
    check (rule_type in ('retail_margin','direct_sales','unilevel','rank_bonus','customer_bonus')),
  level integer check (level is null or level > 0),
  rate numeric(8,4) not null default 0 check (rate >= 0 and rate <= 100),
  fixed_amount numeric(18,2) not null default 0 check (fixed_amount >= 0),
  min_rank_order integer,
  max_rank_order integer,
  active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (business_id,code)
);

create table if not exists public.vora_commission_ledger (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  member_id uuid not null references public.vora_members(id) on delete restrict,
  order_id uuid references public.vora_orders(id) on delete restrict,
  rule_id uuid references public.vora_commission_rules(id) on delete restrict,
  entry_type text not null
    check (entry_type in ('credit','reversal','adjustment')),
  amount numeric(18,2) not null check (amount <> 0),
  currency text not null default 'IDR',
  source_key text not null,
  related_entry_id uuid references public.vora_commission_ledger(id) on delete restrict,
  status text not null default 'posted'
    check (status in ('pending','posted','void')),
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (business_id,source_key)
);

create index if not exists idx_vora_commission_member
  on public.vora_commission_ledger(business_id,member_id,status,created_at desc);
create index if not exists idx_vora_commission_order
  on public.vora_commission_ledger(order_id);

-- ============================================================
-- WALLET
-- ============================================================

create table if not exists public.vora_wallets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  member_id uuid not null references public.vora_members(id) on delete cascade,
  currency text not null default 'IDR',
  available_balance numeric(18,2) not null default 0 check (available_balance >= 0),
  pending_balance numeric(18,2) not null default 0 check (pending_balance >= 0),
  locked_balance numeric(18,2) not null default 0 check (locked_balance >= 0),
  status text not null default 'active'
    check (status in ('active','frozen','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,member_id,currency)
);

create table if not exists public.vora_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.vora_wallets(id) on delete restrict,
  business_id uuid not null references public.businesses(id) on delete cascade,
  member_id uuid not null references public.vora_members(id) on delete restrict,
  direction text not null check (direction in ('credit','debit')),
  transaction_type text not null
    check (transaction_type in ('commission','bonus','refund_reversal','withdrawal','withdrawal_reversal','adjustment')),
  amount numeric(18,2) not null check (amount > 0),
  balance_after numeric(18,2) not null check (balance_after >= 0),
  source_type text,
  source_id uuid,
  idempotency_key text not null,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (wallet_id,idempotency_key)
);

create index if not exists idx_vora_wallet_tx_member
  on public.vora_wallet_transactions(business_id,member_id,created_at desc);

create table if not exists public.vora_withdrawals (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.vora_wallets(id) on delete restrict,
  business_id uuid not null references public.businesses(id) on delete cascade,
  member_id uuid not null references public.vora_members(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  fee numeric(18,2) not null default 0 check (fee >= 0),
  net_amount numeric(18,2) not null check (net_amount > 0),
  method text not null check (method in ('bank_transfer','ewallet')),
  destination jsonb not null default '{}'::jsonb,
  status text not null default 'requested'
    check (status in ('requested','approved','processing','paid','rejected','cancelled')),
  idempotency_key text not null,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references auth.users(id) on delete set null,
  rejection_reason text,
  unique (business_id,idempotency_key)
);

-- ============================================================
-- AUDIT
-- ============================================================

create table if not exists public.vora_audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity text not null,
  entity_id uuid,
  request_id text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_vora_audit_business_time
  on public.vora_audit_logs(business_id,created_at desc);

-- ============================================================
-- AUTHORIZATION HELPERS
-- ============================================================

create or replace function public.vora_is_member_of_business(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists (
    select 1
    from public.vora_members m
    where m.business_id=p_business_id
      and m.user_id=(select auth.uid())
      and m.status in ('pending','active')
  )
$$;

create or replace function public.vora_has_admin_role(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select public.has_business_role(
    p_business_id,
    array['owner','manager']
  )
$$;

revoke all on function public.vora_is_member_of_business(uuid) from public;
revoke all on function public.vora_has_admin_role(uuid) from public;
grant execute on function public.vora_is_member_of_business(uuid) to authenticated;
grant execute on function public.vora_has_admin_role(uuid) to authenticated;

-- ============================================================
-- RLS
-- ============================================================

alter table public.vora_members enable row level security;
alter table public.vora_network_paths enable row level security;
alter table public.vora_rank_rules enable row level security;
alter table public.vora_member_periods enable row level security;
alter table public.vora_orders enable row level security;
alter table public.vora_order_items enable row level security;
alter table public.vora_commission_rules enable row level security;
alter table public.vora_commission_ledger enable row level security;
alter table public.vora_wallets enable row level security;
alter table public.vora_wallet_transactions enable row level security;
alter table public.vora_withdrawals enable row level security;
alter table public.vora_audit_logs enable row level security;

-- Members: a member can read their own record; admins can manage.
drop policy if exists vora_members_self_select on public.vora_members;
create policy vora_members_self_select on public.vora_members
for select to authenticated
using (user_id=(select auth.uid()));

drop policy if exists vora_members_admin_all on public.vora_members;
create policy vora_members_admin_all on public.vora_members
for all to authenticated
using (public.vora_has_admin_role(business_id))
with check (public.vora_has_admin_role(business_id));

-- Network paths: members may inspect paths involving themselves; admins see all.
drop policy if exists vora_paths_member_select on public.vora_network_paths;
create policy vora_paths_member_select on public.vora_network_paths
for select to authenticated
using (
  exists (
    select 1 from public.vora_members me
    where me.user_id=(select auth.uid())
      and me.business_id=vora_network_paths.business_id
      and (me.id=vora_network_paths.ancestor_member_id or me.id=vora_network_paths.descendant_member_id)
  )
  or public.vora_has_admin_role(business_id)
);

-- Rules/ranks: members can read active rules.
drop policy if exists vora_rank_rules_select on public.vora_rank_rules;
create policy vora_rank_rules_select on public.vora_rank_rules
for select to authenticated
using (active or public.vora_has_admin_role(business_id));

drop policy if exists vora_rank_rules_admin on public.vora_rank_rules;
create policy vora_rank_rules_admin on public.vora_rank_rules
for all to authenticated
using (public.vora_has_admin_role(business_id))
with check (public.vora_has_admin_role(business_id));

-- Periods: self read, admin manage.
drop policy if exists vora_period_self_select on public.vora_member_periods;
create policy vora_period_self_select on public.vora_member_periods
for select to authenticated
using (
  exists (
    select 1 from public.vora_members m
    where m.id=member_id and m.user_id=(select auth.uid())
  )
  or public.vora_has_admin_role(business_id)
);

drop policy if exists vora_period_admin_all on public.vora_member_periods;
create policy vora_period_admin_all on public.vora_member_periods
for all to authenticated
using (public.vora_has_admin_role(business_id))
with check (public.vora_has_admin_role(business_id));

-- Orders: owner/admin + seller/customer participant.
drop policy if exists vora_orders_participant_select on public.vora_orders;
create policy vora_orders_participant_select on public.vora_orders
for select to authenticated
using (
  customer_user_id=(select auth.uid())
  or exists (
    select 1 from public.vora_members m
    where m.id=seller_member_id and m.user_id=(select auth.uid())
  )
  or public.vora_has_admin_role(business_id)
);

drop policy if exists vora_orders_admin_write on public.vora_orders;
create policy vora_orders_admin_write on public.vora_orders
for all to authenticated
using (public.vora_has_admin_role(business_id))
with check (public.vora_has_admin_role(business_id));

-- Order items follow order visibility.
drop policy if exists vora_order_items_select on public.vora_order_items;
create policy vora_order_items_select on public.vora_order_items
for select to authenticated
using (
  exists (
    select 1 from public.vora_orders o
    where o.id=order_id
      and (
        o.customer_user_id=(select auth.uid())
        or exists (
          select 1 from public.vora_members m
          where m.id=o.seller_member_id and m.user_id=(select auth.uid())
        )
        or public.vora_has_admin_role(o.business_id)
      )
  )
);

drop policy if exists vora_order_items_admin_write on public.vora_order_items;
create policy vora_order_items_admin_write on public.vora_order_items
for all to authenticated
using (
  exists (
    select 1 from public.vora_orders o
    where o.id=order_id and public.vora_has_admin_role(o.business_id)
  )
)
with check (
  exists (
    select 1 from public.vora_orders o
    where o.id=order_id and public.vora_has_admin_role(o.business_id)
  )
);

-- Commission rules: public read only when active; admin write.
drop policy if exists vora_commission_rules_select on public.vora_commission_rules;
create policy vora_commission_rules_select on public.vora_commission_rules
for select to authenticated
using (active or public.vora_has_admin_role(business_id));

drop policy if exists vora_commission_rules_admin on public.vora_commission_rules;
create policy vora_commission_rules_admin on public.vora_commission_rules
for all to authenticated
using (public.vora_has_admin_role(business_id))
with check (public.vora_has_admin_role(business_id));

-- Commission ledger is read-only to members; no direct client mutation.
drop policy if exists vora_commission_self_select on public.vora_commission_ledger;
create policy vora_commission_self_select on public.vora_commission_ledger
for select to authenticated
using (
  exists (
    select 1 from public.vora_members m
    where m.id=member_id and m.user_id=(select auth.uid())
  )
  or public.vora_has_admin_role(business_id)
);

-- Wallets/transactions are member read, admin read. Mutations go through RPC/backend.
drop policy if exists vora_wallet_self_select on public.vora_wallets;
create policy vora_wallet_self_select on public.vora_wallets
for select to authenticated
using (
  exists (
    select 1 from public.vora_members m
    where m.id=member_id and m.user_id=(select auth.uid())
  )
  or public.vora_has_admin_role(business_id)
);

drop policy if exists vora_wallet_tx_self_select on public.vora_wallet_transactions;
create policy vora_wallet_tx_self_select on public.vora_wallet_transactions
for select to authenticated
using (
  exists (
    select 1 from public.vora_members m
    where m.id=member_id and m.user_id=(select auth.uid())
  )
  or public.vora_has_admin_role(business_id)
);

drop policy if exists vora_withdrawal_self_select on public.vora_withdrawals;
create policy vora_withdrawal_self_select on public.vora_withdrawals
for select to authenticated
using (
  exists (
    select 1 from public.vora_members m
    where m.id=member_id and m.user_id=(select auth.uid())
  )
  or public.vora_has_admin_role(business_id)
);

drop policy if exists vora_withdrawal_member_insert on public.vora_withdrawals;
create policy vora_withdrawal_member_insert on public.vora_withdrawals
for insert to authenticated
with check (
  exists (
    select 1 from public.vora_members m
    where m.id=member_id
      and m.user_id=(select auth.uid())
      and m.business_id=vora_withdrawals.business_id
      and m.status='active'
  )
);

drop policy if exists vora_withdrawal_admin_update on public.vora_withdrawals;
create policy vora_withdrawal_admin_update on public.vora_withdrawals
for update to authenticated
using (public.vora_has_admin_role(business_id))
with check (public.vora_has_admin_role(business_id));

drop policy if exists vora_audit_admin_select on public.vora_audit_logs;
create policy vora_audit_admin_select on public.vora_audit_logs
for select to authenticated
using (public.vora_has_admin_role(business_id));

-- Explicitly prevent anonymous access.
revoke all on table
  public.vora_members,
  public.vora_network_paths,
  public.vora_rank_rules,
  public.vora_member_periods,
  public.vora_orders,
  public.vora_order_items,
  public.vora_commission_rules,
  public.vora_commission_ledger,
  public.vora_wallets,
  public.vora_wallet_transactions,
  public.vora_withdrawals,
  public.vora_audit_logs
from anon;

-- Financial/network tables are not directly writable by the public client.
revoke insert, update, delete on table
  public.vora_network_paths,
  public.vora_commission_ledger,
  public.vora_wallets,
  public.vora_wallet_transactions,
  public.vora_audit_logs
from authenticated;

grant select on table
  public.vora_members,
  public.vora_network_paths,
  public.vora_rank_rules,
  public.vora_member_periods,
  public.vora_orders,
  public.vora_order_items,
  public.vora_commission_rules,
  public.vora_commission_ledger,
  public.vora_wallets,
  public.vora_wallet_transactions,
  public.vora_withdrawals,
  public.vora_audit_logs
to authenticated;

grant insert on public.vora_withdrawals to authenticated;

-- ============================================================
-- BASIC MEMBER REGISTRATION RPC
-- Creates a member safely inside an existing business.
-- Network closure calculation is intentionally separate and server-controlled.
-- ============================================================

create or replace function public.vora_register_member(
  p_business_id uuid,
  p_member_code text,
  p_display_name text,
  p_phone text default null,
  p_sponsor_member_id uuid default null,
  p_placement_parent_id uuid default null,
  p_placement_side text default null
)
returns uuid
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_id uuid;
begin
  if not public.has_business_role(p_business_id,array['owner','manager']) then
    raise exception 'not authorized';
  end if;

  if nullif(trim(p_member_code),'') is null or nullif(trim(p_display_name),'') is null then
    raise exception 'member_code and display_name are required';
  end if;

  if p_sponsor_member_id is not null and not exists (
    select 1 from public.vora_members
    where id=p_sponsor_member_id
      and business_id=p_business_id
      and status='active'
  ) then
    raise exception 'invalid sponsor';
  end if;

  if p_placement_parent_id is not null and not exists (
    select 1 from public.vora_members
    where id=p_placement_parent_id
      and business_id=p_business_id
      and status='active'
  ) then
    raise exception 'invalid placement parent';
  end if;

  if p_placement_side is not null
     and p_placement_side not in ('left','right') then
    raise exception 'invalid placement side';
  end if;

  insert into public.vora_members(
    business_id,user_id,member_code,display_name,phone,
    sponsor_member_id,placement_parent_id,placement_side
  )
  values(
    p_business_id,(select auth.uid()),trim(p_member_code),trim(p_display_name),p_phone,
    p_sponsor_member_id,p_placement_parent_id,p_placement_side
  )
  returning id into v_id;

  insert into public.vora_audit_logs(
    business_id,actor_user_id,action,entity,entity_id,after_data
  )
  values(
    p_business_id,(select auth.uid()),'member.create','vora_members',v_id,
    jsonb_build_object('member_code',p_member_code,'display_name',p_display_name)
  );

  return v_id;
end;
$$;

revoke all on function public.vora_register_member(uuid,text,text,text,uuid,uuid,text) from public;
revoke all on function public.vora_register_member(uuid,text,text,text,uuid,uuid,text) from anon;
grant execute on function public.vora_register_member(uuid,text,text,text,uuid,uuid,text) to authenticated;

-- Generic timestamp maintenance trigger.
create or replace function public.vora_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at=now();
  return new;
end;
$$;

drop trigger if exists trg_vora_members_updated on public.vora_members;
create trigger trg_vora_members_updated
before update on public.vora_members
for each row execute function public.vora_set_updated_at();

drop trigger if exists trg_vora_member_periods_updated on public.vora_member_periods;
create trigger trg_vora_member_periods_updated
before update on public.vora_member_periods
for each row execute function public.vora_set_updated_at();

drop trigger if exists trg_vora_orders_updated on public.vora_orders;
create trigger trg_vora_orders_updated
before update on public.vora_orders
for each row execute function public.vora_set_updated_at();

drop trigger if exists trg_vora_wallets_updated on public.vora_wallets;
create trigger trg_vora_wallets_updated
before update on public.vora_wallets
for each row execute function public.vora_set_updated_at();

-- End VORA foundation migration.
