-- Fix credit sales used when converting quotations to invoices.
create or replace function public.post_sales_invoice(
  p_warehouse_id uuid,
  p_customer_id uuid,
  p_invoice_date timestamptz,
  p_due_date date,
  p_notes text,
  p_items jsonb,
  p_paid_amount numeric,
  p_cashbox_id uuid,
  p_payment_method text
)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_owner uuid := auth.uid();
  v_invoice_id uuid;
  v_invoice_number bigint;
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14,3);
  v_requested numeric(14,3);
  v_price numeric(14,2);
  v_cost numeric(14,2);
  v_discount numeric(14,2);
  v_tax numeric(14,2);
  v_line numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_discounts numeric(14,2) := 0;
  v_taxes numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_paid numeric(14,2) := coalesce(p_paid_amount,0);
  v_available numeric(14,3);
  v_tracks_stock boolean;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.warehouses where id=p_warehouse_id and owner_id=v_owner and is_active) then raise exception 'Invalid warehouse'; end if;
  if p_customer_id is not null and not exists(select 1 from public.customers where id=p_customer_id and owner_id=v_owner and is_active) then raise exception 'Invalid customer'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Invoice requires items'; end if;
  if v_paid < 0 then raise exception 'Paid amount cannot be negative'; end if;
  if p_payment_method is null or p_payment_method not in ('cash','card','bank_transfer','cheque','other','credit') then raise exception 'Invalid payment method'; end if;
  if v_paid > 0 and (p_cashbox_id is null or not exists(select 1 from public.cashboxes where id=p_cashbox_id and owner_id=v_owner and is_active)) then raise exception 'Select an active cashbox for the payment'; end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    begin
      v_product_id := (v_item->>'product_id')::uuid;
      v_qty := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'unit_price')::numeric;
      v_discount := coalesce((v_item->>'discount_amount')::numeric,0);
      v_tax := coalesce((v_item->>'tax_amount')::numeric,0);
    exception when others then raise exception 'Invalid item data'; end;
    if v_qty<=0 or v_price<0 or v_discount<0 or v_tax<0 then raise exception 'Invalid quantity or amount'; end if;
    select cost_price,track_stock into v_cost,v_tracks_stock from public.products where id=v_product_id and owner_id=v_owner and is_active;
    if not found then raise exception 'Invalid product'; end if;
    if v_tracks_stock then
      perform pg_advisory_xact_lock(hashtextextended(v_owner::text||':'||p_warehouse_id::text||':'||v_product_id::text,0));
      select coalesce(sum(quantity_delta),0) into v_available from public.stock_movements where owner_id=v_owner and product_id=v_product_id and warehouse_id=p_warehouse_id;
      select coalesce(sum((x->>'quantity')::numeric),0) into v_requested from jsonb_array_elements(p_items) x where x->>'product_id'=v_product_id::text;
      if v_available < v_requested then raise exception 'Insufficient stock for product %. Available: %, requested: %', v_product_id, v_available, v_requested; end if;
    end if;
    v_line := round(v_qty*v_price,2)-v_discount+v_tax;
    if v_line<0 then raise exception 'Discount exceeds line value'; end if;
    v_subtotal := v_subtotal+round(v_qty*v_price,2);
    v_discounts := v_discounts+v_discount;
    v_taxes := v_taxes+v_tax;
  end loop;
  v_total := v_subtotal-v_discounts+v_taxes;
  if v_total<0 or v_paid>v_total then raise exception 'Paid amount cannot exceed invoice total'; end if;

  insert into public.sales_invoices(owner_id,customer_id,warehouse_id,invoice_date,due_date,status,payment_status,subtotal,discount_total,tax_total,total,paid_total,notes)
  values(v_owner,p_customer_id,p_warehouse_id,coalesce(p_invoice_date,now()),p_due_date,'posted',case when v_paid=0 then 'unpaid' when v_paid>=v_total then 'paid' else 'partial' end,v_subtotal,v_discounts,v_taxes,v_total,v_paid,nullif(trim(p_notes),''))
  returning id,invoice_number into v_invoice_id,v_invoice_number;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;
    v_price := (v_item->>'unit_price')::numeric;
    v_discount := coalesce((v_item->>'discount_amount')::numeric,0);
    v_tax := coalesce((v_item->>'tax_amount')::numeric,0);
    select cost_price,track_stock into v_cost,v_tracks_stock from public.products where id=v_product_id and owner_id=v_owner;
    v_line := round(v_qty*v_price,2)-v_discount+v_tax;
    insert into public.sales_invoice_items(owner_id,invoice_id,product_id,description,quantity,unit_price,unit_cost,discount_amount,tax_amount,line_total)
    select v_owner,v_invoice_id,v_product_id,p.name,v_qty,v_price,v_cost,v_discount,v_tax,v_line from public.products p where p.id=v_product_id and p.owner_id=v_owner;
    if v_tracks_stock then
      insert into public.stock_movements(owner_id,product_id,warehouse_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,notes)
      values(v_owner,v_product_id,p_warehouse_id,'sale',-v_qty,v_cost,'sales_invoice',v_invoice_id,'Sales invoice '||v_invoice_number::text);
    end if;
  end loop;
  if v_paid>0 then
    insert into public.cash_transactions(owner_id,cashbox_id,transaction_type,amount,payment_method,customer_id,reference_type,reference_id,transaction_date,notes)
    values(v_owner,p_cashbox_id,'customer_receipt',v_paid,p_payment_method,p_customer_id,'sales_invoice',v_invoice_id,coalesce(p_invoice_date,now()),'Payment for sales invoice '||v_invoice_number::text);
  end if;
  return jsonb_build_object('invoice_id',v_invoice_id,'invoice_number',v_invoice_number,'subtotal',v_subtotal,'discount_total',v_discounts,'tax_total',v_taxes,'total',v_total,'paid_total',v_paid,'payment_status',case when v_paid=0 then 'unpaid' when v_paid>=v_total then 'paid' else 'partial' end,'status','posted');
end;
$$;
revoke all on function public.post_sales_invoice(uuid,uuid,timestamptz,date,text,jsonb,numeric,uuid,text) from public,anon;
grant execute on function public.post_sales_invoice(uuid,uuid,timestamptz,date,text,jsonb,numeric,uuid,text) to authenticated;
