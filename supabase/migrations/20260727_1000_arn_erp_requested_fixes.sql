-- ARN ERP - requested fixes. Safe to run repeatedly.

alter table public.customers
  add column if not exists registration_date timestamptz;

update public.customers
set registration_date = created_at
where registration_date is null;

alter table public.customers
  alter column registration_date set default now();

create index if not exists idx_customers_company_registration_date
  on public.customers(company_id, registration_date desc);

-- Assignment cancellation leaves the service request waiting for assignment again.
create or replace function public.unassign_service_request(p_service_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  select company_id into v_company_id from public.profiles where id = auth.uid();
  update public.service_requests
  set assigned_technician_id = null,
      planned_date = null,
      status = 'pending',
      updated_at = now()
  where id = p_service_request_id and company_id = v_company_id;
end;
$$;
grant execute on function public.unassign_service_request(uuid) to authenticated;

-- Dashboard keys expected by the Flutter panel.
create or replace function public.erp_dashboard_summary(p_start timestamptz, p_end timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  select company_id into v_company_id from public.profiles where id = auth.uid();
  if v_company_id is null then raise exception 'Firma bilgisi bulunamadı'; end if;
  return jsonb_build_object(
    'pending', (select count(*) from public.service_requests where company_id=v_company_id and status='pending'),
    'assigned', (select count(*) from public.service_requests where company_id=v_company_id and status='assigned'),
    'active', (select count(*) from public.service_requests where company_id=v_company_id and status in ('assigned','in_progress')),
    'completed_today', (select count(*) from public.service_requests where company_id=v_company_id and status='completed' and coalesce(completed_at,updated_at,created_at)>=p_start and coalesce(completed_at,updated_at,created_at)<p_end),
    'completed_period', (select count(*) from public.service_requests where company_id=v_company_id and status='completed' and coalesce(completed_at,updated_at,created_at)>=p_start and coalesce(completed_at,updated_at,created_at)<p_end),
    'low_stock', (select count(*) from public.warehouse_stocks ws join public.products p on p.id=ws.product_id where ws.company_id=v_company_id and ws.quantity<=coalesce(p.critical_stock,0)),
    'daily_collection', coalesce((select sum(amount) from public.payments where company_id=v_company_id and payment_date>=p_start and payment_date<p_end),0),
    'collection_period', coalesce((select sum(amount) from public.payments where company_id=v_company_id and payment_date>=p_start and payment_date<p_end),0),
    'daily_revenue', coalesce((select sum(total_amount) from public.services where company_id=v_company_id and completed_at>=p_start and completed_at<p_end),0),
    'revenue_period', coalesce((select sum(total_amount) from public.services where company_id=v_company_id and completed_at>=p_start and completed_at<p_end),0),
    'open_balance', coalesce((select sum(total_amount-collected_amount) from public.services where company_id=v_company_id),0),
    'active_customers', (select count(*) from public.customers where company_id=v_company_id and coalesce(is_active,true)=true and deleted_at is null)
  );
end;
$$;
grant execute on function public.erp_dashboard_summary(timestamptz,timestamptz) to authenticated;
