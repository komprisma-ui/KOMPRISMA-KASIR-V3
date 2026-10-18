-- KASIRA production migration 021: multi-business owner onboarding and staff invitations.
-- Keeps business creation and role assignment in trusted database code.
-- Only authenticated, email-confirmed users can bootstrap their own business.
-- Staff must use an email-bound, time-limited, single-use invitation token.

drop trigger if exists kasira_bootstrap_first_owner_after_signup on auth.users;
drop function if exists public.kasira_bootstrap_first_owner();

create table if not exists public.kasira_invitations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  email text not null,
  role text not null check (role in ('manager','cashier','warehouse','employee')),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  constraint kasira_invitation_email_normalized check (email = lower(btrim(email))),
  constraint kasira_invitation_expiry_valid check (expires_at > created_at)
);

create index if not exists kasira_invitations_business_created_idx
  on public.kasira_invitations (business_id, created_at desc);
create index if not exists kasira_invitations_email_idx
  on public.kasira_invitations (lower(email), expires_at desc);
create unique index if not exists kasira_invitations_one_open_per_email_idx
  on public.kasira_invitations (business_id, lower(email))
  where accepted_at is null and revoked_at is null;

alter table public.kasira_invitations enable row level security;
revoke all on table public.kasira_invitations from public, anon, authenticated;

-- Tenant onboarding is idempotent and creates only a business owned by auth.uid().
create or replace function public.kasira_complete_owner_signup(p_business_name text)
returns table(out_business_id uuid, out_role text, out_business_name text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_business_id uuid;
  v_existing_role text;
  v_existing_business_id uuid;
  v_existing_business_name text;
  v_email_confirmed_at timestamptz;
  v_store_name text;
  v_slug_base text;
  v_slug text;
begin
  if v_uid is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode = '28000';
  end if;

  select coalesce(u.email_confirmed_at, u.confirmed_at)
    into v_email_confirmed_at
  from auth.users u
  where u.id = v_uid;

  if not found or v_email_confirmed_at is null then
    raise exception 'Verifikasi email terlebih dahulu sebelum mengaktifkan usaha.' using errcode = '28000';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 0));

  select m.business_id, m.role, b.name
    into v_existing_business_id, v_existing_role, v_existing_business_name
  from public.memberships m
  join public.businesses b on b.id = m.business_id
  where m.user_id = v_uid
  order by m.created_at
  limit 1;

  if found then
    if v_existing_role = 'owner' then
      return query select v_existing_business_id, v_existing_role, v_existing_business_name;
      return;
    end if;
    raise exception 'Akun ini sudah terhubung ke usaha lain. Gunakan akun baru untuk usaha berbeda.';
  end if;

  v_store_name := left(btrim(coalesce(p_business_name, '')), 120);
  if length(v_store_name) < 2 then
    raise exception 'Nama usaha minimal 2 karakter.';
  end if;

  v_slug_base := trim(both '-' from regexp_replace(lower(v_store_name), '[^a-z0-9]+', '-', 'g'));
  if v_slug_base = '' then v_slug_base := 'kasira'; end if;
  v_slug := left(v_slug_base, 35) || '-' || left(replace(v_uid::text, '-', ''), 8);

  insert into public.businesses(name, slug)
  values (v_store_name, v_slug)
  returning id into v_business_id;

  insert into public.outlets(business_id, name, code, address)
  values (v_business_id, 'Outlet Utama', 'MAIN', null);

  insert into public.memberships(business_id, user_id, role)
  values (v_business_id, v_uid, 'owner');

  return query select v_business_id, 'owner'::text, v_store_name;
end;
$function$;

-- Create a one-time invitation. The token is shown once and only its hash is stored.
create or replace function public.kasira_create_invitation(
  p_business_id uuid,
  p_email text,
  p_role text
)
returns table(invitation_token text, invitation_expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_role text := lower(btrim(coalesce(p_role, '')));
  v_actor_role text;
  v_token text;
  v_token_hash text;
  v_expires_at timestamptz := now() + interval '7 days';
begin
  if v_uid is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode = '28000';
  end if;

  if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Alamat email undangan tidak valid.';
  end if;

  if v_role not in ('manager','cashier','warehouse','employee') then
    raise exception 'Peran undangan tidak valid.';
  end if;

  select m.role into v_actor_role
  from public.memberships m
  where m.business_id = p_business_id and m.user_id = v_uid
  limit 1;

  if not found or v_actor_role not in ('owner','manager') then
    raise exception 'Hanya Owner atau Manager yang dapat mengundang pengguna.' using errcode = '42501';
  end if;

  if v_role = 'manager' and v_actor_role <> 'owner' then
    raise exception 'Hanya Owner yang dapat mengundang Manager.' using errcode = '42501';
  end if;

  -- Invalidate any older pending token for this email before creating a replacement.
  update public.kasira_invitations i
  set revoked_at = now()
  where i.business_id = p_business_id
    and i.email = v_email
    and i.accepted_at is null
    and i.revoked_at is null;

  v_token := upper(pg_catalog.encode(extensions.gen_random_bytes(24), 'hex'));
  v_token_hash := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(lower(v_token), 'UTF8'), 'sha256'),
    'hex'
  );

  insert into public.kasira_invitations
    (business_id, email, role, token_hash, created_by, expires_at)
  values
    (p_business_id, v_email, v_role, v_token_hash, v_uid, v_expires_at);

  return query select v_token, v_expires_at;
