-- ARN ERP V3 - Ürün ve kategori yönetimi
-- Ürünleri ve fiyatları firma kullanıcıları kendileri girer.

create extension if not exists pgcrypto;

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, name)
);

alter table public.products
  add column if not exists category_id uuid references public.product_categories(id) on delete set null;

create unique index if not exists products_company_sku_unique
  on public.products(company_id, lower(sku))
  where sku is not null and btrim(sku) <> '';

create unique index if not exists products_company_barcode_unique
  on public.products(company_id, barcode)
  where barcode is not null and btrim(barcode) <> '';

create index if not exists product_categories_company_idx
  on public.product_categories(company_id);
create index if not exists products_category_idx
  on public.products(category_id);

alter table public.product_categories enable row level security;

drop policy if exists product_categories_company_access on public.product_categories;
create policy product_categories_company_access
on public.product_categories
for all
to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

grant select, insert, update, delete on public.product_categories to authenticated;

-- Eski metin kategorilerini kategori tablosuna aktar.
insert into public.product_categories(company_id, name)
select distinct company_id, btrim(category)
from public.products
where category is not null and btrim(category) <> ''
on conflict (company_id, name) do nothing;

update public.products p
set category_id = c.id
from public.product_categories c
where p.company_id = c.company_id
  and p.category_id is null
  and p.category is not null
  and lower(btrim(p.category)) = lower(btrim(c.name));
