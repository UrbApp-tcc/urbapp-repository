-- Evidência opcional da possível resolução informada por cidadãos.

alter table public.resolution_cycles
  add column if not exists evidence_storage_path text;

create or replace function public.open_resolution_cycle_with_evidence(
  target_occurrence_id bigint,
  resolution_description text,
  initiator_kind text default 'citizen',
  evidence_storage_path text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  created_cycle_id bigint;
  clean_evidence_path text := nullif(trim(coalesce(evidence_storage_path, '')), '');
begin
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
    set metadata = metadata || jsonb_build_object(
      'evidence_storage_path', clean_evidence_path
    )
    where occurrence_id = target_occurrence_id
      and event_type = 'validation_opened'
      and metadata ->> 'cycle_id' = created_cycle_id::text;
  end if;

  return created_cycle_id;
end;
$$;

revoke all on function public.open_resolution_cycle_with_evidence(bigint, text, text, text)
  from public, anon, authenticated;
grant execute on function public.open_resolution_cycle_with_evidence(bigint, text, text, text)
  to authenticated;

notify pgrst, 'reload schema';
