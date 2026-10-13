-- Phase 3: cheque settlement and installment schedules/payments.
create table if not exists public.financial_operation_requests (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  request_key uuid not null,
  operation_type text not null,
  result jsonb,
  created_at timestamptz not null default now(),
  unique(owner_id, request_key)
);
alter table public.financial_operation_requests enable row level security;
drop policy if exists financial_operation_requests_owner_all on public.financial_operation_requests;
create policy financial_operation_requests_owner_all on public.financial_operation_requests
  for all to authenticated using ((select auth.uid())=owner_id)
  with check ((select auth.uid())=owner_id);

create or replace function public.create_installment_schedule(
  p_party_type text,
  p_reference_id uuid,
  p_first_due_date date,
  p_count integer,
  p_notes text
) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_party_id uuid;
  v_reference_type text;
  v_remaining numeric(14,2);
  v_amount numeric(14,2);
  v_paid numeric(14,2);
  v_total numeric(14,2);
  v_due date;
  v_id uuid;
  v_ids uuid[] := '{}';
  i integer;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_party_type not in ('customer','supplier') then raise exception 'Invalid party type'; end if;
  if p_count is null or p_count<1 or p_count>60 then raise exception 'Installment count must be between 1 and 60'; end if;
  if p_first_due_date is null then raise exception 'Choose the first due date'; end if;

  if p_party_type='customer' then
    select customer_id,total,paid_total into v_party_id,v_total,v_paid
    from public.sales_invoices where id=p_reference_id and owner_id=v_owner and status='posted' for update;
    v_reference_type := 'sales_invoice';
  else
    select supplier_id,total,paid_total into v_party_id,v_total,v_paid
    from public.purchase_invoices where id=p_reference_id and owner_id=v_owner and status='posted' for update;
    v_reference_type := 'purchase_invoice';
  end if;
  if not found then raise exception 'Posted invoice not found'; end if;
  if v_party_id is null then raise exception 'Invoice must have a customer or supplier before scheduling installments'; end if;
  v_remaining := round(v_total-coalesce(v_paid,0),2);
  if v_remaining<=0 then raise exception 'Invoice has no outstanding balance'; end if;
  if exists(select 1 from public.installments where owner_id=v_owner and reference_type=v_reference_type and reference_id=p_reference_id and status in ('pending','partial','overdue')) then
    raise exception 'An active installment schedule already exists for this invoice';
  end if;

  for i in 1..p_count loop
    if i<p_count then v_amount := round(v_remaining/p_count,2); else v_amount := v_remaining - (round(v_remaining/p_count,2)*(p_count-1)); end if;
    v_due := (p_first_due_date + ((i-1)||' months')::interval)::date;
    insert into public.installments(owner_id,party_type,party_id,reference_type,reference_id,due_date,amount,paid_amount,status,notes)
    values(v_owner,p_party_type,v_party_id,v_reference_type,p_reference_id,v_due,v_amount,0,'pending',nullif(trim(coalesce(p_notes,'')),''))
    returning id into v_id;
    v_ids := array_append(v_ids,v_id);
  end loop;
  return jsonb_build_object('installment_ids',to_jsonb(v_ids),'count',p_count,'scheduled_amount',v_remaining,'status','created');
end;
$$;

