-- ARN ERP V9 - Servis takip + tekniker geçmişi
-- 24.08.2026
--
-- Bu dosya bir kez Supabase SQL Editor'da çalıştırılabilir.
-- Amaç:
-- 1) Tamamlanamadı/iptal edilen işlerde tekniker kimliğini ve isim geçmişini korumak.
-- 2) Teknikerin seçili gün için yapılamayan/iptal işleri geçmişte görebilmesi.
-- 3) Teknikerin kendi aktif işini ileri tarih/saate erteleyebilmesi.
-- 4) Teknikerin işi sekretere yeniden planlama için aktarabilmesi (eski kayıt silinmez).
-- 5) Sekreterin tamamlanamayan/iptal servisi Takip Listesi'ne alabilmesi.

-- ---------------------------------------------------------------------------
-- Şema uyumluluğu
-- ---------------------------------------------------------------------------
alter table public.secretary_leads
  add column if not exists service_request_id uuid,
  add column if not exists interest_type text,
  add column if not exists quoted_price numeric,
  add column if not exists reference_name text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'secretary_leads_service_request_id_fkey'
      and conrelid = 'public.secretary_leads'::regclass
  ) then
    alter table public.secretary_leads
      add constraint secretary_leads_service_request_id_fkey
      foreign key (service_request_id)
      references public.service_requests(id)
      on delete set null;
  end if;
end $$;

create index if not exists secretary_leads_service_request_idx
  on public.secretary_leads(secretary_id, service_request_id)
  where service_request_id is not null;

-- Rework alanları eski kurulumlarda eksikse V9 fonksiyonlarının çalışması için tamamla.
alter table public.service_requests
  add column if not exists rework_requested_at timestamptz,
  add column if not exists rework_requested_by uuid references auth.users(id) on delete set null,
  add column if not exists rework_secretary_id uuid references auth.users(id) on delete set null,
  add column if not exists rework_reason text,
  add column if not exists rework_completed_at timestamptz,
  add column if not exists replacement_service_request_id uuid references public.service_requests(id) on delete set null,
  add column if not exists rework_source_service_request_id uuid references public.service_requests(id) on delete set null;

