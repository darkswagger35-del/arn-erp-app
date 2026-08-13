-- Milestone 5: extend profile fields and role support for company-scoped user management
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS email text NULL,
  ADD COLUMN IF NOT EXISTS last_sign_in_at timestamptz NULL;

ALTER TABLE public.profiles
  ALTER COLUMN role SET DEFAULT 'secretary';

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('admin', 'manager', 'secretary', 'technician'));

CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT company_id
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT role
  FROM public.profiles
  WHERE id = auth.uid() AND is_active = true
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
    (SELECT role = 'manager' AND is_active = true FROM public.profiles WHERE id = auth.uid() LIMIT 1),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.current_user_company_id() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_company_id() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.current_user_role() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.is_manager() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_manager() TO authenticated;

DROP POLICY IF EXISTS profiles_select_own_profile ON public.profiles;
CREATE POLICY profiles_select_own_profile
ON public.profiles
FOR SELECT
USING (
  public.is_current_user_active() AND (
    id = auth.uid() OR (
      (public.is_admin() OR public.is_manager()) AND company_id = public.current_user_company_id()
    )
  )
);

DROP POLICY IF EXISTS profiles_update_company_members ON public.profiles;
CREATE POLICY profiles_update_company_members
ON public.profiles
FOR UPDATE
USING (
  public.is_current_user_active() AND (public.is_admin() OR public.is_manager()) AND company_id = public.current_user_company_id()
)
WITH CHECK (
  public.is_current_user_active() AND (public.is_admin() OR public.is_manager()) AND company_id = public.current_user_company_id()
);
