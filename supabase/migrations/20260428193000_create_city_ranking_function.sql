create index if not exists posts_city_id_user_id_status_idx
  on public.posts (city_id, user_id, status);

create or replace function public.get_city_ranking(
  target_city_id bigint,
  page_size integer default 50,
  page_offset integer default 0
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
set search_path = public
as $$
  with city_profiles as (
    select
      profile.id,
      profile.full_name,
      profile.username,
      profile.avatar_url,
      profile.city_id,
      city.name as city_name,
      profile.current_level,
      profile.current_xp,
      profile.current_points,
      profile.created_at
    from public.profiles profile
    join public.cities city
      on city.id = profile.city_id
    where profile.city_id = target_city_id
  ),
  post_stats as (
    select
      post.user_id as profile_id,
      count(*)::integer as posts_count,
      coalesce(sum(coalesce(post.supports_count, 0)), 0)::integer as supports_received,
      coalesce(sum(coalesce(post.comments_count, 0)), 0)::integer as comments_received,
      count(*) filter (
        where post.status in ('completed', 'closed')
      )::integer as resolved_posts_count
    from public.posts post
    where post.city_id = target_city_id
      and post.user_id is not null
    group by post.user_id
  ),
  scored_profiles as (
    select
      city_profile.id as profile_id,
      city_profile.full_name,
      city_profile.username,
      city_profile.avatar_url,
      city_profile.city_id,
      city_profile.city_name,
      city_profile.current_level,
      city_profile.current_xp,
      city_profile.current_points,
      city_profile.created_at,
      coalesce(post_stat.posts_count, 0) as posts_count,
      coalesce(post_stat.supports_received, 0) as supports_received,
      coalesce(post_stat.comments_received, 0) as comments_received,
      coalesce(post_stat.resolved_posts_count, 0) as resolved_posts_count,
      (
        coalesce(post_stat.posts_count, 0) * 50
        + coalesce(post_stat.supports_received, 0) * 15
        + coalesce(post_stat.comments_received, 0) * 5
        + coalesce(post_stat.resolved_posts_count, 0) * 100
      )::bigint as ranking_score
    from city_profiles city_profile
    left join post_stats post_stat
      on post_stat.profile_id = city_profile.id
  )
  select
    dense_rank() over (
      order by
        scored_profile.ranking_score desc,
        scored_profile.current_points desc,
        scored_profile.current_xp desc,
        scored_profile.created_at asc,
        scored_profile.profile_id asc
    ) as rank_position,
    scored_profile.profile_id,
    scored_profile.full_name,
    scored_profile.username,
    scored_profile.avatar_url,
    scored_profile.city_id,
    scored_profile.city_name,
    scored_profile.current_level,
    scored_profile.current_xp,
    scored_profile.current_points,
    scored_profile.posts_count,
    scored_profile.supports_received,
    scored_profile.comments_received,
    scored_profile.resolved_posts_count,
    scored_profile.ranking_score
  from scored_profiles scored_profile
  order by
    ranking_score desc,
    current_points desc,
    current_xp desc,
    created_at asc,
    profile_id asc
  limit greatest(1, least(coalesce(page_size, 50), 100))
  offset greatest(0, coalesce(page_offset, 0));
$$;

grant execute on function public.get_city_ranking(bigint, integer, integer) to anon;
grant execute on function public.get_city_ranking(bigint, integer, integer) to authenticated;
grant execute on function public.get_city_ranking(bigint, integer, integer) to service_role;
