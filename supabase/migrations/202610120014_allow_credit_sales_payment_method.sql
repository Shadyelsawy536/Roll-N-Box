do $$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'post_sales_invoice';

  if v_definition is null then
    raise exception 'post_sales_invoice function not found';
  end if;

  v_updated := replace(
    v_definition,
    'if p_payment_method is null or p_payment_method not in (''cash'',''card'',''instapay'',''wallet'') then raise exception ''Invalid payment method''; end if;',
    'if p_payment_method is null or p_payment_method not in (''cash'',''card'',''instapay'',''wallet'',''credit'') then raise exception ''Invalid payment method''; end if; if p_payment_method = ''credit'' and v_paid > 0 then raise exception ''Credit sales invoices cannot collect payment at creation''; end if;'
  );

  if v_updated = v_definition then
    raise exception 'Could not locate the payment-method validation in post_sales_invoice';
  end if;

  execute v_updated;
end $$;
