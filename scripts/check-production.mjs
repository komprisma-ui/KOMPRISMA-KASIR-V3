import fs from "node:fs";

const required=["package.json","index.html","src/main.jsx","src/supabase.js","supabase/schema.sql"];
for(const file of required) if(!fs.existsSync(file)) throw new Error("Missing required file: "+file);

const pkg=JSON.parse(fs.readFileSync("package.json","utf8"));
if(!pkg.dependencies["@supabase/supabase-js"]) throw new Error("Supabase SDK is not configured.");
if(pkg.version!=="0.5.0") throw new Error("Unexpected KASIRA version.");

const auth=fs.readFileSync("src/auth-overlay.jsx","utf8");
for(const secret of ["owner123","pengguna123","kasir123","karyawan123"]) {
  if(auth.includes(secret)) throw new Error("Demo credentials must never ship in production.");
}
if(auth.includes('localStorage.setItem("kasira_session"')) throw new Error("Fake local session detected.");

console.log("KASIRA production checks passed.");
