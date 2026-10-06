-- Perfil público da cidade e ranking de cidades por indicadores objetivos
-- (spec §22, §33, §44.6).
--
-- * A cidade é permanente e tem histórico contínuo; a gestão é um recorte
--   temporal (métricas próprias em `administration_occurrence_metrics`).
-- * Universo elegível: ocorrências únicas de competência municipal, sem
--   duplicatas absorvidas e sem invalidação (moderação/fraude). Encerramentos
--   administrativos por outro motivo continuam no universo, como não resolvidos.
-- * Resolvida = estado atual RESOLVIDO (`completed`). O tempo de resolução usa a
--   última transição real para RESOLVIDO registrada no histórico.
-- * "Este mês" é uma coorte pela data de criação, no fuso horário da cidade.
-- * Amostras mínimas ficam em `city_ranking_settings`.
-- O ranking de cidades não usa pontos de cidadãos nem score composto.

-- ---------------------------------------------------------------------------
-- 1. Fuso horário da cidade (IANA)
-- ---------------------------------------------------------------------------

-- Fuso oficial predominante de cada UF; Fernando de Noronha e as microrregiões
-- com fuso próprio (oeste do AM e do PA) precisam de ajuste explícito por cidade.
create or replace function public.default_timezone_for_state(target_state text)
returns text
language sql
immutable
as $$
  select case lower(coalesce(target_state, ''))
    when 'ac' then 'America/Rio_Branco'
    when 'am' then 'America/Manaus'
    when 'rr' then 'America/Boa_Vista'
    when 'ro' then 'America/Porto_Velho'
    when 'mt' then 'America/Cuiaba'
    when 'ms' then 'America/Campo_Grande'
    when 'pa' then 'America/Belem'
    when 'ap' then 'America/Belem'
    when 'to' then 'America/Araguaina'
    when 'ma' then 'America/Fortaleza'
    when 'pi' then 'America/Fortaleza'
    when 'ce' then 'America/Fortaleza'
    when 'rn' then 'America/Fortaleza'
    when 'pb' then 'America/Fortaleza'
    when 'pe' then 'America/Recife'
    when 'al' then 'America/Maceio'
    when 'se' then 'America/Maceio'
    when 'ba' then 'America/Bahia'
    else 'America/Sao_Paulo'
  end;
$$;

alter table public.cities add column if not exists timezone text;

update public.cities
set timezone = public.default_timezone_for_state(state::text)
where timezone is null;

alter table public.cities alter column timezone set not null;

create or replace function public.prepare_city_timezone()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.timezone is null or btrim(new.timezone) = '' then
    new.timezone := public.default_timezone_for_state(new.state::text);
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names zone where zone.name = new.timezone) then
    raise exception 'Fuso horário inválido para a cidade: %.', new.timezone;
  end if;
  return new;
end;
$$;

drop trigger if exists prepare_city_timezone on public.cities;
create trigger prepare_city_timezone
before insert or update of timezone, state on public.cities
for each row execute function public.prepare_city_timezone();

-- Primeiro instante do mês corrente no fuso da cidade.
create or replace function public.city_month_start(target_city_id bigint)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select date_trunc('month', now() at time zone city.timezone) at time zone city.timezone
  from public.cities city
  where city.id = target_city_id;
$$;

grant execute on function public.city_month_start(bigint) to authenticated;
revoke all on function public.city_month_start(bigint) from public, anon;

-- ---------------------------------------------------------------------------
-- 2. Universo elegível e momento da resolução
-- ---------------------------------------------------------------------------

-- Última transição real para RESOLVIDO; `resolved_at` só cobre ocorrências
-- anteriores ao histórico de transições.
create or replace function public.occurrence_last_resolution_at(target_occurrence_id bigint)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select max(event.created_at)
      from public.occurrence_events event
      where event.occurrence_id = target_occurrence_id
        and event.event_type = 'status_changed'
        and event.metadata ->> 'to' = 'completed'
    ),
    (select occurrence.resolved_at from public.occurrences occurrence where occurrence.id = target_occurrence_id)
  );
$$;

-- Usada pelas views públicas da cidade: o momento da resolução é informação
-- pública da linha do tempo da ocorrência.
revoke all on function public.occurrence_last_resolution_at(bigint) from public;
grant execute on function public.occurrence_last_resolution_at(bigint) to anon, authenticated;

create index if not exists occurrence_events_status_transition_idx
  on public.occurrence_events (occurrence_id, created_at)
  where event_type = 'status_changed';

create index if not exists occurrences_city_created_idx
  on public.occurrences (city_id, created_at);

