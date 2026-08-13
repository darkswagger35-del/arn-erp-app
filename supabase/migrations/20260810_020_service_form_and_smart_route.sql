-- ARN ERP - Servis formu tasarımcısı + akıllı rota planı
-- Güvenli/tekrarlanabilir migration.

alter table if exists public.company_app_settings
  add column if not exists service_form_config jsonb not null default '{
    "show_phone": true,
    "show_address": true,
    "show_service_type": true,
    "show_technician": true,
    "show_completed_at": true,
    "show_description": true,
    "show_completion_note": true,
    "show_products": true,
    "show_prices": true,
    "show_customer_signature": true,
    "show_technician_signature": true,
    "show_tds_in": false,
    "show_tds_out": false,
    "show_tank_pressure": false,
    "required_completion_note": false,
    "required_customer_signature": false,
    "section_order": ["customer","service","description","products","total","signatures"],
    "custom_fields": []
  }'::jsonb;

alter table if exists public.service_requests
  add column if not exists route_order integer,
  add column if not exists route_plan_date date;

create index if not exists idx_service_requests_route_plan
  on public.service_requests (assigned_technician_id, route_plan_date, route_order)
  where route_order is not null;

-- Teknikerin günlük iş RPC'si rota sırasını da döndürür.
drop function if exists public.technician_my_jobs_v23();
create function public.technician_my_jobs_v23()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      job order by
        job.route_plan_date nulls last,
        job.route_order nulls last,
        job.planned_date nulls last,
        job.created_at desc
    ),
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
    join public.profiles me
      on me.id = auth.uid()
     and me.role::text = 'technician'
     and coalesce(me.is_active, true) = true
    left join public.customers c on c.id = sr.customer_id
    left join public.profiles creator on creator.id = sr.created_by
    where sr.assigned_technician_id = auth.uid()
      and sr.status::text in ('assigned', 'in_progress', 'could_not_complete')
      and (sr.company_id is null or sr.company_id = me.company_id)
  ) job;
$$;

revoke all on function public.technician_my_jobs_v23() from public, anon;
grant execute on function public.technician_my_jobs_v23() to authenticated;
