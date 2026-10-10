-- Merge duplicate membership SELECT policies without changing who can read rows.
drop policy if exists membership_owner_read on public.memberships;
drop policy if exists membership_self_read on public.memberships;
create policy membership_read on public.memberships
for select to authenticated
using (
  (select auth.uid()) = user_id
  or public.has_business_role(business_id, array['owner','manager']::text[])
);

-- Product master fields (including selling price) are managed by owner/manager.
-- Warehouse users should update stock through product_stocks/stock_movements instead.
drop policy if exists product_inventory_update on public.products;
