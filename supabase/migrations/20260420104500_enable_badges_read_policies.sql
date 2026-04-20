grant select on table public.badges to anon;
grant select on table public.badges to authenticated;
grant all on table public.badges to service_role;

grant select on table public.user_badges to anon;
grant select on table public.user_badges to authenticated;
grant all on table public.user_badges to service_role;

alter table public.badges enable row level security;
alter table public.user_badges enable row level security;

drop policy if exists "Badges are viewable by everyone" on public.badges;
create policy "Badges are viewable by everyone"
on public.badges
for select
to anon, authenticated
using (true);

drop policy if exists "User badges are viewable by everyone" on public.user_badges;
create policy "User badges are viewable by everyone"
on public.user_badges
for select
to anon, authenticated
using (true);
