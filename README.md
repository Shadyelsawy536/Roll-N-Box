# Inv Management

A personal, online-first inventory and shop management system built with Flutter and Supabase.

## Planned modules

- Dashboard and business overview
- Products, categories, units, and stock movements (no barcode)
- Multiple warehouses, stock transfers, stock counts, and adjustments
- Sales invoices, sales returns, quotations, and customer reservations
- Purchase invoices, purchase returns, and supplier price history
- Customer accounts, supplier accounts, opening balances, and statements
- Cashboxes, receipts, payments, expenses, installments, and cheque tracking
- Cost of goods sold, gross profit, net profit, and inventory valuation
- Reports, Excel export, printable invoice layouts, user roles, audit trail, and backups

## Stack

- Flutter: Android, iOS, and Web from one codebase
- Supabase Auth
- PostgreSQL with Row Level Security
- Database functions for atomic stock and financial transactions

## Run locally

1. Install Flutter and Git.
2. Run `flutter pub get`.
3. Configure the Supabase URL and publishable key using Dart defines.
4. Run the web app:

```powershell
flutter build apk --release --dart-define=SUPABASE_URL=https://bnnqbrqlgubodkauguoj.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_TBse2DaqNLO5p2UqPkdnmQ_7H6tjcI3
```

For Android, use the same Dart defines with `flutter run` and your connected device.

The publishable key is intended for client applications; never place a Supabase secret or service-role key in Flutter code. All exposed tables must use suitable RLS policies.

## Project status

The repository currently contains the initial application scaffold. Business modules and the database migration will be implemented incrementally and tested as they are added.
