-- ARN ERP V24 - Firma genelinde mesaj ve servis formu ayarları

create table if not exists public.company_app_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  on_my_way_template text not null default
    'Merhaba {{musteri}}, ARN Su Arıtma teknik servis ekibiyim. Adresinize geliyorum.',
  appointment_template text not null default
    'Merhaba {{musteri}}, {{tarih}} tarihli servis randevunuz oluşturulmuştur. İşlem: {{servis_turu}}. Teknik personel: {{teknisyen}}.',
  service_completed_template text not null default
    'Merhaba {{musteri}}, servis işleminiz tamamlanmıştır. Tutar: {{tutar}}.',
  service_form_title text not null default 'ARN SU ARITMA SERVİS FORMU',
  service_form_footer text not null default
    'Hizmetimizi tercih ettiğiniz için teşekkür ederiz.',
  show_prices_on_form boolean not null default true,
  show_signature_on_form boolean not null default true,
  show_customer_address_on_form boolean not null default true,
  enabled_service_types text[] not null default array[
    'new_installation','filter_change','maintenance','fault','membrane',
    'external_filter','relocation','removal','other'
  ]::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.company_app_settings enable row level security;

-- Eski politika isimleri varsa temizle.
drop policy if exists company_app_settings_select on public.company_app_settings;
drop policy if exists company_app_settings_manage on public.company_app_settings;

create policy company_app_settings_select
on public.company_app_settings
for select
to authenticated
using (company_id = public.current_company_id());

create policy company_app_settings_manage
on public.company_app_settings
for all
to authenticated
using (
  company_id = public.current_company_id()
  and public.current_user_role()::text in ('admin', 'manager')
)
with check (
  company_id = public.current_company_id()
  and public.current_user_role()::text in ('admin', 'manager')
);

grant select on public.company_app_settings to authenticated;
grant insert, update, delete on public.company_app_settings to authenticated;

insert into public.company_app_settings(company_id)
select c.id
from public.companies c
where not exists (
  select 1
  from public.company_app_settings s
  where s.company_id = c.id
);

notify pgrst, 'reload schema';
