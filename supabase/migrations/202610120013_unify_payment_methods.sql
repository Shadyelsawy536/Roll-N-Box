do $$
declare
  r record;
  v_definition text;
  v_updated text;
begin
  for r in
    select p.oid, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('post_sales_invoice','post_cash_movement','post_expense','post_sales_return','post_purchase_return')
  loop
    v_definition := pg_get_functiondef(r.oid);
    v_updated := replace(
      v_definition,
      '(''cash'',''card'',''bank_transfer'',''cheque'',''other'')',
      '(''cash'',''card'',''instapay'',''wallet'')'
    );
    if v_updated <> v_definition then
      execute v_updated;
    end if;
  end loop;
end $$;

do $$
declare
  r record;
begin
  for r in
    select c.conname, c.conrelid::regclass as table_name
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname in ('sales_returns','purchase_returns')
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%payment_method%'
  loop
    execute format('alter table %s drop constraint %I', r.table_name, r.conname);
  end loop;
end $$;

alter table public.sales_returns
  add constraint sales_returns_payment_method_check
  check (payment_method in ('cash','card','instapay','wallet','bank_transfer','cheque','other'));

alter table public.purchase_returns
  add constraint purchase_returns_payment_method_check
  check (payment_method in ('cash','card','instapay','wallet','bank_transfer','cheque','other'));
