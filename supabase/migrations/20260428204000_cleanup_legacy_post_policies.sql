alter table public.posts enable row level security;
alter table public.post_status_history enable row level security;

drop policy if exists "Allow public read posts" on public.posts;
drop policy if exists "Permitir insert a todos" on public.posts;

revoke insert, update, delete, truncate, references, trigger
  on table public.posts
  from anon;

revoke delete, truncate, references, trigger
  on table public.posts
  from authenticated;

grant select on table public.posts to anon;
grant select, insert, update on table public.posts to authenticated;
grant all on table public.posts to service_role;

revoke insert, update, delete, truncate, references, trigger
  on table public.post_status_history
  from anon;

revoke update, delete, truncate, references, trigger
  on table public.post_status_history
  from authenticated;

grant select on table public.post_status_history to anon;
grant select, insert on table public.post_status_history to authenticated;
grant all on table public.post_status_history to service_role;
