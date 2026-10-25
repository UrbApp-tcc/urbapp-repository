-- Lista interna de colaboradores da Prefeitura e dos órgãos vinculados.
-- A carga individual considera apenas ações efetivamente registradas.

create or replace function public.get_administration_collaborators(
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
  last_action_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with requester_access as (
    select 1
    from public.administration_users requester
    where requester.administration_id = target_administration_id
      and requester.user_id = auth.uid()
      and requester.is_active = true
  ), collaborators as (
    select
      member.user_id,
      coalesce(nullif(trim(profile.full_name), ''), profile.username, 'Colaborador da Prefeitura') as display_name,
      profile.avatar_url,
      member.role as member_role,
      administration.name as organization_name,
      'administration'::text as organization_kind,
      count(action.id)::bigint as actions_count,
      count(distinct action.occurrence_id)::bigint as demands_count,
      max(action.created_at) as last_action_at
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
      max(action.created_at) as last_action_at
    from requester_access
    join public.municipal_administrations administration
      on administration.id = target_administration_id
    join public.public_agencies agency on agency.city_id = administration.city_id
    join public.agency_users member
      on member.agency_id = agency.id
     and member.is_active = true
    join public.profiles profile on profile.id = member.user_id
    left join public.institutional_actions action
      on action.created_by = member.user_id
     and action.administration_id = target_administration_id
    group by member.user_id, profile.full_name, profile.username,
      profile.avatar_url, member.role, agency.name
  )
  select *
  from collaborators
  order by organization_kind, organization_name, display_name;
$$;

revoke all on function public.get_administration_collaborators(bigint)
  from public, anon;
grant execute on function public.get_administration_collaborators(bigint)
  to authenticated;
