-- ARN ERP V15
-- Müşteri kalıcı silme, tamamlanan servis silme, eski müşteri kaydı ve PostgREST önbellek yenileme.

-- 1) Tamamlanan servisi sil; tahsilatı/cirroyu kaldır ve kullanılan stoğu araca geri koy.
drop function if exists public.delete_completed_service_v11(uuid);
create function public.delete_completed_service_v11(p_service_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_request public.service_requests%rowtype;
  v_service record;
  v_vehicle_id uuid;
  v_item record;
begin
  select company_id, role
    into v_company_id, v_role
  from public.profiles
  where id = v_uid and is_active = true;

  if v_company_id is null or v_role not in ('admin', 'manager') then
    raise exception 'Bu işlemi yalnızca yönetici yapabilir.';
  end if;

  select * into v_request
  from public.service_requests
  where id = p_service_request_id and company_id = v_company_id
  for update;

  if not found then
    raise exception 'Servis talebi bulunamadı.';
  end if;
  if v_request.status <> 'completed' then
    raise exception 'Yalnızca tamamlanan servis silinebilir.';
  end if;

  select id into v_vehicle_id
  from public.warehouses
  where company_id = v_company_id
    and type = 'vehicle'
    and assigned_technician_id = v_request.assigned_technician_id
    and is_active = true
  order by created_at nulls last, id
  limit 1;

  for v_service in
    select id from public.services
    where company_id = v_company_id
      and service_request_id = p_service_request_id
  loop
    for v_item in
      select product_id, sum(quantity)::numeric as quantity
      from public.service_items
      where service_id = v_service.id and product_id is not null
      group by product_id
    loop
      if v_vehicle_id is not null and coalesce(v_item.quantity, 0) > 0 then
        insert into public.stock_movements(
          company_id, product_id, warehouse_id, service_request_id,
          movement_type, quantity, notes, created_by
        ) values (
          v_company_id, v_item.product_id, v_vehicle_id, null,
          'in', v_item.quantity,
          'Tamamlanan servis silindi; ürün araç stoğuna geri eklendi', v_uid
        );
      end if;
    end loop;

    -- Bazı kurulumlarda bakım tablosunda service_id vardır, bazılarında yoktur.
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'customer_maintenance_records'
        and column_name = 'service_id'
    ) then
      execute 'delete from public.customer_maintenance_records where service_id = $1'
      using v_service.id;
    end if;
  end loop;

  delete from public.payments
  where company_id = v_company_id
    and (service_request_id = p_service_request_id
         or service_id in (
           select id from public.services
           where company_id = v_company_id and service_request_id = p_service_request_id
         ));

  delete from public.service_items
  where service_id in (
    select id from public.services
    where company_id = v_company_id and service_request_id = p_service_request_id
  );

  delete from public.services
  where company_id = v_company_id and service_request_id = p_service_request_id;

  delete from public.stock_movements
  where company_id = v_company_id
    and service_request_id = p_service_request_id;

  delete from public.service_requests
  where company_id = v_company_id and id = p_service_request_id;
end;
$$;
grant execute on function public.delete_completed_service_v11(uuid) to authenticated;

