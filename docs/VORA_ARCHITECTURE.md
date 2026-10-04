# VORA — Digital Business Ecosystem

## Positioning
VORA is a digital business ecosystem built around real products, customers, transactions and measurable business value. Network rewards are generated from qualified commercial activity, not from recruitment fees or deposits.

## Product surfaces
- VORA App: member/customer mobile experience
- VORA Store: product discovery and checkout
- VORA Business: partner/business dashboard
- VORA Wallet: balance, ledger and withdrawals
- VORA Network: sponsor/tree visualization and team performance
- VORA Academy: training/content
- VORA Rewards: points, rank and incentives
- VORA Admin: operations, finance, KYC, products, orders, commissions, risk and audit

## Core domains
1. Identity & access
2. Businesses & memberships
3. Members, sponsor and placement tree
4. Customers and commerce
5. Commission rules and immutable commission ledger
6. Wallet and withdrawal
7. Rank/PV/CV
8. Promotions and rewards
9. Notifications
10. Risk, fraud and audit
11. Accounting integration
12. Reporting

## Non-negotiable financial rules
- No commission is created merely because a person registers, pays a membership fee, or recruits another person.
- Commission source must reference a real qualified order/sale.
- Commission ledger entries are immutable; corrections use reversal entries.
- Refund/cancellation reverses related commission.
- Wallet balance is derived from an append-only transaction ledger, with controlled cached balance where needed.
- Every privileged financial action is auditable.
- Idempotency keys are mandatory for payment/webhook/commission settlement paths.

## Initial stack
- Frontend: React + Vite, mobile via Capacitor
- Backend/data: Supabase PostgreSQL + Auth + RLS + RPC
- UI: responsive mobile-first VORA design system
- Future scale path: service/API extraction without changing domain contracts

## Delivery order
Phase 1: data foundation + authorization + member/network model
Phase 2: commerce + order qualification
Phase 3: commission engine + wallet
Phase 4: rank/reward + reports
Phase 5: admin + risk + audit
Phase 6: mobile polish + production hardening + release
