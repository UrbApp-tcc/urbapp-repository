-- Completa o ciclo independente de acompanhamento parlamentar.

alter table public.councilor_followings
  drop constraint if exists councilor_followings_status_check;

alter table public.councilor_followings
  add constraint councilor_followings_status_check
  check (status in (
    'started', 'action_registered', 'awaiting_response', 'resolved', 'ended'
  ));

create or replace function public.start_councilor_following(target_occurrence_id bigint)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  resolved_councilor_id bigint;
  created_following_id bigint;
  target_occurrence public.occurrences%rowtype;
begin
  if current_user_id is null then
    raise exception 'Usuario autenticado e obrigatorio.' using errcode = '42501';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_occurrence_id
    and occurrence.invalidated_at is null;

  if not found then
    raise exception 'Ocorrencia nao encontrada.';
  end if;

  if target_occurrence.status in ('completed', 'closed') then
    raise exception 'Nao e possivel iniciar acompanhamento em ocorrencia finalizada.';
  end if;

  select councilor.id into resolved_councilor_id
  from public.councilor_profiles councilor
  where councilor.profile_id = current_user_id
    and councilor.city_id = target_occurrence.city_id
    and councilor.profile_status in ('verified', 'participant')
    and current_date between councilor.mandate_starts_on and councilor.mandate_ends_on;

  if resolved_councilor_id is null then
    raise exception 'Perfil de vereador verificado e obrigatorio.' using errcode = '42501';
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
$$;

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
    raise exception 'Acompanhamento nao encontrado, finalizado ou sem permissao.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(action_description, ''))) < 3 then
    raise exception 'Descreva a acao de acompanhamento.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_following.occurrence_id;

  insert into public.councilor_actions (
    following_id,
    action_type,
    description,
    evidence_storage_path
  )
  values (
    target_following.id,
    councilor_action_type,
    trim(action_description),
    nullif(trim(coalesce(evidence_storage_path, '')), '')
  )
  returning id into created_action_id;

  update public.councilor_followings
  set status = case
        when councilor_action_type in (
          'forwarding', 'request', 'charge', 'official_letter', 'agency_contact'
        ) then 'awaiting_response'
        else 'action_registered'
      end
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
    'councilor_' || councilor_action_type,
    trim(action_description),
    target_occurrence.administration_id,
    target_occurrence.agency_id,
    jsonb_build_object(
      'following_id', target_following.id,
      'councilor_action_id', created_action_id,
      'evidence_storage_path', nullif(trim(coalesce(evidence_storage_path, '')), '')
    )
  );

  if councilor_action_type = 'possible_resolution' then
    perform public.open_resolution_cycle(
      target_occurrence.id,
      trim(action_description),
      'councilor'
    );
  end if;

  return created_action_id;
end;
$$;

create or replace function public.end_councilor_following(
  target_following_id bigint,
  closing_description text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
    raise exception 'Acompanhamento nao encontrado, finalizado ou sem permissao.' using errcode = '42501';
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
$$;

create or replace function public.mark_councilor_followings_resolved()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'completed' and old.status is distinct from new.status then
    update public.councilor_followings
    set status = 'resolved',
        ended_at = coalesce(ended_at, coalesce(new.resolved_at, now()))
    where occurrence_id = new.id
      and ended_at is null
      and status not in ('resolved', 'ended');
  end if;
  return new;
end;
$$;

drop trigger if exists mark_councilor_followings_resolved on public.occurrences;
create trigger mark_councilor_followings_resolved
after update of status on public.occurrences
for each row execute function public.mark_councilor_followings_resolved();

revoke all on function public.end_councilor_following(bigint, text) from public;
grant execute on function public.end_councilor_following(bigint, text) to authenticated;

notify pgrst, 'reload schema';
