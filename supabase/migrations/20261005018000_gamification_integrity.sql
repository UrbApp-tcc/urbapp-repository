-- Integridade da gamificação (spec §21, §39, §40).
--
-- 1. Cada transação de pontos/XP registra a cidade da ação que a gerou
--    (`xp_transactions.city_id`). O ranking municipal usa essa atribuição, e não
--    a cidade atual do perfil: trocar de cidade não move pontos históricos.
-- 2. XP de relato passa a valer uma vez por cidadão e ocorrência
--    (`report_contribution`, `report_resolved`), como os pontos já valiam.
--    Relatos adicionais na mesma ocorrência não repetem a recompensa.
-- 3. Ranking geral e mensal somam as transações atribuídas à cidade; o mês é
--    contado no horário de Brasília.
-- 4. Remove os triggers e funções legados da antiga camada de apoios por relato
--    (`post_supports`) e funções órfãs, sem dependências.
--
-- Apoios e comentários recebidos continuam indo para quem iniciou a ocorrência:
-- o modelo liga apoios e comentários à ocorrência, não a um relato específico.

-- ---------------------------------------------------------------------------
-- 1. Cidade da transação
-- ---------------------------------------------------------------------------

alter table public.xp_transactions
  add column if not exists city_id bigint references public.cities(id) on delete set null;

create index if not exists xp_transactions_city_created_idx
  on public.xp_transactions (city_id, created_at);

-- Cidade de origem de uma recompensa, derivada de dados imutáveis da ação:
-- ocorrência, relato, comentário ou voto. Transações antigas por relato
-- (modelo anterior) são resolvidas pelo relato quando o usuário não tem
-- vínculo com uma ocorrência de mesmo identificador.
create or replace function public.xp_transaction_city(target_user_id uuid, target_source_type text, target_source_id bigint)
returns bigint
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  kind text := split_part(coalesce(target_source_type, ''), ':', 1);
  resolved_city bigint;
begin
  if target_source_id is null then
    return null;
  end if;

  if kind = 'moderation_reversal' then
    select tx.city_id into resolved_city from public.xp_transactions tx where tx.id = target_source_id;
    return resolved_city;
  end if;

  if kind = 'validation_given' then
    select occurrence.city_id into resolved_city
    from public.resolution_votes vote
    join public.resolution_cycles cycle on cycle.id = vote.cycle_id
    join public.occurrences occurrence on occurrence.id = cycle.occurrence_id
    where vote.id = target_source_id;
    return resolved_city;
  end if;

  -- Comentário (XP de comentar e o antigo `comment_received` sem sufixo).
  if kind = 'comment' or target_source_type = 'comment_received' then
    select coalesce(occurrence.city_id, post.city_id) into resolved_city
    from public.comments comment
    left join public.occurrences occurrence on occurrence.id = comment.occurrence_id
    left join public.posts post on post.id = comment.post_id
    where comment.id = target_source_id;
    return resolved_city;
  end if;

  -- Tipos do modelo anterior, sempre ligados a um relato.
  if kind in ('post_created', 'post_validated', 'post_deleted') then
    select post.city_id into resolved_city from public.posts post where post.id = target_source_id;
    return resolved_city;
  end if;

  -- Tipos ligados à ocorrência: usa a ocorrência quando o usuário tem vínculo
  -- com ela (relato ou apoio); senão, o relato antigo de mesmo id.
  select occurrence.city_id into resolved_city
  from public.occurrences occurrence
  where occurrence.id = target_source_id
    and (
      exists (select 1 from public.posts post where post.occurrence_id = occurrence.id and post.user_id = target_user_id)
      or exists (
        select 1 from public.occurrence_supports support
        where support.occurrence_id = occurrence.id and support.user_id = target_user_id
      )
    );

  if resolved_city is null then
    select post.city_id into resolved_city from public.posts post where post.id = target_source_id;
  end if;

  return resolved_city;
end;
$$;

revoke all on function public.xp_transaction_city(uuid, text, bigint) from public, anon, authenticated;

create or replace function public.assign_xp_transaction_city()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.city_id is null then
    new.city_id := public.xp_transaction_city(new.user_id, new.source_type, new.source_id);
  end if;
  return new;
