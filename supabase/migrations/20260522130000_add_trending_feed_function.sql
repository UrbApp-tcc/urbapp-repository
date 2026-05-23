create index if not exists post_status_history_post_id_created_at_desc_idx
  on public.post_status_history (post_id, created_at desc, id desc);

create or replace function public.get_trending_feed_posts(
  page_size integer default 20,
  page_offset integer default 0
)
returns table (
  id bigint,
  title text,
  description text,
  status public.report_status,
  created_at timestamptz,
  updated_at timestamptz,
  resolved_at timestamptz,
  latitude double precision,
  longitude double precision,
  city_id bigint,
  city_name text,
  category_id bigint,
  category_name text,
  agency_id bigint,
  agency_name text,
  supports_count integer,
  comments_count integer,
  is_anonymous boolean,
  author_id uuid,
  author_display_name text,
  author_username text,
  author_avatar_url text,
  image_count integer,
  primary_image_path text,
  images jsonb,
  trending_score bigint
)
language sql
stable
set search_path = public
as $$
  with follower_counts as (
    select
      profile_follower.followed_id as profile_id,
      count(*)::integer as followers_count
    from public.profile_followers profile_follower
    group by profile_follower.followed_id
  ),
  latest_status_mark as (
    select
      ranked_history.post_id,
      ranked_history.created_at as status_changed_at
    from (
      select
        history.post_id,
        history.created_at,
        row_number() over (
          partition by history.post_id
          order by history.created_at desc, history.id desc
        ) as row_number
      from public.post_status_history history
    ) ranked_history
    where ranked_history.row_number = 1
  ),
  scored_posts as (
    select
      post.id,
      coalesce(latest_status_mark.status_changed_at, post.created_at) as status_changed_at,
      (
        coalesce(post.supports_count, 0) * 18
        + coalesce(post.comments_count, 0) * 24
        + (coalesce(post.supports_count, 0) + coalesce(post.comments_count, 0)) * 6
        + coalesce(follower_counts.followers_count, 0) * 5
        + case post.status
            when 'open' then 80
            when 'in_analysis' then 90
            when 'in_progress' then 70
            when 'completed' then 30
            when 'closed' then 20
            when 'expired' then 10
            else 0
          end
        + floor(
            least(
              extract(
                epoch from (
                  now() - coalesce(latest_status_mark.status_changed_at, post.created_at)
                )
              ) / 3600.0,
              case
                when post.status in ('open', 'in_analysis') then 24 * 30
                when post.status = 'in_progress' then 24 * 21
                when post.status in ('completed', 'closed') then 24 * 7
                else 24 * 3
              end
            ) * case
              when post.status in ('open', 'in_analysis') then 0.90
              when post.status = 'in_progress' then 0.60
              when post.status in ('completed', 'closed') then 0.15
              else 0.08
            end
          )
      )::bigint as trending_score
    from public.posts post
    left join follower_counts
      on follower_counts.profile_id = post.user_id
    left join latest_status_mark
      on latest_status_mark.post_id = post.id
  )
  select
    post.id,
    post.title,
    post.description,
    post.status,
    post.created_at,
    post.updated_at,
    post.resolved_at,
    post.latitude,
    post.longitude,
    post.city_id,
    city.name as city_name,
    post.category_id,
    category.name as category_name,
    post.agency_id,
    agency.name as agency_name,
    post.supports_count,
    post.comments_count,
    post.anonymity as is_anonymous,
    case when post.anonymity then null else profile.id end as author_id,
    case
      when post.anonymity then 'Anonimo'
      else coalesce(nullif(profile.full_name, ''), profile.username)
    end as author_display_name,
    case when post.anonymity then null else profile.username end as author_username,
    case when post.anonymity then null else profile.avatar_url end as author_avatar_url,
    coalesce(image_data.image_count, 0) as image_count,
    image_data.primary_image_path,
    coalesce(image_data.images, '[]'::jsonb) as images,
    scored_post.trending_score
  from public.posts post
  join public.cities city
    on city.id = post.city_id
  left join public.problem_categories category
    on category.id = post.category_id
  left join public.public_agencies agency
    on agency.id = post.agency_id
  join public.profiles profile
    on profile.id = post.user_id
  join scored_posts scored_post
    on scored_post.id = post.id
  left join lateral (
    select
      count(*)::integer as image_count,
      (array_agg(image.storage_path order by image.position))[1] as primary_image_path,
      jsonb_agg(
        jsonb_build_object(
          'id', image.id,
          'storage_path', image.storage_path,
          'caption', image.caption,
          'position', image.position
        )
        order by image.position
      ) as images
    from public.post_images image
    where image.post_id = post.id
  ) image_data on true
  order by
    scored_post.trending_score desc,
    post.comments_count desc,
    post.supports_count desc,
    scored_post.status_changed_at asc,
    post.created_at desc,
    post.id desc
  limit greatest(1, least(coalesce(page_size, 20), 100))
  offset greatest(0, coalesce(page_offset, 0));
$$;

grant execute on function public.get_trending_feed_posts(integer, integer) to anon;
grant execute on function public.get_trending_feed_posts(integer, integer) to authenticated;
grant execute on function public.get_trending_feed_posts(integer, integer) to service_role;
