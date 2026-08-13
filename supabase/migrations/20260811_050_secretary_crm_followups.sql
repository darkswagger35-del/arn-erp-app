-- MOTUS secretary CRM / advertisement lead follow-up flow.
-- Keeps first-contact leads separate from active customers until a job is won.

create table if not exists public.secretary_leads (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  secretary_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  full_name text not null,
  phone text not null,
  source text,
  status text not null default 'new' check (status in ('new','tracking','won','closed')),
  outcome_code text,
  note text,
  follow_up_at timestamptz,
  last_contacted_at timestamptz,
  converted_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists secretary_leads_company_secretary_idx
  on public.secretary_leads(company_id, secretary_id, status, follow_up_at);
create index if not exists secretary_leads_phone_idx
  on public.secretary_leads(company_id, phone);

alter table public.secretary_leads enable row level security;

drop policy if exists secretary_leads_select on public.secretary_leads;
create policy secretary_leads_select on public.secretary_leads
for select using (
  company_id = public.current_company_id()
  and (
    public.current_user_role() in ('admin','manager')
    or secretary_id = auth.uid()
  )
);

drop policy if exists secretary_leads_insert on public.secretary_leads;
create policy secretary_leads_insert on public.secretary_leads
for insert with check (
  company_id = public.current_company_id()
  and (
    public.current_user_role() in ('admin','manager')
    or (public.current_user_role() = 'secretary' and secretary_id = auth.uid())
  )
);

drop policy if exists secretary_leads_update on public.secretary_leads;
create policy secretary_leads_update on public.secretary_leads
for update using (
  company_id = public.current_company_id()
  and (
    public.current_user_role() in ('admin','manager')
    or secretary_id = auth.uid()
  )
) with check (
  company_id = public.current_company_id()
  and (
    public.current_user_role() in ('admin','manager')
    or secretary_id = auth.uid()
  )
);

drop policy if exists secretary_leads_delete on public.secretary_leads;
create policy secretary_leads_delete on public.secretary_leads
for delete using (
  company_id = public.current_company_id()
  and public.current_user_role() in ('admin','manager')
);

create or replace function public.secretary_leads_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_secretary_leads_touch on public.secretary_leads;
create trigger trg_secretary_leads_touch
before update on public.secretary_leads
for each row execute function public.secretary_leads_touch_updated_at();

create table if not exists public.secretary_lead_activities (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  lead_id uuid not null references public.secretary_leads(id) on delete cascade,
  secretary_id uuid not null references public.profiles(id) on delete cascade,
  outcome_code text not null,
  note text,
  follow_up_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists secretary_lead_activities_lead_idx on public.secretary_lead_activities(lead_id, created_at desc);
create index if not exists secretary_lead_activities_secretary_idx on public.secretary_lead_activities(secretary_id, created_at desc);
alter table public.secretary_lead_activities enable row level security;

drop policy if exists secretary_lead_activities_select on public.secretary_lead_activities;
create policy secretary_lead_activities_select on public.secretary_lead_activities
for select using (
  company_id = public.current_company_id()
  and (public.current_user_role() in ('admin','manager') or secretary_id = auth.uid())
);

drop policy if exists secretary_lead_activities_insert on public.secretary_lead_activities;
create policy secretary_lead_activities_insert on public.secretary_lead_activities
for insert with check (
  company_id = public.current_company_id()
  and (public.current_user_role() in ('admin','manager') or (public.current_user_role()='secretary' and secretary_id=auth.uid()))
);
