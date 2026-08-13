begin;

-- MOTUS V40: Raporlar artık hem yeni servis kayıtlarını hem de Excel/geçmiş satışları kullanır.
create or replace function public.erp_dashboard_summary(
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
begin
  if v_company is null then
    raise exception 'Firma bilgisi bulunamadı.';
  end if;

  return jsonb_build_object(
    'pending', (
      select count(*) from public.service_requests
      where company_id=v_company and status::text in ('pending','awaiting_approval')
    ),
    'assigned', (
      select count(*) from public.service_requests
      where company_id=v_company and status::text='assigned'
    ),
    'active', (
      select count(*) from public.service_requests
      where company_id=v_company and status::text in ('assigned','in_progress')
    ),
    'completed_period',
      coalesce((
        select count(*) from public.services s
        where s.company_id=v_company
          and s.completed_at>=p_start and s.completed_at<p_end
      ),0)
      + coalesce((
        select count(distinct (h.customer_id, h.transaction_date))
        from public.historical_customer_sales h
        where h.company_id=v_company
          and h.transaction_date>=p_start::date
          and h.transaction_date<p_end::date
      ),0),
    'revenue_period',
      coalesce((
        select sum(s.total_amount) from public.services s
        where s.company_id=v_company
          and s.completed_at>=p_start and s.completed_at<p_end
      ),0)
      + coalesce((
        select sum(h.amount) from public.historical_customer_sales h
        where h.company_id=v_company
          and h.transaction_date>=p_start::date
          and h.transaction_date<p_end::date
      ),0),
    'collection_period',
      coalesce((
        select sum(p.amount) from public.payments p
        where p.company_id=v_company
          and p.payment_date>=p_start and p.payment_date<p_end
      ),0)
      + coalesce((
        select sum(h.amount) from public.historical_customer_sales h
        where h.company_id=v_company
          and h.transaction_date>=p_start::date
          and h.transaction_date<p_end::date
          and lower(coalesce(h.payment_status,'')) in ('paid','ödendi','odendi')
      ),0),
    'open_balance',
      coalesce((
        select sum(greatest(s.total_amount-s.collected_amount,0))
        from public.services s where s.company_id=v_company
      ),0)
      + coalesce((
        select sum(h.amount) from public.historical_customer_sales h
        where h.company_id=v_company
          and lower(coalesce(h.payment_status,'')) not in ('paid','ödendi','odendi')
      ),0),
    'active_customers', (
      select count(*) from public.customers c
      where c.company_id=v_company and coalesce(c.is_active,true)=true
    ),
    'low_stock', (
      select count(*) from public.warehouse_stocks ws
      join public.products pr on pr.id=ws.product_id
      where ws.company_id=v_company
        and ws.quantity<=coalesce(pr.critical_stock,0)
    )
  );
end;
$$;

revoke all on function public.erp_dashboard_summary(timestamptz,timestamptz) from public, anon;
grant execute on function public.erp_dashboard_summary(timestamptz,timestamptz) to authenticated;

create or replace function public.erp_top_products(
  p_start timestamptz,
  p_end timestamptz,
  p_limit integer default 10
)
returns table(product_name text, quantity numeric, revenue numeric)
language sql
stable
security definer
set search_path = public
as $$
  with all_products as (
    select
      coalesce(nullif(btrim(si.product_name),''),'Ürün') product_name,
      coalesce(si.quantity,0)::numeric quantity,
      coalesce(si.line_total,0)::numeric revenue
    from public.service_items si
    join public.services s on s.id=si.service_id
    where si.company_id=public.current_company_id()
      and s.completed_at>=p_start and s.completed_at<p_end

    union all

    select
      coalesce(nullif(btrim(h.product_name),''),'Ürün'),
      coalesce(h.quantity,0)::numeric,
      coalesce(h.amount,0)::numeric
    from public.historical_customer_sales h
    where h.company_id=public.current_company_id()
      and h.transaction_date>=p_start::date
      and h.transaction_date<p_end::date
  )
  select a.product_name,
         sum(a.quantity)::numeric(14,2),
         sum(a.revenue)::numeric(14,2)
  from all_products a
  group by a.product_name
  order by sum(a.quantity) desc, sum(a.revenue) desc
  limit greatest(1,least(coalesce(p_limit,10),50));
$$;

revoke all on function public.erp_top_products(timestamptz,timestamptz,integer) from public, anon;
grant execute on function public.erp_top_products(timestamptz,timestamptz,integer) to authenticated;

create or replace function public.erp_staff_performance_v40(
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

  with current_tech as (
    select
      s.technician_id user_id,
      count(*)::int completed_services,
      coalesce(sum(s.total_amount),0)::numeric turnover
    from public.services s
    where s.company_id=v_company
      and s.completed_at>=p_start and s.completed_at<p_end
    group by s.technician_id
  ),
  historical_tech as (
    select
      cmr.technician_id user_id,
      count(distinct (h.customer_id,h.transaction_date))::int completed_services,
      coalesce(sum(h.amount),0)::numeric turnover
    from public.historical_customer_sales h
    join public.customer_maintenance_records cmr
      on cmr.company_id=h.company_id
     and cmr.import_batch_id=h.import_batch_id
     and cmr.import_source_row=h.import_source_row
    where h.company_id=v_company
      and h.transaction_date>=p_start::date
      and h.transaction_date<p_end::date
      and cmr.technician_id is not null
    group by cmr.technician_id
  ),
  technician_products as (
    select user_id, sum(product_count)::int product_count,
           mode() within group(order by product_name) top_product
    from (
      select s.technician_id user_id, count(*)::int product_count,
             coalesce(nullif(btrim(si.product_name),''),'Ürün') product_name
      from public.service_items si
      join public.services s on s.id=si.service_id
      where si.company_id=v_company
        and s.completed_at>=p_start and s.completed_at<p_end
      group by s.technician_id, coalesce(nullif(btrim(si.product_name),''),'Ürün')
      union all
      select cmr.technician_id, count(*)::int,
             coalesce(nullif(btrim(cmr.product_name),''),'Ürün')
      from public.customer_maintenance_records cmr
      where cmr.company_id=v_company
        and cmr.technician_id is not null
        and cmr.performed_at>=p_start::date and cmr.performed_at<p_end::date
      group by cmr.technician_id, coalesce(nullif(btrim(cmr.product_name),''),'Ürün')
    ) x
    group by user_id
  ),
  failed_tech as (
    select assigned_technician_id user_id, count(*)::int unsuccessful_services
    from public.service_requests
    where company_id=v_company
      and status::text in ('could_not_complete','cancelled')
      and coalesce(completed_at,updated_at)>=p_start
      and coalesce(completed_at,updated_at)<p_end
    group by assigned_technician_id
  ),
  technician_rows as (
    select p.id,p.full_name,coalesce(p.is_active,false) is_active,
      coalesce(ct.completed_services,0)+coalesce(ht.completed_services,0) completed_services,
      coalesce(ft.unsuccessful_services,0) unsuccessful_services,
      coalesce(ct.turnover,0)+coalesce(ht.turnover,0) turnover,
      coalesce(tp.product_count,0) product_count,
      coalesce(tp.top_product,'-') top_product,
      case when coalesce(ct.completed_services,0)+coalesce(ht.completed_services,0)>0
        then round((coalesce(ct.turnover,0)+coalesce(ht.turnover,0)) /
          (coalesce(ct.completed_services,0)+coalesce(ht.completed_services,0)),2)
        else 0 end average_service_amount,
      dense_rank() over(order by coalesce(ct.turnover,0)+coalesce(ht.turnover,0) desc,
        coalesce(ct.completed_services,0)+coalesce(ht.completed_services,0) desc,p.full_name)::int ranking
    from public.profiles p
    left join current_tech ct on ct.user_id=p.id
    left join historical_tech ht on ht.user_id=p.id
    left join technician_products tp on tp.user_id=p.id
    left join failed_tech ft on ft.user_id=p.id
    where p.company_id=v_company and p.role::text='technician'
  ),
  current_secretary as (
    select sr.created_by user_id,
      count(*)::int opened_services,
      count(*) filter(where sr.status::text='completed')::int completed_services,
      count(*) filter(where sr.status::text='cancelled')::int cancelled_services,
      coalesce(sum(s.total_amount) filter(where sr.status::text='completed'),0)::numeric turnover
    from public.service_requests sr
    left join public.services s on s.service_request_id=sr.id
    where sr.company_id=v_company
      and sr.created_at>=p_start and sr.created_at<p_end
    group by sr.created_by
  ),
  historical_secretary as (
    select h.created_by user_id,
      count(distinct (h.customer_id,h.transaction_date))::int opened_services,
      count(distinct (h.customer_id,h.transaction_date))::int completed_services,
      0::int cancelled_services,
      coalesce(sum(h.amount),0)::numeric turnover
    from public.historical_customer_sales h
    where h.company_id=v_company
      and h.transaction_date>=p_start::date and h.transaction_date<p_end::date
    group by h.created_by
  ),
  secretary_products as (
    select h.created_by user_id,count(*)::int product_count,
      mode() within group(order by coalesce(nullif(btrim(h.product_name),''),'Ürün')) top_product
    from public.historical_customer_sales h
    where h.company_id=v_company
      and h.transaction_date>=p_start::date and h.transaction_date<p_end::date
    group by h.created_by
  ),
  secretary_types as (
    select created_by user_id,service_type::text service_type,count(*) total,
      row_number() over(partition by created_by order by count(*) desc,service_type::text) rn
    from public.service_requests
    where company_id=v_company and created_by is not null
      and created_at>=p_start and created_at<p_end
    group by created_by,service_type::text
  ),
  secretary_rows as (
    select p.id,p.full_name,coalesce(p.is_active,false) is_active,
      coalesce(cs.opened_services,0)+coalesce(hs.opened_services,0) opened_services,
      coalesce(cs.completed_services,0)+coalesce(hs.completed_services,0) completed_services,
      coalesce(cs.cancelled_services,0)+coalesce(hs.cancelled_services,0) cancelled_services,
      coalesce(cs.turnover,0)+coalesce(hs.turnover,0) turnover,
      coalesce(sp.product_count,0) product_count,
      coalesce(sp.top_product,'-') top_product,
      coalesce(st.service_type,'-') top_service_type,
      case when coalesce(cs.completed_services,0)+coalesce(hs.completed_services,0)>0
        then round((coalesce(cs.turnover,0)+coalesce(hs.turnover,0)) /
          (coalesce(cs.completed_services,0)+coalesce(hs.completed_services,0)),2)
        else 0 end average_completed_amount,
      dense_rank() over(order by coalesce(cs.turnover,0)+coalesce(hs.turnover,0) desc,
        coalesce(cs.opened_services,0)+coalesce(hs.opened_services,0) desc,p.full_name)::int ranking
    from public.profiles p
    left join current_secretary cs on cs.user_id=p.id
    left join historical_secretary hs on hs.user_id=p.id
    left join secretary_products sp on sp.user_id=p.id
    left join secretary_types st on st.user_id=p.id and st.rn=1
    where p.company_id=v_company and p.role::text='secretary'
  )
  select jsonb_build_object(
    'technicians',coalesce((select jsonb_agg(to_jsonb(t) order by t.ranking,t.full_name) from technician_rows t),'[]'::jsonb),
    'secretaries',coalesce((select jsonb_agg(to_jsonb(s) order by s.ranking,s.full_name) from secretary_rows s),'[]'::jsonb),
    'leaders',jsonb_build_object(
      'technician',coalesce((select to_jsonb(t) from technician_rows t order by t.ranking,t.full_name limit 1),'{}'::jsonb),
      'secretary',coalesce((select to_jsonb(s) from secretary_rows s order by s.ranking,s.full_name limit 1),'{}'::jsonb),
      'product_user',coalesce((
        select jsonb_build_object('full_name',x.full_name,'role',x.role,'product_count',x.product_count)
        from (
          select full_name,'Teknisyen'::text role,product_count from technician_rows
          union all
          select full_name,'Sekreter'::text role,product_count from secretary_rows
        ) x order by x.product_count desc,x.full_name limit 1
      ),'{}'::jsonb)
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.erp_staff_performance_v40(timestamptz,timestamptz) from public, anon;
grant execute on function public.erp_staff_performance_v40(timestamptz,timestamptz) to authenticated;

notify pgrst,'reload schema';
commit;
