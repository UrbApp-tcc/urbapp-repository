-- Permite que a gestão municipal retire uma prioridade e preserve a decisão
-- no histórico público da ocorrência.

alter table public.institutional_actions
  drop constraint if exists institutional_actions_type_check;

alter table public.institutional_actions
  add constraint institutional_actions_type_check
  check (action_type in (
    'received', 'priority', 'priority_removed', 'forwarding', 'request',
    'official_position', 'forecast', 'analysis', 'scheduled', 'in_progress',
    'progress_update', 'executed', 'observation', 'conclusion'
  ));

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

revoke all on function public.set_administration_occurrence_priority(bigint, boolean, text)
  from public, anon;
grant execute on function public.set_administration_occurrence_priority(bigint, boolean, text)
  to authenticated;
