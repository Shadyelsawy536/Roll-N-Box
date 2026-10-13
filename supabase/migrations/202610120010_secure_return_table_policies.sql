-- Lock down return tables to authenticated owner-scoped reads and inserts only.
revoke all on table public.sales_returns, public.sales_return_items, public.purchase_returns, public.purchase_return_items from public, anon;
grant select, insert on table public.sales_returns, public.sales_return_items, public.purchase_returns, public.purchase_return_items to authenticated;
drop policy if exists sales_returns_owner_all on public.sales_returns;
drop policy if exists sales_return_items_owner_all on public.sales_return_items;
drop policy if exists purchase_returns_owner_all on public.purchase_returns;
drop policy if exists purchase_return_items_owner_all on public.purchase_return_items;
create policy sales_returns_owner_select on public.sales_returns for select to authenticated using ((select auth.uid()) = owner_id);
create policy sales_returns_owner_insert on public.sales_returns for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy sales_return_items_owner_select on public.sales_return_items for select to authenticated using ((select auth.uid()) = owner_id);
create policy sales_return_items_owner_insert on public.sales_return_items for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy purchase_returns_owner_select on public.purchase_returns for select to authenticated using ((select auth.uid()) = owner_id);
create policy purchase_returns_owner_insert on public.purchase_returns for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy purchase_return_items_owner_select on public.purchase_return_items for select to authenticated using ((select auth.uid()) = owner_id);
create policy purchase_return_items_owner_insert on public.purchase_return_items for insert to authenticated with check ((select auth.uid()) = owner_id);
