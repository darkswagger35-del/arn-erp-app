-- MOTUS V66 - Detaylı Kasa / Gider Yönetimi
-- Ön koşul: SUPABASE_V65_KASA.sql daha önce çalıştırılmış olmalıdır.
-- Kredi kartı tahsilatları kasa bakiyesine dahil edilmez.

alter table public.cash_movements
  add column if not exists expense_category text,
  add column if not exists beneficiary_profile_id uuid references public.profiles(id) on delete set null,
  add column if not exists payment_source text,
  add column if not exists source_profile_id uuid references public.profiles(id) on delete set null,
  add column if not exists document_no text,
  add column if not exists expense_at timestamptz;

update public.cash_movements
set expense_category = coalesce(expense_category, 'other'),
    payment_source = coalesce(payment_source, 'main_cash'),
    expense_at = coalesce(expense_at, created_at)
where movement_type = 'expense';

create index if not exists cash_movements_expense_at_idx
  on public.cash_movements(company_id, expense_at desc)
  where movement_type='expense';
create index if not exists cash_movements_beneficiary_idx
  on public.cash_movements(beneficiary_profile_id)
  where movement_type='expense';
create index if not exists cash_movements_source_profile_idx
  on public.cash_movements(source_profile_id)
  where movement_type='expense';

create or replace function public.cash_expense_staff_v66()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_company uuid;
begin
  select company_id into v_company
  from public.profiles
  where id=v_uid and is_active=true and deleted_at is null;
  if v_company is null then raise exception 'Oturum/şirket bilgisi bulunamadı.'; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id,
      'full_name', p.full_name,
      'role', p.role
    ) order by p.full_name)
    from public.profiles p
    where p.company_id=v_company and p.is_active=true and p.deleted_at is null
  ), '[]'::jsonb);
end;
$$;
grant execute on function public.cash_expense_staff_v66() to authenticated;

create or replace function public.cash_register_summary_v66()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_company uuid;
  v_role text;
  v_main_direct numeric := 0;
  v_transfers numeric := 0;
  v_main_expenses numeric := 0;
  v_all_expenses numeric := 0;
  v_holders jsonb := '[]'::jsonb;
  v_receipts jsonb := '[]'::jsonb;
  v_expense_rows jsonb := '[]'::jsonb;
  v_transfer_rows jsonb := '[]'::jsonb;
