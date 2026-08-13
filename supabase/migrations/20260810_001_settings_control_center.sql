-- ARN ERP - Ayarlar Kontrol Merkezi + güvenli şirket yedekleri
-- Bu migration mevcut ayar tablosunu geriye uyumlu biçimde genişletir.

begin;

alter table public.company_app_settings
  add column if not exists permissions jsonb not null default '{
    "secretary_view_customers": true,
    "secretary_edit_customers": true,
    "secretary_create_service": true,
    "secretary_edit_service": true,
    "secretary_edit_completed_service": true,
    "secretary_view_prices": true,
    "secretary_view_payments": false,
    "secretary_view_stock": false,
    "secretary_excel_transfer": false,
    "technician_view_customers": true,
    "technician_edit_customers": true,
    "technician_create_service": false,
    "technician_edit_service": false,
    "technician_edit_completed_service": false,
    "technician_view_prices": true,
    "technician_view_payments": true,
    "technician_view_stock": true,
    "technician_excel_transfer": false
  }'::jsonb,
  add column if not exists service_rules jsonb not null default '{
    "appointment_time_enabled": true,
    "completed_service_editable": true,
    "technician_can_change_products": true,
    "technician_can_change_price": false,
    "technician_can_collect_payment": true,
    "require_work_description": true,
    "require_product_for_filter_change": true,
    "require_payment_status": true,
    "allow_unassigned_service": true
  }'::jsonb,
  add column if not exists customer_rules jsonb not null default '{
    "duplicate_phone_check": true,
    "phone_required": true,
    "city_required": true,
    "district_required": true,
    "address_required": true,
    "email_visible": false
  }'::jsonb,
  add column if not exists panel_visibility jsonb not null default '{
    "admin": {
      "summary": true,
      "recent_services": true,
      "today_schedule": true,
      "recent_payments": true,
      "announcements": false
    },
    "secretary": {
      "metrics": true,
      "today_summary": true,
      "recent_services": true,
      "quick_actions": true,
      "upcoming_maintenance": true
    },
    "technician": {
      "metrics": true,
      "today_jobs": true,
      "next_job": true,
      "route": true,
      "recent_completed": true
    }
  }'::jsonb,
  add column if not exists backup_policy jsonb not null default '{
    "keep_count": 14,
    "include_notifications": false,
    "include_audit_logs": false
  }'::jsonb;

-- Kullanıcının sadeleştirdiği dört servis türü yeni varsayılan olur.
alter table public.company_app_settings
  alter column enabled_service_types set default
    array['new_installation','filter_change','fault','other']::text[];

update public.company_app_settings
set enabled_service_types = array['new_installation','filter_change','fault','other']::text[]
where enabled_service_types is null
   or enabled_service_types = array[
      'new_installation','filter_change','maintenance','fault','membrane',
      'external_filter','relocation','removal','other'
   ]::text[];

-- Eski tekniker müşteri düzenleme ayarı ile yeni izin matrisi senkron tutulur.
update public.company_app_settings
set permissions = jsonb_set(
  coalesce(permissions, '{}'::jsonb),
  '{technician_edit_customers}',
  to_jsonb(coalesce(allow_technician_customer_edit, true)),
  true
);

create table if not exists public.company_data_backups (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  created_by uuid null references auth.users(id) on delete set null,
  label text null,
  counts jsonb not null default '{}'::jsonb,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists company_data_backups_company_created_idx
  on public.company_data_backups(company_id, created_at desc);

alter table public.company_data_backups enable row level security;

drop policy if exists company_data_backups_admin_select on public.company_data_backups;
create policy company_data_backups_admin_select
on public.company_data_backups
for select to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role()::text in ('admin', 'manager')
);

drop policy if exists company_data_backups_admin_insert on public.company_data_backups;
create policy company_data_backups_admin_insert
on public.company_data_backups
for insert to authenticated
with check (
  company_id = public.current_company_id()
  and public.current_user_role()::text in ('admin', 'manager')
);

