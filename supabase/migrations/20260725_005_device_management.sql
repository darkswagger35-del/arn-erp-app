CREATE TABLE IF NOT EXISTS public.customer_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
  brand text NULL,
  model text NULL,
  device_type text NOT NULL,
  pump_type text NOT NULL,
  serial_number text NULL,
  qr_code text NULL,
  membrane_type text NULL,
  installation_date date NULL,
  last_maintenance_date date NULL,
  next_maintenance_date date NULL,
  description text NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz NULL
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'customer_devices_device_type_check'
      AND conrelid = 'public.customer_devices'::regclass
  ) THEN
    ALTER TABLE public.customer_devices
      ADD CONSTRAINT customer_devices_device_type_check
      CHECK (device_type IN ('reverse_osmosis', 'under_counter', 'counter_top', 'industrial', 'softener', 'other'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'customer_devices_pump_type_check'
      AND conrelid = 'public.customer_devices'::regclass
  ) THEN
    ALTER TABLE public.customer_devices
      ADD CONSTRAINT customer_devices_pump_type_check
      CHECK (pump_type IN ('pumped', 'non_pumped', 'unknown'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_customer_devices_company_id
  ON public.customer_devices (company_id);

CREATE INDEX IF NOT EXISTS idx_customer_devices_customer_id
  ON public.customer_devices (customer_id);

CREATE INDEX IF NOT EXISTS idx_customer_devices_serial_number
  ON public.customer_devices (serial_number);

CREATE INDEX IF NOT EXISTS idx_customer_devices_qr_code
  ON public.customer_devices (qr_code);

CREATE INDEX IF NOT EXISTS idx_customer_devices_next_maintenance_date
  ON public.customer_devices (next_maintenance_date);

CREATE INDEX IF NOT EXISTS idx_customer_devices_deleted_at
  ON public.customer_devices (deleted_at);

CREATE INDEX IF NOT EXISTS idx_customer_devices_is_active
  ON public.customer_devices (is_active);

CREATE UNIQUE INDEX IF NOT EXISTS idx_customer_devices_company_qr_normalized_unique
  ON public.customer_devices (company_id, lower(btrim(qr_code)))
  WHERE qr_code IS NOT NULL AND btrim(qr_code) <> '';

ALTER TABLE public.customer_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_devices_select_own ON public.customer_devices;
CREATE POLICY customer_devices_select_own
ON public.customer_devices
FOR SELECT
USING (
  public.is_current_user_active() AND (
    public.is_admin() OR public.is_manager() OR public.is_secretary()
  ) AND company_id = public.current_user_company_id() AND deleted_at IS NULL
);

DROP POLICY IF EXISTS customer_devices_select_own_technician ON public.customer_devices;
CREATE POLICY customer_devices_select_own_technician
ON public.customer_devices
FOR SELECT
USING (
  public.is_current_user_active() AND public.is_technician() AND company_id = public.current_user_company_id() AND is_active = true AND deleted_at IS NULL
);

DROP POLICY IF EXISTS customer_devices_insert_own ON public.customer_devices;
CREATE POLICY customer_devices_insert_own
ON public.customer_devices
FOR INSERT
WITH CHECK (
  public.is_current_user_active() AND (
    public.is_admin() OR public.is_manager() OR public.is_secretary()
  ) AND company_id = public.current_user_company_id() AND EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = customer_id
      AND c.company_id = public.current_user_company_id()
  )
);

DROP POLICY IF EXISTS customer_devices_update_own ON public.customer_devices;
CREATE POLICY customer_devices_update_own
ON public.customer_devices
FOR UPDATE
USING (
  public.is_current_user_active() AND (
    public.is_admin() OR public.is_manager() OR public.is_secretary()
  ) AND company_id = public.current_user_company_id() AND deleted_at IS NULL
)
WITH CHECK (
  public.is_current_user_active() AND (
    public.is_admin() OR public.is_manager() OR public.is_secretary()
  ) AND company_id = public.current_user_company_id() AND EXISTS (
    SELECT 1
    FROM public.customers c
    WHERE c.id = customer_id
      AND c.company_id = public.current_user_company_id()
  )
);

DROP POLICY IF EXISTS customer_devices_no_delete ON public.customer_devices;
CREATE POLICY customer_devices_no_delete
ON public.customer_devices
FOR DELETE
USING (false);

CREATE OR REPLACE FUNCTION public.customer_devices_sanitize_and_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.serial_number := NULLIF(btrim(NEW.serial_number), '');
  NEW.qr_code := NULLIF(btrim(NEW.qr_code), '');

  IF TG_OP = 'INSERT' THEN
    IF NEW.company_id IS DISTINCT FROM public.current_user_company_id() THEN
      RAISE EXCEPTION 'Bu işlem için yetkiniz bulunmuyor.' USING ERRCODE = '42501';
    END IF;

    IF public.is_admin() OR public.is_manager() THEN
      RETURN NEW;
    END IF;

    IF public.is_secretary() THEN
      NEW.is_active := true;
      NEW.deleted_at := NULL;
      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Bu işlem için yetkiniz bulunmuyor.' USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
      RAISE EXCEPTION 'Bu işlem için yetkiniz bulunmuyor.' USING ERRCODE = '42501';
    END IF;

    IF public.is_admin() OR public.is_manager() THEN
      RETURN NEW;
    END IF;

    IF public.is_secretary() THEN
      IF NEW.id IS DISTINCT FROM OLD.id
         OR NEW.created_at IS DISTINCT FROM OLD.created_at
         OR NEW.company_id IS DISTINCT FROM OLD.company_id
         OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
         OR NEW.is_active IS DISTINCT FROM OLD.is_active THEN
        RAISE EXCEPTION 'Bu işlem için yetkiniz bulunmuyor.' USING ERRCODE = '42501';
      END IF;

      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Bu işlem için yetkiniz bulunmuyor.' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_customer_devices_sanitize_and_guard ON public.customer_devices;
CREATE TRIGGER trg_customer_devices_sanitize_and_guard
BEFORE INSERT OR UPDATE ON public.customer_devices
FOR EACH ROW
EXECUTE FUNCTION public.customer_devices_sanitize_and_guard();

DROP TRIGGER IF EXISTS trg_customer_devices_set_updated_at
ON public.customer_devices;

CREATE TRIGGER trg_customer_devices_set_updated_at
BEFORE UPDATE ON public.customer_devices
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
