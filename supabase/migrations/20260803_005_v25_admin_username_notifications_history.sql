-- ARN ERP V25 - admin/manager, username, notifications and history safety
create extension if not exists pgcrypto;

alter table public.profiles add column if not exists username text;
with candidates as (
  select id, company_id,
    coalesce(nullif(lower(regexp_replace(split_part(coalesce(email, id::text), '@', 1), '[^a-zA-Z0-9._-]+', '', 'g')), ''), 'user') as base,
    row_number() over (
      partition by company_id, coalesce(nullif(lower(regexp_replace(split_part(coalesce(email, id::text), '@', 1), '[^a-zA-Z0-9._-]+', '', 'g')), ''), 'user')
      order by created_at nulls last, id
    ) as rn
  from public.profiles
  where username is null or btrim(username) = ''
)
update public.profiles p
set username = c.base || case when c.rn = 1 then '' else '-' || c.rn::text end
from candidates c where c.id = p.id;

create unique index if not exists profiles_company_username_unique
  on public.profiles(company_id, lower(username))
  where username is not null and btrim(username) <> '' and full_name <> 'Silinmiş Kullanıcı';

create or replace function public.erp_login_email_for_username(p_username text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select email from public.profiles
  where lower(username) = lower(btrim(p_username)) and is_active = true
  limit 1;
$$;
grant execute on function public.erp_login_email_for_username(text) to anon, authenticated;

-- Firma başına yalnızca bir aktif admin ve bir aktif yönetici.
create unique index if not exists profiles_one_active_admin_per_company
  on public.profiles(company_id) where role = 'admin' and is_active = true;
create unique index if not exists profiles_one_active_manager_per_company
  on public.profiles(company_id) where role = 'manager' and is_active = true;

-- Geçmiş kayıtlarda isimleri kullanıcı silinse bile koru.
alter table public.service_requests
  add column if not exists assigned_technician_name_snapshot text,
  add column if not exists created_by_name_snapshot text;

update public.service_requests sr
set assigned_technician_name_snapshot = p.full_name
from public.profiles p
where p.id = sr.assigned_technician_id
  and coalesce(sr.assigned_technician_name_snapshot, '') = '';

update public.service_requests sr
set created_by_name_snapshot = p.full_name
from public.profiles p
where p.id = sr.created_by
  and coalesce(sr.created_by_name_snapshot, '') = '';

create or replace function public.capture_service_staff_names_v25()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.assigned_technician_id is not null then
    select full_name into new.assigned_technician_name_snapshot
    from public.profiles where id = new.assigned_technician_id;
  end if;
  if new.created_by is not null and coalesce(new.created_by_name_snapshot,'') = '' then
    select full_name into new.created_by_name_snapshot
    from public.profiles where id = new.created_by;
  end if;
  return new;
end; $$;

drop trigger if exists trg_capture_service_staff_names_v25 on public.service_requests;
create trigger trg_capture_service_staff_names_v25
before insert or update of assigned_technician_id, created_by on public.service_requests
for each row execute function public.capture_service_staff_names_v25();

-- Bildirim altyapısı.
create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  message text not null default '',
  notification_type text not null default 'info',
  route text,
  entity_type text,
  entity_id uuid,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.app_notifications enable row level security;
drop policy if exists app_notifications_select_own on public.app_notifications;
create policy app_notifications_select_own on public.app_notifications for select to authenticated using(user_id=auth.uid());
drop policy if exists app_notifications_update_own on public.app_notifications;
create policy app_notifications_update_own on public.app_notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
grant select, update on public.app_notifications to authenticated;

create or replace function public.notify_service_assignment_v25()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_customer text; v_company uuid;
begin
  if new.assigned_technician_id is not null and old.assigned_technician_id is distinct from new.assigned_technician_id then
    select coalesce(nullif(full_name,''), nullif(company_name,''), 'Müşteri'), company_id
      into v_customer, v_company from public.customers where id=new.customer_id;
    insert into public.app_notifications(company_id,user_id,title,message,notification_type,route,entity_type,entity_id)
    values(coalesce(new.company_id,v_company),new.assigned_technician_id,'Yeni servis atandı',
      coalesce(v_customer,'Müşteri') || case when new.planned_date is null then '' else ' • '||to_char(new.planned_date at time zone 'Europe/Istanbul','DD.MM.YYYY HH24:MI') end,
      'service_assignment','/technician/jobs/'||new.id::text,'service_request',new.id);
  end if;
  return new;
end; $$;
drop trigger if exists trg_notify_service_assignment_v25 on public.service_requests;
create trigger trg_notify_service_assignment_v25 after update of assigned_technician_id on public.service_requests
for each row execute function public.notify_service_assignment_v25();

-- Ürün stok miktarı girilmişse ana depoda da görünmesini sağla.
create or replace function public.sync_product_to_main_warehouse_v25()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_wh uuid;
begin
  select id into v_wh from public.warehouses
  where company_id=new.company_id and type='main' and is_active=true order by created_at limit 1;
  if v_wh is null then
    insert into public.warehouses(company_id,name,type,is_active) values(new.company_id,'Ana Depo','main',true) returning id into v_wh;
  end if;
  insert into public.warehouse_stocks(company_id,warehouse_id,product_id,quantity,updated_at)
  values(new.company_id,v_wh,new.id,greatest(coalesce(new.stock_quantity,0),0),now())
  on conflict(warehouse_id,product_id) do update
    set quantity=greatest(coalesce(excluded.quantity,0),0), updated_at=now();
  return new;
end; $$;
drop trigger if exists trg_sync_product_to_main_warehouse_v25 on public.products;
create trigger trg_sync_product_to_main_warehouse_v25
after insert or update of stock_quantity on public.products
for each row execute function public.sync_product_to_main_warehouse_v25();

-- Mevcut ürünleri ana depoya eşitle.
insert into public.warehouse_stocks(company_id, warehouse_id, product_id, quantity, updated_at)
select p.company_id, w.id, p.id, greatest(coalesce(p.stock_quantity,0),0), now()
from public.products p
join lateral (
  select id from public.warehouses
  where company_id=p.company_id and type='main' and is_active=true
  order by created_at limit 1
) w on true
on conflict(warehouse_id,product_id) do update
set quantity=excluded.quantity, updated_at=now();

notify pgrst, 'reload schema';
