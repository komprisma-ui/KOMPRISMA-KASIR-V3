-- KASIRA production migration 009
-- Final role hardening for sensitive ledgers and administrative tables.
-- Apply after 008.

-- Cash: only owner/manager may directly create/edit/delete cash entries.
-- Sales RPC remains the controlled path for cash from checkout.
drop policy if exists cash_member_all on public.cash_transactions;
create policy cash_member_read on public.cash_transactions
for select to authenticated
using (public.is_business_member(business_id));
create policy cash_manager_write on public.cash_transactions
for insert to authenticated
with check (
  public.has_business_role(business_id,array['owner','manager'])
  and public.is_outlet_member(outlet_id)
  and user_id=(select auth.uid())
);
create policy cash_manager_update on public.cash_transactions
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));
create policy cash_manager_delete on public.cash_transactions
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

-- Returns/refunds are financially sensitive. Reading is available to business
-- members; mutations are restricted to owner/manager/cashier.
drop policy if exists "sale_returns_member_all" on public.sale_returns;
create policy sale_returns_read on public.sale_returns
for select to authenticated
using (public.is_business_member(business_id));
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
);
create policy sale_returns_manager_update on public.sale_returns
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));
create policy sale_returns_manager_delete on public.sale_returns
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

-- Purchases and stock-register administration belong to owner/manager/warehouse.
drop policy if exists purchase_member_all on public.purchases;
create policy purchase_read on public.purchases
for select to authenticated using (public.is_business_member(business_id));
create policy purchase_write on public.purchases
for insert to authenticated
with check (
  public.has_business_role(business_id,array['owner','manager','warehouse'])
  and public.is_outlet_member(outlet_id)
);
create policy purchase_manager_update on public.purchases
for update to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));
create policy purchase_manager_delete on public.purchases
for delete to authenticated
using (public.has_business_role(business_id,array['owner','manager']));

drop policy if exists purchase_item_member_all on public.purchase_items;
create policy purchase_item_read on public.purchase_items
for select to authenticated
using (exists(select 1 from public.purchases p where p.id=purchase_id and public.is_business_member(p.business_id)));
create policy purchase_item_insert on public.purchase_items
for insert to authenticated
with check (
  exists (
    select 1 from public.purchases p
    join public.products pr on pr.business_id=p.business_id
    where p.id=purchase_id and pr.id=product_id
      and public.has_business_role(p.business_id,array['owner','manager','warehouse'])
  )
);
create policy purchase_item_manager_update on public.purchase_items
for update to authenticated
using (exists(select 1 from public.purchases p where p.id=purchase_id and public.has_business_role(p.business_id,array['owner','manager'])))
with check (exists(select 1 from public.purchases p where p.id=purchase_id and public.has_business_role(p.business_id,array['owner','manager'])));
create policy purchase_item_manager_delete on public.purchase_items
for delete to authenticated
using (exists(select 1 from public.purchases p where p.id=purchase_id and public.has_business_role(p.business_id,array['owner','manager'])));

-- Accounting, fixed assets, inventory and payroll are management-only.
drop policy if exists accounts_member_all on public.accounts;
create policy accounts_manager_all on public.accounts
for all to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));

drop policy if exists journal_entries_member_all on public.journal_entries;
create policy journal_entries_manager_all on public.journal_entries
for all to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));

drop policy if exists journal_lines_member_all on public.journal_lines;
create policy journal_lines_manager_all on public.journal_lines
for all to authenticated
using (
  exists(select 1 from public.journal_entries j where j.id=journal_id and public.has_business_role(j.business_id,array['owner','manager']))
)
with check (
  exists(select 1 from public.journal_entries j where j.id=journal_id and public.has_business_role(j.business_id,array['owner','manager']))
);

drop policy if exists fixed_assets_member_all on public.fixed_assets;
create policy fixed_assets_manager_all on public.fixed_assets
for all to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));

drop policy if exists inventory_member_all on public.inventory_register;
create policy inventory_manager_all on public.inventory_register
for all to authenticated
using (public.has_business_role(business_id,array['owner','manager','warehouse']))
with check (public.has_business_role(business_id,array['owner','manager','warehouse']));

drop policy if exists payroll_manager_all on public.payroll;
create policy payroll_manager_all on public.payroll
for all to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));

-- Direct stock writes are restricted to inventory roles; checkout uses the
-- atomic RPC and therefore remains the cashier path.
drop policy if exists stock_update on public.product_stocks;
create policy stock_update on public.product_stocks
for update to authenticated
using (public.is_outlet_member(outlet_id))
with check (
  public.is_outlet_member(outlet_id)
  and public.has_business_role(
    (select o.business_id from public.outlets o where o.id=outlet_id),
    array['owner','manager','warehouse']
  )
);

-- Explicitly document that the production source guard must include this
-- migration before a release can be considered hardened.
