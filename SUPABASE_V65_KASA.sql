-- MOTUS V65 - Kasa / tekniker nakitleri / ana kasa / giderler
-- Kredi kartı tahsilatları bu kasa hesabına DAHİL DEĞİLDİR.

create table if not exists public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  movement_type text not null check (movement_type in ('transfer_to_main','expense')),
  from_profile_id uuid references public.profiles(id) on delete set null,
  amount numeric(14,2) not null check (amount > 0),
  note text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists cash_movements_company_created_idx
  on public.cash_movements(company_id, created_at desc);
create index if not exists cash_movements_from_profile_idx
  on public.cash_movements(from_profile_id, movement_type);

alter table public.cash_movements enable row level security;

drop policy if exists cash_movements_select_company on public.cash_movements;
create policy cash_movements_select_company on public.cash_movements
for select to authenticated
using (
  company_id = (select p.company_id from public.profiles p where p.id = auth.uid())
);

drop policy if exists cash_movements_manage_admin on public.cash_movements;
create policy cash_movements_manage_admin on public.cash_movements
for all to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.company_id = cash_movements.company_id
      and p.role in ('admin','manager')
      and p.is_active = true
  )
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.company_id = cash_movements.company_id
      and p.role in ('admin','manager')
      and p.is_active = true
  )
);

create or replace function public.cash_register_summary_v65()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_company uuid;
  v_role text;
  v_main_received numeric := 0;
  v_transfers numeric := 0;
  v_expenses numeric := 0;
  v_holders jsonb := '[]'::jsonb;
  v_receipts jsonb := '[]'::jsonb;
  v_expense_rows jsonb := '[]'::jsonb;
begin
  select company_id, role into v_company, v_role
  from public.profiles
  where id = v_uid and is_active = true and deleted_at is null;

  if v_company is null then
    raise exception 'Oturum/şirket bilgisi bulunamadı.';
  end if;

  select coalesce(sum(pay.amount),0) into v_main_received
  from public.payments pay
  join public.profiles pr on pr.id = pay.created_by
  where pay.company_id = v_company
    and pay.payment_method = 'cash'
    and pr.role in ('admin','manager');

  select coalesce(sum(amount),0) into v_transfers
  from public.cash_movements
  where company_id = v_company and movement_type = 'transfer_to_main';

  select coalesce(sum(amount),0) into v_expenses
  from public.cash_movements
  where company_id = v_company and movement_type = 'expense';

  select coalesce(jsonb_agg(x order by (x->>'full_name')), '[]'::jsonb)
  into v_holders
  from (
    select jsonb_build_object(
      'profile_id', pr.id,
      'full_name', pr.full_name,
      'role', pr.role,
      'received', coalesce((
        select sum(pay.amount) from public.payments pay
        where pay.company_id=v_company and pay.payment_method='cash' and pay.created_by=pr.id
      ),0),
      'transferred', coalesce((
        select sum(cm.amount) from public.cash_movements cm
        where cm.company_id=v_company and cm.movement_type='transfer_to_main' and cm.from_profile_id=pr.id
      ),0),
      'balance', greatest(0,
        coalesce((select sum(pay.amount) from public.payments pay
          where pay.company_id=v_company and pay.payment_method='cash' and pay.created_by=pr.id),0)
        - coalesce((select sum(cm.amount) from public.cash_movements cm
          where cm.company_id=v_company and cm.movement_type='transfer_to_main' and cm.from_profile_id=pr.id),0)
      )
    ) x
    from public.profiles pr
    where pr.company_id=v_company
      and pr.deleted_at is null
      and pr.is_active=true
      and pr.role not in ('admin','manager')
      and (
        exists(select 1 from public.payments pay where pay.company_id=v_company and pay.payment_method='cash' and pay.created_by=pr.id)
        or exists(select 1 from public.cash_movements cm where cm.company_id=v_company and cm.from_profile_id=pr.id)
      )
  ) q;

  select coalesce(jsonb_agg(x order by (x->>'payment_date') desc), '[]'::jsonb)
  into v_receipts
  from (
    select jsonb_build_object(
      'id', pay.id,
      'amount', pay.amount,
      'payment_date', pay.payment_date,
      'customer_id', pay.customer_id,
      'customer_name', coalesce(c.full_name,c.company_name,'Müşteri'),
      'receiver_id', pay.created_by,
      'receiver_name', coalesce(pr.full_name,'-'),
      'receiver_role', coalesce(pr.role,''),
      'description', coalesce(pay.description,'Nakit tahsilat')
    ) x
    from public.payments pay
    left join public.customers c on c.id=pay.customer_id
    left join public.profiles pr on pr.id=pay.created_by
    where pay.company_id=v_company and pay.payment_method='cash'
    order by pay.payment_date desc
    limit 200
  ) q;

  select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb)
  into v_expense_rows
  from (
    select jsonb_build_object(
      'id', cm.id,
      'amount', cm.amount,
      'note', coalesce(cm.note,'Gider'),
      'created_at', cm.created_at,
      'created_by_name', coalesce(pr.full_name,'-')
    ) x
    from public.cash_movements cm
    left join public.profiles pr on pr.id=cm.created_by
    where cm.company_id=v_company and cm.movement_type='expense'
    order by cm.created_at desc
    limit 100
  ) q;

  -- Tekniker kendi kasasını görebilir; yönetici herkesin kasasını görür.
  if v_role = 'technician' then
    v_holders := coalesce((
      select jsonb_agg(e)
      from jsonb_array_elements(v_holders) e
      where e->>'profile_id' = v_uid::text
    ), '[]'::jsonb);
    v_receipts := coalesce((
      select jsonb_agg(e)
      from jsonb_array_elements(v_receipts) e
      where e->>'receiver_id' = v_uid::text
    ), '[]'::jsonb);
    v_expense_rows := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'main_cash', greatest(0, v_main_received + v_transfers - v_expenses),
    'main_direct_cash', v_main_received,
    'transfers_to_main', v_transfers,
    'expenses_total', v_expenses,
    'holders', v_holders,
    'cash_receipts', v_receipts,
    'expenses', v_expense_rows
  );
