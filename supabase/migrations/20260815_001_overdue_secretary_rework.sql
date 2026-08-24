-- ARN ERP - Geciken servisleri sekretere geri gönderme / yeniden servis akışı
-- Yönetici geciken işi ilgili sekretere yollar; eski kayıt geçmişte kalır.
-- Sekreter tek tuşla aynı müşteri için yeni bir Onay Bekliyor servis kaydı oluşturur.

alter table public.service_requests
  add column if not exists rework_requested_at timestamptz,
  add column if not exists rework_requested_by uuid references auth.users(id) on delete set null,
  add column if not exists rework_secretary_id uuid references auth.users(id) on delete set null,
  add column if not exists rework_reason text,
  add column if not exists rework_completed_at timestamptz,
  add column if not exists replacement_service_request_id uuid references public.service_requests(id) on delete set null;

create index if not exists idx_service_requests_rework_secretary
  on public.service_requests(rework_secretary_id, rework_requested_at desc)
  where rework_requested_at is not null and rework_completed_at is null;

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
  v_actor_name text;
  v_service_company uuid;
  v_customer_name text;
  v_created_by uuid;
  v_secretary_id uuid;
  v_secretary_name text;
  v_planned_date timestamptz;
  v_status text;
  v_message text;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select company_id, role::text, coalesce(nullif(trim(full_name), ''), 'Yönetici')
    into v_company_id, v_role, v_actor_name
  from public.profiles
  where id = v_uid and coalesce(is_active, true) = true;

  if v_company_id is null or v_role not in ('admin', 'manager') then
    raise exception 'Bu işlem yalnızca yönetici tarafından yapılabilir.';
  end if;

  select sr.company_id, sr.created_by, sr.planned_date, sr.status::text,
         coalesce(nullif(trim(c.full_name), ''), nullif(trim(c.company_name), ''), 'Müşteri')
    into v_service_company, v_created_by, v_planned_date, v_status, v_customer_name
  from public.service_requests sr
  left join public.customers c on c.id = sr.customer_id
  where sr.id = p_service_request_id
  for update of sr;

  if not found or v_service_company is distinct from v_company_id then
    raise exception 'Servis kaydı bulunamadı.';
  end if;

  if v_planned_date is null or v_planned_date::date >= current_date then
    raise exception 'Yalnızca plan tarihi geçmiş servisler sekretere gönderilebilir.';
  end if;

  if v_status in ('completed', 'cancelled', 'could_not_complete') then
    raise exception 'Bu servis artık aktif geciken iş durumunda değil.';
  end if;

  if p_secretary_id is not null then
    select id, coalesce(nullif(trim(full_name), ''), 'Sekreter')
      into v_secretary_id, v_secretary_name
    from public.profiles
    where id = p_secretary_id
      and company_id = v_company_id
      and role = 'secretary'
      and coalesce(is_active, true) = true;
  end if;

  if v_secretary_id is null and v_created_by is not null then
    select id, coalesce(nullif(trim(full_name), ''), 'Sekreter')
      into v_secretary_id, v_secretary_name
    from public.profiles
    where id = v_created_by
      and company_id = v_company_id
      and role = 'secretary'
      and coalesce(is_active, true) = true;
  end if;

  if v_secretary_id is null then
    select id, coalesce(nullif(trim(full_name), ''), 'Sekreter')
      into v_secretary_id, v_secretary_name
    from public.profiles
    where company_id = v_company_id
      and role = 'secretary'
      and coalesce(is_active, true) = true
    order by full_name nulls last, id
    limit 1;
  end if;

  if v_secretary_id is null then
    raise exception 'Aktif sekreter bulunamadı.';
  end if;

  update public.service_requests
  set status = 'could_not_complete',
      assigned_technician_id = null,
      route_order = null,
      route_plan_date = null,
      rework_requested_at = now(),
      rework_requested_by = v_uid,
      rework_secretary_id = v_secretary_id,
      rework_reason = 'Geciken servis sekretere yeniden planlama için gönderildi.',
      rework_completed_at = null,
      replacement_service_request_id = null,
      completion_note = trim(concat_ws(E'\n', nullif(completion_note, ''),
        '[Sekretere Geri Gönderildi] Geciken servis yeniden planlanacak.')),
      updated_at = now()
  where id = p_service_request_id;

  v_message := coalesce(v_customer_name, 'Müşteri') ||
               ' için geciken servis yeniden planlama amacıyla size gönderildi.';

  insert into public.app_notifications(
    company_id, user_id, title, message, notification_type, route, entity_type, entity_id
  ) values (
    v_company_id, v_secretary_id, 'Geciken servis yeniden planlanacak', v_message,
    'overdue_rework', '/secretary/service-requests', 'service_request', p_service_request_id
  );

  return jsonb_build_object(
    'ok', true,
    'status', 'could_not_complete',
    'secretary_id', v_secretary_id,
    'secretary_name', v_secretary_name
  );
end;
$$;

create or replace function public.recreate_service_from_rework_v1(
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
  v_old public.service_requests%rowtype;
  v_new_id uuid;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select company_id, role::text
    into v_company_id, v_role
  from public.profiles
  where id = v_uid and coalesce(is_active, true) = true;

  if v_company_id is null or v_role <> 'secretary' then
    raise exception 'Bu işlem yalnızca sekreter tarafından yapılabilir.';
  end if;

  select * into v_old
  from public.service_requests
  where id = p_service_request_id
    and company_id = v_company_id
  for update;

  if not found then
    raise exception 'Servis kaydı bulunamadı.';
  end if;

  if v_old.rework_requested_at is null or v_old.rework_completed_at is not null then
    raise exception 'Bu kayıt yeniden servis oluşturma kuyruğunda değil.';
  end if;

  if v_old.rework_secretary_id is distinct from v_uid and v_old.created_by is distinct from v_uid then
    raise exception 'Bu geciken servis size gönderilmemiş.';
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
    route_plan_date
  ) values (
    v_old.company_id,
    v_old.customer_id,
    v_old.service_type,
    trim(concat_ws(E'\n', nullif(v_old.description, ''), '[Yeniden Servis] Geciken kayıttan yeniden oluşturuldu.')),
    v_old.price,
    'pending',
    null,
    null,
    v_uid,
    v_old.planned_product_id,
    v_old.planned_product_name,
    v_old.planned_quantity,
    v_old.planned_unit_price,
    '',
    null,
    null
  )
  returning id into v_new_id;

  update public.service_requests
  set rework_completed_at = now(),
      replacement_service_request_id = v_new_id,
      updated_at = now()
  where id = p_service_request_id;

  return jsonb_build_object('ok', true, 'new_service_request_id', v_new_id, 'status', 'pending');
end;
$$;

grant execute on function public.send_overdue_service_to_secretary_v1(uuid, uuid) to authenticated;
grant execute on function public.recreate_service_from_rework_v1(uuid) to authenticated;

-- Sekreter kendi açtığı servislere ek olarak kendisine yeniden planlama için
-- gönderilen geciken servisleri de görebilsin.
drop policy if exists service_requests_select_company on public.service_requests;
drop policy if exists service_requests_select_company_v2 on public.service_requests;
drop policy if exists service_requests_select_role_scope on public.service_requests;
create policy service_requests_select_role_scope
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
      and (created_by = auth.uid() or rework_secretary_id = auth.uid())
    )
    or (
      (select role::text from public.profiles where id = auth.uid()) = 'technician'
      and assigned_technician_id = auth.uid()
    )
  )
);

notify pgrst, 'reload schema';
