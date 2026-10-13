create or replace view public.stock_balances
with (security_invoker = true)
as
select
  p.owner_id,
  p.id as product_id,
  p.name as product_name,
  p.internal_code,
  p.minimum_stock,
  p.track_stock,
  w.id as warehouse_id,
  w.name as warehouse_name,
  coalesce(sum(sm.quantity_delta), 0)::numeric(14,3) as quantity_on_hand,
  case when p.track_stock then coalesce(sum(sm.quantity_delta), 0) <= p.minimum_stock else false end as is_low_stock
from public.products p
join public.warehouses w on w.owner_id = p.owner_id and w.is_active = true
left join public.stock_movements sm on sm.owner_id = p.owner_id and sm.product_id = p.id and sm.warehouse_id = w.id
where p.is_active = true
group by p.owner_id, p.id, p.name, p.internal_code, p.minimum_stock, p.track_stock, w.id, w.name;

grant select on public.stock_balances to authenticated;
