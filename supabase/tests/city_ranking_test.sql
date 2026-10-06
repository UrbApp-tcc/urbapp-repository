-- Perfil da cidade, Cidade × Gestão e ranking de cidades (spec §22, §33, §44.6).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

-- Foto já enviada ao Storage (pasta de pendentes), como o app faz antes de publicar.
create or replace function pg_temp.test_photo(photo_owner uuid)
returns text[]
language plpgsql
security definer
as $$
declare
  photo_path text := 'reports/pending/' || gen_random_uuid()::text || '/1.jpg';
begin
  insert into storage.objects (bucket_id, name, owner, owner_id)
  values ('post-images', photo_path, photo_owner, photo_owner::text);
  return array[photo_path];
end;
$$;

select plan(37);

create temporary table refs (key text primary key, id bigint not null) on commit drop;
grant select, insert on refs to anon, authenticated;

create or replace function pg_temp.act_as(target_user text)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', target_user, 'role', 'authenticated')::text, true);
end;
$$;

create or replace function pg_temp.city(target_key text, target_name text, target_state text)
returns bigint
language plpgsql
as $$
declare
  created_id bigint;
begin
  insert into public.cities (name, state) values (target_name, target_state::public.states) returning id into created_id;
  insert into refs values (target_key, created_id);
  return created_id;
end;
$$;

-- Cria uma ocorrência pelo fluxo real e ajusta data e estado, como dado
-- histórico. A transição automática é descartada para que cada teste registre
-- o próprio histórico com datas controladas.
create or replace function pg_temp.occurrence(target_city bigint, created timestamptz, final_status text)
returns bigint
language plpgsql
as $$
declare
  created_id bigint;
begin
  perform pg_temp.act_as('40000000-0000-0000-0000-000000000001');
  select occurrence_id into created_id from public.publish_occurrence_report(
    target_city, (select id from refs where key = 'category'),
    'Ocorrência de teste', 'Descrição da ocorrência de teste.', -23.5, -46.6, null, 'Centro', false,
    pg_temp.test_photo('40000000-0000-0000-0000-000000000001')
  );
  update public.occurrences set created_at = created, status = final_status::public.report_status where id = created_id;
  delete from public.occurrence_events where occurrence_id = created_id and event_type = 'status_changed';
  return created_id;
end;
$$;

-- Registra uma transição de estado no histórico.
create or replace function pg_temp.transition(target_occurrence bigint, to_status text, at timestamptz)
returns void
language plpgsql
as $$
begin
  insert into public.occurrence_events (occurrence_id, actor_kind, event_type, description, metadata, created_at)
  values (target_occurrence, 'system', 'status_changed', 'Transição de teste.', jsonb_build_object('to', to_status), at);
end;
$$;

-- Ocorrência resolvida com duração exata (em dias) até a última resolução.
create or replace function pg_temp.resolved(target_city bigint, days numeric)
returns bigint
language plpgsql
as $$
declare
  created_id bigint;
  created timestamptz := now() - interval '200 days';
begin
  created_id := pg_temp.occurrence(target_city, created, 'completed');
  perform pg_temp.transition(created_id, 'completed', created + make_interval(secs => (days * 86400)::double precision));
  return created_id;
end;
$$;

create or replace function pg_temp.rate_row(target_key text, target_period text)
returns table (eligible bigint, resolved bigint, rate numeric, qualified boolean, pos bigint)
language sql
as $$
  select eligible_occurrences, resolved_occurrences, resolution_rate, qualified, rank_position
  from public.get_city_resolution_ranking('resolution_rate', target_period, 100, 0)
  where city_id = (select id from refs where key = target_key);
$$;

create or replace function pg_temp.time_row(target_key text)
returns table (median double precision, resolved bigint, qualified boolean, pos bigint)
language sql
as $$
  select median_resolution_seconds, resolved_occurrences, qualified, rank_position
  from public.get_city_resolution_ranking('resolution_time', 'all', 100, 0)
  where city_id = (select id from refs where key = target_key);
$$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

with created as (
  insert into public.problem_categories (name, slug, requires_resolution_evidence)
  values ('Categoria Ranking Cidades', 'categoria-ranking-cidades', false)
  returning id
)
insert into refs select 'category', id from created;

