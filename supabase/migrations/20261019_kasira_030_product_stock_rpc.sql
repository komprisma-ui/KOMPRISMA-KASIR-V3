-- KASIRA migration 030: atomic product and initial/current outlet stock save.
create or replace function public.kasira_save_product(payload jsonb)
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
  v_sku text := left(btrim(coalesce(payload->>'sku','')),100);
  v_barcode text := nullif(left(btrim(coalesce(payload->>'barcode','')),100),'');
  v_name text := left(btrim(coalesce(payload->>'name','')),200);
  v_category text := left(btrim(coalesce(payload->>'category','Umum')),100);
  v_buy_price numeric := coalesce((payload->>'buy_price')::numeric,0);
  v_sell_price numeric := coalesce((payload->>'sell_price')::numeric,0);
  v_min_stock integer := coalesce((payload->>'min_stock')::integer,0);
  v_stock numeric := coalesce((payload->>'stock')::numeric,0);
  v_product public.products%rowtype;
  v_stock_now numeric;
begin
  if v_uid is null then raise exception 'Silakan masuk terlebih dahulu.' using errcode='28000'; end if;
  if v_business_id is null or v_outlet_id is null then raise exception 'Bisnis dan outlet wajib tersedia.'; end if;
  if length(v_sku)<1 or length(v_name)<2 then raise exception 'SKU dan nama produk wajib diisi.'; end if;
  if v_buy_price<0 or v_sell_price<0 or v_min_stock<0 or v_stock<0 then raise exception 'Harga dan stok tidak boleh negatif.'; end if;
  if not exists(select 1 from public.outlets o where o.id=v_outlet_id and o.business_id=v_business_id and public.is_business_member(o.business_id)) then
    raise exception 'Outlet tidak sesuai dengan usaha aktif.' using errcode='42501';
  end if;

  if v_product_id is null then
    if not public.has_business_role(v_business_id,array['owner','manager','warehouse']) then
      raise exception 'Peran Anda tidak diizinkan membuat produk.' using errcode='42501';
    end if;
  else
    if not public.has_business_role(v_business_id,array['owner','manager']) then
      raise exception 'Hanya Owner atau Manager yang dapat mengubah produk.' using errcode='42501';
    end if;
    select p.* into v_product from public.products p
    where p.id=v_product_id and p.business_id=v_business_id for update;
    if not found then raise exception 'Produk tidak ditemukan di usaha ini.'; end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_business_id::text||':stock:'||v_outlet_id::text||':'||coalesce(v_product_id::text,v_sku),0)
  );

  if v_product_id is null then
    insert into public.products(business_id,sku,barcode,name,category,buy_price,sell_price,min_stock,active)
    values(v_business_id,v_sku,v_barcode,v_name,coalesce(nullif(v_category,''),'Umum'),v_buy_price,v_sell_price,v_min_stock,true)
    returning * into v_product;
  else
    update public.products p
    set sku=v_sku,barcode=v_barcode,name=v_name,category=coalesce(nullif(v_category,''),'Umum'),
        buy_price=v_buy_price,sell_price=v_sell_price,min_stock=v_min_stock
    where p.id=v_product_id and p.business_id=v_business_id
    returning * into v_product;
  end if;

  perform pg_catalog.set_config('request.jwt.claims',
    jsonb_build_object('stock_source','product_save','sub',v_uid)::text,true);

  insert into public.product_stocks(product_id,outlet_id,quantity)
  values(v_product.id,v_outlet_id,v_stock)
  on conflict (outlet_id,product_id)
  do update set quantity=excluded.quantity,updated_at=now()
  returning quantity into v_stock_now;

  insert into public.audit_logs(business_id,user_id,action,entity,entity_id,metadata)
  values(v_business_id,v_uid,case when v_product_id is null then 'product.create' else 'product.update' end,
    'products',v_product.id,jsonb_build_object('sku',v_sku,'name',v_name,'outlet_id',v_outlet_id,
    'buy_price',v_buy_price,'sell_price',v_sell_price,'stock',v_stock_now));

  return jsonb_build_object('id',v_product.id,'sku',v_product.sku,'barcode',v_product.barcode,
    'name',v_product.name,'category',v_product.category,'buy_price',v_product.buy_price,
    'sell_price',v_product.sell_price,'min_stock',v_product.min_stock,'stock',v_stock_now,'active',v_product.active);
end;
$function$;

revoke all on function public.kasira_save_product(jsonb) from public, anon;
grant execute on function public.kasira_save_product(jsonb) to authenticated;
