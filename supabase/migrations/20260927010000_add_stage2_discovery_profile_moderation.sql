-- Etapa 2: busca por endereco, biografia e denuncias de conteudo.

alter table public.posts
  add column if not exists street text,
  add column if not exists neighborhood text;

create index if not exists posts_city_created_at_idx
  on public.posts (city_id, created_at desc, id desc);

create index if not exists posts_neighborhood_search_idx
  on public.posts (lower(neighborhood));

alter table public.profiles
  add column if not exists biography text;

alter table public.profiles
  drop constraint if exists profiles_biography_length_check;

alter table public.profiles
  add constraint profiles_biography_length_check
  check (biography is null or char_length(biography) <= 240);

alter table public.moderation_reports enable row level security;

grant insert, select on table public.moderation_reports to authenticated;
grant all on table public.moderation_reports to service_role;

drop policy if exists "Users can create moderation reports" on public.moderation_reports;
create policy "Users can create moderation reports"
on public.moderation_reports
for insert
to authenticated
with check (
  reporter_user_id = auth.uid()
  and target_type = 'post'
  and char_length(trim(reason)) between 3 and 500
);

drop policy if exists "Users can view their moderation reports" on public.moderation_reports;
create policy "Users can view their moderation reports"
on public.moderation_reports
for select
to authenticated
using (reporter_user_id = auth.uid());

create unique index if not exists moderation_reports_unique_post_reporter_idx
  on public.moderation_reports (reporter_user_id, target_type, target_id)
  where target_type = 'post';

create index if not exists moderation_reports_status_created_at_idx
  on public.moderation_reports (status, created_at desc);
