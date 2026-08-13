begin;

create or replace function public.erp_staff_performance_v36(
  p_start timestamptz,
  p_end timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_company uuid := public.current_company_id();
  v_result jsonb;
begin
  if v_company is null then
    raise exception 'Firma bilgisi bulunamadı.';
  end if;

  with technician_base as (
    select
      p.id,
      p.full_name,
      coalesce(p.is_active, false) as is_active,
      count(sr.id) filter (
        where sr.status::text = 'completed'
          and sr.updated_at >= p_start
          and sr.updated_at < p_end
      )::int as completed_services,
      count(sr.id) filter (
        where sr.status::text in ('could_not_complete', 'cancelled')
          and sr.updated_at >= p_start
          and sr.updated_at < p_end
      )::int as unsuccessful_services,
      coalesce(sum(sr.price) filter (
        where sr.status::text = 'completed'
          and sr.updated_at >= p_start
          and sr.updated_at < p_end
      ), 0)::numeric as turnover
    from public.profiles p
    left join public.service_requests sr
      on sr.company_id = v_company
     and sr.assigned_technician_id = p.id
    where p.company_id = v_company
      and p.role::text = 'technician'
    group by p.id, p.full_name, p.is_active
  ),
  technician_products as (
    select
      cmr.technician_id as user_id,
      count(*)::int as product_count,
      mode() within group (
        order by coalesce(nullif(btrim(cmr.product_name), ''), pr.name, 'Ürün')
      ) as top_product
    from public.customer_maintenance_records cmr
    left join public.products pr on pr.id = cmr.product_id
    where cmr.company_id = v_company
      and cmr.technician_id is not null
      and cmr.performed_at >= p_start::date
      and cmr.performed_at < p_end::date
    group by cmr.technician_id
  ),
  technician_rows as (
    select
      b.id,
      b.full_name,
      b.is_active,
      b.completed_services,
      b.unsuccessful_services,
      b.turnover,
      coalesce(tp.product_count, 0) as product_count,
      coalesce(tp.top_product, '-') as top_product,
      case when b.completed_services > 0
        then round(b.turnover / b.completed_services, 2)
        else 0 end as average_service_amount,
      dense_rank() over (
        order by b.turnover desc, b.completed_services desc, b.full_name
      )::int as ranking
    from technician_base b
    left join technician_products tp on tp.user_id = b.id
  ),
  secretary_base as (
    select
      p.id,
      p.full_name,
      coalesce(p.is_active, false) as is_active,
      count(sr.id) filter (
        where sr.created_at >= p_start
          and sr.created_at < p_end
      )::int as opened_services,
      count(sr.id) filter (
        where sr.status::text = 'completed'
          and sr.updated_at >= p_start
          and sr.updated_at < p_end
      )::int as completed_services,
      count(sr.id) filter (
        where sr.status::text = 'cancelled'
          and sr.updated_at >= p_start
          and sr.updated_at < p_end
      )::int as cancelled_services,
      coalesce(sum(sr.price) filter (
        where sr.status::text = 'completed'
          and sr.updated_at >= p_start
          and sr.updated_at < p_end
      ), 0)::numeric as turnover
    from public.profiles p
    left join public.service_requests sr
      on sr.company_id = v_company
     and sr.created_by = p.id
    where p.company_id = v_company
      and p.role::text = 'secretary'
    group by p.id, p.full_name, p.is_active
  ),
  secretary_products as (
    select
      cmr.secretary_id as user_id,
      count(*)::int as product_count,
      mode() within group (
        order by coalesce(nullif(btrim(cmr.product_name), ''), pr.name, 'Ürün')
      ) as top_product
    from public.customer_maintenance_records cmr
    left join public.products pr on pr.id = cmr.product_id
    where cmr.company_id = v_company
      and cmr.secretary_id is not null
      and cmr.performed_at >= p_start::date
      and cmr.performed_at < p_end::date
    group by cmr.secretary_id
  ),
  secretary_service_types as (
    select created_by as user_id, service_type::text as service_type, count(*) as total,
      row_number() over (partition by created_by order by count(*) desc, service_type::text) as rn
    from public.service_requests
    where company_id = v_company
      and created_by is not null
      and created_at >= p_start
      and created_at < p_end
    group by created_by, service_type::text
  ),
  secretary_rows as (
    select
      b.id,
      b.full_name,
      b.is_active,
      b.opened_services,
      b.completed_services,
      b.cancelled_services,
      b.turnover,
      coalesce(sp.product_count, 0) as product_count,
      coalesce(sp.top_product, '-') as top_product,
      coalesce(st.service_type, '-') as top_service_type,
      case when b.completed_services > 0
        then round(b.turnover / b.completed_services, 2)
        else 0 end as average_completed_amount,
      dense_rank() over (
        order by b.turnover desc, b.opened_services desc, b.full_name
      )::int as ranking
    from secretary_base b
    left join secretary_products sp on sp.user_id = b.id
    left join secretary_service_types st on st.user_id = b.id and st.rn = 1
  )
  select jsonb_build_object(
    'technicians', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.ranking, t.full_name)
      from technician_rows t
    ), '[]'::jsonb),
    'secretaries', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.ranking, s.full_name)
      from secretary_rows s
    ), '[]'::jsonb),
    'leaders', jsonb_build_object(
      'technician', coalesce((
        select to_jsonb(t) from technician_rows t
        order by t.ranking, t.full_name limit 1
      ), '{}'::jsonb),
      'secretary', coalesce((
        select to_jsonb(s) from secretary_rows s
        order by s.ranking, s.full_name limit 1
      ), '{}'::jsonb),
      'product_user', coalesce((
        select jsonb_build_object(
          'full_name', x.full_name,
          'role', x.role,
          'product_count', x.product_count
        )
        from (
          select full_name, 'Teknisyen'::text role, product_count from technician_rows
          union all
          select full_name, 'Sekreter'::text role, product_count from secretary_rows
        ) x
        order by x.product_count desc, x.full_name
        limit 1
      ), '{}'::jsonb)
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.erp_staff_performance_v36(timestamptz, timestamptz)
from public, anon;
grant execute on function public.erp_staff_performance_v36(timestamptz, timestamptz)
to authenticated;

notify pgrst, 'reload schema';
commit;
