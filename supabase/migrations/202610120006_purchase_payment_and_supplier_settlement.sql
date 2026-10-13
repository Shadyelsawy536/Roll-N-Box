-- Purchase payment method and atomic supplier settlement.
alter table public.purchase_invoices add column if not exists payment_method text not null default 'credit';
alter table public.purchase_invoices drop constraint if exists purchase_invoices_payment_method_check;
alter table public.purchase_invoices add constraint purchase_invoices_payment_method_check check (payment_method in ('cash','card','instapay','wallet','credit'));
alter table public.cash_transactions drop constraint if exists cash_transactions_payment_method_check;
alter table public.cash_transactions add constraint cash_transactions_payment_method_check check (payment_method in ('cash','card','instapay','wallet','bank_transfer','cheque','other'));
alter table public.expenses drop constraint if exists expenses_payment_method_check;
alter table public.expenses add constraint expenses_payment_method_check check (payment_method in ('cash','card','instapay','wallet','bank_transfer','cheque','other'));
drop function if exists public.post_purchase_invoice(uuid,uuid,text,timestamptz,text,jsonb);
CREATE OR REPLACE FUNCTION public.post_purchase_invoice(p_warehouse_id uuid, p_supplier_id uuid, p_supplier_invoice_number text, p_invoice_date timestamp with time zone, p_notes text, p_items jsonb, p_payment_method text, p_cashbox_id uuid DEFAULT NULL::uuid, p_due_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_owner uuid := auth.uid(); v_invoice_id uuid; v_invoice_number bigint; v_item jsonb;
  v_product_id uuid; v_qty numeric(14,3); v_cost numeric(14,2); v_discount numeric(14,2); v_tax numeric(14,2); v_line numeric(14,2);
  v_subtotal numeric(14,2):=0; v_discounts numeric(14,2):=0; v_taxes numeric(14,2):=0; v_total numeric(14,2):=0;
  v_payment_status text; v_paid_total numeric(14,2); v_cash_transaction_id uuid;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_payment_method is null or p_payment_method not in ('cash','card','instapay','wallet','credit') then raise exception 'Invalid purchase payment method'; end if;
  if not exists(select 1 from public.warehouses where id=p_warehouse_id and owner_id=v_owner and is_active) then raise exception 'Invalid warehouse'; end if;
  if p_supplier_id is not null and not exists(select 1 from public.suppliers where id=p_supplier_id and owner_id=v_owner and is_active) then raise exception 'Invalid supplier'; end if;
  if p_payment_method='credit' then
    if p_supplier_id is null then raise exception 'Select a supplier for a credit invoice'; end if;
    if p_cashbox_id is not null then raise exception 'Credit invoices cannot deduct from a cashbox'; end if;
  elsif p_cashbox_id is null or not exists(select 1 from public.cashboxes where id=p_cashbox_id and owner_id=v_owner and is_active) then
    raise exception 'Select an active cashbox for a paid invoice';
  end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Invoice requires items'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    begin
      v_product_id := (v_item->>'product_id')::uuid; v_qty := (v_item->>'quantity')::numeric;
      v_cost := (v_item->>'unit_cost')::numeric; v_discount := coalesce((v_item->>'discount_amount')::numeric,0);
      v_tax := coalesce((v_item->>'tax_amount')::numeric,0);
    exception when others then raise exception 'Invalid item data'; end;
    if v_qty<=0 or v_cost<0 or v_discount<0 or v_tax<0 then raise exception 'Invalid quantity or amount'; end if;
    if not exists(select 1 from public.products where id=v_product_id and owner_id=v_owner and is_active) then raise exception 'Invalid product'; end if;
    v_line := round(v_qty*v_cost,2)-v_discount+v_tax;
    if v_line<0 then raise exception 'Discount exceeds line value'; end if;
    v_subtotal := v_subtotal+round(v_qty*v_cost,2); v_discounts := v_discounts+v_discount; v_taxes := v_taxes+v_tax;
  end loop;
  v_total := v_subtotal-v_discounts+v_taxes;
  if v_total<0 then raise exception 'Negative invoice total'; end if;
  v_payment_status := case when p_payment_method='credit' and v_total>0 then 'unpaid' else 'paid' end;
  v_paid_total := case when v_payment_status='paid' then v_total else 0 end;
  insert into public.purchase_invoices(owner_id,supplier_id,warehouse_id,supplier_invoice_number,invoice_date,due_date,status,payment_status,payment_method,subtotal,discount_total,tax_total,total,paid_total,notes)
  values(v_owner,p_supplier_id,p_warehouse_id,nullif(trim(p_supplier_invoice_number),''),coalesce(p_invoice_date,now()),p_due_date,'posted',v_payment_status,p_payment_method,v_subtotal,v_discounts,v_taxes,v_total,v_paid_total,nullif(trim(p_notes),'')) returning id,invoice_number into v_invoice_id,v_invoice_number;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid; v_qty := (v_item->>'quantity')::numeric;
    v_cost := (v_item->>'unit_cost')::numeric; v_discount := coalesce((v_item->>'discount_amount')::numeric,0);
    v_tax := coalesce((v_item->>'tax_amount')::numeric,0); v_line := round(v_qty*v_cost,2)-v_discount+v_tax;
    insert into public.purchase_invoice_items(owner_id,invoice_id,product_id,quantity,unit_cost,discount_amount,tax_amount,line_total) values(v_owner,v_invoice_id,v_product_id,v_qty,v_cost,v_discount,v_tax,v_line);
    insert into public.stock_movements(owner_id,product_id,warehouse_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,notes) values(v_owner,v_product_id,p_warehouse_id,'purchase',v_qty,v_cost,'purchase_invoice',v_invoice_id,'Purchase invoice '||v_invoice_number::text);
  end loop;
  if v_payment_status='paid' and v_total>0 then
    insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,supplier_id,reference_type,reference_id,transaction_date,notes)
    values(v_owner,p_cashbox_id,'supplier_payment',v_total,p_payment_method,p_supplier_id,'purchase_invoice',v_invoice_id,coalesce(p_invoice_date,now()),'Payment for purchase invoice '||v_invoice_number::text)
    returning id into v_cash_transaction_id;
  end if;
  return jsonb_build_object('invoice_id',v_invoice_id,'invoice_number',v_invoice_number,'subtotal',v_subtotal,'discount_total',v_discounts,'tax_total',v_taxes,'total',v_total,'status','posted','payment_method',p_payment_method,'payment_status',v_payment_status,'paid_total',v_paid_total,'cash_transaction_id',v_cash_transaction_id);
