-- ARN ERP V13 - Tekniker müşteri kartı + güvenli adres/iletişim düzeltme
-- Amaç:
-- 1) Tekniker yalnız kendisine atanmış müşterinin kartını görebilsin.
-- 2) RLS / maybeSingle kaynaklı "Cannot coerce the result to a single JSON object" hatası olmasın.
-- 3) Tekniker yanlış adresi düzelttiğinde eski koordinatlar temizlensin; rota yeni adresi yeniden çözsün.

create or replace function public.technician_customer_card_v1(p_customer_id uuid)
returns jsonb
language plpgsql
stable
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

  if not exists (
    select 1
    from public.service_requests sr
    where sr.company_id = v_company_id
      and sr.customer_id = p_customer_id
      and sr.assigned_technician_id = auth.uid()
  ) then
    raise exception 'Bu müşteri kartına erişim yetkiniz yok.' using errcode = 'P0001';
  end if;

  select to_jsonb(c)
    into v_result
  from public.customers c
  where c.id = p_customer_id
    and c.company_id = v_company_id
    and c.deleted_at is null
  limit 1;

  return v_result;
end;
$$;

revoke all on function public.technician_customer_card_v1(uuid) from public;
grant execute on function public.technician_customer_card_v1(uuid) to authenticated;

create or replace function public.technician_update_customer_v1(
  p_customer_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_role text;
  v_allowed boolean := true;
  v_old public.customers%rowtype;
  v_new public.customers%rowtype;
  v_location_changed boolean := false;
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

  select coalesce((s.permissions ->> 'technician_edit_customers')::boolean, true)
    into v_allowed
  from public.company_app_settings s
  where s.company_id = v_company_id
  limit 1;
  v_allowed := coalesce(v_allowed, true);

  if not v_allowed then
    raise exception 'Müşteri düzenleme yetkiniz kapalı.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.service_requests sr
    where sr.company_id = v_company_id
      and sr.customer_id = p_customer_id
      and sr.assigned_technician_id = auth.uid()
  ) then
    raise exception 'Bu müşteriyi düzenleme yetkiniz yok.' using errcode = 'P0001';
  end if;

  select * into v_old
  from public.customers c
  where c.id = p_customer_id
    and c.company_id = v_company_id
    and c.deleted_at is null
  limit 1;

  if v_old.id is null then
    raise exception 'Müşteri bulunamadı.' using errcode = 'P0001';
  end if;

  v_location_changed :=
       coalesce(trim(p_patch ->> 'address'), '') <> coalesce(trim(v_old.address), '')
    or coalesce(trim(p_patch ->> 'city'), '') <> coalesce(trim(v_old.city), '')
    or coalesce(trim(p_patch ->> 'district'), '') <> coalesce(trim(v_old.district), '')
    or coalesce(trim(p_patch ->> 'neighborhood'), '') <> coalesce(trim(v_old.neighborhood), '');

  update public.customers c
  set
    full_name = coalesce(nullif(trim(p_patch ->> 'full_name'), ''), c.full_name),
    phone = coalesce(nullif(trim(p_patch ->> 'phone'), ''), c.phone),
    city = case when p_patch ? 'city' then nullif(trim(p_patch ->> 'city'), '') else c.city end,
    district = case when p_patch ? 'district' then nullif(trim(p_patch ->> 'district'), '') else c.district end,
    neighborhood = case when p_patch ? 'neighborhood' then nullif(trim(p_patch ->> 'neighborhood'), '') else c.neighborhood end,
    address = coalesce(nullif(trim(p_patch ->> 'address'), ''), c.address),
    notes = case when p_patch ? 'notes' then nullif(trim(p_patch ->> 'notes'), '') else c.notes end,
    latitude = case when v_location_changed then null else c.latitude end,
    longitude = case when v_location_changed then null else c.longitude end,
    maps_url = case when v_location_changed then null else c.maps_url end,
    updated_by = auth.uid(),
    updated_at = now()
  where c.id = p_customer_id
    and c.company_id = v_company_id
    and c.deleted_at is null
  returning c.* into v_new;

  return to_jsonb(v_new);
end;
$$;

revoke all on function public.technician_update_customer_v1(uuid, jsonb) from public;
grant execute on function public.technician_update_customer_v1(uuid, jsonb) to authenticated;

notify pgrst, 'reload schema';
