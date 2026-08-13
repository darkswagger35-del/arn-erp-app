-- ARN ERP v5 final: safe stock movement reversal and permissions
create or replace function public.reverse_stock_movement(p_movement_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_original public.stock_movements%rowtype;
  v_company uuid;
  v_new_id uuid;
  v_reverse_type text;
begin
  v_company := public.current_company_id();
  select * into v_original
  from public.stock_movements
  where id = p_movement_id and company_id = v_company
  for update;
  if not found then raise exception 'Stok hareketi bulunamadı'; end if;
  if coalesce(v_original.notes, '') like 'İPTAL:%' then raise exception 'Bu hareket daha önce iptal edilmiş'; end if;
  if exists(select 1 from public.stock_movements where notes = 'İPTAL:' || p_movement_id::text) then
    raise exception 'Bu hareket daha önce iptal edilmiş';
  end if;
  v_reverse_type := case
    when v_original.movement_type in ('out','service','transfer_out') then 'in'
    else 'out'
  end;
  insert into public.stock_movements(company_id, warehouse_id, product_id, movement_type, quantity, notes, created_by)
  values(v_company, v_original.warehouse_id, v_original.product_id, v_reverse_type, v_original.quantity,
         'İPTAL:' || p_movement_id::text, auth.uid()) returning id into v_new_id;
  update public.stock_movements
  set notes = concat_ws(' | ', nullif(notes,''), 'İptal edildi: ' || v_new_id::text)
  where id = p_movement_id;
  return v_new_id;
end;
$$;
grant execute on function public.reverse_stock_movement(uuid) to authenticated;
