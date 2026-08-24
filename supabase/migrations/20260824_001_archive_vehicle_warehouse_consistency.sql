-- Arşivlenmiş / geçersiz teknikerlere ait araç depolarını aktif listeden kaldır.
-- Uygulama tarafı da aktif profil kontrolü yapar; bu migration veri bütünlüğünü düzeltir.

update public.warehouses w
set is_active = false,
    updated_at = now()
where w.type = 'vehicle'
  and w.is_active = true
  and (
    w.assigned_technician_id is null
    or not exists (
      select 1
      from public.profiles p
      where p.id = w.assigned_technician_id
        and p.company_id = w.company_id
        and p.role::text = 'technician'
        and p.is_active = true
        and p.deleted_at is null
    )
  );

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

  -- Arşivlenen teknikerin veya eski/bağlantısız kaydın araç deposu tekrar görünmesin.
  update public.warehouses w
  set is_active = false,
      updated_at = now()
  where w.company_id = cid
    and w.type = 'vehicle'
    and w.is_active = true
    and (
      w.assigned_technician_id is null
      or not exists (
        select 1
        from public.profiles p
        where p.id = w.assigned_technician_id
          and p.company_id = w.company_id
          and p.role::text = 'technician'
          and p.is_active = true
          and p.deleted_at is null
      )
    );

  insert into public.warehouses(company_id, name, type, is_active)
  select cid, 'Ana Depo', 'main', true
  where not exists (
    select 1 from public.warehouses
    where company_id = cid and type = 'main' and is_active = true
  );

  for tech in
    select id, company_id, full_name
    from public.profiles
    where company_id = cid
      and role::text = 'technician'
      and is_active = true
      and deleted_at is null
  loop
    if not exists (
      select 1 from public.warehouses w
      where w.company_id = tech.company_id
        and w.type = 'vehicle'
        and w.assigned_technician_id = tech.id
        and w.is_active = true
    ) then
      -- Aynı teknikere ait eski pasif araç deposu varsa geçmiş stok/hareketi koruyarak geri aç.
      update public.warehouses w
      set name = tech.full_name || ' Araç Deposu',
          is_active = true,
          updated_at = now()
      where w.id = (
        select x.id
        from public.warehouses x
        where x.company_id = tech.company_id
          and x.type = 'vehicle'
          and x.assigned_technician_id = tech.id
        order by x.is_active desc, x.created_at nulls last, x.id
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
