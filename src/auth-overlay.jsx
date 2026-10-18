import { createRoot } from "react-dom/client";
import React, { useEffect, useRef, useState } from "react";
import { getMembership, supabase, supabaseConfigured } from "./supabase";

const ACCESS = {
  owner: ["Dashboard","Kasir","Produk","Stok","Pembelian","Pelanggan","Transaksi","Laporan","Akuntansi","Aset","Inventaris","Karyawan","Absensi","Kas","Retur","Pengaturan"],
  manager: ["Dashboard","Kasir","Produk","Stok","Pembelian","Pelanggan","Transaksi","Laporan","Akuntansi","Aset","Inventaris","Karyawan","Absensi","Kas","Retur"],
  cashier: ["Dashboard","Kasir","Pelanggan","Transaksi","Retur"],
  warehouse: ["Dashboard","Produk","Stok","Pembelian","Inventaris"],
  employee: ["Dashboard","Absensi"]
};

const ROLE_LABEL = {
  owner: "Owner",
  manager: "Manager",
  cashier: "Kasir",
  warehouse: "Gudang",
  employee: "Karyawan"
};

const PENDING_KEY = "kasira_pending_onboarding_v1";
const KASIRA_PUBLIC_URL = import.meta.env.VITE_PUBLIC_APP_URL || "https://kasira-seven.vercel.app";

function readPendingOnboarding() {
  try {
    const raw = localStorage.getItem(PENDING_KEY);
    if (!raw) return null;
    const value = JSON.parse(raw);
    if (!value || Date.now() - Number(value.savedAt || 0) > 14 * 24 * 60 * 60 * 1000) {
      localStorage.removeItem(PENDING_KEY);
      return null;
    }
    return value;
  } catch {
    return null;
  }
}

function writePendingOnboarding(value) {
  try {
    localStorage.setItem(PENDING_KEY, JSON.stringify({ ...value, savedAt: Date.now() }));
    return true;
  } catch {
    return false;
  }
}

function clearPendingOnboarding() {
  try { localStorage.removeItem(PENDING_KEY); } catch { /* Storage can be unavailable in private mode. */ }
}

function friendlyError(error) {
  const message = String(error?.message || error || "Terjadi kesalahan yang tidak diketahui.");
  const lower = message.toLowerCase();
  if (lower.includes("invalid login credentials")) return "Email atau password tidak sesuai.";
  if (lower.includes("email not confirmed")) return "Email belum diverifikasi. Periksa kotak masuk atau folder spam.";
  if (lower.includes("user already registered")) return "Akun sudah terdaftar. Silakan gunakan tab Masuk.";
  if (lower.includes("password should be at least")) return "Password terlalu pendek. Gunakan minimal 10 karakter.";
  if (lower.includes("rate limit")) return "Terlalu banyak percobaan. Tunggu beberapa saat lalu coba lagi.";
  if (lower.includes("kode undangan") || lower.includes("undangan")) return message;
  if (lower.includes("verifikasi email")) return message;
  if (lower.includes("usaha lain") || lower.includes("sudah terhubung")) return message;
  return message;
}

