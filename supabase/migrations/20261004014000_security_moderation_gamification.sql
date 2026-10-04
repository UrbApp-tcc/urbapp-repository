-- Seguranca de comandos, moderacao auditavel e gamificacao por contribuicao.

-- ENCERRADO nao representa resolucao e, portanto, nao recebe resolved_at.
create or replace function public.handle_post_resolved_timestamp()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'completed' then
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

-- Moderação possui estados próprios, separados da máquina de estados urbana.
alter table public.moderation_reports
  alter column status drop default;

alter table public.moderation_reports
  alter column status type text
  using (
    case status::text
      when 'in_analysis' then 'in_analysis'
      when 'completed' then 'upheld'
      when 'closed' then 'dismissed'
      else 'pending'
    end
  );

alter table public.moderation_reports
  alter column status set default 'pending',
  add column if not exists occurrence_id bigint references public.occurrences(id) on delete set null,
  add column if not exists review_notes text,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references public.profiles(id) on delete set null;

alter table public.moderation_reports
  drop constraint if exists moderation_reports_status_check;

alter table public.moderation_reports
  add constraint moderation_reports_status_check
  check (status in ('pending', 'in_analysis', 'upheld', 'dismissed'));

alter table public.posts
  add column if not exists hidden_at timestamptz,
  add column if not exists hidden_reason text;

create index if not exists moderation_reports_queue_idx
  on public.moderation_reports (status, created_at, id);

create index if not exists posts_public_feed_idx
  on public.posts (city_id, created_at desc, id desc)
  where hidden_at is null;

update public.moderation_reports report
set occurrence_id = post.occurrence_id
from public.posts post
where report.target_type = 'post'
  and report.target_id = post.id
  and report.occurrence_id is null;

create or replace function public.prepare_moderation_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post public.posts%rowtype;
begin
  if new.target_type <> 'post' then
    raise exception 'Tipo de conteudo nao suportado.';
  end if;

  select * into target_post
  from public.posts post
  where post.id = new.target_id;

  if not found then
    raise exception 'Relato nao encontrado.';
  end if;

  if target_post.user_id = new.reporter_user_id then
    raise exception 'Nao e possivel denunciar o proprio relato.';
  end if;

  new.occurrence_id := target_post.occurrence_id;
  new.status := 'pending';
  new.review_notes := null;
  new.reviewed_at := null;
  new.reviewed_by := null;
  return new;
end;
$$;

drop trigger if exists prepare_moderation_report_before_insert
  on public.moderation_reports;
create trigger prepare_moderation_report_before_insert
before insert on public.moderation_reports
for each row execute function public.prepare_moderation_report();

-- Oculta conteúdo moderado da leitura pública, preservando autor e moderação.
drop policy if exists "Posts are viewable by everyone" on public.posts;
create policy "Visible posts are viewable by everyone"
on public.posts
for select
to anon, authenticated
using (
  hidden_at is null
  or user_id = auth.uid()
  or public.is_platform_admin(auth.uid())
);

drop policy if exists "Moderators can view moderation reports"
  on public.moderation_reports;
create policy "Moderators can view moderation reports"
on public.moderation_reports
for select
to authenticated
using (public.is_platform_admin(auth.uid()));

create policy "Administrators can view agency profile requests"
on public.agency_profile_requests
for select
to authenticated
using (public.is_platform_admin(auth.uid()));

create policy "Administrators can view councilor profile requests"
on public.councilor_profile_requests
for select
to authenticated
using (public.is_platform_admin(auth.uid()));

