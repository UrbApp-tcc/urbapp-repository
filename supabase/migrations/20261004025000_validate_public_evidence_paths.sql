-- Impede que clientes associem à linha do tempo um caminho arbitrário que
-- possa conter identificadores pessoais ou mídia de outra ocorrência.

create or replace function public.validate_occurrence_event_evidence_path()
returns trigger
language plpgsql
set search_path = public
as $$
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
    when new.event_type like 'institutional_%'
      or new.event_type like 'councilor_%'
      then 'occurrences/' || new.occurrence_id::text || '/institutional/'
    else null
  end;

  if expected_prefix is not null
     and evidence_path not like expected_prefix || '%' then
    raise exception 'Caminho de evidencia invalido para esta ocorrencia.';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_occurrence_event_evidence_path
  on public.occurrence_events;
create trigger validate_occurrence_event_evidence_path
before insert or update of metadata, occurrence_id, event_type
on public.occurrence_events
for each row execute function public.validate_occurrence_event_evidence_path();
