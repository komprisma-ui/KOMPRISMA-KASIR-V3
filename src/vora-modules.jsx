import React,{useEffect,useState}from"react";
import{Users,Wallet,Receipt,BarChart3,ShieldCheck,LockKeyhole,CheckCircle2,Tag,History}from"lucide-react";
import{Head,PanelHead,Metric,money,num}from"./vora-ui";
import{supabase}from"./supabase";

export function VoraMembers({cloud}){
 const[data,setData]=useState([]),[loading,setLoading]=useState(true);
 useEffect(()=>{(async()=>{if(!supabase||!cloud.businessId){setLoading(false);return}
 const{data:rows,error}=await supabase.from("vora_members").select("id,member_code,display_name,phone,status,joined_at").eq("business_id",cloud.businessId).order("joined_at",{ascending:false});
 if(!error)setData(rows||[]);setLoading(false)})()},[cloud.businessId]);
 return <><Head eyebrow="VORA • MEMBERS" title="Members" desc="Anggota, status, dan identitas bisnis VORA."/><div className="metricGrid"><Metric icon={Users} label="Total Member" value={num(data.length)} note="Cloud VORA"/><Metric icon={CheckCircle2} label="Aktif" value={num(data.filter(x=>x.status==="active").length)} note="Member aktif"/><Metric icon={Users} label="Pending" value={num(data.filter(x=>x.status==="pending").length)} note="Menunggu aktivasi"/><Metric icon={ShieldCheck} label="Security" value="RLS" note="Terproteksi"/></div><section className="panel tablePanel"><PanelHead title="Daftar Member" sub={loading?"Memuat…":data.length+" member"}/>{loading?<div className="empty">Memuat data…</div>:<table><thead><tr><th>Member</th><th>Kode</th><th>Status</th><th>Bergabung</th></tr></thead><tbody>{data.map(x=><tr key={x.id}><td><b>{x.display_name}</b><small>{x.phone||"Tanpa nomor"}</small></td><td>{x.member_code}</td><td><span className={x.status==="active"?"badge":"badge danger"}>{x.status}</span></td><td>{new Date(x.joined_at).toLocaleDateString("id-ID")}</td></tr>)}</tbody></table>}</section></>
}

export function VoraNetwork({cloud}){
 const[data,setData]=useState([]),[loading,setLoading]=useState(true);
 useEffect(()=>{(async()=>{if(!supabase||!cloud.businessId){setLoading(false);return}
 const{data:rows}=await supabase.from("vora_members").select("id,member_code,display_name,status,sponsor_member_id,placement_parent_id,placement_side").eq("business_id",cloud.businessId);
 setData(rows||[]);setLoading(false)})()},[cloud.businessId]);
 return <><Head eyebrow="VORA • NETWORK" title="Network" desc="Sponsor dan placement dengan struktur yang dapat diaudit."/><div className="metricGrid"><Metric icon={Users} label="Member" value={num(data.length)} note="Total jaringan"/><Metric icon={BarChart3} label="Aktif" value={num(data.filter(x=>x.status==="active").length)} note="Member aktif"/><Metric icon={ShieldCheck} label="Komisi" value="Sales" note="Bukan biaya rekrutmen"/><Metric icon={LockKeyhole} label="Security" value="RLS" note="Database policy"/></div><section className="panel tablePanel"><PanelHead title="Struktur Network" sub={loading?"Memuat…":"Sponsor & placement"}/>{loading?<div className="empty">Memuat jaringan…</div>:<table><thead><tr><th>Member</th><th>Sponsor</th><th>Placement</th><th>Status</th></tr></thead><tbody>{data.map(x=>{const s=data.find(y=>y.id===x.sponsor_member_id),p=data.find(y=>y.id===x.placement_parent_id);return <tr key={x.id}><td><b>{x.display_name}</b><small>{x.member_code}</small></td><td>{s?.display_name||"—"}</td><td>{p?p.display_name+" • "+(x.placement_side||"—"):"Root"}</td><td><span className={x.status==="active"?"badge":"badge danger"}>{x.status}</span></td></tr>})}</tbody></table>}</section></>
}

export function VoraOrders({cloud}){
 const[data,setData]=useState([]),[loading,setLoading]=useState(true);
 useEffect(()=>{(async()=>{if(!supabase||!cloud.businessId){setLoading(false);return}
 const{data:rows,error}=await supabase.from("vora_orders").select("id,order_no,status,total,qualified_amount,pv,cv,created_at").eq("business_id",cloud.businessId).order("created_at",{ascending:false}).limit(200);
 if(!error)setData(rows||[]);setLoading(false)})()},[cloud.businessId]);
 return <><Head eyebrow="VORA • COMMERCE" title="Orders" desc="Transaksi nyata sebagai sumber perhitungan reward."/><div className="metricGrid"><Metric icon={Receipt} label="Orders" value={num(data.length)} note="Data terbaru"/><Metric icon={Wallet} label="GMV" value={money(data.reduce((a,x)=>a+Number(x.total||0),0))} note="Nilai order"/><Metric icon={CheckCircle2} label="Qualified" value={money(data.reduce((a,x)=>a+Number(x.qualified_amount||0),0))} note="Basis reward"/><Metric icon={Tag} label="PV" value={num(data.reduce((a,x)=>a+Number(x.pv||0),0))} note="Point volume"/></div><section className="panel tablePanel"><PanelHead title="Transaksi VORA" sub={loading?"Memuat…":data.length+" order"}/>{loading?<div className="empty">Memuat order…</div>:<table><thead><tr><th>Order</th><th>Status</th><th>Total</th><th>Qualified</th><th>PV / CV</th></tr></thead><tbody>{data.map(x=><tr key={x.id}><td><b>{x.order_no}</b><small>{new Date(x.created_at).toLocaleString("id-ID")}</small></td><td><span className="badge">{x.status}</span></td><td>{money(x.total)}</td><td>{money(x.qualified_amount)}</td><td>{num(x.pv)} / {num(x.cv)}</td></tr>)}</tbody></table>}</section></>
}

