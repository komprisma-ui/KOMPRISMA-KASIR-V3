-- KASIRA migration 024: persist customer address and loyalty totals in the tenant database.
-- Extend the current hardened atomic checkout function without weakening its current checks.
alter table public.customers
  add column if not exists address text;

alter table public.customers
  add column if not exists total_spent numeric(14,2) not null default 0;

do $migration$
declare
  v_definition text;
  v_updated_definition text;
  v_anchor text := E'  insert into public.audit_logs(\n';
  v_replacement text := E'  if v_customer_id is not null then\n    update public.customers\n    set points = points + floor(v_total / 10000)::integer,\n        total_spent = total_spent + v_total\n    where id = v_customer_id and business_id = v_business_id;\n    if not found then raise exception \'customer is not in business\'; end if;\n  end if;\n\n  insert into public.audit_logs(\n';
begin
  select pg_catalog.pg_get_functiondef('public.create_sale_atomic(jsonb)'::regprocedure)
    into v_definition;

  if position(v_anchor in v_definition) = 0 then
    raise exception 'KASIRA migration 024 could not locate audit insert in create_sale_atomic; aborting without changing function';
  end if;

  v_updated_definition := replace(v_definition, v_anchor, v_replacement);
  if v_updated_definition = v_definition then
    raise exception 'KASIRA migration 024 did not modify create_sale_atomic';
  end if;

  execute v_updated_definition;
end;
$migration$;

comment on column public.customers.address is 'Customer mailing/contact address, scoped to business.';
comment on column public.customers.total_spent is 'Lifetime settled sale total; updated atomically by create_sale_atomic.';
