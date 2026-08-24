-- ARN ERP V7 - DİNAMİK SERVİS FORMU
-- Supabase > SQL Editor ekranında bir kez çalıştırın.

alter table public.service_requests
  add column if not exists service_form_values jsonb not null default '{}'::jsonb;

comment on column public.service_requests.service_form_values is
  'Servis formu tasarımcısındaki dinamik alanların servis kaydına ait değerleri.';
