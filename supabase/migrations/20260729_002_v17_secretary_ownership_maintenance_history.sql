-- ARN ERP V17
-- Sekreter müşteri sahipliği, servis sonrası bakım yenileme,
-- geçmiş servis silme ve personel görünürlüğü.

alter table public.customer_maintenance_records
  add column if not exists secretary_id uuid references public.profiles(id) on delete set null,
  add column if not exists technician_id uuid references public.profiles(id) on delete set null;

create index if not exists customer_maintenance_secretary_idx
  on public.customer_maintenance_records(secretary_id, next_maintenance_date);
create index if not exists customer_maintenance_technician_idx
  on public.customer_maintenance_records(technician_id, next_maintenance_date);

-- Eski kayıtları mümkün olduğunca doldur.
update public.customer_maintenance_records cmr
set secretary_id = c.created_by
from public.customers c
join public.profiles p on p.id = c.created_by and p.role = 'secretary'
where cmr.customer_id = c.id and cmr.secretary_id is null;

update public.customer_maintenance_records cmr
set technician_id = s.technician_id
from public.services s
where cmr.service_id = s.id and cmr.technician_id is null;

-- Müşteri kartında kayıt eden sekreter ve son teknisyen.
drop function if exists public.customer_staff_summary_v17(uuid);
create function public.customer_staff_summary_v17(p_customer_id uuid)
returns table(secretary_name text, technician_name text)
language sql
stable
security definer
set search_path = public
as $$
  select
    creator.full_name,
    (
      select tech.full_name
      from public.services s
      left join public.profiles tech on tech.id = s.technician_id
      where s.customer_id = c.id
      order by s.completed_at desc nulls last
      limit 1
    )
  from public.customers c
  left join public.profiles creator on creator.id = c.created_by
  where c.id = p_customer_id
    and c.company_id = public.current_company_id();
$$;
grant execute on function public.customer_staff_summary_v17(uuid) to authenticated;

