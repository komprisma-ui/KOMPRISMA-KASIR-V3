import React,{useEffect,useMemo,useState}from"react";
import{createRoot}from"react-dom/client";
import{ShoppingCart,Package,LayoutDashboard,Receipt,Plus,Minus,Trash2,Search,Wallet,Menu,X,BarChart3,Users,Settings,Boxes,Truck,ChevronRight,ArrowUpRight,Bell,ScanLine,Percent,CreditCard,MoreHorizontal}from"lucide-react";
import"./style.css";

const seed=[
{id:1,name:"Air Mineral 600ml",sku:"AM600",category:"Minuman",price:4000,stock:40},
{id:2,name:"Kopi Kapal Api",sku:"KOPI01",category:"Minuman",price:12000,stock:28},
{id:3,name:"Mie Instan",sku:"MIE01",category:"Makanan",price:3500,stock:50},
{id:4,name:"Gula 1 Kg",sku:"GUL001",category:"Sembako",price:17500,stock:25},
{id:5,name:"Sabun Mandi",sku:"SBN01",category:"Kebutuhan",price:5000,stock:8},
{id:6,name:"Roti",sku:"ROT01",category:"Makanan",price:7000,stock:20},
{id:7,name:"Susu UHT",sku:"UHT01",category:"Minuman",price:6000,stock:12},
{id:8,name:"Indomie Goreng",sku:"IND01",category:"Makanan",price:3000,stock:7}
];
const money=n=>new Intl.NumberFormat("id-ID",{style:"currency",currency:"IDR",maximumFractionDigits:0}).format(n);
const load=(k,d)=>{try{return JSON.parse(localStorage.getItem(k))??d}catch{return d}};
const nav=[["Dashboard",LayoutDashboard],["Kasir",ShoppingCart],["Produk",Package],["Stok",Boxes],["Pembelian",Truck],["Pelanggan",Users],["Transaksi",Receipt],["Laporan",BarChart3],["Pengaturan",Settings]];

function App(){
 const[page,setPage]=useState("Dashboard"),[products,setProducts]=useState(()=>load("kasira_products",seed)),[sales,setSales]=useState(()=>load("kasira_sales",[])),[cart,setCart]=useState([]),[q,setQ]=useState(""),[cat,setCat]=useState("Semua"),[mobile,setMobile]=useState(false),[modal,setModal]=useState(false);
 useEffect(()=>localStorage.setItem("kasira_products",JSON.stringify(products)),[products]);
 useEffect(()=>localStorage.setItem("kasira_sales",JSON.stringify(sales)),[sales]);
 const cats=["Semua",...new Set(products.map(p=>p.category))];
 const filtered=useMemo(()=>products.filter(p=>(cat==="Semua"||p.category===cat)&&(p.name.toLowerCase().includes(q.toLowerCase())||p.sku.toLowerCase().includes(q.toLowerCase()))),[products,q,cat]);
 const total=cart.reduce((s,i)=>s+i.price*i.qty,0);
 const today=sales.filter(s=>new Date(s.at).toDateString()===new Date().toDateString());
 const omzet=today.reduce((a,s)=>a+s.total,0);
 const add=p=>setCart(c=>{const x=c.find(i=>i.id===p.id);return x?c.map(i=>i.id===p.id?{...i,qty:Math.min(i.qty+1,p.stock)}:i):[...c,{...p,qty:1}]});
 const change=(id,d)=>setCart(c=>c.map(i=>i.id===id?{...i,qty:i.qty+d}:i).filter(i=>i.qty>0));
 const pay=()=>{if(!cart.length)return;setSales(s=>[{id:Date.now(),at:new Date().toISOString(),items:cart,total,payment:"Tunai"},...s]);setProducts(ps=>ps.map(p=>{const i=cart.find(x=>x.id===p.id);return i?{...p,stock:p.stock-i.qty}:p}));setCart([]);setModal(false)};
 return <div className="app">
  <header className="header">
   <div className="brand"><div className="brandIcon"><img src="/kasira-icon.svg"/></div><div><b>KASIRA</b><small>Point of Sale & Business Management</small></div></div>
   <div className="headerRight"><span className="status"><i/> Online</span><button className="iconBtn"><Bell size={19}/></button><div className="avatar">A</div><div className="userName"><b>Admin</b><small>Owner</small></div></div>
   <button className="menuBtn" onClick={()=>setMobile(!mobile)}>{mobile?<X/>:<Menu/>}</button>
  </header>
  <aside className={mobile?"open":""}>
   <div><div className="outlet"><div className="outletMark">K</div><div><b>Toko Utama</b><small>Outlet aktif</small></div><ChevronRight size={16}/></div>
   <nav>{nav.map(([n,I])=><button className={page===n?"active":""} onClick={()=>{setPage(n);setMobile(false)}} key={n}><I size={18}/><span>{n}</span>{n==="Transaksi"&&sales.length>0?<em>{Math.min(sales.length,99)}</em>:null}</button>)}</nav></div>
   <div className="sideFoot"><div className="cloud"><Wallet size={16}/><span><b>Data aman</b><small>Tersimpan di perangkat</small></span><i/></div><small>v0.2 • KASIRA</small></div>
  </aside>
  <main>
   {page==="Dashboard"&&<Dashboard omzet={omzet} sales={sales} products={products} setPage={setPage}/>}
   {page==="Kasir"&&<POS products={products} filtered={filtered} cats={cats} cat={cat} setCat={setCat} q={q} setQ={setQ} cart={cart} total={total} add={add} change={change} setCart={setCart} setModal={setModal}/>}
   {page==="Produk"&&<Products products={products} setProducts={setProducts}/>}
   {page==="Transaksi"&&<Transactions sales={sales}/>}
   {["Stok","Pembelian","Pelanggan","Laporan","Pengaturan"].includes(page)&&<Coming page={page}/>}
  </main>
  {modal&&<Payment total={total} pay={pay} close={()=>setModal(false)}/>}
 </div>
}

