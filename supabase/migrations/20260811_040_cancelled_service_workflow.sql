-- ARN ERP - İptal edilen servislerin Bekleyen Atamalar'a düşmesini engeller.
-- İptal nedeni / kişi / zaman bilgisini saklar ve yalnız bilinçli "Yeniden Aç" ile pending'e döndürür.

alter table public.service_requests
  add column if not exists cancellation_reason text,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references auth.users(id) on delete set null,
  add column if not exists cancelled_by_name text;

create or replace function public.cancel_service_request_v2(
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
  v_name text;
  v_current_company uuid;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select company_id, role, coalesce(nullif(trim(full_name), ''), 'Kullanıcı')
    into v_company_id, v_role, v_name
  from public.profiles
  where id = v_uid and coalesce(is_active, true) = true;

  if v_company_id is null or v_role not in ('admin', 'manager', 'secretary') then
    raise exception 'Bu işlem için yetkiniz yok.';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'İptal nedeni zorunludur.';
  end if;

  select company_id into v_current_company
  from public.service_requests
  where id = p_service_request_id
  for update;

  if not found or v_current_company is distinct from v_company_id then
    raise exception 'Servis kaydı bulunamadı.';
  end if;

  update public.service_requests
  set status = 'cancelled',
      cancellation_reason = trim(p_reason),
      cancelled_at = now(),
      cancelled_by = v_uid,
      cancelled_by_name = v_name,
      route_order = null,
      route_plan_date = null,
      updated_at = now()
  where id = p_service_request_id;

  return jsonb_build_object('ok', true, 'status', 'cancelled');
end;
$$;

create or replace function public.reopen_cancelled_service_v2(
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
  v_current_company uuid;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select company_id, role into v_company_id, v_role
  from public.profiles
  where id = v_uid and coalesce(is_active, true) = true;

  if v_company_id is null or v_role not in ('admin', 'manager', 'secretary') then
    raise exception 'Bu işlem için yetkiniz yok.';
  end if;

  select company_id, status::text into v_current_company, v_status
  from public.service_requests
  where id = p_service_request_id
  for update;

  if not found or v_current_company is distinct from v_company_id then
    raise exception 'Servis kaydı bulunamadı.';
  end if;
  if v_status <> 'cancelled' then
    raise exception 'Yalnızca iptal edilmiş servis yeniden açılabilir.';
  end if;

  update public.service_requests
  set status = 'pending',
      assigned_technician_id = null,
      planned_date = null,
      route_order = null,
      route_plan_date = null,
      updated_at = now()
  where id = p_service_request_id;

  return jsonb_build_object('ok', true, 'status', 'pending');
end;
$$;

grant execute on function public.cancel_service_request_v2(uuid, text) to authenticated;
grant execute on function public.reopen_cancelled_service_v2(uuid) to authenticated;

notify pgrst, 'reload schema';
