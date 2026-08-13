CREATE TABLE IF NOT EXISTS public.customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  customer_type text NOT NULL,
  full_name text NOT NULL,
  company_name text NULL,
  phone text NOT NULL,
  alternative_phone text NULL,
  email text NULL,
  city text NULL,
  district text NULL,
  neighborhood text NULL,
  address text NOT NULL,
  latitude numeric NULL,
  longitude numeric NULL,
  maps_url text NULL,
  notes text NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid NULL,
  updated_by uuid NULL,
  created_at timestamptz NULL DEFAULT now(),
  updated_at timestamptz NULL DEFAULT now(),
  CONSTRAINT customers_customer_type_check CHECK (customer_type IN ('individual', 'corporate')),
  CONSTRAINT customers_latitude_check CHECK (latitude IS NULL OR (latitude >= -90 AND latitude <= 90)),
  CONSTRAINT customers_longitude_check CHECK (longitude IS NULL OR (longitude >= -180 AND longitude <= 180)),
  CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT
);

ALTER TABLE public.customers
  ALTER COLUMN customer_type SET DEFAULT 'individual';

CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_company_phone_unique ON public.customers (company_id, phone);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers (company_id);
CREATE INDEX IF NOT EXISTS idx_customers_full_name ON public.customers (full_name);
CREATE INDEX IF NOT EXISTS idx_customers_phone ON public.customers (phone);
CREATE INDEX IF NOT EXISTS idx_customers_city ON public.customers (city);
CREATE INDEX IF NOT EXISTS idx_customers_district ON public.customers (district);
CREATE INDEX IF NOT EXISTS idx_customers_is_active ON public.customers (is_active);

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customers_select_own ON public.customers;
CREATE POLICY customers_select_own
ON public.customers
FOR SELECT
USING (
  public.is_current_user_active() AND (
    public.is_admin() OR public.is_manager() OR public.is_secretary()
  ) AND company_id = public.current_user_company_id()
);

DROP POLICY IF EXISTS customers_select_own_technician ON public.customers;
CREATE POLICY customers_select_own_technician
ON public.customers
FOR SELECT
USING (
  public.is_current_user_active() AND public.is_technician() AND company_id = public.current_user_company_id() AND is_active = true
);

DROP POLICY IF EXISTS customers_insert_own ON public.customers;
CREATE POLICY customers_insert_own
ON public.customers
FOR INSERT
WITH CHECK (
  public.is_current_user_active() AND (
    public.is_admin() OR public.is_manager() OR public.is_secretary()
  ) AND company_id = public.current_user_company_id()
);

DROP POLICY IF EXISTS customers_update_own ON public.customers;
CREATE POLICY customers_update_own
ON public.customers
FOR UPDATE
USING (
  public.is_current_user_active() AND (
    public.is_admin() OR public.is_manager() OR public.is_secretary()
  ) AND company_id = public.current_user_company_id()
)
WITH CHECK (
  public.is_current_user_active() AND (
    public.is_admin() OR public.is_manager() OR public.is_secretary()
  ) AND company_id = public.current_user_company_id()
);

DROP POLICY IF EXISTS customers_no_delete ON public.customers;
CREATE POLICY customers_no_delete
ON public.customers
FOR DELETE
USING (false);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_customers_set_updated_at'
      AND tgrelid = 'public.customers'::regclass
  ) THEN
    CREATE TRIGGER trg_customers_set_updated_at
    BEFORE UPDATE ON public.customers
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;
