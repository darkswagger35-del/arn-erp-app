-- ARN ERP: bakım takibi, eski müşteri aktarımı ve hatalı stok hareketi silme

alter table public.products
  add column if not exists maintenance_months integer not null default 0
  check (maintenance_months between 0 and 120);

create table if not exists public.customer_maintenance_records (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  service_id uuid references public.services(id) on delete cascade,
  performed_at date not null,
  next_maintenance_date date,
  assigned_user_id uuid references public.profiles(id) on delete set null,
  assigned_role text not null default 'secretary'
    check (assigned_role in ('secretary', 'technician')),
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists customer_maintenance_company_idx
  on public.customer_maintenance_records(company_id);
create index if not exists customer_maintenance_customer_idx
  on public.customer_maintenance_records(customer_id);
create index if not exists customer_maintenance_next_date_idx
  on public.customer_maintenance_records(next_maintenance_date);
create unique index if not exists customer_maintenance_service_product_unique
  on public.customer_maintenance_records(service_id, product_id)
  where service_id is not null;

alter table public.customer_maintenance_records enable row level security;

drop policy if exists customer_maintenance_company_access
  on public.customer_maintenance_records;
create policy customer_maintenance_company_access
on public.customer_maintenance_records
for all to authenticated
using (company_id = public.current_company_id())
with check (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin', 'manager', 'secretary', 'technician')
);

grant select, insert, update, delete
  on public.customer_maintenance_records to authenticated;

-- Hatalı bir stok hareketini ve varsa onun iptal/ters kaydını tamamen siler.
-- Sonrasında stokları kalan hareketlerden yeniden hesaplar.
create or replace function public.delete_stock_movement(p_movement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid := public.current_company_id();
  v_role text := public.current_user_role();
  v_target public.stock_movements%rowtype;
  v_original_id uuid;
begin
  if v_role not in ('admin', 'manager') then
    raise exception 'Stok hareketi silme yetkiniz yok.';
  end if;

  select * into v_target
  from public.stock_movements
  where id = p_movement_id and company_id = v_company
  for update;

  if not found then
    raise exception 'Stok hareketi bulunamadı.';
  end if;

  -- Seçilen kayıt bir ters kayıt ise asıl kaydı bul.
  if coalesce(v_target.notes, '') like 'İPTAL:%' then
    begin
      v_original_id := split_part(v_target.notes, ':', 2)::uuid;
    exception when others then
      v_original_id := null;
    end;
  else
    v_original_id := v_target.id;
  end if;

  -- Asıl kayıt ve ona bağlı ters kayıt birlikte silinir.
  delete from public.stock_movements
  where company_id = v_company
    and (
      id = v_original_id
      or id = p_movement_id
      or notes = 'İPTAL:' || coalesce(v_original_id, p_movement_id)::text
      or notes like '%İptal edildi:%' and id = coalesce(v_original_id, p_movement_id)
    );

  -- Firma toplam ürün stoklarını kalan hareketlerden yeniden hesapla.
  update public.products p
  set stock_quantity = coalesce(calc.quantity, 0),
      updated_at = now()
  from (
    select p2.id as product_id,
      coalesce(sum(
        case
          when sm.movement_type in ('in', 'transfer_in') then sm.quantity
          when sm.movement_type in ('out', 'service', 'transfer_out') then -sm.quantity
          else 0
        end
      ), 0)::numeric(12,2) as quantity
    from public.products p2
    left join public.stock_movements sm
      on sm.product_id = p2.id and sm.company_id = v_company
    where p2.company_id = v_company
    group by p2.id
  ) calc
  where p.id = calc.product_id and p.company_id = v_company;

  -- Depo stoklarını da kalan hareketlerden yeniden oluştur.
  delete from public.warehouse_stocks where company_id = v_company;
  insert into public.warehouse_stocks(
    company_id, warehouse_id, product_id, quantity, updated_at
  )
  select
    v_company,
    sm.warehouse_id,
    sm.product_id,
    greatest(sum(
      case
        when sm.movement_type in ('in', 'transfer_in') then sm.quantity
        when sm.movement_type in ('out', 'service', 'transfer_out') then -sm.quantity
        else 0
      end
    ), 0)::numeric(12,2),
    now()
  from public.stock_movements sm
  where sm.company_id = v_company and sm.warehouse_id is not null
  group by sm.warehouse_id, sm.product_id
  having sum(
    case
      when sm.movement_type in ('in', 'transfer_in') then sm.quantity
      when sm.movement_type in ('out', 'service', 'transfer_out') then -sm.quantity
      else 0
    end
  ) > 0;
end;
$$;

grant execute on function public.delete_stock_movement(uuid) to authenticated;

-- Sekreterin de bakım kaydı için firma teknisyen/sekreter listesini görebilmesi.
create or replace function public.list_maintenance_staff()
returns table(id uuid, full_name text, role text)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.role
  from public.profiles p
  where p.company_id = public.current_company_id()
    and p.is_active = true
    and p.role in ('secretary', 'technician')
    and public.current_user_role() in ('admin', 'manager', 'secretary')
  order by p.full_name;
$$;

grant execute on function public.list_maintenance_staff() to authenticated;


-- Teknisyen bir servisi tamamladığında kullanılan ve bakım süresi tanımlı
-- ürünler için bakım sayacını otomatik başlatır.
create or replace function public.create_maintenance_from_service_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_service public.services%rowtype;
  v_months integer;
  v_completed_date date;
begin
  if new.product_id is null then return new; end if;

  select * into v_service from public.services where id = new.service_id;
  select coalesce(maintenance_months, 0) into v_months
  from public.products where id = new.product_id;

  if v_months <= 0 then return new; end if;
  v_completed_date := v_service.completed_at::date;

  insert into public.customer_maintenance_records(
    company_id, customer_id, product_id, service_id, performed_at,
    next_maintenance_date, assigned_user_id, assigned_role, notes, created_by
  ) values (
    new.company_id, v_service.customer_id, new.product_id, new.service_id,
    v_completed_date, (v_completed_date + make_interval(months => v_months))::date,
    v_service.technician_id, 'technician',
    'Tamamlanan servisten otomatik bakım kaydı', v_service.technician_id
  )
  on conflict (service_id, product_id) where service_id is not null
  do update set
    performed_at = excluded.performed_at,
    next_maintenance_date = excluded.next_maintenance_date,
    assigned_user_id = excluded.assigned_user_id,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists trg_service_item_maintenance on public.service_items;
create trigger trg_service_item_maintenance
after insert on public.service_items
for each row execute function public.create_maintenance_from_service_item();
