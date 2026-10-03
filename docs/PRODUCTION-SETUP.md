# KASIRA — Production Setup

## 1. Supabase

Create a Supabase project and run supabase/schema.sql in the SQL Editor.

The application uses Supabase Auth for identity/session, memberships for business roles, PostgreSQL RLS for tenant isolation, and create_sale_atomic(jsonb) for the server-side checkout primitive.

The browser must only receive the publishable/anon key. Never put a service_role key in a VITE_* variable or in the APK.

Vite embeds VITE_* values into the client bundle, so they are configuration, not secrets. Keep server-only credentials out of the frontend.

## 2. Bootstrap the first Owner

Create the first user in Supabase Authentication > Users.

Then run this in the SQL Editor after replacing placeholders:

```sql
insert into public.businesses(name,slug) values ('Nama Usaha Anda','nama-usaha-anda') returning id;
insert into public.outlets(business_id,name,code,address) values ('BUSINESS_UUID','Outlet Utama','UTAMA','Alamat usaha') returning id;
insert into public.memberships(business_id,user_id,role) values ('BUSINESS_UUID','AUTH_USER_UUID','owner');
```

## 3. Create staff

Create each staff account in Supabase Auth, then add a membership:

```sql
insert into public.memberships(business_id,user_id,role) values
  ('BUSINESS_UUID','USER_UUID_MANAGER','manager'),
  ('BUSINESS_UUID','USER_UUID_CASHIER','cashier'),
  ('BUSINESS_UUID','USER_UUID_WAREHOUSE','warehouse'),
  ('BUSINESS_UUID','USER_UUID_EMPLOYEE','employee');
```

Roles are enforced by RLS as well as the UI. Hiding a menu is not the security boundary.

## 4. Frontend environment

Create .env.local:

```
VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

Do not commit .env.local.

## 5. Android signing

Generate a release keystore once and keep it outside the repository:

```bash
keytool -genkeypair -v -keystore kasira-release.jks -alias kasira -keyalg RSA -keysize 4096 -validity 10000
```

GitHub Actions secrets required:
- VITE_SUPABASE_URL
- VITE_SUPABASE_ANON_KEY
- KASIRA_KEYSTORE_BASE64
- KASIRA_KEYSTORE_PASSWORD
- KASIRA_KEYSTORE_ALIAS
- KASIRA_KEYSTORE_ALIAS_PASSWORD

PowerShell base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('kasira-release.jks'))
```

The signing key must never be committed to Git.

## 6. Release

Run GitHub Actions > KASIRA Production Release.

The workflow installs dependencies, runs production source guards, builds the web bundle, creates/syncs Android, signs the release, produces AAB and APK, verifies the AAB signature, and uploads both artifacts.

The AAB is intended for Google Play distribution; the APK is useful for controlled direct installation.

## 7. Database rollout

For an existing Supabase installation, apply migrations in order after the base schema:
1. supabase/migrations/20261003_kasira_005_production.sql
2. supabase/migrations/20261003_kasira_006_invariants.sql

Migration 006 adds database-level money, stock, quantity, payment-method, and transaction-formula invariants. For a new database, run supabase/schema.sql first, then apply both migrations in order.

## 8. Pre-launch checklist

- Owner can sign in.
- Manager cannot access Owner-only settings.
- Cashier cannot mutate products, accounting, payroll, or memberships.
- Employee cannot access sales.
- Cross-business reads/writes are denied.
- Duplicate invoices are rejected.
- Stock cannot go below zero through atomic checkout.
- Returns are audited.
- Backup restore is tested on a copy.
- Release AAB is signed with the permanent production key.
- Privacy policy and Play Console declarations are completed.
- Real QRIS/payment gateway and printer integrations are tested separately; the current UI buttons are not proof of payment settlement.