function PageHead({eyebrow,title,desc,action}){return <div className="pageHead"><div><span className="eyebrow">{eyebrow}</span><h1>{title}</h1><p>{desc}</p></div>{action}</div>}

function Dashboard({omzet,sales,products,setPage}){
 const low=products.filter(p=>p.stock<=10);
 return <><PageHead eyebrow="RINGKASAN BISNIS" title="Selamat datang kembali, Admin" desc="Pantau operasional toko dalam satu layar." action={<button className="primary" onClick={()=>setPage("Kasir")}><ShoppingCart size={17}/> Buka Kasir</button>}/>
 <div className="hero"><div><span>Omzet Hari Ini</span><strong>{money(omzet)}</strong><small><ArrowUpRight size={14}/> 12,4% dari kemarin</small></div><div className="heroChart"><span/><span/><span/><span/><span/><span/><span/></div></div>
 <div className="metricGrid"><Metric icon={Receipt} label="Transaksi" value={sales.length} note="Total tercatat"/><Metric icon={Package} label="Produk Aktif" value={products.length} note="Dalam katalog"/><Metric icon={Users} label="Pelanggan" value="52" note="Member terdaftar"/><Metric icon={Boxes} label="Stok Menipis" value={low.length} note="Perlu diperiksa" danger/></div>
 <div className="dashboardGrid"><section className="panel chartPanel"><div className="panelHead"><div><h2>Penjualan 7 Hari</h2><small>Performa omzet harian</small></div><button className="ghost">Minggu <ChevronRight size={15}/></button></div><div className="bars">{[42,58,47,76,62,91,72].map((h,i)=><div key={i}><span style={{height:h+"%"}}/><small>{["Sen","Sel","Rab","Kam","Jum","Sab","Min"][i]}</small></div>)}</div></section>
 <section className="panel"><div className="panelHead"><div><h2>Produk Terlaris</h2><small>7 hari terakhir</small></div><button className="linkBtn">Lihat semua</button></div>{products.slice(0,5).map((p,i)=><div className="rank" key={p.id}><b>{String(i+1).padStart(2,"0")}</b><span className="thumb">{p.name[0]}</span><div><strong>{p.name}</strong><small>{p.category}</small></div><em>{(20-i*2)} pcs</em></div>)}</section>
 <section className="panel lowPanel"><div className="panelHead"><div><h2>Stok Menipis</h2><small>Butuh perhatian</small></div><button className="linkBtn" onClick={()=>setPage("Stok")}>Kelola</button></div>{low.length?low.slice(0,4).map(p=><div className="lowRow" key={p.id}><span className="thumb danger">{p.name[0]}</span><div><strong>{p.name}</strong><small>SKU {p.sku}</small></div><b>{p.stock} pcs</b></div>):<div className="empty">Semua stok aman.</div>}</section>
 </div></>
}
function Metric({icon:I,label,value,note,danger}){return <div className="metric"><div className={danger?"metricIcon danger":"metricIcon"}><I size={18}/></div><div><span>{label}</span><strong>{value}</strong><small>{note}</small></div><MoreHorizontal size={17}/></div>}

