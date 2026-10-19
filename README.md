# KASIRA — Professional POS & Business Management

**Release candidate:** 0.5.3-rc.1  
**Web test release:** https://komprisma-ui.github.io/KOMPRISMA-KASIR-V3/  
**Production Vercel domain (unchanged):** https://kasira-seven.vercel.app

KASIRA is a responsive cashier and business-management application built with React, Vite, Capacitor, Supabase Auth, and PostgreSQL. This repository contains the web release-candidate branch. A successful GitHub Pages deploy and smoke test do not equal full commercial acceptance or a signed Android release.

## Implemented and verified in the current branch

- Responsive interface for phone/tablet/desktop, light and dark appearance.
- Supabase email/password login, account sign-up, password-recovery email request, and first-owner setup flow.
- Multi-tenant business onboarding via database RPC; a verified account creates its own business and main outlet.
- Staff invitation tokens are email-bound, hashed in the database, single-use, and expire after seven days.
- Owner/Manager invitation UI and invitation status history. The code is displayed once and must be shared manually; automatic email delivery is not implemented in this UI.
- Owner role changes and membership removal go through restricted database RPCs and audit logging. Anonymous execute privilege was read-only checked as denied for owner onboarding/invitation/member-management RPCs.
- Database-level business membership checks and RLS; client-side menu hiding is only an interface convenience.
- Cloud checkout path uses `create_sale_atomic` for server-validated pricing/HPP, idempotency and stock protection. Offline sales are queued with client request IDs and retried when online.
- Product catalogue and outlet stock load from Supabase; product save/archive is business-scoped and role-guarded. Customer records, address, points and total spend persist in the database; points/spend are updated atomically by checkout. Purchases/receiving, stock adjustments, cash entries, returns/refunds and payroll payout now have tenant/role-checked database operations and loadback. Employee, attendance, fixed-asset and inventory UI paths now call business-scoped Supabase tables.
- Per-business local cache namespace and a fail-closed loading screen protect the UI while cloud membership context is initialized.
- Automated checks now run offline queue tests, production guards, Vite compilation, built-asset path checks, deploy the branch, and then request the published HTML/JavaScript/CSS to confirm the login UI and invite-RPC code are present/reachable.

## Latest verification

The latest release-candidate workflow run should be used as the source of truth:
https://github.com/komprisma-ui/KOMPRISMA-KASIR-V3/actions

The known-good deploy/smoke-test workflow for the base-path and post-deploy-checkout fix is:
https://github.com/komprisma-ui/KOMPRISMA-KASIR-V3/actions/runs/39187355074

Supabase project used by this branch: `clylvxgilwywwkxngmnv`. Migrations `kasira_021_multi_user_onboarding` through `kasira_027_payroll_payout_rpc` are recorded in the connected database. Read-only privilege checks confirmed the core onboarding and team RPCs reject anonymous execution.

## Limitations / acceptance gates before selling

Do not describe these as completed until tested and evidenced:

1. **Multi-module cloud synchronization:** POS, products, customers, stock adjustments, purchases, cash entries, returns, payroll, employee records, attendance, fixed assets and inventory have cloud paths, but accounting/journals, expenses and receipt/settings content still have local components. A complete E2E test is still needed to prove all reads/writes, RLS and tenant isolation on real accounts before sale.
2. **Real customer acceptance:** run two independent businesses/accounts and verify email confirmation, owner setup, correct invite email, wrong/expired/reused tokens, role restrictions, member removal, tenant isolation and session restoration on a second device. Static asset smoke tests do not validate those interactive Auth flows end-to-end.
3. **Supabase Auth settings:** confirm email sender and templates, site URL/redirect allow-list for each host, password-recovery callback handling, rate limits, and leaked-password protection in the actual project settings.
4. **Offline and payment semantics:** verify duplicate retry/concurrent stock checkout and offline recovery. “QRIS”, card and transfer in the cashier UI identify payment methods; they are not a live payment processor, webhook, refund or settlement integration.
5. **Hardware/Android:** test USB/Bluetooth/network printers, thermal 58/80 mm and A4 layouts, scanner behavior and WebView lifecycle on actual supported Android devices.
6. **Android release artifact:** a web deployment is not an Android APK/AAB. A commercial Android build needs controlled signing credentials, signed artefact generation, install/upgrade tests and verification. Do not commit a private signing keystore to Git.
7. **Legal/commercial release:** have privacy, data retention, account deletion, terms, support contact and customer-data handling reviewed for the actual business. Confirm the public production host does not have a deployment-team SSO gate.
8. **Database operations:** review query performance and indexes for KASIRA's actual workload. Do not apply blanket changes to shared VORA tables without specific evidence/ownership review.

## Development

This repository does not currently commit a `package-lock.json`; therefore workflow uses `npm install`, not deterministic `npm ci`. Generate and commit a reviewed lockfile before stable commercial release.

```bash
npm install
npm run dev
npm test
```

`npm test` executes:
- `npm run test:offline`
- `npm run check:production`
- `npm run build`
- `npm run check:dist`

For Android, `npm run build:android` requires the Android project and build toolchain; verify the resulting APK/AAB and its signing before distribution.
