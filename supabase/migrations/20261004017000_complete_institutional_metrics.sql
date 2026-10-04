-- Indicadores institucionais objetivos e historicamente separados por papel.

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
  occurrence_metrics.inherited_occurrences,
  resolution_metrics.resolved_during_period,
  action_metrics.prioritized_occurrences,
  action_metrics.officially_answered_occurrences,
  administration.mayor_name,
  administration.is_placeholder,
  administration.is_verified,
  occurrence_metrics.active_occurrences,
  inherited_metrics.left_pending_occurrences,
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
    count(*) filter (
      where occurrence.created_administration_id = administration.id
    ) as registered_during_period,
    count(*) filter (
      where occurrence.administration_id = administration.id
        and occurrence.created_administration_id <> administration.id
    ) as inherited_occurrences,
    count(*) filter (
      where occurrence.administration_id = administration.id
        and occurrence.status in (
          'open', 'in_analysis', 'in_progress', 'awaiting_validation', 'reopened'
        )
    ) as active_occurrences
  from public.occurrences occurrence
  where occurrence.invalidated_at is null
    and (
      occurrence.created_administration_id = administration.id
      or occurrence.administration_id = administration.id
    )
) occurrence_metrics
cross join lateral (
  select count(distinct event.occurrence_id) as resolved_during_period
  from public.occurrence_events event
  join public.occurrences occurrence on occurrence.id = event.occurrence_id
  where event.administration_id = administration.id
    and event.event_type = 'resolution_confirmed'
    and occurrence.invalidated_at is null
) resolution_metrics
cross join lateral (
  select count(distinct event.occurrence_id) as left_pending_occurrences
  from public.occurrence_events event
  join public.occurrences occurrence on occurrence.id = event.occurrence_id
  where event.event_type = 'administration_changed'
    and event.metadata ->> 'previous_administration_id' = administration.id::text
    and occurrence.invalidated_at is null
) inherited_metrics
cross join lateral (
  select
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'priority'
    ) as prioritized_occurrences,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'official_position'
    ) as officially_answered_occurrences,
    count(distinct action.occurrence_id) as manifested_occurrences,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'forwarding'
    ) as forwarded_occurrences,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'forecast'
    ) as forecasted_occurrences,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
    ) as conclusions_informed,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
        and exists (
          select 1
          from public.occurrence_events event
          where event.occurrence_id = action.occurrence_id
            and event.event_type = 'resolution_confirmed'
            and event.created_at > action.created_at
        )
    ) as confirmed_conclusions,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
        and exists (
          select 1
          from public.occurrence_events event
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
        and first_conclusion.created_at is not null
    ) as average_seconds_to_conclusion
  from public.institutional_actions action
  join public.occurrences occurrence on occurrence.id = action.occurrence_id
  where action.administration_id = administration.id
    and action.actor_kind = 'administration'
    and occurrence.invalidated_at is null
) action_metrics;

create or replace view public.agency_occurrence_metrics
with (security_invoker = true)
as
select
  agency.id as agency_id,
  agency.city_id,
  agency.name,
  agency.profile_status,
  occurrence_metrics.assigned_occurrences,
  occurrence_metrics.resolved_occurrences,
  action_metrics.official_actions,
  action_metrics.first_recorded_action_at,
  occurrence_metrics.open_occurrences,
  occurrence_metrics.in_progress_occurrences,
  occurrence_metrics.awaiting_validation_occurrences,
  action_metrics.officially_answered_occurrences,
  action_metrics.official_response_percentage,
  action_metrics.conclusions_informed,
  action_metrics.confirmed_conclusions,
  action_metrics.rejected_conclusions,
  responsibility_metrics.average_responsibility_seconds,
  responsibility_metrics.median_responsibility_seconds,
  action_metrics.average_seconds_to_first_response,
  occurrence_metrics.categories_count,
  occurrence_metrics.neighborhoods_count