function Login() {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);
  const [mode, setMode] = useState("login");
  const [signupKind, setSignupKind] = useState("owner");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [businessName, setBusinessName] = useState("");
  const [signupInviteToken, setSignupInviteToken] = useState("");
  const [loginInviteToken, setLoginInviteToken] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [theme, setTheme] = useState(() => {
    try { return localStorage.getItem("kasira_theme") || "light"; } catch { return "light"; }
  });
  const authFlowInProgressRef = useRef(false);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try { localStorage.setItem("kasira_theme", theme); } catch { /* Theme is optional. */ }
  }, [theme]);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }
    let alive = true;
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, next) => {
      if (event === "PASSWORD_RECOVERY" && alive) {
        setMode("reset-password");
        setError("");
        setNotice("");
        setLoading(false);
      }
      if (authFlowInProgressRef.current && next) return;
      if (alive) setSession(next || null);
    });
    supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (!alive) return;
      if (sessionError) setError(friendlyError(sessionError));
      setSession(data?.session || null);
      if (!data?.session || sessionError) setLoading(false);
    }).catch((sessionError) => {
      if (alive) {
        setError(friendlyError(sessionError));
        setLoading(false);
      }
    });
    return () => {
      alive = false;
      subscription.unsubscribe();
    };
  }, []);

  useEffect(() => {
    if (!supabase || !session?.user?.id) return;
    let alive = true;
    const activeUserId = session.user.id;
    setLoading(true);

    (async () => {
      let pending = readPendingOnboarding();
      if (pending?.userId && pending.userId !== activeUserId) {
        clearPendingOnboarding();
        pending = null;
      }

      // Owner onboarding can be recovered after email confirmation opens on another browser tab/device.
      if (!pending && session.user.user_metadata?.kasira_signup_intent === "owner" &&
          String(session.user.user_metadata?.kasira_business_name || "").trim()) {
        pending = {
          kind: "owner",
          userId: activeUserId,
          businessName: String(session.user.user_metadata.kasira_business_name).trim()
        };
      }

      if (pending && pending.userId === activeUserId) {
        const result = pending.kind === "owner"
          ? await supabase.rpc("kasira_complete_owner_signup", { p_business_name: pending.businessName })
          : pending.kind === "invite"
            ? await supabase.rpc("kasira_accept_invitation", { p_token: pending.token })
            : { error: new Error("Jenis pendaftaran tidak dikenali.") };

        if (result.error) throw new Error(friendlyError(result.error));
        clearPendingOnboarding();

        if (pending.kind === "owner") {
          try {
            await supabase.auth.updateUser({
              data: { kasira_signup_intent: null, kasira_business_name: null }
            });
          } catch { /* Tenant creation is already committed; metadata cleanup is best-effort. */ }
        }
      }

      const { membership, error: membershipError } = await getMembership(activeUserId);
      if (membershipError || !membership) {
        throw new Error(
          membershipError
            ? friendlyError(membershipError)
            : "Akun belum terhubung ke usaha KASIRA. Masuk kembali dengan kode undangan yang benar atau minta undangan dari Owner."
        );
      }

      const business = Array.isArray(membership.businesses) ? membership.businesses[0] : membership.businesses;
      if (alive) {
        setSession((current) => current?.user?.id === activeUserId ? {
          ...current,
          kasira: {
            role: membership.role,
            label: ROLE_LABEL[membership.role] || membership.role,
            businessId: membership.business_id,
            businessName: business?.name || "KASIRA"
          }
        } : current);
        setError("");
        setLoading(false);
      }
    })().catch(async (membershipError) => {
      const pending = readPendingOnboarding();
      if (pending?.userId === activeUserId) clearPendingOnboarding();
      if (alive) {
        setError(friendlyError(membershipError));
        try { await supabase.auth.signOut(); } catch { /* A stale session should not block the login form. */ }
        if (alive) {
          setSession(null);
          setLoading(false);
        }
      }
    });

    return () => { alive = false; };
  }, [session?.user?.id]);

  const submit = async (event) => {
    event.preventDefault();
    setError("");
    setNotice("");

    if (!supabaseConfigured) {
      setError("KASIRA belum terhubung ke layanan autentikasi. Periksa konfigurasi Supabase pada deployment.");
      return;
    }
    const normalizedEmail = email.trim().toLowerCase();
    if (!normalizedEmail || (mode !== "forgot" && !password)) {
      setError(mode === "forgot" ? "Email wajib diisi." : "Email dan password wajib diisi.");
      return;
    }

    setLoading(true);

    if (mode === "forgot") {
      try {
        const { error: recoveryError } = await supabase.auth.resetPasswordForEmail(
          normalizedEmail,
          { redirectTo: KASIRA_PUBLIC_URL }
        );
        if (recoveryError) {
          setError(friendlyError(recoveryError));
        } else {
          setNotice("Jika email tersebut terdaftar, tautan pemulihan telah dikirim. Periksa kotak masuk dan folder spam.");
          setMode("forgot");
        }
      } catch (recoveryError) {
        setError(friendlyError(recoveryError));
      } finally {
        setLoading(false);
      }
      return;
    }

    if (mode === "login") {
      const token = loginInviteToken.trim();
      authFlowInProgressRef.current = Boolean(token);
      try {
        const loginResult = await Promise.race([
          supabase.auth.signInWithPassword({ email: normalizedEmail, password }),
          new Promise((_, reject) => setTimeout(() => reject(new Error("Koneksi ke layanan login terlalu lama. Periksa internet lalu coba lagi.")), 15000))
        ]);
        const { data, error: loginError } = loginResult;
        if (loginError) {
          setError(friendlyError(loginError));
          setPassword("");
          setLoading(false);
          authFlowInProgressRef.current = false;
          return;
        }

        const signedInSession = data?.session || null;
        const userId = data?.user?.id || signedInSession?.user?.id;
        if (token && userId) {
          const stored = writePendingOnboarding({ kind: "invite", userId, token });
          if (!stored) {
            setError("Perangkat tidak mengizinkan penyimpanan kode undangan. Aktifkan penyimpanan browser atau coba lewat browser biasa.");
            try { await supabase.auth.signOut(); } catch { /* Ignore sign-out errors. */ }
            setLoading(false);
            authFlowInProgressRef.current = false;
            return;
          }
        }
        setPassword("");
        if (signedInSession) setSession(signedInSession);
        // The session effect performs invitation acceptance and waits for membership before showing the app.
        if (!signedInSession) setLoading(false);
      } catch (loginFailure) {
        setError(friendlyError(loginFailure));
        setPassword("");
        setLoading(false);
      } finally {
        authFlowInProgressRef.current = false;
      }
      return;
    }

    if (fullName.trim().length < 2) {
      setError("Nama lengkap minimal 2 karakter.");
      setLoading(false);
      return;
    }
    if (password.length < 10) {
      setError("Buat password minimal 10 karakter.");
      setLoading(false);
      return;
    }
    if (signupKind === "owner" && businessName.trim().length < 2) {
      setError("Nama usaha minimal 2 karakter.");
      setLoading(false);
      return;
    }
    if (signupKind === "invite" && signupInviteToken.trim().length < 32) {
      setError("Masukkan kode undangan yang diberikan Owner atau Manager.");
      setLoading(false);
      return;
    }

    authFlowInProgressRef.current = true;
    const { data, error: signupError } = await supabase.auth.signUp({
      email: normalizedEmail,
      password,
      options: {
        data: {
          full_name: fullName.trim(),
          kasira_signup_intent: signupKind,
          kasira_business_name: signupKind === "owner" ? businessName.trim() : ""
        },
        emailRedirectTo: KASIRA_PUBLIC_URL
      }
    });

    if (signupError) {
      authFlowInProgressRef.current = false;
      setError(friendlyError(signupError));
      setPassword("");
      setLoading(false);
      return;
    }

    // Supabase may intentionally return an obfuscated user for an already-registered email.
    if (!data?.user?.id || (Array.isArray(data.user.identities) && data.user.identities.length === 0)) {
      authFlowInProgressRef.current = false;
      setPassword("");
      setNotice("Jika email ini belum terdaftar, periksa kotak masuk atau folder spam untuk verifikasi. Jika akun sudah ada, gunakan tab Masuk.");
      setLoading(false);
      return;
    }

    const saved = writePendingOnboarding({
      kind: signupKind,
      userId: data.user.id,
      businessName: signupKind === "owner" ? businessName.trim() : "",
      token: signupKind === "invite" ? signupInviteToken.trim() : ""
    });

    authFlowInProgressRef.current = false;
    setPassword("");

    if (!saved && data.session) {
      setError("Pendaftaran berhasil tetapi penyimpanan onboarding di browser gagal. Jangan tutup halaman; silakan ulangi proses menggunakan browser biasa.");
      setSession(data.session);
      return;
    }

    if (data.session) {
      setNotice("Pendaftaran diterima. KASIRA sedang menyiapkan akses usaha dan peran akun.");
      setSession(data.session);
      return;
    }

    setNotice("Akun berhasil diajukan. Buka email verifikasi, lalu kembali ke halaman KASIRA dan masuk. Untuk bergabung ke usaha, gunakan email yang menerima undangan. Jika membuka email di perangkat/browser lain, masukkan kode undangan pada form Masuk.");
    setLoading(false);
  };

  const submitNewPassword = async (event) => {
    event.preventDefault();
    setError("");
    setNotice("");
    if (!supabase) {
      setError("Layanan autentikasi belum tersedia.");
      return;
    }
    if (newPassword.length < 10) {
      setError("Password baru minimal 10 karakter.");
      return;
    }
    setLoading(true);
    try {
      const { error: updateError } = await supabase.auth.updateUser({ password: newPassword });
      if (updateError) throw updateError;
      await supabase.auth.signOut();
      setSession(null);
      setPassword("");
      setNewPassword("");
      setMode("login");
      setNotice("Password berhasil diperbarui. Silakan masuk menggunakan password baru.");
    } catch (updateError) {
      setError(friendlyError(updateError));
    } finally {
      setLoading(false);
    }
  };

  const logout = async () => {
    try { await supabase?.auth.signOut(); } finally { setSession(null); }
  };

  if (mode === "reset-password") return <div className="kasiraAuth">
    <div className="kasiraAuthCard">
      <div className="kasiraAuthTop">
        <div className="kasiraLogo">K</div>
        <div><b>KASIRA</b><small>Pemulihan akun</small></div>
        <button className="kasiraThemeBtn" type="button" onClick={() => setTheme(theme === "dark" ? "light" : "dark")} aria-label="Ubah tema">{theme === "dark" ? "☀" : "☾"}</button>
      </div>
      <div className="kasiraAuthTitle">Buat password baru</div>
      <p className="kasiraAuthDesc">Gunakan password baru minimal 10 karakter untuk akun Anda.</p>
      <form onSubmit={submitNewPassword}>
        <label>Password baru
          <div className="kasiraPass">
            <input type={showPassword ? "text" : "password"} autoComplete="new-password" minLength={10} value={newPassword} onChange={event => { setNewPassword(event.target.value); setError(""); }} placeholder="Minimal 10 karakter" required />
            <button type="button" onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Sembunyikan" : "Lihat"}</button>
          </div>
        </label>
        {error && <div className="kasiraAuthError" role="alert">{error}</div>}
        <button className="kasiraLoginBtn" disabled={loading}>{loading ? "Menyimpan…" : "Simpan password baru"}</button>
      </form>
      <small className="kasiraSecurityNote">Jangan bagikan tautan pemulihan kepada orang lain.</small>
    </div>
  </div>;

  if (loading) return <div className="kasiraAuth"><div className="kasiraAuthCard"><b>Memeriksa keamanan KASIRA…</b><small>Menyiapkan sesi dan memeriksa hak akses database.</small></div></div>;
  if (session?.kasira) return <Session session={session} theme={theme} setTheme={setTheme} logout={logout}/>;

  return <div className="kasiraAuth">
    <div className="kasiraAuthCard">
      <div className="kasiraAuthTop">
        <div className="kasiraLogo">K</div>
        <div><b>KASIRA</b><small>Professional Point of Sale</small></div>
        <button className="kasiraThemeBtn" type="button" onClick={() => setTheme(theme === "dark" ? "light" : "dark")} aria-label="Ubah tema">{theme === "dark" ? "☀" : "☾"}</button>
      </div>

      <div className="kasiraAuthTitle">{mode === "login" ? "Masuk ke KASIRA" : mode === "signup" ? "Daftar akun KASIRA" : "Pemulihan password"}</div>
      <p className="kasiraAuthDesc">{mode === "login" ? "Masuk menggunakan akun bisnis yang sudah terdaftar." : mode === "signup" ? "Buat ruang usaha baru atau bergabung dengan undangan dari pengelola." : "Masukkan email akun untuk menerima tautan penggantian password."}</p>

      {(mode === "login" || mode === "signup") ? <div className="kasiraModeTabs" role="tablist" aria-label="Mode autentikasi">
        <button type="button" className={mode === "login" ? "active" : ""} onClick={() => { setMode("login"); setError(""); setNotice(""); }}>Masuk</button>
        <button type="button" className={mode === "signup" ? "active" : ""} onClick={() => { setMode("signup"); setError(""); setNotice(""); }}>Daftar</button>
      </div> : <button type="button" className="kasiraBackLogin" onClick={() => { setMode("login"); setError(""); setNotice(""); }}>← Kembali ke Masuk</button>}

      {!supabaseConfigured && <div className="kasiraAuthError">Autentikasi cloud belum dikonfigurasi pada deployment ini.</div>}

      <form onSubmit={submit}>
        {mode === "signup" && <>
          <label>Nama lengkap
            <input type="text" autoComplete="name" maxLength={100} value={fullName} onChange={e => setFullName(e.target.value)} placeholder="Nama pengguna" required/>
          </label>
          <div className="kasiraSignupChoice" role="group" aria-label="Jenis pendaftaran">
            <button type="button" className={signupKind === "owner" ? "active" : ""} onClick={() => { setSignupKind("owner"); setError(""); }}>Buat usaha baru</button>
            <button type="button" className={signupKind === "invite" ? "active" : ""} onClick={() => { setSignupKind("invite"); setError(""); }}>Gabung dengan kode</button>
          </div>
          {signupKind === "owner" ? <label>Nama usaha
            <input type="text" autoComplete="organization" maxLength={120} value={businessName} onChange={e => setBusinessName(e.target.value)} placeholder="Contoh: PRISMAKOM" required/>
          </label> : <label>Kode undangan
            <input type="text" autoComplete="off" spellCheck="false" maxLength={80} value={signupInviteToken} onChange={e => setSignupInviteToken(e.target.value.toUpperCase().replace(/\s+/g, ""))} placeholder="Tempel kode undangan dari pengelola" required/>
            <small className="kasiraFieldHint">Gunakan email yang sama persis dengan email yang diundang.</small>
          </label>}
        </>}

        <label>Email
          <input autoFocus={mode === "login"} type="email" inputMode="email" autoComplete="email" maxLength={254} value={email} onChange={e => { setEmail(e.target.value); setError(""); }} placeholder="nama@perusahaan.com" required/>
        </label>
        {mode !== "forgot" && <label>Password
          <div className="kasiraPass">
            <input type={showPassword ? "text" : "password"} autoComplete={mode === "login" ? "current-password" : "new-password"} minLength={mode === "signup" ? 10 : undefined} value={password} onChange={e => { setPassword(e.target.value); setError(""); }} placeholder={mode === "signup" ? "Minimal 10 karakter" : "Password akun"} required/>
            <button type="button" onClick={() => setShowPassword(!showPassword)}>{showPassword ? "Sembunyikan" : "Lihat"}</button>
          </div>
        </label>}

        {mode === "login" && <button type="button" className="kasiraForgotBtn" onClick={() => { setMode("forgot"); setError(""); setNotice(""); setPassword(""); }}>Lupa password?</button>}

        {mode === "login" && <label>Kode undangan (opsional)
          <input type="text" autoComplete="off" spellCheck="false" maxLength={80} value={loginInviteToken} onChange={e => setLoginInviteToken(e.target.value.toUpperCase().replace(/\s+/g, ""))} placeholder="Isi bila Anda menerima undangan"/>
          <small className="kasiraFieldHint">Pakai jika akun Anda baru dibuat atau perlu menerima undangan setelah verifikasi email.</small>
        </label>}

        {error && <div className="kasiraAuthError" role="alert">{error}</div>}
        {notice && <div className="kasiraAuthNotice" role="status">{notice}</div>}
        <button className="kasiraLoginBtn" disabled={loading || !supabaseConfigured}>{loading ? "Memproses…" : mode === "login" ? "Masuk" : mode === "signup" ? "Buat akun" : "Kirim tautan reset"}</button>
      </form>

      {mode === "forgot" ? null : mode === "login" ? <div className="kasiraRoleInfo">
        <b>Hak akses diatur oleh database</b>
        <span>Owner • semua modul</span><span>Manager • operasional & laporan</span>
        <span>Kasir • transaksi</span><span>Gudang / karyawan • sesuai peran</span>
      </div> : <div className="kasiraRoleInfo">
        <b>Keamanan pendaftaran</b>
        <span>Usaha baru • membuat ruang bisnis terpisah</span>
        <span>Gabung tim • kode terikat ke email dan berlaku 7 hari</span>
        <span>Password minimal 10 karakter</span><span>Konfirmasi email mengikuti pengaturan Supabase</span>
      </div>}

      <small className="kasiraSecurityNote">Sesi autentikasi dan hak akses bisnis diverifikasi melalui Supabase Auth + RLS.<br/><a href={import.meta.env.BASE_URL + "privacy-policy.html"} target="_blank" rel="noreferrer">Kebijakan Privasi</a> · <a href={import.meta.env.BASE_URL + "delete-account.html"} target="_blank" rel="noreferrer">Penghapusan Akun</a></small>
    </div>
  </div>;
}

