-- ARN ERP V4.5: planlama, bakım tarihi ve müşteri portalı
create extension if not exists pgcrypto;

alter table public.service_requests add column if not exists next_maintenance_date timestamptz;
alter table public.service_requests add column if not exists customer_note text;

create table if not exists public.customer_portal_tokens (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  token text not null unique default encode(gen_random_bytes(24),'hex'),
  is_active boolean not null default true,
  expires_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(company_id,customer_id)
);

alter table public.customer_portal_tokens enable row level security;

drop policy if exists "company users manage portal tokens" on public.customer_portal_tokens;
create policy "company users manage portal tokens" on public.customer_portal_tokens
for all to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

create or replace function public.get_customer_portal(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v record; result jsonb;
begin
  select t.*, c.full_name, c.company_name as customer_company_name, co.name as company_name
  into v
  from customer_portal_tokens t
  join customers c on c.id=t.customer_id
  join companies co on co.id=t.company_id
  where t.token=p_token and t.is_active=true and (t.expires_at is null or t.expires_at>now());
  if not found then return '{}'::jsonb; end if;

  select jsonb_build_object(
    'company_name',v.company_name,
    'customer_name',coalesce(nullif(v.customer_company_name,''),v.full_name),
    'balance',coalesce((select sum(case when movement_type='debit' then amount else -amount end) from customer_account_movements where customer_id=v.customer_id),0),
    'services',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'service_type_label',replace(initcap(replace(s.service_type,'_',' ')),'I','İ'),
      'status_label',replace(initcap(replace(s.status,'_',' ')),'I','İ'),
      'price',s.price,'planned_date',s.planned_date,'created_at',s.created_at
    ) order by s.created_at desc) from service_requests s where s.customer_id=v.customer_id limit 50),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(jsonb_build_object('amount',p.amount,'payment_method',p.payment_method,'payment_date',p.payment_date) order by p.payment_date desc) from payments p where p.customer_id=v.customer_id limit 50),'[]'::jsonb)
  ) into result;
  return result;
end $$;

grant execute on function public.get_customer_portal(text) to anon, authenticated;

insert into public.customer_portal_tokens(company_id,customer_id,created_by)
select c.company_id,c.id,auth.uid() from public.customers c
where c.is_active=true
on conflict(company_id,customer_id) do nothing;