insert into auth.users (id, email, raw_user_meta_data)
select seed.id, seed.email, jsonb_build_object('username', seed.username, 'full_name', seed.username)
from (values
  ('40000000-0000-0000-0000-000000000001'::uuid, 'rc1@urbapp.test', 'ranking_cidade_um'),
  ('40000000-0000-0000-0000-000000000002'::uuid, 'rc2@urbapp.test', 'ranking_cidade_dois'),
  ('40000000-0000-0000-0000-000000000003'::uuid, 'rc3@urbapp.test', 'ranking_cidade_tres'),
  ('40000000-0000-0000-0000-000000000004'::uuid, 'rc4@urbapp.test', 'ranking_cidade_quatro'),
  ('40000000-0000-0000-0000-000000000009'::uuid, 'rc9@urbapp.test', 'ranking_cidade_admin')
) as seed(id, email, username);
insert into public.platform_user_roles (user_id, role) values ('40000000-0000-0000-0000-000000000009', 'admin');

-- ---------------------------------------------------------------------------
-- Fuso horário da cidade
-- ---------------------------------------------------------------------------

select pg_temp.city('tz_ac', 'Cidade Fuso Acre', 'ac');
select pg_temp.city('tz_sp', 'Cidade Fuso Paulista', 'sp');

select is(
  (select timezone from public.cities where id = (select id from refs where key = 'tz_ac')),
  'America/Rio_Branco',
  'cidade nova recebe fuso IANA conforme a UF'
);

select throws_ok(
  $$update public.cities set timezone = 'Lua/Base' where id = (select id from refs where key = 'tz_sp')$$,
  'P0001',
  null,
  'fuso horário inválido é rejeitado'
);

select is(
  public.city_month_start((select id from refs where key = 'tz_ac')),
  date_trunc('month', now() at time zone 'America/Rio_Branco') at time zone 'America/Rio_Branco',
  'início do mês segue o fuso da cidade'
);

-- Ocorrências um minuto antes e depois da virada do mês local (Acre).
select pg_temp.occurrence((select id from refs where key = 'tz_ac'),
  public.city_month_start((select id from refs where key = 'tz_ac')) - interval '1 minute', 'open');
select pg_temp.occurrence((select id from refs where key = 'tz_ac'),
  public.city_month_start((select id from refs where key = 'tz_ac')) + interval '1 minute', 'open');

select is(
  (select eligible from pg_temp.rate_row('tz_ac', 'month')),
  1::bigint,
  'a coorte do mês respeita o limite do mês no fuso da cidade'
);

-- ---------------------------------------------------------------------------
-- Taxa de resolução: universo elegível e estados
-- ---------------------------------------------------------------------------

select pg_temp.city('rate_um', 'Cidade Ranking Um', 'sp');
select pg_temp.city('rate_aaa', 'Cidade Ranking Aaa', 'sp');
select pg_temp.city('rate_dois', 'Cidade Ranking Dois', 'sp');
select pg_temp.city('small', 'Cidade Ranking Pequena', 'sp');
select pg_temp.city('empty', 'Cidade Ranking Vazia', 'sp');

-- Cidade Um: 10 elegíveis, 6 resolvidas; estados não resolvidos e exclusões.
select pg_temp.occurrence((select id from refs where key = 'rate_um'), now() - interval '40 days', 'completed')
from generate_series(1, 6);
insert into refs
select 'um_awaiting', pg_temp.occurrence((select id from refs where key = 'rate_um'), now() - interval '40 days', 'awaiting_validation');
select pg_temp.occurrence((select id from refs where key = 'rate_um'), now() - interval '40 days', 'reopened');
select pg_temp.occurrence((select id from refs where key = 'rate_um'), now() - interval '40 days', 'closed');
select pg_temp.occurrence((select id from refs where key = 'rate_um'), now() - interval '40 days', 'open');

-- Relato adicional na mesma ocorrência não cria outra ocorrência.
select pg_temp.act_as('40000000-0000-0000-0000-000000000002');
select public.add_report_to_occurrence((select id from refs where key = 'um_awaiting'), null, 'Também vi este problema.', false);

-- Duplicata absorvida, ocorrência invalidada e fora da competência municipal.
insert into refs
select 'um_duplicate', pg_temp.occurrence((select id from refs where key = 'rate_um'), now() - interval '40 days', 'completed');
insert into refs
select 'um_invalid', pg_temp.occurrence((select id from refs where key = 'rate_um'), now() - interval '40 days', 'completed');
insert into refs
select 'um_outside', pg_temp.occurrence((select id from refs where key = 'rate_um'), now() - interval '40 days', 'completed');
update public.occurrences
set merged_into_occurrence_id = (select id from refs where key = 'um_awaiting'),
    closed_reason = 'duplicate_merged', invalidated_at = now(), status = 'closed'
