import { createRoot } from "react-dom/client";
import React, { useEffect, useState } from "react";

const USERS = [
  { username:"owner", password:"owner123", name:"Owner", role:"owner", label:"Owner" },
  { username:"pengguna", password:"pengguna123", name:"Pengguna", role:"manager", label:"Pengguna / Manager" },
  { username:"kasir", password:"kasir123", name:"Kasir", role:"cashier", label:"Kasir" },
  { username:"karyawan", password:"karyawan123", name:"Karyawan", role:"employee", label:"Karyawan" }
];

const ACCESS = {
  owner:["Dashboard","Kasir","Produk","Stok","Pembelian","Pelanggan","Transaksi","Laporan","Akuntansi","Aset","Inventaris","Karyawan","Absensi","Kas","Retur","Pengaturan"],
  manager:["Dashboard","Kasir","Produk","Stok","Pembelian","Pelanggan","Transaksi","Laporan","Akuntansi","Aset","Inventaris","Karyawan","Absensi","Kas","Retur"],
  cashier:["Dashboard","Kasir","Pelanggan","Transaksi","Retur"],
  employee:["Dashboard","Absensi"]
};

const getSession=()=>{try{return JSON.parse(localStorage.getItem("kasira_session")||"null")}catch{return null}};
const saveSession=v=>v?localStorage.setItem("kasira_session",JSON.stringify(v)):localStorage.removeItem("kasira_session");

function Login(){
 const [session,setSession]=useState(getSession()),[username,setUsername]=useState(""),[password,setPassword]=useState(""),[show,setShow]=useState(false),[error,setError]=useState("");
 const [theme,setTheme]=useState(localStorage.getItem("kasira_theme")||"light");
 useEffect(()=>{document.documentElement.dataset.theme=theme;localStorage.setItem("kasira_theme",theme)},[theme]);
 useEffect(()=>{
   const guard=()=>{
    const s=getSession(); if(!s)return;
    const allowed=ACCESS[s.role]||[];
    document.querySelectorAll("aside nav button").forEach(btn=>{
      const name=(btn.innerText||"").replace(/\s+/g," ").trim();
      const ok=allowed.some(x=>name===x||name.startsWith(x+" "));
      btn.style.display=ok?"":"none"; btn.dataset.kasiraAllowed=ok?"1":"0";
    });
    const active=document.querySelector("aside nav button.active");
    if(active&&active.dataset.kasiraAllowed==="0") [...document.querySelectorAll("aside nav button")].find(x=>x.dataset.kasiraAllowed==="1")?.click();
    const av=document.querySelector(".avatar"),un=document.querySelector(".userName");
    if(av)av.textContent=(s.name||"U").charAt(0).toUpperCase();
    if(un)un.innerHTML="<b>"+s.name+"</b><small>"+s.label+" • KASIRA</small>";
   };
   const t=setInterval(guard,250);guard();return()=>clearInterval(t);
 },[session]);
 if(session)return <Session session={session} theme={theme} setTheme={setTheme} logout={()=>{saveSession(null);setSession(null)}}/>;
 const login=e=>{
  e.preventDefault();
  const u=USERS.find(x=>x.username.toLowerCase()===username.trim().toLowerCase()&&x.password===password);
  if(!u){setError("Username atau password salah.");return}
  const s={username:u.username,name:u.name,role:u.role,label:u.label,loginAt:new Date().toISOString()};
  saveSession(s);setSession(s);setPassword("");setError("");
 };
 return <div className="kasiraAuth"><div className="kasiraAuthCard">
  <div className="kasiraAuthTop"><div className="kasiraLogo">K</div><div><b>KASIRA</b><small>Professional Point of Sale</small></div><button className="kasiraThemeBtn" onClick={()=>setTheme(theme==="dark"?"light":"dark")}>{theme==="dark"?"☀":"☾"}</button></div>
  <div className="kasiraAuthTitle">Masuk ke KASIRA</div><p className="kasiraAuthDesc">Gunakan akun sesuai tugas dan hak akses Anda.</p>
  <form onSubmit={login}>
   <label>Username<input autoFocus value={username} onChange={e=>{setUsername(e.target.value);setError("")}} placeholder="Masukkan username"/></label>
   <label>Password><div className="kasiraPass"><input type={show?"text":"password"} value={password} onChange={e=>{setPassword(e.target.value);setError("")}} placeholder="Masukkan password"/><button type="button" onClick={()=>setShow(!show)}>{show?"Sembunyikan":"Lihat"}</button></div></label>
   {error&&<div className="kasiraAuthError">{error}</div>}<button className="kasiraLoginBtn">Masuk</button>
  </form>
  <div className="kasiraRoleInfo"><b>Akun pengujian</b><span>owner / owner123</span><span>pengguna / pengguna123</span><span>kasir / kasir123</span><span>karyawan / karyawan123</span></div>
  <small className="kasiraSecurityNote">Login lokal untuk pengujian. Produksi dikunci dengan Supabase Auth + RLS.</small>
 </div></div>
}

