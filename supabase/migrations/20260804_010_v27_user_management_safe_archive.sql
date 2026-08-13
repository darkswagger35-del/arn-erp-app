-- ARN ERP V27 - Kullanıcı yönetimi, username ve güvenli arşivleme
begin;

alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists deleted_at timestamptz;

create unique index if not exists profiles_company_username_active_unique
on public.profiles(company_id, lower(username))
where username is not null and deleted_at is null;

create or replace function public.enforce_profile_update_policy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_role text;
  current_company_id uuid;
  self_update boolean;
begin
  if current_setting('app.profile_admin_bypass', true) = 'on' then
    return new;
  end if;

  if current_user_id is null then
    raise exception 'Authentication required for profile updates.' using errcode = '42501';
  end if;

  select role, company_id into current_role, current_company_id
  from public.profiles
  where id = current_user_id and is_active = true
  limit 1;

  if not found then
    raise exception 'No active profile exists for the authenticated user.' using errcode = '42501';
  end if;

  if new.id is distinct from old.id
     or new.company_id is distinct from old.company_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Identity fields of a profile cannot be changed.' using errcode = '42501';
  end if;

  self_update := old.id = current_user_id;

  if self_update then
    if new.role is distinct from old.role or new.is_active is distinct from old.is_active then
      raise exception 'You may only update your own full_name and phone.' using errcode = '42501';
    end if;
    return new;
  end if;

  if current_role = 'admin' and current_company_id = old.company_id then
    return new;
  end if;

  raise exception 'You are not allowed to update this profile.' using errcode = '42501';
end;
$$;

create or replace function public.admin_update_company_user_v27(
  p_user_id uuid,
  p_full_name text default null,
  p_username text default null,
  p_phone text default null,
  p_role text default null,
  p_is_active boolean default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_username text;
begin
  select * into v_actor from public.profiles where id=auth.uid() and is_active=true;
  if v_actor.id is null or v_actor.role::text <> 'admin' then
    raise exception 'Bu işlem için yalnızca Admin yetkilidir.';
  end if;

  select * into v_target
  from public.profiles
  where id=p_user_id and company_id=v_actor.company_id and deleted_at is null
  for update;
  if v_target.id is null then raise exception 'Kullanıcı bulunamadı.'; end if;

  if v_target.role::text='admin' then
    if p_role is not null and p_role<>'admin' then raise exception 'Admin rolü değiştirilemez.'; end if;
    if p_is_active=false then raise exception 'Admin pasife alınamaz.'; end if;
  elsif p_role is not null and p_role not in ('manager','secretary','technician') then
    raise exception 'Geçersiz rol.';
  end if;

  v_username := nullif(lower(btrim(coalesce(p_username, v_target.username))), '');
  if v_username is null or v_username !~ '^[a-z0-9._-]{3,30}$' then
    raise exception 'Kullanıcı adı 3-30 karakter olmalıdır.';
  end if;
  if exists (
    select 1 from public.profiles p
    where p.company_id=v_actor.company_id and p.id<>p_user_id
      and p.deleted_at is null and lower(p.username)=v_username
  ) then raise exception 'Bu kullanıcı adı zaten kullanılıyor.'; end if;

  perform set_config('app.profile_admin_bypass','on',true);
  update public.profiles
  set full_name=coalesce(nullif(btrim(p_full_name),''), full_name),
      username=v_username,
      phone=case when p_phone is null then phone else nullif(btrim(p_phone),'') end,
      role=coalesce(p_role, role),
      is_active=coalesce(p_is_active,is_active),
      updated_at=now()
  where id=p_user_id;
end;
$$;

create or replace function public.archive_company_user_v27(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
begin
  select * into v_actor from public.profiles where id=auth.uid() and is_active=true;
  if v_actor.id is null or v_actor.role::text <> 'admin' then
    raise exception 'Bu işlem için yalnızca Admin yetkilidir.';
  end if;

  select * into v_target
  from public.profiles
  where id=p_user_id and company_id=v_actor.company_id and deleted_at is null
  for update;
  if v_target.id is null then raise exception 'Kullanıcı bulunamadı.'; end if;
  if v_target.id=v_actor.id then raise exception 'Kendi hesabınızı arşivleyemezsiniz.'; end if;
  if v_target.role::text='admin' then raise exception 'Admin hesabı arşivlenemez.'; end if;

  perform set_config('app.profile_admin_bypass','on',true);
  update public.profiles
  set is_active=false,
      deleted_at=now(),
      username=case when username is null then null else username || '__arsiv__' || left(id::text,8) end,
      updated_at=now()
  where id=p_user_id;

  -- Açık işler başka personel atanabilsin diye beklemeye alınır; tamamlanmış geçmişe dokunulmaz.
  update public.service_requests
  set assigned_technician_id=null,
      status=case when status::text in ('assigned','in_progress') then 'pending' else status end,
      updated_at=now()
  where assigned_technician_id=p_user_id
    and status::text in ('assigned','in_progress');

  -- Araç deposu listeden kaldırılır; eski stok hareketleri korunur.
  update public.warehouses
  set is_active=false, updated_at=now()
  where assigned_technician_id=p_user_id;
end;
$$;

revoke all on function public.admin_update_company_user_v27(uuid,text,text,text,text,boolean) from public, anon;
grant execute on function public.admin_update_company_user_v27(uuid,text,text,text,text,boolean) to authenticated;
revoke all on function public.archive_company_user_v27(uuid) from public, anon;
grant execute on function public.archive_company_user_v27(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
