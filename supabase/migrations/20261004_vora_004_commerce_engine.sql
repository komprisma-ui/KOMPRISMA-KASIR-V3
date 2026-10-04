-- VORA authoritative commerce qualification
create table if not exists public.vora_product_qualification (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  qualified_rate numeric(8,4) not null default 100 check (qualified_rate>=0 and qualified_rate<=100),
  pv_per_unit numeric(18,4) not null default 0 check (pv_per_unit>=0),
  cv_per_unit numeric(18,4) not null default 0 check (cv_per_unit>=0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,product_id)
);

alter table public.vora_product_qualification enable row level security;

drop policy if exists vora_product_qualification_select on public.vora_product_qualification;
create policy vora_product_qualification_select on public.vora_product_qualification
for select to authenticated
using (active or public.vora_has_admin_role(business_id));

drop policy if exists vora_product_qualification_admin on public.vora_product_qualification;
create policy vora_product_qualification_admin on public.vora_product_qualification
for all to authenticated
using (public.vora_has_admin_role(business_id))
with check (public.vora_has_admin_role(business_id));

revoke all on table public.vora_product_qualification from anon;
grant select on public.vora_product_qualification to authenticated;

create or replace function public.vora_create_order_atomic(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_business_id uuid := (payload->>'business_id')::uuid;
  v_outlet_id uuid := (payload->>'outlet_id')::uuid;
  v_customer_user_id uuid := nullif(payload->>'customer_user_id','')::uuid;
  v_customer_member_id uuid := nullif(payload->>'customer_member_id','')::uuid;
  v_seller_member_id uuid := nullif(payload->>'seller_member_id','')::uuid;
  v_idempotency text := nullif(trim(payload->>'idempotency_key'),'');
  v_order_id uuid;
  v_order_no text;
  v_item jsonb;
  v_product public.products%rowtype;
  v_stock numeric;
  v_qty numeric;
  v_unit numeric(18,2);
  v_discount numeric(18,2);
  v_line numeric(18,2);
  v_subtotal numeric(18,2) := 0;
  v_discount_total numeric(18,2) := 0;
  v_qualified numeric(18,2) := 0;
  v_pv numeric(18,2) := 0;
  v_cv numeric(18,2) := 0;
  v_qual_rate numeric;
  v_pv_unit numeric;
  v_cv_unit numeric;
  v_item_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if v_business_id is null or v_outlet_id is null then raise exception 'business_id and outlet_id are required'; end if;
  if v_idempotency is null then raise exception 'idempotency_key is required'; end if;

  if not (
    public.has_business_role(v_business_id,array['owner','manager','cashier'])
    or exists(
      select 1 from public.vora_members m
      where m.business_id=v_business_id
        and m.user_id=(select auth.uid())
        and m.status='active'
        and (v_seller_member_id is null or m.id=v_seller_member_id)
    )
  ) then raise exception 'not authorized for business'; end if;

  if not public.has_business_role(v_business_id,array['owner','manager','cashier'])
     and v_customer_user_id is not null
     and v_customer_user_id<>(select auth.uid()) then
    raise exception 'member checkout cannot impersonate another customer';
  end if;

  if v_seller_member_id is null then
    select m.id into v_seller_member_id
    from public.vora_members m
    where m.business_id=v_business_id and m.user_id=(select auth.uid()) and m.status='active'
    limit 1;
  end if;

  if not exists(
    select 1 from public.outlets o
    where o.id=v_outlet_id and o.business_id=v_business_id
  ) then raise exception 'invalid outlet'; end if;

  if v_customer_member_id is not null and not exists(
    select 1 from public.vora_members m
    where m.id=v_customer_member_id and m.business_id=v_business_id
  ) then raise exception 'invalid customer member'; end if;

  if v_seller_member_id is not null and not exists(
    select 1 from public.vora_members m
    where m.id=v_seller_member_id and m.business_id=v_business_id and m.status='active'
  ) then raise exception 'invalid seller member'; end if;

  select id into v_order_id
  from public.vora_orders
  where business_id=v_business_id and idempotency_key=v_idempotency;

  if v_order_id is not null then return v_order_id; end if;

  if jsonb_typeof(payload->'items') <> 'array' or jsonb_array_length(payload->'items')=0 then
    raise exception 'order items are required';
  end if;

  -- Lock and validate every product/stock row before creating the order.
  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := coalesce((v_item->>'quantity')::numeric,0);
    if v_qty<=0 then raise exception 'invalid quantity'; end if;

    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and business_id=v_business_id
      and active=true
    for update;

    if not found then raise exception 'product not found or inactive'; end if;

    select quantity into v_stock
    from public.product_stocks
    where outlet_id=v_outlet_id and product_id=v_product.id
    for update;

    if coalesce(v_stock,0)<v_qty then
      raise exception 'insufficient stock for %',v_product.name;
    end if;

    v_unit := coalesce(v_product.sell_price,0);
    v_discount := greatest(0,coalesce((v_item->>'discount')::numeric,0));
    v_line := (v_unit*v_qty)-v_discount;

    if v_discount>v_unit*v_qty then raise exception 'item discount exceeds item value'; end if;

    v_qual_rate:=0; v_pv_unit:=0; v_cv_unit:=0;
    select coalesce(q.qualified_rate,0),coalesce(q.pv_per_unit,0),coalesce(q.cv_per_unit,0)
    into v_qual_rate,v_pv_unit,v_cv_unit
    from public.vora_product_qualification q
    where q.business_id=v_business_id and q.product_id=v_product.id and q.active=true;

    v_subtotal := v_subtotal+(v_unit*v_qty);
    v_discount_total := v_discount_total+v_discount;
    v_qualified := v_qualified+(v_line*v_qual_rate/100);
    v_pv := v_pv+(v_pv_unit*v_qty);
    v_cv := v_cv+(v_cv_unit*v_qty);
  end loop;

  v_order_no := 'VOR-'||to_char(now(),'YYYYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));

  insert into public.vora_orders(
    business_id,order_no,customer_user_id,customer_member_id,seller_member_id,
    status,subtotal,discount,tax,shipping,total,qualified_amount,pv,cv,
    idempotency_key,paid_at,completed_at
  )
  values(
    v_business_id,v_order_no,v_customer_user_id,v_customer_member_id,v_seller_member_id,
    'paid',v_subtotal,v_discount_total,0,0,v_subtotal-v_discount_total,
    v_qualified,v_pv,v_cv,v_idempotency,now(),now()
  )
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    select * into v_product
    from public.products
    where id=(v_item->>'product_id')::uuid
      and business_id=v_business_id
    for update;

    v_qty := (v_item->>'quantity')::numeric;
    v_unit := coalesce(v_product.sell_price,0);
    v_discount := greatest(0,coalesce((v_item->>'discount')::numeric,0));
    v_line := (v_unit*v_qty)-v_discount;

    v_pv_unit:=0; v_cv_unit:=0;
    select coalesce(q.pv_per_unit,0),coalesce(q.cv_per_unit,0)
    into v_pv_unit,v_cv_unit
    from public.vora_product_qualification q
    where q.business_id=v_business_id and q.product_id=v_product.id and q.active=true;

    insert into public.vora_order_items(
      order_id,product_id,quantity,unit_price,discount,line_total,pv,cv
    )
    values(
      v_order_id,v_product.id,v_qty,v_unit,v_discount,v_line,
      v_pv_unit*v_qty,v_cv_unit*v_qty
    );

    update public.product_stocks
    set quantity=quantity-v_qty,updated_at=now()
    where outlet_id=v_outlet_id and product_id=v_product.id;
  end loop;

  insert into public.vora_audit_logs(
    business_id,actor_user_id,action,entity,entity_id,after_data
  )
  values(
    v_business_id,(select auth.uid()),'order.create','vora_orders',v_order_id,
    jsonb_build_object('order_no',v_order_no,'total',v_subtotal-v_discount_total,
      'qualified_amount',v_qualified,'pv',v_pv,'cv',v_cv)
  );

  return v_order_id;
end;
$$;

revoke all on function public.vora_create_order_atomic(jsonb) from public;
revoke all on function public.vora_create_order_atomic(jsonb) from anon;
grant execute on function public.vora_create_order_atomic(jsonb) to authenticated;

-- End authoritative commerce engine.