-- V8 çalışmış ve atamayı null yapmış eski kapalı servislerde tekniker snapshot'ı
-- benzersiz şekilde bir aktif/pasif tekniker profiline eşleşiyorsa geçmiş atamasını geri kur.
-- Status kapalı olduğu için bu kayıt tekrar aktif işe dönüşmez; sadece geçmiş sahipliği düzelir.
with unique_matches as (
  select sr.id as service_id, min(p.id::text)::uuid as technician_id
  from public.service_requests sr
  join public.profiles p
    on p.company_id = sr.company_id
   and p.role::text = 'technician'
   and lower(btrim(coalesce(p.full_name, ''))) =
       lower(btrim(coalesce(sr.assigned_technician_name_snapshot, '')))
  where sr.assigned_technician_id is null
    and sr.status::text in ('could_not_complete', 'cancelled')
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

-- ---------------------------------------------------------------------------
-- Tamamlanamadı: tekniker atamasını KORU.
-- Aktif günlük listeden status nedeniyle çıkar; seçili gün geçmişinde görünür.
-- ---------------------------------------------------------------------------
create or replace function public.technician_mark_could_not_complete_v1(
  p_service_request_id uuid,
  p_reason text
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
  v_service public.service_requests%rowtype;
  v_technician_name text;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select p.company_id, p.role::text, coalesce(p.is_active, true),
         coalesce(nullif(btrim(p.full_name), ''), 'Tekniker')
    into v_company_id, v_role, v_is_active, v_technician_name
  from public.profiles p
  where p.id = v_uid;

  if v_company_id is null or v_role is distinct from 'technician' or not coalesce(v_is_active, false) then
    raise exception 'Bu işlem yalnızca aktif tekniker tarafından yapılabilir.';
  end if;

  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'Tamamlanamama sebebi boş olamaz.';
  end if;

  select sr.* into v_service
  from public.service_requests sr
  where sr.id = p_service_request_id
    and sr.company_id = v_company_id
  for update;

  if not found then raise exception 'Servis kaydı bulunamadı.'; end if;
  if v_service.assigned_technician_id is distinct from v_uid then
    raise exception 'Bu servis size atanmış değil.';
  end if;
  if v_service.status::text not in ('assigned', 'in_progress') then
    raise exception 'Yalnızca aktif servis tamamlanamadı olarak işaretlenebilir.';
  end if;

  update public.service_requests
  set status = 'could_not_complete',
      completion_note = btrim(p_reason),
      assigned_technician_name_snapshot = coalesce(
        nullif(btrim(assigned_technician_name_snapshot), ''),
        v_technician_name
      ),
      -- assigned_technician_id özellikle korunuyor.
      route_order = null,
      route_plan_date = null,
      updated_at = now()
  where id = p_service_request_id;

  return jsonb_build_object(
    'ok', true,
    'status', 'could_not_complete',
    'service_request_id', p_service_request_id,
    'technician_id', v_uid,
    'technician_name', v_technician_name
  );
end;
$$;

revoke all on function public.technician_mark_could_not_complete_v1(uuid, text) from public, anon;
grant execute on function public.technician_mark_could_not_complete_v1(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Tekniker kapalı iş geçmişi (seçili gün)
-- ---------------------------------------------------------------------------
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
    where sr.status::text in ('could_not_complete', 'cancelled')
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
-- Tekniker kendi aktif işini ileri tarih/saate erteleyebilir.
-- İş tekniker üzerinde kalır, geçmiş silinmez.
-- ---------------------------------------------------------------------------
create or replace function public.technician_reschedule_own_job_v1(
  p_service_request_id uuid,
  p_planned_at timestamptz,
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
  v_service public.service_requests%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if v_uid is null then raise exception 'Oturum bulunamadı.' using errcode='28000'; end if;

  select company_id, role::text, coalesce(is_active, true)
    into v_company_id, v_role, v_is_active
  from public.profiles where id = v_uid;

  if v_role is distinct from 'technician' or not coalesce(v_is_active, false) then
    raise exception 'Bu işlem yalnızca aktif tekniker tarafından yapılabilir.';
  end if;
  if p_planned_at is null or p_planned_at <= now() then
    raise exception 'Yeni tarih/saat ileri bir zaman olmalıdır.';
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
    raise exception 'Yalnızca henüz başlanmamış atanmış iş ertelenebilir.';
  end if;

  update public.service_requests
  set planned_date = p_planned_at,
      status = 'assigned',
      route_order = null,
      route_plan_date = null,
      description = btrim(concat_ws(E'\n', nullif(description, ''),
        '[Tekniker Erteledi] ' || to_char(p_planned_at at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI') ||
        case when v_note is null then '' else ' • ' || v_note end)),
      updated_at = now()
  where id = p_service_request_id;

  return jsonb_build_object(
    'ok', true,
    'service_request_id', p_service_request_id,
    'planned_at', p_planned_at,
    'status', 'assigned'
  );
end;
$$;

revoke all on function public.technician_reschedule_own_job_v1(uuid, timestamptz, text) from public, anon;
grant execute on function public.technician_reschedule_own_job_v1(uuid, timestamptz, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Tekniker aktif işi sekretere aktarır.
-- Eski kayıt tekniker geçmişinde could_not_complete olarak KALIR.
-- Sekreter için yeni deferred taslak oluşturulur.
-- ---------------------------------------------------------------------------
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
  set status = 'could_not_complete',
      -- Eski iş tekniker geçmişidir; assignee ve snapshot korunur.
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

-- ---------------------------------------------------------------------------
-- Sekreter: iptal/tamamlanamadı servisini kendi Takip Listesi'ne alır.
-- Aynı servis ikinci kez Takibe Al denirse yeni duplicate üretmek yerine günceller.
-- ---------------------------------------------------------------------------
create or replace function public.secretary_track_service_v1(
  p_service_request_id uuid,
  p_follow_up_at timestamptz,
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
  v_service public.service_requests%rowtype;
  v_customer_name text;
  v_phone text;
  v_lead_id uuid;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if v_uid is null then raise exception 'Oturum bulunamadı.' using errcode='28000'; end if;

  select company_id, role::text, coalesce(is_active, true)
    into v_company_id, v_role, v_is_active
  from public.profiles where id = v_uid;

  if v_role is distinct from 'secretary' or not coalesce(v_is_active, false) then
    raise exception 'Bu işlem yalnızca aktif sekreter tarafından yapılabilir.';
  end if;

  select sr.* into v_service
  from public.service_requests sr
  where sr.id = p_service_request_id and sr.company_id = v_company_id;

  if not found then raise exception 'Servis kaydı bulunamadı.'; end if;
  if v_service.status::text not in ('could_not_complete', 'cancelled') then
    raise exception 'Yalnızca tamamlanamayan veya iptal edilen servis takibe alınabilir.';
  end if;
  if v_service.created_by is distinct from v_uid
     and v_service.rework_secretary_id is distinct from v_uid then
    raise exception 'Bu servis sizin sekreter kapsamınızda değil.';
  end if;

  select
    coalesce(nullif(btrim(c.full_name), ''), nullif(btrim(c.company_name), ''), 'Müşteri'),
    coalesce(c.phone, '')
    into v_customer_name, v_phone
  from public.customers c
  where c.id = v_service.customer_id;

  if nullif(btrim(coalesce(v_phone, '')), '') is null then
    v_phone := '-';
  end if;

  select sl.id into v_lead_id
  from public.secretary_leads sl
  where sl.secretary_id = v_uid
    and sl.service_request_id = p_service_request_id
  order by sl.updated_at desc
  limit 1;

  if v_lead_id is null then
    insert into public.secretary_leads(
      company_id, secretary_id, customer_id, service_request_id,
      full_name, phone, source, status, outcome_code, note, follow_up_at,
      interest_type, quoted_price
    ) values (
      v_company_id, v_uid, v_service.customer_id, p_service_request_id,
      coalesce(v_customer_name, 'Müşteri'), v_phone, 'Servis Takibi', 'tracking',
      'service_follow_up', v_note, p_follow_up_at,
      v_service.service_type::text, v_service.price
    ) returning id into v_lead_id;
  else
    update public.secretary_leads
    set customer_id = v_service.customer_id,
        full_name = coalesce(v_customer_name, full_name),
        phone = v_phone,
        source = 'Servis Takibi',
        status = 'tracking',
        outcome_code = 'service_follow_up',
        note = coalesce(v_note, note),
        follow_up_at = p_follow_up_at,
        closed_at = null,
        converted_at = null,
        interest_type = v_service.service_type::text,
        quoted_price = v_service.price,
        updated_at = now()
    where id = v_lead_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'lead_id', v_lead_id,
    'service_request_id', p_service_request_id,
    'status', 'tracking'
  );
end;
$$;

revoke all on function public.secretary_track_service_v1(uuid, timestamptz, text) from public, anon;
grant execute on function public.secretary_track_service_v1(uuid, timestamptz, text) to authenticated;

notify pgrst, 'reload schema';