-- 2) Müşteriyi ve bağlı operasyon kayıtlarını doğru FK sırasıyla kalıcı sil.
drop function if exists public.hard_delete_customer(uuid);
create function public.hard_delete_customer(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  v_role text;
begin
  select company_id, role into v_company_id, v_role
  from public.profiles
  where id = v_uid and is_active = true;

  if v_company_id is null or v_role not in ('admin', 'manager', 'secretary') then
    raise exception 'Bu işlem için yetkiniz bulunmuyor.';
  end if;

  if not exists (
    select 1 from public.customers
    where id = p_customer_id and company_id = v_company_id
  ) then
    raise exception 'Müşteri bulunamadı.';
  end if;

  if to_regclass('public.customer_portal_tokens') is not null then
    delete from public.customer_portal_tokens where customer_id = p_customer_id and company_id = v_company_id;
  end if;
  if to_regclass('public.historical_customer_sales') is not null then
    delete from public.historical_customer_sales where customer_id = p_customer_id and company_id = v_company_id;
  end if;
  if to_regclass('public.customer_maintenance_records') is not null then
    delete from public.customer_maintenance_records where customer_id = p_customer_id and company_id = v_company_id;
  end if;
  if to_regclass('public.customer_devices') is not null then
    delete from public.customer_devices where customer_id = p_customer_id and company_id = v_company_id;
  end if;

  delete from public.payments
  where company_id = v_company_id and customer_id = p_customer_id;

  delete from public.service_items
  where service_id in (
    select id from public.services
    where company_id = v_company_id and customer_id = p_customer_id
  );

  delete from public.services
  where company_id = v_company_id and customer_id = p_customer_id;

  -- services silindikten sonra request FK engeli kalmaz.
  delete from public.service_items
  where service_request_id in (
    select id from public.service_requests
    where company_id = v_company_id and customer_id = p_customer_id
  );

  delete from public.stock_movements
  where company_id = v_company_id
    and service_request_id in (
      select id from public.service_requests
      where company_id = v_company_id and customer_id = p_customer_id
    );

  delete from public.payments
  where company_id = v_company_id
    and service_request_id in (
      select id from public.service_requests
      where company_id = v_company_id and customer_id = p_customer_id
    );

  delete from public.service_requests
  where company_id = v_company_id and customer_id = p_customer_id;

  delete from public.customers
  where company_id = v_company_id and id = p_customer_id;
end;
$$;
grant execute on function public.hard_delete_customer(uuid) to authenticated;

-- 3) Geçmiş tarihli müşteri + ürün + ödeme/bakım kaydı.
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
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  v_customer_id uuid;
  v_product_name text;
  v_next_date date;
begin
  select company_id into v_company_id
  from public.profiles
  where id = v_uid and is_active = true and role in ('admin','manager','secretary');

  if v_company_id is null then raise exception 'Yetkiniz yok.'; end if;
  if btrim(coalesce(p_full_name,'')) = '' then raise exception 'Ad soyad zorunludur.'; end if;
  if btrim(coalesce(p_phone,'')) = '' then raise exception 'Telefon zorunludur.'; end if;
  if coalesce(p_quantity,0) <= 0 then raise exception 'Adet 0’dan büyük olmalıdır.'; end if;
  if p_payment_status = 'debt' and p_payment_due_date is null then raise exception 'Ödeme tarihi zorunludur.'; end if;

  select name into v_product_name
  from public.products
  where id = p_product_id and company_id = v_company_id and is_active = true;
  if v_product_name is null then raise exception 'Ürün bulunamadı.'; end if;

  insert into public.customers(
    company_id, customer_type, full_name, phone, city, district, address,
    registration_date, is_active, created_by, updated_by
  ) values (
    v_company_id, 'individual', btrim(p_full_name), btrim(p_phone),
    btrim(p_city), btrim(p_district), btrim(p_address),
    p_record_date, true, v_uid, v_uid
  ) returning id into v_customer_id;

  if to_regclass('public.historical_customer_sales') is not null then
    insert into public.historical_customer_sales(
      company_id, customer_id, product_id, product_name, quantity, amount,
      payment_status, payment_due_date, transaction_date, created_by
    ) values (
      v_company_id, v_customer_id, p_product_id, v_product_name, p_quantity,
      greatest(coalesce(p_amount,0),0), p_payment_status,
      case when p_payment_status='debt' then p_payment_due_date else null end,
      p_record_date, v_uid
    );
  end if;

  if coalesce(p_maintenance_months,0) > 0 then
    v_next_date := (p_record_date + make_interval(months => p_maintenance_months))::date;
    insert into public.customer_maintenance_records(
      company_id, customer_id, product_id, product_name,
      performed_at, next_maintenance_date, assigned_role, notes, created_by
    ) values (
      v_company_id, v_customer_id, p_product_id, v_product_name,
      p_record_date, v_next_date, 'secretary',
      'Geçmiş müşteri kaydından oluşturuldu. Adet: ' || p_quantity, v_uid
    );
  end if;

  return v_customer_id;
end;
$$;
grant execute on function public.create_historical_customer_v11(text,text,text,text,text,date,uuid,numeric,numeric,text,date,integer) to authenticated;

-- PostgREST yeni RPC imzalarını hemen görsün.
notify pgrst, 'reload schema';
