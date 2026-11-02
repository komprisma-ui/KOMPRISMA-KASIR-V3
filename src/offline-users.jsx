import React, { useEffect, useState } from "react";
import { createOfflineUser, getOfflineUsers, setOfflineUserActive } from "./offline-auth.js";

const roleNames = { owner: "Pemilik", admin: "Admin", kasir: "Kasir", pengguna: "Pengguna" };

export default function OfflineUsers({ authUser }) {
  const [users, setUsers] = useState([]);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] = useState("kasir");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  const refresh = async () => setUsers(await getOfflineUsers());
  useEffect(() => { refresh().catch(error => setMessage(error.message)); }, []);

  const submit = async event => {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      await createOfflineUser(authUser, { name, email, password, role });
      setName(""); setEmail(""); setPassword(""); setRole("kasir");
      await refresh();
      setMessage("Pengguna lokal berhasil ditambahkan.");
    } catch (error) {
      setMessage(error.message || "Gagal menambahkan pengguna.");
    } finally { setBusy(false); }
  };

  const toggle = async user => {
    if (user.role === "owner") return;
    setBusy(true); setMessage("");
    try {
      await setOfflineUserActive(authUser, user.id, !user.active);
      await refresh();
    } catch (error) { setMessage(error.message || "Tidak dapat mengubah akun."); }
    finally { setBusy(false); }
  };

  const canManage = ["owner", "admin"].includes(authUser?.role);
  return (
    <section className="offlineUsers">
      <div className="offlineUsersHead">
        <div><span className="eyebrow">LOCAL ACCESS CONTROL</span><h1>Pengguna Perangkat</h1><p>Kelola akun yang dapat masuk ke KASIRA pada perangkat ini.</p></div>
        <span className="offlineLocalChip">Tersimpan lokal</span>
      </div>
      {!canManage && <div className="offlineUsersNotice">Akun Anda hanya dapat melihat daftar pengguna. Hubungi pemilik atau admin untuk perubahan akses.</div>}
      {canManage && (
        <form className="offlineUserForm" onSubmit={submit}>
          <h2>Tambah pengguna</h2>
          <div className="offlineUserGrid">
            <label>Nama<input value={name} onChange={event => setName(event.target.value)} maxLength={100} required /></label>
            <label>Email login<input type="email" value={email} onChange={event => setEmail(event.target.value)} required /></label>
            <label>Peran<select value={role} onChange={event => setRole(event.target.value)}><option value="kasir">Kasir</option><option value="pengguna">Pengguna</option><option value="admin" disabled={authUser?.role !== "owner"}>Admin</option></select></label>
            <label>Kata sandi (min. 10 karakter)<input type="password" value={password} onChange={event => setPassword(event.target.value)} minLength={10} required /></label>
          </div>
          <button className="primary" disabled={busy}>{busy ? "Menyimpan…" : "Simpan pengguna"}</button>
        </form>
      )}
      {message && <div className="offlineUsersNotice" role="status">{message}</div>}
      <div className="offlineUsersTable">
        <div className="offlineUsersTableHead"><b>Nama / Email</b><b>Peran</b><b>Status</b><b>Aksi</b></div>
        {users.map(user => (
          <div className="offlineUsersRow" key={user.id}>
            <span><b>{user.name}</b><small>{user.email}</small></span>
            <span>{roleNames[user.role] || user.role}</span>
            <span className={user.active ? "offlineUserActive" : "offlineUserDisabled"}>{user.active ? "Aktif" : "Nonaktif"}</span>
            <span>{authUser?.role === "owner" && user.role !== "owner" ? <button className="ghost" disabled={busy} onClick={() => toggle(user)}>{user.active ? "Nonaktifkan" : "Aktifkan"}</button> : "—"}</span>
          </div>
        ))}
        {!users.length && <p className="offlineUsersEmpty">Belum ada akun pengguna.</p>}
      </div>
      <p className="offlineUsersDisclaimer">Akun lokal berlaku hanya pada perangkat ini. Karena mode offline tidak memakai server, kontrol akun perangkat bukan pengganti kontrol keamanan server untuk penggunaan multi-perangkat.</p>
    </section>
  );
}
