-- ARN ERP v1.1 - teknisyen servis yürütme ve tamamlama

alter table public.service_requests
  add column if not exists started_at timestamptz,
  add column if not exists completion_note text;

alter table public.service_requests
  drop constraint if exists service_requests_status_check;

alter table public.service_requests
  add constraint service_requests_status_check
  check (status in (
    'pending',
    'assigned',
    'in_progress',
    'completed',
    'cancelled',
    'could_not_complete'
  ));

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  service_request_id uuid not null unique references public.service_requests(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  technician_id uuid not null references public.profiles(id) on delete restrict,
  work_description text not null,
  product_total numeric(12,2) not null default 0,
  labor_amount numeric(12,2) not null default 0,
  discount_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  collected_amount numeric(12,2) not null default 0,
  payment_method text not null default 'cash',
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.service_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete cascade,
  service_request_id uuid not null references public.service_requests(id) on delete restrict,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null default 0,
  line_total numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists services_company_idx on public.services(company_id);
create index if not exists services_customer_idx on public.services(customer_id);
create index if not exists services_technician_idx on public.services(technician_id);
create index if not exists service_items_service_idx on public.service_items(service_id);

alter table public.services enable row level security;
alter table public.service_items enable row level security;

drop policy if exists services_company_access on public.services;
create policy services_company_access
on public.services
for all
to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

drop policy if exists service_items_company_access on public.service_items;
create policy service_items_company_access
on public.service_items
for all
to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

grant select, insert, update on public.services to authenticated;
grant select, insert, update on public.service_items to authenticated;

-- Teknisyen yalnızca kendisine atanmış aktif işleri görebilsin ve güncelleyebilsin.
-- Mevcut genel firma politikası varsa bu ek politika onunla birlikte çalışır.
drop policy if exists service_requests_technician_access on public.service_requests;
create policy service_requests_technician_access
on public.service_requests
for select
to authenticated
using (
  company_id = public.current_company_id()
  and (
    assigned_technician_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('admin', 'manager', 'secretary')
    )
  )
);
