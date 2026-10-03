# KASIRA — Professional POS v0.4.2
Modern Point of Sale MVP built with React + Vite.

## Run locally
npm install
npm run dev

## Included
- POS/cart and checkout
- Product and stock management
- Dashboard and transaction history
- Local offline persistence
- Responsive mobile/tablet/desktop UI

## Release status
Web build: production build verified. Android debug APK: installable build verified by GitHub Actions. Supabase schema: multi-tenant RLS and transaction-hardening foundation available in `supabase/schema.sql`.

## Production hardening still required
Supabase Auth/live synchronization, native camera barcode, thermal Bluetooth/USB printer, real QRIS gateway, cash closing/opname, signed production AAB/APK, Play Store compliance, and device-level acceptance testing.

## KASIRA Professional POS v0.4.2

KASIRA sekarang memiliki fondasi POS profesional yang dapat berjalan offline dan siap dikembangkan menjadi SaaS/cloud.

### Modul aktif
- Executive Dashboard: omzet, transaksi, produk, pelanggan, grafik 7 hari, peringatan stok.
- Smart POS: pencarian SKU/barcode, kategori, keranjang, pelanggan/member, diskon, pajak, multi-metode pembayaran.
- Checkout profesional: Tunai, Kartu, QRIS, Transfer, perhitungan kembalian dan struk.
- Produk & katalog: SKU, barcode, kategori, harga jual, HPP, stok minimum, unit, edit/hapus.
- Inventory Control: stok minimum, indikator restock, stock opname/penyesuaian.
- Pembelian: supplier, invoice, penerimaan barang, HPP dan penambahan stok otomatis.
- CRM & Loyalty: member, poin, kontak, total belanja.
- Sales Ledger: riwayat transaksi dan status pembayaran.
- Business Intelligence: omzet, laba kotor berbasis HPP, ticket size, distribusi pembayaran, nilai persediaan.
- Backup/restore JSON dan pengaturan identitas toko/pajak/struk.
- PWA + Capacitor Android dengan app id `com.kasira.pos`.
- Supabase PostgreSQL + RLS multi-tenant foundation tersedia di `supabase/schema.sql`.

### Enterprise roadmap
Native camera barcode, thermal Bluetooth/USB printer, real QRIS payment integration, live Supabase Auth/sync, offline outbox synchronization, production signing, Play Store release hardening, subscription SaaS, and multi-outlet operations.
