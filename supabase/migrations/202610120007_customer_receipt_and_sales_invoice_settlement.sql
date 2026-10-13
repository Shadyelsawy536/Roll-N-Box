-- Atomic customer receipt allocation to a posted sales invoice.
create or replace function public.post_customer_receipt(
  p_customer_id uuid,
  p_sales_invoice_id uuid,
  p_cashbox_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_transaction_date timestamptz,
  p_notes text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_owner uuid := auth.uid();
  v_invoice public.sales_invoices%rowtype;
  v_remaining numeric(14,2);
  v_new_paid numeric(14,2);
  v_new_status text;
  v_tx_id uuid;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_customer_id is null or not exists (
    select 1 from public.customers where id = p_customer_id and owner_id = v_owner
  ) then raise exception 'Select a valid customer'; end if;
  if p_sales_invoice_id is null then raise exception 'Select a sales invoice to settle'; end if;
  if p_cashbox_id is null or not exists (
    select 1 from public.cashboxes where id = p_cashbox_id and owner_id = v_owner and is_active
  ) then raise exception 'Select an active cashbox'; end if;
  if p_payment_method is null or p_payment_method not in ('cash','card','instapay','wallet') then
    raise exception 'Invalid payment method';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  select * into v_invoice from public.sales_invoices
  where id = p_sales_invoice_id and owner_id = v_owner
    and customer_id = p_customer_id and status = 'posted'
  for update;
  if not found then raise exception 'Sales invoice not found for this customer'; end if;
  v_remaining := round(v_invoice.total - v_invoice.paid_total, 2);
  if v_remaining <= 0 then raise exception 'This invoice is already paid'; end if;
  if p_amount > v_remaining then raise exception 'Receipt exceeds invoice outstanding balance'; end if;
  v_new_paid := round(v_invoice.paid_total + p_amount, 2);
  v_new_status := case when v_new_paid >= v_invoice.total then 'paid' else 'partial' end;
  insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,customer_id,reference_type,reference_id,transaction_date,notes)
  values(v_owner,p_cashbox_id,'customer_receipt',p_amount,p_payment_method,p_customer_id,'sales_invoice',p_sales_invoice_id,coalesce(p_transaction_date,now()),coalesce(nullif(trim(coalesce(p_notes,'')),''),'Customer receipt for sales invoice '||v_invoice.invoice_number::text))
  returning id into v_tx_id;
  update public.sales_invoices set paid_total=v_new_paid,payment_status=v_new_status
  where id=p_sales_invoice_id and owner_id=v_owner;
  return jsonb_build_object('transaction_id',v_tx_id,'invoice_id',p_sales_invoice_id,'amount',p_amount,'paid_total',v_new_paid,'outstanding',round(v_invoice.total-v_new_paid,2),'payment_status',v_new_status,'status','posted');
end;
$function$;
revoke all on function public.post_customer_receipt(uuid,uuid,uuid,numeric,text,timestamptz,text) from public, anon;
grant execute on function public.post_customer_receipt(uuid,uuid,uuid,numeric,text,timestamptz,text) to authenticated;
