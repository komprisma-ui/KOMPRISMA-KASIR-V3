-- VORA identity and integrity hardening
-- Fixes member identity assignment, cross-business relationships,
-- placement uniqueness, and wallet provisioning.

-- One child slot per side in a placement tree.
create unique index if not exists uq_vora_member_parent_side
  on public.vora_members(placement_parent_id,placement_side)
  where placement_parent_id is not null and placement_side is not null;

-- Validate relationships even when an admin uses a direct table write.
create or replace function public.vora_validate_member_relationships()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.sponsor_member_id is not null and not exists (
    select 1 from public.vora_members m
    where m.id=new.sponsor_member_id
      and m.business_id=new.business_id
  ) then
    raise exception 'sponsor must belong to the same business';
  end if;

  if new.placement_parent_id is not null and not exists (
    select 1 from public.vora_members m
    where m.id=new.placement_parent_id
      and m.business_id=new.business_id
  ) then
    raise exception 'placement parent must belong to the same business';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_vora_member_relationships on public.vora_members;
create trigger trg_vora_member_relationships
before insert or update on public.vora_members
for each row execute function public.vora_validate_member_relationships();

-- Replace the earlier RPC with a safe admin function that accepts
-- the target Auth user explicitly.
drop function if exists public.vora_register_member(uuid,text,text,text,uuid,uuid,text);

create or replace function public.vora_admin_create_member(
  p_business_id uuid,
  p_user_id uuid,
  p_member_code text,
  p_display_name text,
  p_phone text default null,
  p_sponsor_member_id uuid default null,
  p_placement_parent_id uuid default null,
  p_placement_side text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id uuid;
begin
  if not public.has_business_role(p_business_id,array['owner','manager']) then
    raise exception 'not authorized';
  end if;

  if p_user_id is null then raise exception 'user_id is required'; end if;
  if nullif(trim(p_member_code),'') is null then raise exception 'member_code is required'; end if;
  if nullif(trim(p_display_name),'') is null then raise exception 'display_name is required'; end if;

  if not exists(select 1 from auth.users u where u.id=p_user_id) then
    raise exception 'auth user does not exist';
  end if;

  if p_sponsor_member_id is not null and not exists (
    select 1 from public.vora_members
    where id=p_sponsor_member_id and business_id=p_business_id and status='active'
  ) then raise exception 'invalid sponsor'; end if;

  if p_placement_parent_id is not null and not exists (
    select 1 from public.vora_members
    where id=p_placement_parent_id and business_id=p_business_id and status='active'
  ) then raise exception 'invalid placement parent'; end if;

  if p_placement_side is not null and p_placement_side not in ('left','right') then
    raise exception 'invalid placement side';
  end if;

  insert into public.vora_members(
    business_id,user_id,member_code,display_name,phone,
    sponsor_member_id,placement_parent_id,placement_side
  )
  values(
    p_business_id,p_user_id,trim(p_member_code),trim(p_display_name),p_phone,
    p_sponsor_member_id,p_placement_parent_id,p_placement_side
  )
  returning id into v_id;

  insert into public.vora_wallets(business_id,member_id,currency)
  values(p_business_id,v_id,'IDR')
  on conflict (business_id,member_id,currency) do nothing;

  insert into public.vora_audit_logs(
    business_id,actor_user_id,action,entity,entity_id,after_data
  )
  values(
    p_business_id,(select auth.uid()),'member.create','vora_members',v_id,
    jsonb_build_object(
      'member_code',p_member_code,
      'display_name',p_display_name,
      'target_user_id',p_user_id
    )
  );

  return v_id;
end;
$$;

revoke all on function public.vora_admin_create_member(uuid,uuid,text,text,text,uuid,uuid,text) from public;
revoke all on function public.vora_admin_create_member(uuid,uuid,text,text,text,uuid,uuid,text) from anon;
grant execute on function public.vora_admin_create_member(uuid,uuid,text,text,text,uuid,uuid,text) to authenticated;

-- Self-registration/claim path. It creates the member for the currently
-- authenticated user and never accepts an arbitrary user_id.
create or replace function public.vora_join_member(
  p_business_id uuid,
  p_member_code text,
  p_display_name text,
  p_phone text default null,
  p_sponsor_member_id uuid default null,
  p_placement_parent_id uuid default null,
  p_placement_side text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;

  if nullif(trim(p_member_code),'') is null then raise exception 'member_code is required'; end if;
  if nullif(trim(p_display_name),'') is null then raise exception 'display_name is required'; end if;

  if p_sponsor_member_id is not null and not exists (
    select 1 from public.vora_members
    where id=p_sponsor_member_id and business_id=p_business_id and status='active'
  ) then raise exception 'invalid sponsor'; end if;

  if p_placement_parent_id is not null and not exists (
    select 1 from public.vora_members
    where id=p_placement_parent_id and business_id=p_business_id and status='active'
  ) then raise exception 'invalid placement parent'; end if;

  if p_placement_side is not null and p_placement_side not in ('left','right') then
    raise exception 'invalid placement side';
  end if;

  insert into public.vora_members(
    business_id,user_id,member_code,display_name,phone,
    sponsor_member_id,placement_parent_id,placement_side,status
  )
  values(
    p_business_id,(select auth.uid()),trim(p_member_code),trim(p_display_name),p_phone,
    p_sponsor_member_id,p_placement_parent_id,p_placement_side,'pending'
  )
  returning id into v_id;

  insert into public.vora_wallets(business_id,member_id,currency)
  values(p_business_id,v_id,'IDR')
  on conflict (business_id,member_id,currency) do nothing;

  insert into public.vora_audit_logs(
    business_id,actor_user_id,action,entity,entity_id,after_data
  )
  values(
    p_business_id,(select auth.uid()),'member.join','vora_members',v_id,
    jsonb_build_object('member_code',p_member_code)
  );

  return v_id;
end;
$$;

revoke all on function public.vora_join_member(uuid,text,text,text,uuid,uuid,text) from public;
revoke all on function public.vora_join_member(uuid,text,text,text,uuid,uuid,text) from anon;
grant execute on function public.vora_join_member(uuid,text,text,text,uuid,uuid,text) to authenticated;

-- Remove the obsolete direct function if a previous deployment left it around.
revoke all on function public.vora_register_member(uuid,text,text,text,uuid,uuid,text) from public;

-- Wallet provisioning for admin-created members is done in the RPC above.
-- Direct member inserts are allowed only for admins; a wallet is still
-- provisioned defensively by this trigger for migration/import paths.
create or replace function public.vora_ensure_wallet()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into public.vora_wallets(business_id,member_id,currency)
  values(new.business_id,new.id,'IDR')
  on conflict (business_id,member_id,currency) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_vora_ensure_wallet on public.vora_members;
create trigger trg_vora_ensure_wallet
after insert on public.vora_members
for each row execute function public.vora_ensure_wallet();

-- A member can only be active when linked to a real Auth identity.
alter table public.vora_members
  drop constraint if exists vora_members_user_id_not_null;
alter table public.vora_members
  alter column user_id set not null;

-- End identity hardening.
