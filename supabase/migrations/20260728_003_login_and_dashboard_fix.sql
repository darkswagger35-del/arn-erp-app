-- V6: Sekreter/teknisyen girişinde şirket bilgisinin RLS nedeniyle görünmemesi
-- ve ana panel servis sayacının eski durum değerlerini kaçırması düzeltmesi.

create or replace function public.erp_current_auth_context()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_company public.companies%rowtype;
begin
  select * into v_profile
  from public.profiles
  where id = auth.uid()
  limit 1;

  if v_profile.id is null then
    return jsonb_build_object('profile', null, 'company', null);
  end if;

  select * into v_company
  from public.companies
  where id = v_profile.company_id
  limit 1;

  return jsonb_build_object(
    'profile', to_jsonb(v_profile),
    'company', case when v_company.id is null then null else to_jsonb(v_company) end
  );
end;
$$;

revoke all on function public.erp_current_auth_context() from public, anon;
grant execute on function public.erp_current_auth_context() to authenticated;

create or replace function public.erp_dashboard_summary(
  p_start timestamptz,
  p_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  select company_id into v_company_id
  from public.profiles
  where id = auth.uid() and is_active = true
  limit 1;

  if v_company_id is null then
    raise exception 'Firma bilgisi bulunamadı';
  end if;

  return jsonb_build_object(
    'pending', (select count(*) from public.service_requests
      where company_id = v_company_id
        and status in ('pending', 'awaiting_approval')),
    'assigned', (select count(*) from public.service_requests
      where company_id = v_company_id and status = 'assigned'),
    'active', (select count(*) from public.service_requests
      where company_id = v_company_id and status in ('assigned','in_progress')),
    'completed_period', (select count(*) from public.service_requests
      where company_id = v_company_id and status = 'completed'
        and coalesce(completed_at, updated_at, created_at) >= p_start
        and coalesce(completed_at, updated_at, created_at) < p_end),
    'low_stock', (select count(*) from public.warehouse_stocks ws
      join public.products p on p.id = ws.product_id
      where ws.company_id = v_company_id
        and ws.quantity <= coalesce(p.critical_stock, 0)),
    'collection_period', coalesce((select sum(amount) from public.payments
      where company_id = v_company_id and payment_date >= p_start and payment_date < p_end),0),
    'revenue_period', coalesce((select sum(total_amount) from public.services
      where company_id = v_company_id and completed_at >= p_start and completed_at < p_end),0),
    'open_balance', coalesce((select sum(total_amount - collected_amount) from public.services
      where company_id = v_company_id),0),
    'active_customers', (select count(*) from public.customers
      where company_id = v_company_id and coalesce(is_active,true) = true)
  );
end;
$$;

grant execute on function public.erp_dashboard_summary(timestamptz,timestamptz) to authenticated;
