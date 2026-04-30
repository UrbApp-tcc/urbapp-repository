create index if not exists agency_users_user_id_agency_id_idx
  on public.agency_users (user_id, agency_id)
  where is_active = true;

grant select on table public.agency_users to authenticated;
grant all on table public.agency_users to service_role;

alter table public.agency_users enable row level security;

drop policy if exists "Agency users can view their own memberships" on public.agency_users;
create policy "Agency users can view their own memberships"
on public.agency_users
for select
to authenticated
using (auth.uid() = user_id);

create or replace function public.handle_post_resolved_timestamp()
returns trigger
language plpgsql
as $$
begin
  if new.status in ('completed', 'closed') then
    if old.status is distinct from new.status then
      new.resolved_at := coalesce(new.resolved_at, now());
    end if;
  elsif old.status is distinct from new.status then
    new.resolved_at := null;
  end if;

  if old.status is distinct from new.status then
    new.updated_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists set_post_resolved_timestamp on public.posts;
create trigger set_post_resolved_timestamp
before update on public.posts
for each row
execute function public.handle_post_resolved_timestamp();

grant update on table public.posts to authenticated;

drop policy if exists "Agency members can update posts assigned to their agency" on public.posts;
create policy "Agency members can update posts assigned to their agency"
on public.posts
for update
to authenticated
using (
  agency_id is not null
  and exists (
    select 1
    from public.agency_users agency_user
    where agency_user.agency_id = posts.agency_id
      and agency_user.user_id = auth.uid()
      and agency_user.is_active = true
  )
)
with check (
  agency_id is not null
  and exists (
    select 1
    from public.agency_users agency_user
    where agency_user.agency_id = posts.agency_id
      and agency_user.user_id = auth.uid()
      and agency_user.is_active = true
  )
);

drop policy if exists "Authenticated users can create their own post status history" on public.post_status_history;
drop policy if exists "Agency members can create status history for assigned posts" on public.post_status_history;
create policy "Users can create status history for owned or managed posts"
on public.post_status_history
for insert
to authenticated
with check (
  auth.uid() = changed_by
  and exists (
    select 1
    from public.posts post
    where post.id = post_status_history.post_id
      and (
        post.user_id = auth.uid()
        or exists (
          select 1
          from public.agency_users agency_user
          where agency_user.agency_id = post.agency_id
            and agency_user.user_id = auth.uid()
            and agency_user.is_active = true
        )
      )
  )
);

revoke update on table public.profiles from authenticated;
grant update (full_name, username, avatar_url, city_id, featured_badge_id)
  on table public.profiles
  to authenticated;
