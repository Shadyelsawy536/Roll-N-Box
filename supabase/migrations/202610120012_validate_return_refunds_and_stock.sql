-- Prevent cash refunds from exceeding actual payments made on the source invoice.
create or replace function public.validate_sales_return_refund()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_paid numeric(14,2); v_prior numeric(14,2);
begin
  select si.paid_total into v_paid
  from public.sales_invoices si
  where si.id=new.sales_invoice_id and si.owner_id=new.owner_id and si.owner_id=auth.uid()
  for update;
  if not found then raise exception 'Sales invoice not found for this user'; end if;
  select coalesce(sum(sr.refund_amount),0) into v_prior
  from public.sales_returns sr
  where sr.sales_invoice_id=new.sales_invoice_id and sr.owner_id=new.owner_id;
  if new.refund_amount > greatest(v_paid-v_prior,0) then
    raise exception 'Cash refund exceeds payments received on the original invoice';
  end if;
  return new;
end;
$$;
create trigger sales_returns_validate_refund
before insert on public.sales_returns
for each row execute function public.validate_sales_return_refund();

create or replace function public.validate_purchase_return_receipt()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_paid numeric(14,2); v_prior numeric(14,2);
begin
  select pi.paid_total into v_paid
  from public.purchase_invoices pi
  where pi.id=new.purchase_invoice_id and pi.owner_id=new.owner_id and pi.owner_id=auth.uid()
  for update;
  if not found then raise exception 'Purchase invoice not found for this user'; end if;
  select coalesce(sum(pr.received_amount),0) into v_prior
  from public.purchase_returns pr
  where pr.purchase_invoice_id=new.purchase_invoice_id and pr.owner_id=new.owner_id;
  if new.received_amount > greatest(v_paid-v_prior,0) then
    raise exception 'Supplier cash refund exceeds payments made on the original invoice';
  end if;
  return new;
end;
$$;
create trigger purchase_returns_validate_receipt
before insert on public.purchase_returns
for each row execute function public.validate_purchase_return_receipt();

-- A return may contain multiple invoice lines for the same product; guard the aggregate against overselling stock.
create or replace function public.validate_purchase_return_stock()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_warehouse uuid; v_available numeric(14,3); v_already numeric(14,3);
begin
  select pr.warehouse_id into v_warehouse
  from public.purchase_returns pr
  where pr.id=new.return_id and pr.owner_id=new.owner_id and pr.owner_id=auth.uid();
  if not found then raise exception 'Purchase return not found for this user'; end if;
  select coalesce(sum(sm.quantity_delta),0) into v_available
  from public.stock_movements sm
  where sm.owner_id=new.owner_id and sm.product_id=new.product_id and sm.warehouse_id=v_warehouse;
  select coalesce(sum(pri.quantity),0) into v_already
  from public.purchase_return_items pri
  where pri.return_id=new.return_id and pri.product_id=new.product_id and pri.owner_id=new.owner_id;
  if v_available < v_already + new.quantity then
    raise exception 'Insufficient stock for total purchase return quantity';
  end if;
  return new;
end;
$$;
create trigger purchase_return_items_validate_stock
before insert on public.purchase_return_items
for each row execute function public.validate_purchase_return_stock();
