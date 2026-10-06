-- UrbApp: camada social no nível da ocorrência (spec §20, §29.2).
--
-- Antes: apoios (`post_supports`) e comentários (`comments.post_id`) ficavam presos
-- a cada relato. Uma ocorrência com N relatos tinha apoios e conversas
-- fragmentados e aparecia N vezes no feed.
-- Agora:
-- * apoios pertencem à ocorrência (`occurrence_supports`), um por usuário;
-- * comentários pertencem à ocorrência (`comments.occurrence_id`);
-- * o feed, a busca e o "Em alta" listam ocorrências únicas (`occurrence_feed_rows`).
-- Contadores são derivados (não editáveis) para evitar divergência.

-- ---------------------------------------------------------------------------
-- Funções auxiliares (não expostas ao cliente)
-- ---------------------------------------------------------------------------

create or replace function public.occurrence_initiator_id(target_occurrence_id bigint)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select post.user_id
  from public.posts post
  where post.occurrence_id = target_occurrence_id
    and post.hidden_at is null
  order by post.created_at, post.id
  limit 1;
$$;

create or replace function public.is_occurrence_contributor(
  target_occurrence_id bigint,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.posts post
    where post.occurrence_id = target_occurrence_id
      and post.user_id = target_user_id
  );
$$;

create or replace function public.occurrence_accepts_interaction(target_occurrence_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.occurrences occurrence
    where occurrence.id = target_occurrence_id
      and occurrence.invalidated_at is null
      and occurrence.merged_into_occurrence_id is null
      and occurrence.status <> 'closed'
  );
$$;

revoke all on function public.occurrence_initiator_id(bigint) from public, anon, authenticated;
revoke all on function public.is_occurrence_contributor(bigint, uuid) from public, anon;
revoke all on function public.occurrence_accepts_interaction(bigint) from public, anon;
grant execute on function public.is_occurrence_contributor(bigint, uuid) to authenticated;
grant execute on function public.occurrence_accepts_interaction(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Preferências de notificação (Perfil → Configurações → Preferências de alertas)
-- ---------------------------------------------------------------------------

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  occurrence_updates boolean not null default true,
  comments boolean not null default true,
  official_updates boolean not null default true,
  validations boolean not null default true,
  councilor_activity boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "Users manage their notification preferences" on public.notification_preferences;
create policy "Users manage their notification preferences"
on public.notification_preferences for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

grant select on public.notification_preferences to authenticated;
grant insert (user_id, occurrence_updates, comments, official_updates, validations, councilor_activity)
  on public.notification_preferences to authenticated;
grant update (occurrence_updates, comments, official_updates, validations, councilor_activity)
  on public.notification_preferences to authenticated;
grant all on public.notification_preferences to service_role;

drop trigger if exists set_notification_preferences_updated_at on public.notification_preferences;
create trigger set_notification_preferences_updated_at
before update on public.notification_preferences
for each row execute function public.set_updated_at();

create or replace function public.notification_allowed(target_user_id uuid, category text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case category
        when 'occurrence_updates' then preference.occurrence_updates
        when 'comments' then preference.comments
        when 'official_updates' then preference.official_updates
        when 'validations' then preference.validations
        when 'councilor_activity' then preference.councilor_activity
        else true
      end
      from public.notification_preferences preference
      where preference.user_id = target_user_id
    ),
    true
  );
$$;

