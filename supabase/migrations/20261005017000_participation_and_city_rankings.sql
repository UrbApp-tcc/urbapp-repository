-- Ranking de participação cidadã (spec §21–22).
--   * Cidadãos mais participativos da cidade, no geral ou no mês corrente,
--     usando apenas os pontos já concedidos pelas regras de gamificação.
--   * Perfis privados e institucionais (vereadores, órgãos, gestão e
--     administração) não entram: o UrbApp não classifica agentes políticos.
-- Não há ranking entre cidades: falta um indicador de participação normalizado
-- (por exemplo, proporcional à população), ainda não definido na especificação.

create or replace function public.is_institutional_account(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
      select 1 from public.councilor_profiles councilor
      where councilor.profile_id = target_user_id
        and councilor.profile_status in ('verified', 'participant')
    )
    or exists (
      select 1 from public.agency_users member
      where member.user_id = target_user_id and member.is_active
    )
    or exists (
      select 1 from public.administration_users member
      where member.user_id = target_user_id and member.is_active
    )
    or exists (
      select 1 from public.platform_user_roles role
      where role.user_id = target_user_id
    );
$$;

revoke all on function public.is_institutional_account(uuid) from public, anon, authenticated;

-- Pontos do período: 'all' usa o saldo do perfil; 'month' soma as transações
-- do mês corrente (inclui estornos por moderação).
create or replace function public.participation_points(target_user_id uuid, period text)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select case
    when coalesce(period, 'all') = 'month' then (
      select coalesce(sum(tx.points_delta), 0)::bigint
      from public.xp_transactions tx
      where tx.user_id = target_user_id
        and tx.created_at >= date_trunc('month', now())
    )
    else (select profile.current_points::bigint from public.profiles profile where profile.id = target_user_id)
  end;
$$;

revoke all on function public.participation_points(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Cidadãos mais participativos
-- ---------------------------------------------------------------------------

drop function if exists public.get_city_ranking(bigint, integer, integer);

create or replace function public.get_city_ranking(
  target_city_id bigint,
  page_size integer default 50,
  page_offset integer default 0,
  period text default 'all'
)
returns table (
  rank_position bigint,
  profile_id uuid,
  full_name text,
  username text,
  avatar_url text,
  city_id bigint,
  city_name text,
  current_level integer,
  current_xp integer,
  current_points bigint,
  posts_count integer,
  supports_received integer,
  comments_received integer,
  resolved_posts_count integer,
  ranking_score bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with city_profiles as (
    select profile.id, profile.full_name, profile.username, profile.avatar_url,
           profile.city_id, city.name as city_name, profile.current_level,
           profile.current_xp, profile.current_points, profile.created_at,
           public.participation_points(profile.id, period) as period_points
    from public.profiles profile
    join public.cities city on city.id = profile.city_id
    where profile.city_id = target_city_id
      and profile.is_public
      and not public.is_institutional_account(profile.id)
  ),
  ranked_profiles as (
    select * from city_profiles where period_points > 0
  ),
  public_contributions as (
    select post.user_id as profile_id,
           count(distinct post.occurrence_id)::integer as posts_count,
           count(distinct post.occurrence_id) filter (where occurrence.status = 'completed')::integer
             as resolved_posts_count
    from public.posts post
    join public.occurrences occurrence on occurrence.id = post.occurrence_id
    where post.city_id = target_city_id
      and post.hidden_at is null
      and not post.anonymity
      and occurrence.invalidated_at is null
    group by post.user_id
  ),
  received as (
    select tx.user_id as profile_id,
           count(*) filter (where tx.source_type like 'support_received:%')::integer as supports_received,
           count(*) filter (where tx.source_type like 'comment_received%')::integer as comments_received
    from public.xp_transactions tx
    where tx.points_delta > 0
    group by tx.user_id
  )
  select
    rank() over (order by profile.period_points desc),
    profile.id, profile.full_name, profile.username, profile.avatar_url, profile.city_id,
    profile.city_name, profile.current_level, profile.current_xp, profile.period_points,
    coalesce(contribution.posts_count, 0),
    coalesce(received.supports_received, 0),
    coalesce(received.comments_received, 0),
    coalesce(contribution.resolved_posts_count, 0),
    profile.period_points
  from ranked_profiles profile
  left join public_contributions contribution on contribution.profile_id = profile.id
  left join received on received.profile_id = profile.id
  order by profile.period_points desc, profile.current_xp desc, profile.created_at, profile.id
  limit greatest(1, least(coalesce(page_size, 50), 100))
  offset greatest(0, coalesce(page_offset, 0));
$$;

revoke all on function public.get_city_ranking(bigint, integer, integer, text) from public, anon;
grant execute on function public.get_city_ranking(bigint, integer, integer, text) to authenticated;

-- Posição do usuário atual e distância para a posição acima.
create or replace function public.get_participation_standing(target_city_id bigint, period text default 'all')
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select profile.id, profile.is_public,
           public.participation_points(profile.id, period) as points,
           public.is_institutional_account(profile.id) as institutional
    from public.profiles profile
    where profile.id = auth.uid()
  ),
  ranked as (
    select scored.id, scored.points,
           rank() over (order by scored.points desc) as position
    from (
      select profile.id, public.participation_points(profile.id, period) as points
      from public.profiles profile
      where profile.city_id = target_city_id
        and profile.is_public
        and not public.is_institutional_account(profile.id)
    ) scored
    where scored.points > 0
  )
  select jsonb_build_object(
    'points', coalesce(me.points, 0),
    'participants', (select count(*) from ranked),
    'position', (select ranked.position from ranked where ranked.id = me.id),
    'points_to_next', (
      select min(ranked.points) - me.points + 1
      from ranked
      where ranked.points > me.points
    ),
    'eligible', coalesce(me.is_public and not me.institutional, false),
    'reason', case
      when me.institutional then 'institutional'
      when not me.is_public then 'private'
      else null
    end
  )
  from me;
$$;

revoke all on function public.get_participation_standing(bigint, text) from public, anon;
grant execute on function public.get_participation_standing(bigint, text) to authenticated;
