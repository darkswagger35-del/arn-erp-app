-- ARN ERP V18
-- Sekreter müşteri / servis / bakım ekranlarında oluşan RLS sonsuz döngüsünü giderir.
-- SELECT politikaları güvenli, SECURITY DEFINER yardımcı fonksiyonlar üzerinden kurulur.

-- Kullanıcı rolünü ve şirketini RLS politikalarından bağımsız okur.
create or replace function public.erp_auth_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.company_id
  from public.profiles p
  where p.id = auth.uid()
  limit 1
$$;

create or replace function public.erp_auth_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
  limit 1
$$;

-- Teknisyenin müşteriye atanmış açık/geçmiş bir servis kaydı var mı?
-- SECURITY DEFINER olduğu için customers <-> service_requests politika döngüsü oluşmaz.
create or replace function public.erp_technician_can_view_customer(p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.service_requests sr
    where sr.customer_id = p_customer_id
      and sr.company_id = public.erp_auth_company_id()
      and sr.assigned_technician_id = auth.uid()
  )
$$;

revoke all on function public.erp_auth_company_id() from public;
revoke all on function public.erp_auth_role() from public;
revoke all on function public.erp_technician_can_view_customer(uuid) from public;
grant execute on function public.erp_auth_company_id() to authenticated;
grant execute on function public.erp_auth_role() to authenticated;
grant execute on function public.erp_technician_can_view_customer(uuid) to authenticated;

-- Önce yalnızca SELECT politikalarını temizle. Insert/update/delete politikaları korunur.
do $$
declare r record;
begin
  for r in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'customers'
      and cmd = 'SELECT'
  loop
    execute format('drop policy if exists %I on public.customers', r.policyname);
  end loop;

  for r in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'service_requests'
      and cmd = 'SELECT'
  loop
    execute format('drop policy if exists %I on public.service_requests', r.policyname);
  end loop;

  for r in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'customer_maintenance_records'
      and cmd = 'SELECT'
  loop
    execute format('drop policy if exists %I on public.customer_maintenance_records', r.policyname);
  end loop;
end $$;

-- Müşteriler:
-- yönetici tüm şirketi, sekreter yalnız kendi oluşturduğunu,
-- teknisyen yalnız kendisine atanmış servis müşterisini görür.
create policy customers_select_v18
on public.customers
for select
to authenticated
using (
  company_id = public.erp_auth_company_id()
  and deleted_at is null
  and (
    public.erp_auth_role() in ('admin', 'manager')
    or (public.erp_auth_role() = 'secretary' and created_by = auth.uid())
    or (
      public.erp_auth_role() = 'technician'
      and public.erp_technician_can_view_customer(id)
    )
  )
);

-- Servis talepleri:
-- yönetici tümünü, sekreter kendi açtığını, teknisyen kendisine atanmış olanı görür.
create policy service_requests_select_v18
on public.service_requests
for select
to authenticated
using (
  company_id = public.erp_auth_company_id()
  and (
    public.erp_auth_role() in ('admin', 'manager')
    or (public.erp_auth_role() = 'secretary' and created_by = auth.uid())
    or (public.erp_auth_role() = 'technician' and assigned_technician_id = auth.uid())
  )
);

-- Bakım kayıtları:
-- yönetici tümünü, sekreter kendi müşterilerine ait olanı,
-- teknisyen kendisine atanmış olanı görür.
create policy customer_maintenance_select_v18
on public.customer_maintenance_records
for select
to authenticated
using (
  company_id = public.erp_auth_company_id()
  and (
    public.erp_auth_role() in ('admin', 'manager')
    or (public.erp_auth_role() = 'secretary' and secretary_id = auth.uid())
    or (public.erp_auth_role() = 'technician' and technician_id = auth.uid())
  )
);

-- Eski verilerde sekreter alanı boşsa, müşteri kaydını açan sekreterden tamamla.
update public.customer_maintenance_records cmr
set secretary_id = c.created_by
from public.customers c
join public.profiles p on p.id = c.created_by
where cmr.customer_id = c.id
  and cmr.secretary_id is null
  and p.role = 'secretary';

notify pgrst, 'reload schema';
