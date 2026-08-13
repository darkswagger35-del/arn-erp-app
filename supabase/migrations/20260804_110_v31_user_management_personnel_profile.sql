-- ARN ERP V31 - Kullanıcı yönetimi, arşiv ve personel profili
begin;

alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists deleted_at timestamptz;

create unique index if not exists profiles_company_username_active_unique
on public.profiles(company_id, lower(username))
where username is not null and deleted_at is null;

create or replace function public.admin_update_company_user_v31(
  p_user_id uuid,
  p_full_name text default null,
  p_username text default null,
  p_phone text default null,
  p_role text default null,
  p_is_active boolean default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_username text;
begin
  select * into v_actor from public.profiles where id=auth.uid() and is_active=true and deleted_at is null;
  if v_actor.id is null or v_actor.role::text not in ('admin','manager') then
    raise exception 'Bu işlem için Admin/Yönetici yetkisi gerekir.';
  end if;

  select * into v_target from public.profiles
  where id=p_user_id and company_id=v_actor.company_id and deleted_at is null
  for update;
  if v_target.id is null then raise exception 'Kullanıcı bulunamadı.'; end if;

  if v_target.role::text='admin' then
    if v_actor.role::text<>'admin' then raise exception 'Admin hesabını yalnız Admin düzenleyebilir.'; end if;
    if p_role is not null and p_role<>'admin' then raise exception 'Admin rolü değiştirilemez.'; end if;
    if p_is_active=false then raise exception 'Admin pasife alınamaz.'; end if;
  elsif p_role is not null and p_role not in ('manager','secretary','technician') then
    raise exception 'Geçersiz rol.';
  end if;

  v_username:=nullif(lower(btrim(coalesce(p_username,v_target.username))), '');
  if v_username is null or v_username !~ '^[a-z0-9._-]{3,30}$' then
    raise exception 'Kullanıcı adı 3-30 karakter olmalı; harf, rakam, nokta, tire ve alt çizgi kullanılabilir.';
  end if;
  if exists(select 1 from public.profiles p where p.company_id=v_actor.company_id and p.id<>p_user_id and p.deleted_at is null and lower(p.username)=v_username) then
    raise exception 'Bu kullanıcı adı zaten kullanılıyor.';
  end if;

  perform set_config('app.profile_admin_bypass','on',true);
  update public.profiles set
    full_name=coalesce(nullif(btrim(p_full_name),''),full_name),
    username=v_username,
    phone=case when p_phone is null then phone else nullif(btrim(p_phone),'') end,
    role=coalesce(p_role,role),
    is_active=coalesce(p_is_active,is_active),
    updated_at=now()
  where id=p_user_id;
end;
$$;

create or replace function public.archive_company_user_v31(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
begin
  select * into v_actor from public.profiles where id=auth.uid() and is_active=true and deleted_at is null;
  if v_actor.id is null or v_actor.role::text<>'admin' then raise exception 'Kullanıcıyı yalnız Admin arşivleyebilir.'; end if;
  select * into v_target from public.profiles where id=p_user_id and company_id=v_actor.company_id and deleted_at is null for update;
  if v_target.id is null then raise exception 'Kullanıcı bulunamadı.'; end if;
  if v_target.id=v_actor.id then raise exception 'Kendi hesabınızı arşivleyemezsiniz.'; end if;
  if v_target.role::text='admin' then raise exception 'Admin hesabı arşivlenemez.'; end if;

  perform set_config('app.profile_admin_bypass','on',true);
  update public.profiles set
    is_active=false,
    deleted_at=now(),
    username=case when username is null then null else split_part(username,'__arsiv__',1)||'__arsiv__'||left(id::text,8) end,
    updated_at=now()
  where id=p_user_id;

  update public.service_requests set
    assigned_technician_id=null,
    status=case when status::text in ('assigned','in_progress') then 'pending' else status::text end,
    updated_at=now()
  where assigned_technician_id=p_user_id and status::text in ('assigned','in_progress');

  update public.warehouses set is_active=false,updated_at=now()
  where assigned_technician_id=p_user_id;
end;
$$;

create or replace function public.restore_company_user_v31(p_user_id uuid,p_username text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_username text:=lower(btrim(p_username));
begin
  select * into v_actor from public.profiles where id=auth.uid() and is_active=true and deleted_at is null;
  if v_actor.id is null or v_actor.role::text<>'admin' then raise exception 'Kullanıcıyı yalnız Admin geri yükleyebilir.'; end if;
  select * into v_target from public.profiles where id=p_user_id and company_id=v_actor.company_id and deleted_at is not null for update;
  if v_target.id is null then raise exception 'Arşiv kaydı bulunamadı.'; end if;
  if v_username !~ '^[a-z0-9._-]{3,30}$' then raise exception 'Geçerli bir kullanıcı adı girin.'; end if;
  if exists(select 1 from public.profiles p where p.company_id=v_actor.company_id and p.id<>p_user_id and p.deleted_at is null and lower(p.username)=v_username) then raise exception 'Bu kullanıcı adı zaten kullanılıyor.'; end if;

  perform set_config('app.profile_admin_bypass','on',true);
  update public.profiles set is_active=true,deleted_at=null,username=v_username,updated_at=now() where id=p_user_id;
  update public.warehouses set is_active=true,updated_at=now() where assigned_technician_id=p_user_id;
end;
$$;

create or replace function public.personnel_profile_v31(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_result jsonb;
begin
  select * into v_actor from public.profiles where id=auth.uid() and is_active=true and deleted_at is null;
  if v_actor.id is null or v_actor.role::text not in ('admin','manager') then raise exception 'Personel profilini görüntüleme yetkiniz yok.'; end if;
  select * into v_target from public.profiles where id=p_user_id and company_id=v_actor.company_id;
  if v_target.id is null then raise exception 'Personel bulunamadı.'; end if;

  select jsonb_build_object(
    'completed_jobs',(select count(*) from public.service_requests sr where sr.company_id=v_actor.company_id and sr.assigned_technician_id=p_user_id and sr.status::text='completed'),
    'month_jobs',(select count(*) from public.service_requests sr where sr.company_id=v_actor.company_id and sr.assigned_technician_id=p_user_id and sr.status::text='completed' and sr.updated_at>=date_trunc('month',now())),
    'opened_services',(select count(*) from public.service_requests sr where sr.company_id=v_actor.company_id and sr.created_by=p_user_id),
    'month_opened_services',(select count(*) from public.service_requests sr where sr.company_id=v_actor.company_id and sr.created_by=p_user_id and sr.created_at>=date_trunc('month',now())),
    'turnover',(select coalesce(sum(sr.price),0) from public.service_requests sr where sr.company_id=v_actor.company_id and sr.status::text='completed' and (sr.assigned_technician_id=p_user_id or sr.created_by=p_user_id)),
    'month_turnover',(select coalesce(sum(sr.price),0) from public.service_requests sr where sr.company_id=v_actor.company_id and sr.status::text='completed' and sr.updated_at>=date_trunc('month',now()) and (sr.assigned_technician_id=p_user_id or sr.created_by=p_user_id)),
    'recent_jobs',coalesce((select jsonb_agg(x order by x.created_at desc) from (
      select sr.id,sr.service_type::text service_type,sr.status::text status,sr.price,sr.created_at,coalesce(c.full_name,'') customer_name
      from public.service_requests sr left join public.customers c on c.id=sr.customer_id
      where sr.company_id=v_actor.company_id and (sr.assigned_technician_id=p_user_id or sr.created_by=p_user_id)
      order by sr.created_at desc limit 10
    ) x),'[]'::jsonb),
    'used_products',coalesce((select jsonb_agg(x order by x.quantity desc) from (
      select coalesce(cmr.product_name,p.name,'Ürün') product_name,count(*) quantity
      from public.customer_maintenance_records cmr
      left join public.products p on p.id=cmr.product_id
      where cmr.company_id=v_actor.company_id and (cmr.technician_id=p_user_id or cmr.secretary_id=p_user_id or cmr.assigned_user_id=p_user_id)
      group by coalesce(cmr.product_name,p.name,'Ürün')
      order by count(*) desc limit 10
    ) x),'[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.admin_update_company_user_v31(uuid,text,text,text,text,boolean) from public,anon;
grant execute on function public.admin_update_company_user_v31(uuid,text,text,text,text,boolean) to authenticated;
revoke all on function public.archive_company_user_v31(uuid) from public,anon;
grant execute on function public.archive_company_user_v31(uuid) to authenticated;
revoke all on function public.restore_company_user_v31(uuid,text) from public,anon;
grant execute on function public.restore_company_user_v31(uuid,text) to authenticated;
revoke all on function public.personnel_profile_v31(uuid) from public,anon;
grant execute on function public.personnel_profile_v31(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
