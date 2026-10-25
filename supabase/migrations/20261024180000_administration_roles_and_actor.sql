-- Papéis internos e autoria explícita das ações institucionais.
-- Gestores e operadores podem agir; analistas possuem acesso de consulta.

create or replace function public.register_institutional_action_as(
  target_occurrence_id bigint,
  institutional_action_type text,
  action_description text,
  requested_actor_kind text,
  action_target_agency_id bigint default null,
  action_forecast_at timestamptz default null,
  evidence_storage_path text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
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

  if requested_actor_kind not in ('administration', 'agency') then
    raise exception 'Informe se a ação será realizada pela Prefeitura ou pelo órgão.';
  end if;

  if requested_actor_kind = 'administration' and exists (
    select 1
    from public.administration_users member
    where member.administration_id = target_occurrence.administration_id
      and member.user_id = current_user_id
      and member.is_active = true
      and member.role in ('manager', 'agent')
  ) then
    resolved_actor_kind := 'administration';
  elsif requested_actor_kind = 'agency' and exists (
    select 1
    from public.agency_users member
    where member.agency_id = target_occurrence.agency_id
      and member.user_id = current_user_id
      and member.is_active = true
  ) then
    resolved_actor_kind := 'agency';
  else
    raise exception 'Seu papel atual não permite registrar esta ação.' using errcode = '42501';
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
$$;

revoke all on function public.register_institutional_action(
  bigint, text, text, bigint, timestamptz, text
) from authenticated;

revoke all on function public.register_institutional_action_as(
  bigint, text, text, text, bigint, timestamptz, text
) from public, anon;
grant execute on function public.register_institutional_action_as(
  bigint, text, text, text, bigint, timestamptz, text
) to authenticated;

create or replace function public.set_administration_occurrence_priority(
  target_occurrence_id bigint,
  priority_enabled boolean,
  action_description text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
  action_type_value text;
  created_action_id bigint;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(action_description, ''))) < 3 then
    raise exception 'Descreva a justificativa da decisão.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null
  for update;

  if not found then
    raise exception 'Ocorrência não encontrada.';
  end if;

  if target_occurrence.status = 'closed' then
    raise exception 'Ocorrência encerrada não pode ter a prioridade alterada.';
  end if;

  if not exists (
    select 1
    from public.administration_users member
    where member.administration_id = target_occurrence.administration_id
      and member.user_id = current_user_id
      and member.is_active = true
      and member.role in ('manager', 'agent')
  ) then
    raise exception 'Usuário não representa a gestão municipal responsável.'
      using errcode = '42501';
  end if;

  if target_occurrence.administrative_priority = priority_enabled then
    if priority_enabled then
      raise exception 'A ocorrência já está priorizada.';
    else
      raise exception 'A ocorrência não está priorizada.';
    end if;
  end if;

  action_type_value := case
    when priority_enabled then 'priority'
    else 'priority_removed'
  end;

  update public.occurrences
  set administrative_priority = priority_enabled
  where id = target_occurrence.id;

  insert into public.institutional_actions (
    occurrence_id,
    administration_id,
    created_by,
    actor_kind,
    action_type,
    description
  )
  values (
    target_occurrence.id,
    target_occurrence.administration_id,
    current_user_id,
    'administration',
    action_type_value,
    trim(action_description)
  )
  returning id into created_action_id;

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
    'administration',
    'institutional_' || action_type_value,
    trim(action_description),
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object(
      'institutional_action_id', created_action_id,
      'priority_enabled', priority_enabled
    )
  );

  return created_action_id;
end;
$$;
