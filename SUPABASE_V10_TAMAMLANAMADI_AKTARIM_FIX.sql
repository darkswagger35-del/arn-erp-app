-- ARN ERP V10 - Tamamlanamadı / Sekretere Aktarım ayrımı
-- 24.08.2026
--
-- Yalnızca tekniker gerçekten "Tamamlanamadı" dediğinde could_not_complete kullanılır.
-- Sekretere yeniden planlama için gönderilen kayıtlar deferred/aktarım geçmişidir.
-- Eski yanlış kayıtlar sadece yeniden-planlama izi varsa düzeltilir.

-- ---------------------------------------------------------------------------
-- ESKI YANLIS SINIFLANDIRILMIS KAYITLARI DUZELT
-- ---------------------------------------------------------------------------
update public.service_requests sr
set status = 'deferred',
    updated_at = now()
where sr.status::text = 'could_not_complete'
  and sr.rework_requested_at is not null
  and (
    sr.replacement_service_request_id is not null
    or coalesce(sr.rework_reason, '') ilike '%yeniden plan%'
    or coalesce(sr.completion_note, '') ilike '%[Sekretere Geri Gönderildi]%'
    or coalesce(sr.completion_note, '') ilike '%[Sekretere Gönderildi]%'
    or coalesce(sr.completion_note, '') ilike '%[Tekniker Sekretere Aktardı]%'
  );

-- V8 döneminde ataması temizlenmiş eski aktarım kayıtlarında tekniker
-- snapshot adı tek bir profile eşleşiyorsa geçmiş sahipliğini geri kur.
with unique_matches as (
  select sr.id as service_id, min(p.id::text)::uuid as technician_id
  from public.service_requests sr
  join public.profiles p
    on p.company_id = sr.company_id
   and p.role::text = 'technician'
   and lower(btrim(coalesce(p.full_name, ''))) =
       lower(btrim(coalesce(sr.assigned_technician_name_snapshot, '')))
  where sr.assigned_technician_id is null
    and sr.status::text = 'deferred'
    and sr.rework_requested_at is not null
    and nullif(btrim(coalesce(sr.assigned_technician_name_snapshot, '')), '') is not null
  group by sr.id
  having count(*) = 1
)
update public.service_requests sr
set assigned_technician_id = um.technician_id,
    updated_at = now()
from unique_matches um
where sr.id = um.service_id
  and sr.assigned_technician_id is null;

-- GELECEK YONETICI -> SEKRETER AKISI
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