function Session({ session, theme, setTheme, logout }) {
  const [teamOpen, setTeamOpen] = useState(false);
  const [teamLoading, setTeamLoading] = useState(false);
  const [teamError, setTeamError] = useState("");
  const [team, setTeam] = useState({ members: [], invitations: [] });
  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteRole, setInviteRole] = useState("cashier");
  const [issuedToken, setIssuedToken] = useState("");
  const [issuedExpiry, setIssuedExpiry] = useState("");
  const [copied, setCopied] = useState(false);
  const role = session.kasira.role;
  const canManage = role === "owner" || role === "manager";

  const loadTeam = async () => {
    if (!supabase || !session.kasira.businessId) return;
    setTeamLoading(true);
    setTeamError("");
    const { data, error } = await supabase.rpc("kasira_list_team", {
      p_business_id: session.kasira.businessId
    });
    if (error) {
      setTeamError(friendlyError(error));
    } else if (data && typeof data === "object") {
      setTeam({
        members: Array.isArray(data.members) ? data.members : [],
        invitations: Array.isArray(data.invitations) ? data.invitations : []
      });
    }
    setTeamLoading(false);
  };

  useEffect(() => {
    if (teamOpen && canManage) loadTeam();
  }, [teamOpen, canManage, session.kasira.businessId]);

  useEffect(() => {
    let box;
    const install = () => {
      const header = document.querySelector(".headerRight");
      if (!header || header.querySelector(".kasiraSessionTools")) return;
      box = document.createElement("div");
      box.className = "kasiraSessionTools";

      if (canManage) {
        const teamButton = document.createElement("button");
        teamButton.className = "kasiraTeamBtn";
        teamButton.type = "button";
        teamButton.title = "Kelola pengguna";
        teamButton.textContent = "Pengguna";
        teamButton.onclick = () => setTeamOpen(true);
        box.appendChild(teamButton);
      }

      const themeButton = document.createElement("button");
      themeButton.type = "button";
      themeButton.title = "Mode siang/malam";
      themeButton.setAttribute("aria-label", "Ubah tema");
      themeButton.textContent = theme === "dark" ? "☀" : "☾";
      themeButton.onclick = () => setTheme(theme === "dark" ? "light" : "dark");

      const logoutButton = document.createElement("button");
      logoutButton.type = "button";
      logoutButton.title = "Keluar";
      logoutButton.setAttribute("aria-label", "Keluar");
      logoutButton.textContent = "↪";
      logoutButton.onclick = logout;

      box.append(themeButton, logoutButton);
      header.appendChild(box);
    };
    const timer = setInterval(install, 250);
    install();
    return () => {
      clearInterval(timer);
      box?.remove();
    };
  }, [theme, logout, canManage, setTheme]);

  const createInvitation = async (event) => {
    event.preventDefault();
    setTeamError("");
    setIssuedToken("");
    setCopied(false);
    const normalizedInviteEmail = inviteEmail.trim().toLowerCase();
    if (!normalizedInviteEmail) {
      setTeamError("Email calon pengguna wajib diisi.");
      return;
    }
    setTeamLoading(true);
    const { data, error } = await supabase.rpc("kasira_create_invitation", {
      p_business_id: session.kasira.businessId,
      p_email: normalizedInviteEmail,
      p_role: inviteRole
    });
    setTeamLoading(false);
    if (error) {
      setTeamError(friendlyError(error));
      return;
    }
    const result = Array.isArray(data) ? data[0] : data;
    if (!result?.invitation_token) {
      setTeamError("Undangan tidak berhasil dibuat. Muat ulang daftar pengguna lalu coba kembali.");
      return;
    }
    setIssuedToken(result.invitation_token);
    setIssuedExpiry(result.invitation_expires_at || "");
    setInviteEmail("");
    await loadTeam();
  };

  const copyInvitation = async () => {
    try {
      await navigator.clipboard.writeText(issuedToken);
      setCopied(true);
      setTeamError("");
    } catch {
      setCopied(false);
      setTeamError("Penyalinan otomatis tidak tersedia. Tekan lama kode untuk menyalin secara manual.");
    }
  };

  const dateLabel = (value) => {
    if (!value) return "—";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "—" : new Intl.DateTimeFormat("id-ID", {
      dateStyle: "medium",
      timeStyle: "short"
    }).format(date);
  };

  const statusLabel = (status) => ({
    pending: "Menunggu",
    accepted: "Diterima",
    expired: "Kedaluwarsa",
    revoked: "Dibatalkan"
  }[status] || status || "—");

  return <>
    {teamOpen && canManage && <div className="kasiraTeamBackdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setTeamOpen(false); }}>
      <section className="kasiraTeamDialog" role="dialog" aria-modal="true" aria-labelledby="kasiraTeamTitle">
        <div className="kasiraTeamHeader">
          <div><b id="kasiraTeamTitle">Pengguna & Undangan</b><small>{session.kasira.businessName}</small></div>
          <button type="button" className="kasiraTeamClose" onClick={() => setTeamOpen(false)} aria-label="Tutup">×</button>
        </div>
        <p className="kasiraTeamIntro">Undang akun dengan email tertentu. Peran disimpan di database dan dibatasi oleh kebijakan akses.</p>

        <form className="kasiraInviteForm" onSubmit={createInvitation}>
          <label>Email pengguna
            <input type="email" inputMode="email" maxLength={254} value={inviteEmail} onChange={event => setInviteEmail(event.target.value)} placeholder="staf@usaha.com" required/>
          </label>
          <label>Peran
            <select value={inviteRole} onChange={event => setInviteRole(event.target.value)}>
              {role === "owner" && <option value="manager">Manager</option>}
              <option value="cashier">Kasir</option>
              <option value="warehouse">Gudang</option>
              <option value="employee">Karyawan</option>
            </select>
          </label>
          <button type="submit" className="kasiraLoginBtn" disabled={teamLoading}>{teamLoading ? "Memproses…" : "Buat kode undangan"}</button>
        </form>

        {issuedToken && <div className="kasiraIssuedInvite">
          <b>Kode undangan berhasil dibuat</b>
          <p>Kirim kode ini kepada pemilik email yang diundang. Kode hanya ditampilkan saat dibuat, terikat ke email, dan berlaku sampai {dateLabel(issuedExpiry)}.</p>
          <div className="kasiraTokenRow"><code>{issuedToken}</code><button type="button" onClick={copyInvitation}>{copied ? "Tersalin" : "Salin"}</button></div>
          <small>Email undangan tidak dikirimi otomatis. Bagikan kode secara pribadi kepada penerima.</small>
        </div>}

        {teamError && <div className="kasiraAuthError" role="alert">{teamError}</div>}

        <div className="kasiraTeamLists">
          <div>
            <h3>Anggota aktif ({team.members.length})</h3>
            {teamLoading && team.members.length === 0 ? <small>Memuat pengguna…</small> : team.members.length === 0 ? <small>Belum ada anggota.</small> :
              team.members.map(member => <div className="kasiraMemberRow" key={member.user_id}>
                <span className="kasiraMemberAvatar">{String(member.email || "U").charAt(0).toUpperCase()}</span>
                <span className="kasiraMemberMeta"><b>{member.email || "Email tidak tersedia"}</b><small>Sejak {dateLabel(member.created_at)}</small></span>
                <span className="kasiraRolePill">{ROLE_LABEL[member.role] || member.role}</span>
              </div>)}
          </div>
          <div>
            <h3>Riwayat undangan</h3>
            {team.invitations.length === 0 ? <small>Belum ada undangan.</small> :
              team.invitations.map(invite => <div className="kasiraInvitationRow" key={invite.id}>
                <span><b>{invite.email}</b><small>{ROLE_LABEL[invite.role] || invite.role} · dibuat {dateLabel(invite.created_at)}</small></span>
                <span className={"kasiraInviteStatus " + (invite.status || "pending")}>{statusLabel(invite.status)}</span>
              </div>)}
          </div>
        </div>
        <div className="kasiraTeamFooter">
          <small>Hanya Owner/Manager dapat membuka pengelolaan pengguna. Akses transaksi dan data tetap diperiksa di server/database.</small>
          <button type="button" className="kasiraTeamRefresh" onClick={loadTeam} disabled={teamLoading}>Muat ulang daftar</button>
        </div>
      </section>
    </div>}
  </>;
}

