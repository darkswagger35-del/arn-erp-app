-- ARN ERP 2026-08-11
-- Sekreter veri izolasyonu: her sekreter yalnız kendi müşteri/servis/bakım/bildirim kayıtlarını görür.

create or replace function public.erp_auth_company_id()
returns uuid language sql stable security definer set search_path=public as $$
  select company_id from public.profiles where id=auth.uid() limit 1
$$;

create or replace function public.erp_auth_role()
returns text language sql stable security definer set search_path=public as $$
  select role from public.profiles where id=auth.uid() limit 1
$$;

create or replace function public.erp_secretary_owns_customer(p_customer_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.customers c
    where c.id=p_customer_id
      and c.company_id=public.erp_auth_company_id()
      and c.created_by=auth.uid()
      and c.deleted_at is null
  )
$$;

create or replace function public.erp_technician_can_view_customer(p_customer_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.service_requests sr
    where sr.customer_id=p_customer_id
      and sr.company_id=public.erp_auth_company_id()
      and sr.assigned_technician_id=auth.uid()
  )
$$;

grant execute on function public.erp_auth_company_id() to authenticated;
grant execute on function public.erp_auth_role() to authenticated;
grant execute on function public.erp_secretary_owns_customer(uuid) to authenticated;
grant execute on function public.erp_technician_can_view_customer(uuid) to authenticated;

-- SELECT politikalarını tek ve net kurala indir.
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname='public' and tablename='customers' and cmd='SELECT'
  loop execute format('drop policy if exists %I on public.customers', r.policyname); end loop;
  for r in select policyname from pg_policies where schemaname='public' and tablename='service_requests' and cmd='SELECT'
  loop execute format('drop policy if exists %I on public.service_requests', r.policyname); end loop;
  for r in select policyname from pg_policies where schemaname='public' and tablename='customer_maintenance_records' and cmd='SELECT'
  loop execute format('drop policy if exists %I on public.customer_maintenance_records', r.policyname); end loop;
end $$;

create policy customers_select_private_v42
on public.customers for select to authenticated
using (
  company_id=public.erp_auth_company_id()
  and deleted_at is null
  and (
    public.erp_auth_role() in ('admin','manager')
    or (public.erp_auth_role()='secretary' and created_by=auth.uid())
    or (public.erp_auth_role()='technician' and public.erp_technician_can_view_customer(id))
  )
);

create policy service_requests_select_private_v42
on public.service_requests for select to authenticated
using (
  company_id=public.erp_auth_company_id()
  and (
    public.erp_auth_role() in ('admin','manager')
    or (public.erp_auth_role()='secretary' and created_by=auth.uid())
    or (public.erp_auth_role()='technician' and assigned_technician_id=auth.uid())
  )
);

create policy customer_maintenance_select_private_v42
on public.customer_maintenance_records for select to authenticated
using (
  company_id=public.erp_auth_company_id()
  and (
    public.erp_auth_role() in ('admin','manager')
    or (
      public.erp_auth_role()='secretary'
      and (secretary_id=auth.uid() or public.erp_secretary_owns_customer(customer_id))
    )
    or (public.erp_auth_role()='technician' and technician_id=auth.uid())
  )
);

-- Eski bakım kayıtlarında secretary_id boşsa müşteri sahibinden tamamla.
update public.customer_maintenance_records cmr
set secretary_id=c.created_by
from public.customers c
join public.profiles p on p.id=c.created_by and p.role='secretary'
where cmr.customer_id=c.id
  and cmr.secretary_id is null;

-- Gidemiyorum bildirimi: yöneticiler + yalnız servisi açan sekreter.
create or replace function public.technician_cannot_attend_v1(
  p_service_request_id uuid,
  p_reason text,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
  v_company_id uuid;
  v_role text;
  v_is_active boolean;
  v_customer_name text;
  v_technician_name text;
  v_current_technician uuid;
  v_status text;
  v_created_by uuid;
  v_message text;
  v_count integer:=0;
  r record;
begin
  if v_uid is null then raise exception 'Oturum bulunamadı.' using errcode='28000'; end if;

  select company_id,role,is_active,coalesce(nullif(trim(full_name),''),'Tekniker')
  into v_company_id,v_role,v_is_active,v_technician_name
  from public.profiles where id=v_uid;

  if v_role is distinct from 'technician' or coalesce(v_is_active,false)=false then
    raise exception 'Bu işlem yalnızca aktif tekniker tarafından yapılabilir.';
  end if;

  select sr.assigned_technician_id,sr.status::text,sr.created_by,
         coalesce(nullif(trim(c.full_name),''),nullif(trim(c.company_name),''),'Müşteri')
  into v_current_technician,v_status,v_created_by,v_customer_name
  from public.service_requests sr
  left join public.customers c on c.id=sr.customer_id
  where sr.id=p_service_request_id and sr.company_id=v_company_id
  for update of sr;

  if not found then raise exception 'Servis kaydı bulunamadı.'; end if;
  if v_current_technician is distinct from v_uid then raise exception 'Bu servis size atanmış değil.'; end if;
  if v_status not in ('assigned') then raise exception 'Yalnızca henüz başlanmamış atanmış servis için Gidemiyorum bildirimi gönderilebilir.'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Sebep seçmelisiniz.'; end if;

  update public.service_requests
  set status='cancelled', route_order=null, route_plan_date=null,
      technician_unavailable_reason=trim(p_reason),
      technician_unavailable_note=nullif(trim(coalesce(p_note,'')),''),
      technician_unavailable_at=now(), technician_unavailable_by=v_uid,
      cancellation_reason=trim(p_reason)||case when nullif(trim(coalesce(p_note,'')),'') is null then '' else ' • '||trim(p_note) end,
      cancelled_at=now(), cancelled_by=v_uid, cancelled_by_name=v_technician_name, updated_at=now()
  where id=p_service_request_id;

  v_message:=coalesce(v_technician_name,'Tekniker')||' • '||coalesce(v_customer_name,'Müşteri')||' • '||trim(p_reason)||
             case when nullif(trim(coalesce(p_note,'')),'') is null then '' else ' • '||trim(p_note) end;

  for r in
    select id,role from public.profiles
    where company_id=v_company_id and is_active=true
      and (
        role in ('admin','manager')
        or (role='secretary' and id=v_created_by)
      )
  loop
    insert into public.app_notifications(company_id,user_id,title,message,notification_type,route,entity_type,entity_id)
    values(v_company_id,r.id,'Tekniker servise gidemiyor',v_message,'technician_cannot_attend',
      case when r.role='secretary' then '/secretary/service-requests' else '/manager/service-requests' end,
      'service_request',p_service_request_id);
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object('ok',true,'status','cancelled','notifications_created',v_count);
end;
$$;
grant execute on function public.technician_cannot_attend_v1(uuid,text,text) to authenticated;

-- Önceki hatalı toplu sekreter bildirimlerini temizle: servis sahibi olmayan sekreterden kaldır.
delete from public.app_notifications n
using public.profiles p, public.service_requests sr
where n.user_id=p.id
  and p.role='secretary'
  and n.notification_type='technician_cannot_attend'
  and n.entity_type='service_request'
  and n.entity_id=sr.id
  and sr.created_by is distinct from p.id;

notify pgrst,'reload schema';
