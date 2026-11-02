import assert from "node:assert/strict";
import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import {
  readLocalStateBatch,
  writeLocalStateBatch
} from "../src/local-db.js";
import {
  createOfflineOwner,
  authenticateOfflineUser,
  getOfflineSession,
  logoutOfflineUser
} from "../src/offline-auth.js";

globalThis.indexedDB = new IDBFactory();

const persisted = await writeLocalStateBatch({
  kasira_products: [{ id: "product-1", name: "Produk Uji", stock: 20 }],
  kasira_sales: [{ id: "sale-1", total: 25000 }],
  kasira_journal: [{ id: "journal-1", debit: 25000, credit: 25000 }]
}, null, { requireAtomic: true });

assert.equal(persisted.engine, "IndexedDB");
assert.equal(persisted.mirrored, false);

const snapshot = await readLocalStateBatch([
  "kasira_products", "kasira_sales", "kasira_journal"
], null);
assert.equal(snapshot.kasira_products[0].stock, 20);
assert.equal(snapshot.kasira_sales[0].total, 25000);
assert.equal(snapshot.kasira_journal[0].debit, snapshot.kasira_journal[0].credit);

// Simulate a structured-clone failure after the first write has already been
// queued. The read-write transaction must abort without committing that first
// write as a partial batch.
await assert.rejects(
  () => writeLocalStateBatch({
    kasira_atomic_good: { value: "must-not-commit" },
    kasira_atomic_bad: { value: () => "not cloneable" }
  }, null, { requireAtomic: true })
);

const afterAbort = await readLocalStateBatch(["kasira_atomic_good", "kasira_atomic_bad"], null);
assert.equal(Object.hasOwn(afterAbort, "kasira_atomic_good"), false);
assert.equal(Object.hasOwn(afterAbort, "kasira_atomic_bad"), false);

// Verify local owner account, session restore, password failure, and logout
// against IndexedDB rather than a localStorage-only fallback.
const owner = await createOfflineOwner({
  name: "Pemilik IndexedDB",
  email: "idb-owner@example.test",
  password: "KASIRA-IndexedDB-Password-123"
});
assert.equal(owner.role, "owner");
assert.equal((await getOfflineSession()).email, "idb-owner@example.test");

await assert.rejects(
  () => authenticateOfflineUser("idb-owner@example.test", "wrong-password"),
  /salah/
);

await authenticateOfflineUser("idb-owner@example.test", "KASIRA-IndexedDB-Password-123");
await logoutOfflineUser();
assert.equal(await getOfflineSession(), null);

console.log("KASIRA IndexedDB persistence, atomic rollback, and auth tests passed.");
