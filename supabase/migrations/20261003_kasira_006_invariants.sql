-- KASIRA production migration 006
-- Database-level invariants for money, stock and transaction quantities.
-- Apply after 005_production.sql.

do $$
begin
  if not exists (select 1 from pg_constraint where conname='products_buy_price_nonnegative') then
    alter table public.products add constraint products_buy_price_nonnegative check (buy_price >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='products_sell_price_nonnegative') then
    alter table public.products add constraint products_sell_price_nonnegative check (sell_price >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='products_min_stock_nonnegative') then
    alter table public.products add constraint products_min_stock_nonnegative check (min_stock >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='product_stocks_quantity_nonnegative') then
    alter table public.product_stocks add constraint product_stocks_quantity_nonnegative check (quantity >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='sales_amounts_nonnegative') then
    alter table public.sales add constraint sales_amounts_nonnegative
      check (subtotal >= 0 and discount >= 0 and tax >= 0 and total >= 0 and paid_amount >= 0 and change_amount >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='sales_total_formula') then
    alter table public.sales add constraint sales_total_formula
      check (round(total,2) = round(subtotal - discount + tax,2));
  end if;
  if not exists (select 1 from pg_constraint where conname='sales_payment_method_allowed') then
    alter table public.sales add constraint sales_payment_method_allowed
      check (payment_method in ('cash','card','qris','transfer'));
  end if;
  if not exists (select 1 from pg_constraint where conname='sale_items_quantity_positive') then
    alter table public.sale_items add constraint sale_items_quantity_positive check (quantity > 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='sale_items_amounts_nonnegative') then
    alter table public.sale_items add constraint sale_items_amounts_nonnegative
      check (unit_price >= 0 and discount >= 0 and total >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='sale_items_total_formula') then
    alter table public.sale_items add constraint sale_items_total_formula
      check (round(total,2) = round(quantity * unit_price - discount,2));
  end if;
  if not exists (select 1 from pg_constraint where conname='purchases_total_nonnegative') then
    alter table public.purchases add constraint purchases_total_nonnegative check (total >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='purchase_items_quantity_positive') then
    alter table public.purchase_items add constraint purchase_items_quantity_positive check (quantity > 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='purchase_items_amounts_nonnegative') then
    alter table public.purchase_items add constraint purchase_items_amounts_nonnegative
      check (unit_cost >= 0 and total >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='purchase_items_total_formula') then
    alter table public.purchase_items add constraint purchase_items_total_formula
      check (round(total,2) = round(quantity * unit_cost,2));
  end if;
  if not exists (select 1 from pg_constraint where conname='cash_transactions_amount_positive') then
    alter table public.cash_transactions add constraint cash_transactions_amount_positive check (amount > 0);
  end if;
end $$;

create index if not exists idx_sales_invoice_business on public.sales(business_id, invoice_no);
create index if not exists idx_sale_items_sale on public.sale_items(sale_id);
create index if not exists idx_product_stocks_product_outlet on public.product_stocks(product_id, outlet_id);
