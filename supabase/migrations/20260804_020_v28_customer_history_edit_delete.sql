-- ARN ERP V28: müşteri kartındaki geçmiş işlemleri düzenleme/silme

create or replace function public.update_customer_maintenance_record_v28(
  p_record_id uuid,
  p_product_id uuid,
  p_performed_at date,
  p_next_maintenance_date date,
  p_secretary_id uuid,
  p_technician_id uuid,
  p_notes text,
  p_quantity numeric,
  p_amount numeric,
  p_payment_status text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_company uuid;
  v_role text;
  v_record public.customer_maintenance_records%rowtype;
  v_product_name text;
  v_service_item public.service_items%rowtype;
  v_service public.services%rowtype;
  v_request public.service_requests%rowtype;
  v_vehicle uuid;
  v_available numeric;
  v_product_total numeric;
  v_total numeric;
begin
  select company_id, role::text into v_company, v_role
  from public.profiles where id=v_uid and is_active=true;
  if v_company is null or v_role not in ('admin','manager','secretary','technician') then
    raise exception 'Bu işlem için yetkiniz yok.';
  end if;
  if coalesce(p_quantity,0)<=0 or coalesce(p_amount,0)<0 then
    raise exception 'Adet ve tutar bilgisi geçersiz.';
  end if;
  if p_payment_status not in ('paid','debt') then
    raise exception 'Ödeme durumu geçersiz.';
  end if;

  select * into v_record from public.customer_maintenance_records
  where id=p_record_id and company_id=v_company for update;
  if not found then raise exception 'Geçmiş kaydı bulunamadı.'; end if;

  select name into v_product_name from public.products
  where id=p_product_id and company_id=v_company;
  if v_product_name is null then raise exception 'Ürün bulunamadı.'; end if;

  update public.customer_maintenance_records
  set product_id=p_product_id,
      product_name=v_product_name,
      performed_at=p_performed_at,
      next_maintenance_date=p_next_maintenance_date,
      secretary_id=p_secretary_id,
      technician_id=p_technician_id,
      assigned_user_id=coalesce(p_technician_id,p_secretary_id),
      assigned_role=case when p_technician_id is not null then 'technician' else 'secretary' end,
      notes=nullif(btrim(coalesce(p_notes,'')),''),
      updated_at=now()
  where id=p_record_id;

  -- Excel/geçmiş satış kaydı aynı aktarım satırıyla birlikte güncellenir.
  if v_record.import_batch_id is not null and v_record.import_source_row is not null then
    update public.historical_customer_sales
    set product_id=p_product_id,
        product_name=v_product_name,
        quantity=p_quantity,
        amount=p_amount,
        payment_status=p_payment_status,
        payment_due_date=case when p_payment_status='debt' then coalesce(payment_due_date,current_date) else null end,
        transaction_date=p_performed_at
    where company_id=v_company
      and import_batch_id=v_record.import_batch_id
      and import_source_row=v_record.import_source_row;
  end if;

  -- Gerçek tamamlanan servise bağlıysa ürün, stok, tahsilat ve toplamları da düzelt.
  if v_record.service_id is not null then
    select * into v_service from public.services
    where id=v_record.service_id and company_id=v_company for update;

    select * into v_service_item from public.service_items
    where service_id=v_record.service_id
      and (product_id=v_record.product_id or product_name=v_record.product_name)
    order by created_at limit 1 for update;

    if v_service_item.id is not null then
      select * into v_request from public.service_requests
      where id=v_service.service_request_id and company_id=v_company;
      select id into v_vehicle from public.warehouses
      where company_id=v_company and type='vehicle'
        and assigned_technician_id=coalesce(p_technician_id,v_service.technician_id)
        and is_active=true limit 1;

      if v_vehicle is not null then
        update public.warehouse_stocks
        set quantity=quantity+v_service_item.quantity,updated_at=now()
        where company_id=v_company and warehouse_id=v_vehicle
          and product_id=v_service_item.product_id;
        if not found then
          insert into public.warehouse_stocks(company_id,warehouse_id,product_id,quantity)
          values(v_company,v_vehicle,v_service_item.product_id,v_service_item.quantity);
        end if;

        select quantity into v_available from public.warehouse_stocks
        where warehouse_id=v_vehicle and product_id=p_product_id for update;
        if coalesce(v_available,0)<p_quantity then
          raise exception 'Teknisyen araç stoğu yetersiz.';
        end if;
        update public.warehouse_stocks set quantity=quantity-p_quantity,updated_at=now()
        where warehouse_id=v_vehicle and product_id=p_product_id;
      end if;

      delete from public.stock_movements
      where company_id=v_company and service_request_id=v_service.service_request_id
        and movement_type='service' and product_id=v_service_item.product_id;
      if v_vehicle is not null then
        insert into public.stock_movements(company_id,product_id,warehouse_id,service_request_id,movement_type,quantity,notes,created_by)
        values(v_company,p_product_id,v_vehicle,v_service.service_request_id,'service',p_quantity,'Geçmiş servis kaydı düzenlendi',v_uid);
      end if;

      update public.service_items
      set product_id=p_product_id,product_name=v_product_name,quantity=p_quantity,
          unit_price=case when p_quantity=0 then 0 else p_amount/p_quantity end,
          line_total=p_amount
      where id=v_service_item.id;

      select coalesce(sum(line_total),0) into v_product_total
      from public.service_items where service_id=v_service.id;
      v_total := greatest(v_product_total+v_service.labor_amount-v_service.discount_amount,0);
      update public.services
      set technician_id=coalesce(p_technician_id,technician_id),
          work_description=coalesce(nullif(btrim(p_notes),''),work_description),
          product_total=v_product_total,total_amount=v_total,
          collected_amount=case when p_payment_status='paid' then v_total else 0 end,
          completed_at=p_performed_at::timestamptz
      where id=v_service.id;
      update public.service_requests
      set assigned_technician_id=coalesce(p_technician_id,assigned_technician_id),
          completion_note=coalesce(nullif(btrim(p_notes),''),completion_note),
          updated_at=now()
      where id=v_service.service_request_id;

      delete from public.payments where service_id=v_service.id;
      if p_payment_status='paid' and v_total>0 then
        insert into public.payments(company_id,customer_id,service_request_id,service_id,amount,payment_method,description,payment_date,created_by)
        values(v_company,v_service.customer_id,v_service.service_request_id,v_service.id,v_total,v_service.payment_method,'Düzenlenen servis tahsilatı',p_performed_at::timestamptz,v_uid);
      end if;
    end if;
  end if;
end;
$$;

grant execute on function public.update_customer_maintenance_record_v28(uuid,uuid,date,date,uuid,uuid,text,numeric,numeric,text) to authenticated;

create or replace function public.delete_customer_maintenance_record_v28(p_record_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid(); v_company uuid; v_role text;
  v_record public.customer_maintenance_records%rowtype;
begin
  select company_id,role::text into v_company,v_role from public.profiles where id=v_uid and is_active=true;
  if v_company is null or v_role not in ('admin','manager','secretary','technician') then raise exception 'Yetkiniz yok.'; end if;
  select * into v_record from public.customer_maintenance_records where id=p_record_id and company_id=v_company;
  if not found then raise exception 'Geçmiş kaydı bulunamadı.'; end if;

  if v_record.import_batch_id is not null and v_record.import_source_row is not null then
    delete from public.historical_customer_sales where company_id=v_company
      and import_batch_id=v_record.import_batch_id and import_source_row=v_record.import_source_row;
  end if;
  delete from public.customer_maintenance_records where id=p_record_id and company_id=v_company;
end;
$$;
grant execute on function public.delete_customer_maintenance_record_v28(uuid) to authenticated;

create or replace function public.delete_customer_history_transaction_v28(p_record_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid(); v_company uuid; v_role text;
  v_record public.customer_maintenance_records%rowtype;
  v_request_id uuid;
begin
  select company_id,role::text into v_company,v_role from public.profiles where id=v_uid and is_active=true;
  if v_company is null or v_role not in ('admin','manager') then raise exception 'Tüm işlemi yalnızca Admin/Yönetici silebilir.'; end if;
  select * into v_record from public.customer_maintenance_records where id=p_record_id and company_id=v_company;
  if not found then raise exception 'Geçmiş kaydı bulunamadı.'; end if;

  if v_record.service_id is not null then
    select service_request_id into v_request_id from public.services where id=v_record.service_id and company_id=v_company;
    if v_request_id is not null then
      perform public.delete_completed_service_v11(v_request_id);
      return;
    end if;
  end if;

  if v_record.import_batch_id is not null and v_record.import_source_row is not null then
    delete from public.historical_customer_sales where company_id=v_company
      and import_batch_id=v_record.import_batch_id and import_source_row=v_record.import_source_row;
  end if;
  delete from public.customer_maintenance_records where id=p_record_id and company_id=v_company;
end;
$$;
grant execute on function public.delete_customer_history_transaction_v28(uuid) to authenticated;

notify pgrst,'reload schema';
