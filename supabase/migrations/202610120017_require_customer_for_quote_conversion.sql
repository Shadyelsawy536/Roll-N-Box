-- Prevent converting a quote without a customer into an unallocated credit invoice.
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
  select * into v_quote from public.quotations where id=p_quotation_id and owner_id=v_owner for update;
  if not found then raise exception 'Quotation not found'; end if;
  if v_quote.status='converted' then raise exception 'Quotation has already been converted'; end if;
  if v_quote.status not in ('draft','sent','accepted') then raise exception 'Only open quotations can be converted'; end if;
  if v_quote.customer_id is null then raise exception 'Select a customer before converting this quotation to a credit sales invoice'; end if;
  if v_quote.warehouse_id is null then raise exception 'Select a warehouse on the quotation before converting'; end if;

  select jsonb_agg(jsonb_build_object(
    'product_id',qi.product_id,'quantity',qi.quantity,'unit_price',qi.unit_price,
    'discount_amount',qi.discount_amount,'tax_amount',qi.tax_amount
  ) order by qi.created_at,qi.id)
  into v_items from public.quotation_items qi where qi.quotation_id=v_quote.id and qi.owner_id=v_owner;
  if v_items is null or jsonb_array_length(v_items)=0 then raise exception 'Quotation has no items'; end if;

  v_result := public.post_sales_invoice(
    v_quote.warehouse_id,v_quote.customer_id,now(),null,
    'Converted from quotation #'||v_quote.quotation_number::text,v_items,0,null,'credit'
  );
  update public.quotations set status='converted' where id=v_quote.id and owner_id=v_owner;
  return v_result || jsonb_build_object('quotation_id',v_quote.id,'quotation_number',v_quote.quotation_number,'quotation_status','converted');
end;
$$;
revoke all on function public.convert_quotation_to_sales_invoice(uuid) from public, anon;
grant execute on function public.convert_quotation_to_sales_invoice(uuid) to authenticated;
