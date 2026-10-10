-- Restrict remaining KASIRA RLS policies that target PUBLIC to signed-in users.
drop policy if exists business_member_read on public.businesses;
create policy business_member_read on public.businesses
for select to authenticated
using (private.is_business_member(id));

drop policy if exists stock_write on public.product_stocks;
create policy stock_write on public.product_stocks
for insert to authenticated
with check (
  private.is_outlet_member(outlet_id)
  and exists (
    select 1
    from public.products p
    join public.outlets o on o.business_id = p.business_id
    where p.id = product_stocks.product_id
      and o.id = product_stocks.outlet_id
  )
  and private.has_business_role(
    (select o.business_id from public.outlets o where o.id = product_stocks.outlet_id),
    array['owner','manager','warehouse']::text[]
  )
);
