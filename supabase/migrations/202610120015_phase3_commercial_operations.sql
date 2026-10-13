-- Phase 3 commercial operations: transactional quotation and stock transfer RPCs.
-- This migration applies only to the dedicated Inv Management project.

alter table public.stock_transfers
  add column if not exists idempotency_key uuid;

create unique index if not exists stock_transfers_owner_idempotency_key_uidx
  on public.stock_transfers(owner_id, idempotency_key)
  where idempotency_key is not null;

create or replace function public.save_quotation(
  p_customer_id uuid,
  p_warehouse_id uuid,
  p_valid_until date,
  p_notes text,
  p_items jsonb
) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_quotation_id uuid;
  v_number bigint;
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14,3);
  v_price numeric(14,2);
  v_discount numeric(14,2);
  v_tax numeric(14,2);
  v_line numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_discounts numeric(14,2) := 0;
  v_taxes numeric(14,2) := 0;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_customer_id is not null and not exists (
    select 1 from public.customers where id=p_customer_id and owner_id=v_owner and is_active
  ) then raise exception 'Invalid customer'; end if;
  if p_warehouse_id is not null and not exists (
    select 1 from public.warehouses where id=p_warehouse_id and owner_id=v_owner and is_active
  ) then raise exception 'Invalid warehouse'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Quotation requires at least one item';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    begin
      v_product_id := (v_item->>'product_id')::uuid;
      v_qty := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'unit_price')::numeric;
      v_discount := coalesce((v_item->>'discount_amount')::numeric,0);
      v_tax := coalesce((v_item->>'tax_amount')::numeric,0);
    exception when others then raise exception 'Invalid quotation item'; end;
    if v_qty<=0 or v_price<0 or v_discount<0 or v_tax<0 then raise exception 'Invalid quantity or amount'; end if;
    if not exists(select 1 from public.products where id=v_product_id and owner_id=v_owner and is_active) then
      raise exception 'Invalid product';
    end if;
    v_line := round(v_qty*v_price,2)-v_discount+v_tax;
    if v_line<0 then raise exception 'Discount exceeds line value'; end if;
    v_subtotal := v_subtotal + round(v_qty*v_price,2);
    v_discounts := v_discounts + v_discount;
    v_taxes := v_taxes + v_tax;
  end loop;

  insert into public.quotations(owner_id,customer_id,warehouse_id,valid_until,status,subtotal,discount_total,tax_total,total,notes)
  values(v_owner,p_customer_id,p_warehouse_id,p_valid_until,'draft',v_subtotal,v_discounts,v_taxes,v_subtotal-v_discounts+v_taxes,nullif(trim(coalesce(p_notes,'')),''))
  returning id,quotation_number into v_quotation_id,v_number;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;
    v_price := (v_item->>'unit_price')::numeric;
    v_discount := coalesce((v_item->>'discount_amount')::numeric,0);
    v_tax := coalesce((v_item->>'tax_amount')::numeric,0);
    v_line := round(v_qty*v_price,2)-v_discount+v_tax;
    insert into public.quotation_items(owner_id,quotation_id,product_id,description,quantity,unit_price,discount_amount,tax_amount,line_total)
    select v_owner,v_quotation_id,p.id,p.name,v_qty,v_price,v_discount,v_tax,v_line
    from public.products p where p.id=v_product_id and p.owner_id=v_owner;
  end loop;
  return jsonb_build_object('quotation_id',v_quotation_id,'quotation_number',v_number,'total',v_subtotal-v_discounts+v_taxes,'status','draft');
end;
$$;

