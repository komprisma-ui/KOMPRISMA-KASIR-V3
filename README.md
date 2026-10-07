# KASIRA — Professional POS v0.5.1

Modern Point of Sale and business-management application built with React + Vite + Capacitor + Supabase.

## Current production hardening

- Premium responsive POS for mobile, tablet and desktop.
- Light/dark themes.
- Supabase Auth with business membership and role-based access.
- Multi-tenant PostgreSQL with RLS.
- Atomic cloud checkout with idempotency, server-authoritative price/HPP validation and stock protection.
- Offline/local persistence fallback.
- Product, stock, purchasing, customer, sales, reporting, accounting, assets, inventory, employee, attendance, cash and returns modules.
- Production security migration 011 closes permissive legacy RLS policies that could bypass role restrictions.
- CI verifies production guards and web build on every push/PR to `main`.

## Release blockers before commercial publication

1. Apply all Supabase migrations through `20261007_kasira_011_rls_bypass_hardening.sql` and verify them against the actual production project.
2. Replace the legal contact placeholders in `public/privacy-policy.html` and `public/delete-account.html`.
3. Configure and test production Supabase Auth, membership, outlet and role assignments.
4. Complete real-device acceptance tests for checkout, stock concurrency, backup/restore, printer and barcode hardware.
5. Configure a real Android release keystore and verify signed AAB/APK before store publication.
6. If QRIS/online payments are offered, connect a real gateway and test webhook/reconciliation flows; the current payment selector does not by itself constitute a live QRIS integration.

## Development

```bash
npm ci
npm run dev
```

Production verification:

```bash
npm run check:production
npm run build
```

Android build:

```bash
npm run build:android
```
