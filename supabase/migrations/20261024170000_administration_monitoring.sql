-- Monitoramento operacional da Prefeitura: validação comunitária e alertas.

create or replace function public.get_administration_validation_overview(
  target_administration_id bigint,
  target_occurrence_ids bigint[]
)
returns table (
  occurrence_id bigint,
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
    occurrence.id,
    cycle.status,
    cycle.opened_at,
    cycle.expires_at,
    count(vote.id) filter (where vote.decision = 'confirm')::integer,
    count(vote.id) filter (where vote.decision = 'reject')::integer,
    cycle.confirmations_required,
    cycle.rejections_required
  from public.administration_users member
  join public.occurrences occurrence
    on occurrence.administration_id = member.administration_id
  join lateral (
    select candidate.*
    from public.resolution_cycles candidate
    where candidate.occurrence_id = occurrence.id
    order by candidate.opened_at desc
    limit 1
  ) cycle on true
  left join public.resolution_votes vote on vote.cycle_id = cycle.id
  where member.administration_id = target_administration_id
    and member.user_id = auth.uid()
    and member.is_active = true
    and occurrence.id = any(coalesce(target_occurrence_ids, array[]::bigint[]))
  group by
    occurrence.id,
    cycle.id,
    cycle.status,
    cycle.opened_at,
    cycle.expires_at,
    cycle.confirmations_required,
    cycle.rejections_required;
$$;

revoke all on function public.get_administration_validation_overview(bigint, bigint[])
  from public, anon;
grant execute on function public.get_administration_validation_overview(bigint, bigint[])
  to authenticated;

create or replace function public.create_administration_alert(
  target_administration_id bigint,
  notification_title text,
  notification_body text,
  notification_payload jsonb,
  alert_key text,
  excluded_user_id uuid default null
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, type, title, body, payload)
  select
    member.user_id,
    'institutional_alert',
    notification_title,
    notification_body,
    coalesce(notification_payload, '{}'::jsonb) || jsonb_build_object(
      'administration_id', target_administration_id,
      'alert_key', alert_key
    )
  from public.administration_users member
  where member.administration_id = target_administration_id
    and member.is_active = true
    and member.user_id is distinct from excluded_user_id
    and not exists (
      select 1
      from public.notifications notification
      where notification.user_id = member.user_id
        and notification.type = 'institutional_alert'
        and notification.payload ->> 'alert_key' = alert_key
    );
$$;

revoke all on function public.create_administration_alert(bigint, text, text, jsonb, text, uuid)
  from public, anon, authenticated;

create or replace function public.notify_administration_occurrence_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_administration_id bigint;
  target_title text;
  alert_title text;
begin
  if not (
    new.actor_kind = 'agency'
    or new.event_type in ('validation_rejected', 'occurrence_reopened')
  ) then
    return new;
  end if;

  select occurrence.administration_id, occurrence.title
  into target_administration_id, target_title
  from public.occurrences occurrence
  where occurrence.id = new.occurrence_id;

  alert_title := case
    when new.event_type = 'validation_rejected'
      then 'Validação comunitária rejeitada'
    when new.event_type = 'occurrence_reopened'
      then 'Ocorrência reaberta'
    else 'Novo retorno do órgão responsável'
  end;

  perform public.create_administration_alert(
    target_administration_id,
    alert_title,
    target_title,
    jsonb_build_object(
      'occurrence_id', new.occurrence_id,
      'event_type', new.event_type,
      'actor_kind', new.actor_kind,
      'agency_id', new.agency_id
    ),
    'event:' || new.id,
    new.actor_id
  );
  return new;
end;
$$;

drop trigger if exists notify_administration_on_occurrence_event
  on public.occurrence_events;
create trigger notify_administration_on_occurrence_event
after insert on public.occurrence_events
for each row execute function public.notify_administration_occurrence_event();

create or replace function public.notify_administration_high_mobilization()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_occurrence public.occurrences%rowtype;
  support_count integer;
begin
  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = new.occurrence_id;

  select count(*)::integer into support_count
  from public.occurrence_supports support
  where support.occurrence_id = new.occurrence_id;

  if support_count >= 5 then
    perform public.create_administration_alert(
      target_occurrence.administration_id,
      'Demanda com alta mobilização',
      target_occurrence.title || ' alcançou ' || support_count || ' apoios.',
      jsonb_build_object(
        'occurrence_id', target_occurrence.id,
        'event_type', 'high_mobilization'
      ),
      'high_mobilization:' || target_occurrence.id,
      new.user_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_administration_on_high_mobilization
  on public.occurrence_supports;
create trigger notify_administration_on_high_mobilization
after insert on public.occurrence_supports
for each row execute function public.notify_administration_high_mobilization();

create or replace function public.notify_overdue_administration_forecasts()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  overdue record;
begin
  for overdue in
    select distinct on (action.occurrence_id)
      action.occurrence_id,
      action.administration_id,
      action.forecast_at,
      occurrence.title
    from public.institutional_actions action
    join public.occurrences occurrence on occurrence.id = action.occurrence_id
    where action.action_type = 'forecast'
      and action.forecast_at < now()
      and occurrence.status in (
        'open', 'in_analysis', 'in_progress', 'awaiting_validation', 'reopened'
      )
    order by action.occurrence_id, action.created_at desc
  loop
    perform public.create_administration_alert(
      overdue.administration_id,
      'Previsão de atendimento vencida',
      overdue.title,
      jsonb_build_object(
        'occurrence_id', overdue.occurrence_id,
        'event_type', 'forecast_overdue',
        'forecast_at', overdue.forecast_at
      ),
      'forecast_overdue:' || overdue.occurrence_id || ':' || overdue.forecast_at,
      null
    );
  end loop;
end;
$$;

revoke all on function public.notify_overdue_administration_forecasts()
  from public, anon, authenticated;
grant execute on function public.notify_overdue_administration_forecasts()
  to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and not exists (
       select 1 from cron.job where jobname = 'urbapp-alertas-previsoes-vencidas'
     ) then
    perform cron.schedule(
      'urbapp-alertas-previsoes-vencidas',
      '15 * * * *',
      'select public.notify_overdue_administration_forecasts()'
    );
  end if;
end;
$$;
