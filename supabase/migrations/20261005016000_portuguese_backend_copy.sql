-- Grafia correta (acentuação) nos textos de negócio gerados pelo backend:
-- mensagens de validação, descrições da linha do tempo e notificações.
-- As funções são recriadas a partir da definição vigente, trocando apenas
-- literais de texto; assinaturas, privilégios e comportamento não mudam.

CREATE OR REPLACE FUNCTION public.add_report_to_occurrence(target_occurrence_id bigint, report_title text, report_description text, report_anonymous boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
  created_post_id bigint;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if not found then
    raise exception 'Ocorrência não encontrada.';
  end if;

  if target_occurrence.status in ('completed', 'closed', 'expired') then
    raise exception 'Não é possível adicionar relato a uma ocorrência encerrada.';
  end if;

  if char_length(trim(coalesce(report_description, ''))) < 3 then
    raise exception 'A descrição deve ter pelo menos 3 caracteres.';
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
    'Relato adicionado a uma ocorrência existente.'
  );

  return created_post_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.assert_resolution_initiator_authorized(target_occurrence occurrences, target_user_id uuid, requested_kind text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  raise exception 'Usuário não está autorizado a atuar com esse papel.'
    using errcode = '42501';
end;
$function$;

CREATE OR REPLACE FUNCTION public.configure_agency_responsibility(target_city_id bigint, target_category_id bigint, target_agency_id bigint, change_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  created_responsibility_id bigint;
begin
  if not public.is_platform_admin(current_user_id)
     and not exists (
       select 1
       from public.administration_users member
       join public.municipal_administrations administration
         on administration.id = member.administration_id
       where member.user_id = current_user_id
         and member.is_active = true
         and member.role = 'manager'
         and administration.city_id = target_city_id
         and administration.ends_on is null
     ) then
    raise exception 'Usuário sem permissão para configurar responsabilidades.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(change_reason, ''))) < 3 then
    raise exception 'Informe o motivo da alteração.';
  end if;

  if not exists (
    select 1 from public.public_agencies agency
    where agency.id = target_agency_id and agency.city_id = target_city_id
  ) then
    raise exception 'O órgão deve pertencer à cidade informada.';
  end if;

  update public.agency_responsibilities
  set ends_on = current_date
  where city_id = target_city_id
    and category_id = target_category_id
    and ends_on is null;

  insert into public.agency_responsibilities (
    city_id,
    category_id,
    agency_id,
    starts_on,
    created_by,
    reason
  )
  values (
    target_city_id,
    target_category_id,
    target_agency_id,
    current_date,
    current_user_id,
    trim(change_reason)
  )
  returning id into created_responsibility_id;

  return created_responsibility_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.configure_validation_settings(target_city_id bigint, required_confirmations integer, required_rejections integer, maximum_radius_km numeric, duration_hours integer, cooldown_hours integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  resolved_settings_id bigint;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores podem alterar a validação.' using errcode = '42501';
  end if;

  if required_confirmations < 1
     or required_rejections < 1
     or maximum_radius_km <= 0
     or duration_hours < 1
     or cooldown_hours < 0 then
    raise exception 'Parâmetros de validação inválidos.';
  end if;

  if target_city_id is null or not exists (
    select 1 from public.cities city where city.id = target_city_id
  ) then
    raise exception 'Cidade inválida.';
  end if;

  insert into public.validation_settings (
    city_id,
    confirmations_required,
    rejections_required,
    radius_km,
    cycle_duration,
    initiator_cooldown
  )
  values (
    target_city_id,
    required_confirmations,
    required_rejections,
    maximum_radius_km,
    make_interval(hours => duration_hours),
    make_interval(hours => cooldown_hours)
  )
  on conflict (city_id) where city_id is not null do update
    set confirmations_required = excluded.confirmations_required,
        rejections_required = excluded.rejections_required,
        radius_km = excluded.radius_km,
        cycle_duration = excluded.cycle_duration,
        initiator_cooldown = excluded.initiator_cooldown,
        updated_at = now()
  returning id into resolved_settings_id;

  insert into public.validation_settings_history (
    settings_id,
    city_id,
    confirmations_required,
    rejections_required,
    radius_km,
    cycle_duration,
    initiator_cooldown,
    changed_by
  )
  values (
    resolved_settings_id,
    target_city_id,
    required_confirmations,
    required_rejections,
    maximum_radius_km,
    make_interval(hours => duration_hours),
    make_interval(hours => cooldown_hours),
    current_user_id
  );

  return resolved_settings_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_institutional_profile_request(target_city_id bigint, institution_name text, institution_type text, institutional_email text, requester_role text DEFAULT NULL::text, proof_summary text DEFAULT NULL::text, proof_links text DEFAULT NULL::text, request_kind text DEFAULT 'agency'::text)
 RETURNS agency_profile_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  created_request public.agency_profile_requests%rowtype;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if request_kind not in ('agency', 'administration') then
    raise exception 'Tipo de perfil institucional inválido.';
  end if;

  if target_city_id is null
     or not exists (select 1 from public.cities city where city.id = target_city_id) then
    raise exception 'A cidade da solicitação é obrigatória.';
  end if;

  if char_length(trim(coalesce(institution_name, ''))) < 3 then
    raise exception 'Informe o nome da instituição.';
  end if;

  if char_length(trim(coalesce(institution_type, ''))) < 3 then
    raise exception 'Informe o tipo da instituição.';
  end if;

  if position('@' in coalesce(institutional_email, '')) = 0 then
    raise exception 'Informe um e-mail institucional válido.';
  end if;

  if char_length(trim(coalesce(proof_summary, ''))) < 3 then
    raise exception 'Descreva as provas institucionais para análise.';
  end if;

  if exists (
    select 1
    from public.agency_profile_requests request
    where request.requester_user_id = current_user_id
      and request.city_id = target_city_id
      and request.request_kind = create_institutional_profile_request.request_kind
      and request.status = 'pending'
  ) then
    raise exception 'Já existe uma solicitação institucional pendente para esta cidade.';
  end if;

  insert into public.agency_profile_requests (
    requester_user_id,
    city_id,
    agency_name,
    agency_type,
    institutional_email,
    requester_role,
    proof_summary,
    proof_links,
    request_kind
  )
  values (
    current_user_id,
    target_city_id,
    trim(institution_name),
    trim(institution_type),
    lower(trim(institutional_email)),
    nullif(trim(coalesce(requester_role, '')), ''),
    trim(proof_summary),
    nullif(trim(coalesce(proof_links, '')), ''),
    request_kind
  )
  returning * into created_request;

  return created_request;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_occurrence_report(target_city_id bigint, target_category_id bigint, report_title text, report_description text, report_latitude double precision, report_longitude double precision, report_street text DEFAULT NULL::text, report_neighborhood text DEFAULT NULL::text, report_anonymous boolean DEFAULT false)
 RETURNS TABLE(occurrence_id bigint, post_id bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  resolved_administration_id bigint;
  resolved_agency_id bigint;
  created_occurrence_id bigint;
  created_post_id bigint;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if target_city_id is null or target_category_id is null then
    raise exception 'Cidade e categoria são obrigatórias.';
  end if;

  if char_length(trim(coalesce(report_title, ''))) < 3 then
    raise exception 'O título deve ter pelo menos 3 caracteres.';
  end if;

  if char_length(trim(coalesce(report_description, ''))) < 3 then
    raise exception 'A descrição deve ter pelo menos 3 caracteres.';
  end if;

  if report_latitude not between -90 and 90
     or report_longitude not between -180 and 180 then
    raise exception 'Coordenadas inválidas.';
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
    raise exception 'Não foi possível determinar a gestão e o órgão responsável.';
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
    'Atribuição automática por cidade e categoria.'
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
      'Ocorrência criada a partir do primeiro relato.',
      resolved_administration_id,
      resolved_agency_id,
      jsonb_build_object('post_id', created_post_id)
    ),
    (
      created_occurrence_id,
      null,
      'system',
      'agency_assigned',
      'Ocorrência associada automaticamente ao órgão responsável.',
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
    'Primeiro relato da ocorrência.'
  );

  return query select created_occurrence_id, created_post_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.end_councilor_following(target_following_id bigint, closing_description text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_following public.councilor_followings%rowtype;
  target_occurrence public.occurrences%rowtype;
  clean_description text := nullif(trim(coalesce(closing_description, '')), '');
begin
  select following.* into target_following
  from public.councilor_followings following
  join public.councilor_profiles councilor
    on councilor.id = following.councilor_profile_id
  where following.id = target_following_id
    and councilor.profile_id = current_user_id
    and councilor.profile_status in ('verified', 'participant')
    and following.ended_at is null
    and following.status not in ('resolved', 'ended')
  for update of following;

  if not found then
    raise exception 'Acompanhamento não encontrado, finalizado ou sem permissão.' using errcode = '42501';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_following.occurrence_id;

  update public.councilor_followings
  set status = 'ended',
      ended_at = now()
  where id = target_following.id;

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
    'councilor',
    'councilor_following_ended',
    coalesce(clean_description, 'Vereador encerrou o acompanhamento da demanda.'),
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object('following_id', target_following.id)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.expire_resolution_cycles(target_occurrence_id bigint DEFAULT NULL::bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      'Validação expirada sem quórum; status anterior restaurado.'
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
      'Validação encerrada sem quórum; status anterior restaurado.',
      expired_cycle.administration_id,
      expired_cycle.agency_id,
      jsonb_build_object('cycle_id', expired_cycle.id)
    );

    expired_count := expired_count + 1;
  end loop;

  return expired_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.link_new_post_to_occurrence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.occurrence_id is null then
    raise exception 'Relatos devem ser criados pelas operações de ocorrência.';
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
$function$;

CREATE OR REPLACE FUNCTION public.merge_duplicate_occurrences(primary_occurrence_id bigint, duplicate_occurrence_id bigint, merge_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  primary_occurrence public.occurrences%rowtype;
  duplicate_occurrence public.occurrences%rowtype;
  moved_report record;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas a moderação pode consolidar duplicidades.' using errcode = '42501';
  end if;

  if primary_occurrence_id = duplicate_occurrence_id then
    raise exception 'Selecione duas ocorrências diferentes.';
  end if;

  if char_length(trim(coalesce(merge_reason, ''))) < 3 then
    raise exception 'Informe o motivo da consolidação.';
  end if;

  select * into primary_occurrence
  from public.occurrences occurrence
  where occurrence.id = primary_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  select * into duplicate_occurrence
  from public.occurrences occurrence
  where occurrence.id = duplicate_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if primary_occurrence.id is null or duplicate_occurrence.id is null then
    raise exception 'Ocorrência principal ou duplicada não encontrada.';
  end if;

  if primary_occurrence.city_id <> duplicate_occurrence.city_id then
    raise exception 'Ocorrências de cidades diferentes não podem ser consolidadas.';
  end if;

  update public.resolution_cycles
  set status = 'cancelled', closed_at = now()
  where occurrence_id = duplicate_occurrence.id
    and status = 'pending';

  for moved_report in
    select post.id, post.status
    from public.posts post
    where post.occurrence_id = duplicate_occurrence.id
    for update
  loop
    insert into public.post_status_history (
      post_id,
      changed_by,
      from_status,
      to_status,
      note
    )
    values (
      moved_report.id,
      current_user_id,
      moved_report.status,
      primary_occurrence.status,
      'Relato associado à ocorrência principal após consolidação de duplicidade.'
    );
  end loop;

  update public.posts
  set occurrence_id = primary_occurrence.id,
      city_id = primary_occurrence.city_id,
      category_id = primary_occurrence.category_id,
      agency_id = primary_occurrence.agency_id,
      status = primary_occurrence.status,
      resolved_at = primary_occurrence.resolved_at,
      updated_at = now()
  where occurrence_id = duplicate_occurrence.id;

  update public.occurrence_agency_assignments
  set ends_at = coalesce(ends_at, now())
  where occurrence_id = duplicate_occurrence.id
    and ends_at is null;

  update public.occurrences
  set status = 'closed',
      resolved_at = null,
      invalidated_at = now(),
      merged_into_occurrence_id = primary_occurrence.id,
      closed_reason = 'duplicate_merged',
      invalidation_reason = trim(merge_reason),
      updated_at = now()
  where id = duplicate_occurrence.id;

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
      primary_occurrence.id,
      current_user_id,
      'moderator',
      'duplicate_absorbed',
      trim(merge_reason),
      primary_occurrence.administration_id,
      primary_occurrence.agency_id,
      jsonb_build_object('absorbed_occurrence_id', duplicate_occurrence.id)
    ),
    (
      duplicate_occurrence.id,
      current_user_id,
      'moderator',
      'occurrence_merged',
      trim(merge_reason),
      duplicate_occurrence.administration_id,
      duplicate_occurrence.agency_id,
      jsonb_build_object('primary_occurrence_id', primary_occurrence.id)
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_post_comment_received()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target_post public.posts%rowtype;
begin
  select * into target_post
  from public.posts post
  where post.id = new.post_id;

  if target_post.user_id is not null
     and target_post.user_id is distinct from new.user_id
     and target_post.hidden_at is null then
    perform public.notify_user(
      target_post.user_id,
      'post_comment',
      'Novo comentário no seu relato',
      left(new.body, 180),
      jsonb_build_object(
        'post_id', target_post.id,
        'occurrence_id', target_post.occurrence_id,
        'comment_id', new.id,
        'commenter_id', new.user_id
      )
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.open_resolution_cycle(target_occurrence_id bigint, resolution_description text, initiator_kind text DEFAULT 'citizen'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
  selected_settings public.validation_settings%rowtype;
  created_cycle_id bigint;
  last_attempt_finished_at timestamptz;
  last_attempt_cooldown interval;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if initiator_kind not in ('citizen', 'administration', 'agency', 'councilor') then
    raise exception 'Tipo de ator inválido.';
  end if;

  if char_length(trim(coalesce(resolution_description, ''))) < 3 then
    raise exception 'Descreva a possível resolução.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if not found then
    raise exception 'Ocorrência não encontrada.';
  end if;

  if target_occurrence.status not in ('open', 'in_analysis', 'in_progress', 'reopened') then
    raise exception 'A ocorrência não permite iniciar validação no estado atual.';
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
    raise exception 'Aguarde o período de espera antes de tentar novamente.';
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
    'Possível resolução informada; aguardando validação comunitária.'
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
    'Possível resolução informada; validação comunitária aberta.',
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
$function$;

CREATE OR REPLACE FUNCTION public.open_resolution_cycle_with_evidence(target_occurrence_id bigint, resolution_description text, initiator_kind text DEFAULT 'citizen'::text, evidence_storage_path text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    raise exception 'Esta categoria exige uma foto recente para informar a resolução.';
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
$function$;

CREATE OR REPLACE FUNCTION public.prepare_moderation_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target_post public.posts%rowtype;
  target_comment public.comments%rowtype;
begin
  if new.target_type = 'post' then
    select * into target_post from public.posts post where post.id = new.target_id;
    if not found then
      raise exception 'Relato não encontrado.';
    end if;
    if target_post.user_id = new.reporter_user_id then
      raise exception 'Não é possível denunciar o próprio relato.';
    end if;
    new.occurrence_id := target_post.occurrence_id;
  elsif new.target_type = 'comment' then
    select * into target_comment from public.comments comment where comment.id = new.target_id;
    if not found then
      raise exception 'Comentário não encontrado.';
    end if;
    if target_comment.user_id = new.reporter_user_id then
      raise exception 'Não é possível denunciar o próprio comentário.';
    end if;
    new.occurrence_id := target_comment.occurrence_id;
  else
    raise exception 'Tipo de conteúdo não suportado.';
  end if;

  new.status := 'pending';
  new.review_notes := null;
  new.reviewed_at := null;
  new.reviewed_by := null;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.provision_category_responsibilities()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.agency_responsibilities (city_id, category_id, agency_id, starts_on, reason)
  select agency.city_id, new.id, agency.id, date '1900-01-01', 'Provisionamento automático da categoria.'
  from public.public_agencies agency
  where agency.name = 'Órgão municipal responsável não definido'
    and not exists (
      select 1 from public.agency_responsibilities responsibility
      where responsibility.city_id = agency.city_id
        and responsibility.category_id = new.id
        and responsibility.ends_on is null
    )
  on conflict do nothing;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.provision_city_institutions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  generic_agency_id bigint;
begin
  insert into public.municipal_administrations (city_id, name, starts_on, is_placeholder)
  values (new.id, 'Gestão municipal não reivindicada', date '1900-01-01', true)
  on conflict do nothing;

  insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
  values (
    new.id,
    'Órgão municipal responsável não definido',
    'generic',
    'nao-reivindicado+' || new.id::text || '@urbapp.local',
    'unclaimed'
  )
  on conflict (city_id, name) do update set name = excluded.name
  returning id into generic_agency_id;

  insert into public.agency_responsibilities (city_id, category_id, agency_id, starts_on, reason)
  select new.id, category.id, generic_agency_id, date '1900-01-01', 'Provisionamento automático da cidade.'
  from public.problem_categories category
  on conflict do nothing;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.register_councilor_action(target_following_id bigint, councilor_action_type text, action_description text, evidence_storage_path text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_following public.councilor_followings%rowtype;
  target_occurrence public.occurrences%rowtype;
  created_action_id bigint;
  clean_evidence text := nullif(trim(coalesce(evidence_storage_path, '')), '');
begin
  select following.* into target_following
  from public.councilor_followings following
  join public.councilor_profiles councilor on councilor.id = following.councilor_profile_id
  where following.id = target_following_id
    and councilor.profile_id = current_user_id
    and councilor.profile_status in ('verified', 'participant')
    and current_date between councilor.mandate_starts_on and councilor.mandate_ends_on
    and following.ended_at is null
    and following.status not in ('resolved', 'ended')
  for update of following;

  if not found then
    raise exception 'Acompanhamento não encontrado, finalizado ou sem permissão.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(action_description, ''))) < 3 then
    raise exception 'Descreva a ação de acompanhamento.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_following.occurrence_id
  for update;

  if target_occurrence.invalidated_at is not null or target_occurrence.status in ('completed', 'closed') then
    raise exception 'A ocorrência não aceita novas ações de acompanhamento.';
  end if;

  insert into public.councilor_actions (following_id, action_type, description, evidence_storage_path)
  values (target_following.id, councilor_action_type, trim(action_description), clean_evidence)
  returning id into created_action_id;

  update public.councilor_followings
  set status = case
        when councilor_action_type in ('forwarding', 'request', 'charge', 'official_letter', 'agency_contact')
          then 'awaiting_response'
        else 'action_registered'
      end
  where id = target_following.id;

  insert into public.occurrence_events (
    occurrence_id, actor_id, actor_kind, event_type, description,
    administration_id, agency_id, metadata
  )
  values (
    target_occurrence.id,
    current_user_id,
    'councilor',
    'councilor_' || councilor_action_type,
    trim(action_description),
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object(
      'following_id', target_following.id,
      'councilor_profile_id', target_following.councilor_profile_id,
      'councilor_action_id', created_action_id,
      'evidence_storage_path', clean_evidence
    )
  );

  if councilor_action_type = 'possible_resolution'
     and target_occurrence.status <> 'awaiting_validation' then
    perform public.open_resolution_cycle(target_occurrence.id, trim(action_description), 'councilor');
  end if;

  return created_action_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.register_institutional_action(target_occurrence_id bigint, institutional_action_type text, action_description text, action_target_agency_id bigint DEFAULT NULL::bigint, action_forecast_at timestamp with time zone DEFAULT NULL::timestamp with time zone, evidence_storage_path text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
  resolved_actor_kind text;
  created_action_id bigint;
  target_status public.report_status;
  clean_evidence text := nullif(trim(coalesce(evidence_storage_path, '')), '');
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if institutional_action_type not in (
    'received', 'priority', 'forwarding', 'request', 'official_position', 'forecast',
    'analysis', 'scheduled', 'in_progress', 'progress_update', 'executed',
    'observation', 'conclusion'
  ) then
    raise exception 'Tipo de ação institucional inválido.';
  end if;

  if char_length(trim(coalesce(action_description, ''))) < 3 then
    raise exception 'Descreva a ação institucional.';
  end if;

  if institutional_action_type = 'forecast' and action_forecast_at is null then
    raise exception 'Informe a data prevista.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if not found then
    raise exception 'Ocorrência não encontrada.';
  end if;

  if target_occurrence.status in ('closed') then
    raise exception 'Ocorrência encerrada não recebe novas ações.';
  end if;

  if exists (
    select 1
    from public.administration_users member
    join public.municipal_administrations administration
      on administration.id = member.administration_id
    where member.administration_id = target_occurrence.administration_id
      and member.user_id = current_user_id
      and member.is_active = true
  ) then
    resolved_actor_kind := 'administration';
  elsif exists (
    select 1
    from public.agency_users member
    where member.agency_id = target_occurrence.agency_id
      and member.user_id = current_user_id
      and member.is_active = true
  ) then
    resolved_actor_kind := 'agency';
  else
    raise exception 'Usuário não representa a gestão ou o órgão responsável.' using errcode = '42501';
  end if;

  if institutional_action_type in ('priority', 'forwarding', 'request')
     and resolved_actor_kind <> 'administration' then
    raise exception 'Esta ação é exclusiva da gestão municipal.' using errcode = '42501';
  end if;

  if institutional_action_type = 'received' and resolved_actor_kind <> 'agency' then
    raise exception 'Confirmar recebimento é uma ação do órgão responsável.' using errcode = '42501';
  end if;

  if target_occurrence.status = 'completed'
     and institutional_action_type not in ('observation', 'official_position') then
    raise exception 'Ocorrência resolvida aceita apenas observações oficiais.';
  end if;

  if institutional_action_type = 'forwarding' then
    if action_target_agency_id is null or not exists (
      select 1 from public.public_agencies agency
      where agency.id = action_target_agency_id
        and agency.city_id = target_occurrence.city_id
    ) then
      raise exception 'Selecione um órgão válido da mesma cidade.';
    end if;

    if action_target_agency_id = target_occurrence.agency_id then
      raise exception 'A ocorrência já está com este órgão.';
    end if;

    update public.occurrence_agency_assignments
    set ends_at = now()
    where occurrence_id = target_occurrence.id
      and ends_at is null;

    insert into public.occurrence_agency_assignments (
      occurrence_id, agency_id, administration_id, assigned_by, reason
    )
    values (
      target_occurrence.id, action_target_agency_id, target_occurrence.administration_id,
      current_user_id, trim(action_description)
    );

    update public.occurrences
    set agency_id = action_target_agency_id
    where id = target_occurrence.id;

    update public.posts
    set agency_id = action_target_agency_id
    where occurrence_id = target_occurrence.id;
  end if;

  if institutional_action_type = 'priority' then
    update public.occurrences
    set administrative_priority = true
    where id = target_occurrence.id;
  elsif institutional_action_type in ('received', 'analysis') then
    target_status := 'in_analysis';
  elsif institutional_action_type in ('scheduled', 'in_progress', 'executed', 'progress_update') then
    target_status := 'in_progress';
  end if;

  if target_status is not null
     and target_occurrence.status in ('open', 'in_analysis', 'in_progress', 'reopened')
     and target_occurrence.status is distinct from target_status
     and not (target_status = 'in_analysis' and target_occurrence.status = 'in_progress') then
    update public.occurrences
    set status = target_status
    where id = target_occurrence.id;

    perform public.sync_occurrence_status_to_posts(
      target_occurrence.id, target_status, null, trim(action_description)
    );
  end if;

  insert into public.institutional_actions (
    occurrence_id, administration_id, agency_id, created_by, actor_kind, action_type,
    description, evidence_storage_path, forecast_at, target_agency_id
  )
  values (
    target_occurrence.id,
    target_occurrence.administration_id,
    case when resolved_actor_kind = 'agency' then target_occurrence.agency_id else null end,
    current_user_id,
    resolved_actor_kind,
    institutional_action_type,
    trim(action_description),
    clean_evidence,
    action_forecast_at,
    action_target_agency_id
  )
  returning id into created_action_id;

  insert into public.occurrence_events (
    occurrence_id, actor_id, actor_kind, event_type, description,
    administration_id, agency_id, metadata
  )
  values (
    target_occurrence.id,
    current_user_id,
    resolved_actor_kind,
    'institutional_' || institutional_action_type,
    trim(action_description),
    target_occurrence.administration_id,
    coalesce(action_target_agency_id, target_occurrence.agency_id),
    jsonb_build_object(
      'institutional_action_id', created_action_id,
      'forecast_at', action_forecast_at,
      'target_agency_id', action_target_agency_id,
      'evidence_storage_path', clean_evidence
    )
  );

  if institutional_action_type = 'conclusion'
     and target_occurrence.status <> 'awaiting_validation' then
    perform public.open_resolution_cycle(
      target_occurrence.id, trim(action_description), resolved_actor_kind
    );
  end if;

  return created_action_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.reopen_occurrence(target_occurrence_id bigint, reopening_description text, evidence_storage_path text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(reopening_description, ''))) < 3
     or char_length(trim(coalesce(evidence_storage_path, ''))) < 3 then
    raise exception 'Reabertura exige descrição e nova evidência.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if not found or target_occurrence.status <> 'completed' then
    raise exception 'Somente ocorrências resolvidas podem ser reabertas.';
  end if;

  update public.occurrences
  set status = 'reopened', resolved_at = null
  where id = target_occurrence.id;

  perform public.sync_occurrence_status_to_posts(
    target_occurrence.id,
    'reopened',
    current_user_id,
    'Ocorrência reaberta com nova evidência.'
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
$function$;

CREATE OR REPLACE FUNCTION public.review_agency_profile_request(target_request_id bigint, decision text, notes text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_request public.agency_profile_requests%rowtype;
  resolved_profile_id bigint;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores podem revisar perfis institucionais.'
      using errcode = '42501';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Decisão inválida.';
  end if;

  select * into target_request
  from public.agency_profile_requests request
  where request.id = target_request_id
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'Solicitação pendente não encontrada.';
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

  if target_request.request_kind = 'administration' then
    select administration.id into resolved_profile_id
    from public.municipal_administrations administration
    where administration.city_id = target_request.city_id
      and administration.starts_on <= current_date
      and (administration.ends_on is null or administration.ends_on >= current_date)
    order by administration.starts_on desc
    limit 1;

    if resolved_profile_id is null then
      raise exception 'A cidade não possui gestão municipal vigente.';
    end if;

    insert into public.administration_users (
      administration_id,
      user_id,
      role,
      is_active
    )
    values (
      resolved_profile_id,
      target_request.requester_user_id,
      'agent',
      true
    )
    on conflict (administration_id, user_id) do update
      set role = excluded.role,
          is_active = true;

    return resolved_profile_id;
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
  returning id into resolved_profile_id;

  insert into public.agency_users (agency_id, user_id, role, is_active)
  values (resolved_profile_id, target_request.requester_user_id, 'admin', true)
  on conflict (agency_id, user_id) do update
    set role = 'admin',
        is_active = true;

  return resolved_profile_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_councilor_profile_request(target_request_id bigint, decision text, notes text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_request public.councilor_profile_requests%rowtype;
  resolved_profile_id bigint;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores podem revisar vereadores.' using errcode = '42501';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Decisão inválida.';
  end if;

  select * into target_request
  from public.councilor_profile_requests request
  where request.id = target_request_id
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'Solicitação pendente não encontrada.';
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
$function$;

CREATE OR REPLACE FUNCTION public.review_moderation_report(target_report_id bigint, decision text, notes text, invalidate_whole_occurrence boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_report public.moderation_reports%rowtype;
  target_post public.posts%rowtype;
  affected_post record;
  target_occurrence public.occurrences%rowtype;
  occurrence_invalidated boolean := false;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas a moderação pode concluir denúncias.' using errcode = '42501';
  end if;

  if decision not in ('upheld', 'dismissed') then
    raise exception 'Decisão de moderação inválida.';
  end if;

  if char_length(trim(coalesce(notes, ''))) < 3 then
    raise exception 'Registre a justificativa da decisão.';
  end if;

  select * into target_report
  from public.moderation_reports report
  where report.id = target_report_id
    and report.status in ('pending', 'in_analysis')
  for update;

  if not found then
    raise exception 'Denúncia aberta não encontrada.';
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
      'Ocorrência encerrada pela moderação; não representa resolução.'
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
$function$;

CREATE OR REPLACE FUNCTION public.rollover_municipal_administration(target_city_id bigint, administration_name text, mayor_name text, starts_on date, ends_on date DEFAULT NULL::date)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  previous_administration_id bigint;
  new_administration_id bigint;
  inherited_occurrence record;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores do UrbApp podem alterar a gestão.' using errcode = '42501';
  end if;

  if $1 is null or not exists (select 1 from public.cities city where city.id = $1) then
    raise exception 'Cidade não encontrada.';
  end if;

  if char_length(trim(coalesce($2, ''))) < 3 then
    raise exception 'Informe o nome da nova gestão.';
  end if;

  if $4 is null or ($5 is not null and $5 < $4) then
    raise exception 'Período da gestão inválido.';
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
    raise exception 'Já existe gestão com início igual ou posterior a esta data.';
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
      'Ocorrência herdada pela nova gestão municipal.',
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
$function$;

CREATE OR REPLACE FUNCTION public.set_category_resolution_evidence(target_category_id bigint, evidence_required boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (
    select 1 from public.platform_user_roles role
    where role.user_id = auth.uid() and role.role = 'admin'
  ) then
    raise exception 'Apenas administradores podem alterar esta regra.' using errcode = '42501';
  end if;

  update public.problem_categories
  set requires_resolution_evidence = coalesce(evidence_required, false)
  where id = target_category_id;

  if not found then
    raise exception 'Categoria não encontrada.';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_occurrence_jurisdiction(target_occurrence_id bigint, jurisdiction text, external_responsible text, change_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
begin
  if jurisdiction not in ('municipal', 'state', 'federal', 'concessionaire', 'private', 'unknown') then
    raise exception 'Competência inválida.';
  end if;

  if char_length(trim(coalesce(change_reason, ''))) < 3 then
    raise exception 'Informe a justificativa da classificação.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
  for update;

  if not found then
    raise exception 'Ocorrência não encontrada.';
  end if;

  if not public.is_platform_admin(current_user_id)
     and not exists (
       select 1 from public.administration_users member
       where member.administration_id = target_occurrence.administration_id
         and member.user_id = current_user_id
         and member.is_active = true
     ) then
    raise exception 'Usuário sem permissão para classificar competência.' using errcode = '42501';
  end if;

  update public.occurrences
  set jurisdiction_type = jurisdiction,
      external_responsible_name = nullif(trim(coalesce(external_responsible, '')), ''),
      updated_at = now()
  where id = target_occurrence.id;

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
    case when public.is_platform_admin(current_user_id) then 'moderator' else 'administration' end,
    'jurisdiction_changed',
    trim(change_reason),
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object(
      'previous_jurisdiction', target_occurrence.jurisdiction_type,
      'jurisdiction', jurisdiction,
      'external_responsible', nullif(trim(coalesce(external_responsible, '')), '')
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.start_councilor_following(target_occurrence_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  resolved_councilor_id bigint;
  created_following_id bigint;
  target_occurrence public.occurrences%rowtype;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null;

  if not found then
    raise exception 'Ocorrência não encontrada.';
  end if;

  if target_occurrence.status in ('completed', 'closed') then
    raise exception 'Não é possível iniciar acompanhamento em ocorrência finalizada.';
  end if;

  select councilor.id into resolved_councilor_id
  from public.councilor_profiles councilor
  where councilor.profile_id = current_user_id
    and councilor.city_id = target_occurrence.city_id
    and councilor.profile_status in ('verified', 'participant')
    and current_date between councilor.mandate_starts_on and councilor.mandate_ends_on;

  if resolved_councilor_id is null then
    raise exception 'Perfil de vereador verificado é obrigatório.' using errcode = '42501';
  end if;

  insert into public.councilor_followings (
    occurrence_id,
    councilor_profile_id
  )
  values (target_occurrence.id, resolved_councilor_id)
  on conflict (occurrence_id, councilor_profile_id) do update
    set ended_at = null,
        started_at = now(),
        status = 'started'
  returning id into created_following_id;

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
    'councilor',
    'councilor_following_started',
    'Vereador iniciou o acompanhamento da demanda.',
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object('following_id', created_following_id)
  );

  return created_following_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.start_moderation_review(target_report_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas a moderação pode analisar denúncias.' using errcode = '42501';
  end if;

  update public.moderation_reports
  set status = 'in_analysis',
      reviewed_by = current_user_id
  where id = target_report_id
    and status = 'pending';

  if not found then
    raise exception 'Denúncia pendente não encontrada.';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_problem_category(target_category_id bigint, category_name text, category_slug text, category_description text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  resolved_category_id bigint;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores podem configurar categorias.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(category_name, ''))) < 2
     or trim(coalesce(category_slug, '')) !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'Nome ou identificador de categoria inválido.';
  end if;

  if target_category_id is null then
    insert into public.problem_categories (name, slug, description)
    values (
      trim(category_name),
      lower(trim(category_slug)),
      nullif(trim(coalesce(category_description, '')), '')
    )
    returning id into resolved_category_id;
  else
    update public.problem_categories
    set name = trim(category_name),
        slug = lower(trim(category_slug)),
        description = nullif(trim(coalesce(category_description, '')), '')
    where id = target_category_id
    returning id into resolved_category_id;

    if resolved_category_id is null then
      raise exception 'Categoria não encontrada.';
    end if;
  end if;

  return resolved_category_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_featured_badge()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.featured_badge_id is not null
     and new.featured_badge_id is distinct from old.featured_badge_id
     and not exists (
       select 1 from public.user_badges badge
       where badge.user_id = new.id and badge.badge_id = new.featured_badge_id
     ) then
    raise exception 'Somente insígnias conquistadas podem ficar em destaque.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_occurrence_event_evidence_path()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    raise exception 'Caminho de evidência inválido para esta ocorrência.';
  end if;

  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'post-images'
      and object.name = evidence_path
  ) then
    raise exception 'A evidência informada não foi enviada.';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_occurrence_institutional_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    raise exception 'A gestão municipal deve pertencer à cidade da ocorrência.';
  end if;

  if new.agency_id is not null and not exists (
    select 1 from public.public_agencies agency
    where agency.id = new.agency_id
      and agency.city_id = new.city_id
  ) then
    raise exception 'O órgão responsável deve pertencer à cidade da ocorrência.';
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_post_status_transition()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception 'O status do relato só pode ser alterado por uma operação de negócio.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.vote_resolution_cycle(target_cycle_id bigint, vote_decision text, voter_latitude double precision, voter_longitude double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if vote_decision not in ('confirm', 'reject') then
    raise exception 'Voto inválido.';
  end if;

  if voter_latitude not between -90 and 90
     or voter_longitude not between -180 and 180 then
    raise exception 'Coordenadas inválidas.';
  end if;

  select * into target_cycle
  from public.resolution_cycles cycle
  where cycle.id = target_cycle_id
  for update;

  if not found or target_cycle.status <> 'pending' then
    raise exception 'Ciclo de validação não está aberto.';
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
      'Validação expirada sem quórum; status anterior restaurado.'
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
      'Validação encerrada sem quórum; status anterior restaurado.',
      target_occurrence.administration_id,
      target_occurrence.agency_id,
      jsonb_build_object('cycle_id', target_cycle.id)
    );

    return jsonb_build_object('cycle_status', 'expired');
  end if;

  if target_cycle.initiated_by = current_user_id then
    raise exception 'Quem iniciou o ciclo não pode votar nele.';
  end if;

  calculated_distance := public.distance_km(
    voter_latitude,
    voter_longitude,
    target_occurrence.latitude,
    target_occurrence.longitude
  );

  if calculated_distance > target_cycle.radius_km then
    raise exception 'Usuário fora do raio permitido para validação.';
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
      'Resolução confirmada pela comunidade.'
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
      'A comunidade confirmou a resolução da ocorrência.',
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
      'Possível resolução rejeitada pela comunidade.'
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
$function$;

-- Textos já gravados na linha do tempo, no histórico e nas notificações.
create temporary table copy_fix (source text primary key, target text not null);
insert into copy_fix (source, target) values
  ('A cidade da solicitacao e obrigatoria.', 'A cidade da solicitação é obrigatória.'),
  ('A cidade nao possui gestao municipal vigente.', 'A cidade não possui gestão municipal vigente.'),
  ('A comunidade confirmou a resolucao da ocorrencia.', 'A comunidade confirmou a resolução da ocorrência.'),
  ('A descricao deve ter pelo menos 3 caracteres.', 'A descrição deve ter pelo menos 3 caracteres.'),
  ('A evidencia informada nao foi enviada.', 'A evidência informada não foi enviada.'),
  ('A gestao municipal deve pertencer a cidade da ocorrencia.', 'A gestão municipal deve pertencer à cidade da ocorrência.'),
  ('A ocorrencia ja esta com este orgao.', 'A ocorrência já está com este órgão.'),
  ('A ocorrencia nao aceita novas acoes de acompanhamento.', 'A ocorrência não aceita novas ações de acompanhamento.'),
  ('A ocorrencia nao permite iniciar validacao no estado atual.', 'A ocorrência não permite iniciar validação no estado atual.'),
  ('Acompanhamento nao encontrado, finalizado ou sem permissao.', 'Acompanhamento não encontrado, finalizado ou sem permissão.'),
  ('Aguarde o periodo de cooldown antes de tentar novamente.', 'Aguarde o período de espera antes de tentar novamente.'),
  ('Apenas a moderacao pode analisar denuncias.', 'Apenas a moderação pode analisar denúncias.'),
  ('Apenas a moderacao pode concluir denuncias.', 'Apenas a moderação pode concluir denúncias.'),
  ('Apenas a moderacao pode consolidar duplicidades.', 'Apenas a moderação pode consolidar duplicidades.'),
  ('Apenas administradores do UrbApp podem alterar a gestao.', 'Apenas administradores do UrbApp podem alterar a gestão.'),
  ('Apenas administradores podem alterar a validacao.', 'Apenas administradores podem alterar a validação.'),
  ('Atribuicao automatica por cidade e categoria.', 'Atribuição automática por cidade e categoria.'),
  ('Caminho de evidencia invalido para esta ocorrencia.', 'Caminho de evidência inválido para esta ocorrência.'),
  ('Categoria nao encontrada.', 'Categoria não encontrada.'),
  ('Ciclo de validacao nao esta aberto.', 'Ciclo de validação não está aberto.'),
  ('Cidade e categoria sao obrigatorias.', 'Cidade e categoria são obrigatórias.'),
  ('Cidade invalida.', 'Cidade inválida.'),
  ('Cidade nao encontrada.', 'Cidade não encontrada.'),
  ('Comentario nao encontrado.', 'Comentário não encontrado.'),
  ('Competencia invalida.', 'Competência inválida.'),
  ('Confirmar recebimento e uma acao do orgao responsavel.', 'Confirmar recebimento é uma ação do órgão responsável.'),
  ('Coordenadas invalidas.', 'Coordenadas inválidas.'),
  ('Decisao de moderacao invalida.', 'Decisão de moderação inválida.'),
  ('Decisao invalida.', 'Decisão inválida.'),
  ('Denuncia aberta nao encontrada.', 'Denúncia aberta não encontrada.'),
  ('Denuncia pendente nao encontrada.', 'Denúncia pendente não encontrada.'),
  ('Descreva a acao de acompanhamento.', 'Descreva a ação de acompanhamento.'),
  ('Descreva a acao institucional.', 'Descreva a ação institucional.'),
  ('Descreva a possivel resolucao.', 'Descreva a possível resolução.'),
  ('Descreva as provas institucionais para analise.', 'Descreva as provas institucionais para análise.'),
  ('Esta acao e exclusiva da gestao municipal.', 'Esta ação é exclusiva da gestão municipal.'),
  ('Esta categoria exige uma foto recente para informar a resolucao.', 'Esta categoria exige uma foto recente para informar a resolução.'),
  ('Gestao municipal nao reivindicada', 'Gestão municipal não reivindicada'),
  ('Informe a justificativa da classificacao.', 'Informe a justificativa da classificação.'),
  ('Informe o motivo da alteracao.', 'Informe o motivo da alteração.'),
  ('Informe o motivo da consolidacao.', 'Informe o motivo da consolidação.'),
  ('Informe o nome da instituicao.', 'Informe o nome da instituição.'),
  ('Informe o nome da nova gestao.', 'Informe o nome da nova gestão.'),
  ('Informe o tipo da instituicao.', 'Informe o tipo da instituição.'),
  ('Informe um e-mail institucional valido.', 'Informe um e-mail institucional válido.'),
  ('Ja existe gestao com inicio igual ou posterior a esta data.', 'Já existe gestão com início igual ou posterior a esta data.'),
  ('Ja existe uma solicitacao institucional pendente para esta cidade.', 'Já existe uma solicitação institucional pendente para esta cidade.'),
  ('Nao e possivel adicionar relato a uma ocorrencia encerrada.', 'Não é possível adicionar relato a uma ocorrência encerrada.'),
  ('Nao e possivel denunciar o proprio comentario.', 'Não é possível denunciar o próprio comentário.'),
  ('Nao e possivel denunciar o proprio relato.', 'Não é possível denunciar o próprio relato.'),
  ('Nao e possivel iniciar acompanhamento em ocorrencia finalizada.', 'Não é possível iniciar acompanhamento em ocorrência finalizada.'),
  ('Nao foi possivel determinar a gestao e o orgao responsavel.', 'Não foi possível determinar a gestão e o órgão responsável.'),
  ('Nome ou identificador de categoria invalido.', 'Nome ou identificador de categoria inválido.'),
  ('Novo comentario no seu relato', 'Novo comentário no seu relato'),
  ('O orgao deve pertencer a cidade informada.', 'O órgão deve pertencer à cidade informada.'),
  ('O orgao responsavel deve pertencer a cidade da ocorrencia.', 'O órgão responsável deve pertencer à cidade da ocorrência.'),
  ('O titulo deve ter pelo menos 3 caracteres.', 'O título deve ter pelo menos 3 caracteres.'),
  ('Ocorrencia associada automaticamente ao orgao responsavel.', 'Ocorrência associada automaticamente ao órgão responsável.'),
  ('Ocorrencia criada a partir do primeiro relato.', 'Ocorrência criada a partir do primeiro relato.'),
  ('Ocorrencia encerrada nao recebe novas acoes.', 'Ocorrência encerrada não recebe novas ações.'),
  ('Ocorrencia encerrada pela moderacao; nao representa resolucao.', 'Ocorrência encerrada pela moderação; não representa resolução.'),
  ('Ocorrencia herdada pela nova gestao municipal.', 'Ocorrência herdada pela nova gestão municipal.'),
  ('Ocorrencia nao encontrada.', 'Ocorrência não encontrada.'),
  ('Ocorrencia principal ou duplicada nao encontrada.', 'Ocorrência principal ou duplicada não encontrada.'),
  ('Ocorrencia reaberta com nova evidencia.', 'Ocorrência reaberta com nova evidência.'),
  ('Ocorrencia resolvida aceita apenas observacoes oficiais.', 'Ocorrência resolvida aceita apenas observações oficiais.'),
  ('Ocorrencias de cidades diferentes nao podem ser consolidadas.', 'Ocorrências de cidades diferentes não podem ser consolidadas.'),
  ('Orgao municipal responsavel nao definido', 'Órgão municipal responsável não definido'),
  ('Parametros de validacao invalidos.', 'Parâmetros de validação inválidos.'),
  ('Perfil de vereador verificado e obrigatorio.', 'Perfil de vereador verificado é obrigatório.'),
  ('Periodo da gestao invalido.', 'Período da gestão inválido.'),
  ('Possivel resolucao informada; aguardando validacao comunitaria.', 'Possível resolução informada; aguardando validação comunitária.'),
  ('Possivel resolucao informada; validacao comunitaria aberta.', 'Possível resolução informada; validação comunitária aberta.'),
  ('Possivel resolucao rejeitada pela comunidade.', 'Possível resolução rejeitada pela comunidade.'),
  ('Primeiro relato da ocorrencia.', 'Primeiro relato da ocorrência.'),
  ('Provisionamento automatico da categoria.', 'Provisionamento automático da categoria.'),
  ('Provisionamento automatico da cidade.', 'Provisionamento automático da cidade.'),
  ('Quem iniciou o ciclo nao pode votar nele.', 'Quem iniciou o ciclo não pode votar nele.'),
  ('Reabertura exige descricao e nova evidencia.', 'Reabertura exige descrição e nova evidência.'),
  ('Registre a justificativa da decisao.', 'Registre a justificativa da decisão.'),
  ('Relato adicionado a uma ocorrencia existente.', 'Relato adicionado a uma ocorrência existente.'),
  ('Relato associado a ocorrencia principal apos consolidacao de duplicidade.', 'Relato associado à ocorrência principal após consolidação de duplicidade.'),
  ('Relato nao encontrado.', 'Relato não encontrado.'),
  ('Relatos devem ser criados pelas operacoes de ocorrencia.', 'Relatos devem ser criados pelas operações de ocorrência.'),
  ('Resolucao confirmada pela comunidade.', 'Resolução confirmada pela comunidade.'),
  ('Selecione duas ocorrencias diferentes.', 'Selecione duas ocorrências diferentes.'),
  ('Selecione um orgao valido da mesma cidade.', 'Selecione um órgão válido da mesma cidade.'),
  ('Solicitacao pendente nao encontrada.', 'Solicitação pendente não encontrada.'),
  ('Somente insignias conquistadas podem ficar em destaque.', 'Somente insígnias conquistadas podem ficar em destaque.'),
  ('Somente ocorrencias resolvidas podem ser reabertas.', 'Somente ocorrências resolvidas podem ser reabertas.'),
  ('Status de reporte so pode ser alterado por uma operacao de negocio.', 'O status do relato só pode ser alterado por uma operação de negócio.'),
  ('Tipo de acao institucional invalido.', 'Tipo de ação institucional inválido.'),
  ('Tipo de ator invalido.', 'Tipo de ator inválido.'),
  ('Tipo de conteudo nao suportado.', 'Tipo de conteúdo não suportado.'),
  ('Tipo de perfil institucional invalido.', 'Tipo de perfil institucional inválido.'),
  ('Usuario autenticado e obrigatorio.', 'Usuário autenticado é obrigatório.'),
  ('Usuario fora do raio permitido para validacao.', 'Usuário fora do raio permitido para validação.'),
  ('Usuario nao esta autorizado a atuar com esse papel.', 'Usuário não está autorizado a atuar com esse papel.'),
  ('Usuario nao representa a gestao ou o orgao responsavel.', 'Usuário não representa a gestão ou o órgão responsável.'),
  ('Usuario sem permissao para classificar competencia.', 'Usuário sem permissão para classificar competência.'),
  ('Usuario sem permissao para configurar responsabilidades.', 'Usuário sem permissão para configurar responsabilidades.'),
  ('Validacao encerrada sem quorum; status anterior restaurado.', 'Validação encerrada sem quórum; status anterior restaurado.'),
  ('Validacao expirada sem quorum; status anterior restaurado.', 'Validação expirada sem quórum; status anterior restaurado.'),
  ('Voto invalido.', 'Voto inválido.');

update public.occurrence_events event
set description = fix.target
from copy_fix fix
where event.description = fix.source;

update public.notifications notification
set body = fix.target
from copy_fix fix
where notification.body = fix.source;

update public.notifications notification
set title = fix.target
from copy_fix fix
where notification.title = fix.source;

update public.post_status_history history
set note = fix.target
from copy_fix fix
where history.note = fix.source;

-- Nomes provisórios criados automaticamente para cidades e categorias.
update public.public_agencies agency
set name = fix.target
from copy_fix fix
where agency.name = fix.source;

update public.municipal_administrations administration
set name = fix.target
from copy_fix fix
where administration.name = fix.source;

drop table copy_fix;
