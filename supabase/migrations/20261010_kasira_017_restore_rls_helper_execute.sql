-- These SECURITY DEFINER helpers are called by KASIRA RLS policies.
-- They are narrowly scoped to auth.uid() and a target business/outlet; authenticated
-- must be allowed to execute them for policy evaluation, while anonymous/PUBLIC are denied.
revoke all on function public.has_business_role(uuid, text[]) from public, anon, authenticated;
grant execute on function public.has_business_role(uuid, text[]) to authenticated;

revoke all on function public.is_business_member(uuid) from public, anon, authenticated;
grant execute on function public.is_business_member(uuid) to authenticated;

revoke all on function public.is_outlet_member(uuid) from public, anon, authenticated;
grant execute on function public.is_outlet_member(uuid) to authenticated;