function Session({session,theme,setTheme,logout}){
 useEffect(()=>{
  const install=()=>{
   const h=document.querySelector(".headerRight");if(!h||h.querySelector(".kasiraSessionTools"))return;
   const box=document.createElement("div");box.className="kasiraSessionTools";
   const th=document.createElement("button");th.title="Mode siang/malam";th.textContent=theme==="dark"?"☀":"☾";th.onclick=()=>setTheme(theme==="dark"?"light":"dark");
   const lo=document.createElement("button");lo.title="Keluar";lo.textContent="↪";lo.onclick=logout;box.append(th,lo);h.appendChild(box);
  };const t=setInterval(install,250);install();return()=>clearInterval(t);
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
.kasiraAuthTop{display:flex;align-items:center;gap:11px;margin-bottom:28px}.kasiraAuthTop b{font-size:19px}.kasiraAuthTop small{display:block;color:#8190a5;font-size:10px;margin-top:2px}.kasiraLogo{width:44px;height:44px;border-radius:13px;background:linear-gradient(135deg,#0875ff,#00cfff);color:#fff;display:grid;place-items:center;font-weight:900;font-size:22px}.kasiraThemeBtn{margin-left:auto;width:38px;height:38px;border-radius:10px;background:#f2f6fb;color:#52627a;font-size:18px}.kasiraAuthTitle{font-size:24px;font-weight:800;margin-bottom:6px}.kasiraAuthDesc{font-size:11px;color:#7c879b;margin:0 0 22px}.kasiraAuth form label{display:block;font-size:10px;color:#718096;margin:13px 0}.kasiraAuth input{width:100%;margin-top:6px;padding:12px;border:1px solid #dce4ef;border-radius:10px;outline:0;font-size:12px;background:#fff;color:#172033}.kasiraPass{position:relative}.kasiraPass input{padding-right:75px}.kasiraPass button{position:absolute;right:6px;top:7px;padding:7px 8px;border-radius:7px;background:#f2f6fb;color:#55708f;font-size:9px}.kasiraAuthError{padding:10px;border-radius:9px;background:#fff0f0;color:#d53f45;font-size:10px;margin:8px 0}.kasiraLoginBtn{width:100%;margin-top:8px;padding:13px;border-radius:10px;background:linear-gradient(135deg,#0875ff,#00a7ff);color:#fff;font-weight:800}.kasiraRoleInfo{display:grid;grid-template-columns:1fr 1fr;gap:5px;margin-top:18px;padding:12px;background:#f6f9fc;border-radius:11px;font-size:9px;color:#718096}.kasiraRoleInfo b{grid-column:1/-1;color:#42536c}.kasiraSecurityNote{display:block;text-align:center;color:#98a4b4;font-size:8px;margin-top:14px}.kasiraSessionTools{display:flex;gap:6px;align-items:center}.kasiraSessionTools button{width:34px;height:34px;border-radius:9px;background:#f2f6fb;color:#52627a;font-size:16px}.kasiraSessionTools button:last-child{color:#d6454a}html[data-theme="dark"] .kasiraSessionTools button{background:#17243a;color:#c9d5e5}
@media(max-width:780px){.kasiraSessionTools{display:none}.kasiraAuthCard{padding:23px}.kasiraRoleInfo{grid-template-columns:1fr}}
`;
document.head.appendChild(style);

function mount(){const root=document.createElement("div");root.id="kasira-auth-root";document.body.appendChild(root);createRoot(root).render(<Login/>);}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",mount);else mount();
