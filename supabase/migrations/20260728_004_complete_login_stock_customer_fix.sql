-- V7 toplu düzeltme: rol bazlı giriş, panel sayaçları ve silme yetkileri.

DROP FUNCTION IF EXISTS public.erp_current_auth_context();
CREATE FUNCTION public.erp_current_auth_context()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile public.profiles%rowtype;
  v_company public.companies%rowtype;
BEGIN
  SELECT * INTO v_profile FROM public.profiles WHERE id = auth.uid() LIMIT 1;
  IF v_profile.id IS NULL THEN
    RETURN jsonb_build_object('profile', null, 'company', null);
  END IF;
  SELECT * INTO v_company FROM public.companies WHERE id = v_profile.company_id LIMIT 1;
  RETURN jsonb_build_object(
    'profile', to_jsonb(v_profile),
    'company', CASE WHEN v_company.id IS NULL THEN null ELSE to_jsonb(v_company) END
  );
END;
$$;
REVOKE ALL ON FUNCTION public.erp_current_auth_context() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.erp_current_auth_context() TO authenticated;

DROP FUNCTION IF EXISTS public.erp_dashboard_summary(timestamptz, timestamptz);
CREATE FUNCTION public.erp_dashboard_summary(
  p_start timestamptz DEFAULT date_trunc('day', now()),
  p_end timestamptz DEFAULT date_trunc('day', now()) + interval '1 day'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id FROM public.profiles
  WHERE id = auth.uid() AND is_active = true LIMIT 1;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Firma bilgisi bulunamadı'; END IF;
  RETURN jsonb_build_object(
    'pending', (SELECT count(*) FROM public.service_requests WHERE company_id=v_company_id AND status IN ('pending','awaiting_approval')),
    'assigned', (SELECT count(*) FROM public.service_requests WHERE company_id=v_company_id AND status='assigned'),
    'active', (SELECT count(*) FROM public.service_requests WHERE company_id=v_company_id AND status IN ('assigned','in_progress')),
    'completed_period', (SELECT count(*) FROM public.service_requests WHERE company_id=v_company_id AND status='completed' AND coalesce(completed_at,updated_at,created_at)>=p_start AND coalesce(completed_at,updated_at,created_at)<p_end),
    'low_stock', (SELECT count(DISTINCT ws.product_id) FROM public.warehouse_stocks ws JOIN public.products p ON p.id=ws.product_id WHERE ws.company_id=v_company_id AND coalesce(p.is_active,true)=true AND coalesce(p.critical_stock,0)>0 AND ws.quantity<=p.critical_stock),
    'collection_period', coalesce((SELECT sum(amount) FROM public.payments WHERE company_id=v_company_id AND payment_date>=p_start AND payment_date<p_end),0),
    'revenue_period', coalesce((SELECT sum(total_amount) FROM public.services WHERE company_id=v_company_id AND completed_at>=p_start AND completed_at<p_end),0),
    'open_balance', coalesce((SELECT sum(total_amount-collected_amount) FROM public.services WHERE company_id=v_company_id),0),
    'active_customers', (SELECT count(*) FROM public.customers WHERE company_id=v_company_id AND coalesce(is_active,true)=true)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.erp_dashboard_summary(timestamptz,timestamptz) TO authenticated;

-- Yanlış stok hareketini ve varsa iptal karşılığını silip stokları yeniden hesaplar.
DROP FUNCTION IF EXISTS public.delete_stock_movement(uuid);
CREATE FUNCTION public.delete_stock_movement(p_movement_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE v_company_id uuid; v_product_id uuid; v_note text;
BEGIN
  SELECT company_id INTO v_company_id FROM public.profiles WHERE id=auth.uid() AND role IN ('admin','manager') AND is_active=true;
  IF v_company_id IS NULL THEN RAISE EXCEPTION 'Yetkiniz yok'; END IF;
  SELECT product_id, notes INTO v_product_id, v_note FROM public.stock_movements WHERE id=p_movement_id AND company_id=v_company_id;
  IF v_product_id IS NULL THEN RAISE EXCEPTION 'Stok hareketi bulunamadı'; END IF;
  DELETE FROM public.stock_movements
  WHERE company_id=v_company_id AND (
    id=p_movement_id OR notes ILIKE '%'||p_movement_id::text||'%' OR
    (v_note IS NOT NULL AND v_note ILIKE '%İPTAL:%' AND id::text=split_part(v_note,'İPTAL:',2))
  );
  UPDATE public.warehouse_stocks ws SET quantity=coalesce(x.qty,0), updated_at=now()
  FROM (
    SELECT w.id warehouse_id,
      coalesce(sum(CASE WHEN sm.movement_type IN ('in','transfer_in','adjustment') THEN sm.quantity ELSE -sm.quantity END),0) qty
    FROM public.warehouses w LEFT JOIN public.stock_movements sm ON sm.warehouse_id=w.id AND sm.product_id=v_product_id
    WHERE w.company_id=v_company_id GROUP BY w.id
  ) x WHERE ws.warehouse_id=x.warehouse_id AND ws.product_id=v_product_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.delete_stock_movement(uuid) TO authenticated;

-- Yönetici ve sekreterin müşteri kartını pasife alabilmesi.
DROP POLICY IF EXISTS customers_update_company_staff ON public.customers;
CREATE POLICY customers_update_company_staff ON public.customers FOR UPDATE TO authenticated
USING (company_id=(SELECT company_id FROM public.profiles WHERE id=auth.uid()) AND EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role IN ('admin','manager','secretary') AND p.is_active=true))
WITH CHECK (company_id=(SELECT company_id FROM public.profiles WHERE id=auth.uid()));
