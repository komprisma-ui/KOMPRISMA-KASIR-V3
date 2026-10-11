import assert from "node:assert/strict";
import { enqueueOfflineSale, readOfflineQueue, removeOfflineSale, countOfflineSales } from "../src/offline-sync.js";

const values = new Map();
const storage = {
  getItem(key) { return values.has(key) ? values.get(key) : null; },
  setItem(key, value) { values.set(key, String(value)); },
  removeItem(key) { values.delete(key); }
};
const entry = id => ({
  clientRequestId: id,
  payload: { client_request_id: id, items: [] },
  sale: { id: "local-" + id, clientRequestId: id, status: "pending_sync" }
});

assert.equal(countOfflineSales("business-a", storage), 0);
enqueueOfflineSale("business-a", entry("req-1"), storage);
assert.equal(countOfflineSales("business-a", storage), 1);
enqueueOfflineSale("business-a", entry("req-1"), storage);
assert.equal(countOfflineSales("business-a", storage), 1, "duplicate request IDs must be idempotent in the local queue");
enqueueOfflineSale("business-a", entry("req-2"), storage);
assert.equal(countOfflineSales("business-a", storage), 2);
assert.equal(countOfflineSales("business-b", storage), 0, "queue must be scoped by business");
assert.equal(readOfflineQueue("business-a", storage)[0].payload.client_request_id, "req-1");
removeOfflineSale("business-a", "req-1", storage);
assert.deepEqual(readOfflineQueue("business-a", storage).map(x => x.clientRequestId), ["req-2"]);
storage.setItem("kasira_offline_sales_v1:broken", "{bad json");
assert.deepEqual(readOfflineQueue("broken", storage), []);
assert.throws(() => enqueueOfflineSale("business-a", { clientRequestId: "x" }, storage));
console.log("Offline queue tests passed (8 assertions).");