from public.public_agencies agency
cross join lateral (
  select
    count(distinct occurrence.id) as assigned_occurrences,
    count(distinct occurrence.id) filter (
      where occurrence.status = 'completed'
    ) as resolved_occurrences,
    count(distinct occurrence.id) filter (
      where occurrence.status in ('open', 'reopened')
    ) as open_occurrences,
    count(distinct occurrence.id) filter (
      where occurrence.status in ('in_analysis', 'in_progress')
    ) as in_progress_occurrences,
    count(distinct occurrence.id) filter (
      where occurrence.status = 'awaiting_validation'
    ) as awaiting_validation_occurrences,
    count(distinct occurrence.category_id) as categories_count,
    count(distinct nullif(trim(occurrence.neighborhood), '')) as neighborhoods_count
  from public.occurrence_agency_assignments assignment
  join public.occurrences occurrence on occurrence.id = assignment.occurrence_id
  where assignment.agency_id = agency.id
    and occurrence.invalidated_at is null
) occurrence_metrics
cross join lateral (
  select
    avg(
      extract(
        epoch from (
          coalesce(
            assignment.ends_at,
            case when occurrence.status = 'completed' then occurrence.resolved_at end,
            now()
          ) - assignment.starts_at
        )
      )
    ) as average_responsibility_seconds,
    percentile_cont(0.5) within group (
      order by extract(
        epoch from (
          coalesce(
            assignment.ends_at,
            case when occurrence.status = 'completed' then occurrence.resolved_at end,
            now()
          ) - assignment.starts_at
        )
      )
    ) as median_responsibility_seconds
  from public.occurrence_agency_assignments assignment
  join public.occurrences occurrence on occurrence.id = assignment.occurrence_id
  where assignment.agency_id = agency.id
    and occurrence.invalidated_at is null
) responsibility_metrics
cross join lateral (
  select
    count(action.id) as official_actions,
    min(action.created_at) as first_recorded_action_at,
    count(distinct action.occurrence_id) as officially_answered_occurrences,
    round(
      case
        when occurrence_metrics.assigned_occurrences = 0 then 0
        else count(distinct action.occurrence_id)::numeric
          / occurrence_metrics.assigned_occurrences::numeric * 100
      end,
      2
    ) as official_response_percentage,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
    ) as conclusions_informed,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
        and exists (
          select 1
          from public.occurrence_events event
          where event.occurrence_id = action.occurrence_id
            and event.event_type = 'resolution_confirmed'
            and event.created_at > action.created_at
        )
    ) as confirmed_conclusions,
    count(distinct action.occurrence_id) filter (
      where action.action_type = 'conclusion'
        and exists (
          select 1
          from public.occurrence_events event
          where event.occurrence_id = action.occurrence_id
            and event.event_type = 'validation_rejected'
            and event.created_at > action.created_at
        )
    ) as rejected_conclusions,
    avg(
      extract(epoch from action.created_at - assignment.starts_at)
    ) filter (
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
) action_metrics;

create or replace view public.councilor_activity_metrics
with (security_invoker = true)
as
select
  councilor.id as councilor_profile_id,
  councilor.profile_id,
  councilor.city_id,
  councilor.public_name,
  count(distinct following.id) as followed_demands,
  count(distinct action.id) as registered_actions,
  count(distinct following.id) filter (
    where exists (
      select 1
      from public.councilor_actions concrete_action
      join public.occurrence_events resolution_event
        on resolution_event.occurrence_id = following.occurrence_id
       and resolution_event.event_type = 'resolution_confirmed'
       and resolution_event.created_at > concrete_action.created_at
      where concrete_action.following_id = following.id
    )
  ) as followed_demands_that_reached_resolution,
  councilor.party,
  councilor.profile_status,
  count(distinct action.id) filter (
    where action.action_type in ('forwarding', 'request', 'agency_contact')
  ) as forwarding_actions,
  count(distinct action.id) filter (
    where action.action_type = 'charge'
  ) as charge_actions,
  count(distinct action.id) filter (
    where action.action_type = 'official_letter'
  ) as official_letters,
  count(distinct following.id) filter (
    where following.status = 'awaiting_response'
  ) as awaiting_response_demands,
  count(distinct following.id) filter (
    where occurrence.status in (
      'open', 'in_analysis', 'in_progress', 'awaiting_validation', 'reopened'
    )
  ) as followed_open_demands,
  count(distinct following.id) filter (
    where following.status = 'ended'
      and not exists (
        select 1
        from public.occurrence_events resolution_event
        where resolution_event.occurrence_id = following.occurrence_id
          and resolution_event.event_type = 'resolution_confirmed'
          and resolution_event.created_at >= following.started_at
      )
  ) as ended_without_resolution,
  avg(
    extract(epoch from (coalesce(following.ended_at, now()) - following.started_at))
  ) as average_followup_seconds
from public.councilor_profiles councilor
left join public.councilor_followings following
  on following.councilor_profile_id = councilor.id
left join public.occurrences occurrence
  on occurrence.id = following.occurrence_id
 and occurrence.invalidated_at is null
left join public.councilor_actions action
  on action.following_id = following.id
group by councilor.id;

grant select on public.administration_occurrence_metrics to anon, authenticated;
grant select on public.agency_occurrence_metrics to anon, authenticated;
grant select on public.councilor_activity_metrics to anon, authenticated;

notify pgrst, 'reload schema';
