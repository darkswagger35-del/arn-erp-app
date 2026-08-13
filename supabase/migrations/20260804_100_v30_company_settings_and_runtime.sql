-- ARN ERP V30 - Firma tarafından yönetilebilir uygulama ayarları

begin;

create table if not exists public.company_app_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  on_my_way_template text not null default
    'Merhaba {{musteri}}, ARN Su Arıtma teknik servis ekibiyim. Adresinize geliyorum.',
  appointment_template text not null default
    'Merhaba {{musteri}}, {{tarih}} tarihli servis randevunuz oluşturulmuştur. İşlem: {{servis_turu}}. Teknik personel: {{teknisyen}}.',
  service_completed_template text not null default
    'Merhaba {{musteri}}, servis işleminiz tamamlanmıştır. Tutar: {{tutar}}.',
  service_form_title text not null default 'ARN SU ARITMA SERVİS FORMU',
  service_form_footer text not null default
    'Hizmetimizi tercih ettiğiniz için teşekkür ederiz.',
  show_prices_on_form boolean not null default true,
  show_signature_on_form boolean not null default true,
  show_customer_address_on_form boolean not null default true,
  enabled_service_types text[] not null default array[
    'new_installation','filter_change','maintenance','fault','membrane',
    'external_filter','relocation','removal','other'
  ]::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.company_app_settings
  add column if not exists maintenance_reminder_days integer not null default 10,
  add column if not exists show_overdue_maintenances boolean not null default true,
  add column if not exists hide_products_without_maintenance boolean not null default true,
  add column if not exists calculate_maintenance_from_product boolean not null default true,
  add column if not exists only_latest_product_maintenance boolean not null default true,
  add column if not exists auto_decrease_stock_on_service boolean not null default true,
  add column if not exists auto_add_new_product_to_main_warehouse boolean not null default true,
  add column if not exists default_initial_stock numeric(12,2) not null default 0,
  add column if not exists allow_negative_stock boolean not null default false,
  add column if not exists critical_stock_notifications boolean not null default true,
  add column if not exists allow_technician_customer_edit boolean not null default true,
  add column if not exists allow_technician_history_edit boolean not null default false,
  add column if not exists require_payment_to_complete_service boolean not null default false,
  add column if not exists allow_partial_payment boolean not null default true,
  add column if not exists default_payment_method text not null default 'cash',
  add column if not exists enabled_payment_methods text[] not null default array['cash','card','transfer','open_account']::text[],
  add column if not exists technician_assignment_notifications boolean not null default true,
  add column if not exists maintenance_notifications boolean not null default true;

alter table public.company_app_settings enable row level security;

drop policy if exists company_app_settings_select on public.company_app_settings;
create policy company_app_settings_select
on public.company_app_settings
for select to authenticated
using (company_id = public.current_company_id());

drop policy if exists company_app_settings_manage on public.company_app_settings;
create policy company_app_settings_manage
on public.company_app_settings
for all to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role()::text in ('admin', 'manager')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_role()::text in ('admin', 'manager')
);

grant select, insert, update, delete on public.company_app_settings to authenticated;

insert into public.company_app_settings(company_id)
select c.id
from public.companies c
where not exists (
  select 1 from public.company_app_settings s where s.company_id = c.id
);

update public.company_app_settings
set maintenance_reminder_days = 10
where maintenance_reminder_days is null
   or maintenance_reminder_days < 1
   or maintenance_reminder_days > 365;

alter table public.company_app_settings
  drop constraint if exists company_app_settings_maintenance_days_check;

alter table public.company_app_settings
  add constraint company_app_settings_maintenance_days_check
  check (maintenance_reminder_days between 1 and 365);

alter table public.company_app_settings
  drop constraint if exists company_app_settings_default_stock_check;

alter table public.company_app_settings
  add constraint company_app_settings_default_stock_check
  check (default_initial_stock >= 0);

-- Yeni ürünün ana depoya eklenmesi firma ayarına göre çalışır.
create or replace function public.sync_product_to_main_warehouse_v30()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wh uuid;
  v_enabled boolean := true;
  v_default_stock numeric(12,2) := 0;
  v_quantity numeric(12,2);
begin
  select
    coalesce(auto_add_new_product_to_main_warehouse, true),
    greatest(coalesce(default_initial_stock, 0), 0)
  into v_enabled, v_default_stock
  from public.company_app_settings
  where company_id = new.company_id;

  if not coalesce(v_enabled, true) then
    return new;
  end if;

  select id into v_wh
  from public.warehouses
  where company_id = new.company_id
    and type = 'main'
    and is_active = true
  order by created_at
  limit 1;

  if v_wh is null then
    insert into public.warehouses(company_id, name, type, is_active)
    values(new.company_id, 'Ana Depo', 'main', true)
    returning id into v_wh;
  end if;

  v_quantity := case
    when coalesce(new.stock_quantity, 0) > 0 then new.stock_quantity
    when tg_op = 'INSERT' then v_default_stock
    else 0
  end;

  insert into public.warehouse_stocks(
    company_id, warehouse_id, product_id, quantity, updated_at
  ) values (
    new.company_id, v_wh, new.id, greatest(v_quantity, 0), now()
  )
  on conflict(warehouse_id, product_id) do update
    set quantity = greatest(excluded.quantity, 0),
        updated_at = now();

  return new;