-- Ocorrências únicas que representam demanda municipal válida, com o tempo de
-- resolução das que estão RESOLVIDAS hoje. Uso interno das métricas e RPCs.
create or replace view public.city_eligible_occurrences
with (security_barrier = true)
as
select occurrence.id,
       occurrence.city_id,
       occurrence.status,
       occurrence.created_at,
       occurrence.category_id,
       occurrence.neighborhood,
       case when occurrence.status = 'completed'
         then extract(epoch from public.occurrence_last_resolution_at(occurrence.id) - occurrence.created_at)
       end as resolution_seconds
from public.occurrences occurrence
where occurrence.invalidated_at is null
  and occurrence.merged_into_occurrence_id is null
  and occurrence.jurisdiction_type = 'municipal';

revoke all on public.city_eligible_occurrences from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Métricas contínuas da cidade (perfil público)
-- ---------------------------------------------------------------------------

drop view if exists public.city_occurrence_metrics;

create view public.city_occurrence_metrics
with (security_barrier = true)
as
select city.id as city_id,
       city.name as city_name,
       city.state::text as state,
       city.timezone,
       count(eligible.id) as total_occurrences,
       count(eligible.id) filter (where eligible.status = 'completed') as resolved_occurrences,
       count(eligible.id) filter (where eligible.status = 'open') as open_occurrences,
       count(eligible.id) filter (where eligible.status in ('in_analysis', 'in_progress', 'reopened')) as active_occurrences,
       count(eligible.id) filter (where eligible.status = 'awaiting_validation') as awaiting_validation_occurrences,
       round(
         100.0 * count(eligible.id) filter (where eligible.status = 'completed') / nullif(count(eligible.id), 0),
         2
       ) as resolution_rate,
       avg(eligible.resolution_seconds) as average_resolution_seconds,
       percentile_cont(0.5) within group (order by eligible.resolution_seconds)
         filter (where eligible.resolution_seconds is not null) as median_resolution_seconds,
       (
         select count(*) from public.occurrences outside
         where outside.city_id = city.id
           and outside.invalidated_at is null
           and outside.merged_into_occurrence_id is null
           and outside.jurisdiction_type <> 'municipal'
       ) as outside_municipal_occurrences,
       count(eligible.id) filter (where eligible.status = 'in_analysis') as in_analysis_occurrences,
       count(eligible.id) filter (where eligible.status = 'in_progress') as in_progress_occurrences,
       count(eligible.id) filter (where eligible.status = 'reopened') as reopened_occurrences,
       count(eligible.id) filter (where eligible.status = 'closed') as closed_occurrences
from public.cities city
left join public.city_eligible_occurrences eligible on eligible.city_id = city.id
group by city.id;

grant select on public.city_occurrence_metrics to anon, authenticated;

-- Evolução mensal no fuso da cidade (mês de criação; resolvidas = estado atual).
drop view if exists public.city_monthly_metrics;

create view public.city_monthly_metrics
with (security_barrier = true)
as
select eligible.city_id,
       date_trunc('month', eligible.created_at at time zone city.timezone)::date as month,
       count(*) as registered_count,
       count(*) filter (where eligible.status = 'completed') as resolved_count
from public.city_eligible_occurrences eligible
join public.cities city on city.id = eligible.city_id
group by eligible.city_id, date_trunc('month', eligible.created_at at time zone city.timezone)::date;

grant select on public.city_monthly_metrics to anon, authenticated;

