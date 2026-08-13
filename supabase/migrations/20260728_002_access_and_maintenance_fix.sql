-- ARN ERP V4: sekreter müşteri erişimi ve bakım atamalarını düzeltir.

-- Müşteriler: aynı firmadaki yönetici ve sekreter tüm müşteri kartlarını görür.
drop policy if exists customers_select_own on public.customers;
create policy customers_select_own
on public.customers
for select to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin', 'manager', 'secretary')
);

drop policy if exists customers_select_own_technician on public.customers;
create policy customers_select_own_technician
on public.customers
for select to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role() = 'technician'
  and is_active = true
);

drop policy if exists customers_insert_own on public.customers;
create policy customers_insert_own
on public.customers
for insert to authenticated
with check (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin', 'manager', 'secretary')
);

drop policy if exists customers_update_own on public.customers;
create policy customers_update_own
on public.customers
for update to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin', 'manager', 'secretary')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin', 'manager', 'secretary')
);

-- Bakım kayıtları: yönetici/sekreter firma kayıtlarını, teknisyen ise kendine atanmış kayıtları görür.
drop policy if exists customer_maintenance_company_access on public.customer_maintenance_records;
drop policy if exists customer_maintenance_select on public.customer_maintenance_records;
drop policy if exists customer_maintenance_insert on public.customer_maintenance_records;
drop policy if exists customer_maintenance_update on public.customer_maintenance_records;
drop policy if exists customer_maintenance_delete on public.customer_maintenance_records;

create policy customer_maintenance_select
on public.customer_maintenance_records
for select to authenticated
using (
  company_id = public.current_company_id()
  and (
    public.current_user_role() in ('admin', 'manager', 'secretary')
    or (public.current_user_role() = 'technician' and assigned_user_id = auth.uid())
  )
);

create policy customer_maintenance_insert
on public.customer_maintenance_records
for insert to authenticated
with check (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin', 'manager', 'secretary', 'technician')
);

create policy customer_maintenance_update
on public.customer_maintenance_records
for update to authenticated
using (
  company_id = public.current_company_id()
  and (
    public.current_user_role() in ('admin', 'manager', 'secretary')
    or assigned_user_id = auth.uid()
  )
)
with check (company_id = public.current_company_id());

create policy customer_maintenance_delete
on public.customer_maintenance_records
for delete to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin', 'manager')
);

grant select, insert, update, delete on public.customer_maintenance_records to authenticated;
