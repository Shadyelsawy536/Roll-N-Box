# Phase 4–5 verification report

Updated: 2026-10-12

## Implemented and verified

- Added `202610120020_enforce_owner_scoped_foreign_keys.sql` and applied it to Supabase project `bnnqbrqlgubodkauguoj`.
- Replaced 42 single-column public-table relationships with owner-scoped composite foreign keys; all are validated. The audited relationships had zero existing cross-owner rows before the migration.
- The two reporting views, `stock_balances` and `cashbox_balances`, already use `security_invoker=true`.
- RLS negative test ran with an unrecognized user claim: selecting another owner's product returned zero rows, and inserting a row with another owner's `owner_id` was blocked.
- Rollback-only end-to-end test passed for purchase invoice, credit sale, customer receipt, sales return, purchase return, warehouse transfer, transfer retry, invoice paid-total update, and stock totals. The test used a nested rollback block; follow-up query confirmed zero QA fixtures persisted.
- Reports page now has PDF and XLSX export actions. XLSX includes summary, sales, purchases, expenses, returns, and inventory sheets.
- Products, customers, and suppliers now have server-side search and 50-row pagination.
- GitHub Actions web build and Dart analysis succeeded on commit `332bccf1a70770a68b159cb41a5bc9a82e91836c`.

## Important remaining risks / follow-up

- **Direct DML grants remain on several ledger tables** for `authenticated`. RLS limits rows to the current owner, but a signed-in owner can still attempt direct writes to their own ledger tables and bypass posting RPC business rules. Do not mark write-permission hardening complete until posting RPCs are audited, moved to a safe privilege model, and direct ledger writes are revoked without breaking the app.
- The negative test used an unrecognized user identity because the project currently has one business owner. A full two-real-account cross-tenant test remains pending.
- Invoice and return RPCs currently lack idempotency request keys. The stock-transfer retry path was tested and passed; invoice/return retry protection is not verified as implemented.
- Reports currently load bounded result sets (for example, up to 1,000 invoices/expenses and 2,000 movement rows), and account statements have a 5,000-row cap. Exported reports may therefore be incomplete for unusually large periods until report queries are changed to fetch all pages.
- PDF output currently uses English labels to avoid unsupported Arabic glyph rendering with the default embedded PDF font. Add and test an Arabic-capable embedded font before treating PDF output as localized/production-ready.
- Supabase Security Advisor still warns that leaked-password protection is disabled. Enable it after reviewing the effect on existing sign-in flows.
- A full multi-account authorization test and manual UI verification on web/Android are still required before production use.
