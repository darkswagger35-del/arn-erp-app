-- ARN ERP V23 - giriş, teknisyen işleri, servis tamamlama çekirdek düzeltmeleri

-- Kullanıcı adı alanı; mevcut profile kayıtlarını güncellemez.
alter table public.profiles
  add column if not exists username text;

create unique index if not exists profiles_username_unique_idx
  on public.profiles (lower(username))
  where username is not null and btrim(username) <> '';

-- Kullanıcı adı olarak profiles.username veya e-postanın @ öncesi kullanılabilir.
create or replace function public.erp_login_email_for_username(p_username text)
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select u.email
  from auth.users u
  left join public.profiles p on p.id = u.id
  where lower(coalesce(nullif(btrim(p.username), ''), split_part(u.email, '@', 1)))
        = lower(btrim(p_username))
    and coalesce(p.is_active, true) = true
  limit 1;
$$;

revoke all on function public.erp_login_email_for_username(text) from public;
grant execute on function public.erp_login_email_for_username(text) to anon, authenticated;

-- Servis taleplerinde company_id boş kalmasın.
create or replace function public.ensure_service_request_company_v23()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.company_id is null and new.customer_id is not null then
    select c.company_id into new.company_id
    from public.customers c
    where c.id = new.customer_id;
  end if;

  if new.company_id is null and new.assigned_technician_id is not null then
    select p.company_id into new.company_id
    from public.profiles p
    where p.id = new.assigned_technician_id;
  end if;

  if new.company_id is null and auth.uid() is not null then
    select p.company_id into new.company_id
    from public.profiles p
    where p.id = auth.uid();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_service_request_company_v23 on public.service_requests;
create trigger trg_service_request_company_v23
before insert or update of customer_id, assigned_technician_id, company_id
on public.service_requests
for each row execute function public.ensure_service_request_company_v23();

-- Geçmişte boş kalmış firma bilgilerini tamamla.
update public.service_requests sr
set company_id = coalesce(
      (select c.company_id from public.customers c where c.id = sr.customer_id),
      (select p.company_id from public.profiles p where p.id = sr.assigned_technician_id)
    ),
    updated_at = now()
where sr.company_id is null
  and coalesce(
        (select c.company_id from public.customers c where c.id = sr.customer_id),
        (select p.company_id from public.profiles p where p.id = sr.assigned_technician_id)
      ) is not null;

-- Teknisyen kendi atanmış açık işlerini RLS'den etkilenmeden güvenli biçimde alır.
drop function if exists public.technician_my_jobs_v23();
create function public.technician_my_jobs_v23()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(job order by job.planned_date nulls last, job.created_at desc), '[]'::jsonb)
  from (
    select
      sr.id,
      sr.customer_id,
      sr.created_by,
      sr.service_type::text as service_type,
      coalesce(sr.description, '') as description,
      sr.status::text as status,
      coalesce(sr.price, 0) as price,
      sr.planned_date,
      sr.planned_product_id,
      coalesce(sr.planned_product_name, '') as planned_product_name,
      coalesce(sr.planned_quantity, 0) as planned_quantity,
      coalesce(sr.planned_unit_price, 0) as planned_unit_price,
      sr.created_at,
      jsonb_build_object(
        'full_name', coalesce(c.full_name, ''),
        'company_name', coalesce(c.company_name, ''),
        'phone', coalesce(c.phone, ''),
        'address', coalesce(c.address, '')
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
      and sr.status::text in ('assigned', 'in_progress', 'could_not_complete')
      and (sr.company_id is null or sr.company_id = me.company_id)
  ) job;
$$;

revoke all on function public.technician_my_jobs_v23() from public, anon;
grant execute on function public.technician_my_jobs_v23() to authenticated;

-- Aynı bakım kaydının hem trigger hem complete_service_v5 tarafından iki kez
-- oluşturulması duplicate key hatasına yol açıyordu. Bakım kaydını V5 yönetir.
drop trigger if exists trg_service_item_maintenance on public.service_items;

notify pgrst, 'reload schema';
