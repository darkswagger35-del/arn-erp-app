-- ARN ERP v1 operasyon modülleri
-- Supabase SQL Editor'da tek sefer çalıştırılabilir.

create extension if not exists pgcrypto;

alter table if exists public.service_requests
  add column if not exists company_id uuid references public.companies(id) on delete cascade,
  add column if not exists priority text not null default 'normal',
  add column if not exists payment_status text not null default 'unpaid',
  add column if not exists collected_amount numeric(12,2) not null default 0,
  add column if not exists assigned_vehicle_id uuid,
  add column if not exists completed_at timestamptz;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  sku text,
  barcode text,
  category text,
  unit text not null default 'adet',
  purchase_price numeric(12,2) not null default 0,
  sale_price numeric(12,2) not null default 0,
  stock_quantity numeric(12,2) not null default 0,
  critical_stock numeric(12,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  plate text not null,
  brand text,
  model text,
  model_year integer,
  current_km numeric(12,2) not null default 0,
  assigned_technician_id uuid references public.profiles(id) on delete set null,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, plate)
);

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  type text not null default 'main',
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  warehouse_id uuid references public.warehouses(id) on delete set null,
  service_request_id uuid references public.service_requests(id) on delete set null,
  movement_type text not null check (movement_type in ('in','out','transfer','adjustment','service')),
  quantity numeric(12,2) not null check (quantity > 0),
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  service_request_id uuid references public.service_requests(id) on delete set null,
  amount numeric(12,2) not null check (amount >= 0),
  payment_method text not null default 'cash',
  description text not null default 'Tahsilat',
  payment_date timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists products_company_idx on public.products(company_id);
create index if not exists vehicles_company_idx on public.vehicles(company_id);
create index if not exists warehouses_company_idx on public.warehouses(company_id);
create index if not exists stock_movements_company_idx on public.stock_movements(company_id);
create index if not exists payments_company_idx on public.payments(company_id);
create index if not exists service_requests_company_idx on public.service_requests(company_id);

-- Mevcut servis taleplerine firma bilgisini müşteriden aktar.
update public.service_requests sr
set company_id = c.company_id
from public.customers c
where sr.customer_id = c.id and sr.company_id is null;

-- Güncel kullanıcı firmasını güvenli biçimde döndürür.
create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select company_id from public.profiles where id = auth.uid();
$$;

alter table public.products enable row level security;
alter table public.vehicles enable row level security;
alter table public.warehouses enable row level security;
alter table public.stock_movements enable row level security;
alter table public.payments enable row level security;

-- Aynı isimli politikalar varsa yeniden oluştur.
do $$
declare
  t text;
begin
  foreach t in array array['products','vehicles','warehouses','stock_movements','payments'] loop
    execute format('drop policy if exists %I on public.%I', t || '_company_access', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (company_id = public.current_company_id()) with check (company_id = public.current_company_id())',
      t || '_company_access', t
    );
  end loop;
end $$;

grant select, insert, update, delete on public.products to authenticated;
grant select, insert, update, delete on public.vehicles to authenticated;
grant select, insert, update, delete on public.warehouses to authenticated;
grant select, insert, update, delete on public.stock_movements to authenticated;
grant select, insert, update, delete on public.payments to authenticated;

-- Stok hareketi eklenince ürün toplamını güncelle.
create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.movement_type = 'in' then
    update public.products set stock_quantity = stock_quantity + new.quantity, updated_at = now() where id = new.product_id;
  elsif new.movement_type in ('out','service') then
    update public.products set stock_quantity = stock_quantity - new.quantity, updated_at = now() where id = new.product_id;
  end if;
  return new;
end;
$$;

drop trigger if exists stock_movement_apply_trigger on public.stock_movements;
create trigger stock_movement_apply_trigger
after insert on public.stock_movements
for each row execute function public.apply_stock_movement();
