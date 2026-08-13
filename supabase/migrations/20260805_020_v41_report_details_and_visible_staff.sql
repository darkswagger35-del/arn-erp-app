begin;

-- Seçilen dönemdeki rakamların hangi kayıtlardan oluştuğunu gösterir.
drop function if exists public.erp_report_details_v41(timestamptz, timestamptz);

create function public.erp_report_details_v41(
  p_start timestamptz,
  p_end timestamptz
)
returns table(
  source_type text,
  record_id uuid,
  transaction_date timestamptz,
  customer_id uuid,
  customer_name text,
  service_type text,
  product_name text,
  quantity numeric,
  amount numeric,
  payment_status text,
  technician_name text,
  secretary_name text,
  description text
)
language sql
stable
security definer
set search_path = public
as $$
  with current_rows as (
    select
      'service'::text source_type,
      s.id record_id,
      s.completed_at transaction_date,
      s.customer_id,
      coalesce(nullif(btrim(c.full_name),''), nullif(btrim(c.company_name),''), 'Müşteri') customer_name,
      sr.service_type::text,
      coalesce(nullif(btrim(si.product_name),''), nullif(btrim(sr.planned_product_name),''), 'Servis') product_name,
      coalesce(si.quantity, sr.planned_quantity, 1)::numeric quantity,
      case
        when si.id is not null then coalesce(si.line_total,0)
        else coalesce(s.total_amount, sr.price,0)
      end::numeric amount,
      case
        when coalesce(s.collected_amount, sr.collected_amount,0) >= coalesce(s.total_amount, sr.price,0)
          then 'Ödendi'
        when coalesce(s.collected_amount, sr.collected_amount,0) > 0 then 'Kısmi Ödeme'
        else coalesce(nullif(sr.payment_status,''),'Ödenmedi')
      end::text payment_status,
      coalesce(nullif(btrim(tp.full_name),''), nullif(btrim(sr.assigned_technician_name_snapshot),''), 'Teknisyen belirtilmedi') technician_name,
      coalesce(nullif(btrim(sp.full_name),''), nullif(btrim(sr.created_by_name_snapshot),''), 'Sekreter belirtilmedi') secretary_name,
      coalesce(nullif(btrim(s.work_description),''), nullif(btrim(sr.completion_note),''), nullif(btrim(sr.description),''), '-') description
    from public.services s
    join public.service_requests sr on sr.id=s.service_request_id
    join public.customers c on c.id=s.customer_id
    left join public.service_items si on si.service_id=s.id
    left join public.profiles tp on tp.id=s.technician_id
    left join public.profiles sp on sp.id=sr.created_by
    where s.company_id=public.current_company_id()
      and s.completed_at>=p_start
      and s.completed_at<p_end
  ),
  historical_rows as (
    select
      'historical'::text source_type,
      h.id record_id,
      h.transaction_date::timestamptz transaction_date,
      h.customer_id,
      coalesce(nullif(btrim(c.full_name),''), nullif(btrim(c.company_name),''), 'Müşteri') customer_name,
      'Geçmiş Satış'::text service_type,
      coalesce(nullif(btrim(h.product_name),''), 'Ürün') product_name,
      coalesce(h.quantity,1)::numeric quantity,
      coalesce(h.amount,0)::numeric amount,
      case lower(coalesce(h.payment_status,''))
        when 'paid' then 'Ödendi'
        when 'partial' then 'Kısmi Ödeme'
        when 'unpaid' then 'Ödenmedi'
        else coalesce(nullif(h.payment_status,''),'Ödendi')
      end::text payment_status,
      coalesce(nullif(btrim(tp.full_name),''), 'Teknisyen belirtilmedi') technician_name,
      coalesce(nullif(btrim(sp.full_name),''), 'Sekreter belirtilmedi') secretary_name,
      coalesce(nullif(btrim(cmr.notes),''), 'Excel / eski işlem kaydı') description
    from public.historical_customer_sales h
    join public.customers c on c.id=h.customer_id
    left join public.customer_maintenance_records cmr
      on cmr.company_id=h.company_id
     and cmr.import_batch_id=h.import_batch_id
     and cmr.import_source_row=h.import_source_row
    left join public.profiles tp on tp.id=cmr.technician_id
    left join public.profiles sp on sp.id=coalesce(cmr.secretary_id,h.created_by)
    where h.company_id=public.current_company_id()
      and h.transaction_date>=p_start::date
      and h.transaction_date<p_end::date
  )
  select * from current_rows
  union all
  select * from historical_rows
  order by transaction_date desc, customer_name, product_name;
$$;

revoke all on function public.erp_report_details_v41(timestamptz,timestamptz) from public, anon;
grant execute on function public.erp_report_details_v41(timestamptz,timestamptz) to authenticated;

notify pgrst, 'reload schema';

commit;
