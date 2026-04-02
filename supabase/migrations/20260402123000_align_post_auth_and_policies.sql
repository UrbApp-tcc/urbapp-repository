grant select on table public.profiles to anon;
grant select, insert, update on table public.profiles to authenticated;
grant all on table public.profiles to service_role;

grant select on table public.problem_categories to anon;
grant select on table public.problem_categories to authenticated;
grant all on table public.problem_categories to service_role;

alter table public.posts drop constraint if exists posts_user_fkey;

alter table public.posts
    rename column user_id to legacy_user_id;

alter table public.posts
    add column user_id uuid;

update public.posts post
set user_id = profile.id
from public.profiles profile
where profile.legacy_user_id = post.legacy_user_id;

alter table public.posts
    add constraint posts_user_id_fkey
    foreign key (user_id) references public.profiles(id) on delete cascade;

create index if not exists posts_user_id_idx on public.posts (user_id);

do $$
begin
    if not exists (
        select 1
        from public.posts
        where user_id is null
    ) then
        alter table public.posts
            alter column user_id set not null;
    end if;
end;
$$;

alter table public.post_status_history drop constraint if exists post_status_history_changed_by_fkey;

alter table public.post_status_history
    rename column changed_by to legacy_changed_by;

alter table public.post_status_history
    add column changed_by uuid;

update public.post_status_history history
set changed_by = profile.id
from public.profiles profile
where profile.legacy_user_id = history.legacy_changed_by;

alter table public.post_status_history
    add constraint post_status_history_changed_by_fkey
    foreign key (changed_by) references public.profiles(id) on delete set null;

create index if not exists post_status_history_changed_by_idx
    on public.post_status_history (changed_by);

grant select on table public.post_status_history to anon;
grant select, insert on table public.post_status_history to authenticated;
grant all on table public.post_status_history to service_role;

alter table public.post_status_history enable row level security;

grant select on table public.post_images to anon;
grant select, insert, update, delete on table public.post_images to authenticated;
grant all on table public.post_images to service_role;

alter table public.post_images enable row level security;

drop policy if exists "Cities are viewable by everyone" on public.cities;

create policy "Cities are viewable by everyone"
on public.cities
for select
to anon, authenticated
using (true);

drop policy if exists "Posts are viewable by everyone" on public.posts;

create policy "Posts are viewable by everyone"
on public.posts
for select
to anon, authenticated
using (true);

drop policy if exists "Authenticated users can create their own posts" on public.posts;

create policy "Authenticated users can create their own posts"
on public.posts
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their own posts" on public.posts;

create policy "Users can update their own posts"
on public.posts
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Status history is viewable by everyone" on public.post_status_history;

create policy "Status history is viewable by everyone"
on public.post_status_history
for select
to anon, authenticated
using (true);

drop policy if exists "Authenticated users can create their own post status history" on public.post_status_history;

create policy "Authenticated users can create their own post status history"
on public.post_status_history
for insert
to authenticated
with check (auth.uid() = changed_by);

drop policy if exists "Post images are viewable by everyone" on public.post_images;

create policy "Post images are viewable by everyone"
on public.post_images
for select
to anon, authenticated
using (true);

drop policy if exists "Authenticated users can create images for their own posts" on public.post_images;

create policy "Authenticated users can create images for their own posts"
on public.post_images
for insert
to authenticated
with check (
    exists (
        select 1
        from public.posts post
        where post.id = post_images.post_id
          and post.user_id = auth.uid()
    )
);

drop policy if exists "Users can update images from their own posts" on public.post_images;

create policy "Users can update images from their own posts"
on public.post_images
for update
to authenticated
using (
    exists (
        select 1
        from public.posts post
        where post.id = post_images.post_id
          and post.user_id = auth.uid()
    )
)
with check (
    exists (
        select 1
        from public.posts post
        where post.id = post_images.post_id
          and post.user_id = auth.uid()
    )
);

drop policy if exists "Users can delete images from their own posts" on public.post_images;

create policy "Users can delete images from their own posts"
on public.post_images
for delete
to authenticated
using (
    exists (
        select 1
        from public.posts post
        where post.id = post_images.post_id
          and post.user_id = auth.uid()
    )
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'post-images',
    'post-images',
    true,
    5242880,
    array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Post images in storage are viewable by everyone" on storage.objects;

create policy "Post images in storage are viewable by everyone"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'post-images');

drop policy if exists "Authenticated users can upload their own post images" on storage.objects;

create policy "Authenticated users can upload their own post images"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can update their own post images in storage" on storage.objects;

create policy "Users can update their own post images in storage"
on storage.objects
for update
to authenticated
using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can delete their own post images in storage" on storage.objects;

create policy "Users can delete their own post images in storage"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
);
