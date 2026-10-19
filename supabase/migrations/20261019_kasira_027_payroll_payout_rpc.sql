-- KASIRA migration 027: atomic payroll payout and cash ledger entry.
create or replace function public.kasira_payroll_payout(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_business_id uuid := nullif(payload->>'business_id','')::uuid;
  v_outlet_id uuid := nullif(payload->>'outlet_id','')::uuid;
  v_employee_id uuid := nullif(payload->>'employee_id','')::uuid;
  v_period_start date := nullif(payload->>'period_start','')::date;
  v_period_end date := nullif(payload->>'period_end','')::date;
  v_amount numeric := coalesce((payload->>'amount')::numeric,0);
  v_employee_name text;
  v_payroll_id uuid;
  v_cash_id uuid;
  v_created_at timestamptz;
begin
  if v_uid is null then raise exception 'Silakan masuk terlebih dahulu.' using errcode='28000'; end if;
  if v_business_id is null or v_outlet_id is null or v_employee_id is null then
    raise exception 'Bisnis, outlet, dan karyawan wajib diisi.';
  end if;
  if not public.has_business_role(v_business_id,array['owner','manager']) then
    raise exception 'Hanya Owner atau Manager yang dapat membayar gaji.' using errcode='42501';
  end if;
  if not exists(select 1 from public.outlets o where o.id=v_outlet_id and o.business_id=v_business_id) then
    raise exception 'Outlet tidak sesuai dengan usaha aktif.' using errcode='42501';
  end if;
  if v_amount<=0 or v_period_start is null or v_period_end is null or v_period_end<v_period_start then
    raise exception 'Periode dan nominal gaji tidak valid.';
  end if;

  select e.name into v_employee_name
  from public.employees e
  where e.id=v_employee_id and e.business_id=v_business_id and e.status='active'
  for update;
  if not found then raise exception 'Karyawan aktif tidak ditemukan pada usaha ini.'; end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    v_business_id::text||':payroll:'||v_employee_id::text||':'||v_period_start::text||':'||v_period_end::text,0
  ));
  if exists(select 1 from public.payroll p where p.business_id=v_business_id
       and p.employee_id=v_employee_id and p.period_start=v_period_start and p.period_end=v_period_end
       and p.status='paid') then
    raise exception 'Gaji untuk karyawan dan periode ini sudah berstatus dibayar.';
  end if;

  insert into public.payroll(business_id,employee_id,period_start,period_end,gross_salary,deductions,net_salary,status)
  values(v_business_id,v_employee_id,v_period_start,v_period_end,v_amount,0,v_amount,'paid')
  returning id,created_at into v_payroll_id,v_created_at;

  insert into public.cash_transactions(business_id,outlet_id,user_id,type,amount,description)
  values(v_business_id,v_outlet_id,v_uid,'out',v_amount,'Pembayaran gaji '||v_employee_name)
  returning id into v_cash_id;

  insert into public.audit_logs(business_id,user_id,action,entity,entity_id,metadata)
  values(v_business_id,v_uid,'payroll.payout','payroll',v_payroll_id,
    jsonb_build_object('employee_id',v_employee_id,'employee_name',v_employee_name,
      'period_start',v_period_start,'period_end',v_period_end,'net_salary',v_amount));

  return jsonb_build_object('payroll_id',v_payroll_id,'cash_transaction_id',v_cash_id,
    'created_at',v_created_at,'employee_id',v_employee_id,'employee_name',v_employee_name,
    'period_start',v_period_start,'period_end',v_period_end,'gross_salary',v_amount,
    'deductions',0,'net_salary',v_amount,'status','Dibayar');
end;
$function$;

revoke all on function public.kasira_payroll_payout(jsonb) from public, anon;
grant execute on function public.kasira_payroll_payout(jsonb) to authenticated;
