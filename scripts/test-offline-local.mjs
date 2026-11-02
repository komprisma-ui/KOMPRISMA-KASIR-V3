import assert from "node:assert/strict";
import {
  readLocalStateBatch,
  writeLocalStateBatch
} from "../src/local-db.js";
import {
  createOfflineOwner,
  authenticateOfflineUser,
  createOfflineUser,
  getOfflineUsers,
  getOfflineSession,
  logoutOfflineUser,
  setOfflineUserActive
} from "../src/offline-auth.js";

const storageValues = new Map();
const storage = {
  getItem(key) { return storageValues.has(key) ? storageValues.get(key) : null; },
  setItem(key, value) { storageValues.set(key, String(value)); },
  removeItem(key) { storageValues.delete(key); }
};

// Test the localStorage fallback used when IndexedDB is unavailable (Node test runner).
await writeLocalStateBatch({ kasira_products: [{ id: "p-1", name: "Test" }] }, storage);
const migrated = await readLocalStateBatch(["kasira_products"], storage);
await assert.rejects(
  () => writeLocalStateBatch({ kasira_products: [{ id: "p-2" }], kasira_sales: [{ id: "s-1" }] }, storage, { requireAtomic: true }),
  /IndexedDB tidak tersedia/
);
assert.equal(migrated.kasira_products[0].id, "p-1");

const originalStorage = globalThis.localStorage;
const originalCrypto = globalThis.crypto;
Object.defineProperty(globalThis, "localStorage", { configurable: true, value: storage });
if (!globalThis.crypto?.subtle) {
  const { webcrypto } = await import("node:crypto");
  Object.defineProperty(globalThis, "crypto", { configurable: true, value: webcrypto });
}

try {
  const owner = await createOfflineOwner({
    name: "Pemilik Uji",
    email: "owner@example.test",
    password: "KASIRA-password-123"
  });
  assert.equal(owner.role, "owner");
  assert.equal((await getOfflineSession()).email, "owner@example.test");

  await assert.rejects(
    () => authenticateOfflineUser("owner@example.test", "wrong-password"),
    /salah/
  );

  const ownerSession = await authenticateOfflineUser("owner@example.test", "KASIRA-password-123");
  assert.equal(ownerSession.role, "owner");

  const cashier = await createOfflineUser(ownerSession, {
    name: "Kasir Uji",
    email: "cashier@example.test",
    password: "Kasir-password-123",
    role: "kasir"
  });
  assert.equal(cashier.role, "kasir");
  assert.equal((await getOfflineUsers()).length, 2);

  await assert.rejects(
    () => setOfflineUserActive(ownerSession, owner.id, false),
    /pemilik utama/
  );
  await setOfflineUserActive(ownerSession, cashier.id, false);
  await assert.rejects(
    () => authenticateOfflineUser("cashier@example.test", "Kasir-password-123"),
    /dinonaktifkan/
  );

  await logoutOfflineUser();
  assert.equal(await getOfflineSession(), null);
  console.log("KASIRA local storage/auth tests passed.");
} finally {
  if (originalStorage === undefined) delete globalThis.localStorage;
  else Object.defineProperty(globalThis, "localStorage", { configurable: true, value: originalStorage });
  if (originalCrypto === undefined) delete globalThis.crypto;
  else Object.defineProperty(globalThis, "crypto", { configurable: true, value: originalCrypto });
}
