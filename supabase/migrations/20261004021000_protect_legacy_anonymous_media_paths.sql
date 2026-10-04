-- Caminhos antigos de mídia continham o UUID do autor. Em relatos anônimos,
-- eles ficam privados até serem migrados para o novo padrão sem identificador.

drop policy if exists "Post images are viewable by everyone" on public.post_images;
create policy "Post images preserve anonymous authors"
on public.post_images
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.posts post
    where post.id = post_images.post_id
      and (
        not post.anonymity
        or post.user_id = auth.uid()
        or public.is_platform_admin(auth.uid())
        or position(post.user_id::text in post_images.storage_path) = 0
      )
  )
);

create or replace view public.post_feed_rows
with (security_barrier = true)
as
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
  post.street,
  post.neighborhood,
  post.category_id,
  post.agency_id,
  post.occurrence_id,
  post.supports_count,
  post.comments_count,
  post.anonymity as is_anonymous,
  case
    when not post.anonymity
      or post.user_id = auth.uid()
      or public.is_platform_admin(auth.uid())
    then post.user_id
    else null
  end as author_id,
  case
    when post.anonymity
      and post.user_id is distinct from auth.uid()
      and not public.is_platform_admin(auth.uid())
    then 'Anônimo'
    else coalesce(nullif(profile.full_name, ''), profile.username)
  end as author_display_name,
  case
    when post.anonymity
      and post.user_id is distinct from auth.uid()
      and not public.is_platform_admin(auth.uid())
    then null
    else profile.username
  end as author_username,
  case
    when post.anonymity
      and post.user_id is distinct from auth.uid()
      and not public.is_platform_admin(auth.uid())
    then null
    else profile.avatar_url
  end as author_avatar_url,
  city.name as city_name,
  category.name as category_name,
  agency.name as agency_name,
  coalesce(image_data.image_count, 0) as image_count,
  image_data.primary_image_path,
  coalesce(image_data.images, '[]'::jsonb) as images
from public.posts post
join public.cities city on city.id = post.city_id
join public.problem_categories category on category.id = post.category_id
left join public.public_agencies agency on agency.id = post.agency_id
join public.profiles profile on profile.id = post.user_id
left join lateral (
  select
    count(*)::integer as image_count,
    (array_agg(image.storage_path order by image.position, image.id))[1]
      as primary_image_path,
    jsonb_agg(
      jsonb_build_object(
        'id', image.id,
        'storage_path', image.storage_path,
        'caption', image.caption,
        'position', image.position
      )
      order by image.position, image.id
    ) as images
  from public.post_images image
  where image.post_id = post.id
    and (
      not post.anonymity
      or post.user_id = auth.uid()
      or public.is_platform_admin(auth.uid())
      or position(post.user_id::text in image.storage_path) = 0
    )
) image_data on true
where post.hidden_at is null
   or post.user_id = auth.uid()
   or public.is_platform_admin(auth.uid());

grant select on public.post_feed_rows to anon, authenticated;

notify pgrst, 'reload schema';
