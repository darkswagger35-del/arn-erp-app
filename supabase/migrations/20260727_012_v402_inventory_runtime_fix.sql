-- ARN ERP V4.0.2
-- Stok hareketi tetikleyicisini depo stoklarıyla birlikte güvenli şekilde onarır.
-- Tekrar çalıştırılabilir.

create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  stock_delta numeric(12,2);
  current_product_stock numeric(12,2);
  current_warehouse_stock numeric(12,2);
begin
  if new.movement_type = 'in' then
    stock_delta := new.quantity;
  elsif new.movement_type in ('out', 'service') then
    stock_delta := -new.quantity;
  else
    -- Sayım/düzeltme gibi tanınmayan hareketler stok değiştirmez.
    return new;
  end if;

  select coalesce(stock_quantity, 0)
    into current_product_stock
  from public.products
  where id = new.product_id
  for update;

  if current_product_stock is null then
    raise exception 'Ürün bulunamadı.';
  end if;

  if current_product_stock + stock_delta < 0 then
    raise exception 'Yetersiz toplam stok. Mevcut stok: %', current_product_stock;
  end if;

  if new.warehouse_id is not null then
    insert into public.warehouse_stocks(
      company_id, warehouse_id, product_id, quantity
    ) values (
      new.company_id, new.warehouse_id, new.product_id, 0
    )
    on conflict (warehouse_id, product_id) do nothing;

    select quantity
      into current_warehouse_stock
    from public.warehouse_stocks
    where warehouse_id = new.warehouse_id
      and product_id = new.product_id
    for update;

    if current_warehouse_stock + stock_delta < 0 then
      raise exception 'Seçilen depoda yeterli stok yok. Depo stoğu: %', current_warehouse_stock;
    end if;

    update public.warehouse_stocks
       set quantity = quantity + stock_delta,
           updated_at = now()
     where warehouse_id = new.warehouse_id
       and product_id = new.product_id;
  end if;

  update public.products
     set stock_quantity = stock_quantity + stock_delta,
         updated_at = now()
   where id = new.product_id;

  return new;
end;
$$;

drop trigger if exists stock_movement_apply_trigger on public.stock_movements;
create trigger stock_movement_apply_trigger
after insert on public.stock_movements
for each row execute function public.apply_stock_movement();

-- Daha önce kaydedilmiş fakat eski tetikleyici nedeniyle depo ekranına
-- yansımamış hareketleri yalnızca depo satırının son güncellemesinden sonra
-- oluşmuşlarsa bir kez uygula.
with pending as (
  select
    sm.company_id,
    sm.warehouse_id,
    sm.product_id,
    sum(
      case
        when sm.movement_type = 'in' then sm.quantity
        when sm.movement_type in ('out', 'service') then -sm.quantity
        else 0
      end
    )::numeric(12,2) as delta
  from public.stock_movements sm
  left join public.warehouse_stocks ws
    on ws.warehouse_id = sm.warehouse_id
   and ws.product_id = sm.product_id
  where sm.warehouse_id is not null
    and sm.created_at > coalesce(ws.updated_at, '1970-01-01'::timestamptz)
  group by sm.company_id, sm.warehouse_id, sm.product_id
)
insert into public.warehouse_stocks(
  company_id, warehouse_id, product_id, quantity, updated_at
)
select company_id, warehouse_id, product_id, greatest(delta, 0), now()
from pending
where delta <> 0
on conflict (warehouse_id, product_id) do update
set quantity = greatest(public.warehouse_stocks.quantity + excluded.quantity, 0),
    updated_at = now();
