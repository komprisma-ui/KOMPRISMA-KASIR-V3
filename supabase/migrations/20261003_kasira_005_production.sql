-- KASIRA production migration 005
-- Apply after the base schema for an existing database.

-- KASIRA v0.5 production hardening
-- Supabase Auth is the identity source; memberships are the authorization source.
alter table public.memberships drop constraint if exists memberships_role_check;
alter table public.memberships add constraint memberships_role_check
  check (role in ('owner','manager','cashier','warehouse','employee'));

-- Owners/managers may administer business memberships. Users can always read their own membership.
drop policy if exists membership_self_read on public.memberships;
create policy membership_self_read on public.memberships
for select to authenticated
using (user_id=(select auth.uid()));

drop policy if exists membership_owner_read on public.memberships;
create policy membership_owner_read on public.memberships
for select to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

drop policy if exists membership_owner_insert on public.memberships;
create policy membership_owner_insert on public.memberships
for insert to authenticated
with check (public.has_business_role(business_id,array['owner']));

drop policy if exists membership_owner_update on public.memberships;
create policy membership_owner_update on public.memberships
for update to authenticated
using (public.has_business_role(business_id,array['owner']))
with check (public.has_business_role(business_id,array['owner']));

drop policy if exists membership_owner_delete on public.memberships;
create policy membership_owner_delete on public.memberships
for delete to authenticated
using (public.has_business_role(business_id,array['owner']));

-- The atomic sale function writes an audit row, so authenticated callers need
-- a tightly scoped insert policy. The row must belong to the caller's business.
drop policy if exists audit_member_insert on public.audit_logs;
create policy audit_member_insert on public.audit_logs
for insert to authenticated
with check (
  public.has_business_role(business_id,array['owner','manager','cashier','warehouse','employee'])
  and user_id=(select auth.uid())
);

-- Strengthen atomic checkout against cross-business IDs and inconsistent item math.
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
       or coalesce((v_item->>'total')::numeric,0)<0 then
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
    business_id,outlet_id,cashier_id,customer_id,invoice_no,
    subtotal,discount,tax,total,payment_method,paid_amount,change_amount,status
  ) values(
    v_business_id,v_outlet_id,(select auth.uid()),v_customer_id,v_invoice,
    v_subtotal,v_discount,v_tax,v_total,v_payment,v_paid,v_change,'paid'
  ) returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    insert into public.sale_items(
      sale_id,product_id,quantity,unit_price,discount,total
    ) values(
      v_sale_id,(v_item->>'product_id')::uuid,
      (v_item->>'quantity')::numeric,(v_item->>'unit_price')::numeric,
      coalesce((v_item->>'discount')::numeric,0),
      coalesce((v_item->>'total')::numeric,0)
    );

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
end;
$function$;

revoke all on function public.create_sale_atomic(jsonb) from public;
revoke all on function public.create_sale_atomic(jsonb) from anon;
grant execute on function public.create_sale_atomic(jsonb) to authenticated;

-- Restrict direct table access to authenticated users; anonymous clients must not
-- be able to read or mutate business data.
revoke all on table public.businesses,public.outlets,public.memberships,public.products,
  public.product_stocks,public.customers,public.suppliers,public.sales,public.sale_items,
  public.purchases,public.purchase_items,public.cash_transactions,public.audit_logs,
  public.sale_returns,public.accounts,public.journal_entries,public.journal_lines,
  public.fixed_assets,public.inventory_register,public.employees,public.attendance,
  public.payroll from anon;

grant select,insert,update,delete on table public.outlets,public.products,public.product_stocks,
  public.customers,public.suppliers,public.sales,public.sale_items,public.purchases,
  public.purchase_items,public.cash_transactions,public.sale_returns,public.accounts,
  public.journal_entries,public.journal_lines,public.fixed_assets,public.inventory_register,
  public.employees,public.attendance,public.payroll,public.memberships to authenticated;
grant select on table public.businesses,public.audit_logs to authenticated;

-- Prevent direct unauthenticated function execution. Keep only the RPC used by
-- the authenticated checkout path explicitly executable.
revoke all on all functions in schema public from anon;
revoke all on function public.create_sale_atomic(jsonb) from anon;
grant execute on function public.create_sale_atomic(jsonb) to authenticated;