create or replace function public.post_installment_payment(
  p_installment_id uuid,
  p_cashbox_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_transaction_date timestamptz,
  p_idempotency_key uuid
) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_inst public.installments%rowtype;
  v_invoice_total numeric(14,2);
  v_invoice_paid numeric(14,2);
  v_new_paid numeric(14,2);
  v_invoice_status text;
  v_tx_id uuid;
  v_result jsonb;
  v_existing jsonb;
  v_inserted uuid;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null then raise exception 'Request key is required'; end if;
  select result into v_existing from public.financial_operation_requests
    where owner_id=v_owner and request_key=p_idempotency_key;
  if found and v_existing is not null then return v_existing || jsonb_build_object('already_posted',true); end if;

  insert into public.financial_operation_requests(owner_id,request_key,operation_type,result)
  values(v_owner,p_idempotency_key,'installment_payment',null)
  on conflict(owner_id,request_key) do nothing
  returning id into v_inserted;
  if v_inserted is null then
    select result into v_existing from public.financial_operation_requests where owner_id=v_owner and request_key=p_idempotency_key;
    if v_existing is not null then return v_existing || jsonb_build_object('already_posted',true); end if;
    raise exception 'A request with this key is already being processed';
  end if;

  select * into v_inst from public.installments where id=p_installment_id and owner_id=v_owner for update;
  if not found then raise exception 'Installment not found'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Payment must be greater than zero'; end if;
  if p_amount>round(v_inst.amount-v_inst.paid_amount,2) then raise exception 'Payment exceeds installment balance'; end if;
  if p_payment_method is null or p_payment_method not in ('cash','card','instapay','wallet') then raise exception 'Invalid payment method'; end if;
  if not exists(select 1 from public.cashboxes where id=p_cashbox_id and owner_id=v_owner and is_active) then raise exception 'Select an active cashbox'; end if;

  if v_inst.party_type='customer' and v_inst.reference_type='sales_invoice' then
    select total,paid_total into v_invoice_total,v_invoice_paid from public.sales_invoices
      where id=v_inst.reference_id and owner_id=v_owner and customer_id=v_inst.party_id and status='posted' for update;
    if not found then raise exception 'Related sales invoice was not found'; end if;
    if p_amount>round(v_invoice_total-v_invoice_paid,2) then raise exception 'Payment exceeds invoice outstanding balance'; end if;
    v_new_paid := round(v_invoice_paid+p_amount,2);
    v_invoice_status := case when v_new_paid>=v_invoice_total then 'paid' else 'partial' end;
    update public.sales_invoices set paid_total=v_new_paid,payment_status=v_invoice_status where id=v_inst.reference_id and owner_id=v_owner;
    insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,customer_id,reference_type,reference_id,transaction_date,notes)
    values(v_owner,p_cashbox_id,'customer_receipt',p_amount,p_payment_method,v_inst.party_id,'installment',v_inst.id,coalesce(p_transaction_date,now()),'Installment payment for sales invoice')
    returning id into v_tx_id;
  elsif v_inst.party_type='supplier' and v_inst.reference_type='purchase_invoice' then
    select total,paid_total into v_invoice_total,v_invoice_paid from public.purchase_invoices
      where id=v_inst.reference_id and owner_id=v_owner and supplier_id=v_inst.party_id and status='posted' for update;
    if not found then raise exception 'Related purchase invoice was not found'; end if;
    if p_amount>round(v_invoice_total-v_invoice_paid,2) then raise exception 'Payment exceeds invoice outstanding balance'; end if;
    v_new_paid := round(v_invoice_paid+p_amount,2);
    v_invoice_status := case when v_new_paid>=v_invoice_total then 'paid' else 'partial' end;
    update public.purchase_invoices set paid_total=v_new_paid,payment_status=v_invoice_status where id=v_inst.reference_id and owner_id=v_owner;
    insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,supplier_id,reference_type,reference_id,transaction_date,notes)
    values(v_owner,p_cashbox_id,'supplier_payment',p_amount,p_payment_method,v_inst.party_id,'installment',v_inst.id,coalesce(p_transaction_date,now()),'Installment payment for purchase invoice')
    returning id into v_tx_id;
  else
    raise exception 'Installment reference type does not match a supported invoice';
  end if;

  update public.installments set paid_amount=round(paid_amount+p_amount,2),
    status=case when round(paid_amount+p_amount,2)>=amount then 'paid' else 'partial' end
  where id=v_inst.id and owner_id=v_owner;
  v_result := jsonb_build_object('installment_id',v_inst.id,'transaction_id',v_tx_id,'paid_amount',round(v_inst.paid_amount+p_amount,2),'status',case when round(v_inst.paid_amount+p_amount,2)>=v_inst.amount then 'paid' else 'partial' end);
  update public.financial_operation_requests set result=v_result where owner_id=v_owner and request_key=p_idempotency_key;
  return v_result;
end;
$$;

create or replace function public.settle_cheque(
  p_cheque_id uuid,
  p_cashbox_id uuid,
  p_payment_method text,
  p_settlement_date timestamptz
) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_cheque public.cheques%rowtype;
  v_tx_id uuid;
  v_type text;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  select * into v_cheque from public.cheques where id=p_cheque_id and owner_id=v_owner for update;
  if not found then raise exception 'Cheque not found'; end if;
  if v_cheque.status='cleared' then
    select id into v_tx_id from public.cash_transactions where owner_id=v_owner and reference_type='cheque' and reference_id=v_cheque.id limit 1;
    return jsonb_build_object('cheque_id',v_cheque.id,'transaction_id',v_tx_id,'status','cleared','already_settled',true);
  end if;
  if v_cheque.status not in ('pending','deposited') then raise exception 'Only pending or deposited cheques can be settled'; end if;
  if not exists(select 1 from public.cashboxes where id=p_cashbox_id and owner_id=v_owner and is_active) then raise exception 'Select an active cashbox'; end if;
  if p_payment_method is null or p_payment_method not in ('cash','card','instapay','wallet') then raise exception 'Invalid payment method'; end if;
  v_type := case
    when v_cheque.direction='received' and v_cheque.party_type='customer' then 'customer_receipt'
    when v_cheque.direction='issued' and v_cheque.party_type='supplier' then 'supplier_payment'
    when v_cheque.direction='received' then 'other_receipt'
    else 'other_payment'
  end;
  insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,customer_id,supplier_id,reference_type,reference_id,transaction_date,notes)
  values(v_owner,p_cashbox_id,v_type,v_cheque.amount,p_payment_method,
    case when v_type='customer_receipt' then v_cheque.party_id else null end,
    case when v_type='supplier_payment' then v_cheque.party_id else null end,
    'cheque',v_cheque.id,coalesce(p_settlement_date,now()),'Settlement of cheque #'||v_cheque.cheque_number)
  returning id into v_tx_id;
  update public.cheques set status='cleared' where id=v_cheque.id and owner_id=v_owner;
  return jsonb_build_object('cheque_id',v_cheque.id,'transaction_id',v_tx_id,'status','cleared','already_settled',false);
end;
$$;

revoke all on function public.create_installment_schedule(text,uuid,date,integer,text) from public, anon;
grant execute on function public.create_installment_schedule(text,uuid,date,integer,text) to authenticated;
revoke all on function public.post_installment_payment(uuid,uuid,numeric,text,timestamptz,uuid) from public, anon;
grant execute on function public.post_installment_payment(uuid,uuid,numeric,text,timestamptz,uuid) to authenticated;
revoke all on function public.settle_cheque(uuid,uuid,text,timestamptz) from public, anon;
grant execute on function public.settle_cheque(uuid,uuid,text,timestamptz) to authenticated;
