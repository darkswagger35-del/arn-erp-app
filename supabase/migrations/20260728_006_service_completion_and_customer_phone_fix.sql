-- ARN ERP V9 - müşteri telefon kontrolü ve servis tamamlama düzeltmeleri

create or replace function public.find_customer_by_phone_v9(
  p_phone text,
  p_exclude_customer_id uuid default null
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.id
  from public.customers c
  where c.company_id = public.current_company_id()
    and c.deleted_at is null
    and regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g') =
        regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')
    and (p_exclude_customer_id is null or c.id <> p_exclude_customer_id)
  limit 1;
$$;

grant execute on function public.find_customer_by_phone_v9(text, uuid) to authenticated;

-- Eski telefon indekslerini temizleyip yalnızca aktif kayıtları kapsayan indeksi yeniden kur.
do $$
declare r record;
begin
  for r in
    select indexname
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'customers'
      and indexdef ilike '%phone%'
      and indexdef ilike '%unique%'
  loop
    execute format('drop index if exists public.%I', r.indexname);
  end loop;
end $$;

create unique index if not exists customers_company_phone_active_unique
on public.customers(company_id, regexp_replace(phone, '[^0-9]', '', 'g'))
where deleted_at is null and phone is not null and btrim(phone) <> '';

-- Servis tamamlama fonksiyonu: firma bilgisini servis kaydından alır,
-- teknisyen/rol yetkisini ayrıca doğrular ve araç stoğu yetmezse ana depoyu kullanır.
drop function if exists public.complete_service_v4(uuid, text, numeric, text, jsonb);

create function public.complete_service_v4(
  p_service_request_id uuid,
  p_work_description text,
  p_collected_amount numeric,
  p_payment_method text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  user_role text;
  profile_company_id uuid;
  cid uuid;
  request_row public.service_requests%rowtype;
  vehicle_warehouse_id uuid;
  main_warehouse_id uuid;
  source_warehouse_id uuid;
  service_id uuid;
  item jsonb;
  v_product_id uuid;
  product_name text;
  qty numeric(12,2);
  unit_price numeric(12,2);
  available_qty numeric(12,2);
  product_total numeric(12,2) := 0;
  service_total numeric(12,2) := 0;
  collected numeric(12,2) := greatest(coalesce(p_collected_amount, 0), 0);
  payment_status_value text;
begin
  if uid is null then
    raise exception 'Oturum bilgisi bulunamadı.';
  end if;

  select role, company_id
    into user_role, profile_company_id
  from public.profiles
  where id = uid;

  select * into request_row
  from public.service_requests
  where id = p_service_request_id
  for update;

  if not found then
    raise exception 'Servis talebi bulunamadı.';
  end if;

  cid := request_row.company_id;

  if profile_company_id is distinct from cid then
    raise exception 'Bu servis başka bir firmaya aittir.';
  end if;

  if user_role = 'technician' and request_row.assigned_technician_id is distinct from uid then
    raise exception 'Bu servis size atanmadı.';
  end if;

  if user_role not in ('technician', 'manager', 'admin') then
    raise exception 'Bu işlemi tamamlamak için yetkiniz bulunmuyor.';
  end if;

  if request_row.status = 'completed' then
    raise exception 'Bu servis daha önce tamamlanmış.';
  end if;

  if request_row.assigned_technician_id is null then
    raise exception 'Servise teknisyen atanmadı.';
  end if;

  if btrim(coalesce(p_work_description, '')) = '' then
    raise exception 'Yapılan işlem açıklaması zorunludur.';
  end if;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'Ürün listesi geçersiz.';
  end if;

  perform public.ensure_company_warehouses();

  select id into vehicle_warehouse_id
  from public.warehouses
  where company_id = cid
    and type = 'vehicle'
    and assigned_technician_id = request_row.assigned_technician_id
    and is_active = true
  limit 1;

  select id into main_warehouse_id
  from public.warehouses
  where company_id = cid
    and type = 'main'
    and is_active = true
  order by created_at
  limit 1;

  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_product_id := nullif(item->>'product_id', '')::uuid;
    qty := coalesce((item->>'quantity')::numeric, 0);
    unit_price := greatest(coalesce((item->>'unit_price')::numeric, 0), 0);

    if v_product_id is null or qty <= 0 then
      raise exception 'Ürün ve miktar bilgisi geçersiz.';
    end if;

    select p.name into product_name
    from public.products p
    where p.id = v_product_id
      and p.company_id = cid
      and p.is_active = true;

    if product_name is null then
      raise exception 'Aktif ürün bulunamadı.';
    end if;

    source_warehouse_id := null;
    available_qty := 0;

    if vehicle_warehouse_id is not null then
      select coalesce(quantity, 0) into available_qty
      from public.warehouse_stocks
      where warehouse_id = vehicle_warehouse_id and product_id = v_product_id
      for update;

      if coalesce(available_qty, 0) >= qty then
        source_warehouse_id := vehicle_warehouse_id;
      end if;
    end if;

    if source_warehouse_id is null and main_warehouse_id is not null then
      select coalesce(quantity, 0) into available_qty
      from public.warehouse_stocks
      where warehouse_id = main_warehouse_id and product_id = v_product_id
      for update;

      if coalesce(available_qty, 0) >= qty then
        source_warehouse_id := main_warehouse_id;
      end if;
    end if;

    if source_warehouse_id is null then
      raise exception '% için kullanılabilir stok yetersiz. İstenen: %', product_name, qty;
    end if;

    product_total := product_total + (qty * unit_price);
  end loop;

  service_total := greatest(coalesce(request_row.price, 0), product_total, 0);

  if collected > service_total then
    raise exception 'Tahsilat toplam tutardan fazla olamaz.';
  end if;

  insert into public.services(
    company_id, service_request_id, customer_id, technician_id,
    work_description, product_total, labor_amount, discount_amount,
    total_amount, collected_amount, payment_method, completed_at
  ) values (
    cid, request_row.id, request_row.customer_id, request_row.assigned_technician_id,
    btrim(p_work_description), product_total, greatest(service_total - product_total, 0), 0,
    service_total, collected, coalesce(nullif(p_payment_method, ''), 'cash'), now()
  ) returning id into service_id;

  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_product_id := (item->>'product_id')::uuid;
    qty := (item->>'quantity')::numeric;
    unit_price := greatest(coalesce((item->>'unit_price')::numeric, 0), 0);

    select name into product_name from public.products where id = v_product_id;

    source_warehouse_id := null;

    if vehicle_warehouse_id is not null and coalesce((
      select quantity from public.warehouse_stocks
      where warehouse_id = vehicle_warehouse_id and product_id = v_product_id
    ), 0) >= qty then
      source_warehouse_id := vehicle_warehouse_id;
    elsif main_warehouse_id is not null and coalesce((
      select quantity from public.warehouse_stocks
      where warehouse_id = main_warehouse_id and product_id = v_product_id
    ), 0) >= qty then
      source_warehouse_id := main_warehouse_id;
    end if;

    insert into public.service_items(
      company_id, service_id, service_request_id, product_id,
      product_name, quantity, unit_price, line_total
    ) values (
      cid, service_id, request_row.id, v_product_id,
      product_name, qty, unit_price, qty * unit_price
    );

    insert into public.stock_movements(
      company_id, product_id, warehouse_id, service_request_id,
      movement_type, quantity, notes, created_by
    ) values (
      cid, v_product_id, source_warehouse_id, request_row.id,
      'service', qty, 'Servis tamamlamada otomatik stok çıkışı', uid
    );
  end loop;

  if collected > 0 then
    insert into public.payments(
      company_id, customer_id, service_request_id, service_id,
      amount, payment_method, description, payment_date, created_by
    ) values (
      cid, request_row.customer_id, request_row.id, service_id,
      collected, coalesce(nullif(p_payment_method, ''), 'cash'),
      'Servis tahsilatı', now(), uid
    );
  end if;

  payment_status_value := case
    when service_total <= 0 or collected >= service_total then 'paid'
    when collected > 0 then 'partial'
    else 'unpaid'
  end;

  update public.service_requests
  set status = 'completed',
      price = service_total,
      collected_amount = collected,
      payment_status = payment_status_value,
      completion_note = btrim(p_work_description),
      completed_at = now(),
      updated_at = now()
  where id = request_row.id;

  return service_id;
end;
$$;

grant execute on function public.complete_service_v4(uuid, text, numeric, text, jsonb) to authenticated;
