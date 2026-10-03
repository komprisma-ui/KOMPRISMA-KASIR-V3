# KASIRA POS MVP
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

## Roadmap
Authentication, cloud database, multi-outlet, purchasing, suppliers, customers, reports, printer/QRIS integrations, audit log and online/offline sync.

## KASIRA Professional POS v0.3

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

### Roadmap enterprise
Barcode camera native, printer thermal Bluetooth/USB, QRIS payment integration, retur/refund, kas masuk/keluar, supplier master, role & permission, multi-outlet, audit log, cloud sync, authentication, subscription SaaS, dan Play Store release hardening.
