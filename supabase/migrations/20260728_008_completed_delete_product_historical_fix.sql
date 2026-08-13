-- V11: tamamlanan servis silme, ürün kalıcı silme, mükerrer araç deposu temizliği,
-- geçmiş müşteri satış/bakım kaydı.

create table if not exists public.historical_customer_sales (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity numeric(12,2) not null default 1,
  amount numeric(12,2) not null default 0,
  payment_status text not null default 'paid' check (payment_status in ('paid','debt')),
  payment_due_date date,
  transaction_date date not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.historical_customer_sales enable row level security;
drop policy if exists historical_customer_sales_company_access on public.historical_customer_sales;
create policy historical_customer_sales_company_access
on public.historical_customer_sales for all to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());
grant select, insert, update, delete on public.historical_customer_sales to authenticated;

-- Aynı teknisyene ait birden fazla araç deposu varsa stokları tek depoda birleştir.
do $$
declare
  r record;
  keep_id uuid;
  duplicate_id uuid;
begin
  for r in
    select company_id, assigned_technician_id
    from public.warehouses
    where type='vehicle' and assigned_technician_id is not null
    group by company_id, assigned_technician_id
    having count(*) > 1
  loop
    select id into keep_id
    from public.warehouses
    where company_id=r.company_id and assigned_technician_id=r.assigned_technician_id and type='vehicle'
    order by created_at nulls last, id
    limit 1;

    for duplicate_id in
      select id from public.warehouses
      where company_id=r.company_id and assigned_technician_id=r.assigned_technician_id
        and type='vehicle' and id<>keep_id
    loop
      update public.stock_movements set warehouse_id=keep_id where warehouse_id=duplicate_id;
      insert into public.warehouse_stocks(company_id, warehouse_id, product_id, quantity)
      select company_id, keep_id, product_id, quantity
      from public.warehouse_stocks where warehouse_id=duplicate_id
      on conflict (warehouse_id, product_id)
      do update set quantity=public.warehouse_stocks.quantity + excluded.quantity, updated_at=now();
      delete from public.warehouse_stocks where warehouse_id=duplicate_id;
      delete from public.warehouses where id=duplicate_id;
    end loop;
  end loop;
end $$;

create unique index if not exists warehouses_one_vehicle_per_technician
on public.warehouses(company_id, assigned_technician_id)
where type='vehicle' and assigned_technician_id is not null;