drop policy if exists company_data_backups_admin_delete on public.company_data_backups;
create policy company_data_backups_admin_delete
on public.company_data_backups
for delete to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role()::text in ('admin', 'manager')
);

grant select, insert, delete on public.company_data_backups to authenticated;

-- Bir tablonun şirkete ait satırlarını JSON olarak döndürür.
-- Tablo veya company_id kolonu yoksa migration/versiyon farklarında boş dizi döner.
create or replace function public.company_backup_rows_v1(
  p_table text,
  p_company_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows jsonb := '[]'::jsonb;
begin
  if to_regclass(format('public.%I', p_table)) is null then
    return v_rows;
  end if;

  begin
    execute format(
      'select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I t where t.company_id = $1',
      p_table
    ) into v_rows using p_company_id;
  exception
    when undefined_column then
      return '[]'::jsonb;
  end;

  return coalesce(v_rows, '[]'::jsonb);
end;
$$;

revoke all on function public.company_backup_rows_v1(text, uuid) from public;
revoke all on function public.company_backup_rows_v1(text, uuid) from anon;
grant execute on function public.company_backup_rows_v1(text, uuid) to authenticated;

create or replace function public.create_company_backup_v1(
  p_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid := public.current_company_id();
  v_role text := public.current_user_role()::text;
  v_backup_id uuid;
  v_snapshot jsonb;
  v_counts jsonb;
  v_keep integer := 14;
  v_customers jsonb;
  v_devices jsonb;
  v_products jsonb;
  v_warehouses jsonb;
  v_warehouse_stocks jsonb;
  v_stock_movements jsonb;
  v_requests jsonb;
  v_services jsonb;
  v_service_items jsonb;
  v_payments jsonb;
  v_maintenance jsonb;
  v_history jsonb;
  v_notifications jsonb;
  v_settings jsonb;
begin
  if v_company_id is null or v_role not in ('admin', 'manager') then
    raise exception 'Bu işlem için yönetici yetkisi gerekir.';
  end if;

  v_customers := public.company_backup_rows_v1('customers', v_company_id);
  v_devices := public.company_backup_rows_v1('customer_devices', v_company_id);
  v_products := public.company_backup_rows_v1('products', v_company_id);
  v_warehouses := public.company_backup_rows_v1('warehouses', v_company_id);
  v_warehouse_stocks := public.company_backup_rows_v1('warehouse_stocks', v_company_id);
  v_stock_movements := public.company_backup_rows_v1('stock_movements', v_company_id);
  v_requests := public.company_backup_rows_v1('service_requests', v_company_id);
  v_services := public.company_backup_rows_v1('services', v_company_id);
  v_service_items := public.company_backup_rows_v1('service_items', v_company_id);
  v_payments := public.company_backup_rows_v1('payments', v_company_id);
  v_maintenance := public.company_backup_rows_v1('customer_maintenance_records', v_company_id);
  v_history := public.company_backup_rows_v1('historical_customer_sales', v_company_id);
  v_notifications := public.company_backup_rows_v1('app_notifications', v_company_id);
  v_settings := public.company_backup_rows_v1('company_app_settings', v_company_id);

  v_snapshot := jsonb_build_object(
    'format_version', 1,
    'created_at', now(),
    'customers', v_customers,
    'customer_devices', v_devices,
    'products', v_products,
    'warehouses', v_warehouses,
    'warehouse_stocks', v_warehouse_stocks,
    'stock_movements', v_stock_movements,
    'service_requests', v_requests,
    'services', v_services,
    'service_items', v_service_items,
    'payments', v_payments,
    'customer_maintenance_records', v_maintenance,
    'historical_customer_sales', v_history,
    'app_notifications', v_notifications,
    'company_app_settings', v_settings
  );

  v_counts := jsonb_build_object(
    'customers', jsonb_array_length(v_customers),
    'services', jsonb_array_length(v_requests),
    'products', jsonb_array_length(v_products),
    'payments', jsonb_array_length(v_payments),
    'maintenance', jsonb_array_length(v_maintenance),
    'stock_movements', jsonb_array_length(v_stock_movements)
  );

  insert into public.company_data_backups(
    company_id, created_by, label, counts, snapshot
  ) values (
    v_company_id,
    auth.uid(),
    nullif(trim(coalesce(p_label, '')), ''),
    v_counts,
    v_snapshot
  ) returning id into v_backup_id;

  begin
    select greatest(
      1,
      least(50, coalesce((backup_policy->>'keep_count')::integer, 14))
    ) into v_keep
    from public.company_app_settings
    where company_id = v_company_id;
  exception when others then
    v_keep := 14;
  end;

  delete from public.company_data_backups b
  where b.company_id = v_company_id
    and b.id not in (
      select id
      from public.company_data_backups
      where company_id = v_company_id
      order by created_at desc
      limit v_keep
    );

  insert into public.audit_logs(
    company_id, user_id, action, entity_type, entity_id, metadata
  ) values (
    v_company_id,
    auth.uid(),
    'backup_created',
    'company_backup',
    v_backup_id,
    jsonb_build_object('counts', v_counts, 'label', p_label)
  );

  return v_backup_id;
end;
$$;

grant execute on function public.create_company_backup_v1(text) to authenticated;

-- Yedekten yalnızca eksik/silinmiş kayıtları geri getirir.
-- Mevcut veya yedekten sonra oluşturulan kayıtları silmez/değiştirmez.
create or replace function public.restore_missing_snapshot_rows_v1(
  p_table text,
  p_rows jsonb,
  p_company_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_table regclass;
  v_columns text;
  v_pk text;
  v_sql text;
  v_count integer := 0;
begin
  if p_rows is null
     or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) = 0 then
    return 0;
  end if;

  v_table := to_regclass(format('public.%I', p_table));
  if v_table is null then
    return 0;
  end if;

  select string_agg(format('%I', a.attname), ', ' order by a.attnum)
  into v_columns
  from pg_attribute a
  where a.attrelid = v_table
    and a.attnum > 0
    and not a.attisdropped
    and a.attgenerated = '';

  select string_agg(format('%I', a.attname), ', ' order by x.ordinality)
  into v_pk
  from pg_index i
  cross join lateral unnest(i.indkey) with ordinality as x(attnum, ordinality)
  join pg_attribute a
    on a.attrelid = i.indrelid
   and a.attnum = x.attnum
  where i.indrelid = v_table
    and i.indisprimary;

  if v_columns is null or v_pk is null then
    return 0;
  end if;

  -- Çoğu ana tabloda soft-delete (deleted_at) kullanılıyor. Kayıt fiziksel
  -- olarak silinmişse yeniden ekle; aynı PK soft-delete edilmişse yalnızca
  -- deleted_at alanını aç. Mevcut aktif kaydı ASLA ezme.
  if exists (
    select 1
    from pg_attribute a
    where a.attrelid = v_table
      and a.attname = 'deleted_at'
      and a.attnum > 0
      and not a.attisdropped
  ) then
    v_sql := format(
      'insert into public.%I as target (%s) '
      || 'select %s from jsonb_populate_recordset(null::public.%I, $1) as x '
      || 'where x.company_id = $2 '
      || 'on conflict (%s) do update set deleted_at = excluded.deleted_at '
      || 'where target.deleted_at is not null',
      p_table,
      v_columns,
      v_columns,
      p_table,
      v_pk
    );
  else
    v_sql := format(
      'insert into public.%I (%s) '
      || 'select %s from jsonb_populate_recordset(null::public.%I, $1) as x '
      || 'where x.company_id = $2 '
      || 'on conflict (%s) do nothing',
      p_table,
      v_columns,
      v_columns,
      p_table,
      v_pk
    );
  end if;

  begin
    execute v_sql using p_rows, p_company_id;
    get diagnostics v_count = row_count;
  exception
    when undefined_column then
      return 0;
  end;

  return v_count;
end;
$$;

revoke all on function public.restore_missing_snapshot_rows_v1(text, jsonb, uuid) from public;
revoke all on function public.restore_missing_snapshot_rows_v1(text, jsonb, uuid) from anon;
grant execute on function public.restore_missing_snapshot_rows_v1(text, jsonb, uuid) to authenticated;

create or replace function public.restore_company_backup_v1(
  p_backup_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid := public.current_company_id();
  v_role text := public.current_user_role()::text;
  v_snapshot jsonb;
  v_safety_backup uuid;
  v_result jsonb := '{}'::jsonb;
  v_count integer;
begin
  if v_company_id is null or v_role not in ('admin', 'manager') then
    raise exception 'Bu işlem için yönetici yetkisi gerekir.';
  end if;

  select snapshot into v_snapshot
  from public.company_data_backups
  where id = p_backup_id
    and company_id = v_company_id;

  if v_snapshot is null then
    raise exception 'Yedek bulunamadı.';
  end if;

  -- Her geri yüklemeden önce mevcut durumun güvenlik yedeğini al.
  v_safety_backup := public.create_company_backup_v1('Geri yükleme öncesi güvenlik yedeği');

  -- FK bağımlılıklarına göre ebeveynden çocuğa ilerle.
  v_count := public.restore_missing_snapshot_rows_v1(
    'customers', v_snapshot->'customers', v_company_id
  );
  v_result := v_result || jsonb_build_object('customers', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'products', v_snapshot->'products', v_company_id
  );
  v_result := v_result || jsonb_build_object('products', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'warehouses', v_snapshot->'warehouses', v_company_id
  );
  v_result := v_result || jsonb_build_object('warehouses', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'customer_devices', v_snapshot->'customer_devices', v_company_id
  );
  v_result := v_result || jsonb_build_object('customer_devices', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'service_requests', v_snapshot->'service_requests', v_company_id
  );
  v_result := v_result || jsonb_build_object('service_requests', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'services', v_snapshot->'services', v_company_id
  );
  v_result := v_result || jsonb_build_object('services', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'service_items', v_snapshot->'service_items', v_company_id
  );
  v_result := v_result || jsonb_build_object('service_items', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'payments', v_snapshot->'payments', v_company_id
  );
  v_result := v_result || jsonb_build_object('payments', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'customer_maintenance_records',
    v_snapshot->'customer_maintenance_records',
    v_company_id
  );
  v_result := v_result || jsonb_build_object('maintenance', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'historical_customer_sales',
    v_snapshot->'historical_customer_sales',
    v_company_id
  );
  v_result := v_result || jsonb_build_object('historical_sales', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'warehouse_stocks', v_snapshot->'warehouse_stocks', v_company_id
  );
  v_result := v_result || jsonb_build_object('warehouse_stocks', v_count);

  v_count := public.restore_missing_snapshot_rows_v1(
    'stock_movements', v_snapshot->'stock_movements', v_company_id
  );
  v_result := v_result || jsonb_build_object('stock_movements', v_count);

  insert into public.audit_logs(
    company_id, user_id, action, entity_type, entity_id, metadata
  ) values (
    v_company_id,
    auth.uid(),
    'backup_restored',
    'company_backup',
    p_backup_id,
    jsonb_build_object(
      'safety_backup_id', v_safety_backup,
      'restored_missing_rows', v_result
    )
  );

  return jsonb_build_object(
    'safety_backup_id', v_safety_backup,
    'restored', v_result
  );
end;
$$;

grant execute on function public.restore_company_backup_v1(uuid) to authenticated;

-- Ayar değişiklikleri de işlem geçmişine düşsün.
create or replace function public.audit_company_app_settings_v1()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_logs(
    company_id, user_id, action, entity_type, entity_id, old_values, new_values
  ) values (
    new.company_id,
    auth.uid(),
    'settings_updated',
    'company_app_settings',
    new.company_id,
    to_jsonb(old),
    to_jsonb(new)
  );
  return new;
end;
$$;

drop trigger if exists trg_audit_company_app_settings_v1
on public.company_app_settings;
create trigger trg_audit_company_app_settings_v1
after update on public.company_app_settings
for each row
when (old is distinct from new)
execute function public.audit_company_app_settings_v1();

notify pgrst, 'reload schema';

commit;
