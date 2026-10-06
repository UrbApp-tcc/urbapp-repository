-- UrbApp: integridade, anonimato e vínculo institucional automático.
-- Corrige divergências apontadas na auditoria de 05/10/2026 (spec §29.4, §37,
-- §39, §40 e §44.8).

-- ---------------------------------------------------------------------------
-- 1. Anonimato: identificadores internos não são lidos pelos clientes.
-- ---------------------------------------------------------------------------

-- `post_status_history.changed_by` recebia o ator de ações de autores anônimos.
revoke select on table public.post_status_history from anon, authenticated;
grant select (id, post_id, from_status, to_status, note, created_at)
  on table public.post_status_history to anon, authenticated;

-- `resolution_cycles.initiated_by` revelava quem informou a possível resolução.
revoke select on table public.resolution_cycles from anon, authenticated;
grant select (
  id,
  occurrence_id,
  initiator_kind,
  previous_status,
  status,
  description,
  confirmations_required,
  rejections_required,
  radius_km,
  cycle_duration,
  initiator_cooldown,
  opened_at,
  expires_at,
  closed_at,
  evidence_storage_path
) on table public.resolution_cycles to anon, authenticated;

drop function if exists public.get_active_resolution_cycle(bigint);
create function public.get_active_resolution_cycle(target_occurrence_id bigint)
returns table (
  cycle_id bigint,
  occurrence_id bigint,
  initiated_by_me boolean,
  initiator_kind text,
  cycle_status text,
  description text,
  evidence_storage_path text,
  opened_at timestamptz,
  expires_at timestamptz,
  confirmations integer,
  rejections integer,
  confirmations_required integer,
  rejections_required integer,
  radius_km numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cycle.id,
    cycle.occurrence_id,
    cycle.initiated_by = auth.uid(),
    cycle.initiator_kind,
    cycle.status,
    cycle.description,
    cycle.evidence_storage_path,
    cycle.opened_at,
    cycle.expires_at,
    count(vote.id) filter (where vote.decision = 'confirm')::integer,
    count(vote.id) filter (where vote.decision = 'reject')::integer,
    cycle.confirmations_required,
    cycle.rejections_required,
    cycle.radius_km
  from public.resolution_cycles cycle
  left join public.resolution_votes vote on vote.cycle_id = cycle.id
  where cycle.occurrence_id = target_occurrence_id
    and cycle.status = 'pending'
  group by cycle.id;
$$;

revoke all on function public.get_active_resolution_cycle(bigint) from public;
grant execute on function public.get_active_resolution_cycle(bigint) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Mídia de relatos: políticas sem leitura direta de `posts.user_id`.
-- ---------------------------------------------------------------------------

create or replace function public.is_post_author(target_post_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.posts post
    where post.id = target_post_id and post.user_id = auth.uid()
  );
$$;

create or replace function public.can_view_post_media(target_post_id bigint, media_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.posts post
    where post.id = target_post_id
      and (post.hidden_at is null or post.user_id = auth.uid() or public.is_platform_admin(auth.uid()))
      and (
        not post.anonymity
        or post.user_id = auth.uid()
        or public.is_platform_admin(auth.uid())
        or position(post.user_id::text in media_path) = 0
      )
  );
$$;

revoke all on function public.is_post_author(bigint) from public, anon;
revoke all on function public.can_view_post_media(bigint, text) from public;
grant execute on function public.is_post_author(bigint) to authenticated;
grant execute on function public.can_view_post_media(bigint, text) to anon, authenticated;

drop policy if exists "Authenticated users can create images for their own posts" on public.post_images;
create policy "Authenticated users can create images for their own posts"
on public.post_images for insert to authenticated
with check (public.is_post_author(post_id) and storage_path like 'reports/' || post_id::text || '/%');

drop policy if exists "Post images preserve anonymous authors" on public.post_images;
create policy "Post images preserve anonymous authors"
on public.post_images for select to anon, authenticated
using (public.can_view_post_media(post_id, storage_path));

-- Buckets públicos servem arquivos pela URL; a listagem do bucket deixa de ser pública.
drop policy if exists "Post images in storage are viewable by everyone" on storage.objects;
drop policy if exists "Users list their own post image uploads" on storage.objects;
create policy "Users list their own post image uploads"
on storage.objects for select to authenticated
using (
  bucket_id = 'post-images'
  and (owner = auth.uid() or owner_id = auth.uid()::text)
);

-- ---------------------------------------------------------------------------
-- 3. Vínculo institucional obrigatório também para cidades e categorias novas.
-- ---------------------------------------------------------------------------

create or replace function public.current_administration_id(
  target_city_id bigint,
  reference_date date default current_date
)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select administration.id
  from public.municipal_administrations administration
  where administration.city_id = target_city_id
    and administration.starts_on <= reference_date
    and (administration.ends_on is null or administration.ends_on >= reference_date)
  order by administration.starts_on desc
  limit 1;
$$;

revoke all on function public.current_administration_id(bigint, date) from public, anon, authenticated;

create or replace function public.provision_city_institutions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  generic_agency_id bigint;
begin
  insert into public.municipal_administrations (city_id, name, starts_on, is_placeholder)
  values (new.id, 'Gestao municipal nao reivindicada', date '1900-01-01', true)
  on conflict do nothing;

  insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
  values (
    new.id,
    'Orgao municipal responsavel nao definido',
    'generic',
    'nao-reivindicado+' || new.id::text || '@urbapp.local',
    'unclaimed'
  )
  on conflict (city_id, name) do update set name = excluded.name
  returning id into generic_agency_id;

  insert into public.agency_responsibilities (city_id, category_id, agency_id, starts_on, reason)
  select new.id, category.id, generic_agency_id, date '1900-01-01', 'Provisionamento automatico da cidade.'
  from public.problem_categories category
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists provision_city_institutions on public.cities;
create trigger provision_city_institutions
after insert on public.cities
for each row execute function public.provision_city_institutions();

create or replace function public.provision_category_responsibilities()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.agency_responsibilities (city_id, category_id, agency_id, starts_on, reason)
  select agency.city_id, new.id, agency.id, date '1900-01-01', 'Provisionamento automatico da categoria.'
  from public.public_agencies agency
  where agency.name = 'Orgao municipal responsavel nao definido'
    and not exists (
      select 1 from public.agency_responsibilities responsibility
      where responsibility.city_id = agency.city_id
        and responsibility.category_id = new.id
        and responsibility.ends_on is null
    )
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists provision_category_responsibilities on public.problem_categories;
create trigger provision_category_responsibilities
after insert on public.problem_categories
for each row execute function public.provision_category_responsibilities();

-- Completa cidades/categorias criadas depois da migração inicial.
insert into public.municipal_administrations (city_id, name, starts_on, is_placeholder)
select city.id, 'Gestao municipal nao reivindicada', date '1900-01-01', true
from public.cities city
where not exists (
  select 1 from public.municipal_administrations administration
  where administration.city_id = city.id
)
on conflict do nothing;

insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
select city.id, 'Orgao municipal responsavel nao definido', 'generic',
       'nao-reivindicado+' || city.id::text || '@urbapp.local', 'unclaimed'
from public.cities city
on conflict (city_id, name) do nothing;

insert into public.agency_responsibilities (city_id, category_id, agency_id, starts_on, reason)
select city.id, category.id, agency.id, date '1900-01-01', 'Provisionamento automatico.'
from public.cities city
cross join public.problem_categories category
join public.public_agencies agency
  on agency.city_id = city.id
 and agency.name = 'Orgao municipal responsavel nao definido'
where not exists (
  select 1 from public.agency_responsibilities responsibility
  where responsibility.city_id = city.id
    and responsibility.category_id = category.id
    and responsibility.ends_on is null
)
on conflict do nothing;

-- Órgão e gestão da ocorrência pertencem sempre à mesma cidade.
create or replace function public.validate_occurrence_institutional_link()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.municipal_administrations administration
    where administration.id = new.administration_id
      and administration.city_id = new.city_id
  ) or not exists (
    select 1 from public.municipal_administrations administration
    where administration.id = new.created_administration_id
      and administration.city_id = new.city_id
  ) then
    raise exception 'A gestao municipal deve pertencer a cidade da ocorrencia.';
  end if;

  if new.agency_id is not null and not exists (
    select 1 from public.public_agencies agency
    where agency.id = new.agency_id
      and agency.city_id = new.city_id
  ) then
    raise exception 'O orgao responsavel deve pertencer a cidade da ocorrencia.';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_occurrence_institutional_link on public.occurrences;
