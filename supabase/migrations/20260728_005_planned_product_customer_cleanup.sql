-- ARN ERP V8 - planlanan ürün, müşteri kalıcı silme ve servis görünürlüğü
alter table public.service_requests
  add column if not exists planned_product_id uuid references public.products(id) on delete set null,
  add column if not exists planned_product_name text,
  add column if not exists planned_quantity numeric(12,3) not null default 0,
  add column if not exists planned_unit_price numeric(12,2) not null default 0;

create or replace function public.hard_delete_customer(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid := public.current_company_id();
  v_role text;
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role not in ('admin','manager','secretary') then
    raise exception 'Bu işlem için yetkiniz bulunmuyor.';
  end if;

  -- Servisle bağlantılı alt kayıtları önce temizle.
  delete from public.customer_maintenance_records where customer_id = p_customer_id and company_id = v_company_id;
  delete from public.service_items where service_request_id in (
    select id from public.service_requests where customer_id = p_customer_id and company_id = v_company_id
  );
  delete from public.payments where service_request_id in (
    select id from public.service_requests where customer_id = p_customer_id and company_id = v_company_id
  );
  delete from public.service_requests where customer_id = p_customer_id and company_id = v_company_id;
  delete from public.customers where id = p_customer_id and company_id = v_company_id;
end;
$$;

grant execute on function public.hard_delete_customer(uuid) to authenticated;

-- Silinmiş eski müşteri kayıtları telefon benzersizliğini engellemesin.
do $$
declare r record;
begin
  for r in select indexname from pg_indexes where schemaname='public' and tablename='customers' and indexdef ilike '%phone%' and indexdef ilike '%unique%'
  loop
    execute format('drop index if exists public.%I', r.indexname);
  end loop;
end $$;

create unique index if not exists customers_company_phone_active_unique
on public.customers(company_id, regexp_replace(phone, '[^0-9]', '', 'g'))
where deleted_at is null and phone is not null and btrim(phone) <> '';
