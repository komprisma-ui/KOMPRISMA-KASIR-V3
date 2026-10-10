-- One-time first-owner bootstrap for KASIRA.
-- Only auth sign-ups explicitly marked by the setup UI can enter this path.
-- The transaction lock prevents two simultaneous sign-ups from both becoming owner.

create or replace function public.kasira_bootstrap_first_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_store_name text;
  v_slug text;
begin
  if coalesce(new.raw_user_meta_data ->> 'kasira_first_owner_setup', 'false') <> 'true' then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('kasira-first-owner-bootstrap', 0));

  if exists (select 1 from public.businesses)
     or exists (select 1 from public.memberships) then
    raise exception 'KASIRA first owner has already been configured';
  end if;

  v_store_name := left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'business_name'), ''), 'PRISMAKOM'), 120);
  v_slug := trim(both '-' from regexp_replace(lower(v_store_name), '[^a-z0-9]+', '-', 'g'));
  if v_slug = '' then v_slug := 'kasira'; end if;
  v_slug := left(v_slug, 35) || '-' || left(replace(new.id::text, '-', ''), 8);

  insert into public.businesses(name, slug)
  values (v_store_name, v_slug)
  returning id into v_business_id;

  insert into public.outlets(business_id, name, code, address)
  values (v_business_id, 'Outlet Utama', 'MAIN', null);

  insert into public.memberships(business_id, user_id, role)
  values (v_business_id, new.id, 'owner');

  return new;
end;
$$;

revoke all on function public.kasira_bootstrap_first_owner() from public, anon, authenticated;

drop trigger if exists kasira_bootstrap_first_owner_after_signup on auth.users;
create trigger kasira_bootstrap_first_owner_after_signup
after insert on auth.users
for each row execute function public.kasira_bootstrap_first_owner();