-- Valida a identidade declarada ao abrir um ciclo de resolução.
create or replace function public.assert_resolution_initiator_authorized(
  target_occurrence public.occurrences,
  target_user_id uuid,
  requested_kind text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if requested_kind = 'citizen' then
    return;
  end if;

  if requested_kind = 'agency' and exists (
    select 1
    from public.agency_users member
    where member.agency_id = target_occurrence.agency_id
      and member.user_id = target_user_id
      and member.is_active = true
  ) then
    return;
  end if;

  if requested_kind = 'administration' and exists (
    select 1
    from public.administration_users member
    where member.administration_id = target_occurrence.administration_id
      and member.user_id = target_user_id
      and member.is_active = true
  ) then
    return;
  end if;

  if requested_kind = 'councilor' and exists (
    select 1
    from public.councilor_profiles councilor
    join public.councilor_followings following
      on following.councilor_profile_id = councilor.id
     and following.occurrence_id = target_occurrence.id
    where councilor.profile_id = target_user_id
      and councilor.city_id = target_occurrence.city_id
      and councilor.profile_status in ('verified', 'participant')
      and current_date between councilor.mandate_starts_on and councilor.mandate_ends_on
      and exists (
        select 1
        from public.councilor_actions action
        where action.following_id = following.id
      )
  ) then
    return;
  end if;

  raise exception 'Usuario nao esta autorizado a atuar com esse papel.'
    using errcode = '42501';
end;
$$;

revoke all on function public.assert_resolution_initiator_authorized(
  public.occurrences,
  uuid,
  text
) from public, anon, authenticated;

create or replace function public.open_resolution_cycle(
  target_occurrence_id bigint,
  resolution_description text,
  initiator_kind text default 'citizen'
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
  selected_settings public.validation_settings%rowtype;
  created_cycle_id bigint;
  last_attempt_finished_at timestamptz;
  last_attempt_cooldown interval;
begin
  if current_user_id is null then
    raise exception 'Usuario autenticado e obrigatorio.' using errcode = '42501';
  end if;

  if initiator_kind not in ('citizen', 'administration', 'agency', 'councilor') then
    raise exception 'Tipo de ator invalido.';
  end if;

  if char_length(trim(coalesce(resolution_description, ''))) < 3 then
    raise exception 'Descreva a possivel resolucao.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if not found then
    raise exception 'Ocorrencia nao encontrada.';
  end if;

  if target_occurrence.status not in ('open', 'in_analysis', 'in_progress', 'reopened') then
    raise exception 'A ocorrencia nao permite iniciar validacao no estado atual.';
  end if;

  perform public.assert_resolution_initiator_authorized(
    target_occurrence,
    current_user_id,
    initiator_kind
  );

  select * into selected_settings
  from public.validation_settings settings
  where settings.city_id = target_occurrence.city_id
     or settings.city_id is null
  order by settings.city_id nulls last
  limit 1;

  select
    greatest(coalesce(cycle.closed_at, cycle.expires_at), cycle.opened_at),
    cycle.initiator_cooldown
    into last_attempt_finished_at, last_attempt_cooldown
  from public.resolution_cycles cycle
  where cycle.occurrence_id = target_occurrence.id
    and cycle.initiated_by = current_user_id
    and cycle.status in ('rejected', 'expired')
  order by cycle.opened_at desc
  limit 1;

  if last_attempt_finished_at is not null
     and last_attempt_finished_at + last_attempt_cooldown > now() then
    raise exception 'Aguarde o periodo de cooldown antes de tentar novamente.';
  end if;

  insert into public.resolution_cycles (
    occurrence_id,
    initiated_by,
    initiator_kind,
    previous_status,
    description,
    confirmations_required,
    rejections_required,
    radius_km,
    cycle_duration,
    initiator_cooldown,
    expires_at
  )
  values (
    target_occurrence.id,
    current_user_id,
    initiator_kind,
    target_occurrence.status,
    trim(resolution_description),
    selected_settings.confirmations_required,
    selected_settings.rejections_required,
    selected_settings.radius_km,
    selected_settings.cycle_duration,
    selected_settings.initiator_cooldown,
    now() + selected_settings.cycle_duration
  )
  returning id into created_cycle_id;

  update public.occurrences
  set previous_operational_status = target_occurrence.status,
      status = 'awaiting_validation',
      resolved_at = null,
      updated_at = now()
  where id = target_occurrence.id;

  perform public.sync_occurrence_status_to_posts(
    target_occurrence.id,
    'awaiting_validation',
    current_user_id,
    'Possivel resolucao informada; aguardando validacao comunitaria.'
  );

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
    initiator_kind,
    'validation_opened',
    'Possivel resolucao informada; validacao comunitaria aberta.',
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object(
      'cycle_id', created_cycle_id,
      'expires_at', now() + selected_settings.cycle_duration,
      'description', trim(resolution_description)
    )
  );

  return created_cycle_id;
end;
$$;

-- Pontos públicos são separados de XP, mas usam o mesmo extrato auditável.
create or replace function public.points_value(target_action text)
returns integer
language sql
immutable
as $$
  select case target_action
    when 'valid_contribution' then 50
    when 'support_received' then 15
    when 'comment_received' then 5
    when 'occurrence_resolved' then 100
    else 0
  end;
$$;

create or replace function public.award_points(
  target_user_id uuid,
  points integer,
  source_type text,
  source_id bigint,
  send_notification boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  created_transaction_id bigint;
  resulting_points bigint;
begin
  if target_user_id is null or coalesce(points, 0) = 0 then
    return false;
  end if;

  insert into public.xp_transactions (
    user_id,
    source_type,
    source_id,
    xp_delta,
    points_delta
  )
  values (target_user_id, source_type, source_id, 0, points)
  on conflict do nothing
  returning id into created_transaction_id;

  if created_transaction_id is null then
    return false;
  end if;

  update public.profiles
  set current_points = greatest(current_points + points, 0)
  where id = target_user_id
  returning current_points into resulting_points;

  if send_notification and points > 0 then
    perform public.notify_user(
      target_user_id,
      'points_awarded',
      'Voce ganhou pontos',
      format('+%s pontos por uma contribuicao util.', points),
      jsonb_build_object(
        'points', points,
        'source_type', source_type,
        'source_id', source_id,
        'current_points', resulting_points
      )
    );
  end if;

  return true;
end;
$$;

revoke all on function public.award_points(uuid, integer, text, bigint, boolean)
  from public, anon, authenticated;

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
    new.id,
    true
  );
  return new;
end;
$$;

drop trigger if exists points_on_post_created on public.posts;
create trigger points_on_post_created
after insert on public.posts
for each row execute function public.trg_points_post_created();

create or replace function public.trg_points_support_received()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  author_id uuid;
begin
  select post.user_id into author_id
  from public.posts post
  where post.id = new.post_id
    and post.hidden_at is null;

  if author_id is null or author_id = new.user_id then
    return new;
  end if;

  perform public.award_points(
    author_id,
    public.points_value('support_received'),
    'support_received:' || new.user_id::text,
    new.post_id,
    false
  );
  return new;
end;
$$;

drop trigger if exists points_on_support_received on public.post_supports;
create trigger points_on_support_received
after insert on public.post_supports
for each row execute function public.trg_points_support_received();

create or replace function public.trg_points_comment_received()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  author_id uuid;
begin
  select post.user_id into author_id
  from public.posts post
  where post.id = new.post_id
    and post.hidden_at is null;

  if author_id is null or author_id = new.user_id then
    return new;
  end if;

  perform public.award_points(
    author_id,
    public.points_value('comment_received'),
    'comment_received',
    new.id,
    false
  );
  return new;
end;
$$;

drop trigger if exists points_on_comment_received on public.comments;
create trigger points_on_comment_received
after insert on public.comments
for each row execute function public.trg_points_comment_received();

create or replace function public.trg_points_occurrence_resolved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  report record;
begin
  if new.status = 'completed' and old.status is distinct from new.status then
    for report in
      select post.id, post.user_id
      from public.posts post
      where post.occurrence_id = new.id
        and post.hidden_at is null
    loop
      perform public.award_points(
        report.user_id,
        public.points_value('occurrence_resolved'),
        'occurrence_resolved',
        report.id,
        true
      );
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists points_on_occurrence_resolved on public.occurrences;
create trigger points_on_occurrence_resolved
after update of status on public.occurrences
for each row execute function public.trg_points_occurrence_resolved();

-- Reconstrói os pontos históricos sem emitir notificações retroativas.
do $$
declare
  contribution record;
begin
  for contribution in
    select post.id, post.user_id
    from public.posts post
    where post.hidden_at is null
  loop
    perform public.award_points(
      contribution.user_id,
      public.points_value('valid_contribution'),
      'valid_contribution',
      contribution.id,
      false
    );
  end loop;

  for contribution in
    select support.post_id, support.user_id as supporter_id, post.user_id as author_id
    from public.post_supports support
    join public.posts post on post.id = support.post_id
    where post.hidden_at is null
      and support.user_id <> post.user_id
  loop
    perform public.award_points(
      contribution.author_id,
      public.points_value('support_received'),
      'support_received:' || contribution.supporter_id::text,
      contribution.post_id,
      false
    );
  end loop;

  for contribution in
    select comment.id, post.user_id as author_id
    from public.comments comment
    join public.posts post on post.id = comment.post_id
    where post.hidden_at is null
      and comment.user_id <> post.user_id
  loop
    perform public.award_points(
      contribution.author_id,
      public.points_value('comment_received'),
      'comment_received',
      contribution.id,
      false
    );
  end loop;

  for contribution in
    select post.id, post.user_id
    from public.posts post
    join public.occurrences occurrence on occurrence.id = post.occurrence_id
    where post.hidden_at is null
      and occurrence.invalidated_at is null
      and occurrence.status = 'completed'
  loop
    perform public.award_points(
      contribution.user_id,
      public.points_value('occurrence_resolved'),
      'occurrence_resolved',
      contribution.id,
      false
    );
  end loop;
end;
$$;

create or replace function public.reverse_direct_points_for_post(target_post_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  awarded_transaction record;
begin
  for awarded_transaction in
    select tx.id, tx.user_id, tx.points_delta
    from public.xp_transactions tx
    where tx.points_delta > 0
      and (
        (
          tx.source_id = target_post_id
          and (
            tx.source_type = 'valid_contribution'
            or tx.source_type = 'occurrence_resolved'
            or tx.source_type like 'support_received:%'
          )
        )
        or (
          tx.source_type = 'comment_received'
          and exists (
            select 1
            from public.comments comment
            where comment.id = tx.source_id
              and comment.post_id = target_post_id
          )
        )
      )
  loop
    perform public.award_points(
      awarded_transaction.user_id,
      -awarded_transaction.points_delta,
      'moderation_reversal',
      awarded_transaction.id,
      false
    );
  end loop;
end;
$$;

revoke all on function public.reverse_direct_points_for_post(bigint)
  from public, anon, authenticated;

create or replace function public.start_moderation_review(
  target_report_id bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas a moderacao pode analisar denuncias.' using errcode = '42501';
  end if;

  update public.moderation_reports
  set status = 'in_analysis',
      reviewed_by = current_user_id
  where id = target_report_id
    and status = 'pending';

  if not found then
    raise exception 'Denuncia pendente nao encontrada.';
  end if;
end;
$$;

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
      reviewed_by = current_user_id
  where id = target_report.id;

  if decision = 'dismissed' then
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
    update public.occurrences
    set invalidated_at = now(),
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
    case when invalidate_whole_occurrence then 'occurrence_invalidated' else 'report_hidden' end,
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

-- Aprovação auditável de solicitações institucionais.
create or replace function public.review_agency_profile_request(
  target_request_id bigint,
  decision text,
  notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_request public.agency_profile_requests%rowtype;
  resolved_agency_id bigint;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores podem revisar orgaos.' using errcode = '42501';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Decisao invalida.';
  end if;

  select * into target_request
  from public.agency_profile_requests request
  where request.id = target_request_id
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'Solicitacao pendente nao encontrada.';
  end if;

  update public.agency_profile_requests
  set status = decision,
      review_notes = nullif(trim(coalesce(notes, '')), ''),
      reviewed_at = now(),
      reviewed_by = current_user_id
  where id = target_request.id;

  if decision = 'rejected' then
    return null;
  end if;

  insert into public.public_agencies (
    city_id,
    name,
    type,
    contact_email,
    profile_status,
    verified_at,
    claimed_at
  )
  values (
    target_request.city_id,
    target_request.agency_name,
    target_request.agency_type,
    lower(target_request.institutional_email),
    'participant',
    now(),
    now()
  )
  on conflict (city_id, name) do update
    set type = excluded.type,
        contact_email = excluded.contact_email,
        profile_status = 'participant',
        verified_at = now(),
        claimed_at = coalesce(public.public_agencies.claimed_at, now())
  returning id into resolved_agency_id;

  insert into public.agency_users (agency_id, user_id, role, is_active)
  values (resolved_agency_id, target_request.requester_user_id, 'admin', true)
  on conflict (agency_id, user_id) do update
    set role = 'admin',
        is_active = true;

  return resolved_agency_id;
end;
$$;

create or replace function public.review_councilor_profile_request(
  target_request_id bigint,
  decision text,
  notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_request public.councilor_profile_requests%rowtype;
  resolved_profile_id bigint;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores podem revisar vereadores.' using errcode = '42501';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Decisao invalida.';
  end if;

  select * into target_request
  from public.councilor_profile_requests request
  where request.id = target_request_id
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'Solicitacao pendente nao encontrada.';
  end if;

  update public.councilor_profile_requests
  set status = decision,
      review_notes = nullif(trim(coalesce(notes, '')), ''),
      reviewed_at = now(),
      reviewed_by = current_user_id
  where id = target_request.id;

  if decision = 'rejected' then
    return null;
  end if;

  insert into public.councilor_profiles (
    profile_id,
    city_id,
    public_name,
    party,
    mandate_starts_on,
    mandate_ends_on,
    profile_status,
    verified_at
  )
  values (
    target_request.requester_user_id,
    target_request.city_id,
    target_request.public_name,
    target_request.party,
    target_request.mandate_starts_on,
    target_request.mandate_ends_on,
    'participant',
    now()
  )
  on conflict (profile_id) do update
    set city_id = excluded.city_id,
        public_name = excluded.public_name,
        party = excluded.party,
        mandate_starts_on = excluded.mandate_starts_on,
        mandate_ends_on = excluded.mandate_ends_on,
        profile_status = 'participant',
        verified_at = now(),
        updated_at = now()
  returning id into resolved_profile_id;

  return resolved_profile_id;
end;
$$;

-- Corrige o ranking legado: ENCERRADO nunca conta como RESOLVIDO.
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
set search_path = public
as $$
  with city_profiles as (
    select
      profile.id,
      profile.full_name,
      profile.username,
      profile.avatar_url,
      profile.city_id,
      city.name as city_name,
      profile.current_level,
      profile.current_xp,
      profile.current_points,
      profile.created_at
    from public.profiles profile
    join public.cities city on city.id = profile.city_id
    where profile.city_id = target_city_id
  ),
  post_stats as (
    select
      post.user_id as profile_id,
      count(*) filter (where post.hidden_at is null)::integer as posts_count,
      coalesce(sum(coalesce(post.supports_count, 0)) filter (where post.hidden_at is null), 0)::integer as supports_received,
      coalesce(sum(coalesce(post.comments_count, 0)) filter (where post.hidden_at is null), 0)::integer as comments_received,
      count(*) filter (
        where post.status = 'completed'
          and post.hidden_at is null
      )::integer as resolved_posts_count
    from public.posts post
    where post.city_id = target_city_id
      and post.user_id is not null
    group by post.user_id
  ),
  scored_profiles as (
    select
      city_profile.*,
      coalesce(post_stat.posts_count, 0) as posts_count,
      coalesce(post_stat.supports_received, 0) as supports_received,
      coalesce(post_stat.comments_received, 0) as comments_received,
      coalesce(post_stat.resolved_posts_count, 0) as resolved_posts_count,
      city_profile.current_points::bigint as ranking_score
    from city_profiles city_profile
    left join post_stats post_stat on post_stat.profile_id = city_profile.id
  )
  select
    dense_rank() over (
      order by
        scored_profile.ranking_score desc,
        scored_profile.current_xp desc,
        scored_profile.created_at asc,
        scored_profile.id asc
    ),
    scored_profile.id,
    scored_profile.full_name,
    scored_profile.username,
    scored_profile.avatar_url,
    scored_profile.city_id,
    scored_profile.city_name,
    scored_profile.current_level,
    scored_profile.current_xp,
    scored_profile.current_points,
    scored_profile.posts_count,
    scored_profile.supports_received,
    scored_profile.comments_received,
    scored_profile.resolved_posts_count,
    scored_profile.ranking_score
  from scored_profiles scored_profile
  order by
    ranking_score desc,
    current_xp desc,
    created_at asc,
    id asc
  limit greatest(1, least(coalesce(page_size, 50), 100))
  offset greatest(0, coalesce(page_offset, 0));
$$;

revoke all on function public.start_moderation_review(bigint)
  from public, anon, authenticated;
revoke all on function public.review_moderation_report(bigint, text, text, boolean)
  from public, anon, authenticated;
revoke all on function public.review_agency_profile_request(bigint, text, text)
  from public, anon, authenticated;
revoke all on function public.review_councilor_profile_request(bigint, text, text)
  from public, anon, authenticated;

grant execute on function public.start_moderation_review(bigint)
  to authenticated;
grant execute on function public.review_moderation_report(bigint, text, text, boolean)
  to authenticated;
grant execute on function public.review_agency_profile_request(bigint, text, text)
  to authenticated;
grant execute on function public.review_councilor_profile_request(bigint, text, text)
  to authenticated;

grant select (hidden_at, hidden_reason) on public.posts to authenticated;
grant select (occurrence_id, review_notes, reviewed_at, reviewed_by)
  on public.moderation_reports to authenticated;

notify pgrst, 'reload schema';
