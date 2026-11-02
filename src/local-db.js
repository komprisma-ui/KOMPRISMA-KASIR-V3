const DB_NAME = "kasira-local-db";
const DB_VERSION = 1;
const STORE_NAME = "app_state";

export const KASIRA_STATE_KEYS = [
  "kasira_products", "kasira_sales", "kasira_customers", "kasira_purchases",
  "kasira_cash", "kasira_returns", "kasira_journal", "kasira_accounts",
  "kasira_expenses", "kasira_payroll", "kasira_assets", "kasira_inventories",
  "kasira_employees", "kasira_attendance", "kasira_settings"
];

let databasePromise;

function safeStorage() {
  try { return globalThis.localStorage || null; } catch { return null; }
}

function openDatabase() {
  if (!globalThis.indexedDB) return Promise.resolve(null);
  if (databasePromise) return databasePromise;

  databasePromise = new Promise((resolve, reject) => {
    let request;
    try {
      request = globalThis.indexedDB.open(DB_NAME, DB_VERSION);
    } catch (error) {
      reject(error);
      return;
    }
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: "key" });
      }
    };
    request.onsuccess = () => {
      const db = request.result;
      db.onversionchange = () => db.close();
      resolve(db);
    };
    request.onerror = () => reject(request.error || new Error("Tidak dapat membuka database lokal."));
    request.onblocked = () => reject(new Error("Database lokal sedang dipakai tab lain. Tutup tab KASIRA yang lain lalu coba lagi."));
  }).catch(error => {
    databasePromise = null;
    throw error;
  });

  return databasePromise;
}

function requestValue(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error("Operasi database lokal gagal."));
  });
}

function transactionFinished(transaction) {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error || new Error("Transaksi database lokal gagal."));
    transaction.onabort = () => reject(transaction.error || new Error("Transaksi database lokal dibatalkan."));
  });
}

function readLegacyValue(storage, key) {
  if (!storage) return { found: false, value: undefined };
  try {
    const raw = storage.getItem(key);
    if (raw === null) return { found: false, value: undefined };
    return { found: true, value: JSON.parse(raw) };
  } catch {
    return { found: false, value: undefined };
  }
}

/**
 * Reads a consistent group of app-state records. Values missing from IndexedDB
 * are migrated from the previous localStorage format without deleting the old copy.
 */
export async function readLocalStateBatch(keys = KASIRA_STATE_KEYS, storage = safeStorage()) {
  const wanted = Array.from(new Set((keys || []).filter(key => typeof key === "string" && key.length)));
  const result = {};
  let db = null;

  try { db = await openDatabase(); } catch { db = null; }

  if (db) {
    try {
      const tx = db.transaction(STORE_NAME, "readonly");
      const done = transactionFinished(tx);
      const store = tx.objectStore(STORE_NAME);
      const requests = wanted.map(key => requestValue(store.get(key)));
      const rows = await Promise.all(requests);
      await done;
      rows.forEach((row, index) => {
        if (row && Object.prototype.hasOwnProperty.call(row, "value")) result[wanted[index]] = row.value;
      });
    } catch {
      // Fall through to the compatible localStorage mirror.
    }
  }

  const migrated = {};
  for (const key of wanted) {
    if (Object.prototype.hasOwnProperty.call(result, key)) continue;
    const legacy = readLegacyValue(storage, key);
    if (legacy.found) {
      result[key] = legacy.value;
      migrated[key] = legacy.value;
    }
  }

  if (Object.keys(migrated).length) {
    try { await writeLocalStateBatch(migrated, storage); } catch { /* Keep the original localStorage copy. */ }
  }

  return result;
}

/**
 * Writes multiple application records in one IndexedDB transaction, then updates
 * the localStorage mirror. The localStorage copy is a compatibility fallback,
 * not the source of truth when IndexedDB is available.
 */
export async function writeLocalStateBatch(values, storage = safeStorage(), options = {}) {
  const requireAtomic = options?.requireAtomic === true;
  const requireAtomic = options?.requireAtomic === true;
  if (!values || typeof values !== "object" || Array.isArray(values)) {
    throw new Error("Batch penyimpanan lokal tidak valid.");
  }

  const entries = Object.entries(values);
  if (!entries.length) return { engine: "none" };

  let db = null;
  let indexedDbWritten = false;
  let indexedDbError = null;

  try { db = await openDatabase(); } catch (error) { indexedDbError = error; }

  if (db) {
    try {
      const tx = db.transaction(STORE_NAME, "readwrite");
      const done = transactionFinished(tx);
      const store = tx.objectStore(STORE_NAME);
      const updatedAt = new Date().toISOString();
      for (const [key, value] of entries) {
        store.put({ key, value, updatedAt });
      }
      await done;
      indexedDbWritten = true;
    } catch (error) {
      indexedDbError = error;
    }
  }

  if (requireAtomic && !indexedDbWritten) {
    const detail = indexedDbError?.message ? " " + indexedDbError.message : "";
    throw new Error("Operasi dibatalkan: IndexedDB tidak tersedia untuk penyimpanan atomik. Jangan lanjutkan transaksi sebelum penyimpanan perangkat pulih." + detail);
  }

  let localStorageWritten = false;
  let localStorageError = null;
  if (storage) {
    try {
      for (const [key, value] of entries) storage.setItem(key, JSON.stringify(value));
      localStorageWritten = true;
    } catch (error) {
      localStorageError = error;
    }
  }

  if (!indexedDbWritten && !localStorageWritten) {
    const detail = localStorageError || indexedDbError;
    throw new Error("Penyimpanan lokal gagal. Jangan tutup aplikasi sebelum ruang penyimpanan perangkat diperiksa." + (detail?.message ? " " + detail.message : ""));
  }

  return {
    engine: indexedDbWritten ? "IndexedDB" : "localStorage",
    mirrored: localStorageWritten
  };
}

export async function writeLocalState(key, value, storage = safeStorage()) {
  return writeLocalStateBatch({ [key]: value }, storage);
}

export async function getLocalStorageStatus() {
  let indexedDbAvailable = false;
  try { indexedDbAvailable = Boolean(await openDatabase()); } catch { indexedDbAvailable = false; }
  const storage = safeStorage();
  let localStorageAvailable = false;
  try {
    const probe = "__kasira_storage_probe__";
    storage?.setItem(probe, "1");
    storage?.removeItem(probe);
    localStorageAvailable = Boolean(storage);
  } catch { localStorageAvailable = false; }
  return {
    primary: indexedDbAvailable ? "IndexedDB" : "localStorage",
    indexedDbAvailable,
    localStorageAvailable
  };
}
