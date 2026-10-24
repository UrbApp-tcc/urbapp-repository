-- Exposição restrita da equipe vinculada aos órgãos da mesma gestão municipal.
-- Retorna apenas dados de apresentação necessários à coordenação interna.

create or replace function public.get_administration_agency_team(
  target_administration_id bigint
)
returns table (
  agency_id bigint,
  display_name text,
  avatar_url text,
  member_role text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    agency.id,
    coalesce(nullif(trim(profile.full_name), ''), profile.username, 'Equipe do órgão'),
    profile.avatar_url,
    member.role
  from public.administration_users administration_member
  join public.municipal_administrations administration
    on administration.id = administration_member.administration_id
  join public.public_agencies agency
    on agency.city_id = administration.city_id
  join public.agency_users member
    on member.agency_id = agency.id
   and member.is_active = true
  join public.profiles profile
    on profile.id = member.user_id
  where administration_member.administration_id = target_administration_id
    and administration_member.user_id = auth.uid()
    and administration_member.is_active = true
  order by agency.name, profile.full_name, profile.username;
$$;

revoke all on function public.get_administration_agency_team(bigint)
  from public, anon;
grant execute on function public.get_administration_agency_team(bigint)
  to authenticated;