-- Personel listesi yönetici için sekreter ve teknisyenleri verir.
drop function if exists public.list_historical_staff_v17();
create function public.list_historical_staff_v17()
returns table(id uuid, full_name text, role text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.role
  from public.profiles p
  where p.company_id = public.current_company_id()
    and p.is_active = true
    and p.role in ('secretary','technician')
  order by p.role, p.full_name;
$$;
grant execute on function public.list_historical_staff_v17() to authenticated;

-- Yönetici geçmiş müşteri eklerken sekreter ve teknisyen seçebilir.
drop function if exists public.create_historical_customer_v17(text,text,text,text,text,date,uuid,numeric,numeric,text,date,integer,uuid,uuid);
create function public.create_historical_customer_v17(
  p_full_name text,
  p_phone text,
  p_city text,
  p_district text,
  p_address text,
  p_record_date date,
  p_product_id uuid,
  p_quantity numeric,
  p_amount numeric,
  p_payment_status text,
  p_payment_due_date date,
  p_maintenance_months integer,
  p_secretary_id uuid,
  p_technician_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := public.current_company_id();
  uid uuid := auth.uid();
  customer_id uuid;
  product_name_value text;
  next_date date;
begin
  if cid is null or uid is null then raise exception 'Oturum veya firma bulunamadı.'; end if;
  if public.current_user_role() not in ('manager','admin') then
    raise exception 'Geçmiş müşteri kaydını yalnızca yönetici oluşturabilir.';
  end if;

  select name into product_name_value
  from public.products
  where id = p_product_id and company_id = cid and is_active = true;
  if product_name_value is null then raise exception 'Ürün bulunamadı.'; end if;

  if p_secretary_id is not null and not exists(
    select 1 from public.profiles where id=p_secretary_id and company_id=cid and role='secretary' and is_active
  ) then raise exception 'Sekreter seçimi geçersiz.'; end if;
  if p_technician_id is not null and not exists(
    select 1 from public.profiles where id=p_technician_id and company_id=cid and role='technician' and is_active
  ) then raise exception 'Teknisyen seçimi geçersiz.'; end if;

  insert into public.customers(
    company_id, customer_type, full_name, phone, city, district, address,
    is_active, registration_date, created_at, updated_at, created_by, updated_by
  ) values (
    cid, 'individual', btrim(p_full_name), btrim(p_phone), btrim(p_city), btrim(p_district), btrim(p_address),
    true, p_record_date, p_record_date, now(), coalesce(p_secretary_id, uid), uid
  ) returning id into customer_id;

  next_date := case when coalesce(p_maintenance_months,0)>0
    then (p_record_date + make_interval(months => p_maintenance_months))::date else null end;

  insert into public.customer_maintenance_records(
    company_id, customer_id, product_id, product_name, performed_at,
    next_maintenance_date, assigned_user_id, assigned_role,
    secretary_id, technician_id, notes, created_by
  ) values (
    cid, customer_id, p_product_id, product_name_value, p_record_date,
    next_date, coalesce(p_technician_id,p_secretary_id),
    case when p_technician_id is not null then 'technician' else 'secretary' end,
    p_secretary_id, p_technician_id,
    'Geçmiş müşteri kaydı. Adet: ' || coalesce(p_quantity,0)::text,
    uid
  );

  if to_regclass('public.historical_customer_sales') is not null then
    insert into public.historical_customer_sales(
      company_id, customer_id, product_id, product_name, quantity, amount,
      payment_status, payment_due_date, transaction_date, created_by
    ) values (
      cid, customer_id, p_product_id, product_name_value, p_quantity, p_amount,
      p_payment_status, p_payment_due_date, p_record_date, uid
    );
  end if;

  return customer_id;
end;
$$;
grant execute on function public.create_historical_customer_v17(text,text,text,text,text,date,uuid,numeric,numeric,text,date,integer,uuid,uuid) to authenticated;

-- Servis tamamlama: mevcut ticari kaydı oluşturur, ardından bakım tarihini yeniler.
drop function if exists public.complete_service_v5(uuid,text,numeric,numeric,numeric,text,jsonb);
create function public.complete_service_v5(
  p_service_request_id uuid,
  p_work_description text,
  p_service_amount numeric,
  p_extra_amount numeric,
  p_collected_amount numeric,
  p_payment_method text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  user_role text;
  profile_company_id uuid;
  cid uuid;
  request_row public.service_requests%rowtype;
  vehicle_warehouse_id uuid;
  service_id uuid;
  item jsonb;
  v_product_id uuid;
  product_name_value text;
  maintenance_months_value integer;
  qty numeric(12,2);
  unit_price numeric(12,2);
  available_qty numeric(12,2);
  product_total numeric(12,2) := 0;
  service_amount numeric(12,2) := greatest(coalesce(p_service_amount,0),0);
  extra_amount numeric(12,2) := greatest(coalesce(p_extra_amount,0),0);
  total_amount_value numeric(12,2);
  collected numeric(12,2) := greatest(coalesce(p_collected_amount,0),0);
  payment_status_value text;
  secretary_value uuid;
begin
  if uid is null then raise exception 'Oturum bilgisi bulunamadı.'; end if;
  select role, company_id into user_role, profile_company_id from public.profiles where id=uid;
  select * into request_row from public.service_requests where id=p_service_request_id for update;
  if not found then raise exception 'Servis talebi bulunamadı.'; end if;
  cid := coalesce(request_row.company_id, profile_company_id);
  if user_role='technician' and request_row.assigned_technician_id is distinct from uid then raise exception 'Bu servis size atanmadı.'; end if;
  if user_role not in ('technician','manager','admin') then raise exception 'Bu işlemi tamamlamak için yetkiniz bulunmuyor.'; end if;
  if request_row.status='completed' then raise exception 'Bu servis daha önce tamamlanmış.'; end if;
  if request_row.assigned_technician_id is null then raise exception 'Servise teknisyen atanmadı.'; end if;

  select id into vehicle_warehouse_id from public.warehouses
  where company_id=cid and type='vehicle' and assigned_technician_id=request_row.assigned_technician_id and is_active
  order by created_at limit 1;

  for item in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_product_id := nullif(item->>'product_id','')::uuid;
    qty := coalesce((item->>'quantity')::numeric,0);
    unit_price := greatest(coalesce((item->>'unit_price')::numeric,0),0);
    if v_product_id is null or qty<=0 then raise exception 'Ürün ve miktar geçersiz.'; end if;
    select name into product_name_value from public.products where id=v_product_id and company_id=cid and is_active;
    if product_name_value is null then raise exception 'Aktif ürün bulunamadı.'; end if;
    if vehicle_warehouse_id is null then raise exception 'Teknisyen araç deposu bulunamadı.'; end if;
    select quantity into available_qty from public.warehouse_stocks
      where warehouse_id=vehicle_warehouse_id and product_id=v_product_id for update;
    if coalesce(available_qty,0)<qty then raise exception '% için araç stoğu yetersiz.', product_name_value; end if;
    product_total := product_total + qty*unit_price;
  end loop;

  total_amount_value := service_amount + extra_amount + product_total;
  if collected>total_amount_value then raise exception 'Tahsilat toplam tutardan fazla olamaz.'; end if;

  insert into public.services(company_id,service_request_id,customer_id,technician_id,work_description,
    product_total,labor_amount,discount_amount,total_amount,collected_amount,payment_method,completed_at)
  values(cid,request_row.id,request_row.customer_id,request_row.assigned_technician_id,
    coalesce(nullif(btrim(p_work_description),''),coalesce(request_row.description,'Servis tamamlandı')),
    product_total,service_amount+extra_amount,0,total_amount_value,collected,
    coalesce(nullif(p_payment_method,''),'cash'),now()) returning id into service_id;

  select case when p.role='secretary' then request_row.created_by else c.created_by end
    into secretary_value
  from public.customers c
  left join public.profiles p on p.id=request_row.created_by
  where c.id=request_row.customer_id;

  for item in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
    v_product_id := (item->>'product_id')::uuid;
    qty := (item->>'quantity')::numeric;
    unit_price := greatest(coalesce((item->>'unit_price')::numeric,0),0);
    select name, coalesce(maintenance_months,0) into product_name_value, maintenance_months_value
      from public.products where id=v_product_id;

    insert into public.service_items(company_id,service_id,service_request_id,product_id,product_name,quantity,unit_price,line_total)
    values(cid,service_id,request_row.id,v_product_id,product_name_value,qty,unit_price,qty*unit_price);
    insert into public.stock_movements(company_id,product_id,warehouse_id,service_request_id,movement_type,quantity,notes,created_by)
    values(cid,v_product_id,vehicle_warehouse_id,request_row.id,'service',qty,'Servis tamamlamada araç stok çıkışı',uid);

    if maintenance_months_value>0 then
      -- Eski aktif sayacı kapat, yeni tarihi servis tarihinden başlat.
      update public.customer_maintenance_records
      set next_maintenance_date=null
      where company_id=cid and customer_id=request_row.customer_id and product_id=v_product_id
        and next_maintenance_date is not null;
      insert into public.customer_maintenance_records(
        company_id,customer_id,service_id,product_id,product_name,performed_at,next_maintenance_date,
        assigned_user_id,assigned_role,secretary_id,technician_id,notes,created_by
      ) values(
        cid,request_row.customer_id,service_id,v_product_id,product_name_value,current_date,
        (current_date + make_interval(months=>maintenance_months_value))::date,
        request_row.assigned_technician_id,'technician',secretary_value,request_row.assigned_technician_id,
        coalesce(nullif(btrim(p_work_description),''),request_row.description),uid
      );
    end if;
  end loop;

  if collected>0 then
    insert into public.payments(company_id,customer_id,service_request_id,service_id,amount,payment_method,description,payment_date,created_by)
    values(cid,request_row.customer_id,request_row.id,service_id,collected,coalesce(nullif(p_payment_method,''),'cash'),'Servis tahsilatı',now(),uid);
  end if;
  payment_status_value := case when total_amount_value<=0 or collected>=total_amount_value then 'paid' when collected>0 then 'partial' else 'unpaid' end;
  update public.service_requests set company_id=cid,status='completed',price=total_amount_value,collected_amount=collected,
    payment_status=payment_status_value,completion_note=coalesce(nullif(btrim(p_work_description),''),request_row.description),
    completed_at=now(),updated_at=now() where id=request_row.id;
  return service_id;
end;
$$;
grant execute on function public.complete_service_v5(uuid,text,numeric,numeric,numeric,text,jsonb) to authenticated;

-- Tamamlanan servisi sil: geçmişi, tahsilatı ve stoğu geri al.
drop function if exists public.delete_completed_service_v11(uuid);
drop function if exists public.delete_completed_service_v17(uuid);
create function public.delete_completed_service_v17(p_service_request_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  cid uuid := public.current_company_id();
  sid uuid;
  tech uuid;
  wid uuid;
  x record;
begin
  if public.current_user_role() not in ('manager','admin') then raise exception 'Bu işlem için yönetici yetkisi gerekir.'; end if;
  select id,technician_id into sid,tech from public.services
   where service_request_id=p_service_request_id and company_id=cid order by completed_at desc limit 1;
  if sid is null then raise exception 'Tamamlanan servis bulunamadı.'; end if;
  select id into wid from public.warehouses where company_id=cid and type='vehicle' and assigned_technician_id=tech and is_active order by created_at limit 1;
  if wid is not null then
    for x in select product_id,sum(quantity) quantity from public.service_items where service_id=sid and product_id is not null group by product_id loop
      insert into public.warehouse_stocks(company_id,warehouse_id,product_id,quantity) values(cid,wid,x.product_id,x.quantity)
      on conflict(warehouse_id,product_id) do update set quantity=public.warehouse_stocks.quantity+excluded.quantity;
    end loop;
  end if;
  delete from public.customer_maintenance_records where service_id=sid;
  delete from public.payments where service_id=sid or service_request_id=p_service_request_id;
  delete from public.stock_movements where service_request_id=p_service_request_id;
  delete from public.service_items where service_id=sid;
  delete from public.services where id=sid;
  delete from public.service_requests where id=p_service_request_id and company_id=cid;
end;
$$;
grant execute on function public.delete_completed_service_v17(uuid) to authenticated;

-- Sekreter kendi müşterisini; yönetici tümünü görür. Teknisyen atanmış iş/müşteri görür.
drop policy if exists customers_company_access on public.customers;
drop policy if exists customers_select_own on public.customers;
drop policy if exists customers_select_own_technician on public.customers;
drop policy if exists customers_select_v17 on public.customers;
create policy customers_select_v17 on public.customers for select to authenticated using (
  company_id=public.current_company_id() and deleted_at is null and (
    public.current_user_role() in ('manager','admin')
    or (public.current_user_role()='secretary' and created_by=auth.uid())
    or (public.current_user_role()='technician' and exists(
      select 1 from public.service_requests sr where sr.customer_id=customers.id and sr.assigned_technician_id=auth.uid()
    ))
  )
);

drop policy if exists customer_maintenance_company_access on public.customer_maintenance_records;
drop policy if exists customer_maintenance_select on public.customer_maintenance_records;
drop policy if exists customer_maintenance_select_v17 on public.customer_maintenance_records;
create policy customer_maintenance_select_v17 on public.customer_maintenance_records for select to authenticated using (
  company_id=public.current_company_id() and (
    public.current_user_role() in ('manager','admin')
    or (public.current_user_role()='secretary' and secretary_id=auth.uid())
    or (public.current_user_role()='technician' and technician_id=auth.uid())
  )
);

notify pgrst, 'reload schema';
