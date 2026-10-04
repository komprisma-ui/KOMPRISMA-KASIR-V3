-- KASIRA production migration 008
-- Idempotent checkout + historical unit cost + stock movement audit trail.

alter table public.sales
  add column if not exists client_request_id text;

create unique index if not exists sales_business_client_request_uidx
  on public.sales(business_id, client_request_id)
  where client_request_id is not null and client_request_id <> '';

alter table public.sale_items
  add column if not exists unit_cost_at_sale numeric(14,2) not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='sale_items_unit_cost_nonnegative') then
    alter table public.sale_items add constraint sale_items_unit_cost_nonnegative check (unit_cost_at_sale >= 0);
  end if;
end $$;

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  outlet_id uuid not null references public.outlets(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity_delta numeric(14,3) not null,
  quantity_before numeric(14,3) not null,
  quantity_after numeric(14,3) not null,
  source text not null,
  reference_id uuid,
  user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_stock_movements_business_created
  on public.stock_movements(business_id, created_at desc);
create index if not exists idx_stock_movements_product_outlet
  on public.stock_movements(product_id, outlet_id, created_at desc);

alter table public.stock_movements enable row level security;
revoke all on table public.stock_movements from anon;
grant select on table public.stock_movements to authenticated;

drop policy if exists stock_movements_read on public.stock_movements;
create policy stock_movements_read on public.stock_movements
for select to authenticated
using (public.is_business_member(business_id));

create or replace function public.log_stock_movement()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_business_id uuid;
  v_delta numeric;
  v_source text;
begin
  select business_id into v_business_id
  from public.products where id=new.product_id;

  if v_business_id is null then
    return new;
  end if;

  v_delta := new.quantity - coalesce(old.quantity,0);
  if abs(v_delta) < 0.0005 then
    return new;
  end if;

  v_source := coalesce(current_setting('request.jwt.claims', true)::jsonb->>'stock_source','adjustment');

  insert into public.stock_movements(
    business_id,outlet_id,product_id,quantity_delta,
    quantity_before,quantity_after,source,reference_id,user_id
  ) values (
    v_business_id,new.outlet_id,new.product_id,v_delta,
    coalesce(old.quantity,0),new.quantity,v_source,null,auth.uid()
  );
  return new;
end;
$$;

drop trigger if exists trg_log_stock_movement on public.product_stocks;
create trigger trg_log_stock_movement
after update on public.product_stocks
for each row execute function public.log_stock_movement();

create or replace function public.create_sale_atomic(payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=''
as $function$
declare
  v_sale_id uuid;
  v_business_id uuid := (payload->>'business_id')::uuid;
  v_outlet_id uuid := (payload->>'outlet_id')::uuid;
  v_customer_id uuid := nullif(payload->>'customer_id','')::uuid;
  v_invoice text := nullif(trim(payload->>'invoice_no'),'');
  v_client_request_id text := nullif(trim(payload->>'client_request_id'),'');
  v_subtotal numeric := coalesce((payload->>'subtotal')::numeric,0);
  v_discount numeric := coalesce((payload->>'discount')::numeric,0);
  v_tax numeric := coalesce((payload->>'tax')::numeric,0);
  v_total numeric := coalesce((payload->>'total')::numeric,0);
  v_payment text := lower(coalesce(payload->>'payment_method','cash'));
  v_paid numeric := coalesce((payload->>'paid_amount')::numeric,0);
  v_change numeric := coalesce((payload->>'change_amount')::numeric,0);
  v_item jsonb;
  v_stock numeric;
  v_item_subtotal numeric := 0;
  v_item_discount numeric := 0;
  v_item_total numeric := 0;
begin
  if not public.has_business_role(v_business_id,array['owner','manager','cashier']) then
    raise exception 'not authorized for business';
  end if;

  if not exists(
    select 1 from public.outlets o
    where o.id=v_outlet_id and o.business_id=v_business_id
      and public.is_business_member(o.business_id)
  ) then
    raise exception 'outlet is not accessible for business';
  end if;

  if v_client_request_id is not null then
    select id into v_sale_id
    from public.sales
    where business_id=v_business_id and client_request_id=v_client_request_id;
    if v_sale_id is not null then
      return v_sale_id;
    end if;
  end if;

  if v_invoice is null then raise exception 'invoice_no is required'; end if;
  if v_payment not in ('cash','card','qris','transfer') then raise exception 'invalid payment method'; end if;
  if exists(select 1 from public.sales where business_id=v_business_id and invoice_no=v_invoice) then
    raise exception 'duplicate invoice';
  end if;

  if v_subtotal < 0 or v_discount < 0 or v_discount > v_subtotal
     or v_tax < 0 or v_total < 0 or v_paid < 0 or v_change < 0 then
    raise exception 'invalid sale amounts';
  end if;

  if v_customer_id is not null and not exists(
    select 1 from public.customers c
    where c.id=v_customer_id and c.business_id=v_business_id
  ) then
    raise exception 'customer is not in business';
  end if;

  if jsonb_typeof(payload->'items') <> 'array' or jsonb_array_length(payload->'items')=0 then
    raise exception 'sale items are required';
  end if;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    if (v_item->>'product_id') is null
       or coalesce((v_item->>'quantity')::numeric,0)<=0
       or coalesce((v_item->>'unit_price')::numeric,0)<0
       or coalesce((v_item->>'discount')::numeric,0)<0
       or coalesce((v_item->>'total')::numeric,0)<0
       or coalesce((v_item->>'unit_cost_at_sale')::numeric,0)<0 then
      raise exception 'invalid sale item';
    end if;

    if not exists(
      select 1 from public.products p
      where p.id=(v_item->>'product_id')::uuid
        and p.business_id=v_business_id and p.active
    ) then
      raise exception 'product is not in business';
    end if;

    v_item_subtotal := v_item_subtotal
      + ((v_item->>'unit_price')::numeric * (v_item->>'quantity')::numeric);
    v_item_discount := v_item_discount + coalesce((v_item->>'discount')::numeric,0);
    v_item_total := v_item_total + coalesce((v_item->>'total')::numeric,0);

    select quantity into v_stock
    from public.product_stocks
    where outlet_id=v_outlet_id and product_id=(v_item->>'product_id')::uuid
    for update;

    if coalesce(v_stock,0)<(v_item->>'quantity')::numeric then
      raise exception 'insufficient stock';
    end if;
  end loop;

  if abs(v_item_subtotal-v_subtotal)>0.01
     or abs(v_item_discount-v_discount)>0.01
     or abs(v_item_total-(v_subtotal-v_discount))>0.01 then
    raise exception 'sale item totals mismatch';
  end if;

  if abs(((v_subtotal-v_discount)+v_tax)-v_total)>0.01 then
    raise exception 'sale total mismatch';
  end if;

  if v_payment='cash' then
    if v_paid < v_total or abs((v_paid-v_total)-v_change)>0.01 then
      raise exception 'cash payment mismatch';
    end if;
  elsif v_paid<>v_total or v_change<>0 then
    raise exception 'non-cash payment mismatch';
  end if;

  insert into public.sales(
    business_id,outlet_id,cashier_id,customer_id,invoice_no,client_request_id,
    subtotal,discount,tax,total,payment_method,paid_amount,change_amount,status
  ) values(
    v_business_id,v_outlet_id,(select auth.uid()),v_customer_id,v_invoice,v_client_request_id,
    v_subtotal,v_discount,v_tax,v_total,v_payment,v_paid,v_change,'paid'
  ) returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    insert into public.sale_items(
      sale_id,product_id,quantity,unit_price,unit_cost_at_sale,discount,total
    ) values(
      v_sale_id,(v_item->>'product_id')::uuid,
      (v_item->>'quantity')::numeric,(v_item->>'unit_price')::numeric,
      (v_item->>'unit_cost_at_sale')::numeric,
      coalesce((v_item->>'discount')::numeric,0),
      coalesce((v_item->>'total')::numeric,0)
    );

    perform set_config('request.jwt.claims',
      jsonb_build_object('stock_source','sale','sub',auth.uid())::text,true);

    update public.product_stocks
    set quantity=quantity-(v_item->>'quantity')::numeric,updated_at=now()
    where outlet_id=v_outlet_id and product_id=(v_item->>'product_id')::uuid;
  end loop;

  if v_payment='cash' then
    insert into public.cash_transactions(
      business_id,outlet_id,user_id,type,amount,description
    ) values(
      v_business_id,v_outlet_id,(select auth.uid()),'in',v_total,'Penjualan '||v_invoice
    );
  end if;

  insert into public.audit_logs(
    business_id,user_id,action,entity,entity_id,metadata
  ) values(
    v_business_id,(select auth.uid()),'sale.create','sales',v_sale_id,
    jsonb_build_object('invoice_no',v_invoice,'total',v_total,'payment_method',v_payment)
  );

  return v_sale_id;
exception
  when unique_violation then
    if v_client_request_id is not null then
      select id into v_sale_id from public.sales
      where business_id=v_business_id and client_request_id=v_client_request_id;
      if v_sale_id is not null then return v_sale_id; end if;
    end if;
    raise;
end;
$function$;

revoke all on function public.create_sale_atomic(jsonb) from public;
revoke all on function public.create_sale_atomic(jsonb) from anon;
grant execute on function public.create_sale_atomic(jsonb) to authenticated;
