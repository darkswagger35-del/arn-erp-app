-- V12: müşteri işlem geçmişi, ürün kalıcı silme ve mükerrer araç deposu düzeltmesi.

-- Ürün silinse bile geçmişte ürün adı saklanabilsin.
alter table public.customer_maintenance_records
  add column if not exists product_name text;

update public.customer_maintenance_records cmr
set product_name = p.name
from public.products p
where cmr.product_id = p.id
  and nullif(btrim(cmr.product_name), '') is null;

alter table public.customer_maintenance_records
  alter column product_id drop not null;

alter table public.customer_maintenance_records
  drop constraint if exists customer_maintenance_records_product_id_fkey;

alter table public.customer_maintenance_records
  add constraint customer_maintenance_records_product_id_fkey
  foreign key (product_id) references public.products(id) on delete set null;

-- Aynı isimle kalmış mükerrer araç depolarını tek depoda birleştir.
do $$
declare
  grp record;
  keep_id uuid;
  duplicate_id uuid;
begin
  for grp in
    select company_id, lower(btrim(name)) as normalized_name
    from public.warehouses
    where type = 'vehicle' and is_active = true
    group by company_id, lower(btrim(name))
    having count(*) > 1
  loop
    select w.id into keep_id
    from public.warehouses w
    left join public.profiles p on p.id = w.assigned_technician_id
    where w.company_id = grp.company_id
      and w.type = 'vehicle'
      and w.is_active = true
      and lower(btrim(w.name)) = grp.normalized_name
    order by (coalesce(p.is_active, false) and p.role = 'technician') desc,
             (w.assigned_technician_id is not null) desc,
             w.created_at nulls last,
             w.id
    limit 1;

    for duplicate_id in
      select w.id
      from public.warehouses w
      where w.company_id = grp.company_id
        and w.type = 'vehicle'
        and w.is_active = true
        and lower(btrim(w.name)) = grp.normalized_name
        and w.id <> keep_id
    loop
      insert into public.warehouse_stocks(company_id, warehouse_id, product_id, quantity)
      select company_id, keep_id, product_id, quantity
      from public.warehouse_stocks
      where warehouse_id = duplicate_id
      on conflict (warehouse_id, product_id)
      do update set
        quantity = public.warehouse_stocks.quantity + excluded.quantity,
        updated_at = now();

      update public.stock_movements
      set warehouse_id = keep_id
      where warehouse_id = duplicate_id;

      delete from public.warehouse_stocks where warehouse_id = duplicate_id;
      delete from public.warehouses where id = duplicate_id;
    end loop;
  end loop;
end $$;

-- Aktif teknisyen için aynı isimli eski depo varsa onu yeni profil ile eşleştir,
-- ikinci bir depo oluşturma.
create or replace function public.ensure_company_warehouses()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := public.current_company_id();
  tech record;
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

  for tech in
    select id, company_id, full_name
    from public.profiles
    where company_id = cid and role = 'technician' and is_active = true
  loop
    if not exists (
      select 1 from public.warehouses w
      where w.company_id = tech.company_id
        and w.type = 'vehicle'
        and w.assigned_technician_id = tech.id
        and w.is_active = true
    ) then
      update public.warehouses w
      set assigned_technician_id = tech.id,
          name = tech.full_name || ' Araç Deposu',
          is_active = true
      where w.id = (
        select x.id
        from public.warehouses x
        where x.company_id = tech.company_id
          and x.type = 'vehicle'
          and x.is_active = true
          and lower(btrim(x.name)) =
              lower(btrim(tech.full_name || ' Araç Deposu'))
        order by x.created_at nulls last, x.id
        limit 1
      );

      if not found then
        insert into public.warehouses(
          company_id, name, type, assigned_technician_id, is_active
        ) values (
          tech.company_id, tech.full_name || ' Araç Deposu', 'vehicle', tech.id, true
        );
      end if;
    end if;
  end loop;
end;
$$;

grant execute on function public.ensure_company_warehouses() to authenticated;

-- Ürün silme: bakım geçmişinde ürün adını koru, bağlantıları güvenle kaldır.
drop function if exists public.delete_product_v11(uuid);
create function public.delete_product_v11(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid := auth.uid();
  cid uuid;
  role_name text;
  deleted_product_name text;
begin
  select company_id, role into cid, role_name
  from public.profiles
  where id=uid and is_active=true;

  if cid is null or role_name not in ('admin','manager') then
    raise exception 'Yetkiniz yok.';
  end if;

  select name into deleted_product_name
  from public.products
  where id=p_product_id and company_id=cid;

  if deleted_product_name is null then
    raise exception 'Ürün bulunamadı.';
  end if;

  update public.customer_maintenance_records
  set product_name = coalesce(nullif(product_name, ''), deleted_product_name),
      product_id = null,
      updated_at = now()
  where company_id=cid and product_id=p_product_id;

  update public.service_requests
  set planned_product_id=null,
      planned_product_name=coalesce(planned_product_name, deleted_product_name),
      planned_quantity=0,
      planned_unit_price=0
  where company_id=cid and planned_product_id=p_product_id and status<>'completed';

  update public.service_items
  set product_id=null,
      product_name=coalesce(nullif(product_name, ''), deleted_product_name)
  where company_id=cid and product_id=p_product_id;

  update public.historical_customer_sales
  set product_id=null,
      product_name=coalesce(nullif(product_name, ''), deleted_product_name)
  where company_id=cid and product_id=p_product_id;

  delete from public.warehouse_stocks where company_id=cid and product_id=p_product_id;
  delete from public.stock_movements where company_id=cid and product_id=p_product_id;
  delete from public.products where company_id=cid and id=p_product_id;
end;
$$;

grant execute on function public.delete_product_v11(uuid) to authenticated;