-- Tamamlanan servisi tamamen geri alır.
drop function if exists public.delete_completed_service_v11(uuid);
create function public.delete_completed_service_v11(p_service_request_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid := auth.uid();
  cid uuid;
  role_name text;
  req public.service_requests%rowtype;
  service_row record;
  vehicle_id uuid;
  item record;
begin
  select company_id, role into cid, role_name from public.profiles
  where id=uid and is_active=true;
  if cid is null or role_name not in ('admin','manager') then
    raise exception 'Bu işlemi yalnızca yönetici yapabilir.';
  end if;

  select * into req from public.service_requests
  where id=p_service_request_id and company_id=cid for update;
  if not found then raise exception 'Servis talebi bulunamadı.'; end if;
  if req.status <> 'completed' then raise exception 'Yalnızca tamamlanan servis silinebilir.'; end if;

  select id into vehicle_id from public.warehouses
  where company_id=cid and type='vehicle' and assigned_technician_id=req.assigned_technician_id
  order by created_at nulls last, id limit 1;

  for service_row in select id from public.services where service_request_id=req.id loop
    for item in select product_id, quantity from public.service_items where service_id=service_row.id loop
      if vehicle_id is not null and item.product_id is not null and item.quantity > 0 then
        insert into public.stock_movements(
          company_id, product_id, warehouse_id, service_request_id,
          movement_type, quantity, notes, created_by
        ) values (
          cid, item.product_id, vehicle_id, null,
          'in', item.quantity, 'Tamamlanan servis silindi; ürün teknisyen aracına geri eklendi', uid
        );
      end if;
    end loop;
  end loop;

  delete from public.payments where service_request_id=req.id;
  delete from public.service_items where service_request_id=req.id;
  delete from public.services where service_request_id=req.id;
  -- Eski servis çıkış hareketleri geçmişten tamamen kaldırılır; geri giriş hareketi stok bakiyesini korur.
  delete from public.stock_movements
  where service_request_id=req.id and movement_type='service';
  delete from public.customer_maintenance_records where service_request_id=req.id;
  delete from public.service_requests where id=req.id;
end;
$$;
grant execute on function public.delete_completed_service_v11(uuid) to authenticated;

-- Ürünü tüm aktif stok/plan bağlantılarından kaldırır. Geçmiş servis satırındaki ürün adı korunur.
drop function if exists public.delete_product_v11(uuid);
create function public.delete_product_v11(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid := auth.uid();
  cid uuid;
  role_name text;
begin
  select company_id, role into cid, role_name from public.profiles where id=uid and is_active=true;
  if cid is null or role_name not in ('admin','manager') then raise exception 'Yetkiniz yok.'; end if;
  if not exists(select 1 from public.products where id=p_product_id and company_id=cid) then
    raise exception 'Ürün bulunamadı.';
  end if;

  update public.service_requests
  set planned_product_id=null, planned_product_name=null, planned_quantity=0, planned_unit_price=0
  where company_id=cid and planned_product_id=p_product_id and status<>'completed';
  update public.service_items set product_id=null where company_id=cid and product_id=p_product_id;
  update public.customer_maintenance_records set product_id=null where company_id=cid and product_id=p_product_id;
  update public.historical_customer_sales set product_id=null where company_id=cid and product_id=p_product_id;
  delete from public.warehouse_stocks where company_id=cid and product_id=p_product_id;
  delete from public.stock_movements where company_id=cid and product_id=p_product_id;
  delete from public.products where company_id=cid and id=p_product_id;
end;
$$;
grant execute on function public.delete_product_v11(uuid) to authenticated;

-- Geçmiş müşteri + ürün + ödeme durumu + bakım tarihi.
drop function if exists public.create_historical_customer_v11(text,text,text,text,text,date,uuid,numeric,numeric,text,date,integer);
create function public.create_historical_customer_v11(
  p_full_name text,
  p_phone text,
  p_city text,
  p_district text,
  p_address text,
  p_record_date date,
  p_product_id uuid,
  p_quantity numeric,
  p_amount numeric,
  p_payment_status text,
  p_payment_due_date date,
  p_maintenance_months integer
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid:=auth.uid();
  cid uuid;
  customer_id uuid;
  product_name_value text;
  next_date date;
begin
  select company_id into cid from public.profiles
  where id=uid and is_active=true and role in ('admin','manager','secretary');
  if cid is null then raise exception 'Yetkiniz yok.'; end if;
  select name into product_name_value from public.products
  where id=p_product_id and company_id=cid and is_active=true;
  if product_name_value is null then raise exception 'Ürün bulunamadı.'; end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'Adet 0’dan büyük olmalıdır.'; end if;
  if p_payment_status='debt' and p_payment_due_date is null then raise exception 'Ödeme tarihi zorunludur.'; end if;

  insert into public.customers(
    company_id, customer_type, full_name, phone, city, district, address,
    registration_date, is_active, created_by, updated_by
  ) values (
    cid, 'individual', btrim(p_full_name), btrim(p_phone), btrim(p_city), btrim(p_district),
    btrim(p_address), p_record_date, true, uid, uid
  ) returning id into customer_id;

  insert into public.historical_customer_sales(
    company_id, customer_id, product_id, product_name, quantity, amount,
    payment_status, payment_due_date, transaction_date, created_by
  ) values (
    cid, customer_id, p_product_id, product_name_value, p_quantity, greatest(coalesce(p_amount,0),0),
    p_payment_status, case when p_payment_status='debt' then p_payment_due_date else null end,
    p_record_date, uid
  );

  if coalesce(p_maintenance_months,0)>0 then
    next_date := (p_record_date + make_interval(months => p_maintenance_months))::date;
    insert into public.customer_maintenance_records(
      company_id, customer_id, product_id, performed_at, next_maintenance_date,
      assigned_role, notes, created_by
    ) values (
      cid, customer_id, p_product_id, p_record_date, next_date,
      'secretary', 'Geçmiş müşteri kaydından oluşturuldu. Adet: '||p_quantity, uid
    );
  end if;

  return customer_id;
end;
$$;
grant execute on function public.create_historical_customer_v11(text,text,text,text,text,date,uuid,numeric,numeric,text,date,integer) to authenticated;
