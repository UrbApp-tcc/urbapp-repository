-- Vereadores que acompanham institucionalmente uma demanda recebem os
-- eventos da ocorrência sem precisar segui-la também como cidadãos.
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
      union
      select councilor.profile_id
      from public.councilor_followings following
      join public.councilor_profiles councilor
        on councilor.id = following.councilor_profile_id
      where following.occurrence_id = new.occurrence_id
        and following.status not in ('ended', 'resolved')
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

