import { createRoot } from "react-dom/client";
import React, { useEffect, useState } from "react";
import { getMembership, supabase, supabaseConfigured } from "./supabase";

const ACCESS = {
  owner:["Dashboard","Kasir","Produk","Stok","Pembelian","Pelanggan","Transaksi","Laporan","Akuntansi","Aset","Inventaris","Karyawan","Absensi","Kas","Retur","Pengaturan"],
  manager:["Dashboard","Kasir","Produk","Stok","Pembelian","Pelanggan","Transaksi","Laporan","Akuntansi","Aset","Inventaris","Karyawan","Absensi","Kas","Retur"],
  cashier:["Dashboard","Kasir","Pelanggan","Transaksi","Retur"],
  warehouse:["Dashboard","Produk","Stok","Pembelian","Inventaris"],
  employee:["Dashboard","Absensi"]
};

const ROLE_LABEL = {
  owner:"Owner",
  manager:"Pengguna / Manager",
  cashier:"Kasir",
  warehouse:"Gudang",
  employee:"Karyawan"
};

const getTheme=()=>localStorage.getItem("kasira_theme")||"light";

function Login(){
  const [session,setSession]=useState(null);
  const [loading,setLoading]=useState(true);
  const [username,setUsername]=useState("");
  const [password,setPassword]=useState("");
  const [show,setShow]=useState(false);
  const [error,setError]=useState("");
  const [theme,setTheme]=useState(getTheme());

  useEffect(()=>{
    document.documentElement.dataset.theme=theme;
    localStorage.setItem("kasira_theme",theme);
  },[theme]);

  useEffect(()=>{
    if(!supabase){setLoading(false);return;}
    let alive=true;
    supabase.auth.getSession().then(({data})=>{
      if(alive)setSession(data.session||null);
    }).finally(()=>{if(alive)setLoading(false)});
    const {data:{subscription}}=supabase.auth.onAuthStateChange((_event,next)=>{
      if(alive)setSession(next||null);
    });
    return()=>{alive=false;subscription.unsubscribe()};
  },[]);

  useEffect(()=>{
    if(!session?.user?.id)return;
    let alive=true;
    (async()=>{
      const {membership,error}=await getMembership(session.user.id);
      if(!alive)return;
      if(error||!membership){
        setError(error?.message||"Akun belum memiliki keanggotaan bisnis KASIRA.");
        await supabase?.auth.signOut();
        return;
      }
      const business=Array.isArray(membership.businesses)?membership.businesses[0]:membership.businesses;
      setSession({...session,kasira:{
        role:membership.role,
        label:ROLE_LABEL[membership.role]||membership.role,
        businessId:membership.business_id,
        businessName:business?.name||"KASIRA"
      }});
      setError("");
    })();
    return()=>{alive=false};
  },[session?.user?.id]);

  useEffect(()=>{
    if(!session?.kasira)return;
    const guard=()=>{
      const allowed=ACCESS[session.kasira.role]||[];
      document.querySelectorAll("aside nav button").forEach(btn=>{
        const name=(btn.innerText||"").replace(/\s+/g," ").trim();
        const ok=allowed.some(x=>name===x||name.startsWith(x+" "));
        btn.style.display=ok?"":"none";
        btn.dataset.kasiraAllowed=ok?"1":"0";
      });
      const active=document.querySelector("aside nav button.active");
      if(active&&active.dataset.kasiraAllowed==="0")
        [...document.querySelectorAll("aside nav button")].find(x=>x.dataset.kasiraAllowed==="1")?.click();
      const av=document.querySelector(".avatar"),un=document.querySelector(".userName");
      if(av)av.textContent=(session.user.user_metadata?.full_name||session.user.email||"U").charAt(0).toUpperCase();
      if(un){
        const name=session.user.user_metadata?.full_name||session.user.email||"Pengguna";
        un.innerHTML="<b>"+name+"</b><small>"+(session.kasira.label||"Pengguna")+" • "+session.kasira.businessName+"</small>";
      }
    };
    const t=setInterval(guard,250);guard();
    return()=>clearInterval(t);
  },[session?.kasira?.role,session?.kasira?.businessName]);

  const login=async e=>{
    e.preventDefault();
    setError("");
    if(!supabaseConfigured){
      setError("KASIRA belum dikonfigurasi ke Supabase. Isi VITE_SUPABASE_URL dan VITE_SUPABASE_ANON_KEY saat build produksi.");
      return;
    }
    if(!username.trim()||!password){setError("Email dan password wajib diisi.");return;}
    setLoading(true);
    const {error}=await supabase.auth.signInWithPassword({email:username.trim(),password});
    if(error)setError(error.message||"Login gagal.");
    setPassword("");
    setLoading(false);
  };

  const logout=async()=>{await supabase?.auth.signOut();setSession(null)};

  if(loading)return <div className="kasiraAuth"><div className="kasiraAuthCard"><b>Memuat keamanan KASIRA…</b><small>Memeriksa sesi pengguna.</small></div></div>;
  if(session?.kasira)return <Session session={session} theme={theme} setTheme={setTheme} logout={logout}/>;

  return <div className="kasiraAuth">
    <div className="kasiraAuthCard">
      <div className="kasiraAuthTop">
        <div className="kasiraLogo">K</div>
        <div><b>KASIRA</b><small>Professional Point of Sale</small></div>
        <button className="kasiraThemeBtn" type="button" onClick={()=>setTheme(theme==="dark"?"light":"dark")}>{theme==="dark"?"☀":"☾"}</button>
      </div>
      <div className="kasiraAuthTitle">Masuk ke KASIRA</div>
      <p className="kasiraAuthDesc">Gunakan akun perusahaan yang telah dibuat oleh Owner/Admin.</p>
      {!supabaseConfigured&&<div className="kasiraAuthError">Mode produksi belum terhubung ke Supabase.</div>}
      <form onSubmit={login}>
        <label>Email<input autoFocus type="email" autoComplete="username" value={username} onChange={e=>{setUsername(e.target.value);setError("")}} placeholder="nama@perusahaan.com"/></label>
        <label>Password<div className="kasiraPass"><input type={show?"text":"password"} autoComplete="current-password" value={password} onChange={e=>{setPassword(e.target.value);setError("")}} placeholder="Password akun"/><button type="button" onClick={()=>setShow(!show)}>{show?"Sembunyikan":"Lihat"}</button></div></label>
        {error&&<div className="kasiraAuthError">{error}</div>}
        <button className="kasiraLoginBtn" disabled={loading||!supabaseConfigured}>{loading?"Memproses…":"Masuk"}</button>
      </form>
      <div className="kasiraRoleInfo"><b>Hak akses otomatis dari database</b><span>Owner • semua modul</span><span>Manager • operasional & laporan</span><span>Kasir • transaksi</span><span>Karyawan • absensi</span></div>
      <small className="kasiraSecurityNote">Kredensial tidak ditanam di APK. Otorisasi bisnis dikendalikan Supabase Auth + RLS.<br/><a href="/privacy-policy.html" target="_blank" rel="noreferrer">Kebijakan Privasi</a> · <a href="/delete-account.html" target="_blank" rel="noreferrer">Penghapusan Akun</a></small>
    </div>
  </div>;
}