end;
$$;

drop trigger if exists trg_sync_product_to_main_warehouse_v25
on public.products;
drop trigger if exists trg_sync_product_to_main_warehouse_v30
on public.products;

create trigger trg_sync_product_to_main_warehouse_v30
after insert or update of stock_quantity
on public.products
for each row
execute function public.sync_product_to_main_warehouse_v30();

-- İş atama bildirimi firma ayarına göre oluşturulur.
create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  message text not null default '',
  notification_type text not null default 'info',
  route text,
  entity_type text,
  entity_id uuid,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.app_notifications enable row level security;

drop policy if exists app_notifications_select_own
on public.app_notifications;
create policy app_notifications_select_own
on public.app_notifications
for select to authenticated
using(user_id = auth.uid());

drop policy if exists app_notifications_update_own
on public.app_notifications;
create policy app_notifications_update_own
on public.app_notifications
for update to authenticated
using(user_id = auth.uid())
with check(user_id = auth.uid());

grant select, update on public.app_notifications to authenticated;

create or replace function public.notify_service_assignment_v30()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer text;
  v_company uuid;
  v_enabled boolean := true;
begin
  if new.assigned_technician_id is null
     or old.assigned_technician_id is not distinct from new.assigned_technician_id then
    return new;
  end if;

  select
    coalesce(nullif(full_name, ''), nullif(company_name, ''), 'Müşteri'),
    company_id
  into v_customer, v_company
  from public.customers
  where id = new.customer_id;

  select coalesce(technician_assignment_notifications, true)
  into v_enabled
  from public.company_app_settings
  where company_id = coalesce(new.company_id, v_company);

  if not coalesce(v_enabled, true) then
    return new;
  end if;

  insert into public.app_notifications(
    company_id, user_id, title, message, notification_type,
    route, entity_type, entity_id
  ) values (
    coalesce(new.company_id, v_company),
    new.assigned_technician_id,
    'Yeni servis atandı',
    coalesce(v_customer, 'Müşteri') ||
      case
        when new.planned_date is null then ''
        else ' • ' || to_char(
          new.planned_date at time zone 'Europe/Istanbul',
          'DD.MM.YYYY HH24:MI'
        )
      end,
    'service_assignment',
    '/technician/jobs/' || new.id::text,
    'service_request',
    new.id
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_service_assignment_v25
on public.service_requests;
drop trigger if exists trg_notify_service_assignment_v30
on public.service_requests;

create trigger trg_notify_service_assignment_v30
after update of assigned_technician_id
on public.service_requests
for each row
execute function public.notify_service_assignment_v30();

-- Bakım süresi kapatılan ürünlerin bakım tarihlerini temizler;
-- süre değişirse her müşteri için yalnız en güncel kaydı yeniden hesaplar.
create or replace function public.sync_product_maintenance_dates_v30()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean := true;
begin
  if new.maintenance_months is not distinct from old.maintenance_months then
    return new;
  end if;

  select coalesce(calculate_maintenance_from_product, true)
  into v_enabled
  from public.company_app_settings
  where company_id = new.company_id;

  update public.customer_maintenance_records
  set next_maintenance_date = null
  where product_id = new.id;

  if coalesce(v_enabled, true) and coalesce(new.maintenance_months, 0) > 0 then
    with latest as (
      select distinct on (company_id, customer_id)
        id, performed_at
      from public.customer_maintenance_records
      where product_id = new.id
      order by company_id, customer_id, performed_at desc, created_at desc
    )
    update public.customer_maintenance_records cmr
    set next_maintenance_date =
      (latest.performed_at::date +
        make_interval(months => new.maintenance_months))::date
    from latest
    where cmr.id = latest.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_product_maintenance_dates
on public.products;
drop trigger if exists trg_sync_product_maintenance_dates_v30
on public.products;

create trigger trg_sync_product_maintenance_dates_v30
after update of maintenance_months
on public.products
for each row
execute function public.sync_product_maintenance_dates_v30();


-- Servis kapatma davranışı da firma ayarlarından okunur.
create or replace function public.complete_service_v5(
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

  if v_auto_stock then
    select id into vehicle_warehouse_id
    from public.warehouses
    where company_id = cid
      and type = 'vehicle'
      and assigned_technician_id = request_row.assigned_technician_id
      and is_active
    order by created_at
    limit 1;
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

grant execute on function public.complete_service_v5(
  uuid, text, numeric, numeric, numeric, text, jsonb
) to authenticated;

notify pgrst, 'reload schema';

commit;
