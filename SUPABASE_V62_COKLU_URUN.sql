-- MOTUS V62 - Servis talebinde birden fazla planlanan ürün
-- Supabase > SQL Editor > New query > Run

alter table public.service_requests
  add column if not exists planned_items jsonb not null default '[]'::jsonb;

comment on column public.service_requests.planned_items is
  'Sekreter/yönetici servis talebi açarken seçilen birden fazla ürün satırı. Her satır product_id, product_name, quantity, unit_price, line_total içerir.';

-- Eski tek ürünlü kayıtları yeni yapıya geri doldur.
update public.service_requests
set planned_items = jsonb_build_array(
  jsonb_build_object(
    'product_id', planned_product_id,
    'product_name', coalesce(planned_product_name, ''),
    'quantity', coalesce(planned_quantity, 0),
    'unit_price', coalesce(planned_unit_price, 0),
    'line_total', coalesce(price, 0)
  )
)
where coalesce(jsonb_array_length(planned_items), 0) = 0
  and planned_product_id is not null
  and coalesce(planned_quantity, 0) > 0;
