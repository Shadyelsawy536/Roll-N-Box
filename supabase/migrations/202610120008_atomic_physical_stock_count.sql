-- Atomic physical stock count posting. Apply only to the dedicated Inv Management project.
create or replace function public.post_stock_count(
  p_warehouse_id uuid,
  p_count_date timestamptz,
  p_notes text,
  p_items jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_owner uuid := auth.uid();
  v_count_id uuid;
  v_count_number bigint;
  v_item jsonb;
  v_product_id uuid;
  v_counted numeric(14,3);
  v_expected numeric(14,3);
  v_difference numeric(14,3);
  v_cost numeric(14,2);
  v_name text;
  v_tracks_stock boolean;
  v_item_count integer := 0;
  v_adjusted_count integer := 0;
begin
  if v_owner is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.warehouses
    where id=p_warehouse_id and owner_id=v_owner and is_active
  ) then raise exception 'Select an active warehouse'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Stock count requires at least one item';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) x
    group by x->>'product_id' having count(*) > 1
  ) then raise exception 'Duplicate products are not allowed in a stock count'; end if;

  for v_item in select value from jsonb_array_elements(p_items) order by value->>'product_id' loop
    begin
      v_product_id := (v_item->>'product_id')::uuid;
      v_counted := (v_item->>'counted_quantity')::numeric;
    exception when others then raise exception 'Invalid stock count item data'; end;
    if v_counted is null or v_counted < 0 then raise exception 'Counted quantity cannot be negative'; end if;
    select name, cost_price, track_stock into v_name, v_cost, v_tracks_stock
    from public.products where id=v_product_id and owner_id=v_owner and is_active;
    if not found or v_tracks_stock is distinct from true then
      raise exception 'Product is invalid or does not track stock';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(v_owner::text||':'||p_warehouse_id::text||':'||v_product_id::text,0));
  end loop;

  insert into public.stock_counts(owner_id,warehouse_id,count_date,status,notes)
  values(v_owner,p_warehouse_id,coalesce(p_count_date,now()),'posted',nullif(trim(coalesce(p_notes,'')),''))
  returning id,count_number into v_count_id,v_count_number;

  for v_item in select value from jsonb_array_elements(p_items) order by value->>'product_id' loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_counted := (v_item->>'counted_quantity')::numeric;
    select name,cost_price into v_name,v_cost from public.products
    where id=v_product_id and owner_id=v_owner and is_active and track_stock;
    select coalesce(sum(quantity_delta),0)::numeric(14,3) into v_expected
    from public.stock_movements
    where owner_id=v_owner and product_id=v_product_id and warehouse_id=p_warehouse_id;
    v_difference := v_counted-v_expected;
    insert into public.stock_count_items(owner_id,stock_count_id,product_id,expected_quantity,counted_quantity)
    values(v_owner,v_count_id,v_product_id,v_expected,v_counted);
    v_item_count := v_item_count+1;
    if v_difference <> 0 then
      insert into public.stock_movements(owner_id,product_id,warehouse_id,movement_type,quantity_delta,unit_cost,reference_type,reference_id,notes)
      values(v_owner,v_product_id,p_warehouse_id,'stock_count',v_difference,v_cost,'stock_count',v_count_id,
        'Stock count #'||v_count_number::text||' • '||v_name);
      v_adjusted_count := v_adjusted_count+1;
    end if;
  end loop;

  return jsonb_build_object('stock_count_id',v_count_id,'count_number',v_count_number,'items_count',v_item_count,'adjusted_items_count',v_adjusted_count,'status','posted');
end;
$function$;
revoke all on function public.post_stock_count(uuid,timestamptz,text,jsonb) from public, anon;
grant execute on function public.post_stock_count(uuid,timestamptz,text,jsonb) to authenticated;
