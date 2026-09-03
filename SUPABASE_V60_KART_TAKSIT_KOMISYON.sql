-- MOTUS V60 - Kredi kartı taksit / komisyon / net tahsilat
-- Supabase SQL Editor'da bir kez çalıştırın.

alter table public.payments
  add column if not exists card_installments integer not null default 1,
  add column if not exists card_commission_rate numeric(8,4) not null default 0,
  add column if not exists card_commission_amount numeric(14,2) not null default 0,
  add column if not exists net_amount numeric(14,2);

update public.payments
set net_amount = amount - coalesce(card_commission_amount, 0)
where net_amount is null;

alter table public.payments
  alter column net_amount set default 0;

comment on column public.payments.card_installments is 'Kart tahsilatında taksit adedi; tek çekim = 1';
comment on column public.payments.card_commission_rate is 'POS/banka komisyon oranı yüzde';
comment on column public.payments.card_commission_amount is 'Tahsilattan düşülen kart komisyonu';
comment on column public.payments.net_amount is 'Komisyon sonrası net tahsilat';
