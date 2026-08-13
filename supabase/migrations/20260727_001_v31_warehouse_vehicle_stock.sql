-- ARN ERP V3.1 - Ana depo, teknisyen araç depoları ve güvenli transfer

alter table public.warehouses
  add column if not exists assigned_technician_id uuid references public.profiles(id) on delete set null;

alter table public.stock_movements
  add column if not exists transfer_group_id uuid;

create unique index if not exists warehouses_one_main_per_company
  on public.warehouses(company_id) where type = 'main' and is_active = true;

create unique index if not exists warehouses_one_vehicle_per_technician
  on public.warehouses(company_id, assigned_technician_id)
  where type = 'vehicle' and assigned_technician_id is not null and is_active = true;

create index if not exists warehouses_assigned_technician_idx
  on public.warehouses(assigned_technician_id);
create index if not exists stock_movements_transfer_group_idx
  on public.stock_movements(transfer_group_id);


-- Mevcut firmalara ana depo oluştur ve önceki toplam stoğu ana depoya taşı.
insert into public.warehouses(company_id, name, type, is_active)
select c.id, 'Ana Depo', 'main', true
from public.companies c
where not exists (
  select 1 from public.warehouses w
  where w.company_id = c.id and w.type = 'main' and w.is_active = true
);

insert into public.warehouse_stocks(company_id, warehouse_id, product_id, quantity)
select p.company_id, w.id, p.id, greatest(p.stock_quantity, 0)
from public.products p
join public.warehouses w on w.company_id = p.company_id and w.type = 'main' and w.is_active = true
where not exists (
  select 1 from public.warehouse_stocks ws
  where ws.warehouse_id = w.id and ws.product_id = p.id
);

-- Firma için ana depoyu ve aktif teknisyenlerin araç depolarını hazırlar.
create or replace function public.ensure_company_warehouses()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := public.current_company_id();
begin
  if cid is null then
    raise exception 'Firma bilgisi bulunamadı.';
  end if;

  insert into public.warehouses(company_id, name, type, is_active)
  select cid, 'Ana Depo', 'main', true
  where not exists (
    select 1 from public.warehouses
    where company_id = cid and type = 'main' and is_active = true
  );

  insert into public.warehouses(
    company_id, name, type, assigned_technician_id, is_active
  )
  select p.company_id, p.full_name || ' Araç Deposu', 'vehicle', p.id, true
  from public.profiles p
  where p.company_id = cid
    and p.role = 'technician'
    and p.is_active = true
    and not exists (
      select 1 from public.warehouses w
      where w.company_id = p.company_id
        and w.type = 'vehicle'
        and w.assigned_technician_id = p.id
        and w.is_active = true
    );
end;
$$;

grant execute on function public.ensure_company_warehouses() to authenticated;

-- Ana depo / araç deposu arasında atomik ürün transferi.
create or replace function public.transfer_stock(
  p_product_id uuid,
  p_source_warehouse_id uuid,
  p_destination_warehouse_id uuid,
  p_quantity numeric,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := public.current_company_id();
  uid uuid := auth.uid();
  source_qty numeric(12,2);
  transfer_id uuid := gen_random_uuid();
begin
  if cid is null then raise exception 'Firma bilgisi bulunamadı.'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Miktar sıfırdan büyük olmalıdır.'; end if;
  if p_source_warehouse_id = p_destination_warehouse_id then raise exception 'Kaynak ve hedef depo aynı olamaz.'; end if;

  if not exists (select 1 from public.products where id = p_product_id and company_id = cid and is_active = true) then
    raise exception 'Ürün bulunamadı.';
  end if;
  if not exists (select 1 from public.warehouses where id = p_source_warehouse_id and company_id = cid and is_active = true) then
    raise exception 'Kaynak depo bulunamadı.';
  end if;
  if not exists (select 1 from public.warehouses where id = p_destination_warehouse_id and company_id = cid and is_active = true) then
    raise exception 'Hedef depo bulunamadı.';
  end if;

  insert into public.warehouse_stocks(company_id, warehouse_id, product_id, quantity)
  values (cid, p_source_warehouse_id, p_product_id, 0)
  on conflict (warehouse_id, product_id) do nothing;
  insert into public.warehouse_stocks(company_id, warehouse_id, product_id, quantity)
  values (cid, p_destination_warehouse_id, p_product_id, 0)
  on conflict (warehouse_id, product_id) do nothing;

  select quantity into source_qty
  from public.warehouse_stocks
  where warehouse_id = p_source_warehouse_id and product_id = p_product_id
  for update;

  if source_qty < p_quantity then
    raise exception 'Yetersiz stok. Kaynak depoda % adet var.', source_qty;
  end if;

  -- Mevcut stok tetikleyicisi in/out hareketlerini depo ve ürün toplamında uygular.
  insert into public.stock_movements(
    company_id, product_id, warehouse_id, movement_type, quantity,
    notes, created_by, transfer_group_id
  ) values (
    cid, p_product_id, p_source_warehouse_id, 'out', p_quantity,
    coalesce(p_notes, 'Depolar arası transfer çıkışı'), uid, transfer_id
  );

  insert into public.stock_movements(
    company_id, product_id, warehouse_id, movement_type, quantity,
    notes, created_by, transfer_group_id
  ) values (
    cid, p_product_id, p_destination_warehouse_id, 'in', p_quantity,
    coalesce(p_notes, 'Depolar arası transfer girişi'), uid, transfer_id
  );

  return transfer_id;
end;
$$;

grant execute on function public.transfer_stock(uuid, uuid, uuid, numeric, text) to authenticated;

-- Yönetici/manager/sekreter manuel stok girişi yapabilir; teknisyen yapamaz.
drop policy if exists stock_movements_company_access on public.stock_movements;
create policy stock_movements_read_company
on public.stock_movements for select to authenticated
using (company_id = public.current_company_id());

create policy stock_movements_insert_authorized
on public.stock_movements for insert to authenticated
with check (
  company_id = public.current_company_id()
  and (
    public.current_user_role() in ('admin', 'manager', 'secretary')
    or (public.current_user_role() = 'technician' and movement_type = 'service' and created_by = auth.uid())
  )
);
