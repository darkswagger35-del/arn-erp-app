-- ARN ERP V10
-- Teknisyen yalnızca kendi araç deposundaki ürünleri görür.
-- Ürün fiyatını teknisyen girer; servis ve ekstra ücret stoktan bağımsızdır.
-- Servis tamamlama firma eşleşmesi atanmış teknisyen üzerinden güvenli biçimde doğrulanır.

create or replace function public.technician_vehicle_products_v10(
  p_technician_id uuid
)
returns table(
  id uuid,
  name text,
  unit text,
  stock_quantity numeric,
  warehouse_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.name,
    p.unit,
    ws.quantity::numeric,
    w.id
  from public.warehouses w
  join public.warehouse_stocks ws on ws.warehouse_id = w.id
  join public.products p on p.id = ws.product_id
  where w.type = 'vehicle'
    and w.assigned_technician_id = p_technician_id
    and w.is_active = true
    and p.is_active = true
    and ws.quantity > 0
    and (
      auth.uid() = p_technician_id
      or exists (
        select 1
        from public.profiles pr
        where pr.id = auth.uid()
          and pr.company_id = w.company_id
          and pr.role in ('manager', 'admin')
      )
    )
  order by p.name;
$$;

grant execute on function public.technician_vehicle_products_v10(uuid) to authenticated;

drop function if exists public.complete_service_v5(uuid, text, numeric, numeric, numeric, text, jsonb);

create function public.complete_service_v5(
  p_service_request_id uuid,
  p_work_description text,
  p_service_amount numeric,
  p_extra_amount numeric,
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
  service_id uuid;
  item jsonb;
  v_product_id uuid;
  product_name text;
  qty numeric(12,2);
  unit_price numeric(12,2);
  available_qty numeric(12,2);
  product_total numeric(12,2) := 0;
  service_amount numeric(12,2) := greatest(coalesce(p_service_amount, 0), 0);
  extra_amount numeric(12,2) := greatest(coalesce(p_extra_amount, 0), 0);
  total_amount_value numeric(12,2) := 0;
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
  if cid is null then
    select company_id into cid
    from public.customers
    where id = request_row.customer_id;
  end if;
  cid := coalesce(cid, profile_company_id);

  -- Atanmış teknisyen kendi işini şirket profilindeki eski/eksik eşleşmelerden
  -- etkilenmeden tamamlayabilir. Yönetici ve admin için firma eşleşmesi zorunludur.
  if user_role = 'technician' then
    if request_row.assigned_technician_id is distinct from uid then
      raise exception 'Bu servis size atanmadı.';
    end if;
  elsif user_role in ('manager', 'admin') then
    if profile_company_id is distinct from cid then
      raise exception 'Bu servis başka bir firmaya aittir.';
    end if;
  else
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

  select id into vehicle_warehouse_id
  from public.warehouses
  where company_id = cid
    and type = 'vehicle'
    and assigned_technician_id = request_row.assigned_technician_id
    and is_active = true
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

    if vehicle_warehouse_id is null then
      raise exception 'Teknisyen araç deposu bulunamadı.';
    end if;

    select coalesce(quantity, 0) into available_qty
    from public.warehouse_stocks
    where warehouse_id = vehicle_warehouse_id
      and product_id = v_product_id
    for update;

    if coalesce(available_qty, 0) < qty then
      raise exception '% için araç stoğu yetersiz. İstenen: %', product_name, qty;
    end if;

    product_total := product_total + (qty * unit_price);
  end loop;

  total_amount_value := service_amount + extra_amount + product_total;

  if collected > total_amount_value then
    raise exception 'Tahsilat toplam tutardan fazla olamaz.';
  end if;

  insert into public.services(
    company_id, service_request_id, customer_id, technician_id,
    work_description, product_total, labor_amount, discount_amount,
    total_amount, collected_amount, payment_method, completed_at
  ) values (
    cid, request_row.id, request_row.customer_id, request_row.assigned_technician_id,
    btrim(p_work_description), product_total, service_amount + extra_amount, 0,
    total_amount_value, collected, coalesce(nullif(p_payment_method, ''), 'cash'), now()
  ) returning id into service_id;

  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_product_id := (item->>'product_id')::uuid;
    qty := (item->>'quantity')::numeric;
    unit_price := greatest(coalesce((item->>'unit_price')::numeric, 0), 0);

    select name into product_name
    from public.products
    where id = v_product_id;

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
      cid, v_product_id, vehicle_warehouse_id, request_row.id,
      'service', qty, 'Servis tamamlamada araç deposundan otomatik stok çıkışı', uid
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
    when total_amount_value <= 0 or collected >= total_amount_value then 'paid'
    when collected > 0 then 'partial'
    else 'unpaid'
  end;

  update public.service_requests
  set company_id = cid,
      status = 'completed',
      price = total_amount_value,
      collected_amount = collected,
      payment_status = payment_status_value,
      completion_note = btrim(p_work_description),
      completed_at = now(),
      updated_at = now()
  where id = request_row.id;

  return service_id;
end;
$$;

grant execute on function public.complete_service_v5(uuid, text, numeric, numeric, numeric, text, jsonb) to authenticated;