create or replace function public.convert_quotation_to_sales_invoice(p_quotation_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_quote public.quotations%rowtype;
  v_items jsonb;
  v_result jsonb;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  select * into v_quote from public.quotations
    where id=p_quotation_id and owner_id=v_owner for update;
  if not found then raise exception 'Quotation not found'; end if;
  if v_quote.status='converted' then raise exception 'Quotation has already been converted'; end if;
  if v_quote.status not in ('draft','sent','accepted') then raise exception 'Only open quotations can be converted'; end if;
  if v_quote.warehouse_id is null then raise exception 'Select a warehouse on the quotation before converting'; end if;

  select jsonb_agg(jsonb_build_object(
    'product_id',qi.product_id,
    'quantity',qi.quantity,
    'unit_price',qi.unit_price,
    'discount_amount',qi.discount_amount,
    'tax_amount',qi.tax_amount
  ) order by qi.created_at,qi.id)
  into v_items
  from public.quotation_items qi
  where qi.quotation_id=v_quote.id and qi.owner_id=v_owner;
  if v_items is null or jsonb_array_length(v_items)=0 then raise exception 'Quotation has no items'; end if;

  v_result := public.post_sales_invoice(
    v_quote.warehouse_id,
    v_quote.customer_id,
    now(),
    null,
    'Converted from quotation #'||v_quote.quotation_number::text,
    v_items,
    0,
    null,
    'credit'
  );
  update public.quotations set status='converted' where id=v_quote.id and owner_id=v_owner;
  return v_result || jsonb_build_object('quotation_id',v_quote.id,'quotation_number',v_quote.quotation_number,'quotation_status','converted');
end;
$$;

create or replace function public.post_stock_transfer(
  p_source_warehouse_id uuid,
  p_destination_warehouse_id uuid,
  p_transfer_date timestamptz,
  p_notes text,
  p_items jsonb,
  p_idempotency_key uuid
) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_transfer_id uuid;
  v_number bigint;
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14,3);
  v_cost numeric(14,2);
  v_available numeric(14,3);
  v_inserted_id uuid;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null then raise exception 'Request key is required'; end if;
  if p_source_warehouse_id is null or p_destination_warehouse_id is null or p_source_warehouse_id=p_destination_warehouse_id then
    raise exception 'Choose two different warehouses';
  end if;
  if not exists(select 1 from public.warehouses where id=p_source_warehouse_id and owner_id=v_owner and is_active) then
    raise exception 'Invalid source warehouse';
  end if;
  if not exists(select 1 from public.warehouses where id=p_destination_warehouse_id and owner_id=v_owner and is_active) then
    raise exception 'Invalid destination warehouse';
  end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Transfer requires items'; end if;

  -- Return the original result when the same request is retried after a timeout.
  select id,transfer_number into v_transfer_id,v_number from public.stock_transfers
  where owner_id=v_owner and idempotency_key=p_idempotency_key;
  if found then
    return jsonb_build_object('transfer_id',v_transfer_id,'transfer_number',v_number,'status','posted','already_posted',true);
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    begin v_product_id := (v_item->>'product_id')::uuid; v_qty := (v_item->>'quantity')::numeric;
    exception when others then raise exception 'Invalid transfer item'; end;
    if v_qty<=0 then raise exception 'Transfer quantity must be greater than zero'; end if;
    if exists(select 1 from jsonb_array_elements(p_items) x where x->>'product_id'=v_product_id::text group by x->>'product_id' having count(*)>1) then
      raise exception 'Duplicate product in transfer; combine its quantity';
    end if;
    if not exists(select 1 from public.products where id=v_product_id and owner_id=v_owner and is_active and track_stock) then
      raise exception 'Invalid or non-stock product';
    end if;
    -- Lock both warehouse/product pairs in a stable order.
    if p_source_warehouse_id::text < p_destination_warehouse_id::text then
      perform pg_advisory_xact_lock(hashtextextended(v_owner::text||':'||p_source_warehouse_id::text||':'||v_product_id::text,0));
      perform pg_advisory_xact_lock(hashtextextended(v_owner::text||':'||p_destination_warehouse_id::text||':'||v_product_id::text,0));
    else
      perform pg_advisory_xact_lock(hashtextextended(v_owner::text||':'||p_destination_warehouse_id::text||':'||v_product_id::text,0));
      perform pg_advisory_xact_lock(hashtextextended(v_owner::text||':'||p_source_warehouse_id::text||':'||v_product_id::text,0));
    end if;
    select coalesce(sum(quantity_delta),0) into v_available from public.stock_movements
      where owner_id=v_owner and product_id=v_product_id and warehouse_id=p_source_warehouse_id;
    if v_available<v_qty then raise exception 'Insufficient stock for product %. Available %, requested %',v_product_id,v_available,v_qty; end if;
  end loop;

  insert into public.stock_transfers(owner_id,source_warehouse_id,destination_warehouse_id,transfer_date,status,notes,idempotency_key)
  values(v_owner,p_source_warehouse_id,p_destination_warehouse_id,coalesce(p_transfer_date,now()),'posted',nullif(trim(coalesce(p_notes,'')),''),p_idempotency_key)
  on conflict (owner_id,idempotency_key) where idempotency_key is not null do nothing
  returning id,transfer_number into v_inserted_id,v_number;
  if v_inserted_id is null then
    select id,transfer_number into v_transfer_id,v_number from public.stock_transfers where owner_id=v_owner and idempotency_key=p_idempotency_key;
    return jsonb_build_object('transfer_id',v_transfer_id,'transfer_number',v_number,'status','posted','already_posted',true);
  end if;
  v_transfer_id := v_inserted_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;
    select cost_price into v_cost from public.products where id=v_product_id and owner_id=v_owner;
    insert into public.stock_transfer_items(owner_id,transfer_id,product_id,quantity,unit_cost)
    values(v_owner,v_transfer_id,v_product_id,v_qty,v_cost);
    insert into public.stock_movements(owner_id,product_id,warehouse_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,notes)
    values(v_owner,v_product_id,p_source_warehouse_id,'transfer_out',-v_qty,v_cost,'stock_transfer',v_transfer_id,'Transfer #'||v_number::text||' out');
    insert into public.stock_movements(owner_id,product_id,warehouse_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,notes)
    values(v_owner,v_product_id,p_destination_warehouse_id,'transfer_in',v_qty,v_cost,'stock_transfer',v_transfer_id,'Transfer #'||v_number::text||' in');
  end loop;
  return jsonb_build_object('transfer_id',v_transfer_id,'transfer_number',v_number,'status','posted','already_posted',false);
end;
$$;

revoke all on function public.save_quotation(uuid,uuid,date,text,jsonb) from public, anon;
grant execute on function public.save_quotation(uuid,uuid,date,text,jsonb) to authenticated;
revoke all on function public.convert_quotation_to_sales_invoice(uuid) from public, anon;
grant execute on function public.convert_quotation_to_sales_invoice(uuid) to authenticated;
revoke all on function public.post_stock_transfer(uuid,uuid,timestamptz,text,jsonb,uuid) from public, anon;
grant execute on function public.post_stock_transfer(uuid,uuid,timestamptz,text,jsonb,uuid) to authenticated;
