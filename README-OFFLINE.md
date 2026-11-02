# KASIRA Offline — Local Edition

This build is a separate, device-local edition of KASIRA. It does not require Supabase, a cloud account, or an internet connection after the application assets have been installed.

## Local operation

- Products, stock, sales, customers, purchases, cash records, returns, journals, employees, attendance, assets, inventory, and settings are stored on the device.
- IndexedDB is the primary local database. Existing localStorage data is migrated on first start and retained as a compatibility mirror.
- A sale is committed to one IndexedDB transaction before the receipt is displayed. If local persistence fails, the checkout must not be treated as completed.
- Local accounts use PBKDF2 password hashes. The first local account becomes the owner; the owner can create admin, cashier, and user accounts on that device.
- The PWA service worker caches the application shell and built assets for subsequent offline launches.
- Backup and restore use the KASIRA JSON backup feature in Settings. Create and test a backup at the end of each business day; the backup does not include local login credentials.

## Build

Use the offline Vite mode:

```sh
npm run build:offline
```

For a local Android debug package:

```sh
npm run build:android:offline
```

The Android debug package is for installation testing, not commercial distribution. A commercial APK/AAB must be signed with the publisher's protected release keystore and tested on target devices.

## Important limitations

- Local data belongs to one browser profile or one installed app's private storage. It is not shared with another phone, tablet, browser profile, or the online KASIRA edition.
- The offline edition does not automatically upload or synchronize its data to Supabase. Export a backup before uninstalling, clearing app storage, resetting the device, or moving to another device.
- For a web/PWA installation, the first successful load must happen while online so the service worker can cache the application files. An Android package built with Capacitor bundles the app assets locally.
- Local account access controls apply to this device only. They are not a server-side security boundary and do not protect data from a person who can inspect or modify the device storage. Local login credentials are intentionally excluded from JSON backup; create a new owner account on a replacement device.
- Selecting QRIS, card, or transfer records the payment method only. It does not initiate a payment gateway transaction.
- Printer, barcode scanner, tax, stock reconciliation, and recovery behavior must still be accepted on the actual target hardware before commercial release.

## Release gate

Do not describe this edition as production-certified until the automated checks pass and manual testing covers: airplane-mode cold start, repeated checkout, forced app close during checkout, stock consistency after restart, backup/restore, owner and cashier roles, invalid passwords, storage-full handling, barcode entry, and the exact printer models being sold.