end;
$$;

revoke all on function public.assign_xp_transaction_city() from public, anon, authenticated;

drop trigger if exists assign_xp_transaction_city on public.xp_transactions;
create trigger assign_xp_transaction_city
before insert on public.xp_transactions
for each row execute function public.assign_xp_transaction_city();

-- Atribuição histórica: recompensas primeiro, estornos depois (herdam a cidade).
update public.xp_transactions tx
set city_id = public.xp_transaction_city(tx.user_id, tx.source_type, tx.source_id)
where tx.city_id is null
  and tx.source_type <> 'moderation_reversal';

update public.xp_transactions tx
set city_id = original.city_id
from public.xp_transactions original
where tx.city_id is null
  and tx.source_type = 'moderation_reversal'
  and original.id = tx.source_id;

-- ---------------------------------------------------------------------------
-- 2. XP de relato por ocorrência (antifarm)
-- ---------------------------------------------------------------------------

create or replace function public.xp_value(p_action text)
returns integer
language sql
immutable
as $$
    select case p_action
        when 'report_contribution' then 20  -- primeiro relato do cidadão na ocorrência
        when 'report_resolved'     then 50  -- ocorrência com relato do cidadão resolvida
        when 'post_created'        then 20  -- histórico (modelo anterior, por relato)
        when 'post_validated'      then 50  -- histórico (modelo anterior, por relato)
        when 'support_given'       then 5
        when 'comment'             then 5   -- limite diário em xp_daily_comment_cap()
        when 'validation_given'    then 10
        else 0
    end;
$$;

create or replace function public.trg_xp_post_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Uma vez por cidadão e ocorrência, valendo o mesmo para quem inicia e para
  -- quem adiciona relato a uma ocorrência existente.
  perform public.award_xp(new.user_id, public.xp_value('report_contribution'), 'report_contribution', new.occurrence_id);
  return new;
end;
$$;