-- GELECEK TEKNIKER -> SEKRETER AKISI
create or replace function public.technician_send_job_to_secretary_v1(
  p_service_request_id uuid,
  p_note text default ''
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
  v_is_active boolean;
  v_technician_name text;
  v_service public.service_requests%rowtype;
  v_customer_name text;
  v_secretary_id uuid;
  v_secretary_name text;
  v_draft_id uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_reason text;
begin
  if v_uid is null then raise exception 'Oturum bulunamadı.' using errcode='28000'; end if;

  select company_id, role::text, coalesce(is_active, true),
         coalesce(nullif(btrim(full_name), ''), 'Tekniker')
    into v_company_id, v_role, v_is_active, v_technician_name
  from public.profiles where id = v_uid;

  if v_role is distinct from 'technician' or not coalesce(v_is_active, false) then
    raise exception 'Bu işlem yalnızca aktif tekniker tarafından yapılabilir.';
  end if;

  select sr.* into v_service
  from public.service_requests sr
  where sr.id = p_service_request_id and sr.company_id = v_company_id
  for update;

  if not found then raise exception 'Servis kaydı bulunamadı.'; end if;
  if v_service.assigned_technician_id is distinct from v_uid then
    raise exception 'Bu servis size atanmış değil.';
  end if;
  if v_service.status::text <> 'assigned' then
    raise exception 'Yalnızca henüz başlanmamış atanmış iş sekretere aktarılabilir.';
  end if;
  if v_service.replacement_service_request_id is not null then
    raise exception 'Bu servis daha önce yeniden planlama akışına gönderilmiş.';
  end if;

  select coalesce(nullif(btrim(c.full_name), ''), nullif(btrim(c.company_name), ''), 'Müşteri')
    into v_customer_name
  from public.customers c
  where c.id = v_service.customer_id;

  -- Öncelik işi açan aktif sekreterde.
  if v_service.created_by is not null then
    select p.id, coalesce(nullif(btrim(p.full_name), ''), 'Sekreter')
      into v_secretary_id, v_secretary_name
    from public.profiles p
    where p.id = v_service.created_by
      and p.company_id = v_company_id
      and p.role::text = 'secretary'
      and coalesce(p.is_active, true) = true;
  end if;

  -- İşi açan kişi sekreter değilse firmadaki ilk aktif sekreter.
  if v_secretary_id is null then
    select p.id, coalesce(nullif(btrim(p.full_name), ''), 'Sekreter')
      into v_secretary_id, v_secretary_name
    from public.profiles p
    where p.company_id = v_company_id
      and p.role::text = 'secretary'
      and coalesce(p.is_active, true) = true
    order by p.full_name nulls last, p.id
    limit 1;
  end if;

  if v_secretary_id is null then raise exception 'Aktif sekreter bulunamadı.'; end if;

  v_reason := 'Tekniker yeniden planlama için sekretere aktardı.' ||
    case when v_note is null then '' else ' ' || v_note end;

  insert into public.service_requests(
    company_id, customer_id, service_type, description, price, status,
    planned_date, assigned_technician_id, created_by,
    planned_product_id, planned_product_name, planned_quantity, planned_unit_price,
    completion_note, route_order, route_plan_date,
    rework_requested_at, rework_requested_by, rework_secretary_id, rework_reason,
    rework_completed_at, replacement_service_request_id, rework_source_service_request_id
  ) values (
    v_service.company_id,
    v_service.customer_id,
    v_service.service_type,
    btrim(concat_ws(E'\n', nullif(v_service.description, ''),
      '[Teknikerden Geldi] ' || coalesce(v_note, 'Yeniden planlanacak.'))),
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
    v_reason,
    null,
    null,
    v_service.id
  ) returning id into v_draft_id;

  update public.service_requests
  set status = 'deferred',
      -- Eski iş tekniker geçmişidir; sekretere aktarıldı, tamamlanamadı değildir.
      -- Assignee ve snapshot korunur.
      assigned_technician_name_snapshot = coalesce(
        nullif(btrim(assigned_technician_name_snapshot), ''),
        v_technician_name
      ),
      route_order = null,
      route_plan_date = null,
      rework_requested_at = now(),
      rework_requested_by = v_uid,
      rework_secretary_id = v_secretary_id,
      rework_reason = v_reason,
      rework_completed_at = now(),
      replacement_service_request_id = v_draft_id,
      completion_note = btrim(concat_ws(E'\n', nullif(completion_note, ''),
        '[Tekniker Sekretere Aktardı] ' || coalesce(v_note, 'Yeniden planlanacak.'))),
      updated_at = now()
  where id = v_service.id;

  insert into public.app_notifications(
    company_id, user_id, title, message, notification_type, route, entity_type, entity_id
  ) values (
    v_company_id,
    v_secretary_id,
    'Tekniker işi size aktardı',
    coalesce(v_technician_name, 'Tekniker') || ' • ' || coalesce(v_customer_name, 'Müşteri') ||
      case when v_note is null then '' else ' • ' || v_note end,
    'technician_to_secretary',
    '/secretary/service-requests',
    'service_request',
    v_draft_id
  );

  return jsonb_build_object(
    'ok', true,
    'status', 'deferred',
    'source_service_request_id', v_service.id,
    'draft_service_request_id', v_draft_id,
    'secretary_id', v_secretary_id,
    'secretary_name', v_secretary_name
  );
end;
$$;

revoke all on function public.technician_send_job_to_secretary_v1(uuid, text) from public, anon;
grant execute on function public.technician_send_job_to_secretary_v1(uuid, text) to authenticated;

-- TEKNIKER GECMISINDE AKTARILAN ISLERI DE KORU
create or replace function public.technician_job_history_v1(p_day date)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select p.id, p.company_id, coalesce(nullif(btrim(p.full_name), ''), 'Tekniker') as full_name
    from public.profiles p
    where p.id = auth.uid()
      and p.role::text = 'technician'
      and coalesce(p.is_active, true) = true
    limit 1
  )
  select coalesce(
    jsonb_agg(job order by job.planned_date nulls last, job.created_at desc),
    '[]'::jsonb
  )
  from (
    select
      sr.id,
      sr.customer_id,
      sr.created_by,
      sr.service_type::text as service_type,
      coalesce(sr.description, '') as description,
      coalesce(sr.completion_note, '') as completion_note,
      sr.status::text as status,
      coalesce(sr.price, 0) as price,
      sr.planned_date,
      sr.route_order,
      sr.route_plan_date,
      sr.planned_product_id,
      coalesce(sr.planned_product_name, '') as planned_product_name,
      coalesce(sr.planned_quantity, 0) as planned_quantity,
      coalesce(sr.planned_unit_price, 0) as planned_unit_price,
      sr.created_at,
      sr.completed_at,
      sr.cancelled_at,
      coalesce(sr.cancellation_reason, '') as cancellation_reason,
      coalesce(sr.technician_unavailable_reason, '') as technician_unavailable_reason,
      coalesce(sr.technician_unavailable_note, '') as technician_unavailable_note,
      jsonb_build_object(
        'full_name', coalesce(c.full_name, ''),
        'company_name', coalesce(c.company_name, ''),
        'phone', coalesce(c.phone, ''),
        'city', coalesce(c.city, ''),
        'district', coalesce(c.district, ''),
        'neighborhood', coalesce(c.neighborhood, ''),
        'address', coalesce(c.address, ''),
        'latitude', c.latitude,
        'longitude', c.longitude,
        'maps_url', c.maps_url
      ) as customers,
      case when creator.role::text = 'secretary'
        then coalesce(creator.full_name, '') else '' end as secretary_name
    from public.service_requests sr
    join me on me.company_id = sr.company_id
    left join public.customers c on c.id = sr.customer_id
    left join public.profiles creator on creator.id = sr.created_by
    where (
        sr.status::text in ('could_not_complete', 'cancelled')
        or (
          sr.status::text = 'deferred'
          and sr.rework_requested_at is not null
          and sr.replacement_service_request_id is not null
        )
      )
      and (
        sr.assigned_technician_id = me.id
        or (
          sr.assigned_technician_id is null
          and nullif(btrim(coalesce(sr.assigned_technician_name_snapshot, '')), '') is not null
          and lower(btrim(sr.assigned_technician_name_snapshot)) = lower(btrim(me.full_name))
        )
      )
      and sr.planned_date is not null
      and (sr.planned_date at time zone 'Europe/Istanbul')::date = p_day
  ) job;
$$;

revoke all on function public.technician_job_history_v1(date) from public, anon;
grant execute on function public.technician_job_history_v1(date) to authenticated;

-- ---------------------------------------------------------------------------
-- SEKRETER LISTESINDE KAYNAK + TASLAK CIFT GORUNMESIN
-- Kaynak servis geçmişte korunur ama sekreter aktif iş listesinde yalnızca
-- yeniden-planlama taslağını görür. Yönetici ve tekniker geçmişi etkilenmez.
-- ---------------------------------------------------------------------------
drop policy if exists service_requests_select_role_scope_v2 on public.service_requests;
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
            status::text in ('could_not_complete', 'deferred')
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

notify pgrst, 'reload schema';
