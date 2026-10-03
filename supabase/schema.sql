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
create unique index if not exists products_business_barcode_uidx
on public.products(business_id, barcode)
where barcode is not null and barcode <> '';
create index if not exists idx_sale_items_product on public.sale_items(product_id);
create index if not exists idx_purchase_items_product on public.purchase_items(product_id);

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
returns boolean language sql stable security definer set search_path=''
as $function$
  select exists (
    select 1 from public.memberships m
    where m.business_id=target_business and m.user_id=auth.uid()
  );
$function$;

create or replace function public.is_business_manager(target_business uuid)
returns boolean language sql stable security definer set search_path=''
as $function$
  select exists (
    select 1 from public.memberships m
    where m.business_id=target_business and m.user_id=auth.uid()
      and m.role in ('owner','manager')
  );
$function$;

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

drop policy if exists sale_item_member_all on public.sale_items;
create policy sale_item_member_all on public.sale_items for all
using (exists(select 1 from public.sales s where s.id=sale_id and public.is_business_member(s.business_id)))
with check (exists(select 1 from public.sales s where s.id=sale_id and public.is_business_member(s.business_id)));

drop policy if exists purchase_item_member_all on public.purchase_items;
create policy purchase_item_member_all on public.purchase_items for all
using (exists(select 1 from public.purchases p where p.id=purchase_id and public.is_business_member(p.business_id)))
with check (exists(select 1 from public.purchases p where p.id=purchase_id and public.is_business_member(p.business_id)));

drop policy if exists purchase_member_all on public.purchases;
create policy purchase_member_all on public.purchases for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists cash_member_all on public.cash_transactions;
create policy cash_member_all on public.cash_transactions for all using (public.is_business_member(business_id)) with check (public.is_business_member(business_id));

drop policy if exists audit_member_read on public.audit_logs;
create policy audit_member_read on public.audit_logs for select using (public.is_business_member(business_id));


-- KASIRA v0.4 operational controls
create table if not exists public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  outlet_id uuid references public.outlets(id) on delete set null,
  sale_id uuid not null references public.sales(id) on delete restrict,
  sale_item_id uuid references public.sale_items(id) on delete set null,
  qty numeric(14,3) not null check (qty > 0),
  refund_amount numeric(14,2) not null default 0 check (refund_amount >= 0),
  reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists sale_returns_business_idx on public.sale_returns(business_id, created_at desc);
alter table public.sale_returns enable row level security;

drop policy if exists "sale_returns_member_all" on public.sale_returns;
create policy "sale_returns_member_all" on public.sale_returns
for all using (public.is_business_member(business_id))
with check (public.is_business_member(business_id));

-- Cash ledger indexes/policies are intentionally business-scoped.
create index if not exists cash_transactions_business_idx on public.cash_transactions(business_id, created_at desc);


-- KASIRA v0.4.1 security hardening
-- Explicit role helpers and cross-tenant relationship checks.

create or replace function public.has_business_role(target_business uuid, allowed_roles text[])
returns boolean
language sql stable security definer set search_path=''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.business_id = target_business
      and m.user_id = auth.uid()
      and m.role = any(allowed_roles)
  );
$$;

create or replace function public.is_outlet_member(target_outlet uuid)
returns boolean
language sql stable security definer set search_path=''
as $$
  select exists (
    select 1
    from public.outlets o
    where o.id = target_outlet
      and public.is_business_member(o.business_id)
  );
$$;

-- Replace broad FOR ALL policies with role-aware policies.
drop policy if exists product_member_all on public.products;
create policy product_member_read on public.products
for select using (public.is_business_member(business_id));
create policy product_manager_insert on public.products
for insert with check (public.has_business_role(business_id, array['owner','manager','warehouse']));
create policy product_manager_update on public.products
for update using (public.has_business_role(business_id, array['owner','manager','warehouse']))
with check (public.has_business_role(business_id, array['owner','manager','warehouse']));
create policy product_manager_delete on public.products
for delete using (public.has_business_role(business_id, array['owner','manager']));