where id = (select id from refs where key = 'um_duplicate');
update public.occurrences set invalidated_at = now(), invalidation_reason = 'Improcedente', status = 'closed'
where id = (select id from refs where key = 'um_invalid');
update public.occurrences set jurisdiction_type = 'state'
where id = (select id from refs where key = 'um_outside');

select is((select eligible from pg_temp.rate_row('rate_um', 'all')), 10::bigint,
  'universo elegível conta ocorrências únicas: relatos extras, duplicatas, invalidadas e externas ficam fora');
select is((select resolved from pg_temp.rate_row('rate_um', 'all')), 6::bigint,
  'aguardando validação, reaberta e encerrada não contam como resolvidas');
select is((select rate from pg_temp.rate_row('rate_um', 'all')), 60.0::numeric,
  'taxa = resolvidas ÷ elegíveis × 100');
select is(
  (select total_occurrences::bigint from public.city_occurrence_metrics where city_id = (select id from refs where key = 'rate_um')),
  10::bigint,
  'o perfil da cidade usa o mesmo universo elegível do ranking'
);
select is(
  (select closed_occurrences::bigint from public.city_occurrence_metrics where city_id = (select id from refs where key = 'rate_um')),
  1::bigint,
  'encerramento administrativo continua visível no perfil, como não resolvido'
);

-- Mesma taxa (60%): Dois tem mais ocorrências; Aaa empata com Um e vence pelo nome.
select pg_temp.occurrence((select id from refs where key = 'rate_dois'), now() - interval '40 days', 'completed')
from generate_series(1, 12);
select pg_temp.occurrence((select id from refs where key = 'rate_dois'), now() - interval '40 days', 'open')
from generate_series(1, 8);
select pg_temp.occurrence((select id from refs where key = 'rate_aaa'), now() - interval '40 days', 'completed')
from generate_series(1, 6);
select pg_temp.occurrence((select id from refs where key = 'rate_aaa'), now() - interval '40 days', 'open')
from generate_series(1, 4);

select is(
  (
    select array_agg(key order by pos)
    from (
      select refs.key, ranking.rank_position as pos
      from public.get_city_resolution_ranking('resolution_rate', 'all', 100, 0) ranking
      join refs on refs.id = ranking.city_id and refs.key in ('rate_um', 'rate_aaa', 'rate_dois')
    ) ordered
  ),
  array['rate_dois', 'rate_aaa', 'rate_um'],
  'desempate da taxa: mais ocorrências, depois ordem alfabética'
);

-- Amostra mínima e cidade sem dados.
select pg_temp.occurrence((select id from refs where key = 'small'), now() - interval '40 days', 'completed');
select ok((select not qualified and pos is null from pg_temp.rate_row('small', 'all')),
  'cidade abaixo da amostra mínima não recebe posição');
select is((select rate from pg_temp.rate_row('small', 'all')), 100.0::numeric,
  'a cidade abaixo da amostra continua com seus dados');
select ok(
  (
    select max(listed.ord) filter (where listed.qualified) < min(listed.ord) filter (where not listed.qualified)
    from public.get_city_resolution_ranking('resolution_rate', 'all', 100, 0)
      with ordinality as listed(rank_position, city_id, city_name, state, eligible_occurrences,
                                resolved_occurrences, resolution_rate, median_resolution_seconds,
                                qualified, minimum_required, ord)
  ),
  'cidades sem posição aparecem depois das classificadas'
);
select ok(
  not exists (select 1 from public.get_city_resolution_ranking('resolution_rate', 'all', 100, 0)
              where city_id = (select id from refs where key = 'empty')),
  'cidade sem ocorrências não aparece no ranking'
);
select is(
  (select total_occurrences::bigint from public.city_occurrence_metrics where city_id = (select id from refs where key = 'empty')),
  0::bigint,
  'cidade sem dados mantém perfil com indicadores zerados'
);

update public.city_ranking_settings set min_occurrences_for_rate = 1;
select ok((select qualified from pg_temp.rate_row('small', 'all')), 'a amostra mínima vem da configuração central');
update public.city_ranking_settings set min_occurrences_for_rate = 10;

-- ---------------------------------------------------------------------------
-- Período: coorte pela data de criação
-- ---------------------------------------------------------------------------

select pg_temp.city('month', 'Cidade Ranking Mensal', 'sp');
insert into refs
select 'month_old', pg_temp.occurrence((select id from refs where key = 'month'),
  public.city_month_start((select id from refs where key = 'month')) - interval '2 days', 'completed');
