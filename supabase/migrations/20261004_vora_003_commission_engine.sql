-- VORA commission settlement engine
-- Commission is derived from qualified commercial orders only.

create table if not exists public.vora_commission_runs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  order_id uuid not null references public.vora_orders(id) on delete restrict,
  status text not null default 'processing'
    check (status in ('processing','completed','failed')),
  total_commission numeric(18,2) not null default 0 check (total_commission >= 0),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  error_message text,
  unique (business_id,order_id)
);

create index if not exists idx_vora_commission_runs_order
  on public.vora_commission_runs(business_id,order_id);

create or replace function public.vora_settle_order_commissions(p_order_id uuid)
returns numeric
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order public.vora_orders%rowtype;
  v_run_id uuid;
  v_existing_status text;
  v_row record;
  v_amount numeric(18,2);
  v_source_key text;
  v_ledger_id uuid;
  v_wallet public.vora_wallets%rowtype;
  v_new_balance numeric(18,2);
  v_total numeric(18,2) := 0;
begin
  select * into v_order
  from public.vora_orders
  where id=p_order_id
  for update;

  if not found then raise exception 'order not found'; end if;

  if v_order.status <> 'completed' then
    raise exception 'order must be completed before commission settlement';
  end if;

  if v_order.qualified_amount <= 0 then
    raise exception 'order has no qualified amount';
  end if;

  select id,status into v_run_id,v_existing_status
  from public.vora_commission_runs
  where business_id=v_order.business_id and order_id=v_order.id
  for update;

  if v_run_id is not null and v_existing_status='completed' then
    select coalesce(sum(amount),0) into v_total
    from public.vora_commission_ledger
    where business_id=v_order.business_id
      and order_id=v_order.id
      and entry_type='credit'
      and status='posted';
    return v_total;
  end if;

  if v_run_id is null then
    insert into public.vora_commission_runs(business_id,order_id,status)
    values(v_order.business_id,v_order.id,'processing')
    returning id into v_run_id;
  else
    update public.vora_commission_runs
    set status='processing',error_message=null
    where id=v_run_id;
  end if;

  begin
    -- Direct sales commission: the member responsible for the sale.
    for v_row in
      select r.id as rule_id,r.code,r.rule_type,r.rate,r.fixed_amount,
             v_order.seller_member_id as member_id,0 as level
      from public.vora_commission_rules r
      where r.business_id=v_order.business_id
        and r.active
        and r.rule_type='direct_sales'
        and v_order.seller_member_id is not null
        and (r.starts_at is null or r.starts_at<=now())
        and (r.ends_at is null or r.ends_at>=now())

      union all

      -- Unilevel commission: sponsor chain only.
      with recursive chain as (
        select m.id as member_id,m.sponsor_member_id,1 as level
        from public.vora_members m
        where m.id=v_order.seller_member_id
          and m.business_id=v_order.business_id
        union all
        select p.id,p.sponsor_member_id,c.level+1
        from public.vora_members p
        join chain c on c.sponsor_member_id=p.id
        where p.business_id=v_order.business_id
          and c.level<100
      )
      select r.id,r.code,r.rule_type,r.rate,r.fixed_amount,
             c.member_id,c.level
      from public.vora_commission_rules r
      join chain c
        on r.rule_type='unilevel'
       and (r.level is null or r.level=c.level)
      where r.business_id=v_order.business_id
        and r.active
        and (r.starts_at is null or r.starts_at<=now())
        and (r.ends_at is null or r.ends_at>=now())
    loop
      if v_row.member_id is null then continue; end if;

      v_amount := round(
        (v_order.qualified_amount * coalesce(v_row.rate,0) / 100)
        + coalesce(v_row.fixed_amount,0),2
      );

      if v_amount<=0 then continue; end if;

      v_source_key := 'order:'||v_order.id::text||
        ':rule:'||v_row.rule_id::text||
        ':member:'||v_row.member_id::text||
        ':level:'||v_row.level::text;

      insert into public.vora_commission_ledger(
        business_id,member_id,order_id,rule_id,entry_type,amount,
        source_key,status,description,metadata
      )
      values(
        v_order.business_id,v_row.member_id,v_order.id,v_row.rule_id,'credit',
        v_amount,v_source_key,'posted',
        'Komisi VORA untuk order '||v_order.order_no,
        jsonb_build_object('rule',v_row.code,'level',v_row.level)
      )
      on conflict (business_id,source_key) do nothing
      returning id into v_ledger_id;

      if v_ledger_id is null then
        continue;
      end if;

      insert into public.vora_wallets(business_id,member_id,currency)
      values(v_order.business_id,v_row.member_id,'IDR')
      on conflict (business_id,member_id,currency) do nothing;

      select * into v_wallet
      from public.vora_wallets
      where business_id=v_order.business_id
        and member_id=v_row.member_id
        and currency='IDR'
      for update;

      if v_wallet.status<>'active' then
        raise exception 'wallet is not active for member %',v_row.member_id;
      end if;

      v_new_balance := v_wallet.available_balance + v_amount;

      update public.vora_wallets
      set available_balance=v_new_balance,updated_at=now()
      where id=v_wallet.id;

      insert into public.vora_wallet_transactions(
        wallet_id,business_id,member_id,direction,transaction_type,
        amount,balance_after,source_type,source_id,idempotency_key,
        description,metadata
      )
      values(
        v_wallet.id,v_order.business_id,v_row.member_id,'credit','commission',
        v_amount,v_new_balance,'commission',v_ledger_id,v_source_key,
        'Komisi order '||v_order.order_no,
        jsonb_build_object('order_id',v_order.id,'rule_id',v_row.rule_id,'level',v_row.level)
      )
      on conflict (wallet_id,idempotency_key) do nothing;

      v_total := v_total + v_amount;
    end loop;

    update public.vora_commission_runs
    set status='completed',total_commission=v_total,completed_at=now()
    where id=v_run_id;

    insert into public.vora_audit_logs(
      business_id,actor_user_id,action,entity,entity_id,after_data
    )
    values(
      v_order.business_id,(select auth.uid()),'commission.settle',
      'vora_orders',v_order.id,
      jsonb_build_object('run_id',v_run_id,'total_commission',v_total)
    );

    return v_total;
  exception when others then
    update public.vora_commission_runs
    set status='failed',error_message=left(sqlerrm,1000)
    where id=v_run_id;
    raise;
  end;
