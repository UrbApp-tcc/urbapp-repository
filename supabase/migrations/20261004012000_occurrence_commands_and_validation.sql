-- Operacoes transacionais do dominio de ocorrencias.

create or replace function public.distance_km(
  first_latitude double precision,
  first_longitude double precision,
  second_latitude double precision,
  second_longitude double precision
)
returns numeric
language sql
immutable
strict
as $$
  select round((
    6371 * 2 * asin(
      sqrt(
        power(sin(radians(second_latitude - first_latitude) / 2), 2)
        + cos(radians(first_latitude))
        * cos(radians(second_latitude))
        * power(sin(radians(second_longitude - first_longitude) / 2), 2)
      )
    )
  )::numeric, 3);
$$;

create or replace function public.sync_occurrence_status_to_posts(
  target_occurrence_id bigint,
  target_status public.report_status,
  changed_by_user_id uuid,
  change_note text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.post_status_history (
    post_id,
    changed_by,
    from_status,
    to_status,
    note
  )
  select
    post.id,
    changed_by_user_id,
    post.status,
    target_status,
    change_note
  from public.posts post
  where post.occurrence_id = target_occurrence_id
    and post.status is distinct from target_status;

  update public.posts
  set status = target_status,
      resolved_at = case when target_status = 'completed' then now() else null end
  where occurrence_id = target_occurrence_id
    and status is distinct from target_status;
end;
$$;

revoke all on function public.sync_occurrence_status_to_posts(bigint, public.report_status, uuid, text)
  from public, anon, authenticated;

create or replace function public.create_occurrence_report(
  target_city_id bigint,
  target_category_id bigint,
  report_title text,
  report_description text,
  report_latitude double precision,
  report_longitude double precision,
  report_street text default null,
  report_neighborhood text default null,
  report_anonymous boolean default false
)
returns table (occurrence_id bigint, post_id bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  resolved_administration_id bigint;
  resolved_agency_id bigint;
  created_occurrence_id bigint;
  created_post_id bigint;
begin
  if current_user_id is null then
    raise exception 'Usuario autenticado e obrigatorio.' using errcode = '42501';
  end if;

  if target_city_id is null or target_category_id is null then
    raise exception 'Cidade e categoria sao obrigatorias.';
  end if;

  if char_length(trim(coalesce(report_title, ''))) < 3 then
    raise exception 'O titulo deve ter pelo menos 3 caracteres.';
  end if;

  if char_length(trim(coalesce(report_description, ''))) < 3 then
    raise exception 'A descricao deve ter pelo menos 3 caracteres.';
  end if;

  if report_latitude not between -90 and 90
     or report_longitude not between -180 and 180 then
    raise exception 'Coordenadas invalidas.';
  end if;

  select administration.id
    into resolved_administration_id
  from public.municipal_administrations administration
  where administration.city_id = target_city_id
    and administration.starts_on <= current_date
    and (administration.ends_on is null or administration.ends_on >= current_date)
  order by administration.starts_on desc
  limit 1;

  select responsibility.agency_id
    into resolved_agency_id
  from public.agency_responsibilities responsibility
  where responsibility.city_id = target_city_id
    and responsibility.category_id = target_category_id
    and responsibility.starts_on <= current_date
    and (responsibility.ends_on is null or responsibility.ends_on >= current_date)
  order by responsibility.starts_on desc
  limit 1;

  if resolved_administration_id is null or resolved_agency_id is null then
    raise exception 'Nao foi possivel determinar a gestao e o orgao responsavel.';
  end if;

  insert into public.occurrences (
    city_id,
    administration_id,
    created_administration_id,
    category_id,
    agency_id,
    title,
    summary,
    latitude,
    longitude,
    street,
    neighborhood,
    status
  )
  values (
    target_city_id,
    resolved_administration_id,
    resolved_administration_id,
    target_category_id,
    resolved_agency_id,
    trim(report_title),
    trim(report_description),
    report_latitude,
    report_longitude,
    nullif(trim(coalesce(report_street, '')), ''),
    nullif(trim(coalesce(report_neighborhood, '')), ''),
    'open'
  )
  returning id into created_occurrence_id;

  insert into public.posts (
    user_id,
    occurrence_id,
    city_id,
    category_id,
    agency_id,
    title,
    description,
    latitude,
    longitude,
    street,
    neighborhood,
    anonymity,
    status
  )
  values (
    current_user_id,
    created_occurrence_id,
    target_city_id,
    target_category_id,
    resolved_agency_id,
    trim(report_title),
    trim(report_description),
    report_latitude,
    report_longitude,
    nullif(trim(coalesce(report_street, '')), ''),
    nullif(trim(coalesce(report_neighborhood, '')), ''),
    report_anonymous,
    'open'
  )
  returning id into created_post_id;

  update public.occurrences
  set legacy_post_id = created_post_id
  where id = created_occurrence_id;

  insert into public.occurrence_agency_assignments (
    occurrence_id,
    agency_id,
    administration_id,
    reason
  )
  values (
    created_occurrence_id,
    resolved_agency_id,
    resolved_administration_id,
    'Atribuicao automatica por cidade e categoria.'
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
  values
    (
      created_occurrence_id,
      case when report_anonymous then null else current_user_id end,
      'citizen',
      'occurrence_created',
      'Ocorrencia criada a partir do primeiro relato.',
      resolved_administration_id,
      resolved_agency_id,
      jsonb_build_object('post_id', created_post_id)
    ),
    (
      created_occurrence_id,
      null,
      'system',
      'agency_assigned',
      'Ocorrencia associada automaticamente ao orgao responsavel.',
      resolved_administration_id,
      resolved_agency_id,
      jsonb_build_object('category_id', target_category_id)
    );

  insert into public.post_status_history (
    post_id,
    changed_by,
    from_status,
    to_status,
    note
  )
  values (
    created_post_id,
    case when report_anonymous then null else current_user_id end,
    null,
    'open',
    'Primeiro relato da ocorrencia.'
  );

  return query select created_occurrence_id, created_post_id;
end;
$$;

create or replace function public.add_report_to_occurrence(
  target_occurrence_id bigint,
  report_title text,
  report_description text,
  report_anonymous boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
  created_post_id bigint;
begin
  if current_user_id is null then
    raise exception 'Usuario autenticado e obrigatorio.' using errcode = '42501';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if not found then
    raise exception 'Ocorrencia nao encontrada.';
  end if;

  if target_occurrence.status in ('completed', 'closed', 'expired') then
    raise exception 'Nao e possivel adicionar relato a uma ocorrencia encerrada.';
  end if;

  if char_length(trim(coalesce(report_description, ''))) < 3 then
    raise exception 'A descricao deve ter pelo menos 3 caracteres.';
  end if;

  insert into public.posts (
    user_id,
    occurrence_id,
    city_id,
    category_id,
    agency_id,
    title,
    description,
    latitude,
    longitude,
    street,
    neighborhood,
    anonymity,
    status
  )
  values (
    current_user_id,
    target_occurrence.id,
    target_occurrence.city_id,
    target_occurrence.category_id,
    target_occurrence.agency_id,
    coalesce(nullif(trim(report_title), ''), target_occurrence.title),
    trim(report_description),
    target_occurrence.latitude,
    target_occurrence.longitude,
    target_occurrence.street,
    target_occurrence.neighborhood,
    report_anonymous,
    target_occurrence.status
  )
  returning id into created_post_id;

  insert into public.post_status_history (
    post_id,
    changed_by,
    from_status,
    to_status,
    note
  )
  values (
    created_post_id,
    case when report_anonymous then null else current_user_id end,
    null,
    target_occurrence.status,
    'Relato adicionado a uma ocorrencia existente.'
  );

  return created_post_id;
end;
$$;

create or replace function public.find_potential_duplicate_occurrences(
  target_city_id bigint,
  target_category_id bigint,
  target_latitude double precision,
  target_longitude double precision,
  target_text text default null,
  maximum_distance_km numeric default 1
)
returns table (
  occurrence_id bigint,
  title text,
  summary text,
  status public.report_status,
  distance_km numeric,
  text_match boolean,
  reports_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    occurrence.id,
    occurrence.title,
    occurrence.summary,
    occurrence.status,
    public.distance_km(
      target_latitude,
      target_longitude,
      occurrence.latitude,
      occurrence.longitude
    ) as distance_km,
    case
      when nullif(trim(coalesce(target_text, '')), '') is null then false
      else lower(coalesce(occurrence.title, '') || ' ' || coalesce(occurrence.summary, ''))
        like '%' || lower(trim(target_text)) || '%'
    end as text_match,
    count(post.id) as reports_count
  from public.occurrences occurrence
  left join public.posts post on post.occurrence_id = occurrence.id
  where occurrence.city_id = target_city_id
    and occurrence.category_id = target_category_id
    and occurrence.invalidated_at is null
    and occurrence.status in ('open', 'in_analysis', 'in_progress', 'awaiting_validation', 'reopened')
    and public.distance_km(
      target_latitude,
      target_longitude,
      occurrence.latitude,
      occurrence.longitude
    ) <= greatest(maximum_distance_km, 0.05)
  group by occurrence.id
  order by distance_km, text_match desc, occurrence.created_at desc
  limit 10;
$$;

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

  if initiator_kind = 'agency' and not exists (
    select 1
    from public.agency_users agency_user
    where agency_user.agency_id = target_occurrence.agency_id
      and agency_user.user_id = current_user_id
      and agency_user.is_active = true
  ) then
    raise exception 'Usuario nao representa o orgao responsavel.' using errcode = '42501';
  end if;

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
      resolved_at = null
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

create or replace function public.vote_resolution_cycle(
  target_cycle_id bigint,
  vote_decision text,
  voter_latitude double precision,
  voter_longitude double precision
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_cycle public.resolution_cycles%rowtype;
  target_occurrence public.occurrences%rowtype;
  calculated_distance numeric;
  confirmation_count integer;
  rejection_count integer;
  resulting_status text := 'pending';
  created_vote_id bigint;
  contributed_report record;
begin
  if current_user_id is null then
    raise exception 'Usuario autenticado e obrigatorio.' using errcode = '42501';
  end if;

  if vote_decision not in ('confirm', 'reject') then
    raise exception 'Voto invalido.';
  end if;

  if voter_latitude not between -90 and 90
     or voter_longitude not between -180 and 180 then
    raise exception 'Coordenadas invalidas.';
  end if;

  select * into target_cycle
  from public.resolution_cycles cycle
  where cycle.id = target_cycle_id
  for update;

  if not found or target_cycle.status <> 'pending' then
    raise exception 'Ciclo de validacao nao esta aberto.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_cycle.occurrence_id
  for update;

  if target_cycle.expires_at <= now() then
    update public.resolution_cycles
    set status = 'expired', closed_at = now()
    where id = target_cycle.id;

    update public.occurrences
    set status = target_cycle.previous_status,
        previous_operational_status = null
    where id = target_occurrence.id;

    perform public.sync_occurrence_status_to_posts(
      target_occurrence.id,
      target_cycle.previous_status,
      null,
      'Validacao expirada sem quorum; status anterior restaurado.'
    );

    insert into public.occurrence_events (
      occurrence_id,
      actor_kind,
      event_type,
      description,
      administration_id,
      agency_id,
      metadata
    )
    values (
      target_occurrence.id,
      'system',
      'validation_expired',
      'Validacao encerrada sem quorum; status anterior restaurado.',
      target_occurrence.administration_id,
      target_occurrence.agency_id,
      jsonb_build_object('cycle_id', target_cycle.id)
    );

    return jsonb_build_object('cycle_status', 'expired');
  end if;

  if target_cycle.initiated_by = current_user_id then
    raise exception 'Quem iniciou o ciclo nao pode votar nele.';
  end if;

  calculated_distance := public.distance_km(
    voter_latitude,
    voter_longitude,
    target_occurrence.latitude,
    target_occurrence.longitude
  );

  if calculated_distance > target_cycle.radius_km then
    raise exception 'Usuario fora do raio permitido para validacao.';
  end if;

  insert into public.resolution_votes (
    cycle_id,
    voter_id,
    decision,
    latitude,
    longitude,
    distance_km
  )
  values (
    target_cycle.id,
    current_user_id,
    vote_decision,
    voter_latitude,
    voter_longitude,
    calculated_distance
  )
  returning id into created_vote_id;

  perform public.award_xp(
    current_user_id,
    public.xp_value('validation_given'),
    'validation_given',
    created_vote_id
  );

  select
    count(*) filter (where vote.decision = 'confirm'),
    count(*) filter (where vote.decision = 'reject')
  into confirmation_count, rejection_count
  from public.resolution_votes vote
  where vote.cycle_id = target_cycle.id;

  if confirmation_count >= target_cycle.confirmations_required then
    resulting_status := 'approved';

    update public.resolution_cycles
    set status = 'approved', closed_at = now()
    where id = target_cycle.id;

    update public.occurrences
    set status = 'completed',
        previous_operational_status = null,
        resolved_at = now()
    where id = target_occurrence.id;

    perform public.sync_occurrence_status_to_posts(
      target_occurrence.id,
      'completed',
      current_user_id,
      'Resolucao confirmada pela comunidade.'
    );

    insert into public.occurrence_events (
      occurrence_id,
      actor_kind,
      event_type,
      description,
      administration_id,
      agency_id,
      metadata
    )
    values (
      target_occurrence.id,
      'system',
      'resolution_confirmed',
      'A comunidade confirmou a resolucao da ocorrencia.',
      target_occurrence.administration_id,
      target_occurrence.agency_id,
      jsonb_build_object(
        'cycle_id', target_cycle.id,
        'confirmations', confirmation_count,
        'rejections', rejection_count
      )
    );

    for contributed_report in
      select post.id, post.user_id
      from public.posts post
      where post.occurrence_id = target_occurrence.id
    loop
      perform public.award_xp(
        contributed_report.user_id,
        public.xp_value('post_validated'),
        'post_validated',
        contributed_report.id
      );
    end loop;
  elsif rejection_count >= target_cycle.rejections_required then
    resulting_status := 'rejected';

    update public.resolution_cycles
    set status = 'rejected', closed_at = now()
    where id = target_cycle.id;

    update public.occurrences
    set status = target_cycle.previous_status,
        previous_operational_status = null,
        resolved_at = null
    where id = target_occurrence.id;

    perform public.sync_occurrence_status_to_posts(
      target_occurrence.id,
      target_cycle.previous_status,
      current_user_id,
      'Possivel resolucao rejeitada pela comunidade.'
    );

    insert into public.occurrence_events (
      occurrence_id,
      actor_kind,
      event_type,
      description,
      administration_id,
      agency_id,
      metadata
    )
    values (
      target_occurrence.id,
      'system',
      'validation_rejected',
      'A comunidade informou que o problema continua.',
      target_occurrence.administration_id,
      target_occurrence.agency_id,
      jsonb_build_object(
        'cycle_id', target_cycle.id,
        'confirmations', confirmation_count,
        'rejections', rejection_count
      )
    );
  end if;

  return jsonb_build_object(
    'cycle_status', resulting_status,
    'confirmations', confirmation_count,
    'rejections', rejection_count,
    'confirmations_required', target_cycle.confirmations_required,
    'rejections_required', target_cycle.rejections_required
  );
end;
$$;

create or replace function public.get_active_resolution_cycle(
  target_occurrence_id bigint
)
returns table (
  cycle_id bigint,
  occurrence_id bigint,
  initiated_by uuid,
  cycle_status text,
  opened_at timestamptz,
  expires_at timestamptz,
  confirmations integer,
  rejections integer,
  confirmations_required integer,
  rejections_required integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cycle.id,
    cycle.occurrence_id,
    cycle.initiated_by,
    cycle.status,
    cycle.opened_at,
    cycle.expires_at,
    count(vote.id) filter (where vote.decision = 'confirm')::integer,
    count(vote.id) filter (where vote.decision = 'reject')::integer,
    cycle.confirmations_required,
    cycle.rejections_required
  from public.resolution_cycles cycle
  join public.occurrences occurrence on occurrence.id = cycle.occurrence_id
  left join public.resolution_votes vote on vote.cycle_id = cycle.id
  where cycle.occurrence_id = target_occurrence_id
    and cycle.status = 'pending'
  group by cycle.id;
$$;

create or replace function public.expire_resolution_cycles(
  target_occurrence_id bigint default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  expired_cycle record;
  expired_count integer := 0;
begin
  for expired_cycle in
    select cycle.*, occurrence.administration_id, occurrence.agency_id
    from public.resolution_cycles cycle
    join public.occurrences occurrence on occurrence.id = cycle.occurrence_id
    where cycle.status = 'pending'
      and cycle.expires_at <= now()
      and (target_occurrence_id is null or cycle.occurrence_id = target_occurrence_id)
    for update of cycle, occurrence
  loop
    update public.resolution_cycles
    set status = 'expired', closed_at = now()
    where id = expired_cycle.id;

    update public.occurrences
    set status = expired_cycle.previous_status,
        previous_operational_status = null
    where id = expired_cycle.occurrence_id
      and status = 'awaiting_validation';

    perform public.sync_occurrence_status_to_posts(
      expired_cycle.occurrence_id,
      expired_cycle.previous_status,
      null,
      'Validacao expirada sem quorum; status anterior restaurado.'
    );

    insert into public.occurrence_events (
      occurrence_id,
      actor_kind,
      event_type,
      description,
      administration_id,
      agency_id,
      metadata
    )
    values (
      expired_cycle.occurrence_id,
      'system',
      'validation_expired',
      'Validacao encerrada sem quorum; status anterior restaurado.',
      expired_cycle.administration_id,
      expired_cycle.agency_id,
      jsonb_build_object('cycle_id', expired_cycle.id)
    );

    expired_count := expired_count + 1;
  end loop;

  return expired_count;
end;
$$;

create or replace function public.reopen_occurrence(
  target_occurrence_id bigint,
  reopening_description text,
  evidence_storage_path text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
begin
  if current_user_id is null then
    raise exception 'Usuario autenticado e obrigatorio.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(reopening_description, ''))) < 3
     or char_length(trim(coalesce(evidence_storage_path, ''))) < 3 then
    raise exception 'Reabertura exige descricao e nova evidencia.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if not found or target_occurrence.status <> 'completed' then
    raise exception 'Somente ocorrencias resolvidas podem ser reabertas.';
  end if;

  update public.occurrences
  set status = 'reopened', resolved_at = null
  where id = target_occurrence.id;

  perform public.sync_occurrence_status_to_posts(
    target_occurrence.id,
    'reopened',
    current_user_id,
    'Ocorrencia reaberta com nova evidencia.'
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
    'citizen',
    'occurrence_reopened',
    trim(reopening_description),
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object('evidence_storage_path', trim(evidence_storage_path))
  );
end;
$$;

revoke all on function public.create_occurrence_report(
  bigint, bigint, text, text, double precision, double precision, text, text, boolean
) from public, anon, authenticated;

revoke all on function public.add_report_to_occurrence(bigint, text, text, boolean)
  from public, anon, authenticated;

revoke all on function public.find_potential_duplicate_occurrences(
  bigint, bigint, double precision, double precision, text, numeric
) from public, anon, authenticated;

revoke all on function public.open_resolution_cycle(bigint, text, text)
  from public, anon, authenticated;

revoke all on function public.vote_resolution_cycle(bigint, text, double precision, double precision)
  from public, anon, authenticated;

revoke all on function public.get_active_resolution_cycle(bigint)
  from public, anon, authenticated;

revoke all on function public.expire_resolution_cycles(bigint)
  from public, anon, authenticated;

revoke all on function public.reopen_occurrence(bigint, text, text)
  from public, anon, authenticated;

grant execute on function public.create_occurrence_report(
  bigint, bigint, text, text, double precision, double precision, text, text, boolean
) to authenticated;

grant execute on function public.add_report_to_occurrence(bigint, text, text, boolean)
  to authenticated;

grant execute on function public.find_potential_duplicate_occurrences(
  bigint, bigint, double precision, double precision, text, numeric
) to anon, authenticated;

grant execute on function public.open_resolution_cycle(bigint, text, text)
  to authenticated;

grant execute on function public.vote_resolution_cycle(bigint, text, double precision, double precision)
  to authenticated;

grant execute on function public.get_active_resolution_cycle(bigint)
  to anon, authenticated;

grant execute on function public.expire_resolution_cycles(bigint)
  to authenticated, service_role;

grant execute on function public.reopen_occurrence(bigint, text, text)
  to authenticated;

notify pgrst, 'reload schema';
