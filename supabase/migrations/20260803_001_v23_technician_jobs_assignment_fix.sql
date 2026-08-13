-- ARN ERP V23 - Teknisyen ataması, günlük işler ve bildirim düzeltmesi.
-- Excel aktarımıyla gelen müşteri kayıtlarını değiştirmez.

-- Eski veya eksik servislerde firma bilgisini müşteriden/teknisyenden tamamla.
update public.service_requests sr
set company_id = coalesce(c.company_id, p.company_id),
    updated_at = now()
from public.customers c
left join public.profiles p on p.id = sr.assigned_technician_id
where c.id = sr.customer_id
  and sr.company_id is null
  and coalesce(c.company_id, p.company_id) is not null;

-- JSON dönüşü, enum/date tip uyuşmazlıklarını tamamen önler.
drop function if exists public.technician_my_jobs_v23();
create function public.technician_my_jobs_v23()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(job_row order by job_row.planned_date asc nulls last, job_row.created_at desc),
    '[]'::jsonb
  )
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
      case
        when creator.role::text = 'secretary' then coalesce(creator.full_name, '')
        else ''
      end as secretary_name
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
  ) job_row;
$$;

revoke all on function public.technician_my_jobs_v23() from public, anon;
grant execute on function public.technician_my_jobs_v23() to authenticated;

-- Yeni servis ve atamalarda company_id boş kalmasın.
create or replace function public.ensure_service_request_company_v23()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.company_id is null then
    if new.assigned_technician_id is not null then
      select p.company_id into new.company_id
      from public.profiles p
      where p.id = new.assigned_technician_id;
    end if;

    if new.company_id is null and new.customer_id is not null then
      select c.company_id into new.company_id
      from public.customers c
      where c.id = new.customer_id;
    end if;

    if new.company_id is null then
      select p.company_id into new.company_id
      from public.profiles p
      where p.id = auth.uid();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_service_request_company_v23 on public.service_requests;
create trigger trg_service_request_company_v23
before insert or update of assigned_technician_id, customer_id, company_id
on public.service_requests
for each row execute function public.ensure_service_request_company_v23();

-- Atama bildirimi INSERT sırasında da çalışır ve NULL company_id kullanmaz.
create or replace function public.notify_service_assignment_v23()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_customer_name text;
  v_date_text text;
begin
  if new.assigned_technician_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.assigned_technician_id is not distinct from new.assigned_technician_id then
    return new;
  end if;

  select coalesce(new.company_id, p.company_id)
    into v_company_id
  from public.profiles p
  where p.id = new.assigned_technician_id;

  if v_company_id is null then
    return new;
  end if;

  select coalesce(nullif(trim(c.full_name), ''), nullif(trim(c.company_name), ''), 'Müşteri')
    into v_customer_name
  from public.customers c
  where c.id = new.customer_id;

  v_date_text := case
    when new.planned_date is null then ''
    else ' - ' || to_char(new.planned_date, 'DD.MM.YYYY HH24:MI')
  end;

  insert into public.app_notifications(
    company_id, user_id, title, message, notification_type,
    route, entity_type, entity_id
  ) values (
    v_company_id,
    new.assigned_technician_id,
    'Yeni servis atandı',
    coalesce(v_customer_name, 'Müşteri') || v_date_text,
    'service_assignment',
    '/technician/jobs/' || new.id::text,
    'service_request',
    new.id
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_service_assignment on public.service_requests;
drop trigger if exists trg_notify_service_assignment_v23 on public.service_requests;
create trigger trg_notify_service_assignment_v23
after insert or update of assigned_technician_id
on public.service_requests
for each row execute function public.notify_service_assignment_v23();

-- Mevcut atanmış açık işler için eksik bildirimleri tek seferlik oluştur.
insert into public.app_notifications(
  company_id, user_id, title, message, notification_type,
  route, entity_type, entity_id
)
select
  coalesce(sr.company_id, p.company_id),
  sr.assigned_technician_id,
  'Yeni servis atandı',
  coalesce(nullif(trim(c.full_name), ''), nullif(trim(c.company_name), ''), 'Müşteri'),
  'service_assignment',
  '/technician/jobs/' || sr.id::text,
  'service_request',
  sr.id
from public.service_requests sr
join public.profiles p on p.id = sr.assigned_technician_id
left join public.customers c on c.id = sr.customer_id
where sr.assigned_technician_id is not null
  and sr.status::text in ('assigned', 'in_progress', 'could_not_complete')
  and coalesce(sr.company_id, p.company_id) is not null
  and not exists (
    select 1
    from public.app_notifications n
    where n.user_id = sr.assigned_technician_id
      and n.entity_type = 'service_request'
      and n.entity_id = sr.id
      and n.notification_type = 'service_assignment'
  );

notify pgrst, 'reload schema';
