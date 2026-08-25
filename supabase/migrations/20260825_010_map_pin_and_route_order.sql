-- ARN ERP V14 - Tekniker harita pini + kalıcı rota sırası
-- 1) Tekniker yalnız kendisine atanmış müşterinin kesin harita pinini kaydedebilir.
-- 2) Rota sırası auth.uid() teknikerine ait günlük aktif işlere güvenli biçimde yazılır.

create or replace function public.technician_set_customer_map_point_v1(
  p_customer_id uuid,
  p_latitude double precision,
  p_longitude double precision
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_role text;
  v_result jsonb;
begin
  select p.company_id, p.role::text
    into v_company_id, v_role
  from public.profiles p
  where p.id = auth.uid()
    and coalesce(p.is_active, false) = true
  limit 1;

  if v_company_id is null or v_role <> 'technician' then
    raise exception 'Tekniker oturumu doğrulanamadı.' using errcode = 'P0001';
  end if;

  if p_latitude < 35 or p_latitude > 43 or p_longitude < 25 or p_longitude > 45 then
    raise exception 'Seçilen konum Türkiye sınırları dışında.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.service_requests sr
    where sr.company_id = v_company_id
      and sr.customer_id = p_customer_id
      and sr.assigned_technician_id = auth.uid()
  ) then
    raise exception 'Bu müşterinin konumunu düzenleme yetkiniz yok.' using errcode = 'P0001';
  end if;

  update public.customers c
  set latitude = p_latitude,
      longitude = p_longitude,
      maps_url = 'motus-pin:' || p_latitude::text || ',' || p_longitude::text,
      updated_by = auth.uid(),
      updated_at = now()
  where c.id = p_customer_id
    and c.company_id = v_company_id
    and c.deleted_at is null
  returning to_jsonb(c) into v_result;

  if v_result is null then
    raise exception 'Müşteri bulunamadı.' using errcode = 'P0001';
  end if;

  return v_result;
end;
$$;

revoke all on function public.technician_set_customer_map_point_v1(uuid, double precision, double precision) from public;
grant execute on function public.technician_set_customer_map_point_v1(uuid, double precision, double precision) to authenticated;

drop function if exists public.technician_save_route_order_v1(uuid[]);
drop function if exists public.technician_save_route_order_v1(text[]);
drop function if exists public.technician_save_route_order_v1(jsonb);

create function public.technician_save_route_order_v1(
  p_service_request_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_role text;
  v_day date;
begin
  select p.company_id, p.role::text
    into v_company_id, v_role
  from public.profiles p
  where p.id = auth.uid()
    and coalesce(p.is_active, false) = true
  limit 1;

  if v_company_id is null or v_role <> 'technician' then
    raise exception 'Tekniker oturumu doğrulanamadı.' using errcode = 'P0001';
  end if;

  if coalesce(array_length(p_service_request_ids, 1), 0) = 0 then
    return;
  end if;

  select (sr.planned_date at time zone 'Europe/Istanbul')::date
    into v_day
  from public.service_requests sr
  where sr.id = p_service_request_ids[1]
    and sr.company_id = v_company_id
    and sr.assigned_technician_id = auth.uid()
  limit 1;

  if v_day is null then
    raise exception 'Rota günü bulunamadı.' using errcode = 'P0001';
  end if;

  update public.service_requests sr
  set route_order = null,
      route_plan_date = null,
      updated_at = now()
  where sr.company_id = v_company_id
    and sr.assigned_technician_id = auth.uid()
    and sr.status in ('assigned', 'in_progress')
    and (sr.planned_date at time zone 'Europe/Istanbul')::date = v_day;

  update public.service_requests sr
  set route_order = x.ord::integer,
      route_plan_date = v_day,
      updated_at = now()
  from unnest(p_service_request_ids) with ordinality as x(id, ord)
  where sr.id = x.id
    and sr.company_id = v_company_id
    and sr.assigned_technician_id = auth.uid()
    and sr.status in ('assigned', 'in_progress')
    and (sr.planned_date at time zone 'Europe/Istanbul')::date = v_day;
end;
$$;

revoke all on function public.technician_save_route_order_v1(uuid[]) from public;
grant execute on function public.technician_save_route_order_v1(uuid[]) to authenticated;

notify pgrst, 'reload schema';
