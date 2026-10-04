-- KASIRA production migration 010
-- Close permissive legacy policies and enforce server-authoritative sale pricing/cost.

-- A sale is created only through create_sale_atomic(). Direct inserts could bypass
-- stock, cash, audit and idempotency guarantees.
drop policy if exists sale_cashier_insert on public.sales;
drop policy if exists sale_item_insert on public.sale_items;

-- Returns must identify the authenticated actor.
drop policy if exists sale_returns_insert on public.sale_returns;
drop policy if exists sale_returns_create on public.sale_returns;
create policy sale_returns_create on public.sale_returns
for insert to authenticated
with check (
  public.has_business_role(business_id,array['owner','manager','cashier'])
  and public.is_outlet_member(outlet_id)
  and created_by=(select auth.uid())
  and exists (
    select 1 from public.sales s
    where s.id=sale_id and s.business_id=business_id
  )
  and (
    sale_item_id is null
    or exists (
      select 1 from public.sale_items si
      where si.id=sale_item_id and si.sale_id=sale_id
    )
  )
);

-- Server-authoritative pricing: the client cannot falsify sell price or HPP.
create or replace function public.validate_sale_item_price_cost()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_sell numeric;
  v_buy numeric;
begin
  select p.sell_price,p.buy_price into v_sell,v_buy
  from public.products p
  where p.id=new.product_id and p.active;

  if v_sell is null then
    raise exception 'product is inactive or unavailable';
  end if;

  if round(new.unit_price,2) <> round(v_sell,2) then
    raise exception 'sale unit price does not match product price';
  end if;

  if round(new.unit_cost_at_sale,2) <> round(v_buy,2) then
    raise exception 'sale unit cost does not match product cost';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_sale_item_price_cost on public.sale_items;
create trigger trg_validate_sale_item_price_cost
before insert or update on public.sale_items
for each row execute function public.validate_sale_item_price_cost();

-- Prevent impossible stock movement records even if a future mutation path is added.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='stock_movements_quantity_after_nonnegative'
  ) then
    alter table public.stock_movements
      add constraint stock_movements_quantity_after_nonnegative check (quantity_after >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint where conname='stock_movements_before_nonnegative'
  ) then
    alter table public.stock_movements
      add constraint stock_movements_before_nonnegative check (quantity_before >= 0);
  end if;
end $$;

-- Cross-tenant invariant for stock rows.
create or replace function public.validate_product_stock_relation()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_product_business uuid;
  v_outlet_business uuid;
begin
  select business_id into v_product_business from public.products where id=new.product_id;
  select business_id into v_outlet_business from public.outlets where id=new.outlet_id;
  if v_product_business is null or v_outlet_business is null or v_product_business <> v_outlet_business then
    raise exception 'product stock business mismatch';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_product_stock_relation on public.product_stocks;
create trigger trg_validate_product_stock_relation
before insert or update on public.product_stocks
for each row execute function public.validate_product_stock_relation();
