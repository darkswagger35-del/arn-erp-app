-- ARN ERP V25: kullanıcı adıyla giriş ve teknisyen iş listesi desteği

alter table public.profiles add column if not exists username text;

create unique index if not exists profiles_username_unique_idx
  on public.profiles (lower(username))
  where username is not null and btrim(username) <> '';

-- Mevcut kullanıcılar için e-postanın @ öncesini başlangıç kullanıcı adı yapar.
update public.profiles p
set username = lower(split_part(u.email, '@', 1))
from auth.users u
where u.id = p.id
  and (p.username is null or btrim(p.username) = '')
  and not exists (
    select 1 from public.profiles p2
    where p2.id <> p.id
      and lower(p2.username) = lower(split_part(u.email, '@', 1))
  );

create or replace function public.erp_login_email_for_username(p_username text)
returns text
language sql
security definer
set search_path = public, auth
as $$
  select u.email
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(p.username) = lower(btrim(p_username))
    and coalesce(p.is_active, true) = true
  limit 1;
$$;

revoke all on function public.erp_login_email_for_username(text) from public;
grant execute on function public.erp_login_email_for_username(text) to anon, authenticated;

-- JSON dönüşü kullanıldığı için mevcut kolonların numeric/enum tipleri fark etse de çalışır.
create or replace function public.technician_jobs_v25()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(job_row order by job_row.planned_date asc nulls last, job_row.created_at desc), '[]'::jsonb)
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
      coalesce(nullif(c.company_name, ''), c.full_name, '') as customer_name,
      coalesce(c.phone, '') as phone,
      coalesce(c.address, '') as address,
      case when creator.role::text = 'secretary'
        then coalesce(creator.full_name, '') else '' end as secretary_name,
      sr.created_at
    from public.service_requests sr
    left join public.customers c on c.id = sr.customer_id
    left join public.profiles creator on creator.id = sr.created_by
    where sr.assigned_technician_id = auth.uid()
      and sr.status::text in ('assigned', 'in_progress', 'could_not_complete')
  ) job_row;
$$;

grant execute on function public.technician_jobs_v25() to authenticated;