function POS({products,filtered,cats,cat,setCat,q,setQ,cart,total,add,change,setCart,setModal}){
 return <><PageHead eyebrow="POINT OF SALE" title="Kasir" desc="Pilih produk, atur keranjang, lalu selesaikan pembayaran." action={<button className="scan"><ScanLine size={18}/> Scan Barcode</button>}/>
 <div className="pos"><section className="catalog panel"><div className="searchBox"><Search size={18}/><input placeholder="Cari produk atau scan SKU..." value={q} onChange={e=>setQ(e.target.value)}/><kbd>⌘ K</kbd></div><div className="cats">{cats.map(c=><button className={cat===c?"sel":""} onClick={()=>setCat(c)} key={c}>{c}</button>)}</div><div className="grid">{filtered.map(p=><button className="product" key={p.id} onClick={()=>add(p)} disabled={!p.stock}><span className="productVisual">{p.name[0]}</span><b>{p.name}</b><small>{p.sku}</small><strong>{money(p.price)}</strong><em className={p.stock<=10?"stock dangerText":"stock"}>{p.stock} stok</em></button>)}</div></section>
 <section className="cart panel"><div className="cartHead"><div><span className="eyebrow">TRANSAKSI BARU</span><h2>Keranjang</h2></div><button className="ghost" onClick={()=>setCart([])}>Kosongkan</button></div><div className="items">{cart.length?cart.map(i=><div className="item" key={i.id}><span className="productVisual small">{i.name[0]}</span><div className="itemInfo"><b>{i.name}</b><small>{money(i.price)} × {i.qty}</small></div><div className="controls"><button onClick={()=>change(i.id,-1)}><Minus size={14}/></button><b>{i.qty}</b><button onClick={()=>change(i.id,1)}><Plus size={14}/></button><button className="delete" onClick={()=>setCart(c=>c.filter(x=>x.id!==i.id))}><Trash2 size={15}/></button></div></div>):<div className="empty cartEmpty"><ShoppingCart size={30}/><b>Keranjang masih kosong</b><span>Pilih produk untuk memulai transaksi.</span></div>}</div><div className="summary"><div><span>Subtotal</span><b>{money(total)}</b></div><div><span>Diskon</span><b>Rp 0</b></div><div className="grand"><span>Total</span><strong>{money(total)}</strong></div><button className="pay" disabled={!cart.length} onClick={()=>setModal(true)}>Bayar Sekarang <ChevronRight size={18}/></button></div></section></div></>
}
function Payment({total,pay,close}){return <div className="modalBackdrop"><div className="modal"><button className="modalClose" onClick={close}><X/></button><span className="eyebrow">PEMBAYARAN</span><h2>Konfirmasi Pembayaran</h2><div className="paymentTotal">{money(total)}</div><div className="payMethods"><button className="selected"><Wallet/> Tunai</button><button><CreditCard/> Kartu</button><button><Percent/> QRIS</button><button><ArrowUpRight/> Transfer</button></div><label>Nominal diterima<input autoFocus type="number" defaultValue={total}/></label><div className="change">Kembalian <b>{money(0)}</b></div><button className="pay" onClick={pay}>Selesaikan Transaksi</button></div></div>}

function Products({products,setProducts}){const[f,setF]=useState({name:"",sku:"",category:"Umum",price:"",stock:""});const add=()=>{if(!f.name||!f.price)return;setProducts(p=>[...p,{...f,id:Date.now(),price:+f.price,stock:+f.stock||0}]);setF({name:"",sku:"",category:"Umum",price:"",stock:""})};return <><PageHead eyebrow="MASTER DATA" title="Produk" desc="Kelola katalog, harga, SKU, dan stok produk." action={<button className="primary" onClick={add}><Plus size={17}/> Tambah Produk</button>}/><div className="panel form">{Object.keys(f).map(k=><label key={k}><span>{k}</span><input placeholder={k==="name"?"Nama produk":k} value={f[k]} onChange={e=>setF({...f,[k]:e.target.value})}/></label>)}<button className="primary" onClick={add}><Plus size={17}/> Simpan</button></div><div className="panel tablePanel"><div className="panelHead"><div><h2>Daftar Produk</h2><small>{products.length} produk aktif</small></div><Search size={18}/></div><table><thead><tr><th>Produk</th><th>SKU</th><th>Kategori</th><th>Harga</th><th>Stok</th></tr></thead><tbody>{products.map(p=><tr key={p.id}><td><span className="tableProduct"><span className="productVisual small">{p.name[0]}</span><b>{p.name}</b></span></td><td>{p.sku}</td><td>{p.category}</td><td>{money(p.price)}</td><td><span className={p.stock<=10?"badge danger":"badge"}>{p.stock}</span></td></tr>)}</tbody></table></div></>}
function Transactions({sales}){return <><PageHead eyebrow="RIWAYAT" title="Transaksi" desc="Pantau seluruh transaksi yang tersimpan."/><div className="panel tablePanel"><table><thead><tr><th>Nomor</th><th>Waktu</th><th>Item</th><th>Metode</th><th>Total</th></tr></thead><tbody>{sales.map(s=><tr key={s.id}><td>TRX-{String(s.id).slice(-6)}</td><td>{new Date(s.at).toLocaleString("id-ID")}</td><td>{s.items.reduce((a,i)=>a+i.qty,0)} item</td><td><span className="badge">{s.payment||"Tunai"}</span></td><td><b>{money(s.total)}</b></td></tr>)}</tbody></table>{!sales.length&&<div className="empty">Belum ada transaksi.</div>}</div></>}
function Coming({page}){return <><PageHead eyebrow="KASIRA MODULE" title={page} desc="Modul sedang disiapkan dalam arsitektur KASIRA."/><div className="coming panel"><div className="comingIcon"><Settings/></div><h2>{page} segera hadir</h2><p>Fondasi antarmuka sudah disiapkan. Modul ini akan terhubung ke database, role pengguna, dan sinkronisasi cloud pada fase berikutnya.</p></div></>}

createRoot(document.getElementById("root")).render(<App/>);
