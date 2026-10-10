-- Remove legacy PUBLIC-target policies duplicated by stricter authenticated policies.
-- The authenticated policies below already enforce the same or broader business-role checks.
drop policy if exists inventory_register_manager_all on public.inventory_register;
drop policy if exists product_manager_insert on public.products;
drop policy if exists sale_item_read on public.sale_items;
drop policy if exists cash_read on public.cash_transactions;
