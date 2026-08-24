-- ARN ERP - Geciken servislerin sekreter tarafında yeniden planlanması (V2)
-- Akış:
-- 1) Yönetici geciken işi sekretere yollar.
-- 2) Eski servis kaydı geçmişte kalır, sekreter için ayrı bir taslak servis oluşturulur.
-- 3) Sekreter tarih / servis türü / ürün / fiyat / açıklama bilgisini düzenler.
-- 4) Sekreter tek tek veya toplu biçimde yönetici onayına gönderir.
-- 5) Taslak kayıt pending (Onay Bekliyor) olur; yönetici normal onay/atama akışından devam eder.

alter table public.service_requests
  add column if not exists rework_source_service_request_id uuid
    references public.service_requests(id) on delete set null;

create index if not exists idx_service_requests_rework_source_v2
  on public.service_requests(rework_source_service_request_id)
  where rework_source_service_request_id is not null;

-- V1 ile sekretere gönderilmiş fakat henüz yeniden oluşturulmamış kayıtları
-- yeni V2 taslak yapısına dönüştür. Böylece mevcut ekrandaki kayıtlar kaybolmaz.
do $$
declare
  r public.service_requests%rowtype;
  v_secretary_id uuid;
  v_draft_id uuid;
begin
  for r in
    select sr.*
    from public.service_requests sr
    where sr.rework_requested_at is not null
      and sr.rework_completed_at is null
      and sr.rework_source_service_request_id is null
      and sr.status::text = 'could_not_complete'
      and sr.replacement_service_request_id is null
  loop
    v_secretary_id := r.rework_secretary_id;

    if v_secretary_id is null then
      select p.id into v_secretary_id
      from public.profiles p
      where p.company_id = r.company_id
        and p.role::text = 'secretary'
        and coalesce(p.is_active, true) = true
      order by p.full_name nulls last, p.id
      limit 1;
    end if;

    if v_secretary_id is null then
      continue;
    end if;

    insert into public.service_requests(
      company_id,
      customer_id,
      service_type,
      description,
      price,
      status,
      planned_date,
      assigned_technician_id,
      created_by,
      planned_product_id,
      planned_product_name,
      planned_quantity,
      planned_unit_price,
      completion_note,
      route_order,
      route_plan_date,
      rework_requested_at,
      rework_requested_by,
      rework_secretary_id,
      rework_reason,
      rework_completed_at,
      replacement_service_request_id,
      rework_source_service_request_id
    ) values (
      r.company_id,
      r.customer_id,
      r.service_type,
      r.description,
      r.price,
      'deferred',
      null,
      null,
      v_secretary_id,
      r.planned_product_id,
      r.planned_product_name,
      r.planned_quantity,
      r.planned_unit_price,
      '',
      null,
      null,
      coalesce(r.rework_requested_at, now()),
      r.rework_requested_by,
      v_secretary_id,
      coalesce(nullif(r.rework_reason, ''), 'Geciken servis yeniden planlanacak.'),
      null,
      null,
      r.id
    ) returning id into v_draft_id;

    update public.service_requests
    set rework_completed_at = now(),
        replacement_service_request_id = v_draft_id,
        updated_at = now()
    where id = r.id;
  end loop;
end $$;