-- Histórico de gestões da cidade (recorte temporal, sem misturar com a cidade).
create or replace function public.get_city_administrations(target_city_id bigint)
returns table (
  administration_id bigint,
  name text,
  mayor_name text,
  starts_on date,
  ends_on date,
  is_current boolean,
  is_verified boolean,
  is_placeholder boolean,
  registered_during_period bigint,
  inherited_occurrences bigint,
  resolved_during_period bigint,
  left_pending_occurrences bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select administration.id,
         administration.name,
         administration.mayor_name,
         administration.starts_on,
         administration.ends_on,
         administration.id = public.current_administration_id(target_city_id),
         administration.is_verified,
         administration.is_placeholder,
         coalesce(metrics.registered_during_period, 0),
         coalesce(metrics.inherited_occurrences, 0),
         coalesce(metrics.resolved_during_period, 0),
         coalesce(metrics.left_pending_occurrences, 0)
  from public.municipal_administrations administration
  left join public.administration_occurrence_metrics metrics on metrics.administration_id = administration.id
  where administration.city_id = target_city_id
  order by administration.starts_on desc;
$$;

revoke all on function public.get_city_administrations(bigint) from public, anon;
grant execute on function public.get_city_administrations(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Ranking de cidades: taxa de resolução e mediana do tempo de resolução
-- ---------------------------------------------------------------------------

create table if not exists public.city_ranking_settings (
  id boolean primary key default true check (id),
  min_occurrences_for_rate integer not null default 10 check (min_occurrences_for_rate > 0),
  min_resolved_for_time integer not null default 5 check (min_resolved_for_time > 0),
  updated_at timestamptz not null default now()
);

insert into public.city_ranking_settings (id) values (true) on conflict do nothing;

alter table public.city_ranking_settings enable row level security;

drop policy if exists "City ranking settings are public" on public.city_ranking_settings;
create policy "City ranking settings are public"
on public.city_ranking_settings for select to authenticated
using (true);

revoke all on public.city_ranking_settings from anon, authenticated;
grant select on public.city_ranking_settings to authenticated;
grant all on public.city_ranking_settings to service_role;

-- indicator: 'resolution_rate' | 'resolution_time'; period: 'month' | 'all'.
-- Cidades qualificadas recebem posição; as que têm dados abaixo da amostra
-- mínima aparecem depois, sem posição. Cidades sem ocorrências no período não
-- aparecem.
create or replace function public.get_city_resolution_ranking(
  indicator text default 'resolution_rate',
  period text default 'all',
  page_size integer default 50,
  page_offset integer default 0
)
returns table (
  rank_position bigint,
  city_id bigint,
  city_name text,
  state text,
  eligible_occurrences bigint,
  resolved_occurrences bigint,
  resolution_rate numeric,
  median_resolution_seconds double precision,
  qualified boolean,
  minimum_required integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  settings public.city_ranking_settings%rowtype;
  by_time boolean := coalesce(indicator, 'resolution_rate') = 'resolution_time';
begin
  if coalesce(indicator, 'resolution_rate') not in ('resolution_rate', 'resolution_time') then
    raise exception 'Indicador de ranking inválido.';
  end if;
  if coalesce(period, 'all') not in ('month', 'all') then
    raise exception 'Período de ranking inválido.';
  end if;

  select * into settings from public.city_ranking_settings where id;

  return query
  with cohort as (
    select eligible.*
    from public.city_eligible_occurrences eligible
    join public.cities city on city.id = eligible.city_id
    where coalesce(period, 'all') = 'all'
       or eligible.created_at >= date_trunc('month', now() at time zone city.timezone) at time zone city.timezone
  ),
  per_city as (
    select city.id as city_id,
           city.name as city_name,
           city.state::text as state,
           count(cohort.id) as eligible_count,
           count(cohort.id) filter (where cohort.status = 'completed') as resolved_count,
           percentile_cont(0.5) within group (order by cohort.resolution_seconds)
             filter (where cohort.resolution_seconds is not null) as median_seconds
    from public.cities city
    join cohort on cohort.city_id = city.id
    group by city.id
  ),
  scored as (
    select per_city.*,
           round(100.0 * per_city.resolved_count / nullif(per_city.eligible_count, 0), 1) as rate,
           case when by_time then per_city.resolved_count >= settings.min_resolved_for_time
                else per_city.eligible_count >= settings.min_occurrences_for_rate end as is_qualified
    from per_city
  ),
  ordered as (
    select scored.*,
           row_number() over (
             order by
               scored.is_qualified desc,
               case when not by_time then scored.rate end desc nulls last,
               case when not by_time then scored.eligible_count end desc,
               case when by_time then scored.median_seconds end asc nulls last,
               case when by_time then scored.resolved_count end desc,
               scored.city_name asc,
               scored.city_id asc
           ) as overall_order
    from scored
  )
  select
    case when ordered.is_qualified then ordered.overall_order end,
    ordered.city_id,
    ordered.city_name,
    ordered.state,
    ordered.eligible_count,
    ordered.resolved_count,
    coalesce(ordered.rate, 0),
    ordered.median_seconds,
    ordered.is_qualified,
    case when by_time then settings.min_resolved_for_time else settings.min_occurrences_for_rate end
  from ordered
  order by ordered.overall_order
  limit greatest(1, least(coalesce(page_size, 50), 100))
  offset greatest(0, coalesce(page_offset, 0));
end;
$$;

revoke all on function public.get_city_resolution_ranking(text, text, integer, integer) from public, anon;
grant execute on function public.get_city_resolution_ranking(text, text, integer, integer) to authenticated;
