-- Anonimato precisa ser garantido pelo backend, não apenas pela interface.

update public.post_status_history history
set changed_by = null
from public.posts post
where post.id = history.post_id
  and post.anonymity = true
  and history.changed_by = post.user_id;

update public.occurrence_events event
set actor_id = null
from public.posts post
where event.event_type = 'occurrence_created'
  and post.anonymity = true
  and event.actor_id = post.user_id
  and coalesce(
    event.metadata ->> 'post_id',
    event.metadata ->> 'legacy_post_id'
  ) = post.id::text;

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
) image_data on true
where post.hidden_at is null
   or post.user_id = auth.uid()
   or public.is_platform_admin(auth.uid());

revoke select on table public.posts from anon, authenticated;

grant select (
  id,
  created_at,
  city_id,
  likes,
  description,
  status,
  latitude,
  longitude,
  anonymity,
  title,
  category_id,
  agency_id,
  supports_count,
  comments_count,
  updated_at,
  resolved_at,
  street,
  neighborhood,
  occurrence_id,
  hidden_at
) on table public.posts to anon, authenticated;

grant select on public.post_feed_rows to anon, authenticated;

drop policy if exists "Authenticated users can upload their own post images"
  on storage.objects;
create policy "Authenticated users can upload their own post images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'post-images'
  and (owner = auth.uid() or owner_id = auth.uid()::text)
);

drop policy if exists "Users can update their own post images in storage"
  on storage.objects;
create policy "Users can update their own post images in storage"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'post-images'
  and (owner = auth.uid() or owner_id = auth.uid()::text)
)
with check (
  bucket_id = 'post-images'
  and (owner = auth.uid() or owner_id = auth.uid()::text)
);

drop policy if exists "Users can delete their own post images in storage"
  on storage.objects;
create policy "Users can delete their own post images in storage"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'post-images'
  and (owner = auth.uid() or owner_id = auth.uid()::text)
);

notify pgrst, 'reload schema';