end;
$$;

revoke all on function public.vora_settle_order_commissions(uuid) from public;
revoke all on function public.vora_settle_order_commissions(uuid) from anon;
grant execute on function public.vora_settle_order_commissions(uuid) to authenticated;

-- Reverse all posted commission credits generated by an order.
-- The function refuses to create a negative available wallet balance.
create or replace function public.vora_reverse_order_commissions(p_order_id uuid)
returns numeric
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order public.vora_orders%rowtype;
  v_entry record;
  v_wallet public.vora_wallets%rowtype;
  v_new_balance numeric(18,2);
  v_total numeric(18,2) := 0;
  v_source_key text;
begin
  select * into v_order from public.vora_orders where id=p_order_id;
  if not found then raise exception 'order not found'; end if;

  for v_entry in
    select l.*
    from public.vora_commission_ledger l
    where l.business_id=v_order.business_id
      and l.order_id=v_order.id
      and l.entry_type='credit'
      and l.status='posted'
    order by l.created_at
  loop
    v_source_key := 'reversal:'||v_entry.id::text;

    insert into public.vora_commission_ledger(
      business_id,member_id,order_id,rule_id,entry_type,amount,
      source_key,related_entry_id,status,description
    )
    values(
      v_entry.business_id,v_entry.member_id,v_entry.order_id,v_entry.rule_id,
      'reversal',-v_entry.amount,v_source_key,v_entry.id,'posted',
      'Reversal komisi order '||v_order.order_no
    )
    on conflict (business_id,source_key) do nothing;

    if not found then continue; end if;

    select * into v_wallet
    from public.vora_wallets
    where business_id=v_entry.business_id
      and member_id=v_entry.member_id
      and currency='IDR'
    for update;

    if not found then raise exception 'wallet not found for commission member'; end if;
    if v_wallet.available_balance < v_entry.amount then
      raise exception 'insufficient wallet balance for commission reversal';
    end if;

    v_new_balance := v_wallet.available_balance-v_entry.amount;

    update public.vora_wallets
    set available_balance=v_new_balance,updated_at=now()
    where id=v_wallet.id;

    insert into public.vora_wallet_transactions(
      wallet_id,business_id,member_id,direction,transaction_type,
      amount,balance_after,source_type,source_id,idempotency_key,
      description
    )
    values(
      v_wallet.id,v_entry.business_id,v_entry.member_id,'debit','refund_reversal',
      v_entry.amount,v_new_balance,'commission_reversal',v_entry.id,v_source_key,
      'Reversal komisi order '||v_order.order_no
    )
    on conflict (wallet_id,idempotency_key) do nothing;

    v_total := v_total+v_entry.amount;
  end loop;

  insert into public.vora_audit_logs(
    business_id,actor_user_id,action,entity,entity_id,after_data
  )
  values(
    v_order.business_id,(select auth.uid()),'commission.reverse',
    'vora_orders',v_order.id,
    jsonb_build_object('total_reversed',v_total)
  );

  return v_total;
end;
$$;

revoke all on function public.vora_reverse_order_commissions(uuid) from public;
revoke all on function public.vora_reverse_order_commissions(uuid) from anon;
grant execute on function public.vora_reverse_order_commissions(uuid) to authenticated;

-- Only privileged business roles may call settlement/reversal.
-- The function itself checks the order business through a membership gate.
create or replace function public.vora_can_settle_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.vora_orders o
    where o.id=p_order_id
      and public.has_business_role(o.business_id,array['owner','manager'])
  )
$$;

revoke all on function public.vora_can_settle_order(uuid) from public;
grant execute on function public.vora_can_settle_order(uuid) to authenticated;

-- End commission settlement engine.