end;
$function$

CREATE OR REPLACE FUNCTION public.post_supplier_payment(p_supplier_id uuid, p_purchase_invoice_id uuid, p_cashbox_id uuid, p_amount numeric, p_payment_method text, p_transaction_date timestamp with time zone, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_owner uuid := auth.uid(); v_invoice public.purchase_invoices%rowtype; v_remaining numeric(14,2);
  v_tx_id uuid; v_new_paid numeric(14,2); v_new_status text;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_supplier_id is null or not exists(select 1 from public.suppliers where id=p_supplier_id and owner_id=v_owner and is_active) then raise exception 'Select a valid supplier'; end if;
  if p_purchase_invoice_id is null then raise exception 'Select a purchase invoice to settle'; end if;
  if p_cashbox_id is null or not exists(select 1 from public.cashboxes where id=p_cashbox_id and owner_id=v_owner and is_active) then raise exception 'Select an active cashbox'; end if;
  if p_payment_method is null or p_payment_method not in ('cash','card','instapay','wallet') then raise exception 'Invalid payment method'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Amount must be greater than zero'; end if;
  select * into v_invoice from public.purchase_invoices where id=p_purchase_invoice_id and owner_id=v_owner and supplier_id=p_supplier_id and status='posted' for update;
  if not found then raise exception 'Purchase invoice not found for this supplier'; end if;
  v_remaining := round(v_invoice.total-v_invoice.paid_total,2);
  if v_remaining<=0 then raise exception 'This invoice is already paid'; end if;
  if p_amount>v_remaining then raise exception 'Payment exceeds invoice outstanding balance'; end if;
  v_new_paid := round(v_invoice.paid_total+p_amount,2);
  v_new_status := case when v_new_paid>=v_invoice.total then 'paid' else 'partial' end;
  insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,supplier_id,reference_type,reference_id,transaction_date,notes)
  values(v_owner,p_cashbox_id,'supplier_payment',p_amount,p_payment_method,p_supplier_id,'purchase_invoice',p_purchase_invoice_id,coalesce(p_transaction_date,now()),coalesce(nullif(trim(coalesce(p_notes,'')),''),'Supplier payment for purchase invoice '||v_invoice.invoice_number::text))
  returning id into v_tx_id;
  update public.purchase_invoices set paid_total=v_new_paid,payment_status=v_new_status where id=p_purchase_invoice_id and owner_id=v_owner;
  return jsonb_build_object('transaction_id',v_tx_id,'invoice_id',p_purchase_invoice_id,'amount',p_amount,'paid_total',v_new_paid,'outstanding',round(v_invoice.total-v_new_paid,2),'payment_status',v_new_status,'status','posted');
end;
$function$

revoke all on function public.post_purchase_invoice(uuid,uuid,text,timestamptz,text,jsonb,text,uuid,date) from public,anon;
grant execute on function public.post_purchase_invoice(uuid,uuid,text,timestamptz,text,jsonb,text,uuid,date) to authenticated;
revoke all on function public.post_supplier_payment(uuid,uuid,uuid,numeric,text,timestamptz,text) from public,anon;
grant execute on function public.post_supplier_payment(uuid,uuid,uuid,numeric,text,timestamptz,text) to authenticated;
