-- ARN ERP - Tekniker “Gidemiyorum” akışı
-- Tekniker “Gidemiyorum” dediğinde iş İptal Edildi bölümüne gider.
-- Sebep/not iptal detayında tutulur ve sekreter/yöneticilere bildirim gider.

alter table public.service_requests
  add column if not exists technician_unavailable_reason text,
  add column if not exists technician_unavailable_note text,
  add column if not exists technician_unavailable_at timestamptz,
  add column if not exists technician_unavailable_by uuid references auth.users(id) on delete set null,
  add column if not exists cancellation_reason text,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references auth.users(id) on delete set null,
  add column if not exists cancelled_by_name text;

create or replace function public.technician_cannot_attend_v1(
  p_service_request_id uuid,
  p_reason text,
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
  v_customer_name text;
  v_technician_name text;
  v_current_technician uuid;
  v_status text;
  v_message text;
  v_count integer := 0;
  r record;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select company_id, role, is_active, coalesce(nullif(trim(full_name), ''), 'Tekniker')
    into v_company_id, v_role, v_is_active, v_technician_name
  from public.profiles
  where id = v_uid;

  if v_role is distinct from 'technician' or coalesce(v_is_active, false) = false then
    raise exception 'Bu işlem yalnızca aktif tekniker tarafından yapılabilir.';
  end if;

  select sr.assigned_technician_id,
         sr.status::text,
         coalesce(nullif(trim(c.full_name), ''), nullif(trim(c.company_name), ''), 'Müşteri')
    into v_current_technician, v_status, v_customer_name
  from public.service_requests sr
  left join public.customers c on c.id = sr.customer_id
  where sr.id = p_service_request_id
    and sr.company_id = v_company_id
  for update of sr;

  if not found then
    raise exception 'Servis kaydı bulunamadı.';
  end if;

  if v_current_technician is distinct from v_uid then
    raise exception 'Bu servis size atanmış değil.';
  end if;

  if v_status not in ('assigned') then
    raise exception 'Yalnızca henüz başlanmamış atanmış servis için Gidemiyorum bildirimi gönderilebilir.';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Sebep seçmelisiniz.';
  end if;

  update public.service_requests
  set status = 'cancelled',
      route_order = null,
      route_plan_date = null,
      technician_unavailable_reason = trim(p_reason),
      technician_unavailable_note = nullif(trim(coalesce(p_note, '')), ''),
      technician_unavailable_at = now(),
      technician_unavailable_by = v_uid,
      cancellation_reason = trim(p_reason) ||
        case when nullif(trim(coalesce(p_note, '')), '') is null
             then '' else ' • ' || trim(p_note) end,
      cancelled_at = now(),
      cancelled_by = v_uid,
      cancelled_by_name = v_technician_name,
      updated_at = now()
  where id = p_service_request_id;

  v_message := coalesce(v_technician_name, 'Tekniker') || ' • ' ||
               coalesce(v_customer_name, 'Müşteri') || ' • ' || trim(p_reason) ||
               case
                 when nullif(trim(coalesce(p_note, '')), '') is null then ''
                 else ' • ' || trim(p_note)
               end;

  for r in
    select id, role
    from public.profiles
    where company_id = v_company_id
      and is_active = true
      and role in ('admin', 'secretary')
  loop
    insert into public.app_notifications(
      company_id,
      user_id,
      title,
      message,
      notification_type,
      route,
      entity_type,
      entity_id
    ) values (
      v_company_id,
      r.id,
      'Tekniker servise gidemiyor',
      v_message,
      'technician_cannot_attend',
      case when r.role = 'secretary' then '/secretary/service-requests' else '/manager/service-requests' end,
      'service_request',
      p_service_request_id
    );
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'status', 'cancelled',
    'notifications_created', v_count
  );
end;
$$;

grant execute on function public.technician_cannot_attend_v1(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
