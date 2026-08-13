-- ARN ERP V22 - Teknisyene atanan işlerin güvenli ve kesin listelenmesi
-- Supabase SQL Editor'da bir kez çalıştırılmalıdır.

create or replace function public.technician_jobs_v22()
returns setof jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'id', sr.id,
    'customer_id', sr.customer_id,
    'created_by', sr.created_by,
    'service_type', sr.service_type,
    'description', sr.description,
    'status', sr.status,
    'price', coalesce(sr.price, 0),
    'planned_date', sr.planned_date,
    'planned_product_id', sr.planned_product_id,
    'planned_product_name', coalesce(sr.planned_product_name, ''),
    'planned_quantity', coalesce(sr.planned_quantity, 0),
    'planned_unit_price', coalesce(sr.planned_unit_price, 0),
    'secretary_name', case when creator.role = 'secretary'
      then coalesce(creator.full_name, '') else '' end,
    'customers', jsonb_build_object(
      'full_name', coalesce(c.full_name, ''),
      'company_name', coalesce(c.company_name, ''),
      'phone', coalesce(c.phone, ''),
      'address', coalesce(c.address, '')
    )
  )
  from public.service_requests sr
  join public.profiles me
    on me.id = auth.uid()
   and me.is_active = true
   and me.role = 'technician'
   and me.company_id = sr.company_id
  left join public.customers c on c.id = sr.customer_id
  left join public.profiles creator on creator.id = sr.created_by
  where sr.assigned_technician_id = auth.uid()
    and sr.status in ('assigned', 'in_progress', 'could_not_complete')
  order by sr.planned_date asc nulls last, sr.created_at desc;
$$;

revoke all on function public.technician_jobs_v22() from public;
grant execute on function public.technician_jobs_v22() to authenticated;

notify pgrst, 'reload schema';
