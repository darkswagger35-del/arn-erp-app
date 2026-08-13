-- ARN ERP V4.0 - Ticari çekirdek
-- Servis tamamlama, araç stoğu, tahsilat, cari ve rapor altyapısı tek migration.

create extension if not exists pgcrypto;

alter table public.payments
  add column if not exists service_id uuid references public.services(id) on delete set null;

create index if not exists payments_customer_date_idx
  on public.payments(customer_id, payment_date desc);
create index if not exists services_customer_date_idx
  on public.services(customer_id, completed_at desc);
create index if not exists service_items_product_idx
  on public.service_items(product_id);

-- Müşteri cari hareketleri: servis borç, tahsilat alacak olarak tek listede.
create or replace view public.customer_account_movements
with (security_invoker = true)
as
select
  s.id,
  s.company_id,
  s.customer_id,
  s.completed_at as movement_date,
  'service'::text as movement_type,
  'Servis'::text as description,
  s.total_amount::numeric(12,2) as debit,
  0::numeric(12,2) as credit,
  s.service_request_id,
  s.id as service_id,
  null::uuid as payment_id
from public.services s
union all
select
  p.id,
  p.company_id,
  p.customer_id,
  p.payment_date as movement_date,
  'payment'::text as movement_type,
  p.description,
  0::numeric(12,2) as debit,
  p.amount::numeric(12,2) as credit,
  p.service_request_id,
  p.service_id,
  p.id as payment_id
from public.payments p
where p.customer_id is not null;

grant select on public.customer_account_movements to authenticated;

