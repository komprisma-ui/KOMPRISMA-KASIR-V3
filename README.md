# KASIRA — Professional POS v0.5.2 release candidate

KASIRA is a responsive point-of-sale and business-management application built with React, Vite, Capacitor, Supabase Auth, and PostgreSQL.

## Implemented safeguards and features

- Responsive POS for phone, tablet, and desktop, with light/dark themes.
- Supabase Auth login and email/password sign-up.
- Multi-tenant business onboarding: a verified user can create their own business and main outlet; tenant creation and owner assignment happen in a trusted database function.
- Staff onboarding through a one-time, email-bound invitation code that expires after seven days.
- Owner/Manager user management: issue invitations and review active memberships and invitation status. The invitation code is shown only once; sending it to the recipient remains a manual step.
- Database-enforced role checks and Row Level Security (RLS). Client-side menu hiding is a usability feature, not the security boundary.
- Atomic cloud checkout with idempotency, server-authoritative price/HPP validation, and stock protection.
- Offline/local persistence fallback with an offline-queue test.
- Product, stock, purchasing, customer, sales, reporting, accounting, assets, inventory, employee, attendance, cash, and returns modules.
- Production security migration 011 removes permissive legacy RLS policies. Migration 021 adds isolated owner onboarding and secure staff invitations.
- Production guard checks for transaction safeguards, auth flows, migration presence, invitation RLS, and restricted RPC access.

## Current verification state

- The connected KASIRA Supabase project is active and healthy.
- Database migrations through `kasira_021_multi_user_onboarding` are recorded. Read-only verification confirmed the invitation table, RLS, and all four onboarding/team RPC functions exist. The invitation table has no direct client policies; anonymous execution of the invitation RPC is denied.
- Vercel has `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` variables configured for Production, Preview, and Development.
- The multi-user UI and production guards are on branch `feat/kasira-multi-user-onboarding`; they are not yet promoted to the production branch.
- A successful deployment status does not substitute for an end-to-end sign-up/sign-in/invitation test. The release candidate still requires CI/build verification and real-device acceptance.

## Checklist before commercial publication

1. Complete CI/build verification for this release candidate, review the preview, and merge/deploy only after checks pass.
2. Test the end-to-end flows with separate test accounts: owner creates business, email confirmation, wrong/expired/reused invitation, email mismatch, staff joins, role-limited access, and cross-business data isolation.
3. In Supabase Auth settings, enable leaked-password protection and verify email confirmation, redirect URLs, rate limits, password recovery, and sender configuration.
4. Run real-device acceptance tests: checkout and concurrent stock changes, offline queue and retry/idempotency, backup/restore, Bluetooth/USB/thermal printer sizes, barcode scanner, and Android WebView behavior.
5. Set up a controlled Android release keystore and produce/verify a signed release APK/AAB. A successful web deployment does not mean a signed Android release artifact exists.
6. Confirm the public production domain is reachable without deployment-team SSO gates, while application access remains protected by Supabase Auth and database RLS.
7. Have the privacy, data retention, account-deletion, and commercial terms reviewed for the actual business operation. If QRIS/online payments are sold as a feature, integrate a live provider and test webhooks/refund/reconciliation; choosing a payment method in the UI is not a live gateway integration.
8. Review database performance advisor findings before launch. The latest advisor reported 55 unindexed foreign keys across the shared database (many belong to VORA tables); assess ownership and query patterns and add targeted indexes without changing unrelated VORA schema blindly.

## Development

This repository currently has no committed npm lockfile, so use `npm install` rather than `npm ci` until a lockfile is generated and committed.

```bash
npm install
npm run dev
```

Production verification:

```bash
npm run test
```

Android build:

```bash
npm run build:android
```

Before producing a signed release, verify the Android signing configuration and test the exact generated APK/AAB on supported devices.