begin
  select company_id, role into v_company, v_role
  from public.profiles
  where id=v_uid and is_active=true and deleted_at is null;

  if v_company is null then raise exception 'Oturum/şirket bilgisi bulunamadı.'; end if;

  select coalesce(sum(pay.amount),0) into v_main_direct
  from public.payments pay
  join public.profiles pr on pr.id=pay.created_by
  where pay.company_id=v_company and pay.payment_method='cash'
    and pr.role in ('admin','manager');

  select coalesce(sum(amount),0) into v_transfers
  from public.cash_movements
  where company_id=v_company and movement_type='transfer_to_main';

  select coalesce(sum(amount),0) into v_main_expenses
  from public.cash_movements
  where company_id=v_company and movement_type='expense'
    and coalesce(payment_source,'main_cash')='main_cash';

  select coalesce(sum(amount),0) into v_all_expenses
  from public.cash_movements
  where company_id=v_company and movement_type='expense';

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
      'expenses', coalesce((
        select sum(cm.amount) from public.cash_movements cm
        where cm.company_id=v_company and cm.movement_type='expense'
          and cm.payment_source='personnel_cash' and cm.source_profile_id=pr.id
      ),0),
      'balance', greatest(0,
        coalesce((select sum(pay.amount) from public.payments pay
          where pay.company_id=v_company and pay.payment_method='cash' and pay.created_by=pr.id),0)
        - coalesce((select sum(cm.amount) from public.cash_movements cm
          where cm.company_id=v_company and cm.movement_type='transfer_to_main' and cm.from_profile_id=pr.id),0)
        - coalesce((select sum(cm.amount) from public.cash_movements cm
          where cm.company_id=v_company and cm.movement_type='expense'
            and cm.payment_source='personnel_cash' and cm.source_profile_id=pr.id),0)
      )
    ) x
    from public.profiles pr
    where pr.company_id=v_company and pr.deleted_at is null and pr.is_active=true
      and pr.role not in ('admin','manager')
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
    limit 500
  ) q;

  select coalesce(jsonb_agg(x order by (x->>'expense_at') desc), '[]'::jsonb)
  into v_expense_rows
  from (
    select jsonb_build_object(
      'id', cm.id,
      'amount', cm.amount,
      'category', coalesce(cm.expense_category,'other'),
      'beneficiary_profile_id', cm.beneficiary_profile_id,
      'beneficiary_name', coalesce(bp.full_name,'-'),
      'beneficiary_role', coalesce(bp.role,''),
      'payment_source', coalesce(cm.payment_source,'main_cash'),
      'source_profile_id', cm.source_profile_id,
      'source_profile_name', coalesce(sp.full_name,'-'),
      'note', coalesce(cm.note,''),
      'document_no', coalesce(cm.document_no,''),
      'expense_at', coalesce(cm.expense_at,cm.created_at),
      'created_at', cm.created_at,
      'created_by_name', coalesce(cr.full_name,'-')
    ) x
    from public.cash_movements cm
    left join public.profiles bp on bp.id=cm.beneficiary_profile_id
    left join public.profiles sp on sp.id=cm.source_profile_id
    left join public.profiles cr on cr.id=cm.created_by
    where cm.company_id=v_company and cm.movement_type='expense'
    order by coalesce(cm.expense_at,cm.created_at) desc
    limit 500
  ) q;

  select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb)
  into v_transfer_rows
  from (
    select jsonb_build_object(
      'id', cm.id,
      'amount', cm.amount,
      'from_profile_id', cm.from_profile_id,
      'from_profile_name', coalesce(fp.full_name,'-'),
      'note', coalesce(cm.note,''),
      'created_at', cm.created_at,
      'created_by_name', coalesce(cr.full_name,'-')
    ) x
    from public.cash_movements cm
    left join public.profiles fp on fp.id=cm.from_profile_id
    left join public.profiles cr on cr.id=cm.created_by
    where cm.company_id=v_company and cm.movement_type='transfer_to_main'
    order by cm.created_at desc
    limit 200
  ) q;

  if v_role = 'technician' then
    v_holders := coalesce((select jsonb_agg(e) from jsonb_array_elements(v_holders) e where e->>'profile_id'=v_uid::text),'[]'::jsonb);
    v_receipts := coalesce((select jsonb_agg(e) from jsonb_array_elements(v_receipts) e where e->>'receiver_id'=v_uid::text),'[]'::jsonb);
    v_expense_rows := coalesce((select jsonb_agg(e) from jsonb_array_elements(v_expense_rows) e where e->>'source_profile_id'=v_uid::text),'[]'::jsonb);
    v_transfer_rows := coalesce((select jsonb_agg(e) from jsonb_array_elements(v_transfer_rows) e where e->>'from_profile_id'=v_uid::text),'[]'::jsonb);
  end if;

  return jsonb_build_object(
    'main_cash', greatest(0,v_main_direct+v_transfers-v_main_expenses),
    'main_direct_cash', v_main_direct,
    'transfers_to_main', v_transfers,
    'expenses_total', v_all_expenses,
    'main_expenses_total', v_main_expenses,
    'holders', v_holders,
    'cash_receipts', v_receipts,
    'expenses', v_expense_rows,
    'transfers', v_transfer_rows
  );
end;
$$;
grant execute on function public.cash_register_summary_v66() to authenticated;

create or replace function public.cash_transfer_to_main_v66(
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
  v_person_expenses numeric := 0;
begin
  select company_id,role into v_company,v_role from public.profiles
  where id=v_uid and is_active=true and deleted_at is null;
  if v_company is null or v_role not in ('admin','manager') then raise exception 'Bu işlem için yönetici yetkisi gerekir.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Tutar sıfırdan büyük olmalıdır.'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_from_profile_id and p.company_id=v_company and p.deleted_at is null) then raise exception 'Personel bulunamadı.'; end if;

  select coalesce(sum(amount),0) into v_received from public.payments
   where company_id=v_company and payment_method='cash' and created_by=p_from_profile_id;
  select coalesce(sum(amount),0) into v_transferred from public.cash_movements
   where company_id=v_company and movement_type='transfer_to_main' and from_profile_id=p_from_profile_id;
  select coalesce(sum(amount),0) into v_person_expenses from public.cash_movements
   where company_id=v_company and movement_type='expense' and payment_source='personnel_cash' and source_profile_id=p_from_profile_id;

  if p_amount>(v_received-v_transferred-v_person_expenses) then raise exception 'Personel kasasında yeterli nakit yok.'; end if;

  insert into public.cash_movements(company_id,movement_type,from_profile_id,amount,note,created_by)
  values(v_company,'transfer_to_main',p_from_profile_id,p_amount,nullif(btrim(p_note),''),v_uid);
end;
$$;
grant execute on function public.cash_transfer_to_main_v66(uuid,numeric,text) to authenticated;

