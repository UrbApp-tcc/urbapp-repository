-- A linha do tempo pública identifica o papel, não a conta interna do ator.
-- Os UUIDs continuam disponíveis para funções de auditoria executadas no backend.

revoke select on table public.occurrence_events from anon, authenticated;
grant select (
  id,
  occurrence_id,
  actor_kind,
  event_type,
  description,
  administration_id,
  agency_id,
  metadata,
  created_at
) on table public.occurrence_events to anon, authenticated;

revoke select on table public.institutional_actions from anon, authenticated;
grant select (
  id,
  occurrence_id,
  administration_id,
  agency_id,
  actor_kind,
  action_type,
  description,
  evidence_storage_path,
  forecast_at,
  target_agency_id,
  created_at
) on table public.institutional_actions to anon, authenticated;

notify pgrst, 'reload schema';