drop policy if exists outlet_member_all on public.outlets;
create policy outlet_member_read on public.outlets
for select using (public.is_business_member(business_id));
create policy outlet_manager_write on public.outlets
for insert with check (public.has_business_role(business_id, array['owner','manager']));
create policy outlet_manager_update on public.outlets
for update using (public.has_business_role(business_id, array['owner','manager']))
with check (public.has_business_role(business_id, array['owner','manager']));
create policy outlet_manager_delete on public.outlets
for delete using (public.has_business_role(business_id, array['owner','manager']));

drop policy if exists stock_member_all on public.product_stocks;
create policy stock_member_read on public.product_stocks
for select using (public.is_outlet_member(outlet_id));
create policy stock_write on public.product_stocks
for insert with check (
  public.is_outlet_member(outlet_id)
  and exists (
    select 1 from public.products p
    join public.outlets o on o.business_id=p.business_id
    where p.id=product_id and o.id=outlet_id
  )
  and public.has_business_role((select o.business_id from public.outlets o where o.id=outlet_id), array['owner','manager','warehouse'])
);
create policy stock_update on public.product_stocks
for update using (public.is_outlet_member(outlet_id))
with check (
  public.is_outlet_member(outlet_id)
  and exists (
    select 1 from public.products p
    join public.outlets o on o.business_id=p.business_id
    where p.id=product_id and o.id=outlet_id
  )
  and public.has_business_role((select o.business_id from public.outlets o where o.id=outlet_id), array['owner','manager','warehouse'])
);

drop policy if exists sale_member_all on public.sales;
create policy sale_member_read on public.sales
for select using (public.is_business_member(business_id));
create policy sale_cashier_insert on public.sales
for insert with check (
  public.has_business_role(business_id, array['owner','manager','cashier'])
  and public.is_outlet_member(outlet_id)
  and (customer_id is null or exists(select 1 from public.customers c where c.id=customer_id and c.business_id=business_id))
);
create policy sale_manager_update on public.sales
for update using (public.has_business_role(business_id, array['owner','manager']))
with check (public.has_business_role(business_id, array['owner','manager']));
create policy sale_manager_delete on public.sales
for delete using (public.has_business_role(business_id, array['owner','manager']));

drop policy if exists sale_item_member_all on public.sale_items;
create policy sale_item_read on public.sale_items
for select using (exists(select 1 from public.sales s where s.id=sale_id and public.is_business_member(s.business_id)));
create policy sale_item_insert on public.sale_items
for insert with check (
  exists (
    select 1
    from public.sales s
    join public.products p on p.business_id=s.business_id
    where s.id=sale_id and p.id=product_id
      and public.has_business_role(s.business_id, array['owner','manager','cashier'])
  )
);
create policy sale_item_manager_update on public.sale_items
for update using (exists(select 1 from public.sales s where s.id=sale_id and public.has_business_role(s.business_id,array['owner','manager'])))
with check (exists(select 1 from public.sales s join public.products p on p.business_id=s.business_id where s.id=sale_id and p.id=product_id and public.has_business_role(s.business_id,array['owner','manager'])));
create policy sale_item_manager_delete on public.sale_items
for delete using (exists(select 1 from public.sales s where s.id=sale_id and public.has_business_role(s.business_id,array['owner','manager'])));

drop policy if exists purchase_member_all on public.purchases;
create policy purchase_read on public.purchases
for select using (public.is_business_member(business_id));
create policy purchase_write on public.purchases
for insert with check (public.has_business_role(business_id,array['owner','manager','warehouse']) and public.is_outlet_member(outlet_id));
create policy purchase_manager_update on public.purchases
for update using (public.has_business_role(business_id,array['owner','manager'])) with check (public.has_business_role(business_id,array['owner','manager']));
create policy purchase_manager_delete on public.purchases
for delete using (public.has_business_role(business_id,array['owner','manager']));