create or replace function public.cash_add_expense_v66(
  p_category text,
  p_amount numeric,
  p_payment_source text,
  p_beneficiary_profile_id uuid default null,
  p_source_profile_id uuid default null,
  p_note text default null,
  p_document_no text default null,
  p_expense_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid(); v_company uuid; v_role text; v_available numeric := 0;
begin
  select company_id,role into v_company,v_role from public.profiles
  where id=v_uid and is_active=true and deleted_at is null;
  if v_company is null or v_role not in ('admin','manager') then raise exception 'Bu işlem için yönetici yetkisi gerekir.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Tutar sıfırdan büyük olmalıdır.'; end if;
  if coalesce(p_payment_source,'') not in ('main_cash','personnel_cash') then raise exception 'Geçersiz ödeme kaynağı.'; end if;
  if p_beneficiary_profile_id is not null and not exists(select 1 from public.profiles p where p.id=p_beneficiary_profile_id and p.company_id=v_company) then raise exception 'Gider kişisi bulunamadı.'; end if;

  if p_payment_source='main_cash' then
    select greatest(0,
      coalesce((select sum(pay.amount) from public.payments pay join public.profiles pr on pr.id=pay.created_by where pay.company_id=v_company and pay.payment_method='cash' and pr.role in ('admin','manager')),0)
      + coalesce((select sum(amount) from public.cash_movements where company_id=v_company and movement_type='transfer_to_main'),0)
      - coalesce((select sum(amount) from public.cash_movements where company_id=v_company and movement_type='expense' and coalesce(payment_source,'main_cash')='main_cash'),0)
    ) into v_available;
  else
    if p_source_profile_id is null then raise exception 'Personel kasası seçilmelidir.'; end if;
    select greatest(0,
      coalesce((select sum(amount) from public.payments where company_id=v_company and payment_method='cash' and created_by=p_source_profile_id),0)
      - coalesce((select sum(amount) from public.cash_movements where company_id=v_company and movement_type='transfer_to_main' and from_profile_id=p_source_profile_id),0)
      - coalesce((select sum(amount) from public.cash_movements where company_id=v_company and movement_type='expense' and payment_source='personnel_cash' and source_profile_id=p_source_profile_id),0)
    ) into v_available;
  end if;
  if p_amount>v_available then raise exception 'Seçilen kasada yeterli nakit yok.'; end if;

  insert into public.cash_movements(company_id,movement_type,amount,note,created_by,expense_category,beneficiary_profile_id,payment_source,source_profile_id,document_no,expense_at)
  values(v_company,'expense',p_amount,nullif(btrim(p_note),''),v_uid,coalesce(nullif(btrim(p_category),''),'other'),p_beneficiary_profile_id,p_payment_source,p_source_profile_id,nullif(btrim(p_document_no),''),coalesce(p_expense_at,now()));
end;
$$;
grant execute on function public.cash_add_expense_v66(text,numeric,text,uuid,uuid,text,text,timestamptz) to authenticated;

create or replace function public.cash_update_expense_v66(
  p_movement_id uuid,
  p_category text,
  p_amount numeric,
  p_payment_source text,
  p_beneficiary_profile_id uuid default null,
  p_source_profile_id uuid default null,
  p_note text default null,
  p_document_no text default null,
  p_expense_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid(); v_company uuid; v_role text;
begin
  select company_id,role into v_company,v_role from public.profiles where id=v_uid and is_active=true and deleted_at is null;
  if v_company is null or v_role not in ('admin','manager') then raise exception 'Bu işlem için yönetici yetkisi gerekir.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Tutar sıfırdan büyük olmalıdır.'; end if;
  if coalesce(p_payment_source,'') not in ('main_cash','personnel_cash') then raise exception 'Geçersiz ödeme kaynağı.'; end if;
  if p_payment_source='personnel_cash' and p_source_profile_id is null then raise exception 'Personel kasası seçilmelidir.'; end if;

  update public.cash_movements set
    amount=p_amount,
    expense_category=coalesce(nullif(btrim(p_category),''),'other'),
    beneficiary_profile_id=p_beneficiary_profile_id,
    payment_source=p_payment_source,
    source_profile_id=p_source_profile_id,
    note=nullif(btrim(p_note),''),
    document_no=nullif(btrim(p_document_no),''),
    expense_at=coalesce(p_expense_at,expense_at,created_at)
  where id=p_movement_id and company_id=v_company and movement_type='expense';
  if not found then raise exception 'Gider kaydı bulunamadı.'; end if;
end;
$$;
grant execute on function public.cash_update_expense_v66(uuid,text,numeric,text,uuid,uuid,text,text,timestamptz) to authenticated;

create or replace function public.cash_delete_expense_v66(p_movement_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid(); v_company uuid; v_role text;
begin
  select company_id,role into v_company,v_role from public.profiles where id=v_uid and is_active=true and deleted_at is null;
  if v_company is null or v_role not in ('admin','manager') then raise exception 'Bu işlem için yönetici yetkisi gerekir.'; end if;
  delete from public.cash_movements where id=p_movement_id and company_id=v_company and movement_type='expense';
  if not found then raise exception 'Gider kaydı bulunamadı.'; end if;
end;
$$;
grant execute on function public.cash_delete_expense_v66(uuid) to authenticated;
