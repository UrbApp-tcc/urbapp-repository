create table if not exists public.comment_likes (
  comment_id bigint not null references public.comments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint comment_likes_pkey primary key (comment_id, user_id)
);

create index if not exists comment_likes_user_id_idx
  on public.comment_likes (user_id);

create index if not exists comment_likes_comment_id_idx
  on public.comment_likes (comment_id);

grant select on table public.comment_likes to anon;
grant select, insert, delete on table public.comment_likes to authenticated;
grant all on table public.comment_likes to service_role;

alter table public.comment_likes enable row level security;

drop policy if exists "Comment likes are viewable by everyone" on public.comment_likes;
create policy "Comment likes are viewable by everyone"
on public.comment_likes
for select
to anon, authenticated
using (true);

drop policy if exists "Authenticated users can insert their own comment like" on public.comment_likes;
create policy "Authenticated users can insert their own comment like"
on public.comment_likes
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own comment like" on public.comment_likes;
create policy "Users can delete their own comment like"
on public.comment_likes
for delete
to authenticated
using (auth.uid() = user_id);

create or replace function public.sync_comment_likes_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.comments
       set likes = coalesce(likes, 0) + 1
     where id = new.comment_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.comments
       set likes = greatest(0, coalesce(likes, 0) - 1)
     where id = old.comment_id;
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_comment_likes_count_sync on public.comment_likes;
create trigger trg_comment_likes_count_sync
after insert or delete on public.comment_likes
for each row
execute function public.sync_comment_likes_count();

update public.comments c
set likes = coalesce(src.cnt, 0)
from (
  select comment_id, count(*)::bigint as cnt
  from public.comment_likes
  group by comment_id
) src
where c.id = src.comment_id;

update public.comments
set likes = 0
where likes is null;
