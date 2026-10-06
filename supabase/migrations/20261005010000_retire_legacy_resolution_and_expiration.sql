-- UrbApp: aposenta o fluxo legado de validação por relato e a expiração automática.
--
-- Divergências corrigidas (spec §30, §31, §44.8):
-- * `run_daily_expiration` (cron diário) marcava relatos abertos sem movimento como
--   `expired`. `expired` não é estado oficial e ausência de interação não altera o
--   estado real do problema.
-- * `request_post_resolution` / `vote_post_resolution` implementavam uma segunda
--   validação comunitária por relato (raio em metros, sem ciclo, sem cooldown),
--   capaz de marcar um relato como `completed` sem passar pela ocorrência.
-- O histórico (`post_resolution_requests`, `post_resolution_votes`) é preservado,
-- apenas sem acesso de escrita/leitura pelos clientes.

do $$
begin
  if exists (select 1 from cron.job where jobname = 'urbapp-expiracao-diaria') then
    perform cron.unschedule('urbapp-expiracao-diaria');
  end if;
end;
$$;

drop function if exists public.run_daily_expiration();
drop function if exists public.request_post_resolution(bigint, text);
drop function if exists public.vote_post_resolution(bigint, boolean, double precision, double precision);
drop function if exists public.get_post_resolution_status(bigint);
drop function if exists public.get_awaiting_validation_post_ids(bigint[]);

revoke all on table public.post_resolution_requests from anon, authenticated;
revoke all on table public.post_resolution_votes from anon, authenticated;
alter table public.post_resolution_requests enable row level security;
alter table public.post_resolution_votes enable row level security;

drop policy if exists "Admins read legacy resolution requests" on public.post_resolution_requests;
create policy "Admins read legacy resolution requests"
on public.post_resolution_requests for select to authenticated
using (public.is_platform_admin(auth.uid()));

drop policy if exists "Admins read legacy resolution votes" on public.post_resolution_votes;
create policy "Admins read legacy resolution votes"
on public.post_resolution_votes for select to authenticated
using (public.is_platform_admin(auth.uid()));

grant select on public.post_resolution_requests to authenticated;
grant select on public.post_resolution_votes to authenticated;

-- Ocorrências marcadas como `expired` voltam ao último estado operacional conhecido.
with restored as (
  update public.occurrences occurrence
  set status = coalesce(
        nullif(occurrence.previous_operational_status, 'expired'::public.report_status),
        'open'::public.report_status
      ),
      previous_operational_status = null
  where occurrence.status = 'expired'
  returning occurrence.id, occurrence.status, occurrence.administration_id, occurrence.agency_id
)
insert into public.occurrence_events (
  occurrence_id,
  actor_kind,
  event_type,
  description,
  administration_id,
  agency_id,
  metadata
)
select
  restored.id,
  'system',
  'status_restored',
  'Estado legado "expirado" removido; a ocorrência voltou ao estado operacional.',
  restored.administration_id,
  restored.agency_id,
  jsonb_build_object('restored_status', restored.status)
from restored;

-- Relatos acompanham o estado global da ocorrência à qual pertencem.
select set_config('urbapp.system_status_change', 'on', true);

update public.posts post
set status = occurrence.status,
    resolved_at = occurrence.resolved_at
from public.occurrences occurrence
where occurrence.id = post.occurrence_id
  and post.status is distinct from occurrence.status;

update public.posts
set status = 'open'
where status = 'expired';

select set_config('urbapp.system_status_change', 'off', true);

alter table public.occurrences
  drop constraint if exists occurrences_official_status_check;
alter table public.occurrences
  add constraint occurrences_official_status_check
  check (status <> 'expired' and (previous_operational_status is null or previous_operational_status <> 'expired'));

alter table public.posts
  drop constraint if exists posts_official_status_check;
alter table public.posts
  add constraint posts_official_status_check
  check (status <> 'expired');

-- O rótulo público segue a nomenclatura oficial da especificação.
create or replace function public.status_label(p_status public.report_status)
returns text
language sql
immutable
as $$
  select case p_status
    when 'open' then 'Aberto'
    when 'in_analysis' then 'Em análise'
    when 'in_progress' then 'Em andamento'
    when 'awaiting_validation' then 'Aguardando validação'
    when 'completed' then 'Resolvido'
    when 'reopened' then 'Reaberto'
    when 'closed' then 'Encerrado'
    else 'Aberto'
  end;
$$;

comment on type public.report_status is
  'Estados globais oficiais (spec §31): open=ABERTO, in_analysis=EM_ANALISE, '
  'in_progress=EM_ANDAMENTO, awaiting_validation=AGUARDANDO_VALIDACAO, '
  'completed=RESOLVIDO, reopened=REABERTO, closed=ENCERRADO. '
  'O valor legado expired é bloqueado por constraint e não deve ser usado.';

notify pgrst, 'reload schema';
