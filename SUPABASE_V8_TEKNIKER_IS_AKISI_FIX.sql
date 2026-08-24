-- ARN ERP V8 - Tekniker iş akışı düzeltmesi
-- Amaç:
-- 1) "Tamamlanamadı" işlemini RLS'den bağımsız ve güvenli bir RPC ile kaydetmek.
-- 2) Tamamlanamayan işi tekniker atamasından ve günlük rota listesinden çıkarmak.
-- 3) Teknikerin günlük iş RPC'sinde yalnız aktif durumları döndürmek.
-- Güvenli/tekrarlanabilir olarak bir kez çalıştırılabilir.

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
begin
  if v_uid is null then
    raise exception 'Oturum bulunamadı.' using errcode = '28000';
  end if;

  select p.company_id, p.role::text, coalesce(p.is_active, true)
    into v_company_id, v_role, v_is_active
  from public.profiles p
  where p.id = v_uid;

  if v_company_id is null or v_role is distinct from 'technician' or not coalesce(v_is_active, false) then
    raise exception 'Bu işlem yalnızca aktif tekniker tarafından yapılabilir.';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Tamamlanamama sebebi boş olamaz.';
  end if;

  select sr.*
    into v_service
  from public.service_requests sr
  where sr.id = p_service_request_id
    and sr.company_id = v_company_id
  for update;

  if not found then
    raise exception 'Servis kaydı bulunamadı.';
  end if;

  if v_service.assigned_technician_id is distinct from v_uid then
    raise exception 'Bu servis size atanmış değil.';
  end if;

  if v_service.status::text not in ('assigned', 'in_progress') then
    raise exception 'Yalnızca aktif servis tamamlanamadı olarak işaretlenebilir.';
  end if;

  update public.service_requests
  set status = 'could_not_complete',
      completion_note = trim(p_reason),
      assigned_technician_id = null,
      route_order = null,
      route_plan_date = null,
      updated_at = now()
  where id = p_service_request_id;

  return jsonb_build_object(
    'ok', true,
    'status', 'could_not_complete',
    'service_request_id', p_service_request_id
  );
end;
$$;

revoke all on function public.technician_mark_could_not_complete_v1(uuid, text) from public, anon;
grant execute on function public.technician_mark_could_not_complete_v1(uuid, text) to authenticated;

-- Günlük işler RPC'si geçmiş/kapalı "could_not_complete" kayıtlarını hiç döndürmesin.
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
      and sr.status::text in ('assigned', 'in_progress')
      and (sr.company_id is null or sr.company_id = me.company_id)
  ) job;
$$;

revoke all on function public.technician_my_jobs_v23() from public, anon;
grant execute on function public.technician_my_jobs_v23() to authenticated;

notify pgrst, 'reload schema';
