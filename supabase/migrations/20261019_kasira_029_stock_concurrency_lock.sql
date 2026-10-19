-- KASIRA migration 029: serialize stock-row creation and quantity updates across concurrent requests.
-- KASIRA migration 025: tenant-safe stock adjustment and purchase receiving.
alter table public.purchases
  add column if not exists supplier_name text;

create or replace function public.kasira_adjust_stock(
  p_business_id uuid,
  p_outlet_id uuid,
  p_product_id uuid,
  p_delta numeric
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_before numeric;
  v_after numeric;
begin
  if v_uid is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode = '28000';
  end if;
  if p_delta is null or p_delta = 0 then
    raise exception 'Perubahan stok tidak boleh nol.';
  end if;
  if not public.has_business_role(p_business_id, array['owner','manager','warehouse']) then
    raise exception 'Hanya Owner, Manager, atau Gudang yang dapat menyesuaikan stok.' using errcode = '42501';
  end if;
  if not exists(
    select 1 from public.outlets o
    where o.id=p_outlet_id and o.business_id=p_business_id
      and public.is_business_member(o.business_id)
  ) then
    raise exception 'Outlet tidak sesuai dengan usaha aktif.' using errcode = '42501';
  end if;
  if not exists(
    select 1 from public.products p
    where p.id=p_product_id and p.business_id=p_business_id and p.active
  ) then
    raise exception 'Produk aktif tidak ditemukan pada usaha ini.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_business_id::text||':stock:'||v_outlet_id::text||':'||v_product_id::text,0)
  );
  select ps.quantity into v_before
  from public.product_stocks ps
  where ps.product_id=p_product_id and ps.outlet_id=p_outlet_id
  for update;

  if not found then
    if p_delta < 0 then raise exception 'Stok tidak mencukupi.'; end if;
    v_before := 0;
    perform pg_catalog.set_config('request.jwt.claims',
      jsonb_build_object('stock_source','adjustment','sub',v_uid)::text,true);
    insert into public.product_stocks(product_id,outlet_id,quantity)
    values(p_product_id,p_outlet_id,p_delta);
    v_after := p_delta;
  else
    v_after := v_before + p_delta;
    if v_after < 0 then raise exception 'Stok akhir tidak boleh negatif.'; end if;
    perform pg_catalog.set_config('request.jwt.claims',
      jsonb_build_object('stock_source','adjustment','sub',v_uid)::text,true);
    update public.product_stocks
    set quantity=v_after,updated_at=now()
    where product_id=p_product_id and outlet_id=p_outlet_id;
  end if;

  insert into public.audit_logs(business_id,user_id,action,entity,entity_id,metadata)
  values(p_business_id,v_uid,'stock.adjustment','product_stocks',p_product_id,
    jsonb_build_object('outlet_id',p_outlet_id,'delta',p_delta,'quantity_before',v_before,'quantity_after',v_after));

  return v_after;
end;
$function$;

revoke all on function public.kasira_adjust_stock(uuid,uuid,uuid,numeric) from public, anon;
grant execute on function public.kasira_adjust_stock(uuid,uuid,uuid,numeric) to authenticated;

