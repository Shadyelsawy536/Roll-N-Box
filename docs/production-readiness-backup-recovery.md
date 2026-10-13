# Production Readiness: Backup, Recovery, and Regression Checklist

## Backup policy

This application stores business-critical inventory and accounting records in Supabase. A backup is not considered verified until a restore has been tested.

1. Before every database migration or bulk correction, create a fresh Supabase database backup/export and record the date, project ref, migration name, and operator.
2. Confirm the project's configured automated backup retention in Supabase Dashboard. Do not assume Point-in-Time Recovery (PITR) is enabled; availability and retention depend on the project's plan and settings.
3. Keep a separate encrypted copy of periodic logical exports in access-controlled storage. Never commit database dumps, customer data, credentials, or service-role keys to this repository.
4. Export business-critical tables together with schema and constraints. A CSV-only export is not a full recovery copy because it omits relationships, policies, functions, indexes, and sequences.
5. Restrict backup access to trusted administrators. Treat exports as sensitive financial/customer data.

## Recovery runbook

1. Declare a recovery window and stop business writes where possible.
2. Identify the last known-good backup and the time range of missing/corrupt data.
3. Restore into a separate recovery/staging project first; never overwrite production as the first test.
4. Verify table counts and relationships for products, warehouses, stock movements, sales/purchase invoices and items, returns, cash transactions, expenses, cheques, installments, and audit logs.
5. Reconcile stock by product and warehouse against stock movements; reconcile invoice paid totals against cash transactions; investigate discrepancies rather than silently editing balances.
6. Run authentication/RLS checks with two separate test users and confirm each can only see and mutate its own records.
7. Verify critical RPCs (sales/purchase posting, returns, transfers, installment payments, cheque settlement) on test records and confirm retry attempts do not duplicate ledger entries.
8. Only after sign-off, schedule production restoration. Record recovery point, recovery duration, validation results, and follow-up actions.

## Pre-release regression checklist

- [ ] Sign in/out and session expiry work.
- [ ] A user cannot read or reference another user's customer, supplier, product, warehouse, cashbox, invoice, or stock record.
- [ ] Posting a sales invoice decreases stock exactly once and records the expected cash/receivable.
- [ ] Posting a purchase invoice increases stock exactly once and records the expected cash/payable.
- [ ] Sales and purchase returns cannot exceed quantities originally invoiced/remaining returnable quantities.
- [ ] A warehouse transfer decreases source stock and increases destination stock by equal quantities.
- [ ] Installment payments cannot exceed installment or invoice outstanding balances.
- [ ] Settling the same cheque twice does not create a second cash transaction.
- [ ] Reports reconcile with invoice, return, expense, and cash transaction records.
- [ ] Empty states, slow network, permission errors, and retry actions show clear messages.
- [ ] Desktop and narrow mobile layouts are checked.
- [ ] A restore has been rehearsed in staging.

## Current known gaps

- Idempotency/retry protection still needs review for sales invoices, purchase invoices, and both return-posting RPCs. Do not claim the whole posting workflow is duplicate-safe until those functions are updated and tested.
- Cross-owner foreign-key references and direct client write access to ledger tables need a dedicated security review.
- PDF/Excel export and server-side pagination are not yet verified as implemented.
- Enable Supabase leaked-password protection in the Auth security settings after evaluating the impact on existing users.
