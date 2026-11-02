import { readLocalStateBatch, writeLocalStateBatch } from "./local-db.js";

const USERS_KEY = "kasira_offline_users_v1";
const SESSION_KEY = "kasira_offline_session_v1";
const ITERATIONS = 210000;
const ALLOWED_ROLES = new Set(["owner", "admin", "kasir", "pengguna"]);

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function toHex(bytes) {
  return Array.from(new Uint8Array(bytes), byte => byte.toString(16).padStart(2, "0")).join("");
}

function randomBytes(length) {
  if (!globalThis.crypto?.getRandomValues) throw new Error("Perangkat tidak mendukung generator keamanan untuk login lokal.");
  const bytes = new Uint8Array(length);
  globalThis.crypto.getRandomValues(bytes);
  return bytes;
}

async function passwordHash(password, saltHex) {
  if (!globalThis.crypto?.subtle) throw new Error("Browser/WebView tidak mendukung enkripsi login lokal. Perbarui browser atau aplikasi.");
  const salt = new Uint8Array(saltHex.match(/.{1,2}/g).map(byte => parseInt(byte, 16)));
  const key = await globalThis.crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(String(password)),
    "PBKDF2",
    false,
    ["deriveBits"]
  );
  const bits = await globalThis.crypto.subtle.deriveBits(
    { name: "PBKDF2", salt, iterations: ITERATIONS, hash: "SHA-256" },
    key,
    256
  );
  return toHex(bits);
}

function equalHash(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) diff |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return diff === 0;
}

function publicUser(user) {
  if (!user) return null;
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    active: user.active !== false,
    createdAt: user.createdAt
  };
}

async function readUsers() {
  const values = await readLocalStateBatch([USERS_KEY]);
  return Array.isArray(values[USERS_KEY]) ? values[USERS_KEY] : [];
}

async function saveUsers(users) {
  await writeLocalStateBatch({ [USERS_KEY]: users });
}

function newId() {
  return globalThis.crypto?.randomUUID?.() || ("local_" + Date.now().toString(36) + "_" + toHex(randomBytes(8)));
}

async function createRecord({ name, email, password, role }) {
  const cleanName = String(name || "").trim();
  const cleanEmail = normalizeEmail(email);
  if (cleanName.length < 2) throw new Error("Nama pengguna minimal 2 karakter.");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) throw new Error("Alamat email tidak valid.");
  if (String(password || "").length < 10) throw new Error("Kata sandi minimal 10 karakter.");
  if (!ALLOWED_ROLES.has(role)) throw new Error("Peran pengguna tidak valid.");

  const users = await readUsers();
  if (users.some(user => user.email === cleanEmail)) throw new Error("Email sudah terdaftar di perangkat ini.");
  const salt = toHex(randomBytes(16));
  const hash = await passwordHash(password, salt);
  return {
    id: newId(),
    name: cleanName,
    email: cleanEmail,
    role,
    salt,
    passwordHash: hash,
    active: true,
    createdAt: new Date().toISOString()
  };
}

async function createSession(user) {
  const session = {
    userId: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    signedInAt: new Date().toISOString()
  };
  await writeLocalStateBatch({ [SESSION_KEY]: session });
  return session;
}

export async function getOfflineUsers() {
  const users = await readUsers();
  return users.map(publicUser);
}

export async function getOfflineSession() {
  const values = await readLocalStateBatch([USERS_KEY, SESSION_KEY]);
  const users = Array.isArray(values[USERS_KEY]) ? values[USERS_KEY] : [];
  const session = values[SESSION_KEY];
  if (!session?.userId) return null;
  const user = users.find(item => item.id === session.userId && item.active !== false);
  return user ? {
    userId: user.id,
    name: user.name,
    email: user.email,
    role: user.role,
    signedInAt: session.signedInAt
  } : null;
}

export async function createOfflineOwner({ name, email, password }) {
  const users = await readUsers();
  if (users.length) throw new Error("Akun pemilik sudah dibuat. Silakan masuk dengan akun yang terdaftar.");
  const owner = await createRecord({ name, email, password, role: "owner" });
  await writeLocalStateBatch({
    [USERS_KEY]: [owner],
    [SESSION_KEY]: {
      userId: owner.id,
      name: owner.name,
      email: owner.email,
      role: owner.role,
      signedInAt: new Date().toISOString()
    }
  });
  return publicUser(owner);
}

export async function authenticateOfflineUser(email, password) {
  const cleanEmail = normalizeEmail(email);
  const users = await readUsers();
  const user = users.find(item => item.email === cleanEmail);
  if (!user || user.active === false) throw new Error("Akun tidak ditemukan atau dinonaktifkan.");
  const candidate = await passwordHash(password, user.salt);
  if (!equalHash(candidate, user.passwordHash)) throw new Error("Email atau kata sandi salah.");
  return createSession(user);
}

export async function createOfflineUser(actor, input) {
  if (!actor || !["owner", "admin"].includes(actor.role)) throw new Error("Hanya pemilik atau admin yang dapat menambah pengguna.");
  const users = await readUsers();
  if (!users.some(item => item.id === actor.userId && item.active !== false)) throw new Error("Sesi pengelola tidak valid.");
  const role = input?.role;
  if (!["admin", "kasir", "pengguna"].includes(role)) throw new Error("Peran baru tidak valid.");
  if (actor.role === "admin" && role === "admin") throw new Error("Admin tidak dapat membuat admin lain.");
  const record = await createRecord({ ...input, role });
  await saveUsers([...users, record]);
  return publicUser(record);
}

export async function setOfflineUserActive(actor, userId, active) {
  if (!actor || actor.role !== "owner") throw new Error("Hanya pemilik yang dapat mengubah status akun pengguna.");
  const users = await readUsers();
  const target = users.find(item => item.id === userId);
  if (!target) throw new Error("Pengguna tidak ditemukan.");
  if (target.role === "owner") throw new Error("Akun pemilik utama tidak dapat dinonaktifkan.");
  const next = users.map(item => item.id === userId ? { ...item, active: Boolean(active) } : item);
  await saveUsers(next);
  if (!active && actor.userId === userId) await writeLocalStateBatch({ [SESSION_KEY]: null });
  return next.map(publicUser);
}

export async function logoutOfflineUser() {
  await writeLocalStateBatch({ [SESSION_KEY]: null });
}