const style = document.createElement("style");
style.textContent =
  "html[data-theme=\"dark\"] body{background:#0b1220;color:#e8eef8}" +
  "html[data-theme=\"dark\"] .header,html[data-theme=\"dark\"] aside,html[data-theme=\"dark\"] .panel,html[data-theme=\"dark\"] .metric,html[data-theme=\"dark\"] .product,html[data-theme=\"dark\"] .modal,html[data-theme=\"dark\"] .outlet{background:#111b2d;color:#e8eef8;border-color:#24324a}" +
  "html[data-theme=\"dark\"] aside{border-right-color:#24324a}html[data-theme=\"dark\"] nav button{color:#aab7cb}html[data-theme=\"dark\"] nav button:hover{background:#17243a}html[data-theme=\"dark\"] nav button.active{background:#102d55;color:#5eb0ff}" +
  "html[data-theme=\"dark\"] .searchBox,html[data-theme=\"dark\"] .form input,html[data-theme=\"dark\"] .form select,html[data-theme=\"dark\"] .settingsCard input,html[data-theme=\"dark\"] .settingsCard textarea,html[data-theme=\"dark\"] .settingsCard select,html[data-theme=\"dark\"] .tableSearch{background:#0c1626;color:#e8eef8;border-color:#2b3a53}" +
  "html[data-theme=\"dark\"] .searchBox input,html[data-theme=\"dark\"] .itemInfo b,html[data-theme=\"dark\"] .rank strong,html[data-theme=\"dark\"] .lowRow strong,html[data-theme=\"dark\"] .panelHead h2,html[data-theme=\"dark\"] .formTitle{color:#e8eef8}" +
  "html[data-theme=\"dark\"] .cats button,html[data-theme=\"dark\"] .controls button,html[data-theme=\"dark\"] .iconBtn,html[data-theme=\"dark\"] .ghost,html[data-theme=\"dark\"] .settingAction,html[data-theme=\"dark\"] .cloud{background:#17243a;color:#b8c5d8;border-color:#2b3a53}" +
  "html[data-theme=\"dark\"] .tablePanel th{background:#17243a;color:#aab7cb}html[data-theme=\"dark\"] .tablePanel th,html[data-theme=\"dark\"] .tablePanel td,html[data-theme=\"dark\"] .panelHead,html[data-theme=\"dark\"] .item,html[data-theme=\"dark\"] .summary{border-color:#24324a}" +
  "html[data-theme=\"dark\"] .modalBackdrop{background:rgba(2,8,18,.78)}html[data-theme=\"dark\"] .scan{background:#111b2d;color:#62b3ff;border-color:#31547c}html[data-theme=\"dark\"] .customerPicker select{background:#111b2d;color:#c9d5e5}" +
  ".kasiraAuth{position:fixed;inset:0;z-index:99999;display:grid;place-items:center;padding:16px;background:radial-gradient(circle at 20% 20%,rgba(0,207,255,.12),transparent 35%),linear-gradient(135deg,#06152d,#0a2b55 55%,#062033);font-family:Inter,system-ui,sans-serif;overflow:auto}" +
  ".kasiraAuthCard{width:min(430px,100%);background:#fff;border-radius:24px;padding:26px;box-shadow:0 30px 90px rgba(0,0,0,.3);color:#172033;max-height:calc(100dvh - 32px);overflow:auto}html[data-theme=\"dark\"] .kasiraAuthCard{background:#111b2d;color:#e8eef8;border:1px solid #2b3a53}" +
  ".kasiraAuthTop{display:flex;align-items:center;gap:11px;margin-bottom:22px}.kasiraAuthTop b{font-size:19px}.kasiraAuthTop small{display:block;color:#8190a5;font-size:10px;margin-top:2px}.kasiraLogo{width:44px;height:44px;border-radius:13px;background:linear-gradient(135deg,#0875ff,#00cfff);color:#fff;display:grid;place-items:center;font-weight:900;font-size:22px}.kasiraThemeBtn{margin-left:auto;width:38px;height:38px;border-radius:10px;background:#f2f6fb;color:#52627a;font-size:18px}" +
  ".kasiraAuthTitle{font-size:24px;font-weight:800;margin-bottom:6px}.kasiraAuthDesc{font-size:11px;color:#7c879b;margin:0 0 18px}.kasiraAuth form label,.kasiraInviteForm label{display:block;font-size:11px;color:#718096;margin:12px 0}.kasiraAuth input,.kasiraInviteForm input,.kasiraInviteForm select{box-sizing:border-box;width:100%;margin-top:6px;padding:12px;border:1px solid #dce4ef;border-radius:10px;outline:0;font-size:12px;background:#fff;color:#172033}.kasiraAuth input:focus,.kasiraInviteForm input:focus,.kasiraInviteForm select:focus{border-color:#0875ff;box-shadow:0 0 0 3px rgba(8,117,255,.12)}" +
  ".kasiraPass{position:relative}.kasiraPass input{padding-right:84px}.kasiraPass button{position:absolute;right:6px;top:7px;padding:7px 8px;border-radius:7px;background:#f2f6fb;color:#55708f;font-size:9px}" +
  ".kasiraAuthError{padding:10px;border-radius:9px;background:#fff0f0;color:#b52e36;font-size:11px;margin:8px 0;overflow-wrap:anywhere}.kasiraAuthNotice{padding:10px;border-radius:9px;background:#eef7ff;color:#174f84;font-size:11px;margin:8px 0;overflow-wrap:anywhere}html[data-theme=\"dark\"] .kasiraAuthNotice{background:#102943;color:#b7dcff}" +
  ".kasiraLoginBtn{width:100%;margin-top:8px;padding:13px;border-radius:10px;background:linear-gradient(135deg,#0875ff,#00a7ff);color:#fff;font-weight:800}.kasiraLoginBtn:disabled{opacity:.5;cursor:not-allowed}" +
  ".kasiraModeTabs,.kasiraSignupChoice{display:grid;grid-template-columns:1fr 1fr;gap:5px;padding:4px;background:#f1f5fa;border-radius:12px;margin:0 0 16px}.kasiraModeTabs button,.kasiraSignupChoice button{padding:10px;border-radius:9px;background:transparent;color:#6c7b91;font-size:11px;font-weight:700}.kasiraModeTabs button.active,.kasiraSignupChoice button.active{background:#fff;color:#075fd0;box-shadow:0 2px 10px rgba(15,43,82,.1)}html[data-theme=\"dark\"] .kasiraModeTabs,html[data-theme=\"dark\"] .kasiraSignupChoice{background:#0c1626}html[data-theme=\"dark\"] .kasiraModeTabs button.active,html[data-theme=\"dark\"] .kasiraSignupChoice button.active{background:#21395b;color:#8cc5ff}" +
  ".kasiraFieldHint{display:block;color:#8a96a8;font-size:9px;margin-top:5px;line-height:1.45}.kasiraForgotBtn,.kasiraBackLogin{display:block;margin:0 0 10px auto;padding:7px 0;background:transparent;color:#0875ff;font-size:10px;font-weight:700}.kasiraBackLogin{margin:0 0 16px}.kasiraRoleInfo{display:grid;grid-template-columns:1fr 1fr;gap:5px;margin-top:17px;padding:12px;background:#f6f9fc;border-radius:11px;font-size:9px;color:#718096}.kasiraRoleInfo b{grid-column:1/-1;color:#42536c}.kasiraSecurityNote{display:block;text-align:center;color:#98a4b4;font-size:9px;line-height:1.6;margin-top:14px}.kasiraSecurityNote a{color:#6a89ad}" +
  ".kasiraSessionTools{display:flex;gap:6px;align-items:center;margin-left:10px}.kasiraSessionTools button{min-width:34px;height:34px;padding:0 7px;border-radius:9px;background:#f2f6fb;color:#52627a;font-size:15px}.kasiraSessionTools button:last-child{color:#d6454a}.kasiraSessionTools .kasiraTeamBtn{font-size:10px;font-weight:800}html[data-theme=\"dark\"] .kasiraSessionTools button{background:#17243a;color:#c9d5e5}" +
  ".kasiraTeamBackdrop{position:fixed;inset:0;z-index:100001;display:flex;align-items:center;justify-content:center;padding:14px;background:rgba(2,9,22,.68);backdrop-filter:blur(8px);font-family:Inter,system-ui,sans-serif;color:#182538}" +
  ".kasiraTeamDialog{width:min(920px,100%);max-height:calc(100dvh - 28px);overflow:auto;border-radius:20px;background:#fff;box-shadow:0 32px 100px rgba(0,0,0,.35);padding:22px}html[data-theme=\"dark\"] .kasiraTeamDialog{background:#111b2d;color:#e8eef8;border:1px solid #2b3a53}" +
  ".kasiraTeamHeader{display:flex;align-items:center;justify-content:space-between;gap:14px}.kasiraTeamHeader b{font-size:19px}.kasiraTeamHeader small{display:block;color:#7f8da1;font-size:11px;margin-top:4px}.kasiraTeamClose{width:36px;height:36px;border-radius:10px;background:#f0f4f9;color:#54657c;font-size:24px}html[data-theme=\"dark\"] .kasiraTeamClose{background:#17243a;color:#e8eef8}" +
  ".kasiraTeamIntro{font-size:11px;color:#78869a;line-height:1.6}.kasiraInviteForm{display:grid;grid-template-columns:minmax(0,2fr) minmax(125px,1fr) minmax(150px,1fr);gap:10px;align-items:end;border:1px solid #e1e8f1;border-radius:14px;padding:12px}html[data-theme=\"dark\"] .kasiraInviteForm{border-color:#2b3a53}.kasiraInviteForm label{margin:0}.kasiraInviteForm .kasiraLoginBtn{margin:0;height:41px;padding:10px;font-size:11px}.kasiraIssuedInvite{padding:14px;margin-top:12px;border:1px solid #bcd9fa;border-radius:13px;background:#f3f8ff;font-size:11px;color:#35516f}html[data-theme=\"dark\"] .kasiraIssuedInvite{background:#10243a;border-color:#31547c;color:#c9d5e5}.kasiraIssuedInvite p{line-height:1.6}.kasiraIssuedInvite small{display:block;margin-top:8px;color:#7b8fa6}.kasiraTokenRow{display:flex;align-items:center;gap:8px}.kasiraTokenRow code{display:block;flex:1;overflow-wrap:anywhere;user-select:all;font-size:12px;font-weight:800;letter-spacing:.4px;padding:10px;border-radius:8px;background:#fff;border:1px dashed #98b8de;color:#0a4f9a}html[data-theme=\"dark\"] .kasiraTokenRow code{background:#0b1627;color:#9dccff;border-color:#31547c}.kasiraTokenRow button,.kasiraTeamRefresh{padding:10px 12px;border-radius:9px;background:#0875ff;color:#fff;font-size:10px;font-weight:800}" +
  ".kasiraTeamLists{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-top:18px}.kasiraTeamLists h3{font-size:12px;margin:0 0 9px}.kasiraTeamLists>div>small{font-size:10px;color:#8290a3}.kasiraMemberRow,.kasiraInvitationRow{display:flex;align-items:center;gap:9px;padding:10px 0;border-bottom:1px solid #edf1f6;font-size:10px}html[data-theme=\"dark\"] .kasiraMemberRow,html[data-theme=\"dark\"] .kasiraInvitationRow{border-color:#24324a}.kasiraMemberAvatar{width:30px;height:30px;flex:0 0 30px;display:grid;place-items:center;border-radius:9px;background:#e8f3ff;color:#1765ac;font-weight:800}.kasiraMemberMeta,.kasiraInvitationRow>span:first-child{display:flex;flex-direction:column;gap:4px;min-width:0;flex:1;overflow-wrap:anywhere}.kasiraMemberMeta small,.kasiraInvitationRow small{color:#8a97a8;font-size:9px}.kasiraRolePill,.kasiraInviteStatus{white-space:nowrap;border-radius:999px;padding:5px 7px;background:#edf4ff;color:#245b9b;font-size:9px;font-weight:700}.kasiraInviteStatus.accepted{background:#e9f8ef;color:#257144}.kasiraInviteStatus.expired,.kasiraInviteStatus.revoked{background:#f2f3f5;color:#6d7480}.kasiraTeamFooter{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:16px;border-top:1px solid #edf1f6;padding-top:14px}.kasiraTeamFooter small{max-width:580px;color:#8794a6;font-size:9px;line-height:1.5}html[data-theme=\"dark\"] .kasiraTeamFooter{border-color:#24324a}" +
  "html[data-theme=\"dark\"] .kasiraInviteForm input,html[data-theme=\"dark\"] .kasiraInviteForm select{background:#0c1626;color:#e8eef8;border-color:#2b3a53}" +
  "@media(max-width:780px){.kasiraAuth{padding:8px;place-items:start center}.kasiraAuthCard{padding:20px;border-radius:18px;max-height:calc(100dvh - 16px)}.kasiraRoleInfo{grid-template-columns:1fr}.kasiraSessionTools{gap:3px;margin-left:4px}.kasiraSessionTools button{min-width:30px;width:auto;height:32px;padding:0 6px}.kasiraSessionTools .kasiraTeamBtn{font-size:9px;padding:0 7px}.kasiraTeamDialog{padding:16px;border-radius:16px}.kasiraInviteForm{grid-template-columns:1fr}.kasiraTeamLists{grid-template-columns:1fr;gap:15px}.kasiraTeamFooter{align-items:flex-start;flex-direction:column}.kasiraTeamRefresh{width:100%}.kasiraTokenRow{align-items:stretch;flex-direction:column}.kasiraTokenRow button{width:100%}}";
document.head.appendChild(style);

function mount() {
  const root = document.createElement("div");
  root.id = "kasira-auth-root";
  document.body.appendChild(root);
  createRoot(root).render(<Login />);
}
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount); else mount();