select pg_temp.transition((select id from refs where key = 'month_old'), 'completed', now());
select pg_temp.occurrence((select id from refs where key = 'month'), now(), 'completed');
select pg_temp.occurrence((select id from refs where key = 'month'), now(), 'open');

select is((select eligible from pg_temp.rate_row('month', 'month')), 2::bigint,
  '"Este mês" considera só ocorrências criadas no mês');
select is((select resolved from pg_temp.rate_row('month', 'month')), 1::bigint,
  'ocorrência anterior resolvida neste mês não entra em "Este mês"');
select is((select resolved from pg_temp.rate_row('month', 'all')), 2::bigint,
  'a mesma ocorrência entra em "Geral"');

-- ---------------------------------------------------------------------------
-- Tempo de resolução: mediana sobre a última resolução
-- ---------------------------------------------------------------------------

select pg_temp.city('t_odd', 'Cidade Tempo Impar', 'sp');
select pg_temp.city('t_even', 'Cidade Tempo Par', 'sp');
select pg_temp.city('t_reopen', 'Cidade Tempo Reaberta', 'sp');
select pg_temp.city('t_tie_more', 'Cidade Tempo Empate Maior', 'sp');
select pg_temp.city('t_tie_less', 'Cidade Tempo Empate Menor', 'sp');

select pg_temp.resolved((select id from refs where key = 't_odd'), days) from unnest(array[1, 2, 3, 4, 100]) days;
select pg_temp.resolved((select id from refs where key = 't_even'), days) from unnest(array[1, 2, 3, 4, 5, 6]) days;

select is((select median from pg_temp.time_row('t_odd')), 3 * 86400::double precision,
  'mediana com quantidade ímpar, sem efeito do outlier');
select is((select median from pg_temp.time_row('t_even')), 3.5 * 86400::double precision,
  'mediana com quantidade par');

-- Reaberta e resolvida de novo usa a última resolução; reaberta atual fica fora.
select pg_temp.resolved((select id from refs where key = 't_reopen'), days) from unnest(array[9, 9, 11, 11]) days;
insert into refs
select 'reopen_twice', pg_temp.occurrence((select id from refs where key = 't_reopen'), now() - interval '200 days', 'completed');
select pg_temp.transition((select id from refs where key = 'reopen_twice'), 'completed', now() - interval '199 days');
select pg_temp.transition((select id from refs where key = 'reopen_twice'), 'reopened', now() - interval '195 days');
select pg_temp.transition((select id from refs where key = 'reopen_twice'), 'completed', now() - interval '190 days');
insert into refs
select 'still_reopened', pg_temp.occurrence((select id from refs where key = 't_reopen'), now() - interval '200 days', 'reopened');
select pg_temp.transition((select id from refs where key = 'still_reopened'), 'completed', now() - interval '199 days');
select pg_temp.transition((select id from refs where key = 'still_reopened'), 'reopened', now() - interval '198 days');

select is((select median from pg_temp.time_row('t_reopen')), 10 * 86400::double precision,
  'ocorrência reaberta e resolvida de novo usa a última resolução');
select is((select resolved from pg_temp.time_row('t_reopen')), 5::bigint,
  'ocorrência atualmente reaberta fica fora do tempo de resolução');

select pg_temp.resolved((select id from refs where key = 't_tie_more'), 4) from generate_series(1, 6);
select pg_temp.resolved((select id from refs where key = 't_tie_less'), 4) from generate_series(1, 5);

select is(
  (
    select array_agg(key order by pos)
    from (
      select refs.key, ranking.rank_position as pos
      from public.get_city_resolution_ranking('resolution_time', 'all', 100, 0) ranking
      join refs on refs.id = ranking.city_id and refs.key like 't\_%'
    ) ordered
  ),
  array['t_odd', 't_even', 't_tie_more', 't_tie_less', 't_reopen'],
  'ordenação do tempo: menor mediana; empate pela maior amostra'
);

select ok((select not qualified and pos is null from pg_temp.time_row('small')),
  'tempo exige a amostra mínima de resoluções');

select is(
  (select count(*) from public.get_city_resolution_ranking('resolution_time', 'all', 2, 0)),
  2::bigint,
  'o ranking é paginado'
);
select ok(
  (select city_id from public.get_city_resolution_ranking('resolution_time', 'all', 1, 1))
  = (select city_id from public.get_city_resolution_ranking('resolution_time', 'all', 2, 0) offset 1 limit 1),
  'a paginação mantém a ordem determinística'
);

