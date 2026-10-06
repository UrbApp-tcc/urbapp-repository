-- UrbApp: ações institucionais completas e indicadores sem dupla contagem.
-- Spec §3.2, §3.3, §11, §12, §13, §34, §35, §36 e §44.6.

-- ---------------------------------------------------------------------------
-- 1. Órgão verificado: confirmar recebimento, atualizar andamento e registrar
--    observação oficial (spec §3.3). Uma conclusão informada durante um ciclo
--    já aberto é registrada sem abrir outro ciclo.
-- ---------------------------------------------------------------------------

alter table public.institutional_actions drop constraint if exists institutional_actions_type_check;
alter table public.institutional_actions
  add constraint institutional_actions_type_check
  check (action_type in (
    'received', 'priority', 'forwarding', 'request', 'official_position', 'forecast',
    'analysis', 'scheduled', 'in_progress', 'progress_update', 'executed',
    'observation', 'conclusion'
  ));

create or replace function public.register_institutional_action(
  target_occurrence_id bigint,
  institutional_action_type text,
  action_description text,
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
    raise exception 'Usuario autenticado e obrigatorio.' using errcode = '42501';
  end if;

  if institutional_action_type not in (
    'received', 'priority', 'forwarding', 'request', 'official_position', 'forecast',
    'analysis', 'scheduled', 'in_progress', 'progress_update', 'executed',
    'observation', 'conclusion'
  ) then
    raise exception 'Tipo de acao institucional invalido.';
  end if;

  if char_length(trim(coalesce(action_description, ''))) < 3 then
    raise exception 'Descreva a acao institucional.';
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
    raise exception 'Ocorrencia nao encontrada.';
  end if;

  if target_occurrence.status in ('closed') then
    raise exception 'Ocorrencia encerrada nao recebe novas acoes.';
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
    raise exception 'Usuario nao representa a gestao ou o orgao responsavel.' using errcode = '42501';
  end if;

  if institutional_action_type in ('priority', 'forwarding', 'request')
     and resolved_actor_kind <> 'administration' then
    raise exception 'Esta acao e exclusiva da gestao municipal.' using errcode = '42501';
  end if;

  if institutional_action_type = 'received' and resolved_actor_kind <> 'agency' then
    raise exception 'Confirmar recebimento e uma acao do orgao responsavel.' using errcode = '42501';
  end if;

  if target_occurrence.status = 'completed'
     and institutional_action_type not in ('observation', 'official_position') then
    raise exception 'Ocorrencia resolvida aceita apenas observacoes oficiais.';
  end if;

  if institutional_action_type = 'forwarding' then
    if action_target_agency_id is null or not exists (
      select 1 from public.public_agencies agency
      where agency.id = action_target_agency_id
        and agency.city_id = target_occurrence.city_id
    ) then
      raise exception 'Selecione um orgao valido da mesma cidade.';
    end if;

    if action_target_agency_id = target_occurrence.agency_id then
      raise exception 'A ocorrencia ja esta com este orgao.';
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

revoke all on function public.register_institutional_action(bigint, text, text, bigint, timestamptz, text)
  from public, anon;
grant execute on function public.register_institutional_action(bigint, text, text, bigint, timestamptz, text)
  to authenticated;

-- Possível resolução informada por vereador durante um ciclo aberto não falha.
create or replace function public.register_councilor_action(
  target_following_id bigint,
  councilor_action_type text,
  action_description text,
  evidence_storage_path text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
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
    raise exception 'Acompanhamento nao encontrado, finalizado ou sem permissao.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(action_description, ''))) < 3 then
    raise exception 'Descreva a acao de acompanhamento.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_following.occurrence_id
  for update;

  if target_occurrence.invalidated_at is not null or target_occurrence.status in ('completed', 'closed') then
    raise exception 'A ocorrencia nao aceita novas acoes de acompanhamento.';
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
$$;

revoke all on function public.register_councilor_action(bigint, text, text, text) from public, anon;
grant execute on function public.register_councilor_action(bigint, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Indicadores (spec §11–§13, §34, §36): ocorrências fora da competência
--    municipal não entram na gestão/órgão; estados correntes contam apenas para
--    o órgão atual; herdadas derivam dos eventos de troca de gestão; crédito de
--    vereador exige ação concreta durante o acompanhamento e antes da resolução.
-- ---------------------------------------------------------------------------

create or replace view public.administration_occurrence_metrics
with (security_invoker = true)
as
select
  administration.id as administration_id,
  administration.city_id,
  administration.name,
  administration.starts_on,
  administration.ends_on,
  occurrence_metrics.registered_during_period,
  inherited_metrics.inherited_occurrences,
  resolution_metrics.resolved_during_period,
  action_metrics.prioritized_occurrences,
  action_metrics.officially_answered_occurrences,
  administration.mayor_name,
  administration.is_placeholder,
  administration.is_verified,
  occurrence_metrics.active_occurrences,
  left_metrics.left_pending_occurrences,
  action_metrics.manifested_occurrences,
  action_metrics.forwarded_occurrences,
  action_metrics.forecasted_occurrences,
  action_metrics.conclusions_informed,
  action_metrics.confirmed_conclusions,
  action_metrics.rejected_conclusions,
  action_metrics.average_seconds_to_first_manifestation,
  action_metrics.average_seconds_to_conclusion
from public.municipal_administrations administration
cross join lateral (
  select
    count(*) filter (where occurrence.created_administration_id = administration.id)
      as registered_during_period,
    count(*) filter (
      where occurrence.administration_id = administration.id
        and occurrence.status in ('open', 'in_analysis', 'in_progress', 'awaiting_validation', 'reopened')
    ) as active_occurrences
  from public.occurrences occurrence
  where occurrence.invalidated_at is null
    and occurrence.merged_into_occurrence_id is null
    and occurrence.jurisdiction_type = 'municipal'
    and (occurrence.created_administration_id = administration.id
         or occurrence.administration_id = administration.id)
) occurrence_metrics
cross join lateral (
  select count(distinct event.occurrence_id) as inherited_occurrences
  from public.occurrence_events event
  join public.occurrences occurrence on occurrence.id = event.occurrence_id
  where event.event_type = 'administration_changed'
    and event.administration_id = administration.id
    and occurrence.invalidated_at is null
    and occurrence.jurisdiction_type = 'municipal'
) inherited_metrics
cross join lateral (
  select count(distinct event.occurrence_id) as resolved_during_period
  from public.occurrence_events event
  join public.occurrences occurrence on occurrence.id = event.occurrence_id
  where event.administration_id = administration.id
    and event.event_type = 'resolution_confirmed'
    and occurrence.invalidated_at is null
    and occurrence.jurisdiction_type = 'municipal'
) resolution_metrics
cross join lateral (
  select count(distinct event.occurrence_id) as left_pending_occurrences
  from public.occurrence_events event
  join public.occurrences occurrence on occurrence.id = event.occurrence_id
  where event.event_type = 'administration_changed'
    and event.metadata ->> 'previous_administration_id' = administration.id::text
    and occurrence.invalidated_at is null
    and occurrence.jurisdiction_type = 'municipal'
) left_metrics
cross join lateral (
  select
    count(distinct action.occurrence_id) filter (where action.action_type = 'priority')
      as prioritized_occurrences,
    count(distinct action.occurrence_id) filter (where action.action_type = 'official_position')
      as officially_answered_occurrences,
    count(distinct action.occurrence_id) as manifested_occurrences,
    count(distinct action.occurrence_id) filter (where action.action_type = 'forwarding')
      as forwarded_occurrences,
    count(distinct action.occurrence_id) filter (where action.action_type = 'forecast')
      as forecasted_occurrences,
    count(distinct action.occurrence_id) filter (where action.action_type = 'conclusion')
      as conclusions_informed,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
        and exists (
          select 1 from public.occurrence_events event
          where event.occurrence_id = action.occurrence_id
            and event.event_type = 'resolution_confirmed'
            and event.created_at > action.created_at
        )
    ) as confirmed_conclusions,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
        and exists (
          select 1 from public.occurrence_events event
          where event.occurrence_id = action.occurrence_id
            and event.event_type = 'validation_rejected'
            and event.created_at > action.created_at
        )
    ) as rejected_conclusions,
    (
      select avg(extract(epoch from first_action.created_at - occurrence.created_at))
      from public.occurrences occurrence
      cross join lateral (
        select min(source.created_at) as created_at
        from public.institutional_actions source
        where source.occurrence_id = occurrence.id
          and source.administration_id = administration.id
          and source.actor_kind = 'administration'
      ) first_action
      where occurrence.invalidated_at is null
        and occurrence.jurisdiction_type = 'municipal'
        and first_action.created_at is not null
    ) as average_seconds_to_first_manifestation,
    (
      select avg(extract(epoch from first_conclusion.created_at - occurrence.created_at))
      from public.occurrences occurrence
      cross join lateral (
        select min(source.created_at) as created_at
        from public.institutional_actions source
        where source.occurrence_id = occurrence.id
          and source.administration_id = administration.id
          and source.actor_kind = 'administration'
          and source.action_type = 'conclusion'
      ) first_conclusion
      where occurrence.invalidated_at is null
        and occurrence.jurisdiction_type = 'municipal'
        and first_conclusion.created_at is not null
    ) as average_seconds_to_conclusion
  from public.institutional_actions action
  join public.occurrences occurrence on occurrence.id = action.occurrence_id
  where action.administration_id = administration.id
    and action.actor_kind = 'administration'
    and occurrence.invalidated_at is null
    and occurrence.jurisdiction_type = 'municipal'
) action_metrics;

create or replace view public.agency_occurrence_metrics
with (security_invoker = true)
as
select
  agency.id as agency_id,
  agency.city_id,
  agency.name,
  agency.profile_status,
  historical_metrics.assigned_occurrences,
  current_metrics.resolved_occurrences,
  action_metrics.official_actions,
  action_metrics.first_recorded_action_at,
  current_metrics.open_occurrences,
  current_metrics.in_progress_occurrences,
  current_metrics.awaiting_validation_occurrences,
  action_metrics.officially_answered_occurrences,
  action_metrics.official_response_percentage,
  action_metrics.conclusions_informed,
  action_metrics.confirmed_conclusions,
  action_metrics.rejected_conclusions,
  responsibility_metrics.average_responsibility_seconds,
  responsibility_metrics.median_responsibility_seconds,
  action_metrics.average_seconds_to_first_response,
  historical_metrics.categories_count,
  historical_metrics.neighborhoods_count
from public.public_agencies agency
cross join lateral (
  select
    count(distinct occurrence.id) as assigned_occurrences,
    count(distinct occurrence.category_id) as categories_count,
    count(distinct nullif(trim(occurrence.neighborhood), '')) as neighborhoods_count
  from public.occurrence_agency_assignments assignment
  join public.occurrences occurrence on occurrence.id = assignment.occurrence_id
  where assignment.agency_id = agency.id
    and occurrence.invalidated_at is null
    and occurrence.merged_into_occurrence_id is null
    and occurrence.jurisdiction_type = 'municipal'
) historical_metrics
cross join lateral (
  -- Estados correntes e resoluções pertencem ao órgão responsável no momento.
  select
    count(*) filter (where occurrence.status = 'completed') as resolved_occurrences,
    count(*) filter (where occurrence.status in ('open', 'reopened')) as open_occurrences,
    count(*) filter (where occurrence.status in ('in_analysis', 'in_progress')) as in_progress_occurrences,
    count(*) filter (where occurrence.status = 'awaiting_validation') as awaiting_validation_occurrences
  from public.occurrences occurrence
  where occurrence.agency_id = agency.id
    and occurrence.invalidated_at is null
    and occurrence.merged_into_occurrence_id is null
    and occurrence.jurisdiction_type = 'municipal'
) current_metrics
cross join lateral (
  select
    avg(extract(epoch from (
      coalesce(assignment.ends_at,
               case when occurrence.status = 'completed' then occurrence.resolved_at end,
               now()) - assignment.starts_at
    ))) as average_responsibility_seconds,
    percentile_cont(0.5) within group (
      order by extract(epoch from (
        coalesce(assignment.ends_at,
                 case when occurrence.status = 'completed' then occurrence.resolved_at end,
                 now()) - assignment.starts_at
      ))
    ) as median_responsibility_seconds
  from public.occurrence_agency_assignments assignment
  join public.occurrences occurrence on occurrence.id = assignment.occurrence_id
  where assignment.agency_id = agency.id
    and occurrence.invalidated_at is null
    and occurrence.jurisdiction_type = 'municipal'
) responsibility_metrics
cross join lateral (
  select
    count(action.id) as official_actions,
    min(action.created_at) as first_recorded_action_at,
    count(distinct action.occurrence_id) as officially_answered_occurrences,
    round(
      case when historical_metrics.assigned_occurrences = 0 then 0
           else count(distinct action.occurrence_id)::numeric
                / historical_metrics.assigned_occurrences::numeric * 100 end,
      2
    ) as official_response_percentage,
    count(distinct action.occurrence_id) filter (where action.action_type = 'conclusion')
      as conclusions_informed,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
        and exists (
          select 1 from public.occurrence_events event
          where event.occurrence_id = action.occurrence_id
            and event.event_type = 'resolution_confirmed'
            and event.created_at > action.created_at
        )
    ) as confirmed_conclusions,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
        and exists (
          select 1 from public.occurrence_events event
          where event.occurrence_id = action.occurrence_id
            and event.event_type = 'validation_rejected'
            and event.created_at > action.created_at
        )
    ) as rejected_conclusions,
    avg(extract(epoch from action.created_at - assignment.starts_at)) filter (
      where action.created_at = (
        select min(first_action.created_at)
        from public.institutional_actions first_action
        where first_action.occurrence_id = action.occurrence_id
          and first_action.agency_id = agency.id
          and first_action.actor_kind = 'agency'
      )
    ) as average_seconds_to_first_response
  from public.institutional_actions action
  join public.occurrence_agency_assignments assignment
    on assignment.occurrence_id = action.occurrence_id
   and assignment.agency_id = agency.id
   and action.created_at >= assignment.starts_at
   and (assignment.ends_at is null or action.created_at <= assignment.ends_at)
  join public.occurrences occurrence on occurrence.id = action.occurrence_id
  where action.agency_id = agency.id
    and action.actor_kind = 'agency'
    and occurrence.invalidated_at is null
    and occurrence.jurisdiction_type = 'municipal'
) action_metrics;

