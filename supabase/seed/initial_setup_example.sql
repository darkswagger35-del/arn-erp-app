-- Example seed script for initial company and admin profile.
-- This script is intentionally not executed automatically.
-- Replace placeholder values before use.

-- 1. Create the first company
INSERT INTO public.companies (name, legal_name, phone, email, tax_number)
VALUES (
  'YOUR_COMPANY_NAME',
  'YOUR_COMPANY_LEGAL_NAME',
  'YOUR_COMPANY_PHONE',
  'YOUR_COMPANY_EMAIL',
  'YOUR_TAX_NUMBER'
)
ON CONFLICT DO NOTHING;

-- 2. Obtain the UUID of the Supabase Auth user you created in the dashboard.
-- Example placeholder:
-- SELECT 'YOUR_AUTH_USER_UUID'::uuid;

-- 3. Create the first admin profile for that auth user.
-- Replace YOUR_AUTH_USER_UUID with the real UUID.
INSERT INTO public.profiles (id, company_id, full_name, phone, role, is_active)
VALUES (
  'YOUR_AUTH_USER_UUID'::uuid,
  (SELECT id FROM public.companies WHERE name = 'YOUR_COMPANY_NAME' LIMIT 1),
  'Yönetici Adı',
  'YOUR_PHONE',
  'admin',
  true
)
ON CONFLICT (id) DO NOTHING;

-- 4. Create the initial company settings row.
INSERT INTO public.company_settings (company_id, currency_code, locale_code, timezone, maintenance_reminder_days)
VALUES (
  (SELECT id FROM public.companies WHERE name = 'YOUR_COMPANY_NAME' LIMIT 1),
  'TRY',
  'tr-TR',
  'Europe/Istanbul',
  15
)
ON CONFLICT (company_id) DO NOTHING;