-- Servisi tek transaction içinde tamamlar. Herhangi bir adım hata verirse hiçbir kayıt yazılmaz.
create or replace function public.complete_service_v4(
  p_service_request_id uuid,
  p_work_description text,
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
  cid uuid := public.current_company_id();
  uid uuid := auth.uid();
  user_role text := public.current_user_role();
  request_row public.service_requests%rowtype;
  vehicle_warehouse_id uuid;
  service_id uuid;
  item jsonb;
  v_product_id uuid;
  product_name text;
  qty numeric(12,2);
  unit_price numeric(12,2);
  available_qty numeric(12,2);
  product_total numeric(12,2) := 0;
  collected numeric(12,2) := greatest(coalesce(p_collected_amount, 0), 0);
  payment_status_value text;
begin
  if cid is null or uid is null then
    raise exception 'Oturum veya firma bilgisi bulunamadı.';
  end if;

  select * into request_row
  from public.service_requests
  where id = p_service_request_id and company_id = cid
  for update;

  if not found then raise exception 'Servis talebi bulunamadı.'; end if;
  if request_row.status = 'completed' then raise exception 'Bu servis daha önce tamamlanmış.'; end if;
  if user_role = 'technician' and request_row.assigned_technician_id is distinct from uid then
    raise exception 'Bu servis size atanmadı.';
  end if;
  if request_row.assigned_technician_id is null then raise exception 'Servise teknisyen atanmadı.'; end if;
  if btrim(coalesce(p_work_description, '')) = '' then raise exception 'Yapılan işlem açıklaması zorunludur.'; end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then raise exception 'Ürün listesi geçersiz.'; end if;

  perform public.ensure_company_warehouses();
  select id into vehicle_warehouse_id
  from public.warehouses
  where company_id = cid
    and type = 'vehicle'
    and assigned_technician_id = request_row.assigned_technician_id
    and is_active = true
  limit 1;

  if vehicle_warehouse_id is null and jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 0 then
    raise exception 'Teknisyen araç deposu bulunamadı.';
  end if;

  -- Önce tüm ürünleri ve stokları kilitle/validasyon yap.
  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_product_id := nullif(item->>'product_id', '')::uuid;
    qty := coalesce((item->>'quantity')::numeric, 0);
    unit_price := greatest(coalesce((item->>'unit_price')::numeric, 0), 0);
    if v_product_id is null or qty <= 0 then raise exception 'Ürün ve miktar bilgisi geçersiz.'; end if;

    select p.name into product_name
    from public.products p
    where p.id = v_product_id and p.company_id = cid and p.is_active = true;
    if product_name is null then raise exception 'Aktif ürün bulunamadı.'; end if;

    select quantity into available_qty
    from public.warehouse_stocks
    where warehouse_id = vehicle_warehouse_id and product_id = v_product_id
    for update;

    available_qty := coalesce(available_qty, 0);
    if available_qty < qty then
      raise exception '% için araç stoğu yetersiz. Mevcut: %, İstenen: %', product_name, available_qty, qty;
    end if;
    product_total := product_total + (qty * unit_price);
  end loop;

  if collected > product_total then
    raise exception 'Tahsilat toplam tutardan fazla olamaz.';
  end if;

  insert into public.services(
    company_id, service_request_id, customer_id, technician_id,
    work_description, product_total, labor_amount, discount_amount,
    total_amount, collected_amount, payment_method, completed_at
  ) values (
    cid, request_row.id, request_row.customer_id, request_row.assigned_technician_id,
    btrim(p_work_description), product_total, 0, 0,
    product_total, collected, coalesce(nullif(p_payment_method, ''), 'cash'), now()
  ) returning id into service_id;

  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_product_id := (item->>'product_id')::uuid;
    qty := (item->>'quantity')::numeric;
    unit_price := greatest(coalesce((item->>'unit_price')::numeric, 0), 0);
    select name into product_name from public.products where id = v_product_id;

    insert into public.service_items(
      company_id, service_id, service_request_id, product_id,
      product_name, quantity, unit_price, line_total
    ) values (
      cid, service_id, request_row.id, v_product_id,
      product_name, qty, unit_price, qty * unit_price
    );

    insert into public.stock_movements(
      company_id, product_id, warehouse_id, service_request_id,
      movement_type, quantity, notes, created_by
    ) values (
      cid, v_product_id, vehicle_warehouse_id, request_row.id,
      'service', qty, 'Servis tamamlamada otomatik araç stok çıkışı', uid
    );
  end loop;

  if collected > 0 then
    insert into public.payments(
      company_id, customer_id, service_request_id, service_id,
      amount, payment_method, description, payment_date, created_by
    ) values (
      cid, request_row.customer_id, request_row.id, service_id,
      collected, coalesce(nullif(p_payment_method, ''), 'cash'),
      'Servis tahsilatı', now(), uid
    );
  end if;

  payment_status_value := case
    when product_total <= 0 or collected >= product_total then 'paid'
    when collected > 0 then 'partial'
    else 'unpaid'
  end;

  update public.service_requests
  set status = 'completed',
      price = product_total,
      collected_amount = collected,
      payment_status = payment_status_value,
      completion_note = btrim(p_work_description),
      completed_at = now(),
      updated_at = now()
  where id = request_row.id;

  return service_id;
end;
$$;

grant execute on function public.complete_service_v4(uuid, text, numeric, text, jsonb) to authenticated;

-- Dashboard ve raporlar için tek hızlı RPC.
create or replace function public.erp_dashboard_summary(
  p_start timestamptz default date_trunc('day', now()),
  p_end timestamptz default date_trunc('day', now()) + interval '1 day'
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with cid as (select public.current_company_id() id),
  sr as (
    select
      count(*) filter (where status = 'pending')::int pending,
      count(*) filter (where status in ('assigned','in_progress'))::int active,
      count(*) filter (where status = 'completed' and completed_at >= p_start and completed_at < p_end)::int completed_period
    from public.service_requests, cid where company_id = cid.id
  ),
  money as (
    select
      coalesce(sum(total_amount) filter (where completed_at >= p_start and completed_at < p_end),0)::numeric(12,2) revenue_period,
      coalesce(sum(total_amount - collected_amount),0)::numeric(12,2) open_balance
    from public.services, cid where company_id = cid.id
  ),
  pay as (
    select coalesce(sum(amount) filter (where payment_date >= p_start and payment_date < p_end),0)::numeric(12,2) collection_period
    from public.payments, cid where company_id = cid.id
  ),
  cust as (
    select count(*) filter (where is_active)::int active_customers
    from public.customers, cid where company_id = cid.id
  ),
  low as (
    select count(*)::int low_stock
    from public.products p, cid
    where p.company_id = cid.id and p.is_active and p.stock_quantity <= p.critical_stock
  )
  select jsonb_build_object(
    'pending', sr.pending,
    'active', sr.active,
    'completed_period', sr.completed_period,
    'revenue_period', money.revenue_period,
    'collection_period', pay.collection_period,
    'open_balance', money.open_balance,
    'active_customers', cust.active_customers,
    'low_stock', low.low_stock
  ) from sr, money, pay, cust, low;
$$;

grant execute on function public.erp_dashboard_summary(timestamptz, timestamptz) to authenticated;

create or replace function public.erp_top_products(
  p_start timestamptz,
  p_end timestamptz,
  p_limit integer default 10
)
returns table(product_name text, quantity numeric, revenue numeric)
language sql
stable
security definer
set search_path = public
as $$
  select si.product_name,
         sum(si.quantity)::numeric(12,2) quantity,
         sum(si.line_total)::numeric(12,2) revenue
  from public.service_items si
  join public.services s on s.id = si.service_id
  where si.company_id = public.current_company_id()
    and s.completed_at >= p_start and s.completed_at < p_end
  group by si.product_name
  order by quantity desc, revenue desc
  limit greatest(1, least(coalesce(p_limit,10),50));
$$;

grant execute on function public.erp_top_products(timestamptz, timestamptz, integer) to authenticated;