end;
$function$;

-- Accept an invitation only when token, account email, expiry, and membership rules match.
create or replace function public.kasira_accept_invitation(p_token text)
returns table(out_business_id uuid, out_role text, out_business_name text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_token text := upper(btrim(coalesce(p_token, '')));
  v_token_hash text;
  v_email text;
  v_email_confirmed_at timestamptz;
  v_invitation public.kasira_invitations%rowtype;
  v_member_role text;
  v_business_name text;
begin
  if v_uid is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode = '28000';
  end if;

  if length(v_token) < 32 or length(v_token) > 80 then
    raise exception 'Kode undangan tidak valid atau sudah kedaluwarsa.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 0));

  select u.email, coalesce(u.email_confirmed_at, u.confirmed_at)
    into v_email, v_email_confirmed_at
  from auth.users u
  where u.id = v_uid;

  if not found or v_email is null then
    raise exception 'Email akun tidak tersedia.';
  end if;
  if v_email_confirmed_at is null then
    raise exception 'Verifikasi email terlebih dahulu sebelum menerima undangan.' using errcode = '28000';
  end if;

  v_token_hash := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(lower(v_token), 'UTF8'), 'sha256'),
    'hex'
  );

  select i.* into v_invitation
  from public.kasira_invitations i
  where i.token_hash = v_token_hash
  for update;

  if not found then
    raise exception 'Kode undangan tidak valid atau sudah kedaluwarsa.';
  end if;

  -- A retried request after a lost network response returns the existing membership safely.
  if v_invitation.accepted_at is not null then
    if v_invitation.accepted_by = v_uid then
      select m.role, b.name into v_member_role, v_business_name
      from public.memberships m
      join public.businesses b on b.id = m.business_id
      where m.business_id = v_invitation.business_id and m.user_id = v_uid;
      if found then
        return query select v_invitation.business_id, v_member_role, v_business_name;
        return;
      end if;
    end if;
    raise exception 'Kode undangan sudah digunakan.';
  end if;

  if v_invitation.revoked_at is not null or v_invitation.expires_at <= now() then
    raise exception 'Kode undangan tidak valid atau sudah kedaluwarsa.';
  end if;

  if lower(v_email) <> v_invitation.email then
    raise exception 'Gunakan email yang sama dengan alamat email pada undangan.';
  end if;

  if exists (select 1 from public.memberships m where m.user_id = v_uid) then
    raise exception 'Akun ini sudah terhubung ke usaha lain atau sudah menjadi anggota. Gunakan akun yang sesuai.';
  end if;

  insert into public.memberships(business_id, user_id, role)
  values (v_invitation.business_id, v_uid, v_invitation.role);

  update public.kasira_invitations
  set accepted_by = v_uid, accepted_at = now()
  where id = v_invitation.id;

  select b.name into v_business_name
  from public.businesses b
  where b.id = v_invitation.business_id;

  return query select v_invitation.business_id, v_invitation.role, v_business_name;
end;
$function$;

-- Team information is returned only to Owner/Manager; invitation tokens are never returned.
create or replace function public.kasira_list_team(p_business_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_actor_role text;
  v_members jsonb;
  v_invitations jsonb;
begin
  if v_uid is null then
    raise exception 'Silakan masuk terlebih dahulu.' using errcode = '28000';
  end if;

  select m.role into v_actor_role
  from public.memberships m
  where m.business_id = p_business_id and m.user_id = v_uid
  limit 1;

  if not found or v_actor_role not in ('owner','manager') then
    raise exception 'Anda tidak memiliki izin melihat daftar pengguna.' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', m.user_id,
        'email', coalesce(u.email, ''),
        'role', m.role,
        'created_at', m.created_at
      ) order by m.created_at asc
    ),
    '[]'::jsonb
  )
  into v_members
  from public.memberships m
  left join auth.users u on u.id = m.user_id
  where m.business_id = p_business_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'email', i.email,
        'role', i.role,
        'created_at', i.created_at,
        'expires_at', i.expires_at,
        'accepted_at', i.accepted_at,
        'status', case
          when i.accepted_at is not null then 'accepted'
          when i.revoked_at is not null then 'revoked'
          when i.expires_at <= now() then 'expired'
          else 'pending'
        end
      ) order by i.created_at desc
    ),
    '[]'::jsonb
  )
  into v_invitations
  from (
    select *
    from public.kasira_invitations
    where business_id = p_business_id
    order by created_at desc
    limit 30
  ) i;

  return jsonb_build_object('members', v_members, 'invitations', v_invitations);
end;
$function$;

revoke all on function public.kasira_complete_owner_signup(text) from public, anon;
revoke all on function public.kasira_create_invitation(uuid, text, text) from public, anon;
revoke all on function public.kasira_accept_invitation(text) from public, anon;
revoke all on function public.kasira_list_team(uuid) from public, anon;

grant execute on function public.kasira_complete_owner_signup(text) to authenticated;
grant execute on function public.kasira_create_invitation(uuid, text, text) to authenticated;
grant execute on function public.kasira_accept_invitation(text) to authenticated;
grant execute on function public.kasira_list_team(uuid) to authenticated;
