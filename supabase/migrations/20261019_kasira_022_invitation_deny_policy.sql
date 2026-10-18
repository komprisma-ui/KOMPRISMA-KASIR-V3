-- KASIRA production migration 022: explicitly deny direct access to invitation records.
-- Business workflows use the security-checked RPCs from migration 021.
-- This policy is intentionally false for authenticated and anonymous clients.
-- Direct table privileges remain revoked as an independent protection layer.

drop policy if exists kasira_invitations_deny_direct_access on public.kasira_invitations;
create policy kasira_invitations_deny_direct_access
on public.kasira_invitations
for all
to anon, authenticated
using (false)
with check (false);
