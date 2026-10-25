-- Amplia o diretório institucional da gestão com vereadores em mandato e
-- registra as ocorrências vinculadas a cada pessoa para o filtro operacional.

drop function if exists public.get_administration_collaborators(bigint);

create function public.get_administration_collaborators(
  target_administration_id bigint
)
returns table (
  user_id uuid,
  display_name text,
  avatar_url text,
  member_role text,
  organization_name text,
  organization_kind text,
  actions_count bigint,
  demands_count bigint,
  last_action_at timestamptz,
  occurrence_ids bigint[]
)
language sql
stable
security definer
set search_path = public
as $$
  with requester_access as (
    select administration.city_id
    from public.administration_users requester
    join public.municipal_administrations administration
      on administration.id = requester.administration_id
    where requester.administration_id = target_administration_id
      and requester.user_id = auth.uid()
      and requester.is_active = true
  ), people as (
    select
      member.user_id,
      coalesce(nullif(trim(profile.full_name), ''), profile.username, 'Colaborador da Prefeitura') as display_name,
      profile.avatar_url,
      member.role as member_role,
      administration.name as organization_name,
      'administration'::text as organization_kind,
      count(action.id)::bigint as actions_count,
      count(distinct action.occurrence_id)::bigint as demands_count,
      max(action.created_at) as last_action_at,
      coalesce(
        array_agg(distinct action.occurrence_id) filter (where action.occurrence_id is not null),
        '{}'::bigint[]
      ) as occurrence_ids
    from public.administration_users member
    join public.municipal_administrations administration
      on administration.id = member.administration_id
    join public.profiles profile on profile.id = member.user_id
    left join public.institutional_actions action
      on action.created_by = member.user_id
     and action.administration_id = member.administration_id
    where member.administration_id = target_administration_id
      and member.is_active = true
      and exists (select 1 from requester_access)
    group by member.user_id, profile.full_name, profile.username,
      profile.avatar_url, member.role, administration.name

    union all

    select
      member.user_id,
      coalesce(nullif(trim(profile.full_name), ''), profile.username, 'Colaborador do órgão') as display_name,
      profile.avatar_url,
      member.role as member_role,
      agency.name as organization_name,
      'agency'::text as organization_kind,
      count(action.id)::bigint as actions_count,
      count(distinct action.occurrence_id)::bigint as demands_count,
      max(action.created_at) as last_action_at,
      coalesce(
        array_agg(distinct action.occurrence_id) filter (where action.occurrence_id is not null),
        '{}'::bigint[]
      ) as occurrence_ids
    from requester_access
    join public.public_agencies agency
      on agency.city_id = requester_access.city_id
    join public.agency_users member
      on member.agency_id = agency.id
     and member.is_active = true
    join public.profiles profile on profile.id = member.user_id
    left join public.institutional_actions action
      on action.created_by = member.user_id
     and action.administration_id = target_administration_id
    group by member.user_id, profile.full_name, profile.username,
      profile.avatar_url, member.role, agency.name

    union all

    select
      councilor.profile_id as user_id,
      councilor.public_name as display_name,
      profile.avatar_url,
      'councilor'::text as member_role,
      case
        when nullif(trim(councilor.party), '') is null then 'Câmara Municipal'
        else 'Câmara Municipal · ' || trim(councilor.party)
      end as organization_name,
      'councilor'::text as organization_kind,
      count(distinct action.id)::bigint as actions_count,
      count(distinct following.occurrence_id)::bigint as demands_count,
      max(action.created_at) as last_action_at,
      coalesce(
        array_agg(distinct following.occurrence_id) filter (where following.occurrence_id is not null),
        '{}'::bigint[]
      ) as occurrence_ids
    from requester_access
    join public.councilor_profiles councilor
      on councilor.city_id = requester_access.city_id
     and current_date between councilor.mandate_starts_on and councilor.mandate_ends_on
    join public.profiles profile on profile.id = councilor.profile_id
    left join public.councilor_followings following
      on following.councilor_profile_id = councilor.id
    left join public.councilor_actions action on action.following_id = following.id
    group by councilor.profile_id, councilor.public_name, profile.avatar_url,
      councilor.party
  )
  select *
  from people
  order by organization_kind, organization_name, display_name;
$$;

revoke all on function public.get_administration_collaborators(bigint)
  from public, anon;
grant execute on function public.get_administration_collaborators(bigint)
  to authenticated;
