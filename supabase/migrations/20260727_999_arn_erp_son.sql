-- ARN ERP SON - final database layer
-- Safe to run more than once.

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

create index if not exists idx_app_notifications_user_created
  on public.app_notifications(user_id, created_at desc);
create index if not exists idx_app_notifications_user_unread
  on public.app_notifications(user_id, is_read)
  where is_read = false;

alter table public.app_notifications enable row level security;

drop policy if exists app_notifications_select_own on public.app_notifications;
create policy app_notifications_select_own
on public.app_notifications for select
to authenticated
using (user_id = auth.uid());

drop policy if exists app_notifications_update_own on public.app_notifications;
create policy app_notifications_update_own
on public.app_notifications for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create or replace function public.notify_service_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_name text;
  v_date_text text;
begin
  if new.assigned_technician_id is not null
     and (old.assigned_technician_id is distinct from new.assigned_technician_id) then
    select coalesce(nullif(trim(full_name), ''), nullif(trim(company_name), ''), 'Müşteri')
      into v_customer_name
      from public.customers
     where id = new.customer_id;

    v_date_text := case
      when new.planned_date is null then ''
      else ' - ' || to_char(new.planned_date at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')
    end;

    insert into public.app_notifications(
      company_id, user_id, title, message, notification_type,
      route, entity_type, entity_id
    ) values (
      new.company_id,
      new.assigned_technician_id,
      'Yeni servis atandı',
      coalesce(v_customer_name, 'Müşteri') || v_date_text,
      'service_assignment',
      '/technician/jobs/' || new.id::text,
      'service_request',
      new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_service_assignment on public.service_requests;
create trigger trg_notify_service_assignment
after update of assigned_technician_id on public.service_requests
for each row execute function public.notify_service_assignment();

-- One consistent dashboard function used by all panels.
create or replace function public.erp_dashboard_summary(
  p_start timestamptz,
  p_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_result jsonb;
begin
  select company_id into v_company_id
  from public.profiles
  where id = auth.uid();

  if v_company_id is null then
    raise exception 'Firma bilgisi bulunamadı';
  end if;

  select jsonb_build_object(
    'pending', (select count(*) from public.service_requests
      where company_id = v_company_id and status = 'pending'),
    'assigned', (select count(*) from public.service_requests
      where company_id = v_company_id and status = 'assigned'),
    'active', (select count(*) from public.service_requests
      where company_id = v_company_id and status in ('assigned','in_progress')),
    'completed_period', (select count(*) from public.service_requests
      where company_id = v_company_id and status = 'completed'
        and coalesce(completed_at, updated_at, created_at) >= p_start
        and coalesce(completed_at, updated_at, created_at) < p_end),
    'low_stock', (select count(*) from public.warehouse_stocks ws
      join public.products p on p.id = ws.product_id
      where ws.company_id = v_company_id
        and ws.quantity <= coalesce(p.critical_stock, 0)),
    'collection_period', coalesce((select sum(amount) from public.payments
      where company_id = v_company_id and payment_date >= p_start and payment_date < p_end),0),
    'revenue_period', coalesce((select sum(total_amount) from public.services
      where company_id = v_company_id and completed_at >= p_start and completed_at < p_end),0),
    'open_balance', coalesce((select sum(total_amount - collected_amount) from public.services
      where company_id = v_company_id),0),
    'active_customers', (select count(*) from public.customers
      where company_id = v_company_id and coalesce(is_active,true) = true)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.erp_dashboard_summary(timestamptz,timestamptz) to authenticated;
