import React, { useEffect, useState } from "react";
import { authenticateOfflineUser, createOfflineOwner, getOfflineUsers } from "./offline-auth.js";

export default function OfflineAuth({ onAuthenticated }) {
  const [hasUsers, setHasUsers] = useState(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    let active = true;
    getOfflineUsers()
      .then(users => { if (active) setHasUsers(users.length > 0); })
      .catch(error => { if (active) { setHasUsers(false); setMessage(error.message || "Penyimpanan lokal belum siap."); } });
    return () => { active = false; };
  }, []);

  const setup = hasUsers === false;
  const submit = async event => {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      if (setup) {
        if (password !== confirm) throw new Error("Konfirmasi kata sandi tidak sama.");
        const owner = await createOfflineOwner({ name, email, password });
        onAuthenticated({
          userId: owner.id, id: owner.id, name: owner.name,
          email: owner.email, role: owner.role, local: true
        });
      } else {
        const session = await authenticateOfflineUser(email, password);
        onAuthenticated({
          ...session, id: session.userId, local: true
        });
      }
    } catch (error) {
      setMessage(error.message || "Tidak dapat memproses akun lokal.");
      if (setup) {
        try { setHasUsers((await getOfflineUsers()).length > 0); } catch { /* keep the form visible */ }
      }
    } finally {
      setBusy(false);
    }
  };

  if (hasUsers === null) {
    return <div className="offlineAuth"><section className="offlineAuthCard"><h1>KASIRA Offline</h1><p>Menyiapkan penyimpanan perangkat…</p></section></div>;
  }

  return (
    <div className="offlineAuth">
      <form className="offlineAuthCard" onSubmit={submit}>
        <div className="offlineAuthBrand"><div className="offlineAuthLogo">K</div><div><b>KASIRA</b><small>OFFLINE POS • LOCAL EDITION</small></div></div>
        <span className="offlineAuthEyebrow">{setup ? "AKTIVASI PERANGKAT" : "AKSES PERANGKAT"}</span>
        <h1>{setup ? "Buat akun pemilik" : "Masuk ke KASIRA"}</h1>
        <p className="offlineAuthDescription">
          {setup
            ? "Buat akun pemilik lokal pertama. Akun dan seluruh data usaha akan tersimpan di perangkat ini."
            : "Masuk menggunakan akun lokal yang sudah dibuat di perangkat ini."}
        </p>
        {setup && <label>Nama pemilik<input value={name} onChange={event => setName(event.target.value)} autoComplete="name" minLength={2} maxLength={100} required /></label>}
        <label>Email pengguna<input type="email" value={email} onChange={event => setEmail(event.target.value)} autoComplete="username" required /></label>
        <label>Kata sandi<input type="password" value={password} onChange={event => setPassword(event.target.value)} autoComplete={setup ? "new-password" : "current-password"} minLength={10} required /></label>
        {setup && <label>Ulangi kata sandi<input type="password" value={confirm} onChange={event => setConfirm(event.target.value)} autoComplete="new-password" minLength={10} required /></label>}
        {message && <div className="offlineAuthMessage" role="alert">{message}</div>}
        <button className="offlineAuthSubmit" type="submit" disabled={busy}>
          {busy ? "Memproses…" : setup ? "Buat akun pemilik" : "Masuk"}
        </button>
        <div className="offlineAuthFoot">
          <b><span className="offlineDot" /> Data tersimpan di perangkat</b>
          <small>Tidak perlu internet. Lakukan backup berkala melalui menu Pengaturan. Kata sandi lokal tidak dapat dipulihkan melalui email.</small>
        </div>
      </form>
    </div>
  );
}
