alter table public.profiles
  add column if not exists featured_badge_id bigint references public.badges(id) on delete set null;

create index if not exists profiles_featured_badge_id_idx
  on public.profiles (featured_badge_id);

create table if not exists public.profile_followers (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint profile_followers_pkey primary key (follower_id, followed_id),
  constraint profile_followers_no_self_follow check (follower_id <> followed_id)
);

create index if not exists profile_followers_followed_id_idx
  on public.profile_followers (followed_id);

create index if not exists profile_followers_follower_id_idx
  on public.profile_followers (follower_id);

grant select on table public.badges to anon;
grant select on table public.badges to authenticated;
grant all on table public.badges to service_role;

grant select on table public.user_badges to anon;
grant select on table public.user_badges to authenticated;
grant all on table public.user_badges to service_role;

grant select on table public.profile_followers to anon;
grant select, insert, delete on table public.profile_followers to authenticated;
grant all on table public.profile_followers to service_role;

alter table public.profile_followers enable row level security;

drop policy if exists "Profile followers are viewable by everyone" on public.profile_followers;
create policy "Profile followers are viewable by everyone"
on public.profile_followers
for select
to anon, authenticated
using (true);

drop policy if exists "Users can follow from their own profile" on public.profile_followers;
create policy "Users can follow from their own profile"
on public.profile_followers
for insert
to authenticated
with check (auth.uid() = follower_id);

drop policy if exists "Users can unfollow from their own profile" on public.profile_followers;
create policy "Users can unfollow from their own profile"
on public.profile_followers
for delete
to authenticated
using (auth.uid() = follower_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-images',
  'profile-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Profile images are viewable by everyone" on storage.objects;
create policy "Profile images are viewable by everyone"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'profile-images');

drop policy if exists "Authenticated users can upload their own profile images" on storage.objects;
create policy "Authenticated users can upload their own profile images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can update their own profile images" on storage.objects;
create policy "Users can update their own profile images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can delete their own profile images" on storage.objects;
create policy "Users can delete their own profile images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
