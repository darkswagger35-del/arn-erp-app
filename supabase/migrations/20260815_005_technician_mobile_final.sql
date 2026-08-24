-- ARN ERP V6 - Tekniker mobil saha finali
-- 1) Tekniker firma ürünlerini görür (araç + merkez stok bilgisi).
-- 2) Merkezde bulunan ama araçta olmayan ürünü kullanabilir.
-- 3) Kullanım tekniker araç stoğunu eksiye düşürebilir; firma toplam stoğu eksiye düşemez.
-- 4) Servis tamamlamada not zorunlu değildir.

create or replace function public.technician_service_products_v1()
returns table(
  id uuid,
  name text,
  sale_price numeric,
  stock_quantity numeric,
  main_stock numeric,
  company_stock numeric,
  warehouse_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company uuid;
  v_role text;
  v_vehicle uuid;
  v_main uuid;
begin
  if v_uid is null then
    raise exception 'Oturum bilgisi bulunamadı.';
  end if;

  select p.company_id, p.role::text
    into v_company, v_role
  from public.profiles p
  where p.id = v_uid;

  if v_company is null then
    raise exception 'Firma bilgisi bulunamadı.';
  end if;
  if v_role not in ('technician', 'manager', 'admin') then
    raise exception 'Ürün listesi için yetkiniz bulunmuyor.';
  end if;

  if v_role = 'technician' then
    select w.id into v_vehicle
    from public.warehouses w
    where w.company_id = v_company
      and w.type = 'vehicle'
      and w.assigned_technician_id = v_uid
      and w.is_active
    order by w.created_at
    limit 1;

    if v_vehicle is null then
      insert into public.warehouses as new_vehicle(company_id, name, type, assigned_technician_id, is_active)
      select v_company, coalesce(nullif(btrim(p.full_name), ''), 'Tekniker') || ' Araç Deposu', 'vehicle', v_uid, true
      from public.profiles p
      where p.id = v_uid
      returning new_vehicle.id into v_vehicle;
    end if;
  end if;

  select w.id into v_main
  from public.warehouses w
  where w.company_id = v_company and w.type = 'main' and w.is_active
  order by w.created_at
  limit 1;

  return query
  select
    p.id,
    p.name,
    coalesce(p.sale_price, 0)::numeric,
    coalesce(vs.quantity, 0)::numeric as stock_quantity,
    coalesce(ms.quantity, 0)::numeric as main_stock,
    coalesce(p.stock_quantity, 0)::numeric as company_stock,
    v_vehicle as warehouse_id
  from public.products p
  left join public.warehouse_stocks vs
    on vs.warehouse_id = v_vehicle and vs.product_id = p.id
  left join public.warehouse_stocks ms
    on ms.warehouse_id = v_main and ms.product_id = p.id
  where p.company_id = v_company
    and p.is_active = true
    and (
      coalesce(p.stock_quantity, 0) > 0
      or coalesce(vs.quantity, 0) <> 0
      or coalesce(ms.quantity, 0) > 0
    )
  order by lower(p.name);
end;
$$;

grant execute on function public.technician_service_products_v1() to authenticated;

-- Servis hareketinde araç deposunun eksiye düşmesine izin ver. Bu yalnızca
-- araç bazlı görünümü eksiye düşürür; products.stock_quantity (firma toplamı)
-- halen 0 altına inemez. Böylece merkezde mal varsa tekniker sahada kullanabilir.
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
  target_warehouse_type text;
begin
  if new.movement_type = 'in' then
    stock_delta := new.quantity;
  elsif new.movement_type in ('out', 'service') then
    stock_delta := -new.quantity;
  else
    return new;
  end if;

  select coalesce(p.stock_quantity, 0)
    into current_product_stock
  from public.products p
  where p.id = new.product_id
  for update;

  if current_product_stock is null then
    raise exception 'Ürün bulunamadı.';
  end if;

  if current_product_stock + stock_delta < 0 then
    raise exception 'Firma toplam stoğu yetersiz. Mevcut stok: %', current_product_stock;
  end if;

  if new.warehouse_id is not null then
    select w.type into target_warehouse_type
    from public.warehouses w
    where w.id = new.warehouse_id;

    insert into public.warehouse_stocks(company_id, warehouse_id, product_id, quantity)
    values(new.company_id, new.warehouse_id, new.product_id, 0)
    on conflict (warehouse_id, product_id) do nothing;

    select ws.quantity
      into current_warehouse_stock
    from public.warehouse_stocks ws
    where ws.warehouse_id = new.warehouse_id
      and ws.product_id = new.product_id
    for update;

    if current_warehouse_stock + stock_delta < 0
       and not (new.movement_type = 'service' and target_warehouse_type = 'vehicle') then
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

create or replace function public.technician_complete_service_v1(
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
  product_name_value text;
  maintenance_months_value integer;
  qty numeric(12,2);
  unit_price numeric(12,2);
  available_qty numeric(12,2);
  product_total numeric(12,2) := 0;
  service_amount numeric(12,2) := greatest(coalesce(p_service_amount, 0), 0);
  extra_amount numeric(12,2) := greatest(coalesce(p_extra_amount, 0), 0);
  total_amount_value numeric(12,2);
  collected numeric(12,2) := greatest(coalesce(p_collected_amount, 0), 0);
  payment_status_value text;
  secretary_value uuid;
  v_auto_stock boolean := true;
  v_allow_negative boolean := false;
  v_require_payment boolean := false;
  v_allow_partial boolean := true;
  v_calc_maintenance boolean := true;
  v_enabled_payment_methods text[] := array['cash','card','transfer','open_account']::text[];
  v_payment_method text := coalesce(nullif(p_payment_method, ''), 'cash');
begin
  if uid is null then raise exception 'Oturum bilgisi bulunamadı.'; end if;

  select role::text, company_id
  into user_role, profile_company_id
  from public.profiles
  where id = uid;

  select * into request_row
  from public.service_requests
  where id = p_service_request_id
  for update;

  if not found then raise exception 'Servis talebi bulunamadı.'; end if;
  cid := coalesce(request_row.company_id, profile_company_id);

  select
    coalesce(auto_decrease_stock_on_service, true),
    coalesce(allow_negative_stock, false),
    coalesce(require_payment_to_complete_service, false),
    coalesce(allow_partial_payment, true),
    coalesce(calculate_maintenance_from_product, true),
    coalesce(enabled_payment_methods, array['cash','card','transfer','open_account']::text[])
  into
    v_auto_stock,
    v_allow_negative,
    v_require_payment,
    v_allow_partial,
    v_calc_maintenance,
    v_enabled_payment_methods
  from public.company_app_settings
  where company_id = cid;

  if not (v_payment_method = any(v_enabled_payment_methods)) then
    raise exception 'Seçilen ödeme yöntemi firma ayarlarında kapalı.';
  end if;

  if user_role = 'technician'
     and request_row.assigned_technician_id is distinct from uid then
    raise exception 'Bu servis size atanmadı.';
  end if;
  if user_role not in ('technician', 'manager', 'admin') then
    raise exception 'Bu işlemi tamamlamak için yetkiniz bulunmuyor.';
  end if;
  if request_row.status::text = 'completed' then
    raise exception 'Bu servis daha önce tamamlanmış.';
  end if;
  if request_row.assigned_technician_id is null then
    raise exception 'Servise teknisyen atanmadı.';
  end if;

  -- Tekniker sahada merkez depoda mevcut bir ürünü kullanabilir. Ürün
  -- araçta yoksa araç stoğu eksiye düşer; toplam firma stoğu yine negatif olamaz.
  v_allow_negative := true;

  if v_auto_stock then
    select id into vehicle_warehouse_id
    from public.warehouses
    where company_id = cid
      and type = 'vehicle'
      and assigned_technician_id = request_row.assigned_technician_id
      and is_active
    order by created_at
    limit 1;

    if vehicle_warehouse_id is null then
      insert into public.warehouses as new_vehicle(company_id, name, type, assigned_technician_id, is_active)
      select cid, coalesce(nullif(btrim(p.full_name), ''), 'Tekniker') || ' Araç Deposu',
             'vehicle', request_row.assigned_technician_id, true
      from public.profiles p
      where p.id = request_row.assigned_technician_id
      returning new_vehicle.id into vehicle_warehouse_id;
    end if;
  end if;

  for item in
    select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_product_id := nullif(item->>'product_id', '')::uuid;
    qty := coalesce((item->>'quantity')::numeric, 0);
    unit_price := greatest(coalesce((item->>'unit_price')::numeric, 0), 0);

    if v_product_id is null or qty <= 0 then
      raise exception 'Ürün ve miktar geçersiz.';
    end if;

    select name into product_name_value
    from public.products
    where id = v_product_id and company_id = cid and is_active;

    if product_name_value is null then
      raise exception 'Aktif ürün bulunamadı.';
    end if;

    if v_auto_stock then
      if vehicle_warehouse_id is null then
        raise exception 'Teknisyen araç deposu bulunamadı.';
      end if;

      select quantity into available_qty
      from public.warehouse_stocks
      where warehouse_id = vehicle_warehouse_id
        and product_id = v_product_id
      for update;

      if not v_allow_negative and coalesce(available_qty, 0) < qty then
        raise exception '% için araç stoğu yetersiz.', product_name_value;
      end if;
    end if;

    product_total := product_total + qty * unit_price;
  end loop;

  total_amount_value := service_amount + extra_amount + product_total;

  if collected > total_amount_value then
    raise exception 'Tahsilat toplam tutardan fazla olamaz.';
  end if;
  if v_require_payment and total_amount_value > 0 and collected <= 0 then
    raise exception 'Firma ayarına göre servis kapatmak için tahsilat zorunludur.';
  end if;
  if not v_allow_partial
     and collected > 0
     and collected < total_amount_value then
    raise exception 'Firma ayarına göre kısmi ödeme kabul edilmiyor.';
  end if;

  insert into public.services(
    company_id, service_request_id, customer_id, technician_id,
    work_description, product_total, labor_amount, discount_amount,
    total_amount, collected_amount, payment_method, completed_at
  ) values (
    cid, request_row.id, request_row.customer_id,
    request_row.assigned_technician_id,
    coalesce(
      nullif(btrim(p_work_description), ''),
      coalesce(request_row.description, 'Servis tamamlandı')
    ),
    product_total, service_amount + extra_amount, 0,
    total_amount_value, collected, v_payment_method, now()
  ) returning id into service_id;

  select case
    when p.role::text = 'secretary' then request_row.created_by
    else c.created_by
  end
  into secretary_value
  from public.customers c
  left join public.profiles p on p.id = request_row.created_by
  where c.id = request_row.customer_id;

  for item in
    select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_product_id := (item->>'product_id')::uuid;
    qty := (item->>'quantity')::numeric;
    unit_price := greatest(coalesce((item->>'unit_price')::numeric, 0), 0);

    select name, coalesce(maintenance_months, 0)
    into product_name_value, maintenance_months_value
    from public.products
    where id = v_product_id;

    insert into public.service_items(
      company_id, service_id, service_request_id, product_id,
      product_name, quantity, unit_price, line_total
    ) values (
      cid, service_id, request_row.id, v_product_id,
      product_name_value, qty, unit_price, qty * unit_price
    );

    if v_auto_stock then
      insert into public.stock_movements(
        company_id, product_id, warehouse_id, service_request_id,
        movement_type, quantity, notes, created_by
      ) values (
        cid, v_product_id, vehicle_warehouse_id, request_row.id,
        'service', qty, 'Servis tamamlamada araç stok çıkışı', uid
      );
    end if;

    if v_calc_maintenance and maintenance_months_value > 0 then
      update public.customer_maintenance_records
      set next_maintenance_date = null
      where company_id = cid
        and customer_id = request_row.customer_id
        and product_id = v_product_id
        and next_maintenance_date is not null;

      insert into public.customer_maintenance_records(
        company_id, customer_id, service_id, product_id, product_name,
        performed_at, next_maintenance_date, assigned_user_id,
        assigned_role, secretary_id, technician_id, notes, created_by
      ) values (
        cid, request_row.customer_id, service_id, v_product_id,
        product_name_value, current_date,
        (current_date + make_interval(months => maintenance_months_value))::date,
        request_row.assigned_technician_id, 'technician', secretary_value,
        request_row.assigned_technician_id,
        coalesce(nullif(btrim(p_work_description), ''), request_row.description),
        uid
      );
    end if;
  end loop;

  if collected > 0 then
    insert into public.payments(
      company_id, customer_id, service_request_id, service_id,
      amount, payment_method, description, payment_date, created_by
    ) values (
      cid, request_row.customer_id, request_row.id, service_id,
      collected, v_payment_method, 'Servis tahsilatı', now(), uid
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
      completion_note = coalesce(
        nullif(btrim(p_work_description), ''),
        request_row.description
      ),
      completed_at = now(),
      updated_at = now()
  where id = request_row.id;

  return service_id;
end;
$$;


grant execute on function public.technician_complete_service_v1(uuid, text, numeric, numeric, numeric, text, jsonb) to authenticated;

notify pgrst, 'reload schema';