drop policy if exists purchase_item_member_all on public.purchase_items;
create policy purchase_item_read on public.purchase_items
for select using (exists(select 1 from public.purchases p where p.id=purchase_id and public.is_business_member(p.business_id)));
create policy purchase_item_insert on public.purchase_items
for insert with check (
  exists (
    select 1 from public.purchases pu
    join public.products pr on pr.business_id=pu.business_id
    where pu.id=purchase_id and pr.id=product_id
      and public.has_business_role(pu.business_id,array['owner','manager','warehouse'])
  )
);
create policy purchase_item_manager_update on public.purchase_items
for update using (exists(select 1 from public.purchases p where p.id=purchase_id and public.has_business_role(p.business_id,array['owner','manager'])))
with check (exists(select 1 from public.purchases pu join public.products pr on pr.business_id=pu.business_id where pu.id=purchase_id and pr.id=product_id and public.has_business_role(pu.business_id,array['owner','manager'])));
create policy purchase_item_manager_delete on public.purchase_items
for delete using (exists(select 1 from public.purchases p where p.id=purchase_id and public.has_business_role(p.business_id,array['owner','manager'])));

drop policy if exists cash_member_all on public.cash_transactions;
create policy cash_read on public.cash_transactions
for select using (public.is_business_member(business_id));
create policy cash_insert on public.cash_transactions
for insert with check (public.has_business_role(business_id,array['owner','manager','cashier']) and public.is_outlet_member(outlet_id));
create policy cash_manager_update on public.cash_transactions
for update using (public.has_business_role(business_id,array['owner','manager'])) with check (public.has_business_role(business_id,array['owner','manager']));
create policy cash_manager_delete on public.cash_transactions
for delete using (public.has_business_role(business_id,array['owner','manager']));

drop policy if exists "sale_returns_member_all" on public.sale_returns;
create policy sale_returns_read on public.sale_returns
for select using (public.is_business_member(business_id));
create policy sale_returns_insert on public.sale_returns
for insert with check (
  public.has_business_role(business_id,array['owner','manager','cashier'])
  and exists(select 1 from public.sales s where s.id=sale_id and s.business_id=business_id)
  and (sale_item_id is null or exists(select 1 from public.sale_items si where si.id=sale_item_id and si.sale_id=sale_id))
);
create policy sale_returns_manager_update on public.sale_returns
for update using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));
create policy sale_returns_manager_delete on public.sale_returns
for delete using (public.has_business_role(business_id,array['owner','manager']));

create or replace function public.validate_sale_item_business()
returns trigger language plpgsql security invoker
as $$
declare sale_business uuid; product_business uuid;
begin
  select business_id into sale_business from public.sales where id=new.sale_id;
  select business_id into product_business from public.products where id=new.product_id;
  if sale_business is null or product_business is null or sale_business <> product_business then
    raise exception 'sale item business mismatch';
  end if;
  if new.quantity <= 0 or new.unit_price < 0 or new.discount < 0 or new.total < 0 then
    raise exception 'invalid sale item amounts';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_sale_item_business on public.sale_items;
create trigger trg_validate_sale_item_business
before insert or update on public.sale_items
for each row execute function public.validate_sale_item_business();

create or replace function public.validate_purchase_item_business()
returns trigger language plpgsql security invoker
as $$
declare purchase_business uuid; product_business uuid;
begin
  select business_id into purchase_business from public.purchases where id=new.purchase_id;
  select business_id into product_business from public.products where id=new.product_id;
  if purchase_business is null or product_business is null or purchase_business <> product_business then
    raise exception 'purchase item business mismatch';
  end if;
  if new.quantity <= 0 or new.unit_cost < 0 or new.total < 0 then
    raise exception 'invalid purchase item amounts';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_purchase_item_business on public.purchase_items;
create trigger trg_validate_purchase_item_business
before insert or update on public.purchase_items
for each row execute function public.validate_purchase_item_business();

create index if not exists idx_sale_items_sale on public.sale_items(sale_id);
create index if not exists idx_purchase_items_purchase on public.purchase_items(purchase_id);