create or replace function public.kasira_create_purchase(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_business_id uuid := nullif(payload->>'business_id','')::uuid;
  v_outlet_id uuid := nullif(payload->>'outlet_id','')::uuid;
  v_product_id uuid := nullif(payload->>'product_id','')::uuid;
  v_invoice text := left(btrim(coalesce(payload->>'invoice_no','')),100);
  v_supplier text := left(btrim(coalesce(payload->>'supplier_name','')),200);
  v_qty numeric := coalesce((payload->>'quantity')::numeric,0);
  v_cost numeric := coalesce((payload->>'unit_cost')::numeric,0);
  v_total numeric;
  v_stock_before numeric;
  v_stock_after numeric;
  v_purchase_id uuid;
  v_cash_id uuid;
  v_created_at timestamptz;
begin
  if v_uid is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode = '28000';
  end if;
  if v_business_id is null or v_outlet_id is null or v_product_id is null then
    raise exception 'Bisnis, outlet, dan produk wajib tersedia.';
  end if;
  if not public.has_business_role(v_business_id,array['owner','manager','warehouse']) then
    raise exception 'Hanya Owner, Manager, atau Gudang yang dapat menerima pembelian.' using errcode = '42501';
  end if;
  if not exists(
    select 1 from public.outlets o
    where o.id=v_outlet_id and o.business_id=v_business_id
      and public.is_business_member(o.business_id)
  ) then
    raise exception 'Outlet tidak sesuai dengan usaha aktif.' using errcode = '42501';
  end if;
  if length(v_invoice)<1 then
    raise exception 'Nomor invoice pembelian wajib diisi.';
  end if;
  if v_qty<=0 or v_cost<0 then
    raise exception 'Qty harus lebih dari nol dan HPP tidak boleh negatif.';
  end if;
  if not exists(
    select 1 from public.products p
    where p.id=v_product_id and p.business_id=v_business_id and p.active
  ) then
    raise exception 'Produk aktif tidak ditemukan pada usaha ini.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_business_id::text||':purchase:'||lower(v_invoice),0)
  );
  if exists(select 1 from public.purchases p where p.business_id=v_business_id and lower(p.invoice_no)=lower(v_invoice)) then
    raise exception 'Nomor invoice sudah tercatat pada usaha ini.';
  end if;

  v_total := round(v_qty*v_cost,2);

  perform pg_catalog.set_config('request.jwt.claims',
    jsonb_build_object('stock_source','purchase','sub',v_uid)::text,true);

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_business_id::text||':stock:'||v_outlet_id::text||':'||v_product_id::text,0)
  );
  select ps.quantity into v_stock_before
  from public.product_stocks ps
  where ps.product_id=v_product_id and ps.outlet_id=v_outlet_id
  for update;
  if not found then v_stock_before:=0; end if;

  insert into public.purchases(business_id,outlet_id,supplier_name,invoice_no,total,status)
  values(v_business_id,v_outlet_id,nullif(v_supplier,''),v_invoice,v_total,'received')
  returning id,created_at into v_purchase_id,v_created_at;

  insert into public.purchase_items(purchase_id,product_id,quantity,unit_cost,total)
  values(v_purchase_id,v_product_id,v_qty,v_cost,v_total);

  if exists(select 1 from public.product_stocks where product_id=v_product_id and outlet_id=v_outlet_id) then
    update public.product_stocks
    set quantity=quantity+v_qty,updated_at=now()
    where product_id=v_product_id and outlet_id=v_outlet_id
    returning quantity into v_stock_after;
  else
    insert into public.product_stocks(product_id,outlet_id,quantity)
    values(v_product_id,v_outlet_id,v_qty)
    returning quantity into v_stock_after;
  end if;

  update public.products
  set buy_price=v_cost
  where id=v_product_id and business_id=v_business_id;

  insert into public.cash_transactions(business_id,outlet_id,user_id,type,amount,description)
  values(v_business_id,v_outlet_id,v_uid,'out',v_total,'Pembelian '||v_invoice)
  returning id into v_cash_id;

  insert into public.audit_logs(business_id,user_id,action,entity,entity_id,metadata)
  values(v_business_id,v_uid,'purchase.create','purchases',v_purchase_id,
    jsonb_build_object('invoice_no',v_invoice,'supplier_name',v_supplier,'product_id',v_product_id,
      'quantity',v_qty,'unit_cost',v_cost,'total',v_total,'stock_before',v_stock_before,'stock_after',v_stock_after));

  return jsonb_build_object(
    'purchase_id',v_purchase_id,
    'cash_transaction_id',v_cash_id,
    'created_at',v_created_at,
    'invoice_no',v_invoice,
    'supplier_name',coalesce(v_supplier,'Umum'),
    'product_id',v_product_id,
    'quantity',v_qty,
    'unit_cost',v_cost,
    'total',v_total,
    'stock_quantity',v_stock_after
  );
end;
$function$;

revoke all on function public.kasira_create_purchase(jsonb) from public, anon;
grant execute on function public.kasira_create_purchase(jsonb) to authenticated;

comment on column public.purchases.supplier_name is 'Supplier label supplied at receiving time; no separate supplier master record required.';