-- XP da resolução: uma vez por cidadão e ocorrência, só relatos visíveis.
CREATE OR REPLACE FUNCTION public.vote_resolution_cycle(target_cycle_id bigint, vote_decision text, voter_latitude double precision, voter_longitude double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_cycle public.resolution_cycles%rowtype;
  target_occurrence public.occurrences%rowtype;
  calculated_distance numeric;
  confirmation_count integer;
  rejection_count integer;
  resulting_status text := 'pending';
  created_vote_id bigint;
  contributed_report record;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if vote_decision not in ('confirm', 'reject') then
    raise exception 'Voto inválido.';
  end if;

  if voter_latitude not between -90 and 90
     or voter_longitude not between -180 and 180 then
    raise exception 'Coordenadas inválidas.';
  end if;

  select * into target_cycle
  from public.resolution_cycles cycle
  where cycle.id = target_cycle_id
  for update;

  if not found or target_cycle.status <> 'pending' then
    raise exception 'Ciclo de validação não está aberto.';
  end if;

  select * into target_occurrence
  from public.occurrences occurrence
  where occurrence.id = target_cycle.occurrence_id
  for update;

  if target_cycle.expires_at <= now() then
    update public.resolution_cycles
    set status = 'expired', closed_at = now()
    where id = target_cycle.id;

    update public.occurrences
    set status = target_cycle.previous_status,
        previous_operational_status = null
    where id = target_occurrence.id;

    perform public.sync_occurrence_status_to_posts(
      target_occurrence.id,
      target_cycle.previous_status,
      null,
      'Validação expirada sem quórum; status anterior restaurado.'
    );

    insert into public.occurrence_events (
      occurrence_id,
      actor_kind,
      event_type,
      description,
      administration_id,
      agency_id,
      metadata
    )
    values (
      target_occurrence.id,
      'system',
      'validation_expired',
      'Validação encerrada sem quórum; status anterior restaurado.',
      target_occurrence.administration_id,
      target_occurrence.agency_id,
      jsonb_build_object('cycle_id', target_cycle.id)
    );

    return jsonb_build_object('cycle_status', 'expired');
  end if;

  if target_cycle.initiated_by = current_user_id then
    raise exception 'Quem iniciou o ciclo não pode votar nele.';
  end if;

  calculated_distance := public.distance_km(
    voter_latitude,
    voter_longitude,
    target_occurrence.latitude,
    target_occurrence.longitude
  );

  if calculated_distance > target_cycle.radius_km then
    raise exception 'Usuário fora do raio permitido para validação.';
  end if;

  insert into public.resolution_votes (
    cycle_id,
    voter_id,
    decision,
    latitude,
    longitude,
    distance_km
  )
  values (
    target_cycle.id,
    current_user_id,
    vote_decision,
    voter_latitude,
    voter_longitude,
    calculated_distance
  )
  returning id into created_vote_id;

  perform public.award_xp(
    current_user_id,
    public.xp_value('validation_given'),
    'validation_given',
    created_vote_id
  );

  select
    count(*) filter (where vote.decision = 'confirm'),
    count(*) filter (where vote.decision = 'reject')
  into confirmation_count, rejection_count
  from public.resolution_votes vote
  where vote.cycle_id = target_cycle.id;

  if confirmation_count >= target_cycle.confirmations_required then
    resulting_status := 'approved';

    update public.resolution_cycles
    set status = 'approved', closed_at = now()
    where id = target_cycle.id;

    update public.occurrences
    set status = 'completed',
        previous_operational_status = null,
        resolved_at = now()
    where id = target_occurrence.id;

    perform public.sync_occurrence_status_to_posts(
      target_occurrence.id,
      'completed',
      current_user_id,
      'Resolução confirmada pela comunidade.'
    );

    insert into public.occurrence_events (
      occurrence_id,
      actor_kind,
      event_type,
      description,
      administration_id,
      agency_id,
      metadata
    )
    values (
      target_occurrence.id,
      'system',
      'resolution_confirmed',
      'A comunidade confirmou a resolução da ocorrência.',
      target_occurrence.administration_id,
      target_occurrence.agency_id,
      jsonb_build_object(
        'cycle_id', target_cycle.id,
        'confirmations', confirmation_count,
        'rejections', rejection_count
      )
    );

    -- Uma vez por cidadão e ocorrência, independentemente de quantos relatos fez.
    for contributed_report in
      select distinct post.user_id
      from public.posts post
      where post.occurrence_id = target_occurrence.id
        and post.hidden_at is null
    loop
      perform public.award_xp(
        contributed_report.user_id,
        public.xp_value('report_resolved'),
        'report_resolved',
        target_occurrence.id
      );
    end loop;
  elsif rejection_count >= target_cycle.rejections_required then
    resulting_status := 'rejected';

    update public.resolution_cycles
    set status = 'rejected', closed_at = now()
    where id = target_cycle.id;

    update public.occurrences
    set status = target_cycle.previous_status,
        previous_operational_status = null,
        resolved_at = null
    where id = target_occurrence.id;

    perform public.sync_occurrence_status_to_posts(
      target_occurrence.id,
      target_cycle.previous_status,
      current_user_id,
      'Possível resolução rejeitada pela comunidade.'
    );

    insert into public.occurrence_events (
      occurrence_id,
      actor_kind,
      event_type,
      description,
      administration_id,
      agency_id,
      metadata
    )
    values (
      target_occurrence.id,
      'system',
      'validation_rejected',
      'A comunidade informou que o problema continua.',
      target_occurrence.administration_id,
      target_occurrence.agency_id,
      jsonb_build_object(
        'cycle_id', target_cycle.id,
        'confirmations', confirmation_count,
        'rejections', rejection_count
      )
    );
  end if;

  return jsonb_build_object(
    'cycle_status', resulting_status,
    'confirmations', confirmation_count,
    'rejections', rejection_count,
    'confirmations_required', target_cycle.confirmations_required,
    'rejections_required', target_cycle.rejections_required
  );
end;
$function$;

-- Estorno por moderação também cobre o XP por ocorrência.
CREATE OR REPLACE FUNCTION public.reverse_direct_points_for_post(target_post_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target_post public.posts%rowtype;
  awarded_transaction record;
  reversed_xp integer := 0;
begin
  select * into target_post from public.posts post where post.id = target_post_id;
  if not found then
    return;
  end if;

  for awarded_transaction in
    select tx.id, tx.user_id, tx.points_delta, tx.xp_delta
    from public.xp_transactions tx
    where tx.user_id = target_post.user_id
      and (tx.points_delta > 0 or tx.xp_delta > 0)
      and (
        (tx.source_id = target_post.id and tx.source_type in (
          'valid_contribution', 'occurrence_resolved', 'post_created', 'post_validated'
        ))
        or (tx.source_id = target_post.occurrence_id and (
          tx.source_type in ('valid_contribution', 'occurrence_resolved', 'report_contribution', 'report_resolved')
          or tx.source_type like 'support_received:%'
          or tx.source_type like 'comment_received:%'
        ))
      )
      and not exists (
        select 1 from public.xp_transactions reversal
        where reversal.source_type = 'moderation_reversal'
          and reversal.source_id = tx.id
      )
  loop
    if awarded_transaction.points_delta > 0 then
      perform public.award_points(
        awarded_transaction.user_id,
        -awarded_transaction.points_delta,
        'moderation_reversal',
        awarded_transaction.id,
        false
      );
    else
      insert into public.xp_transactions (user_id, source_type, source_id, xp_delta, points_delta)
      values (awarded_transaction.user_id, 'moderation_reversal', awarded_transaction.id, 0, 0)
      on conflict do nothing;
    end if;
    reversed_xp := reversed_xp + greatest(awarded_transaction.xp_delta, 0);
  end loop;

  if reversed_xp > 0 then
    update public.profiles
    set current_xp = greatest(current_xp - reversed_xp, 0),
        current_level = public.level_for_xp(greatest(current_xp - reversed_xp, 0))
    where id = target_post.user_id;
  end if;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Ranking de cidadãos por pontos atribuídos à cidade
-- ---------------------------------------------------------------------------

-- Início do mês corrente no horário de Brasília.
create or replace function public.ranking_month_start()
returns timestamptz
language sql
stable
as $$
  select date_trunc('month', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo';
$$;

drop function if exists public.participation_points(uuid, text);

-- Pontos do cidadão atribuídos à cidade: 'all' soma todo o histórico;
-- 'month' soma o mês corrente. Estornos por moderação entram com sinal negativo.
create or replace function public.participation_points(target_user_id uuid, target_city_id bigint, period text)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(tx.points_delta), 0)::bigint
  from public.xp_transactions tx
  where tx.user_id = target_user_id
    and tx.city_id = target_city_id
    and tx.points_delta <> 0
    and (coalesce(period, 'all') <> 'month' or tx.created_at >= public.ranking_month_start());
$$;

revoke all on function public.participation_points(uuid, bigint, text) from public, anon, authenticated;

-- Cidadãos elegíveis com pontos na cidade e no período.
create or replace function public.city_participation_scores(target_city_id bigint, period text)
returns table (user_id uuid, points bigint)
language sql
stable
security definer
set search_path = public
as $$
  select tx.user_id, sum(tx.points_delta)::bigint as points
  from public.xp_transactions tx
  join public.profiles profile on profile.id = tx.user_id
  where tx.city_id = target_city_id
    and tx.points_delta <> 0
    and (coalesce(period, 'all') <> 'month' or tx.created_at >= public.ranking_month_start())
    and profile.is_public
    and not public.is_institutional_account(tx.user_id)
  group by tx.user_id
  having sum(tx.points_delta) > 0;
$$;

revoke all on function public.city_participation_scores(bigint, text) from public, anon, authenticated;

drop function if exists public.get_city_ranking(bigint, integer, integer, text);

create or replace function public.get_city_ranking(
  target_city_id bigint,
  page_size integer default 50,
  page_offset integer default 0,
  period text default 'all'
)
returns table (
  rank_position bigint,
  profile_id uuid,
  full_name text,
  username text,
  avatar_url text,
  city_id bigint,
  city_name text,
  current_level integer,
  current_xp integer,
  current_points bigint,
  posts_count integer,
  supports_received integer,
  comments_received integer,
  resolved_posts_count integer,
  ranking_score bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with scores as (
    select * from public.city_participation_scores(target_city_id, period)
  ),
  ranked as (
    select scores.user_id, scores.points, rank() over (order by scores.points desc) as position
    from scores
  ),
  public_contributions as (
    select post.user_id as profile_id,
           count(distinct post.occurrence_id)::integer as posts_count,
           count(distinct post.occurrence_id) filter (where occurrence.status = 'completed')::integer
             as resolved_posts_count
    from public.posts post
    join public.occurrences occurrence on occurrence.id = post.occurrence_id
    where occurrence.city_id = target_city_id
      and post.hidden_at is null
      and not post.anonymity
      and occurrence.invalidated_at is null
    group by post.user_id
  ),
  received as (
    select tx.user_id as profile_id,
           count(*) filter (where tx.source_type like 'support_received:%')::integer as supports_received,
           count(*) filter (where tx.source_type like 'comment_received%')::integer as comments_received
    from public.xp_transactions tx
    where tx.points_delta > 0
      and tx.city_id = target_city_id
    group by tx.user_id
  )
  select
    ranked.position,
    profile.id, profile.full_name, profile.username, profile.avatar_url,
    target_city_id, city.name,
    profile.current_level, profile.current_xp, ranked.points,
    coalesce(contribution.posts_count, 0),
    coalesce(received.supports_received, 0),
    coalesce(received.comments_received, 0),
    coalesce(contribution.resolved_posts_count, 0),
    ranked.points
  from ranked
  join public.profiles profile on profile.id = ranked.user_id
  join public.cities city on city.id = target_city_id
  left join public_contributions contribution on contribution.profile_id = profile.id
  left join received on received.profile_id = profile.id
  order by ranked.points desc, profile.current_xp desc, profile.created_at, profile.id
  limit greatest(1, least(coalesce(page_size, 50), 100))
  offset greatest(0, coalesce(page_offset, 0));
$$;

revoke all on function public.get_city_ranking(bigint, integer, integer, text) from public, anon;
grant execute on function public.get_city_ranking(bigint, integer, integer, text) to authenticated;

create or replace function public.get_participation_standing(target_city_id bigint, period text default 'all')
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select profile.id, profile.is_public,
           public.participation_points(profile.id, target_city_id, period) as points,
           public.is_institutional_account(profile.id) as institutional
    from public.profiles profile
    where profile.id = auth.uid()
  ),
  ranked as (
    select scores.user_id, scores.points, rank() over (order by scores.points desc) as position
    from public.city_participation_scores(target_city_id, period) scores
  )
  select jsonb_build_object(
    'points', greatest(coalesce(me.points, 0), 0),
    'participants', (select count(*) from ranked),
    'position', (select ranked.position from ranked where ranked.user_id = me.id),
    'points_to_next', (
      select min(ranked.points) - me.points + 1
      from ranked
      where ranked.points > me.points
    ),
    'eligible', coalesce(me.is_public and not me.institutional, false),
    'reason', case
      when me.institutional then 'institutional'
      when not me.is_public then 'private'
      else null
    end
  )
  from me;
$$;

revoke all on function public.get_participation_standing(bigint, text) from public, anon;
grant execute on function public.get_participation_standing(bigint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Legado da camada de apoios por relato
-- ---------------------------------------------------------------------------
-- `post_supports` foi substituída por `occurrence_supports` (backfill na
-- migração 20261005012000). O cliente só tem leitura nela e nenhuma função
-- vigente escreve nela; os triggers abaixo não têm como disparar. A tabela é
-- mantida como histórico.

drop trigger if exists xp_on_support_given on public.post_supports;
drop trigger if exists points_on_support_received on public.post_supports;
drop trigger if exists trg_post_supports_count_sync on public.post_supports;
drop trigger if exists notify_on_post_support on public.post_supports;

drop function if exists public.trg_xp_support_given();
drop function if exists public.trg_points_support_received();
drop function if exists public.sync_post_supports_count();
drop function if exists public.notify_post_support_received();

-- Funções órfãs (sem trigger) do modelo anterior.
drop function if exists public.trg_points_comment_received();
drop function if exists public.trg_xp_post_deleted();
drop function if exists public.trg_notify_post_status();
