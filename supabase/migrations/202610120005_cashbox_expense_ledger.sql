-- Cashbox balances are derived from the transaction ledger.
create or replace view public.cashbox_balances
with (security_invoker = true) as
select c.id as cashbox_id, c.owner_id, c.name, c.opening_balance, c.is_default, c.is_active, c.created_at,
  coalesce(sum(case
    when t.transaction_type in ('customer_receipt','other_receipt','cash_transfer_in') then t.amount
    when t.transaction_type in ('supplier_payment','expense','other_payment','cash_transfer_out') then -t.amount
    else 0 end),0)::numeric(14,2) as transaction_balance,
  (c.opening_balance + coalesce(sum(case
    when t.transaction_type in ('customer_receipt','other_receipt','cash_transfer_in') then t.amount
    when t.transaction_type in ('supplier_payment','expense','other_payment','cash_transfer_out') then -t.amount
    else 0 end),0))::numeric(14,2) as balance
from public.cashboxes c
left join public.cash_transactions t on t.cashbox_id=c.id and t.owner_id=c.owner_id
group by c.id;
grant select on public.cashbox_balances to authenticated;

create or replace function public.post_expense(p_cashbox_id uuid,p_category text,p_description text,p_amount numeric,p_expense_date date,p_payment_method text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_owner uuid := auth.uid(); v_expense_id uuid; v_cash_transaction_id uuid;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_category is null or length(trim(p_category))=0 then raise exception 'Expense category is required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
  if p_payment_method is null or p_payment_method not in ('cash','card','bank_transfer','cheque','other') then raise exception 'Invalid payment method'; end if;
  if p_cashbox_id is not null and not exists(select 1 from public.cashboxes c where c.id=p_cashbox_id and c.owner_id=v_owner and c.is_active) then raise exception 'Invalid cashbox'; end if;
  insert into public.expenses(owner_id,cashbox_id,category,description,amount,expense_date,payment_method)
  values(v_owner,p_cashbox_id,trim(p_category),nullif(trim(coalesce(p_description,'')),''),p_amount,coalesce(p_expense_date,current_date),p_payment_method)
  returning id into v_expense_id;
  if p_cashbox_id is not null then
    insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,reference_type,reference_id,transaction_date,notes)
    values(v_owner,p_cashbox_id,'expense',p_amount,p_payment_method,'expense',v_expense_id,coalesce(p_expense_date,current_date)::timestamptz,
      'Expense: '||trim(p_category)||case when nullif(trim(coalesce(p_description,'')),'') is null then '' else ' - '||trim(p_description) end)
    returning id into v_cash_transaction_id;
  end if;
  return jsonb_build_object('expense_id',v_expense_id,'cash_transaction_id',v_cash_transaction_id,'amount',p_amount,'status','posted');
end;
$$;

create or replace function public.post_cash_movement(p_cashbox_id uuid,p_direction text,p_amount numeric,p_payment_method text,p_transaction_date timestamptz,p_notes text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_owner uuid := auth.uid(); v_id uuid; v_type text;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_cashbox_id is null or not exists(select 1 from public.cashboxes c where c.id=p_cashbox_id and c.owner_id=v_owner and c.is_active) then raise exception 'Select an active cashbox'; end if;
  if p_direction not in ('receipt','payment') then raise exception 'Invalid direction'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
  if p_payment_method is null or p_payment_method not in ('cash','card','bank_transfer','cheque','other') then raise exception 'Invalid payment method'; end if;
  v_type := case when p_direction='receipt' then 'other_receipt' else 'other_payment' end;
  insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,transaction_date,notes)
  values(v_owner,p_cashbox_id,v_type,p_amount,p_payment_method,coalesce(p_transaction_date,now()),nullif(trim(coalesce(p_notes,'')),''))
  returning id into v_id;
  return jsonb_build_object('transaction_id',v_id,'transaction_type',v_type,'amount',p_amount,'status','posted');
end;
$$;
revoke all on function public.post_expense(uuid,text,text,numeric,date,text) from public,anon;
grant execute on function public.post_expense(uuid,text,text,numeric,date,text) to authenticated;
revoke all on function public.post_cash_movement(uuid,text,numeric,text,timestamptz,text) from public,anon;
grant execute on function public.post_cash_movement(uuid,text,numeric,text,timestamptz,text) to authenticated;
