-- KASIRA production migration 011
-- Remove permissive legacy RLS policies that could bypass role hardening.
-- Apply after 010_transaction_bypass_hardening.sql.

-- Business/outlet administration.
drop policy if exists outlet_member_all on public.outlets;
create policy outlet_member_read on public.outlets
for select to authenticated using (public.is_business_member(business_id));
create policy outlet_manager_write on public.outlets
for insert to authenticated
with check (public.has_business_role(business_id,array['owner','manager']));
create policy outlet_manager_update on public.outlets
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));
create policy outlet_manager_delete on public.outlets
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

-- Products: members may read; only management/warehouse may mutate.
drop policy if exists product_member_all on public.products;
create policy product_member_read on public.products
for select to authenticated using (public.is_business_member(business_id));
create policy product_inventory_insert on public.products
for insert to authenticated
with check (public.has_business_role(business_id,array['owner','manager','warehouse']));
create policy product_manager_update on public.products
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));
create policy product_inventory_update on public.products
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager','warehouse']))
with check (public.has_business_role(business_id,array['owner','manager','warehouse']));
create policy product_manager_delete on public.products
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

-- Stock: members may read; writes are inventory roles only.
drop policy if exists stock_member_all on public.product_stocks;
create policy stock_member_read on public.product_stocks
for select to authenticated
using (exists(select 1 from public.outlets o where o.id=outlet_id and public.is_business_member(o.business_id)));

-- Customers: members may read; cashier can create/update customer records, management can delete.
drop policy if exists customer_member_all on public.customers;
create policy customer_member_read on public.customers
for select to authenticated using (public.is_business_member(business_id));
create policy customer_frontdesk_write on public.customers
for insert to authenticated
with check (public.has_business_role(business_id,array['owner','manager','cashier']));
create policy customer_frontdesk_update on public.customers
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager','cashier']))
with check (public.has_business_role(business_id,array['owner','manager','cashier']));
create policy customer_manager_delete on public.customers
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

-- Suppliers: read for members, mutations for management/warehouse.
drop policy if exists supplier_member_all on public.suppliers;
create policy supplier_member_read on public.suppliers
for select to authenticated using (public.is_business_member(business_id));
create policy supplier_inventory_insert on public.suppliers
for insert to authenticated
with check (public.has_business_role(business_id,array['owner','manager','warehouse']));
create policy supplier_manager_update on public.suppliers
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));
create policy supplier_manager_delete on public.suppliers
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

-- Sales: read-only through PostgREST; creation must use create_sale_atomic().
drop policy if exists sale_member_all on public.sales;
create policy sale_member_read on public.sales
for select to authenticated using (public.is_business_member(business_id));
create policy sale_manager_update on public.sales
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));
create policy sale_manager_delete on public.sales
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

-- Sale items: read-only; the atomic sale function owns inserts.
drop policy if exists sale_item_member_all on public.sale_items;
create policy sale_item_member_read on public.sale_items
for select to authenticated
using (exists(select 1 from public.sales s where s.id=sale_id and public.is_business_member(s.business_id)));
create policy sale_item_manager_update on public.sale_items
for update to authenticated
using (exists(select 1 from public.sales s where s.id=sale_id and public.has_business_role(s.business_id,array['owner','manager'])))
with check (exists(select 1 from public.sales s where s.id=sale_id and public.has_business_role(s.business_id,array['owner','manager'])));
create policy sale_item_manager_delete on public.sale_items
for delete to authenticated
using (exists(select 1 from public.sales s where s.id=sale_id and public.has_business_role(s.business_id,array['owner','manager'])));

-- Audit log is append-only by trusted server-side functions; members can read.
drop policy if exists audit_member_insert on public.audit_logs;
drop policy if exists audit_member_all on public.audit_logs;
create policy audit_member_read on public.audit_logs
for select to authenticated using (public.is_business_member(business_id));

-- Defense-in-depth constraints.
alter table public.sales drop constraint if exists sales_total_nonnegative;
alter table public.sales add constraint sales_total_nonnegative check (total >= 0 and subtotal >= 0 and discount >= 0 and tax >= 0);
alter table public.sale_items drop constraint if exists sale_items_quantity_positive;
alter table public.sale_items add constraint sale_items_quantity_positive check (quantity > 0 and unit_price >= 0 and discount >= 0 and total >= 0);

create index if not exists idx_sales_outlet_created on public.sales(outlet_id, created_at desc);
create index if not exists idx_product_stocks_product_outlet on public.product_stocks(product_id, outlet_id);
