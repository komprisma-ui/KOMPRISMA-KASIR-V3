-- The old VORA RPCs are not part of KASIRA. Disable direct invocation of
-- financial/network RPCs while retaining helper functions used by legacy RLS policies.
revoke all on function public.vora_network_summary(uuid, uuid) from public, anon, authenticated;
revoke all on function public.vora_request_withdrawal(uuid, numeric, jsonb, text) from public, anon, authenticated;