revoke all on function public.notification_allowed(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Apoios da ocorrência
-- ---------------------------------------------------------------------------

create table if not exists public.occurrence_supports (
  occurrence_id bigint not null references public.occurrences(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (occurrence_id, user_id)
);

create index if not exists occurrence_supports_user_idx
  on public.occurrence_supports (user_id, created_at desc);
create index if not exists occurrence_supports_recent_idx
  on public.occurrence_supports (occurrence_id, created_at desc);

-- Preserva os apoios legados uma única vez por ocorrência (sem disparar gatilhos).
insert into public.occurrence_supports (occurrence_id, user_id, created_at)
select post.occurrence_id, support.user_id, min(support.created_at)
from public.post_supports support
join public.posts post on post.id = support.post_id
where post.occurrence_id is not null
group by post.occurrence_id, support.user_id
on conflict do nothing;

alter table public.occurrence_supports enable row level security;

drop policy if exists "Occurrence supports are public" on public.occurrence_supports;
create policy "Occurrence supports are public"
on public.occurrence_supports for select to anon, authenticated using (true);

drop policy if exists "Users support occurrences of other citizens" on public.occurrence_supports;
create policy "Users support occurrences of other citizens"
on public.occurrence_supports for insert to authenticated
with check (
  user_id = auth.uid()
  and public.occurrence_accepts_interaction(occurrence_id)
  and not public.is_occurrence_contributor(occurrence_id, auth.uid())
  and exists (
    select 1
    from public.occurrences occurrence
    where occurrence.id = occurrence_id
      and occurrence.status <> 'completed'
  )
);

drop policy if exists "Users remove their support" on public.occurrence_supports;
create policy "Users remove their support"
on public.occurrence_supports for delete to authenticated
using (user_id = auth.uid());

grant select on public.occurrence_supports to anon, authenticated;
grant insert (occurrence_id, user_id) on public.occurrence_supports to authenticated;
grant delete on public.occurrence_supports to authenticated;
grant all on public.occurrence_supports to service_role;

-- O apoio legado por relato fica somente leitura.
drop policy if exists "Authenticated users can insert their own post support" on public.post_supports;
drop policy if exists "Users can delete their own post support" on public.post_supports;

create or replace function public.handle_occurrence_support_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  initiator_id uuid := public.occurrence_initiator_id(new.occurrence_id);
  target_title text;
begin
  perform public.award_xp(
    new.user_id,
    public.xp_value('support_given'),
    'support_given',
    new.occurrence_id
  );

  if initiator_id is null or initiator_id = new.user_id then
    return new;
  end if;

  perform public.award_points(
    initiator_id,
    public.points_value('support_received'),
    'support_received:' || new.user_id::text,
    new.occurrence_id,
    false
  );

  if public.notification_allowed(initiator_id, 'occurrence_updates') then
    select occurrence.title into target_title
    from public.occurrences occurrence
    where occurrence.id = new.occurrence_id;

    perform public.notify_user(
      initiator_id,
      'occurrence_support',
      'Sua ocorrência recebeu apoio',
      target_title,
      jsonb_build_object('occurrence_id', new.occurrence_id)
    );
  end if;

  return new;
end;
$$;

drop trigger if exists on_occurrence_support_created on public.occurrence_supports;
create trigger on_occurrence_support_created
after insert on public.occurrence_supports
for each row execute function public.handle_occurrence_support_created();

-- ---------------------------------------------------------------------------
-- Comentários da ocorrência
-- ---------------------------------------------------------------------------

alter table public.comments
  add column if not exists occurrence_id bigint references public.occurrences(id) on delete cascade,
  add column if not exists hidden_at timestamptz,
  add column if not exists hidden_reason text;

update public.comments comment
set occurrence_id = post.occurrence_id
from public.posts post
where post.id = comment.post_id
  and comment.occurrence_id is null;

alter table public.comments alter column post_id drop not null;

alter table public.comments drop constraint if exists comments_occurrence_required_check;
alter table public.comments
  add constraint comments_occurrence_required_check
  check (occurrence_id is not null) not valid;

alter table public.comments drop constraint if exists comments_body_length_check;
alter table public.comments
  add constraint comments_body_length_check
  check (char_length(trim(body)) between 1 and 1000) not valid;

create index if not exists comments_occurrence_created_idx
  on public.comments (occurrence_id, created_at, id);

drop trigger if exists update_post_comments_count on public.comments;
drop trigger if exists notify_on_post_comment on public.comments;
drop trigger if exists points_on_comment_received on public.comments;

create or replace function public.prepare_occurrence_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_comment public.comments%rowtype;
begin
  new.user_id := auth.uid();
  new.body := trim(new.body);
  new.likes := 0;
  new.post_id := null;
  new.hidden_at := null;
  new.hidden_reason := null;

  if new.parent_comment_id is not null then
    select * into parent_comment
    from public.comments comment
    where comment.id = new.parent_comment_id;

    if not found or parent_comment.occurrence_id is distinct from new.occurrence_id then
      raise exception 'Resposta deve pertencer à mesma ocorrência.';
    end if;

    -- As respostas ficam em um único nível, como na conversa aprovada.
    new.parent_comment_id := coalesce(parent_comment.parent_comment_id, parent_comment.id);
  end if;

  return new;
end;
$$;

drop trigger if exists prepare_occurrence_comment_before_insert on public.comments;
create trigger prepare_occurrence_comment_before_insert
before insert on public.comments
for each row
when (current_user not in ('postgres', 'service_role', 'supabase_admin'))
execute function public.prepare_occurrence_comment();

create or replace function public.handle_occurrence_comment_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  initiator_id uuid := public.occurrence_initiator_id(new.occurrence_id);
  parent_author_id uuid;
  target_title text;
begin
  select occurrence.title into target_title
  from public.occurrences occurrence
  where occurrence.id = new.occurrence_id;

  if new.parent_comment_id is not null then
    select comment.user_id into parent_author_id
    from public.comments comment
    where comment.id = new.parent_comment_id;

    if parent_author_id is not null
       and parent_author_id <> new.user_id
       and public.notification_allowed(parent_author_id, 'comments') then
      perform public.notify_user(
        parent_author_id,
        'comment_reply',
        'Nova resposta ao seu comentário',
        left(new.body, 180),
        jsonb_build_object(
          'occurrence_id', new.occurrence_id,
          'comment_id', new.id,
          'occurrence_title', target_title
        )
      );
    end if;
  end if;

  if initiator_id is null or initiator_id = new.user_id then
    return new;
  end if;

  perform public.award_points(
    initiator_id,
    public.points_value('comment_received'),
    'comment_received:' || new.user_id::text,
    new.occurrence_id,
    false
  );

  if initiator_id is distinct from parent_author_id
     and public.notification_allowed(initiator_id, 'comments') then
    perform public.notify_user(
      initiator_id,
      'occurrence_comment',
      'Novo comentário na sua ocorrência',
      left(new.body, 180),
      jsonb_build_object(
        'occurrence_id', new.occurrence_id,
        'comment_id', new.id,
        'occurrence_title', target_title
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists on_occurrence_comment_created on public.comments;
create trigger on_occurrence_comment_created
after insert on public.comments
for each row
when (new.occurrence_id is not null)
execute function public.handle_occurrence_comment_created();

drop policy if exists "Authenticated users can create their own comments" on public.comments;
drop policy if exists "Users comment on active occurrences" on public.comments;
create policy "Users comment on active occurrences"
on public.comments for insert to authenticated
with check (
  user_id = auth.uid()
  and occurrence_id is not null
  and public.occurrence_accepts_interaction(occurrence_id)
);

drop policy if exists "Comments are viewable by everyone" on public.comments;
drop policy if exists "Visible comments are public" on public.comments;
create policy "Visible comments are public"
on public.comments for select to anon, authenticated
using (
  hidden_at is null
  or user_id = auth.uid()
  or public.is_platform_admin(auth.uid())
);

grant select on public.comments to anon, authenticated;
grant insert (occurrence_id, body, parent_comment_id, user_id) on public.comments to authenticated;
grant update (body) on public.comments to authenticated;
grant delete on public.comments to authenticated;

-- ---------------------------------------------------------------------------
-- Leituras públicas da ocorrência
-- ---------------------------------------------------------------------------

create or replace view public.occurrence_feed_rows
with (security_barrier = true)
as
select
  occurrence.id,
  occurrence.title,
  occurrence.summary,
  occurrence.status,
  occurrence.previous_operational_status,
  occurrence.created_at,
  occurrence.updated_at,
  occurrence.resolved_at,
  occurrence.latitude,
  occurrence.longitude,
  occurrence.street,
  occurrence.neighborhood,
  occurrence.city_id,
  city.name as city_name,
  city.state as city_state,
  occurrence.category_id,
  category.name as category_name,
  category.slug as category_slug,
  occurrence.agency_id,
  agency.name as agency_name,
  agency.type as agency_type,
  agency.profile_status as agency_profile_status,
  occurrence.administration_id,
  occurrence.jurisdiction_type,
  occurrence.external_responsible_name,
  occurrence.administrative_priority,
  coalesce(report_data.reports_count, 0) as reports_count,
  coalesce(support_data.supports_count, 0) as supports_count,
  coalesce(support_data.recent_supports_count, 0) as recent_supports_count,
  coalesce(comment_data.comments_count, 0) as comments_count,
  coalesce(report_data.recent_reports_count, 0) as recent_reports_count,
  coalesce(image_data.image_count, 0) as image_count,
  image_data.primary_image_path,
  exists (
    select 1 from public.occurrence_supports support
    where support.occurrence_id = occurrence.id
      and support.user_id = auth.uid()
  ) as supported_by_me,
  exists (
    select 1 from public.occurrence_followers follower
    where follower.occurrence_id = occurrence.id
      and follower.user_id = auth.uid()
  ) as followed_by_me,
  coalesce(public.is_occurrence_contributor(occurrence.id, auth.uid()), false) as contributed_by_me,
  official.latest_official_action,
  greatest(occurrence.updated_at, coalesce(event_data.last_event_at, occurrence.created_at))
    as last_activity_at
from public.occurrences occurrence
join public.cities city on city.id = occurrence.city_id
join public.problem_categories category on category.id = occurrence.category_id
left join public.public_agencies agency on agency.id = occurrence.agency_id
left join lateral (
  select
    count(*)::integer as reports_count,
    count(*) filter (where post.created_at > now() - interval '24 hours')::integer
      as recent_reports_count
  from public.posts post
  where post.occurrence_id = occurrence.id
    and post.hidden_at is null
) report_data on true
left join lateral (
  select
    count(*)::integer as supports_count,
    count(*) filter (where support.created_at > now() - interval '24 hours')::integer
      as recent_supports_count
  from public.occurrence_supports support
  where support.occurrence_id = occurrence.id
) support_data on true
left join lateral (
  select count(*)::integer as comments_count
  from public.comments comment
  where comment.occurrence_id = occurrence.id
    and comment.hidden_at is null
) comment_data on true
left join lateral (
  select
    count(*)::integer as image_count,
    (array_agg(image.storage_path order by post.created_at, post.id, image.position, image.id))[1]
      as primary_image_path
  from public.posts post
  join public.post_images image on image.post_id = post.id
  where post.occurrence_id = occurrence.id
    and post.hidden_at is null
    and (not post.anonymity or position(post.user_id::text in image.storage_path) = 0)
) image_data on true
left join lateral (
  select jsonb_build_object(
    'actor_kind', action.actor_kind,
    'action_type', action.action_type,
    'description', action.description,
    'created_at', action.created_at,
    'agency_name', acting_agency.name,
    'agency_profile_status', acting_agency.profile_status
  ) as latest_official_action
  from public.institutional_actions action
  left join public.public_agencies acting_agency on acting_agency.id = action.agency_id
  where action.occurrence_id = occurrence.id
  order by action.created_at desc, action.id desc
  limit 1
) official on true
left join lateral (
  select max(event.created_at) as last_event_at
  from public.occurrence_events event
  where event.occurrence_id = occurrence.id
) event_data on true
where occurrence.invalidated_at is null
  and occurrence.merged_into_occurrence_id is null;

grant select on public.occurrence_feed_rows to anon, authenticated;

-- Comentários com identidade pública do autor (comentários nunca são anônimos).
create or replace view public.occurrence_comment_rows
with (security_barrier = true)
as
select
  comment.id,
  comment.occurrence_id,
  comment.parent_comment_id,
  comment.body,
  comment.created_at,
  comment.updated_at,
  comment.user_id as author_id,
  coalesce(nullif(profile.full_name, ''), profile.username) as author_display_name,
  profile.username as author_username,
  profile.avatar_url as author_avatar_url,
  (select count(*)::integer from public.comment_likes liked where liked.comment_id = comment.id)
    as likes_count,
  exists (
    select 1 from public.comment_likes liked
    where liked.comment_id = comment.id and liked.user_id = auth.uid()
  ) as liked_by_me
from public.comments comment
join public.profiles profile on profile.id = comment.user_id
where comment.occurrence_id is not null
  and (
    comment.hidden_at is null
    or comment.user_id = auth.uid()
    or public.is_platform_admin(auth.uid())
  );

grant select on public.occurrence_comment_rows to anon, authenticated;

-- "Em alta" (spec §20): apoios, comentários, crescimento recente, tempo sem
-- solução e quantidade de cidadãos mobilizados. Ocorrências resolvidas ou
-- encerradas não entram, pois não precisam mais de mobilização.
create or replace function public.get_trending_occurrences(
  target_city_id bigint default null,
  page_size integer default 20,
  page_offset integer default 0
)
returns setof public.occurrence_feed_rows
language sql
stable
set search_path = public
as $$
  select feed.*
  from public.occurrence_feed_rows feed
  where (target_city_id is null or feed.city_id = target_city_id)
    and feed.status not in ('completed', 'closed')
  order by
    (
      feed.supports_count * 3
      + feed.comments_count * 2
      + feed.reports_count * 5
      + feed.recent_supports_count * 6
      + feed.recent_reports_count * 8
      + least(extract(epoch from now() - feed.created_at) / 86400, 30)
      + case when feed.last_activity_at > now() - interval '48 hours' then 10 else 0 end
    ) desc,
    feed.created_at desc,
    feed.id desc
  limit least(greatest(coalesce(page_size, 20), 1), 100)
  offset greatest(coalesce(page_offset, 0), 0);
$$;

-- Busca server-side por texto, categoria, status, região e distância.
create or replace function public.search_occurrences(
  search_text text default null,
  target_city_id bigint default null,
  target_category_id bigint default null,
  target_status text default null,
  neighborhood_text text default null,
  origin_latitude double precision default null,
  origin_longitude double precision default null,
  maximum_distance_km numeric default null,
  page_size integer default 30,
  page_offset integer default 0
)
returns setof public.occurrence_feed_rows
language plpgsql
stable
set search_path = public
as $$
declare
  terms text[] := array_remove(
    regexp_split_to_array(lower(trim(coalesce(search_text, ''))), '\s+'),
    ''
  );
begin
  return query
  select feed.*
  from public.occurrence_feed_rows feed
  where (target_city_id is null or feed.city_id = target_city_id)
    and (target_category_id is null or feed.category_id = target_category_id)
    and (target_status is null or feed.status::text = target_status)
    and (
      nullif(trim(coalesce(neighborhood_text, '')), '') is null
      or coalesce(feed.neighborhood, '') ilike '%' || trim(neighborhood_text) || '%'
      or coalesce(feed.street, '') ilike '%' || trim(neighborhood_text) || '%'
    )
    and (
      maximum_distance_km is null
      or origin_latitude is null
      or origin_longitude is null
      or public.distance_km(origin_latitude, origin_longitude, feed.latitude, feed.longitude)
         <= maximum_distance_km
    )
    and (
      coalesce(array_length(terms, 1), 0) = 0
      or not exists (
        select 1
        from unnest(terms) term
        where lower(
          concat_ws(' ',
            feed.title, feed.summary, feed.street, feed.neighborhood,
            feed.category_name, feed.agency_name, feed.city_name
          )
        ) not like '%' || term || '%'
      )
    )
  order by
    case
      when origin_latitude is not null and origin_longitude is not null
           and coalesce(array_length(terms, 1), 0) = 0
      then public.distance_km(origin_latitude, origin_longitude, feed.latitude, feed.longitude)
    end asc nulls last,
    feed.created_at desc,
    feed.id desc
  limit least(greatest(coalesce(page_size, 30), 1), 200)
  offset greatest(coalesce(page_offset, 0), 0);
end;
$$;

revoke all on function public.get_trending_occurrences(bigint, integer, integer) from public;
revoke all on function public.search_occurrences(text, bigint, bigint, text, text, double precision, double precision, numeric, integer, integer) from public;
grant execute on function public.get_trending_occurrences(bigint, integer, integer) to anon, authenticated;
grant execute on function public.search_occurrences(text, bigint, bigint, text, text, double precision, double precision, numeric, integer, integer) to anon, authenticated;

-- O feed legado por relato deixa de ser a porta de entrada; continua disponível
-- para a lista de relatos de uma ocorrência via `post_feed_rows`.
drop function if exists public.get_feed_posts(integer, integer);
drop function if exists public.get_trending_feed_posts(integer, integer);

-- ---------------------------------------------------------------------------
-- Notificações de eventos respeitam as preferências do usuário.
-- ---------------------------------------------------------------------------

create or replace function public.notify_occurrence_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient record;
  notification_title text;
  notification_category text;
begin
  -- `status_changed` acompanha eventos de negócio que já notificam a mudança.
  if new.event_type in ('occurrence_created', 'report_added', 'agency_assigned', 'status_changed') then
    return new;
  end if;

  notification_category := case
    when new.event_type like 'validation_%' or new.event_type = 'resolution_confirmed' then 'validations'
    when new.actor_kind in ('agency', 'administration') then 'official_updates'
    when new.actor_kind = 'councilor' then 'councilor_activity'
    else 'occurrence_updates'
  end;

  notification_title := case
    when new.event_type = 'validation_opened' then 'Validação comunitária disponível'
    when new.event_type = 'resolution_confirmed' then 'Ocorrência resolvida'
    when new.event_type = 'validation_rejected' then 'A comunidade informou que o problema continua'
    when new.event_type = 'validation_expired' then 'Validação encerrada sem quórum'
    when new.event_type = 'occurrence_reopened' then 'Ocorrência reaberta'
    when new.event_type = 'institutional_priority' then 'Prioridade reconhecida pela gestão municipal'
    when new.event_type = 'councilor_following_started' then 'Vereador passou a acompanhar'
    when new.actor_kind = 'agency' then 'Atualização oficial do órgão'
    when new.actor_kind = 'administration' then 'Atualização oficial da gestão municipal'
    when new.actor_kind = 'councilor' then 'Nova ação de vereador'
    when new.event_type like 'status_%' then 'Mudança de status'
    else 'Atualização da ocorrência'
  end;

  for recipient in
    select distinct recipient_id
    from (
      select post.user_id as recipient_id
      from public.posts post
      where post.occurrence_id = new.occurrence_id
      union
      select follower.user_id
      from public.occurrence_followers follower
      where follower.occurrence_id = new.occurrence_id
      union
      select support.user_id
      from public.occurrence_supports support
      where support.occurrence_id = new.occurrence_id
        and new.event_type in ('validation_opened', 'resolution_confirmed', 'occurrence_reopened')
    ) recipients
    where recipient_id is not null
      and recipient_id is distinct from new.actor_id
  loop
    if public.notification_allowed(recipient.recipient_id, notification_category) then
      perform public.notify_user(
        recipient.recipient_id,
        'occurrence_event',
        notification_title,
        new.description,
        jsonb_build_object(
          'occurrence_id', new.occurrence_id,
          'event_id', new.id,
          'event_type', new.event_type,
          'actor_kind', new.actor_kind,
          'agency_id', new.agency_id
        )
      );
    end if;
  end loop;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Denúncias passam a aceitar comentários, além de relatos.
-- ---------------------------------------------------------------------------

create or replace function public.prepare_moderation_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post public.posts%rowtype;
  target_comment public.comments%rowtype;
begin
  if new.target_type = 'post' then
    select * into target_post from public.posts post where post.id = new.target_id;
    if not found then
      raise exception 'Relato nao encontrado.';
    end if;
    if target_post.user_id = new.reporter_user_id then
      raise exception 'Nao e possivel denunciar o proprio relato.';
    end if;
    new.occurrence_id := target_post.occurrence_id;
  elsif new.target_type = 'comment' then
    select * into target_comment from public.comments comment where comment.id = new.target_id;
    if not found then
      raise exception 'Comentario nao encontrado.';
    end if;
    if target_comment.user_id = new.reporter_user_id then
      raise exception 'Nao e possivel denunciar o proprio comentario.';
    end if;
    new.occurrence_id := target_comment.occurrence_id;
  else
    raise exception 'Tipo de conteudo nao suportado.';
  end if;

  new.status := 'pending';
  new.review_notes := null;
  new.reviewed_at := null;
  new.reviewed_by := null;
  return new;
end;
$$;

drop index if exists public.moderation_reports_unique_post_reporter_idx;
create unique index if not exists moderation_reports_unique_target_reporter_idx
  on public.moderation_reports (reporter_user_id, target_type, target_id);

drop policy if exists "Users can create moderation reports" on public.moderation_reports;
create policy "Users can create moderation reports"
on public.moderation_reports for insert to authenticated
with check (
  reporter_user_id = auth.uid()
  and target_type in ('post', 'comment')
  and char_length(trim(reason)) between 3 and 500
);

create or replace function public.review_moderation_report(
  target_report_id bigint,
  decision text,
  notes text,
  invalidate_whole_occurrence boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_report public.moderation_reports%rowtype;
  target_post public.posts%rowtype;
  affected_post record;
  target_occurrence public.occurrences%rowtype;
  occurrence_invalidated boolean := false;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas a moderacao pode concluir denuncias.' using errcode = '42501';
  end if;

  if decision not in ('upheld', 'dismissed') then
    raise exception 'Decisao de moderacao invalida.';
  end if;

  if char_length(trim(coalesce(notes, ''))) < 3 then
    raise exception 'Registre a justificativa da decisao.';
  end if;

  select * into target_report
  from public.moderation_reports report
  where report.id = target_report_id
    and report.status in ('pending', 'in_analysis')
  for update;

  if not found then
    raise exception 'Denuncia aberta nao encontrada.';
  end if;

  update public.moderation_reports
  set status = decision,
      review_notes = trim(notes),
      reviewed_at = now(),
      reviewed_by = current_user_id,
      resolved_at = now()
  where id = target_report.id;

  if decision = 'dismissed' then
    return;
  end if;

  if target_report.target_type = 'comment' then
    update public.comments
    set hidden_at = coalesce(hidden_at, now()),
        hidden_reason = coalesce(hidden_reason, trim(notes))
    where id = target_report.target_id;

    insert into public.occurrence_events (
      occurrence_id, actor_id, actor_kind, event_type, description, metadata
    )
    select
      target_report.occurrence_id,
      current_user_id,
      'moderator',
      'comment_hidden',
      'Comentário removido da exibição pública pela moderação.',
      jsonb_build_object('moderation_report_id', target_report.id, 'comment_id', target_report.target_id)
    where target_report.occurrence_id is not null;
    return;
  end if;

  select * into target_post
  from public.posts post
  where post.id = target_report.target_id
  for update;

  if not found then
    return;
  end if;

  update public.posts
  set hidden_at = now(),
      hidden_reason = trim(notes)
  where id = target_post.id;

  perform public.reverse_direct_points_for_post(target_post.id);

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_post.occurrence_id
  for update;

  if not found then
    return;
  end if;

  if invalidate_whole_occurrence or not exists (
    select 1
    from public.posts post
    where post.occurrence_id = target_occurrence.id
      and post.hidden_at is null
  ) then
    occurrence_invalidated := true;

    update public.occurrences
    set invalidated_at = now(),
        invalidation_reason = trim(notes),
        status = 'closed',
        resolved_at = null,
        updated_at = now()
    where id = target_occurrence.id;

    perform public.sync_occurrence_status_to_posts(
      target_occurrence.id,
      'closed',
      current_user_id,
      'Ocorrencia encerrada pela moderacao; nao representa resolucao.'
    );

    if invalidate_whole_occurrence then
      for affected_post in
        select post.id
        from public.posts post
        where post.occurrence_id = target_occurrence.id
      loop
        update public.posts
        set hidden_at = coalesce(hidden_at, now()),
            hidden_reason = coalesce(hidden_reason, trim(notes))
        where id = affected_post.id;
        perform public.reverse_direct_points_for_post(affected_post.id);
      end loop;
    end if;
  end if;

  insert into public.occurrence_events (
    occurrence_id,
    actor_id,
    actor_kind,
    event_type,
    description,
    administration_id,
    agency_id,
    metadata
  )
  values (
    target_occurrence.id,
    current_user_id,
    'moderator',
    case when occurrence_invalidated then 'occurrence_invalidated' else 'report_hidden' end,
    trim(notes),
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object(
      'moderation_report_id', target_report.id,
      'post_id', target_post.id,
      'whole_occurrence', invalidate_whole_occurrence
    )
  );
end;
$$;

notify pgrst, 'reload schema';
