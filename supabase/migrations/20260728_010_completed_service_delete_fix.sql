-- ARN ERP V14: tamamlanan servis silme fonksiyonundaki hatalı kolon düzeltmesi

DROP FUNCTION IF EXISTS public.delete_completed_service_v11(uuid);

CREATE FUNCTION public.delete_completed_service_v11(p_service_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  uid uuid := auth.uid();
  cid uuid;
  role_name text;
  req public.service_requests%rowtype;
  service_row record;
  vehicle_id uuid;
  item record;
BEGIN
  SELECT company_id, role INTO cid, role_name
  FROM public.profiles
  WHERE id=uid AND is_active=true;

  IF cid IS NULL OR role_name NOT IN ('admin','manager') THEN
    RAISE EXCEPTION 'Bu işlemi yalnızca yönetici yapabilir.';
  END IF;

  SELECT * INTO req
  FROM public.service_requests
  WHERE id=p_service_request_id AND company_id=cid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Servis talebi bulunamadı.';
  END IF;

  IF req.status <> 'completed' THEN
    RAISE EXCEPTION 'Yalnızca tamamlanan servis silinebilir.';
  END IF;

  SELECT id INTO vehicle_id
  FROM public.warehouses
  WHERE company_id=cid
    AND type='vehicle'
    AND assigned_technician_id=req.assigned_technician_id
  ORDER BY created_at NULLS LAST, id
  LIMIT 1;

  -- Kullanılan ürünleri teknisyen araç deposuna geri ekle.
  FOR service_row IN
    SELECT id FROM public.services WHERE service_request_id=req.id
  LOOP
    FOR item IN
      SELECT product_id, quantity
      FROM public.service_items
      WHERE service_id=service_row.id
    LOOP
      IF vehicle_id IS NOT NULL
         AND item.product_id IS NOT NULL
         AND item.quantity > 0 THEN
        INSERT INTO public.stock_movements(
          company_id, product_id, warehouse_id, service_request_id,
          movement_type, quantity, notes, created_by
        ) VALUES (
          cid, item.product_id, vehicle_id, NULL,
          'in', item.quantity,
          'Tamamlanan servis silindi; ürün teknisyen aracına geri eklendi',
          uid
        );
      END IF;
    END LOOP;
  END LOOP;

  DELETE FROM public.payments
  WHERE service_request_id=req.id;

  DELETE FROM public.service_items
  WHERE service_request_id=req.id;

  -- customer_maintenance_records tablosunda service_request_id yoktur.
  -- Bu kayıtlar service_id üzerinden public.services silinince ON DELETE CASCADE ile temizlenir.
  DELETE FROM public.services
  WHERE service_request_id=req.id;

  DELETE FROM public.stock_movements
  WHERE service_request_id=req.id
    AND movement_type='service';

  DELETE FROM public.service_requests
  WHERE id=req.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_completed_service_v11(uuid) TO authenticated;
