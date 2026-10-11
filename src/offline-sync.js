const PREFIX = "kasira_offline_sales_v1:";

export function offlineQueueKey(businessId) {
  if (!businessId) throw new Error("Business ID wajib untuk antrean offline.");
  return PREFIX + businessId;
}

export function readOfflineQueue(businessId, storage = globalThis.localStorage) {
  if (!businessId || !storage) return [];
  try {
    const value = JSON.parse(storage.getItem(offlineQueueKey(businessId)) || "[]");
    return Array.isArray(value) ? value.filter(x => x && x.clientRequestId && x.payload && x.sale) : [];
  } catch {
    return [];
  }
}

export function enqueueOfflineSale(businessId, entry, storage = globalThis.localStorage) {
  if (!entry?.clientRequestId || !entry?.payload || !entry?.sale) {
    throw new Error("Data transaksi offline tidak lengkap.");
  }
  const queue = readOfflineQueue(businessId, storage);
  if (queue.some(item => item.clientRequestId === entry.clientRequestId)) return queue;
  const next = [...queue, { ...entry, queuedAt: entry.queuedAt || new Date().toISOString() }];
  storage.setItem(offlineQueueKey(businessId), JSON.stringify(next));
  return next;
}

export function removeOfflineSale(businessId, clientRequestId, storage = globalThis.localStorage) {
  const next = readOfflineQueue(businessId, storage).filter(item => item.clientRequestId !== clientRequestId);
  storage.setItem(offlineQueueKey(businessId), JSON.stringify(next));
  return next;
}

export function countOfflineSales(businessId, storage = globalThis.localStorage) {
  return readOfflineQueue(businessId, storage).length;
}
