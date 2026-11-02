import fs from "node:fs";

const required=[
  "package.json","index.html","src/main.jsx","src/supabase.js",
  "src/local-db.js","src/offline-auth.js","src/offline-auth.jsx","src/offline-users.jsx","scripts/build-android-offline.mjs","capacitor.config.ts",
  "public/sw.js",".env.offline","README-OFFLINE.md","scripts/test-offline-local.mjs","scripts/test-indexeddb.mjs",
  "supabase/schema.sql",
  "supabase/migrations/20261003_kasira_005_production.sql",
  "supabase/migrations/20261003_kasira_006_invariants.sql",
  "supabase/migrations/20261003_kasira_007_employee_auth.sql",
  "supabase/migrations/20261003_kasira_008_idempotency_stock_audit.sql",
  "supabase/migrations/20261004_kasira_009_final_role_hardening.sql",
  "supabase/migrations/20261004_kasira_010_transaction_bypass_hardening.sql",
  "supabase/migrations/20261007_kasira_011_rls_bypass_hardening.sql",
  "supabase/migrations/20261019_kasira_021_multi_user_onboarding.sql",
  "supabase/migrations/20261019_kasira_022_invitation_deny_policy.sql",
  "public/privacy-policy.html","public/delete-account.html"
];
for(const file of required) if(!fs.existsSync(file)) throw new Error("Missing required file: "+file);

const pkg=JSON.parse(fs.readFileSync("package.json","utf8"));
if(!pkg.dependencies["@supabase/supabase-js"]) throw new Error("Supabase SDK is not configured.");
if(!/^0\.5\.[0-9]+$/.test(pkg.version)) throw new Error("Unexpected KASIRA version: "+pkg.version);

const auth=fs.readFileSync("src/auth-overlay.jsx","utf8");
for(const secret of ["owner123","pengguna123","kasir123","karyawan123"])
  if(auth.includes(secret)) throw new Error("Demo credentials must never ship in production.");
if(auth.includes('localStorage.setItem("kasira_session"'))
  throw new Error("Fake local session detected.");

for(const file of ["public/privacy-policy.html","public/delete-account.html"]){
  const body=fs.readFileSync(file,"utf8");
  if(/\[(NAMA BADAN USAHA|ALAMAT RESMI|EMAIL KONTAK RESMI)\]/.test(body))
    throw new Error("Legal contact placeholders must be completed before production release: "+file);
}

const main=fs.readFileSync("src/main.jsx","utf8");
for(const marker of ["client_request_id","unit_cost_at_sale","cloudSales","create_sale_atomic"])
  if(!main.includes(marker)) throw new Error("Production checkout safeguard missing: "+marker);

const authSource=fs.readFileSync("src/auth-overlay.jsx","utf8");
if(authSource.includes(".innerHTML=")) throw new Error("Unsafe innerHTML assignment detected in authentication UI.");
for(const marker of [
  "supabase.auth.signUp",
  "resetPasswordForEmail(",
  'PASSWORD_RECOVERY',
  'updateUser({ password: newPassword })',
  'rpc("kasira_complete_owner_signup"',
  'rpc("kasira_accept_invitation"',
  'rpc("kasira_create_invitation"',
  'rpc("kasira_list_team"'
]) if(!authSource.includes(marker)) throw new Error("Multi-user authentication/recovery safeguard missing: "+marker);

const onboardingMigration=fs.readFileSync("supabase/migrations/20261019_kasira_021_multi_user_onboarding.sql","utf8");
for(const marker of [
  "alter table public.kasira_invitations enable row level security",
  "revoke all on table public.kasira_invitations from public, anon, authenticated",
  "grant execute on function public.kasira_accept_invitation(text) to authenticated",
  "pg_catalog.hashtextextended",
  "extensions.digest"
]) if(!onboardingMigration.includes(marker)) throw new Error("Invitation/onboarding security guard missing: "+marker);

const invitationPolicyMigration=fs.readFileSync("supabase/migrations/20261019_kasira_022_invitation_deny_policy.sql","utf8");
for(const marker of ["for all","to anon, authenticated","using (false)","with check (false)"])
  if(!invitationPolicyMigration.includes(marker)) throw new Error("Invitation direct-access deny policy missing: "+marker);

const migration=fs.readFileSync("supabase/migrations/20261007_kasira_011_rls_bypass_hardening.sql","utf8");
for(const forbidden of ["drop policy if exists product_member_all","drop policy if exists stock_member_all","drop policy if exists sale_member_all","drop policy if exists sale_item_member_all"])
  if(!migration.includes(forbidden)) throw new Error("RLS bypass hardening missing: "+forbidden);

const offlineMain=fs.readFileSync("src/main.jsx","utf8");
for(const marker of ["OFFLINE_BUILD","writeLocalStateBatch","readLocalStateBatch","OfflineAuth","OfflineUsers"])
  if(!offlineMain.includes(marker)) throw new Error("KASIRA offline integration missing: "+marker);

const localDb=fs.readFileSync("src/local-db.js","utf8");
for(const marker of ["indexedDB.open","transactionFinished","writeLocalStateBatch","readLocalStateBatch"])
  if(!localDb.includes(marker)) throw new Error("KASIRA local database safeguard missing: "+marker);

const localAuth=fs.readFileSync("src/offline-auth.js","utf8");
for(const marker of ["PBKDF2","210000","createOfflineOwner","authenticateOfflineUser"])
  if(!localAuth.includes(marker)) throw new Error("KASIRA local authentication safeguard missing: "+marker);

const serviceWorker=fs.readFileSync("public/sw.js","utf8");
for(const marker of ["addEventListener(\"install\"","addEventListener(\"fetch\"","caches.open"])
  if(!serviceWorker.includes(marker)) throw new Error("KASIRA offline app cache missing: "+marker);

const offlineEnv=fs.readFileSync(".env.offline","utf8");
if(!offlineEnv.includes("VITE_KASIRA_MODE=offline")) throw new Error("KASIRA offline build mode is missing.");
if(!pkg.scripts["build:offline"]||!pkg.scripts["build:android:offline"]||!pkg.scripts["test:offline-local"]||!pkg.devDependencies["fake-indexeddb"])
  throw new Error("KASIRA offline build/test scripts are missing.");
const capacitorConfig=fs.readFileSync("capacitor.config.ts","utf8");
for(const marker of ["KASIRA_OFFLINE","com.kasira.pos.offline","android-offline"])
  if(!capacitorConfig.includes(marker)) throw new Error("Separate KASIRA offline Android identity is missing: "+marker);

console.log("KASIRA production and local-first offline checks passed.");