create or replace function public.send_overdue_service_to_secretary_v1(
  p_service_request_id uuid,
  p_secretary_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_service public.service_requests%rowtype;
  v_customer_name text;
  v_secretary_id uuid;
  v_secretary_name text;
  v_draft_id uuid;
  v_message text;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select p.company_id, p.role::text
    into v_company_id, v_role
  from public.profiles p
  where p.id = v_uid and coalesce(p.is_active, true) = true;

  if v_company_id is null or v_role not in ('admin', 'manager') then
    raise exception 'Bu işlem yalnızca yönetici tarafından yapılabilir.';
  end if;

  select sr.* into v_service
  from public.service_requests sr
  where sr.id = p_service_request_id
    and sr.company_id = v_company_id
  for update;

  if not found then
    raise exception 'Servis kaydı bulunamadı.';
  end if;

  if v_service.planned_date is null or v_service.planned_date::date >= current_date then
    raise exception 'Yalnızca plan tarihi geçmiş servisler sekretere gönderilebilir.';
  end if;

  if v_service.status::text in ('completed', 'cancelled', 'could_not_complete', 'deferred') then
    raise exception 'Bu servis artık aktif geciken iş durumunda değil.';
  end if;

  if v_service.replacement_service_request_id is not null then
    raise exception 'Bu servis daha önce yeniden planlama akışına gönderilmiş.';
  end if;

  select coalesce(nullif(trim(c.full_name), ''), nullif(trim(c.company_name), ''), 'Müşteri')
    into v_customer_name
  from public.customers c
  where c.id = v_service.customer_id;

  if p_secretary_id is not null then
    select p.id, coalesce(nullif(trim(p.full_name), ''), 'Sekreter')
      into v_secretary_id, v_secretary_name
    from public.profiles p
    where p.id = p_secretary_id
      and p.company_id = v_company_id
      and p.role::text = 'secretary'
      and coalesce(p.is_active, true) = true;
  end if;

  if v_secretary_id is null and v_service.created_by is not null then
    select p.id, coalesce(nullif(trim(p.full_name), ''), 'Sekreter')
      into v_secretary_id, v_secretary_name
    from public.profiles p
    where p.id = v_service.created_by
      and p.company_id = v_company_id
      and p.role::text = 'secretary'
      and coalesce(p.is_active, true) = true;
  end if;

  if v_secretary_id is null then
    select p.id, coalesce(nullif(trim(p.full_name), ''), 'Sekreter')
      into v_secretary_id, v_secretary_name
    from public.profiles p
    where p.company_id = v_company_id
      and p.role::text = 'secretary'
      and coalesce(p.is_active, true) = true
    order by p.full_name nulls last, p.id
    limit 1;
  end if;

  if v_secretary_id is null then
    raise exception 'Aktif sekreter bulunamadı.';
  end if;

  -- Sekreterin düzenleyeceği YENİ taslak kayıt. Eski işin kendisi değiştirilmez.
  insert into public.service_requests(
    company_id,
    customer_id,
    service_type,
    description,
    price,
    status,
    planned_date,
    assigned_technician_id,
    created_by,
    planned_product_id,
    planned_product_name,
    planned_quantity,
    planned_unit_price,
    completion_note,
    route_order,
    route_plan_date,
    rework_requested_at,
    rework_requested_by,
    rework_secretary_id,
    rework_reason,
    rework_completed_at,
    replacement_service_request_id,
    rework_source_service_request_id
  ) values (
    v_service.company_id,
    v_service.customer_id,
    v_service.service_type,
    v_service.description,
    v_service.price,
    'deferred',
    null,
    null,
    v_secretary_id,
    v_service.planned_product_id,
    v_service.planned_product_name,
    v_service.planned_quantity,
    v_service.planned_unit_price,
    '',
    null,
    null,
    now(),
    v_uid,
    v_secretary_id,
    'Geciken servis sekreter tarafından yeniden planlanacak.',
    null,
    null,
    v_service.id
  ) returning id into v_draft_id;

  -- Eski kayıt geçmişte kalsın; aktif listede yeni taslak üzerinden devam edilir.
  update public.service_requests
  set status = 'could_not_complete',
      assigned_technician_id = null,
      route_order = null,
      route_plan_date = null,
      rework_requested_at = now(),
      rework_requested_by = v_uid,
      rework_secretary_id = v_secretary_id,
      rework_reason = 'Geciken servis sekretere yeniden planlama için gönderildi.',
      rework_completed_at = now(),
      replacement_service_request_id = v_draft_id,
      completion_note = trim(concat_ws(E'\n', nullif(completion_note, ''),
        '[Sekretere Gönderildi] Yeni servis taslağı oluşturuldu.')),
      updated_at = now()
  where id = v_service.id;

  v_message := coalesce(v_customer_name, 'Müşteri') ||
               ' için geciken servis yeniden planlama amacıyla size gönderildi. ' ||
               'Tarih, servis türü, ürün ve fiyat bilgisini kontrol edip yöneticiye gönderin.';

  insert into public.app_notifications(
    company_id, user_id, title, message, notification_type, route, entity_type, entity_id
  ) values (
    v_company_id,
    v_secretary_id,
    'Servisi yeniden planlayın',
    v_message,
    'overdue_rework',
    '/secretary/service-requests',
    'service_request',
    v_draft_id
  );

  return jsonb_build_object(
    'ok', true,
    'status', 'deferred',
    'secretary_id', v_secretary_id,
    'secretary_name', v_secretary_name,
    'draft_service_request_id', v_draft_id
  );
end;
$$;

create or replace function public.submit_rework_service_to_manager_v2(
  p_service_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company_id uuid;
  v_role text;
  v_request public.service_requests%rowtype;
  v_customer_name text;
  v_message text;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select p.company_id, p.role::text
    into v_company_id, v_role
  from public.profiles p
  where p.id = v_uid and coalesce(p.is_active, true) = true;

  if v_company_id is null or v_role <> 'secretary' then
    raise exception 'Bu işlem yalnızca sekreter tarafından yapılabilir.';
  end if;

  select sr.* into v_request
  from public.service_requests sr
  where sr.id = p_service_request_id
    and sr.company_id = v_company_id
  for update;

  if not found then
    raise exception 'Servis kaydı bulunamadı.';
  end if;

  if v_request.rework_source_service_request_id is null
     or v_request.rework_requested_at is null
     or v_request.rework_completed_at is not null then
    raise exception 'Bu kayıt sekreter yeniden planlama kuyruğunda değil.';
  end if;

  if v_request.rework_secretary_id is distinct from v_uid then
    raise exception 'Bu servis size gönderilmemiş.';
  end if;

  if v_request.planned_date is null then
    raise exception 'Yöneticiye göndermeden önce servis tarihi belirlenmelidir.';
  end if;

  update public.service_requests
  set status = 'pending',
      assigned_technician_id = null,
      route_order = null,
      route_plan_date = null,
      rework_completed_at = now(),
      rework_reason = trim(concat_ws(E'\n', nullif(rework_reason, ''),
        '[Sekreter] Düzenlendi ve yönetici onayına gönderildi.')),
      updated_at = now()
  where id = p_service_request_id;

  select coalesce(nullif(trim(c.full_name), ''), nullif(trim(c.company_name), ''), 'Müşteri')
    into v_customer_name
  from public.customers c
  where c.id = v_request.customer_id;

  v_message := coalesce(v_customer_name, 'Müşteri') ||
               ' için yeniden planlanan servis yönetici onayı bekliyor.';

  insert into public.app_notifications(
    company_id, user_id, title, message, notification_type, route, entity_type, entity_id
  )
  select
    v_company_id,
    p.id,
    'Yeniden planlanan servis onay bekliyor',
    v_message,
    'rework_pending_approval',
    '/manager/service-requests',
    'service_request',
    p_service_request_id
  from public.profiles p
  where p.company_id = v_company_id
    and p.role::text in ('admin', 'manager')
    and coalesce(p.is_active, true) = true;

  return jsonb_build_object(
    'ok', true,
    'service_request_id', p_service_request_id,
    'status', 'pending'
  );
end;
$$;

-- Eski istemci çağrısı kalırsa da artık yeni kayıt üretmek yerine mevcut taslağı
-- yönetici onayına gönder. Böylece aynı işin iki kez kopyalanması engellenir.
create or replace function public.recreate_service_from_rework_v1(
  p_service_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  v_result := public.submit_rework_service_to_manager_v2(p_service_request_id);
  return jsonb_build_object(
    'ok', true,
    'new_service_request_id', p_service_request_id,
    'status', 'pending',
    'result', v_result
  );
end;
$$;

grant execute on function public.send_overdue_service_to_secretary_v1(uuid, uuid) to authenticated;
grant execute on function public.submit_rework_service_to_manager_v2(uuid) to authenticated;
grant execute on function public.recreate_service_from_rework_v1(uuid) to authenticated;
grant update on table public.service_requests to authenticated;

-- Servis listesinde sekreter yalnız kendi kayıtlarını ve kendisine atanmış aktif
-- yeniden-planlama taslaklarını görür. Yenisi oluşturulmuş eski geciken kayıt
-- aynı listede ikinci kez görünmez.
do $$
declare
  r record;
begin
  for r in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'service_requests'
      and cmd = 'SELECT'
  loop
    execute format('drop policy if exists %I on public.service_requests', r.policyname);
  end loop;
end $$;

create policy service_requests_select_role_scope_v2
on public.service_requests
for select
to authenticated
using (
  company_id = (select company_id from public.profiles where id = auth.uid())
  and coalesce((select is_active from public.profiles where id = auth.uid()), false) = true
  and (
    (select role::text from public.profiles where id = auth.uid()) in ('admin', 'manager')
    or (
      (select role::text from public.profiles where id = auth.uid()) = 'secretary'
      and (
        (
          created_by = auth.uid()
          and not (
            status::text = 'could_not_complete'
            and replacement_service_request_id is not null
            and rework_source_service_request_id is null
            and rework_completed_at is not null
          )
        )
        or (
          rework_secretary_id = auth.uid()
          and rework_source_service_request_id is not null
          and rework_completed_at is null
        )
      )
    )
    or (
      (select role::text from public.profiles where id = auth.uid()) = 'technician'
      and assigned_technician_id = auth.uid()
    )
  )
);

drop policy if exists service_requests_update_secretary_rework_v2 on public.service_requests;
create policy service_requests_update_secretary_rework_v2
on public.service_requests
for update
to authenticated
using (
  company_id = (select company_id from public.profiles where id = auth.uid())
  and (select role::text from public.profiles where id = auth.uid()) = 'secretary'
  and rework_secretary_id = auth.uid()
  and rework_source_service_request_id is not null
  and rework_completed_at is null
)
with check (
  company_id = (select company_id from public.profiles where id = auth.uid())
  and rework_secretary_id = auth.uid()
  and rework_source_service_request_id is not null
);

notify pgrst, 'reload schema';
