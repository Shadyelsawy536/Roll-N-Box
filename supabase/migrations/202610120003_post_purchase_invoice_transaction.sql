create or replace function public.post_purchase_invoice(p_warehouse_id uuid,p_supplier_id uuid,p_supplier_invoice_number text,p_invoice_date timestamptz,p_notes text,p_items jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_owner uuid := auth.uid(); v_invoice_id uuid; v_invoice_number bigint; v_item jsonb;
  v_product_id uuid; v_qty numeric(14,3); v_cost numeric(14,2); v_discount numeric(14,2); v_tax numeric(14,2); v_line numeric(14,2);
  v_subtotal numeric(14,2):=0; v_discounts numeric(14,2):=0; v_taxes numeric(14,2):=0; v_total numeric(14,2):=0;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.warehouses where id=p_warehouse_id and owner_id=v_owner and is_active) then raise exception 'Invalid warehouse'; end if;
  if p_supplier_id is not null and not exists(select 1 from public.suppliers where id=p_supplier_id and owner_id=v_owner and is_active) then raise exception 'Invalid supplier'; end if;
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
  insert into public.purchase_invoices(owner_id,supplier_id,warehouse_id,supplier_invoice_number,invoice_date,status,payment_status,subtotal,discount_total,tax_total,total,paid_total,notes)
  values(v_owner,p_supplier_id,p_warehouse_id,nullif(trim(p_supplier_invoice_number),''),coalesce(p_invoice_date,now()),'posted',case when v_total=0 then 'paid' else 'unpaid' end,v_subtotal,v_discounts,v_taxes,v_total,0,nullif(trim(p_notes),'')) returning id,invoice_number into v_invoice_id,v_invoice_number;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid; v_qty := (v_item->>'quantity')::numeric;
    v_cost := (v_item->>'unit_cost')::numeric; v_discount := coalesce((v_item->>'discount_amount')::numeric,0);
    v_tax := coalesce((v_item->>'tax_amount')::numeric,0); v_line := round(v_qty*v_cost,2)-v_discount+v_tax;
    insert into public.purchase_invoice_items(owner_id,invoice_id,product_id,quantity,unit_cost,discount_amount,tax_amount,line_total)
    values(v_owner,v_invoice_id,v_product_id,v_qty,v_cost,v_discount,v_tax,v_line);
    insert into public.stock_movements(owner_id,product_id,warehouse_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,notes)
    values(v_owner,v_product_id,p_warehouse_id,'purchase',v_qty,v_cost,'purchase_invoice',v_invoice_id,'Purchase invoice '||v_invoice_number::text);
  end loop;
  return jsonb_build_object('invoice_id',v_invoice_id,'invoice_number',v_invoice_number,'subtotal',v_subtotal,'discount_total',v_discounts,'tax_total',v_taxes,'total',v_total,'status','posted');
end; $$;
revoke all on function public.post_purchase_invoice(uuid,uuid,text,timestamptz,text,jsonb) from public,anon;
grant execute on function public.post_purchase_invoice(uuid,uuid,text,timestamptz,text,jsonb) to authenticated;