create trigger validate_occurrence_institutional_link
before insert or update of city_id, administration_id, created_administration_id, agency_id
on public.occurrences
for each row execute function public.validate_occurrence_institutional_link();

-- Troca de gestão localiza a gestão vigente por data, não apenas por `ends_on`.
create or replace function public.rollover_municipal_administration(
  target_city_id bigint,
  administration_name text,
  mayor_name text,
  starts_on date,
  ends_on date default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  previous_administration_id bigint;
  new_administration_id bigint;
  inherited_occurrence record;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores do UrbApp podem alterar a gestao.' using errcode = '42501';
  end if;

  if $1 is null or not exists (select 1 from public.cities city where city.id = $1) then
    raise exception 'Cidade nao encontrada.';
  end if;

  if char_length(trim(coalesce($2, ''))) < 3 then
    raise exception 'Informe o nome da nova gestao.';
  end if;

  if $4 is null or ($5 is not null and $5 < $4) then
    raise exception 'Periodo da gestao invalido.';
  end if;

  select administration.id into previous_administration_id
  from public.municipal_administrations as administration
  where administration.city_id = $1
    and administration.starts_on < $4
    and (administration.ends_on is null or administration.ends_on >= $4)
  order by administration.starts_on desc
  limit 1
  for update;

  if exists (
    select 1 from public.municipal_administrations administration
    where administration.city_id = $1
      and administration.starts_on >= $4
  ) then
    raise exception 'Ja existe gestao com inicio igual ou posterior a esta data.';
  end if;

  if previous_administration_id is not null then
    update public.municipal_administrations
    set ends_on = $4 - 1
    where id = previous_administration_id;
  end if;

  insert into public.municipal_administrations (
    city_id, name, mayor_name, starts_on, ends_on, is_placeholder, is_verified
  )
  values ($1, trim($2), nullif(trim(coalesce($3, '')), ''), $4, $5, false, true)
  returning id into new_administration_id;

  for inherited_occurrence in
    update public.occurrences
    set administration_id = new_administration_id
    where occurrences.city_id = $1
      and occurrences.invalidated_at is null
      and occurrences.status in ('open', 'in_analysis', 'in_progress', 'awaiting_validation', 'reopened')
    returning id, agency_id
  loop
    insert into public.occurrence_events (
      occurrence_id, actor_id, actor_kind, event_type, description,
      administration_id, agency_id, metadata
    )
    values (
      inherited_occurrence.id,
      current_user_id,
      'system',
      'administration_changed',
      'Ocorrencia herdada pela nova gestao municipal.',
      new_administration_id,
      inherited_occurrence.agency_id,
      jsonb_build_object(
        'previous_administration_id', previous_administration_id,
        'new_administration_id', new_administration_id
      )
    );
  end loop;

  return new_administration_id;
end;
$$;

-- O relato inicial não gera também o evento "novo relato adicionado".
create or replace function public.link_new_post_to_occurrence()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.occurrence_id is null then
    raise exception 'Relatos devem ser criados pelas operacoes de ocorrencia.';
  end if;

  if exists (
    select 1 from public.posts post
    where post.occurrence_id = new.occurrence_id
      and post.id <> new.id
  ) then
    insert into public.occurrence_events (
      occurrence_id, actor_id, actor_kind, event_type, description,
      administration_id, agency_id, metadata
    )
    select
      new.occurrence_id,
      case when new.anonymity then null else new.user_id end,
      'citizen',
      'report_added',
      'Novo relato da comunidade adicionado à ocorrência.',
      occurrence.administration_id,
      occurrence.agency_id,
      jsonb_build_object('post_id', new.id)
    from public.occurrences occurrence
    where occurrence.id = new.occurrence_id;
  end if;

  return new;
end;
$$;

-- Notificações legadas por relato duplicavam os eventos da ocorrência.
drop trigger if exists notify_on_post_status_change on public.posts;
drop trigger if exists guard_author_completion on public.posts;
drop function if exists public.guard_author_completion();

-- ---------------------------------------------------------------------------
-- 4. Auditoria de transições de status com origem e destino.
-- ---------------------------------------------------------------------------

create or replace function public.audit_occurrence_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.occurrence_events (
    occurrence_id, actor_kind, event_type, description,
    administration_id, agency_id, metadata
  )
  values (
    new.id,
    'system',
    'status_changed',
    'Status alterado para ' || public.status_label(new.status) || '.',
    new.administration_id,
    new.agency_id,
    jsonb_build_object('from', old.status, 'to', new.status)
  );
  return new;
end;
$$;

drop trigger if exists audit_occurrence_status_change on public.occurrences;
create trigger audit_occurrence_status_change
after update of status on public.occurrences
for each row
when (old.status is distinct from new.status)
execute function public.audit_occurrence_status_change();

-- ---------------------------------------------------------------------------
-- 5. Gamificação: uma recompensa por contribuição por ocorrência.
-- ---------------------------------------------------------------------------

create or replace function public.trg_points_post_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.award_points(
    new.user_id,
    public.points_value('valid_contribution'),
    'valid_contribution',
    new.occurrence_id,
    true
  );
  return new;
end;
$$;

create or replace function public.trg_points_occurrence_resolved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  contributor record;
begin
  if new.status = 'completed' and old.status is distinct from new.status then
    for contributor in
      select distinct post.user_id
      from public.posts post
      where post.occurrence_id = new.id
        and post.hidden_at is null
    loop
      perform public.award_points(
        contributor.user_id,
        public.points_value('occurrence_resolved'),
        'occurrence_resolved',
        new.id,
        true
      );
    end loop;
  end if;
  return new;
end;
$$;

-- Estorno de fraude alcança pontos e XP obtidos diretamente pelo relato.
create or replace function public.reverse_direct_points_for_post(target_post_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post public.posts%rowtype;
  awarded_transaction record;
  reversed_xp integer := 0;
begin
  select * into target_post from public.posts post where post.id = target_post_id;
  if not found then
    return;
  end if;

  for awarded_transaction in
    select tx.id, tx.user_id, tx.points_delta, tx.xp_delta
    from public.xp_transactions tx
    where tx.user_id = target_post.user_id
      and (tx.points_delta > 0 or tx.xp_delta > 0)
      and (
        (tx.source_id = target_post.id and tx.source_type in (
          'valid_contribution', 'occurrence_resolved', 'post_created', 'post_validated'
        ))
        or (tx.source_id = target_post.occurrence_id and (
          tx.source_type in ('valid_contribution', 'occurrence_resolved')
          or tx.source_type like 'support_received:%'
          or tx.source_type like 'comment_received:%'
        ))
      )
      and not exists (
        select 1 from public.xp_transactions reversal
        where reversal.source_type = 'moderation_reversal'
          and reversal.source_id = tx.id
      )
  loop
    if awarded_transaction.points_delta > 0 then
      perform public.award_points(
        awarded_transaction.user_id,
        -awarded_transaction.points_delta,
        'moderation_reversal',
        awarded_transaction.id,
        false
      );
    else
      insert into public.xp_transactions (user_id, source_type, source_id, xp_delta, points_delta)
      values (awarded_transaction.user_id, 'moderation_reversal', awarded_transaction.id, 0, 0)
      on conflict do nothing;
    end if;
    reversed_xp := reversed_xp + greatest(awarded_transaction.xp_delta, 0);
  end loop;

  if reversed_xp > 0 then
    update public.profiles
    set current_xp = greatest(current_xp - reversed_xp, 0),
        current_level = public.level_for_xp(greatest(current_xp - reversed_xp, 0))
    where id = target_post.user_id;
  end if;
end;
$$;

revoke all on function public.reverse_direct_points_for_post(bigint) from public, anon, authenticated;

-- Insígnia em destaque precisa ter sido conquistada.
create or replace function public.validate_featured_badge()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.featured_badge_id is not null
     and new.featured_badge_id is distinct from old.featured_badge_id
     and not exists (
       select 1 from public.user_badges badge
       where badge.user_id = new.id and badge.badge_id = new.featured_badge_id
     ) then
    raise exception 'Somente insignias conquistadas podem ficar em destaque.';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_featured_badge on public.profiles;
create trigger validate_featured_badge
before update of featured_badge_id on public.profiles
for each row execute function public.validate_featured_badge();

-- ---------------------------------------------------------------------------
-- 6. Evidência de resolução exigível por categoria (spec §30) e existência real
--    do arquivo no Storage para qualquer evidência referenciada.
-- ---------------------------------------------------------------------------

alter table public.problem_categories
  add column if not exists requires_resolution_evidence boolean not null default false;

create or replace function public.open_resolution_cycle_with_evidence(
  target_occurrence_id bigint,
  resolution_description text,
  initiator_kind text default 'citizen',
  evidence_storage_path text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  created_cycle_id bigint;
  clean_evidence_path text := nullif(trim(coalesce(evidence_storage_path, '')), '');
  evidence_required boolean;
begin
  select category.requires_resolution_evidence into evidence_required
  from public.occurrences occurrence
  join public.problem_categories category on category.id = occurrence.category_id
  where occurrence.id = target_occurrence_id;

  if coalesce(evidence_required, false)
     and coalesce(initiator_kind, 'citizen') = 'citizen'
     and clean_evidence_path is null then
    raise exception 'Esta categoria exige uma foto recente para informar a resolucao.';
  end if;

  created_cycle_id := public.open_resolution_cycle(
    target_occurrence_id,
    resolution_description,
    initiator_kind
  );

  if clean_evidence_path is not null then
    update public.resolution_cycles
    set evidence_storage_path = clean_evidence_path
    where id = created_cycle_id;

    update public.occurrence_events
    set metadata = metadata || jsonb_build_object('evidence_storage_path', clean_evidence_path)
    where occurrence_id = target_occurrence_id
      and event_type = 'validation_opened'
      and metadata ->> 'cycle_id' = created_cycle_id::text;
  end if;

  return created_cycle_id;
end;
$$;

create or replace function public.validate_occurrence_event_evidence_path()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  evidence_path text := nullif(trim(coalesce(new.metadata ->> 'evidence_storage_path', '')), '');
  expected_prefix text;
begin
  if evidence_path is null then
    return new;
  end if;

  expected_prefix := case
    when new.event_type = 'validation_opened'
      then 'occurrences/' || new.occurrence_id::text || '/resolution/'
    when new.event_type = 'occurrence_reopened'
      then 'occurrences/' || new.occurrence_id::text || '/reopening/'
    when new.event_type like 'institutional_%' or new.event_type like 'councilor_%'
      then 'occurrences/' || new.occurrence_id::text || '/institutional/'
    else null
  end;

  if expected_prefix is not null and evidence_path not like expected_prefix || '%' then
    raise exception 'Caminho de evidencia invalido para esta ocorrencia.';
  end if;

  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'post-images'
      and object.name = evidence_path
  ) then
    raise exception 'A evidencia informada nao foi enviada.';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Ranking de cidadãos sem leitura direta de autoria e sem expor anônimos.
-- ---------------------------------------------------------------------------

create or replace function public.get_city_ranking(
  target_city_id bigint,
  page_size integer default 50,
  page_offset integer default 0
)
returns table (
  rank_position bigint,
  profile_id uuid,
  full_name text,
  username text,
  avatar_url text,
  city_id bigint,
  city_name text,
  current_level integer,
  current_xp integer,
  current_points bigint,
  posts_count integer,
  supports_received integer,
  comments_received integer,
  resolved_posts_count integer,
  ranking_score bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with city_profiles as (
    select profile.id, profile.full_name, profile.username, profile.avatar_url,
           profile.city_id, city.name as city_name, profile.current_level,
           profile.current_xp, profile.current_points, profile.created_at
    from public.profiles profile
    join public.cities city on city.id = profile.city_id
    where profile.city_id = target_city_id
  ),
  public_contributions as (
    select post.user_id as profile_id,
           count(distinct post.occurrence_id)::integer as posts_count,
           count(distinct post.occurrence_id) filter (where occurrence.status = 'completed')::integer
             as resolved_posts_count
    from public.posts post
    join public.occurrences occurrence on occurrence.id = post.occurrence_id
    where post.city_id = target_city_id
      and post.hidden_at is null
      and not post.anonymity
      and occurrence.invalidated_at is null
    group by post.user_id
  ),
  received as (
    select tx.user_id as profile_id,
           count(*) filter (where tx.source_type like 'support_received:%')::integer as supports_received,
           count(*) filter (where tx.source_type like 'comment_received%')::integer as comments_received
    from public.xp_transactions tx
    where tx.points_delta > 0
    group by tx.user_id
  )
  select
    dense_rank() over (
      order by profile.current_points desc, profile.current_xp desc, profile.created_at, profile.id
    ),
    profile.id, profile.full_name, profile.username, profile.avatar_url, profile.city_id,
    profile.city_name, profile.current_level, profile.current_xp, profile.current_points,
    coalesce(contribution.posts_count, 0),
    coalesce(received.supports_received, 0),
    coalesce(received.comments_received, 0),
    coalesce(contribution.resolved_posts_count, 0),
    profile.current_points::bigint
  from city_profiles profile
  left join public_contributions contribution on contribution.profile_id = profile.id
  left join received on received.profile_id = profile.id
  order by profile.current_points desc, profile.current_xp desc, profile.created_at, profile.id
  limit greatest(1, least(coalesce(page_size, 50), 100))
  offset greatest(0, coalesce(page_offset, 0));
$$;

revoke all on function public.get_city_ranking(bigint, integer, integer) from public;
grant execute on function public.get_city_ranking(bigint, integer, integer) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. Aprovação de acesso da gestão marca a gestão como verificada.
-- ---------------------------------------------------------------------------

create or replace function public.mark_administration_verified_on_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active then
    update public.municipal_administrations
    set is_verified = true
    where id = new.administration_id
      and not is_verified;
  end if;
  return new;
end;
$$;

drop trigger if exists mark_administration_verified_on_membership on public.administration_users;
create trigger mark_administration_verified_on_membership
after insert or update of is_active on public.administration_users
for each row execute function public.mark_administration_verified_on_membership();

notify pgrst, 'reload schema';
