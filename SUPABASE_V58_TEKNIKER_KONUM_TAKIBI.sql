-- MOTUS V58 - Tekniker mesai konumu altyapısı
-- Web/PWA'da uygulama açıkken konum güncellenir. Native iOS/Android arka plan
-- takibi daha sonra aynı tablolar/RPC üzerinden çalışacak şekilde tasarlanmıştır.

create table if not exists public.technician_current_locations (
  technician_id uuid primary key references public.profiles(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_m double precision,
  speed_mps double precision,
  heading_deg double precision,
  source text not null default 'web',
  is_sharing boolean not null default true,
  recorded_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.technician_current_locations
  add column if not exists is_sharing boolean not null default true;

create index if not exists technician_current_locations_company_idx
  on public.technician_current_locations(company_id, recorded_at desc);

create table if not exists public.technician_location_history (
  id uuid primary key default gen_random_uuid(),
  technician_id uuid not null references public.profiles(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_m double precision,
  speed_mps double precision,
  heading_deg double precision,
  source text not null default 'web',
  recorded_at timestamptz not null default now()
);

create index if not exists technician_location_history_company_tech_time_idx
  on public.technician_location_history(company_id, technician_id, recorded_at desc);

alter table public.technician_current_locations enable row level security;
alter table public.technician_location_history enable row level security;

grant select on public.technician_current_locations to authenticated;
grant select on public.technician_location_history to authenticated;

-- RLS içinde profiles tablosuna güvenli erişim. SECURITY DEFINER sayesinde
-- profiles üzerindeki başka RLS kurallarıyla recursion oluşmaz.
create or replace function public.technician_location_can_view(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.company_id = p_company_id
      and p.is_active = true
      and p.role in ('admin', 'manager')
  );
$$;

revoke all on function public.technician_location_can_view(uuid) from public;
grant execute on function public.technician_location_can_view(uuid) to authenticated;

-- Tekniker kendi konumunu doğrudan tabloya yazmaz; yalnız bu doğrulamalı RPC'yi çağırır.
create or replace function public.technician_push_location_v1(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision default null,
  p_speed_mps double precision default null,
  p_heading_deg double precision default null,
  p_source text default 'web'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_role text;
  v_active boolean;
  v_now timestamptz := now();
  v_source text := left(coalesce(nullif(trim(p_source), ''), 'web'), 32);
begin
  select p.company_id, p.role, p.is_active
    into v_company_id, v_role, v_active
  from public.profiles p
  where p.id = auth.uid();

  if v_company_id is null or coalesce(v_active, false) = false then
    raise exception 'Aktif kullanıcı profili bulunamadı.' using errcode = 'P0001';
  end if;

  if v_role <> 'technician' then
    raise exception 'Konum yalnız tekniker hesabından gönderilebilir.' using errcode = 'P0001';
  end if;

  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Geçersiz konum.' using errcode = 'P0001';
  end if;

  insert into public.technician_current_locations (
    technician_id, company_id, latitude, longitude, accuracy_m,
    speed_mps, heading_deg, source, is_sharing, recorded_at, updated_at
  ) values (
    auth.uid(), v_company_id, p_latitude, p_longitude, p_accuracy_m,
    p_speed_mps, p_heading_deg, v_source, true, v_now, v_now
  )
  on conflict (technician_id) do update set
    company_id = excluded.company_id,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    accuracy_m = excluded.accuracy_m,
    speed_mps = excluded.speed_mps,
    heading_deg = excluded.heading_deg,
    source = excluded.source,
    is_sharing = true,
    recorded_at = excluded.recorded_at,
    updated_at = excluded.updated_at;

  -- Geçmişi şişirmemek için son kayıttan en az 60 sn geçtiyse yeni nokta ekle.
  if not exists (
    select 1
    from public.technician_location_history h
    where h.technician_id = auth.uid()
      and h.recorded_at > v_now - interval '60 seconds'
  ) then
    insert into public.technician_location_history (
      technician_id, company_id, latitude, longitude, accuracy_m,
      speed_mps, heading_deg, source, recorded_at
    ) values (
      auth.uid(), v_company_id, p_latitude, p_longitude, p_accuracy_m,
      p_speed_mps, p_heading_deg, v_source, v_now
    );
  end if;

  delete from public.technician_location_history
  where technician_id = auth.uid()
    and company_id = v_company_id
    and recorded_at < v_now - interval '30 days';

  return jsonb_build_object(
    'ok', true,
    'recorded_at', v_now,
    'technician_id', auth.uid()
  );
end;
$$;

revoke all on function public.technician_push_location_v1(double precision, double precision, double precision, double precision, double precision, text) from public;
grant execute on function public.technician_push_location_v1(double precision, double precision, double precision, double precision, double precision, text) to authenticated;

create or replace function public.technician_set_location_sharing_v1(p_active boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_role text;
  v_active boolean;
begin
  select p.company_id, p.role, p.is_active
    into v_company_id, v_role, v_active
  from public.profiles p
  where p.id = auth.uid();

  if v_company_id is null or coalesce(v_active, false) = false or v_role <> 'technician' then
    raise exception 'Yetkisiz işlem.' using errcode = 'P0001';
  end if;

  update public.technician_current_locations
  set is_sharing = coalesce(p_active, false),
      updated_at = now()
  where technician_id = auth.uid()
    and company_id = v_company_id;

  return true;
end;
$$;

revoke all on function public.technician_set_location_sharing_v1(boolean) from public;
grant execute on function public.technician_set_location_sharing_v1(boolean) to authenticated;

drop policy if exists technician_current_locations_manager_select on public.technician_current_locations;
create policy technician_current_locations_manager_select
on public.technician_current_locations
for select
to authenticated
using (public.technician_location_can_view(company_id));

drop policy if exists technician_current_locations_own_select on public.technician_current_locations;
create policy technician_current_locations_own_select
on public.technician_current_locations
for select
to authenticated
using (technician_id = auth.uid());

drop policy if exists technician_location_history_manager_select on public.technician_location_history;
create policy technician_location_history_manager_select
on public.technician_location_history
for select
to authenticated
using (public.technician_location_can_view(company_id));

drop policy if exists technician_location_history_own_select on public.technician_location_history;
create policy technician_location_history_own_select
on public.technician_location_history
for select
to authenticated
using (technician_id = auth.uid());

-- Eski konum geçmişi için 30 günlük saklama yardımcı fonksiyonu.
create or replace function public.cleanup_technician_location_history_v1()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_company_id uuid;
begin
  select p.company_id into v_company_id
  from public.profiles p
  where p.id = auth.uid()
    and p.role in ('admin', 'manager')
    and p.is_active = true;

  if v_company_id is null then
    raise exception 'Yetkisiz işlem.' using errcode = 'P0001';
  end if;

  delete from public.technician_location_history
  where company_id = v_company_id
    and recorded_at < now() - interval '30 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.cleanup_technician_location_history_v1() from public;
grant execute on function public.cleanup_technician_location_history_v1() to authenticated;
