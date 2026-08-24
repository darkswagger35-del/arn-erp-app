-- ARN ERP - Dinamik servis formu alanlarının servis bazında değer saklaması
-- Form Tasarımcısı'nda tanımlanan TDS, tank basıncı, tarih ve özel alanlar
-- tekniker tarafından doldurulur ve servis PDF'ine aktarılır.

alter table public.service_requests
  add column if not exists service_form_values jsonb not null default '{}'::jsonb;

comment on column public.service_requests.service_form_values is
  'Servis formu tasarımcısındaki dinamik alanların servis kaydına ait değerleri.';
