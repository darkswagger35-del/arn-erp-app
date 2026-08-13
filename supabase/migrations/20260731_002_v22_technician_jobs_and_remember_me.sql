-- V22: Teknisyenin kendisine atanmış aktif işleri güvenli biçimde getirmesi.
-- Profil güncellemez; mevcut profil güvenlik trigger'larını tetiklemez.

create or replace function public.technician_my_jobs_v22()
returns table (
  id uuid,
  customer_id uuid,
  created_by uuid,
  service_type text,
  description text,
  status text,
  price numeric,
  planned_date timestamptz,
  planned_product_id uuid,
  planned_product_name text,
  planned_quantity numeric,
  planned_unit_price numeric,
  created_at timestamptz,
  customer_full_name text,
  customer_company_name text,
  customer_phone text,
  customer_address text,
  secretary_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Oturum açmanız gerekiyor.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'technician'
      and p.is_active = true
  ) then
    raise exception 'Aktif teknisyen profili bulunamadı.';
  end if;

  return query
  select
    sr.id,
    sr.customer_id,
    sr.created_by,
    sr.service_type,
    sr.description,
    sr.status,
    sr.price,
    sr.planned_date,
    sr.planned_product_id,
    sr.planned_product_name,
    sr.planned_quantity,
    sr.planned_unit_price,
    sr.created_at,
    c.full_name,
    c.company_name,
    c.phone,
    c.address,
    case when creator.role = 'secretary' then creator.full_name else '' end
  from public.service_requests sr
  left join public.customers c on c.id = sr.customer_id
  left join public.profiles creator on creator.id = sr.created_by
  where sr.assigned_technician_id = auth.uid()
    and sr.status in ('assigned', 'in_progress', 'could_not_complete')
  order by sr.planned_date asc nulls last, sr.created_at desc;
end;
$$;

revoke all on function public.technician_my_jobs_v22() from public, anon;
grant execute on function public.technician_my_jobs_v22() to authenticated;
