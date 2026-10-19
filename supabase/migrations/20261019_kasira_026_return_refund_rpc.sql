-- KASIRA migration 026: atomic returns/refunds with quantity validation and stock restore.
create or replace function public.kasira_create_sale_return(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_sale_id uuid := nullif(payload->>'sale_id','')::uuid;
  v_item_id uuid := nullif(payload->>'sale_item_id','')::uuid;
  v_qty numeric := coalesce((payload->>'quantity')::numeric,0);
  v_reason text := left(btrim(coalesce(payload->>'reason','Barang dikembalikan')),500);
  v_business_id uuid;
  v_outlet_id uuid;
  v_product_id uuid;
  v_invoice text;
  v_item_qty numeric;
  v_item_total numeric;
  v_subtotal numeric;
  v_discount numeric;
  v_tax numeric;
  v_returned numeric;
  v_base_refund numeric;
  v_refund numeric;
  v_return_id uuid;
  v_cash_id uuid;
  v_created_at timestamptz;
  v_stock numeric;
begin
  if v_uid is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode='28000';
  end if;
  if v_sale_id is null or v_item_id is null or v_qty<=0 then
    raise exception 'Transaksi, barang, dan qty retur wajib valid.';
  end if;

  select s.business_id,s.outlet_id,s.invoice_no,s.subtotal,s.discount,s.tax,
         si.product_id,si.quantity,si.total
    into v_business_id,v_outlet_id,v_invoice,v_subtotal,v_discount,v_tax,
         v_product_id,v_item_qty,v_item_total
  from public.sales s
  join public.sale_items si on si.sale_id=s.id
  where s.id=v_sale_id and si.id=v_item_id
  for update of si;

  if not found then raise exception 'Transaksi atau baris barang tidak ditemukan.'; end if;
  if not public.has_business_role(v_business_id,array['owner','manager','cashier']) then
    raise exception 'Tidak memiliki hak untuk memproses retur.' using errcode='42501';
  end if;
  if not exists(select 1 from public.outlets o where o.id=v_outlet_id and o.business_id=v_business_id) then
    raise exception 'Outlet transaksi tidak valid.' using errcode='42501';
  end if;

  select coalesce(sum(r.qty),0) into v_returned
  from public.sale_returns r
  where r.sale_id=v_sale_id and r.sale_item_id=v_item_id;
  if v_qty > v_item_qty-v_returned then
    raise exception 'Qty retur melebihi sisa barang yang dapat diretur.';
  end if;

  if v_subtotal-v_discount<=0 then
    v_base_refund:=0;
  else
    v_base_refund:=round((v_item_total/v_item_qty)*v_qty,2);
  end if;
  v_refund:=round(v_base_refund + case when v_subtotal-v_discount>0 then v_base_refund*(v_tax/(v_subtotal-v_discount)) else 0 end,2);
  if v_refund<=0 then raise exception 'Nilai refund tidak valid.'; end if;

  perform pg_catalog.set_config('request.jwt.claims',
    jsonb_build_object('stock_source','return','sub',v_uid)::text,true);

  select ps.quantity into v_stock
  from public.product_stocks ps
  where ps.product_id=v_product_id and ps.outlet_id=v_outlet_id
  for update;
  if not found then
    insert into public.product_stocks(product_id,outlet_id,quantity)
    values(v_product_id,v_outlet_id,v_qty);
  else
    update public.product_stocks set quantity=quantity+v_qty,updated_at=now()
    where product_id=v_product_id and outlet_id=v_outlet_id;
  end if;

  insert into public.sale_returns(business_id,outlet_id,sale_id,sale_item_id,qty,refund_amount,reason,created_by)
  values(v_business_id,v_outlet_id,v_sale_id,v_item_id,v_qty,v_refund,nullif(v_reason,''),v_uid)
  returning id,created_at into v_return_id,v_created_at;

  insert into public.cash_transactions(business_id,outlet_id,user_id,type,amount,description)
  values(v_business_id,v_outlet_id,v_uid,'out',v_refund,'Refund retur '||v_invoice)
  returning id into v_cash_id;

  insert into public.audit_logs(business_id,user_id,action,entity,entity_id,metadata)
  values(v_business_id,v_uid,'sale.return','sale_returns',v_return_id,
    jsonb_build_object('sale_id',v_sale_id,'sale_item_id',v_item_id,'product_id',v_product_id,
      'quantity',v_qty,'refund_amount',v_refund,'invoice_no',v_invoice));

  return jsonb_build_object('return_id',v_return_id,'cash_transaction_id',v_cash_id,
    'created_at',v_created_at,'sale_id',v_sale_id,'sale_item_id',v_item_id,
    'product_id',v_product_id,'invoice_no',v_invoice,'quantity',v_qty,
    'refund_amount',v_refund,'reason',v_reason);
end;
$function$;

revoke all on function public.kasira_create_sale_return(jsonb) from public, anon;
grant execute on function public.kasira_create_sale_return(jsonb) to authenticated;