end;
$$;

grant execute on function public.cash_register_summary_v65() to authenticated;

create or replace function public.cash_transfer_to_main_v65(
  p_from_profile_id uuid,
  p_amount numeric,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_company uuid;
  v_role text;
  v_received numeric := 0;
  v_transferred numeric := 0;
begin
  select company_id, role into v_company, v_role
  from public.profiles where id=v_uid and is_active=true and deleted_at is null;
  if v_company is null or v_role not in ('admin','manager') then
    raise exception 'Bu işlem için yönetici yetkisi gerekir.';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Tutar sıfırdan büyük olmalıdır.'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_from_profile_id and p.company_id=v_company and p.deleted_at is null) then
    raise exception 'Personel bulunamadı.';
  end if;

  select coalesce(sum(amount),0) into v_received from public.payments
    where company_id=v_company and payment_method='cash' and created_by=p_from_profile_id;
  select coalesce(sum(amount),0) into v_transferred from public.cash_movements
    where company_id=v_company and movement_type='transfer_to_main' and from_profile_id=p_from_profile_id;

  if p_amount > (v_received-v_transferred) then raise exception 'Personel kasasında yeterli nakit yok.'; end if;

  insert into public.cash_movements(company_id,movement_type,from_profile_id,amount,note,created_by)
  values(v_company,'transfer_to_main',p_from_profile_id,p_amount,nullif(btrim(p_note),''),v_uid);
end;
$$;
grant execute on function public.cash_transfer_to_main_v65(uuid,numeric,text) to authenticated;

create or replace function public.cash_add_expense_v65(p_amount numeric, p_note text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_company uuid;
  v_role text;
  v_main numeric := 0;
begin
  select company_id, role into v_company, v_role
  from public.profiles where id=v_uid and is_active=true and deleted_at is null;
  if v_company is null or v_role not in ('admin','manager') then
    raise exception 'Bu işlem için yönetici yetkisi gerekir.';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Tutar sıfırdan büyük olmalıdır.'; end if;

  select
    coalesce((select sum(pay.amount) from public.payments pay join public.profiles pr on pr.id=pay.created_by
      where pay.company_id=v_company and pay.payment_method='cash' and pr.role in ('admin','manager')),0)
    + coalesce((select sum(amount) from public.cash_movements where company_id=v_company and movement_type='transfer_to_main'),0)
    - coalesce((select sum(amount) from public.cash_movements where company_id=v_company and movement_type='expense'),0)
  into v_main;

  if p_amount > v_main then raise exception 'Ana kasada yeterli nakit yok.'; end if;
  insert into public.cash_movements(company_id,movement_type,amount,note,created_by)
  values(v_company,'expense',p_amount,coalesce(nullif(btrim(p_note),''),'Gider'),v_uid);
end;
$$;
grant execute on function public.cash_add_expense_v65(numeric,text) to authenticated;