select throws_ok(
  $$select * from public.get_city_resolution_ranking('urbapp_score', 'all', 10, 0)$$,
  'P0001',
  null,
  'não existe indicador composto'
);

-- ---------------------------------------------------------------------------
-- Cidade × Gestão (spec §33)
-- ---------------------------------------------------------------------------

select pg_temp.city('gestao', 'Cidade Duas Gestoes', 'sp');
insert into public.validation_settings (city_id, confirmations_required, rejections_required, radius_km)
values ((select id from refs where key = 'gestao'), 2, 2, 5);

select pg_temp.act_as('40000000-0000-0000-0000-000000000009');
insert into refs
select 'gestao_a', public.rollover_municipal_administration(
  (select id from refs where key = 'gestao'), 'Gestão A', 'Prefeito A', current_date - 30, null);

select pg_temp.act_as('40000000-0000-0000-0000-000000000001');
insert into refs
select 'gestao_occurrence', occurrence_id from public.publish_occurrence_report(
  (select id from refs where key = 'gestao'), (select id from refs where key = 'category'),
  'Calçada quebrada', 'Calçada quebrada em frente à escola.', -23.5, -46.6, null, 'Centro', false,
  pg_temp.test_photo('40000000-0000-0000-0000-000000000001')
);

select pg_temp.act_as('40000000-0000-0000-0000-000000000009');
insert into refs
select 'gestao_b', public.rollover_municipal_administration(
  (select id from refs where key = 'gestao'), 'Gestão B', 'Prefeito B', current_date, null);

select pg_temp.act_as('40000000-0000-0000-0000-000000000002');
insert into refs
select 'gestao_cycle', public.open_resolution_cycle((select id from refs where key = 'gestao_occurrence'), 'Consertaram a calçada.', 'citizen');
select pg_temp.act_as('40000000-0000-0000-0000-000000000003');
select public.vote_resolution_cycle((select id from refs where key = 'gestao_cycle'), 'confirm', -23.5001, -46.6001);
select pg_temp.act_as('40000000-0000-0000-0000-000000000004');
select public.vote_resolution_cycle((select id from refs where key = 'gestao_cycle'), 'confirm', -23.5002, -46.6002);
select pg_temp.act_as('40000000-0000-0000-0000-000000000001');

select is(
  (select row(total_occurrences, resolved_occurrences)::text from public.city_occurrence_metrics
   where city_id = (select id from refs where key = 'gestao')),
  '(1,1)',
  'a cidade mantém histórico contínuo entre mandatos'
);
select is(
  (select row(registered_during_period, left_pending_occurrences, resolved_during_period)::text
   from public.get_city_administrations((select id from refs where key = 'gestao'))
   where administration_id = (select id from refs where key = 'gestao_a')),
  '(1,1,0)',
  'Gestão A registra a ocorrência criada no mandato e a deixa pendente'
);
select is(
  (select row(registered_during_period, inherited_occurrences, resolved_during_period)::text
   from public.get_city_administrations((select id from refs where key = 'gestao'))
   where administration_id = (select id from refs where key = 'gestao_b')),
  '(0,1,1)',
  'Gestão B herda a ocorrência e registra a resolução no seu período'
);
select ok(
  (select is_current from public.get_city_administrations((select id from refs where key = 'gestao'))
   where administration_id = (select id from refs where key = 'gestao_b')),
  'a gestão vigente é identificada pelo período'
);

-- ---------------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------------

set local role authenticated;
select throws_ok(
  $$update public.city_ranking_settings set min_occurrences_for_rate = 1$$,
  '42501',
  null,
  'o cliente não altera a amostra mínima'
);
select throws_ok(
  $$select * from public.city_eligible_occurrences$$,
  '42501',
  null,
  'o universo interno do ranking não é exposto ao cliente'
);
reset role;
set local role anon;
select lives_ok(
  $$select total_occurrences, median_resolution_seconds from public.city_occurrence_metrics$$,
  'o perfil público da cidade é legível sem login, como na Transparência'
);
select lives_ok(
  $$select * from public.city_monthly_metrics$$,
  'a evolução mensal da cidade é legível sem login'
);
select throws_ok(
  $$select * from public.get_city_resolution_ranking('resolution_rate', 'all', 10, 0)$$,
  '42501',
  null,
  'visitantes não autenticados não consultam o ranking de cidades'
);
reset role;

select * from finish();
rollback;
