-- ARN ERP V22
-- Kullanıcı adı ile giriş için güvenli e-posta çözümleyici.
-- Profiller tablosunu güncellemez; mevcut profil güncelleme trigger'ını tetiklemez.

create or replace function public.erp_resolve_login_email_v22(p_identifier text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_identifier text := lower(trim(coalesce(p_identifier, '')));
  v_email text;
  v_count integer;
begin
  if v_identifier = '' then
    return null;
  end if;

  select count(*), min(lower(u.email))
    into v_count, v_email
  from auth.users u
  join public.profiles p on p.id = u.id
  where coalesce(p.is_active, true) = true
    and (
      lower(u.email) = v_identifier
      or lower(split_part(u.email, '@', 1)) = v_identifier
    );

  -- Aynı kullanıcı adı birden fazla e-postada varsa güvenlik için sonuç verme.
  if v_count <> 1 then
    return null;
  end if;

  return v_email;
end;
$$;

revoke all on function public.erp_resolve_login_email_v22(text) from public;
grant execute on function public.erp_resolve_login_email_v22(text) to anon, authenticated;