export function VoraWallet({cloud}){
 const[wallet,setWallet]=useState(null),[tx,setTx]=useState([]),[loading,setLoading]=useState(true);
 useEffect(()=>{(async()=>{if(!supabase||!cloud.businessId||!cloud.userId){setLoading(false);return}
 const{data:member}=await supabase.from("vora_members").select("id").eq("business_id",cloud.businessId).eq("user_id",cloud.userId).maybeSingle();
 if(!member){setLoading(false);return}
 const{data:w}=await supabase.from("vora_wallets").select("available_balance,pending_balance,locked_balance,currency,status").eq("business_id",cloud.businessId).eq("member_id",member.id).maybeSingle();
 const{data:t}=await supabase.from("vora_wallet_transactions").select("id,direction,transaction_type,amount,balance_after,description,created_at").eq("business_id",cloud.businessId).eq("member_id",member.id).order("created_at",{ascending:false}).limit(100);
 setWallet(w||null);setTx(t||[]);setLoading(false)})()},[cloud.businessId,cloud.userId]);
 return <><Head eyebrow="VORA • WALLET" title="Wallet" desc="Saldo dan ledger penghasilan dengan jejak transaksi."/><div className="metricGrid"><Metric icon={Wallet} label="Available" value={money(wallet?.available_balance)} note={wallet?.currency||"IDR"}/><Metric icon={History} label="Pending" value={money(wallet?.pending_balance)} note="Belum tersedia"/><Metric icon={LockKeyhole} label="Locked" value={money(wallet?.locked_balance)} note="Terkunci"/><Metric icon={ShieldCheck} label="Status" value={wallet?.status||"—"} note="Wallet"/></div><section className="panel tablePanel"><PanelHead title="Ledger Wallet" sub={loading?"Memuat…":tx.length+" transaksi"}/>{loading?<div className="empty">Memuat wallet…</div>:<table><thead><tr><th>Waktu</th><th>Jenis</th><th>Arah</th><th>Nominal</th><th>Saldo</th></tr></thead><tbody>{tx.map(x=><tr key={x.id}><td>{new Date(x.created_at).toLocaleString("id-ID")}</td><td>{x.transaction_type}</td><td><span className={x.direction==="credit"?"badge":"badge danger"}>{x.direction}</span></td><td><b>{money(x.amount)}</b></td><td>{money(x.balance_after)}</td></tr>)}</tbody></table>}</section></>
}

export function VoraRewards({cloud}){
 const[data,setData]=useState([]),[ranks,setRanks]=useState([]),[loading,setLoading]=useState(true);
 useEffect(()=>{(async()=>{if(!supabase||!cloud.businessId||!cloud.userId){setLoading(false);return}
 const{data:member}=await supabase.from("vora_members").select("id").eq("business_id",cloud.businessId).eq("user_id",cloud.userId).maybeSingle();
 if(!member){setLoading(false);return}
 const{data:p}=await supabase.from("vora_member_periods").select("period_start,period_end,personal_pv,personal_cv,group_pv,group_cv,direct_active,status,rank_id").eq("business_id",cloud.businessId).eq("member_id",member.id).order("period_start",{ascending:false}).limit(24);
 const{data:r}=await supabase.from("vora_rank_rules").select("id,name,rank_order").eq("business_id",cloud.businessId).eq("active",true).order("rank_order");
 setData(p||[]);setRanks(r||[]);setLoading(false)})()},[cloud.businessId,cloud.userId]);
 return <><Head eyebrow="VORA • REWARDS" title="Rewards & Rank" desc="PV, CV, periode kinerja, dan level pertumbuhan anggota."/><div className="metricGrid"><Metric icon={BarChart3} label="Periode" value={num(data.length)} note="Riwayat"/><Metric icon={Tag} label="Personal PV" value={num(data[0]?.personal_pv)} note="Terbaru"/><Metric icon={Users} label="Group PV" value={num(data[0]?.group_pv)} note="Terbaru"/><Metric icon={BarChart3} label="Rank" value={ranks.find(x=>x.id===data[0]?.rank_id)?.name||"Belum ditetapkan"} note="Terbaru"/></div><section className="panel tablePanel"><PanelHead title="Riwayat Kinerja" sub={loading?"Memuat…":data.length+" periode"}/>{loading?<div className="empty">Memuat rewards…</div>:<table><thead><tr><th>Periode</th><th>Personal PV</th><th>Group PV</th><th>Direct Active</th><th>Rank</th></tr></thead><tbody>{data.map(x=><tr key={x.period_start+"-"+x.period_end}><td>{x.period_start} — {x.period_end}</td><td>{num(x.personal_pv)}</td><td>{num(x.group_pv)}</td><td>{num(x.direct_active)}</td><td>{ranks.find(r=>r.id===x.rank_id)?.name||"—"}</td></tr>)}</tbody></table>}</section></>
}
