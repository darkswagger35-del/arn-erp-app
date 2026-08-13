-- Milestone 5.5: company settings, storage, and manager-only access
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS contact_person text NULL,
  ADD COLUMN IF NOT EXISTS tax_office text NULL,
  ADD COLUMN IF NOT EXISTS address text NULL,
  ADD COLUMN IF NOT EXISTS logo_url text NULL;

ALTER TABLE public.company_settings
  ADD COLUMN IF NOT EXISTS maintenance_reminder_months integer NULL,
  ADD COLUMN IF NOT EXISTS qr_validation_required boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS customer_signature_required boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS service_photo_required boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS payment_required boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pdf_auto_create boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS whatsapp_service_form_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pdf_show_logo boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS pdf_show_seal boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS pdf_show_signature boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS whatsapp_notifications_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS sms_notifications_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS email_notifications_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'company_settings_maintenance_reminder_months_check'
      AND conrelid = 'public.company_settings'::regclass
  ) THEN
    ALTER TABLE public.company_settings
      ADD CONSTRAINT company_settings_maintenance_reminder_months_check
      CHECK (
        maintenance_reminder_months IS NULL
        OR maintenance_reminder_months IN (3, 6, 12, 24)
      );
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_company_settings_company_id_unique
  ON public.company_settings (company_id);

CREATE INDEX IF NOT EXISTS idx_company_settings_updated_at_desc
  ON public.company_settings (updated_at DESC);

DROP TRIGGER IF EXISTS trg_company_settings_set_updated_at
ON public.company_settings;

CREATE TRIGGER trg_company_settings_set_updated_at
BEFORE UPDATE ON public.company_settings
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT company_id
  FROM public.profiles
  WHERE id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_manager()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT role = 'manager' AND is_active = true
      FROM public.profiles
      WHERE id = auth.uid()
      LIMIT 1
    ),
    false
  );
$$;

REVOKE EXECUTE
ON FUNCTION public.current_user_company_id()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.current_user_company_id()
TO authenticated;

REVOKE EXECUTE
ON FUNCTION public.is_manager()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.is_manager()
TO authenticated;

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS companies_select_own_company
ON public.companies;

CREATE POLICY companies_select_own_company
ON public.companies
FOR SELECT
USING (
  public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND id = public.current_user_company_id()
);

DROP POLICY IF EXISTS companies_update_own_company
ON public.companies;

CREATE POLICY companies_update_own_company
ON public.companies
FOR UPDATE
USING (
  public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND id = public.current_user_company_id()
)
WITH CHECK (
  public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND id = public.current_user_company_id()
);

DROP POLICY IF EXISTS companies_no_insert
ON public.companies;

CREATE POLICY companies_no_insert
ON public.companies
FOR INSERT
WITH CHECK (false);

DROP POLICY IF EXISTS companies_no_delete
ON public.companies;

CREATE POLICY companies_no_delete
ON public.companies
FOR DELETE
USING (false);

DROP POLICY IF EXISTS company_settings_select_own
ON public.company_settings;

CREATE POLICY company_settings_select_own
ON public.company_settings
FOR SELECT
USING (
  public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND company_id = public.current_user_company_id()
);

DROP POLICY IF EXISTS company_settings_insert_own
ON public.company_settings;

CREATE POLICY company_settings_insert_own
ON public.company_settings
FOR INSERT
WITH CHECK (
  public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND company_id = public.current_user_company_id()
);

DROP POLICY IF EXISTS company_settings_update_own
ON public.company_settings;

CREATE POLICY company_settings_update_own
ON public.company_settings
FOR UPDATE
USING (
  public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND company_id = public.current_user_company_id()
)
WITH CHECK (
  public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND company_id = public.current_user_company_id()
);

DROP POLICY IF EXISTS company_settings_no_delete
ON public.company_settings;

CREATE POLICY company_settings_no_delete
ON public.company_settings
FOR DELETE
USING (false);

INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'company-logos',
  'company-logos',
  false,
  2097152,
  ARRAY['image/png', 'image/jpeg']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS company_logos_select_own
ON storage.objects;

CREATE POLICY company_logos_select_own
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'company-logos'
  AND public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND (storage.foldername(name))[1] = public.current_user_company_id()::text
);

DROP POLICY IF EXISTS company_logos_insert_own
ON storage.objects;

CREATE POLICY company_logos_insert_own
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'company-logos'
  AND auth.uid() IS NOT NULL
  AND public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND (storage.foldername(name))[1] = public.current_user_company_id()::text
  AND lower(split_part(name, '.', -1)) IN ('png', 'jpg', 'jpeg')
);

DROP POLICY IF EXISTS company_logos_update_own
ON storage.objects;

CREATE POLICY company_logos_update_own
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'company-logos'
  AND public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND (storage.foldername(name))[1] = public.current_user_company_id()::text
)
WITH CHECK (
  bucket_id = 'company-logos'
  AND public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND (storage.foldername(name))[1] = public.current_user_company_id()::text
  AND lower(split_part(name, '.', -1)) IN ('png', 'jpg', 'jpeg')
);

DROP POLICY IF EXISTS company_logos_delete_own
ON storage.objects;

CREATE POLICY company_logos_delete_own
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'company-logos'
  AND public.is_current_user_active()
  AND (public.is_admin() OR public.is_manager())
  AND (storage.foldername(name))[1] = public.current_user_company_id()::text
);