function Session({session,theme,setTheme,logout}){
  useEffect(()=>{
    let box;
    const install=()=>{
      const h=document.querySelector(".headerRight");
      if(!h||h.querySelector(".kasiraSessionTools"))return;
      box=document.createElement("div");
      box.className="kasiraSessionTools";
      const th=document.createElement("button");
      th.title="Mode siang/malam";
      th.textContent=theme==="dark"?"☀":"☾";
      th.onclick=()=>setTheme(theme==="dark"?"light":"dark");
      const lo=document.createElement("button");
      lo.title="Keluar";
      lo.textContent="↪";
      lo.onclick=logout;
      box.append(th,lo);h.appendChild(box);
    };
    const t=setInterval(install,250);install();
    return()=>{clearInterval(t);box?.remove()};
  },[theme,logout]);
  return null;
}

const style=document.createElement("style");
style.textContent=`
html[data-theme="dark"] body{background:#0b1220;color:#e8eef8}
html[data-theme="dark"] .header,html[data-theme="dark"] aside,html[data-theme="dark"] .panel,html[data-theme="dark"] .metric,html[data-theme="dark"] .product,html[data-theme="dark"] .modal,html[data-theme="dark"] .outlet{background:#111b2d;color:#e8eef8;border-color:#24324a}
html[data-theme="dark"] aside{border-right-color:#24324a}html[data-theme="dark"] nav button{color:#aab7cb}html[data-theme="dark"] nav button:hover{background:#17243a}html[data-theme="dark"] nav button.active{background:#102d55;color:#5eb0ff}
html[data-theme="dark"] .searchBox,html[data-theme="dark"] .form input,html[data-theme="dark"] .form select,html[data-theme="dark"] .settingsCard input,html[data-theme="dark"] .settingsCard textarea,html[data-theme="dark"] .settingsCard select,html[data-theme="dark"] .tableSearch{background:#0c1626;color:#e8eef8;border-color:#2b3a53}
html[data-theme="dark"] .searchBox input,html[data-theme="dark"] .itemInfo b,html[data-theme="dark"] .rank strong,html[data-theme="dark"] .lowRow strong,html[data-theme="dark"] .panelHead h2,html[data-theme="dark"] .formTitle{color:#e8eef8}
html[data-theme="dark"] .cats button,html[data-theme="dark"] .controls button,html[data-theme="dark"] .iconBtn,html[data-theme="dark"] .ghost,html[data-theme="dark"] .settingAction,html[data-theme="dark"] .cloud{background:#17243a;color:#b8c5d8;border-color:#2b3a53}
html[data-theme="dark"] .tablePanel th{background:#17243a;color:#aab7cb}html[data-theme="dark"] .tablePanel th,html[data-theme="dark"] .tablePanel td,html[data-theme="dark"] .panelHead,html[data-theme="dark"] .item,html[data-theme="dark"] .summary{border-color:#24324a}
html[data-theme="dark"] .modalBackdrop{background:rgba(2,8,18,.78)}html[data-theme="dark"] .scan{background:#111b2d;color:#62b3ff;border-color:#31547c}html[data-theme="dark"] .customerPicker select{background:#111b2d;color:#c9d5e5}
.kasiraAuth{position:fixed;inset:0;z-index:99999;display:grid;place-items:center;padding:20px;background:radial-gradient(circle at 20% 20%,rgba(0,207,255,.12),transparent 35%),linear-gradient(135deg,#06152d,#0a2b55 55%,#062033);font-family:Inter,system-ui,sans-serif}
.kasiraAuthCard{width:min(430px,100%);background:#fff;border-radius:24px;padding:28px;box-shadow:0 30px 90px rgba(0,0,0,.3);color:#172033}html[data-theme="dark"] .kasiraAuthCard{background:#111b2d;color:#e8eef8;border:1px solid #2b3a53}
.kasiraAuthTop{display:flex;align-items:center;gap:11px;margin-bottom:28px}.kasiraAuthTop b{font-size:19px}.kasiraAuthTop small{display:block;color:#8190a5;font-size:10px;margin-top:2px}.kasiraLogo{width:44px;height:44px;border-radius:13px;background:linear-gradient(135deg,#0875ff,#00cfff);color:#fff;display:grid;place-items:center;font-weight:900;font-size:22px}.kasiraThemeBtn{margin-left:auto;width:38px;height:38px;border-radius:10px;background:#f2f6fb;color:#52627a;font-size:18px}.kasiraAuthTitle{font-size:24px;font-weight:800;margin-bottom:6px}.kasiraAuthDesc{font-size:11px;color:#7c879b;margin:0 0 22px}.kasiraAuth form label{display:block;font-size:10px;color:#718096;margin:13px 0}.kasiraAuth input{width:100%;margin-top:6px;padding:12px;border:1px solid #dce4ef;border-radius:10px;outline:0;font-size:12px;background:#fff;color:#172033}.kasiraPass{position:relative}.kasiraPass input{padding-right:75px}.kasiraPass button{position:absolute;right:6px;top:7px;padding:7px 8px;border-radius:7px;background:#f2f6fb;color:#55708f;font-size:9px}.kasiraAuthError{padding:10px;border-radius:9px;background:#fff0f0;color:#b52e36;font-size:10px;margin:8px 0}.kasiraLoginBtn{width:100%;margin-top:8px;padding:13px;border-radius:10px;background:linear-gradient(135deg,#0875ff,#00a7ff);color:#fff;font-weight:800}.kasiraLoginBtn:disabled{opacity:.5;cursor:not-allowed}.kasiraRoleInfo{display:grid;grid-template-columns:1fr 1fr;gap:5px;margin-top:18px;padding:12px;background:#f6f9fc;border-radius:11px;font-size:9px;color:#718096}.kasiraRoleInfo b{grid-column:1/-1;color:#42536c}.kasiraSecurityNote{display:block;text-align:center;color:#98a4b4;font-size:8px;margin-top:14px}.kasiraSessionTools{display:flex;gap:6px;align-items:center}.kasiraSessionTools button{width:34px;height:34px;border-radius:9px;background:#f2f6fb;color:#52627a;font-size:16px}.kasiraSessionTools button:last-child{color:#d6454a}html[data-theme="dark"] .kasiraSessionTools button{background:#17243a;color:#c9d5e5}
@media(max-width:780px){.kasiraSessionTools{display:none}.kasiraAuthCard{padding:23px}.kasiraRoleInfo{grid-template-columns:1fr}}
`;
document.head.appendChild(style);

function mount(){
  const root=document.createElement("div");
  root.id="kasira-auth-root";
  document.body.appendChild(root);
  createRoot(root).render(<Login/>);
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",mount);else mount();
