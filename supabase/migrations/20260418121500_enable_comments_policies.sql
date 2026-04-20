grant select on table public.comments to anon;
grant select, insert, update, delete on table public.comments to authenticated;
grant all on table public.comments to service_role;

alter table public.comments enable row level security;

drop policy if exists "Comments are viewable by everyone" on public.comments;

create policy "Comments are viewable by everyone"
on public.comments
for select
to anon, authenticated
using (true);

drop policy if exists "Authenticated users can create their own comments" on public.comments;

create policy "Authenticated users can create their own comments"
on public.comments
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their own comments" on public.comments;

create policy "Users can update their own comments"
on public.comments
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own comments" on public.comments;

create policy "Users can delete their own comments"
on public.comments
for delete
to authenticated
using (auth.uid() = user_id);

create or replace function public.handle_post_comments_count()
returns trigger
language plpgsql
as $$
begin
    if tg_op = 'INSERT' then
        update public.posts
        set comments_count = comments_count + 1
        where id = new.post_id;
        return new;
    end if;

    if tg_op = 'DELETE' then
        update public.posts
        set comments_count = greatest(comments_count - 1, 0)
        where id = old.post_id;
        return old;
    end if;

    return null;
end;
$$;

drop trigger if exists update_post_comments_count on public.comments;

create trigger update_post_comments_count
after insert or delete on public.comments
for each row
execute function public.handle_post_comments_count();