-- Atomic sale primitive for the cloud-connected POS.
-- The client should call this RPC instead of independently mutating sale,
-- sale_items, stock and cash when Supabase sync is enabled.
create or replace function public.create_sale_atomic(payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_sale_id uuid;
  v_business_id uuid := (payload->>'business_id')::uuid;
  v_outlet_id uuid := (payload->>'outlet_id')::uuid;
  v_customer_id uuid := nullif(payload->>'customer_id','')::uuid;
  v_invoice text := payload->>'invoice_no';
  v_subtotal numeric := coalesce((payload->>'subtotal')::numeric,0);
  v_discount numeric := coalesce((payload->>'discount')::numeric,0);
  v_tax numeric := coalesce((payload->>'tax')::numeric,0);
  v_total numeric := coalesce((payload->>'total')::numeric,0);
  v_payment text := coalesce(payload->>'payment_method','cash');
  v_paid numeric := coalesce((payload->>'paid_amount')::numeric,0);
  v_change numeric := coalesce((payload->>'change_amount')::numeric,0);
  v_item jsonb;
  v_stock numeric;
begin
  if not public.has_business_role(v_business_id, array['owner','manager','cashier']) then
    raise exception 'not authorized for business';
  end if;
  if not public.is_outlet_member(v_outlet_id) then
    raise exception 'outlet is not accessible';
  end if;
  if exists(select 1 from public.sales where business_id=v_business_id and invoice_no=v_invoice) then
    raise exception 'duplicate invoice';
  end if;
  if v_subtotal < 0 or v_discount < 0 or v_discount > v_subtotal
     or v_tax < 0 or v_total < 0 or v_paid < 0 or v_change < 0 then
    raise exception 'invalid sale amounts';
  end if;

  insert into public.sales(
    business_id,outlet_id,cashier_id,customer_id,invoice_no,
    subtotal,discount,tax,total,payment_method,paid_amount,change_amount,status
  ) values (
    v_business_id,v_outlet_id,auth.uid(),v_customer_id,v_invoice,
    v_subtotal,v_discount,v_tax,v_total,v_payment,v_paid,v_change,'paid'
  ) returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(coalesce(payload->'items','[]'::jsonb)) loop
    if (v_item->>'product_id') is null then raise exception 'missing product_id'; end if;
    if coalesce((v_item->>'quantity')::numeric,0) <= 0 then raise exception 'invalid quantity'; end if;
    if coalesce((v_item->>'unit_price')::numeric,0) < 0 then raise exception 'invalid unit price'; end if;

    select quantity into v_stock
    from public.product_stocks
    where outlet_id=v_outlet_id and product_id=(v_item->>'product_id')::uuid
    for update;

    if coalesce(v_stock,0) < (v_item->>'quantity')::numeric then
      raise exception 'insufficient stock';
    end if;

    if not exists(
      select 1 from public.products p
      where p.id=(v_item->>'product_id')::uuid and p.business_id=v_business_id and p.active
    ) then raise exception 'product is not in business'; end if;

    insert into public.sale_items(
      sale_id,product_id,quantity,unit_price,discount,total
    ) values (
      v_sale_id,(v_item->>'product_id')::uuid,
      (v_item->>'quantity')::numeric,(v_item->>'unit_price')::numeric,
      coalesce((v_item->>'discount')::numeric,0),
      coalesce((v_item->>'total')::numeric,0)
    );

    update public.product_stocks
    set quantity=quantity-(v_item->>'quantity')::numeric,updated_at=now()
    where outlet_id=v_outlet_id and product_id=(v_item->>'product_id')::uuid;
  end loop;

  if v_payment = 'cash' then
    insert into public.cash_transactions(
      business_id,outlet_id,user_id,type,amount,description
    ) values (
      v_business_id,v_outlet_id,auth.uid(),'in',v_total,'Penjualan '||v_invoice
    );
  end if;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,metadata
  ) values (
    v_business_id,auth.uid(),'sale.create','sales',v_sale_id,
    jsonb_build_object('invoice_no',v_invoice,'total',v_total,'payment_method',v_payment)
  );

  return v_sale_id;
end;
$$;

revoke all on function public.create_sale_atomic(jsonb) from public;
grant execute on function public.create_sale_atomic(jsonb) to authenticated;
