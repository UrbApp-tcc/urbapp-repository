-- Consulta interna usada somente pela Edge Function de login.
create or replace function public.find_profile_id_by_username(
  login_username text
)
returns uuid
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select profile.id
  from public.profiles profile
  where lower(profile.username) = lower(
    trim(leading '@' from trim(login_username))
  )
  limit 1;
$$;

revoke all on function public.find_profile_id_by_username(text)
  from public, anon, authenticated;

grant execute on function public.find_profile_id_by_username(text)
  to service_role;
