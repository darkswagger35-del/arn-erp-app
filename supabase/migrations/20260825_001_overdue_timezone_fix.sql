-- ARN ERP V12 - Geciken servis saat dilimi duzeltmesi
-- 25.08.2026
-- Sorun: Uygulama Türkiye saatine göre yeni güne geçerken PostgreSQL current_date
-- UTC gününde kalabiliyor. Bu yüzden ekranda geciken görünen servis RPC tarafından reddediliyordu.
-- Çözüm: Geciken servis kontrolü Europe/Istanbul takvim gününe göre yapılır.

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

  if v_service.planned_date is null
     or (v_service.planned_date at time zone 'Europe/Istanbul')::date
        >= (now() at time zone 'Europe/Istanbul')::date then
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
  set status = 'deferred',
      -- Kaynak kayıt geçmiş olarak tekniker üzerinde kalır; bu bir başarısızlık değildir.
      assigned_technician_name_snapshot = coalesce(
        nullif(btrim(assigned_technician_name_snapshot), ''),
        (select nullif(btrim(p.full_name), '') from public.profiles p
         where p.id = assigned_technician_id)
      ),
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

grant execute on function public.send_overdue_service_to_secretary_v1(uuid, uuid) to authenticated;
