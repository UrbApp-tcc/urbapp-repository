create index if not exists posts_created_at_desc_idx
    on public.posts (created_at desc, id desc);

grant select on table public.public_agencies to anon;
grant select on table public.public_agencies to authenticated;
grant all on table public.public_agencies to service_role;

create or replace function public.get_feed_posts(
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
    images jsonb
)
language sql
stable
set search_path = public
as $$
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
        coalesce(image_data.images, '[]'::jsonb) as images
    from public.posts post
    join public.cities city
        on city.id = post.city_id
    left join public.problem_categories category
        on category.id = post.category_id
    left join public.public_agencies agency
        on agency.id = post.agency_id
    join public.profiles profile
        on profile.id = post.user_id
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
    order by post.created_at desc, post.id desc
    limit greatest(1, least(coalesce(page_size, 20), 100))
    offset greatest(0, coalesce(page_offset, 0));
$$;

grant execute on function public.get_feed_posts(integer, integer) to anon;
grant execute on function public.get_feed_posts(integer, integer) to authenticated;
grant execute on function public.get_feed_posts(integer, integer) to service_role;
