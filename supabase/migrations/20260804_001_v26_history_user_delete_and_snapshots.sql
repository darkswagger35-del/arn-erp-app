-- ARN ERP V26: kullanıcı silinse bile geçmiş isimleri koru.
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists deleted_at timestamptz;
alter table public.service_requests add column if not exists assigned_technician_name_snapshot text;
alter table public.service_requests add column if not exists created_by_name_snapshot text;

create or replace function public.snapshot_service_request_staff_v26()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.assigned_technician_id is not null then
    select p.full_name into new.assigned_technician_name_snapshot
    from public.profiles p where p.id = new.assigned_technician_id;
  end if;
  if new.created_by is not null then
    select p.full_name into new.created_by_name_snapshot
    from public.profiles p where p.id = new.created_by;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_snapshot_service_request_staff_v26 on public.service_requests;
create trigger trg_snapshot_service_request_staff_v26
before insert or update of assigned_technician_id, created_by
on public.service_requests
for each row execute function public.snapshot_service_request_staff_v26();

update public.service_requests sr
set assigned_technician_name_snapshot = coalesce(
      sr.assigned_technician_name_snapshot,
      (select p.full_name from public.profiles p where p.id = sr.assigned_technician_id)
    ),
    created_by_name_snapshot = coalesce(
      sr.created_by_name_snapshot,
      (select p.full_name from public.profiles p where p.id = sr.created_by)
    );

create or replace function public.delete_company_user_v26(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_company_id uuid;
  v_name text;
  v_current_role text;
begin
  select company_id, role::text into v_company_id, v_current_role
  from public.profiles where id = auth.uid();
  if v_current_role not in ('admin','manager') then
    raise exception 'Bu işlem için yetkiniz bulunmuyor.';
  end if;

  select full_name into v_name
  from public.profiles
  where id = p_user_id and company_id = v_company_id;
  if v_name is null then
    raise exception 'Kullanıcı bulunamadı.';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Kendi hesabınızı silemezsiniz.';
  end if;

  update public.service_requests
  set assigned_technician_name_snapshot = coalesce(assigned_technician_name_snapshot, v_name)
  where assigned_technician_id = p_user_id;
  update public.service_requests
  set created_by_name_snapshot = coalesce(created_by_name_snapshot, v_name)
  where created_by = p_user_id;

  -- Hesabı listeden kaldır; geçmiş ilişkiler ve profil adı korunur.
  update public.profiles
  set is_active = false,
      deleted_at = now(),
      email = null,
      phone = null,
      username = null,
      updated_at = now()
  where id = p_user_id and company_id = v_company_id;

  -- Giriş yapamasın. Auth kaydı silinemezse profil pasif kalır.
  begin
    delete from auth.users where id = p_user_id;
  exception when others then
    null;
  end;
end;
$$;

grant execute on function public.delete_company_user_v26(uuid) to authenticated;
notify pgrst, 'reload schema';


-- Teknisyen, kendi firmasında müşterinin eksik iletişim/adres bilgisini düzeltebilir.
drop policy if exists customers_update_staff_v26 on public.customers;
create policy customers_update_staff_v26
on public.customers
for update
to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin','manager','secretary','technician')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin','manager','secretary','technician')
);