create or replace view public.councilor_activity_metrics
with (security_invoker = true)
as
select
  councilor.id as councilor_profile_id,
  councilor.profile_id,
  councilor.city_id,
  councilor.public_name,
  count(distinct following.id) filter (where occurrence.id is not null) as followed_demands,
  count(distinct action.id) filter (where occurrence.id is not null) as registered_actions,
  count(distinct following.id) filter (
    where occurrence.id is not null
      and exists (
        select 1
        from public.councilor_actions concrete_action
        join public.occurrence_events resolution_event
          on resolution_event.occurrence_id = following.occurrence_id
         and resolution_event.event_type = 'resolution_confirmed'
         and resolution_event.created_at > concrete_action.created_at
         and resolution_event.created_at >= following.started_at
         and (following.ended_at is null or resolution_event.created_at <= following.ended_at)
        where concrete_action.following_id = following.id
          and concrete_action.action_type <> 'possible_resolution'
          and concrete_action.created_at >= following.started_at
      )
  ) as followed_demands_that_reached_resolution,
  councilor.party,
  councilor.profile_status,
  count(distinct action.id) filter (
    where occurrence.id is not null
      and action.action_type in ('forwarding', 'request', 'agency_contact')
  ) as forwarding_actions,
  count(distinct action.id) filter (where occurrence.id is not null and action.action_type = 'charge')
    as charge_actions,
  count(distinct action.id) filter (where occurrence.id is not null and action.action_type = 'official_letter')
    as official_letters,
  count(distinct following.id) filter (
    where occurrence.id is not null and following.status = 'awaiting_response'
  ) as awaiting_response_demands,
  count(distinct following.id) filter (
    where following.ended_at is null
      and occurrence.status in ('open', 'in_analysis', 'in_progress', 'awaiting_validation', 'reopened')
  ) as followed_open_demands,
  count(distinct following.id) filter (
    where occurrence.id is not null
      and following.status = 'ended'
      and not exists (
        select 1 from public.occurrence_events resolution_event
        where resolution_event.occurrence_id = following.occurrence_id
          and resolution_event.event_type = 'resolution_confirmed'
          and resolution_event.created_at >= following.started_at
      )
  ) as ended_without_resolution,
  avg(extract(epoch from (coalesce(following.ended_at, now()) - following.started_at)))
    filter (where occurrence.id is not null) as average_followup_seconds
