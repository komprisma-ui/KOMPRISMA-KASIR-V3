-- Keep SECURITY DEFINER RLS helpers outside the exposed public API schema.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

alter function public.has_business_role(uuid, text[]) set schema private;
alter function public.is_business_member(uuid) set schema private;
alter function public.is_outlet_member(uuid) set schema private;

revoke all on function private.has_business_role(uuid, text[]) from public, anon, authenticated;
grant execute on function private.has_business_role(uuid, text[]) to authenticated;
revoke all on function private.is_business_member(uuid) from public, anon, authenticated;
grant execute on function private.is_business_member(uuid) to authenticated;
revoke all on function private.is_outlet_member(uuid) from public, anon, authenticated;
grant execute on function private.is_outlet_member(uuid) to authenticated;
