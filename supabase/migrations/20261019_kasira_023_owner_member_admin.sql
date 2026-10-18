-- KASIRA production migration 023: owner-managed team roles and membership removal.
-- No public/anonymous execution. Mutations are scoped to the authenticated owner's business.
create or replace function public.kasira_set_member_role(
  p_business_id uuid,
  p_user_id uuid,
  p_role text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_role text;
  v_target_role text;
  v_new_role text := lower(btrim(coalesce(p_role, '')));
begin
  if v_actor is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode = '28000';
  end if;

  select m.role into v_actor_role
  from public.memberships m
  where m.business_id = p_business_id and m.user_id = v_actor
  limit 1;

  if v_actor_role is distinct from 'owner' then
    raise exception 'Hanya Owner yang dapat mengubah peran pengguna.' using errcode = '42501';
  end if;
  if p_user_id = v_actor then
    raise exception 'Peran akun Owner yang sedang digunakan tidak dapat diubah dari menu ini.';
  end if;
  if v_new_role not in ('manager','cashier','warehouse','employee') then
    raise exception 'Peran yang dipilih tidak valid.';
  end if;

  select m.role into v_target_role
  from public.memberships m
  where m.business_id = p_business_id and m.user_id = p_user_id
  for update;

  if not found then
    raise exception 'Pengguna tidak ditemukan pada usaha ini.';
  end if;
  if v_target_role = 'owner' then
    raise exception 'Peran Owner tidak dapat diubah melalui pengelolaan anggota.';
  end if;

  update public.memberships
  set role = v_new_role
  where business_id = p_business_id and user_id = p_user_id;

  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, metadata)
  values (
    p_business_id, v_actor, 'member_role_updated', 'membership', p_user_id,
    jsonb_build_object('previous_role', v_target_role, 'new_role', v_new_role)
  );

  return v_new_role;
end;
$function$;

create or replace function public.kasira_remove_member(
  p_business_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_actor_role text;
  v_target_role text;
begin
  if v_actor is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode = '28000';
  end if;

  select m.role into v_actor_role
  from public.memberships m
  where m.business_id = p_business_id and m.user_id = v_actor
  limit 1;

  if v_actor_role is distinct from 'owner' then
    raise exception 'Hanya Owner yang dapat menghapus anggota.' using errcode = '42501';
  end if;
  if p_user_id = v_actor then
    raise exception 'Owner tidak dapat menghapus akun yang sedang digunakan.';
  end if;

  select m.role into v_target_role
  from public.memberships m
  where m.business_id = p_business_id and m.user_id = p_user_id
  for update;

  if not found then
    raise exception 'Pengguna tidak ditemukan pada usaha ini.';
  end if;
  if v_target_role = 'owner' then
    raise exception 'Akun Owner utama tidak dapat dihapus melalui menu anggota.';
  end if;

  delete from public.memberships
  where business_id = p_business_id and user_id = p_user_id;

  insert into public.audit_logs (business_id, user_id, action, entity, entity_id, metadata)
  values (
    p_business_id, v_actor, 'member_removed', 'membership', p_user_id,
    jsonb_build_object('previous_role', v_target_role)
  );

  return true;
end;
$function$;

revoke all on function public.kasira_set_member_role(uuid, uuid, text) from public, anon;
revoke all on function public.kasira_remove_member(uuid, uuid) from public, anon;
grant execute on function public.kasira_set_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.kasira_remove_member(uuid, uuid) to authenticated;
