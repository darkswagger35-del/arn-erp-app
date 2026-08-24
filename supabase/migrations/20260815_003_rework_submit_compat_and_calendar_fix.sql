-- ARN ERP - Sekreter yeniden planlama gönderim uyumluluk düzeltmesi (V3)
-- 001 (eski tek-kayıt akışı) ve 002 (taslak akışı) kurulumlarının ikisinde de
-- sekreterin düzenlediği yeni tarih / servis türü / ürün / fiyat bilgileriyle
-- yönetici onayına güvenli biçimde gönderebilmesini sağlar.

alter table public.service_requests
  add column if not exists rework_source_service_request_id uuid
    references public.service_requests(id) on delete set null;

create or replace function public.submit_rework_service_to_manager_v3(
  p_service_request_id uuid,
  p_planned_date timestamptz default null,
  p_service_type text default null,
  p_description text default null,
  p_product_id uuid default null,
  p_product_name text default null,
  p_quantity numeric default null,
  p_unit_price numeric default null,
  p_price numeric default null
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
  v_new_id uuid;
  v_customer_name text;
  v_effective_date timestamptz;
  v_message text;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select p.company_id, p.role::text
    into v_company_id, v_role
  from public.profiles p
  where p.id = v_uid
    and coalesce(p.is_active, true) = true;

  if v_company_id is null or v_role <> 'secretary' then
    raise exception 'Bu işlem yalnızca sekreter tarafından yapılabilir.';
  end if;

  select sr.*
    into v_request
  from public.service_requests sr
  where sr.id = p_service_request_id
    and sr.company_id = v_company_id
  for update;

  if not found then
    raise exception 'Servis kaydı bulunamadı.';
  end if;

  if v_request.rework_requested_at is null
     or v_request.rework_completed_at is not null then
    raise exception 'Bu kayıt sekreter yeniden planlama kuyruğunda değil.';
  end if;

  if v_request.rework_secretary_id is distinct from v_uid
     and v_request.created_by is distinct from v_uid then
    raise exception 'Bu servis size gönderilmemiş.';
  end if;

  v_effective_date := coalesce(p_planned_date, v_request.planned_date);
  if v_effective_date is null then
    raise exception 'Yöneticiye göndermeden önce yeni servis tarihi belirlenmelidir.';
  end if;

  select coalesce(
           nullif(trim(c.full_name), ''),
           nullif(trim(c.company_name), ''),
           'Müşteri'
         )
    into v_customer_name
  from public.customers c
  where c.id = v_request.customer_id;

  if v_request.rework_source_service_request_id is not null then
    -- 002 taslak akışı: aynı taslak kayıt yönetici onayına çevrilir.
    update public.service_requests
    set service_type = v_request.service_type,
        planned_date = v_effective_date,
        description = v_request.description,
        planned_product_id = v_request.planned_product_id,
        planned_product_name = v_request.planned_product_name,
        planned_quantity = v_request.planned_quantity,
        planned_unit_price = v_request.planned_unit_price,
        price = v_request.price,
        status = 'pending',
        assigned_technician_id = null,
        route_order = null,
        route_plan_date = null,
        rework_completed_at = now(),
        rework_reason = trim(concat_ws(E'\n', nullif(v_request.rework_reason, ''),
          '[Sekreter] Düzenlendi ve yönetici onayına gönderildi.')),
        updated_at = now()
    where id = v_request.id
    returning id into v_new_id;
  else
    -- 001 eski akış: geçmiş kaydı değiştirmeden yeni pending servis oluşturulur.
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
      route_plan_date
    ) values (
      v_request.company_id,
      v_request.customer_id,
      v_request.service_type,
      v_request.description,
      v_request.price,
      'pending',
      v_effective_date,
      null,
      v_uid,
      v_request.planned_product_id,
      v_request.planned_product_name,
      v_request.planned_quantity,
      v_request.planned_unit_price,
      '',
      null,
      null
    ) returning id into v_new_id;

    update public.service_requests
    set rework_completed_at = now(),
        replacement_service_request_id = v_new_id,
        status = 'could_not_complete',
        assigned_technician_id = null,
        route_order = null,
        route_plan_date = null,
        rework_reason = trim(concat_ws(E'\n', nullif(v_request.rework_reason, ''),
          '[Sekreter] Yeniden planlandı ve yönetici onayına gönderildi.')),
        updated_at = now()
    where id = v_request.id;
  end if;

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
    v_new_id
  from public.profiles p
  where p.company_id = v_company_id
    and p.role::text in ('admin', 'manager')
    and coalesce(p.is_active, true) = true;

  return jsonb_build_object(
    'ok', true,
    'service_request_id', v_new_id,
    'status', 'pending'
  );
end;
$$;

grant execute on function public.submit_rework_service_to_manager_v3(
  uuid, timestamptz, text, text, uuid, text, numeric, numeric, numeric
) to authenticated;

notify pgrst, 'reload schema';
