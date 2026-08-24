-- ARN ERP - Sekretere yeniden planlama icin gonderilen servislerde musteri bilgisini goster (V4 FIX)
-- Bu surum erp_auth_company_id() / erp_auth_role() yardimci fonksiyonlarina BAGLI DEGILDIR.
-- Dolayisiyla eski/veritabani migration sirasi farkli kurulumlarda da calisir.

create or replace function public.erp_secretary_can_view_service_customer_v4(
  p_customer_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.customers c
    join public.profiles me
      on me.id = auth.uid()
     and me.company_id = c.company_id
     and coalesce(me.is_active, false) = true
     and me.role::text = 'secretary'
    where c.id = p_customer_id
      and c.deleted_at is null
      and (
        c.created_by = auth.uid()
        or exists(
          select 1
          from public.service_requests sr
          where sr.company_id = c.company_id
            and sr.customer_id = c.id
            and (
              sr.created_by = auth.uid()
              or sr.rework_secretary_id = auth.uid()
            )
        )
      )
  );
$$;

grant execute on function public.erp_secretary_can_view_service_customer_v4(uuid)
to authenticated;

-- Eski taslaklarda customer_id bos kaldiysa kaynak servisten geri doldur.
update public.service_requests draft
set customer_id = source.customer_id,
    updated_at = now()
from public.service_requests source
where draft.rework_source_service_request_id = source.id
  and draft.customer_id is null
  and source.customer_id is not null;

-- Sekreter sadece kendi firmasinda, kendi olusturdugu veya kendisine yeniden planlama
-- icin gonderilmis servislerin musteri kaydini gorebilir.
drop policy if exists customers_select_secretary_service_scope_v4 on public.customers;
create policy customers_select_secretary_service_scope_v4
on public.customers
for select
to authenticated
using (
  deleted_at is null
  and exists (
    select 1
    from public.profiles me
    where me.id = auth.uid()
      and coalesce(me.is_active, false) = true
      and me.role::text = 'secretary'
      and me.company_id = customers.company_id
  )
  and public.erp_secretary_can_view_service_customer_v4(id)
);

notify pgrst, 'reload schema';
