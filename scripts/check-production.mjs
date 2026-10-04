import fs from "node:fs";

const required=["package.json","index.html","src/main.jsx","src/supabase.js","supabase/schema.sql","supabase/migrations/20261003_kasira_005_production.sql","supabase/migrations/20261003_kasira_006_invariants.sql","supabase/migrations/20261003_kasira_007_employee_auth.sql","supabase/migrations/20261003_kasira_008_idempotency_stock_audit.sql","supabase/migrations/20261004_kasira_009_final_role_hardening.sql","public/privacy-policy.html","public/delete-account.html"];
for(const file of required) if(!fs.existsSync(file)) throw new Error("Missing required file: "+file);

const pkg=JSON.parse(fs.readFileSync("package.json","utf8"));
if(!pkg.dependencies["@supabase/supabase-js"]) throw new Error("Supabase SDK is not configured.");
if(pkg.version!=="0.5.0") throw new Error("Unexpected KASIRA version.");

const auth=fs.readFileSync("src/auth-overlay.jsx","utf8");
for(const secret of ["owner123","pengguna123","kasir123","karyawan123"]) {
  if(auth.includes(secret)) throw new Error("Demo credentials must never ship in production.");
}
if(auth.includes('localStorage.setItem("kasira_session"')) throw new Error("Fake local session detected.");

for (const file of ["public/privacy-policy.html","public/delete-account.html"]) {
  const body=fs.readFileSync(file,"utf8");
  if (/\[(NAMA BADAN USAHA|ALAMAT RESMI|EMAIL KONTAK RESMI)\]/.test(body)) {
    throw new Error("Legal contact placeholders must be completed before production release: "+file);
  }
}
const main=fs.readFileSync("src/main.jsx","utf8");
if(!main.includes("client_request_id")||!main.includes("unit_cost_at_sale")) throw new Error("Production checkout idempotency/cost snapshot is missing.");
const authSource=fs.readFileSync("src/auth-overlay.jsx","utf8");
if(authSource.includes(".innerHTML=")) throw new Error("Unsafe innerHTML assignment detected in authentication UI.");
console.log("KASIRA production checks passed.");