from public.councilor_profiles councilor
left join public.councilor_followings following on following.councilor_profile_id = councilor.id
left join public.occurrences occurrence
  on occurrence.id = following.occurrence_id
 and occurrence.invalidated_at is null
left join public.councilor_actions action on action.following_id = following.id
group by councilor.id;

grant select on public.administration_occurrence_metrics to anon, authenticated;
grant select on public.agency_occurrence_metrics to anon, authenticated;
grant select on public.councilor_activity_metrics to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Leituras de apoio às telas (sem regras de negócio no cliente).
-- ---------------------------------------------------------------------------

-- Contexto de validação para o usuário atual: o backend informa se ele pode
-- iniciar um ciclo, se já votou e até quando dura o cooldown.
create or replace function public.get_resolution_context(target_occurrence_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_occurrence public.occurrences%rowtype;
  selected_settings public.validation_settings%rowtype;
  pending_cycle public.resolution_cycles%rowtype;
  cooldown_until timestamptz;
  my_vote text;
  evidence_required boolean;
  confirmations integer := 0;
  rejections integer := 0;
begin
  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id and occurrence.invalidated_at is null;

  if not found then
    return null;
  end if;

  select * into selected_settings
  from public.validation_settings settings
  where settings.city_id = target_occurrence.city_id or settings.city_id is null
  order by settings.city_id nulls last
  limit 1;

  select category.requires_resolution_evidence into evidence_required
  from public.problem_categories category where category.id = target_occurrence.category_id;

  select * into pending_cycle
  from public.resolution_cycles cycle
  where cycle.occurrence_id = target_occurrence.id and cycle.status = 'pending';

  if pending_cycle.id is not null then
    select
      count(*) filter (where vote.decision = 'confirm'),
      count(*) filter (where vote.decision = 'reject')
    into confirmations, rejections
    from public.resolution_votes vote where vote.cycle_id = pending_cycle.id;

    if current_user_id is not null then
      select vote.decision into my_vote
      from public.resolution_votes vote
      where vote.cycle_id = pending_cycle.id and vote.voter_id = current_user_id;
    end if;
  end if;

  if current_user_id is not null then
    select greatest(coalesce(cycle.closed_at, cycle.expires_at), cycle.opened_at) + cycle.initiator_cooldown
    into cooldown_until
    from public.resolution_cycles cycle
    where cycle.occurrence_id = target_occurrence.id
      and cycle.initiated_by = current_user_id
      and cycle.status in ('rejected', 'expired')
    order by cycle.opened_at desc
    limit 1;

    if cooldown_until <= now() then
      cooldown_until := null;
    end if;
  end if;

  return jsonb_build_object(
    'occurrence_status', target_occurrence.status,
    'can_start', current_user_id is not null
      and target_occurrence.status in ('open', 'in_analysis', 'in_progress', 'reopened')
      and cooldown_until is null,
    'cooldown_until', cooldown_until,
    'evidence_required', coalesce(evidence_required, false),
    'settings', jsonb_build_object(
      'confirmations_required', selected_settings.confirmations_required,
      'rejections_required', selected_settings.rejections_required,
      'radius_km', selected_settings.radius_km,
      'duration_hours', extract(epoch from selected_settings.cycle_duration) / 3600,
      'cooldown_hours', extract(epoch from selected_settings.initiator_cooldown) / 3600
    ),
    'cycle', case when pending_cycle.id is null then null else jsonb_build_object(
      'id', pending_cycle.id,
      'initiator_kind', pending_cycle.initiator_kind,
      'initiated_by_me', pending_cycle.initiated_by = current_user_id,
      'description', pending_cycle.description,
      'evidence_storage_path', pending_cycle.evidence_storage_path,
      'opened_at', pending_cycle.opened_at,
      'expires_at', pending_cycle.expires_at,
      'confirmations', confirmations,
      'rejections', rejections,
      'confirmations_required', pending_cycle.confirmations_required,
      'rejections_required', pending_cycle.rejections_required,
      'radius_km', pending_cycle.radius_km,
      'my_vote', my_vote
    ) end
  );
end;
$$;

revoke all on function public.get_resolution_context(bigint) from public;
grant execute on function public.get_resolution_context(bigint) to anon, authenticated;

-- Ocorrências próximas aguardando validação em que o usuário ainda pode votar.
create or replace function public.get_pending_validations_near(
  origin_latitude double precision,
  origin_longitude double precision,
  page_size integer default 10
)
returns setof public.occurrence_feed_rows
language sql
stable
security definer
set search_path = public
as $$
  select feed.*
  from public.occurrence_feed_rows feed
  join public.resolution_cycles cycle
    on cycle.occurrence_id = feed.id
   and cycle.status = 'pending'
   and cycle.expires_at > now()
  where auth.uid() is not null
    and cycle.initiated_by <> auth.uid()
    and not exists (
      select 1 from public.resolution_votes vote
      where vote.cycle_id = cycle.id and vote.voter_id = auth.uid()
    )
    and public.distance_km(origin_latitude, origin_longitude, feed.latitude, feed.longitude)
        <= cycle.radius_km
  order by public.distance_km(origin_latitude, origin_longitude, feed.latitude, feed.longitude)
  limit least(greatest(coalesce(page_size, 10), 1), 50);
$$;

revoke all on function public.get_pending_validations_near(double precision, double precision, integer) from public;
grant execute on function public.get_pending_validations_near(double precision, double precision, integer) to authenticated;

-- Histórico de validações do próprio usuário (Perfil → Validações).
create or replace function public.get_my_validation_votes()
returns table (
  vote_id bigint,
  occurrence_id bigint,
  decision text,
  voted_at timestamptz,
  cycle_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select vote.id, cycle.occurrence_id, vote.decision, vote.created_at, cycle.status
  from public.resolution_votes vote
  join public.resolution_cycles cycle on cycle.id = vote.cycle_id
  where vote.voter_id = auth.uid()
  order by vote.created_at desc;
$$;

revoke all on function public.get_my_validation_votes() from public, anon;
grant execute on function public.get_my_validation_votes() to authenticated;

-- Contribuições públicas de um perfil (relatos não anônimos) e as do próprio
-- usuário, incluindo anônimas, que só ele vê.
alter table public.profiles add column if not exists is_public boolean not null default true;
grant update (is_public) on public.profiles to authenticated;

create or replace function public.get_profile_contributions(target_profile_id uuid)
returns table (
  occurrence_id bigint,
  post_id bigint,
  is_anonymous boolean,
  is_initiator boolean,
  contributed_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    post.occurrence_id,
    post.id,
    post.anonymity,
    post.id = (
      select first_post.id from public.posts first_post
      where first_post.occurrence_id = post.occurrence_id
      order by first_post.created_at, first_post.id
      limit 1
    ),
    post.created_at
  from public.posts post
  join public.profiles profile on profile.id = post.user_id
  join public.occurrences occurrence on occurrence.id = post.occurrence_id
  where post.user_id = target_profile_id
    and occurrence.invalidated_at is null
    and (
      target_profile_id = auth.uid()
      or (profile.is_public and not post.anonymity and post.hidden_at is null)
    )
  order by post.created_at desc;
$$;

revoke all on function public.get_profile_contributions(uuid) from public;
grant execute on function public.get_profile_contributions(uuid) to anon, authenticated;

-- Resumo de participação (contagens derivadas, não editáveis).
create or replace function public.get_participation_summary(target_profile_id uuid default auth.uid())
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'reports', (
      select count(distinct post.occurrence_id) from public.posts post
      where post.user_id = target_profile_id and post.hidden_at is null
        and (target_profile_id = auth.uid() or not post.anonymity)
    ),
    'supports', (
      select count(*) from public.occurrence_supports support
      where support.user_id = target_profile_id
    ),
    'validations', (
      select count(*) from public.resolution_votes vote
      where vote.voter_id = target_profile_id
    ),
    'following', (
      select count(*) from public.occurrence_followers follower
      where follower.user_id = target_profile_id
    )
  );
$$;

revoke all on function public.get_participation_summary(uuid) from public;
grant execute on function public.get_participation_summary(uuid) to anon, authenticated;

-- Realtime das interações da ocorrência.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'occurrence_supports'
  ) then
    alter publication supabase_realtime add table public.occurrence_supports;
  end if;
end;
$$;

notify pgrst, 'reload schema';

-- Administração define quais categorias exigem foto para informar resolução.
create or replace function public.set_category_resolution_evidence(
  target_category_id bigint,
  evidence_required boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
    raise exception 'Categoria nao encontrada.';
  end if;
end;
$$;

revoke all on function public.set_category_resolution_evidence(bigint, boolean) from public, anon;
grant execute on function public.set_category_resolution_evidence(bigint, boolean) to authenticated;

notify pgrst, 'reload schema';
