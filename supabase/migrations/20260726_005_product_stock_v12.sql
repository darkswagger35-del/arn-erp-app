-- ARN ERP v1.2 - ürün, kategori ve depo bazlı stok yönetimi
-- Ürünler sistem tarafından hazır gelmez. Firma kendi ürünlerini ve fiyatlarını uygulamadan girer.

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, name)
);

alter table public.products
  add column if not exists category_id uuid references public.product_categories(id) on delete set null;

create unique index if not exists products_company_sku_unique
  on public.products(company_id, lower(sku)) where sku is not null and btrim(sku) <> '';
create unique index if not exists products_company_barcode_unique
  on public.products(company_id, barcode) where barcode is not null and btrim(barcode) <> '';
create index if not exists products_category_idx on public.products(category_id);

create table if not exists public.warehouse_stocks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity numeric(12,2) not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  unique(warehouse_id, product_id)
);

create index if not exists product_categories_company_idx on public.product_categories(company_id);
create index if not exists warehouse_stocks_company_idx on public.warehouse_stocks(company_id);
create index if not exists warehouse_stocks_product_idx on public.warehouse_stocks(product_id);

alter table public.product_categories enable row level security;
alter table public.warehouse_stocks enable row level security;

drop policy if exists product_categories_company_access on public.product_categories;
create policy product_categories_company_access
on public.product_categories for all to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

drop policy if exists warehouse_stocks_company_access on public.warehouse_stocks;
create policy warehouse_stocks_company_access
on public.warehouse_stocks for all to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

grant select, insert, update, delete on public.product_categories to authenticated;
grant select, insert, update, delete on public.warehouse_stocks to authenticated;

-- Stok çıkışında eksi stoğa izin verme ve genel/depo stoklarını birlikte güncelle.
create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_product_stock numeric(12,2);
  current_warehouse_stock numeric(12,2);
  stock_delta numeric(12,2);
begin
  select stock_quantity into current_product_stock
  from public.products
  where id = new.product_id
  for update;

  if current_product_stock is null then
    raise exception 'Ürün bulunamadı.';
  end if;

  if new.movement_type in ('out', 'service') then
    stock_delta := -new.quantity;
  else
    stock_delta := new.quantity;
  end if;

  if current_product_stock + stock_delta < 0 then
    raise exception 'Yetersiz stok. Mevcut stok: %', current_product_stock;
  end if;

  update public.products
  set stock_quantity = stock_quantity + stock_delta,
      updated_at = now()
  where id = new.product_id;

  if new.warehouse_id is not null then
    insert into public.warehouse_stocks(company_id, warehouse_id, product_id, quantity)
    values (new.company_id, new.warehouse_id, new.product_id, 0)
    on conflict (warehouse_id, product_id) do nothing;

    select quantity into current_warehouse_stock
    from public.warehouse_stocks
    where warehouse_id = new.warehouse_id and product_id = new.product_id
    for update;

    if current_warehouse_stock + stock_delta < 0 then
      raise exception 'Seçilen depoda yeterli stok yok. Depo stoğu: %', current_warehouse_stock;
    end if;

    update public.warehouse_stocks
    set quantity = quantity + stock_delta,
        updated_at = now()
    where warehouse_id = new.warehouse_id and product_id = new.product_id;
  end if;

  return new;
end;
$$;

-- Eski tetikleyiciyi yeni güvenli fonksiyonla devam ettir.
drop trigger if exists stock_movement_apply_trigger on public.stock_movements;
create trigger stock_movement_apply_trigger
after insert on public.stock_movements
for each row execute function public.apply_stock_movement();
