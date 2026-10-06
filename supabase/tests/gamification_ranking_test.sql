-- Gamificação e ranking de cidadãos (spec §21, §22, §39, §40).
-- Fluxos reais (relatar, adicionar relato, validar), executados com o papel da
-- API (`authenticated` / `anon`) sempre que a regra envolve o cliente.
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

select plan(26);

create temporary table refs (key text primary key, id bigint not null) on commit drop;
grant select, insert on refs to anon, authenticated;

create or replace function pg_temp.act_as(target_user text)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', target_user, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.points(target_user text, source text, occurrence bigint)
returns bigint
language sql
as $$
  select coalesce(sum(points_delta), 0)::bigint from public.xp_transactions
  where user_id = target_user::uuid and source_type = source and source_id = occurrence;
$$;

create or replace function pg_temp.count_tx(target_user text, source text, occurrence bigint)
returns bigint
language sql
as $$
  select count(*) from public.xp_transactions
  where user_id = target_user::uuid and source_type = source and source_id = occurrence;
$$;

-- ---------------------------------------------------------------------------
-- Fixtures (superusuário)
-- ---------------------------------------------------------------------------

with created as (insert into public.cities (name, state) values ('Cidade Pontos A', 'sp') returning id)
insert into refs select 'city_a', id from created;
with created as (insert into public.cities (name, state) values ('Cidade Pontos B', 'sp') returning id)
insert into refs select 'city_b', id from created;
with created as (
  insert into public.problem_categories (name, slug, requires_resolution_evidence)
  values ('Categoria Pontos', 'categoria-pontos', false)
  returning id
)
insert into refs select 'category', id from created;

insert into public.validation_settings (city_id, confirmations_required, rejections_required, radius_km)
values ((select id from refs where key = 'city_a'), 2, 2, 5);

insert into auth.users (id, email, raw_user_meta_data)
select seed.id, seed.email,
       jsonb_build_object('username', seed.username, 'full_name', seed.full_name,
                          'city_id', (select id::text from refs where key = 'city_a'))
from (values
  ('30000000-0000-0000-0000-000000000001'::uuid, 'p1@urbapp.test', 'pontos_um', 'Pontos Um'),
  ('30000000-0000-0000-0000-000000000002'::uuid, 'p2@urbapp.test', 'pontos_dois', 'Pontos Dois'),
  ('30000000-0000-0000-0000-000000000003'::uuid, 'p3@urbapp.test', 'pontos_tres', 'Pontos Tres'),
  ('30000000-0000-0000-0000-000000000004'::uuid, 'p4@urbapp.test', 'pontos_quatro', 'Pontos Quatro'),
  ('30000000-0000-0000-0000-000000000005'::uuid, 'p5@urbapp.test', 'pontos_cinco', 'Pontos Cinco'),
  ('30000000-0000-0000-0000-000000000006'::uuid, 'p6@urbapp.test', 'pontos_seis', 'Pontos Seis')
) as seed(id, email, username, full_name);

-- p6 representa um órgão da cidade A.
insert into public.agency_users (agency_id, user_id, role, is_active)
select agency.id, '30000000-0000-0000-0000-000000000006', 'agent', true
from public.public_agencies agency
where agency.city_id = (select id from refs where key = 'city_a')
limit 1;

-- ---------------------------------------------------------------------------
-- Relato novo e relato em ocorrência existente valem o mesmo
-- ---------------------------------------------------------------------------

select pg_temp.act_as('30000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into refs
select 'occurrence', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city_a'), (select id from refs where key = 'category'),
  'Buraco na avenida', 'Buraco grande na faixa da direita.', -23.5000, -46.6000, 'Av. Central', 'Centro', false,
  pg_temp.test_photo('30000000-0000-0000-0000-000000000001')
);

select pg_temp.act_as('30000000-0000-0000-0000-000000000002');
select lives_ok(
  $$select public.add_report_to_occurrence((select id from refs where key = 'occurrence'), null, 'Também vi o buraco hoje.', false)$$,
  'um cidadão adiciona relato a uma ocorrência existente'
);
select lives_ok(
  $$select public.add_report_to_occurrence((select id from refs where key = 'occurrence'), null, 'Voltei e piorou.', false)$$,
  'o mesmo cidadão adiciona um segundo relato na mesma ocorrência'
);

reset role;

select is(
  pg_temp.points('30000000-0000-0000-0000-000000000001', 'valid_contribution', (select id from refs where key = 'occurrence')),
  50::bigint,
  'relato que inicia a ocorrência recebe a recompensa de contribuição'
);

select is(
  pg_temp.points('30000000-0000-0000-0000-000000000002', 'valid_contribution', (select id from refs where key = 'occurrence')),
  50::bigint,
  'relato em ocorrência existente recebe recompensa equivalente'
);

select is(
  pg_temp.count_tx('30000000-0000-0000-0000-000000000002', 'valid_contribution', (select id from refs where key = 'occurrence')),
  1::bigint,
  'segundo relato do mesmo cidadão na mesma ocorrência não repete os pontos'
);

select is(
  pg_temp.count_tx('30000000-0000-0000-0000-000000000002', 'report_contribution', (select id from refs where key = 'occurrence')),
  1::bigint,
  'segundo relato do mesmo cidadão na mesma ocorrência não repete o XP'
);

select is(
  (select xp_delta from public.xp_transactions
   where user_id = '30000000-0000-0000-0000-000000000001' and source_type = 'report_contribution'
     and source_id = (select id from refs where key = 'occurrence')),
  (select xp_delta from public.xp_transactions
   where user_id = '30000000-0000-0000-0000-000000000002' and source_type = 'report_contribution'
     and source_id = (select id from refs where key = 'occurrence')),
  'iniciar ou adicionar relato rende o mesmo XP'
);

select is(
  (select count(*) from public.xp_transactions
   where user_id in ('30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002')
     and (city_id is distinct from (select id from refs where key = 'city_a'))),
  0::bigint,
  'todas as transações registram a cidade da ação'
);

-- ---------------------------------------------------------------------------
-- Resolução: uma recompensa por cidadão elegível
-- ---------------------------------------------------------------------------

select pg_temp.act_as('30000000-0000-0000-0000-000000000003');
set local role authenticated;
insert into refs
select 'cycle', public.open_resolution_cycle((select id from refs where key = 'occurrence'), 'Tamparam o buraco.', 'citizen');
select pg_temp.act_as('30000000-0000-0000-0000-000000000004');
select public.vote_resolution_cycle((select id from refs where key = 'cycle'), 'confirm', -23.5001, -46.6001);
select pg_temp.act_as('30000000-0000-0000-0000-000000000005');
select public.vote_resolution_cycle((select id from refs where key = 'cycle'), 'confirm', -23.5002, -46.6002);
reset role;

select is(
  (select status::text from public.occurrences where id = (select id from refs where key = 'occurrence')),
  'completed',
  'a validação comunitária resolve a ocorrência'
);

select is(
  pg_temp.count_tx('30000000-0000-0000-0000-000000000002', 'occurrence_resolved', (select id from refs where key = 'occurrence')),
  1::bigint,
  'quem fez dois relatos recebe a recompensa de resolução uma única vez'
);

select is(
  (select count(distinct user_id) from public.xp_transactions
   where source_type = 'occurrence_resolved' and source_id = (select id from refs where key = 'occurrence')),
  2::bigint,
  'iniciador e quem adicionou relato recebem a recompensa de resolução'
);

select is(
  pg_temp.count_tx('30000000-0000-0000-0000-000000000002', 'report_resolved', (select id from refs where key = 'occurrence')),
  1::bigint,
  'o XP de resolução também vale uma vez por cidadão e ocorrência'
);

select is(
  (select total_occurrences::bigint from public.city_occurrence_metrics where city_id = (select id from refs where key = 'city_a')),
  1::bigint,
  'vários relatores não multiplicam a ocorrência nos indicadores públicos'
);

select is(
  public.award_points(
    '30000000-0000-0000-0000-000000000001'::uuid, 50, 'valid_contribution',
    (select id from refs where key = 'occurrence'), false
  ),
  false,
  'conceder a mesma recompensa de novo é idempotente'
);

-- ---------------------------------------------------------------------------
-- Ranking por cidade da ação, geral e mensal
-- ---------------------------------------------------------------------------

select pg_temp.act_as('30000000-0000-0000-0000-000000000002');
set local role authenticated;
update public.profiles set city_id = (select id from refs where key = 'city_b')
where id = '30000000-0000-0000-0000-000000000002';

select is(
  (select current_points from public.get_city_ranking((select id from refs where key = 'city_a'))
   where profile_id = '30000000-0000-0000-0000-000000000002'),
  150::bigint,
  'trocar a cidade do perfil não move os pontos históricos'
);

select ok(
  not exists (
    select 1 from public.get_city_ranking((select id from refs where key = 'city_b'))
    where profile_id = '30000000-0000-0000-0000-000000000002'
  ),
  'a nova cidade do perfil não recebe pontos que não foram gerados nela'
);

reset role;
insert into public.xp_transactions (user_id, source_type, source_id, xp_delta, points_delta, city_id, created_at)
values ('30000000-0000-0000-0000-000000000003', 'valid_contribution', 990001, 0, 500,
        (select id from refs where key = 'city_a'), now() - interval '60 days');
update public.profiles set current_points = current_points + 500 where id = '30000000-0000-0000-0000-000000000003';

-- p6 (órgão) e p4 (perfil privado) acumulam pontos na cidade.
insert into public.xp_transactions (user_id, source_type, source_id, xp_delta, points_delta, city_id)
values
  ('30000000-0000-0000-0000-000000000006', 'valid_contribution', 990002, 0, 900, (select id from refs where key = 'city_a')),
  ('30000000-0000-0000-0000-000000000004', 'valid_contribution', 990003, 0, 800, (select id from refs where key = 'city_a'));
update public.profiles set current_points = current_points + 900 where id = '30000000-0000-0000-0000-000000000006';
update public.profiles set current_points = current_points + 800, is_public = false where id = '30000000-0000-0000-0000-000000000004';

select pg_temp.act_as('30000000-0000-0000-0000-000000000001');
set local role authenticated;

select is(
  (select profile_id from public.get_city_ranking((select id from refs where key = 'city_a'), 50, 0, 'all') where rank_position = 1),
  '30000000-0000-0000-0000-000000000003'::uuid,
  'o ranking geral soma o histórico de pontos atribuídos à cidade'
);

select ok(
  not exists (
    select 1 from public.get_city_ranking((select id from refs where key = 'city_a'), 50, 0, 'month')
    where profile_id = '30000000-0000-0000-0000-000000000003'
  ),
  'o ranking do mês considera apenas pontos do mês corrente'
);

select is(
  (select current_points from public.get_city_ranking((select id from refs where key = 'city_a'), 50, 0, 'month')
   where profile_id = '30000000-0000-0000-0000-000000000001'),
  (select sum(points_delta)::bigint from public.xp_transactions
   where user_id = '30000000-0000-0000-0000-000000000001'
     and city_id = (select id from refs where key = 'city_a')
     and created_at >= public.ranking_month_start()),
  'os pontos do mês são a soma das transações da cidade no período'
);

select ok(
  not exists (
    select 1 from public.get_city_ranking((select id from refs where key = 'city_a'))
    where profile_id in ('30000000-0000-0000-0000-000000000006', '30000000-0000-0000-0000-000000000004')
  ),
  'perfis institucionais e privados não aparecem no ranking de cidadãos'
);

-- ---------------------------------------------------------------------------
-- Segurança: o cliente não manipula pontos nem XP
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.xp_transactions (user_id, source_type, source_id, points_delta)
    values (auth.uid(), 'valid_contribution', 1, 1000)$$,
  '42501',
  null,
  'o cliente não insere transações de pontos'
);

select throws_ok(
  $$update public.profiles set current_points = 99999, current_xp = 99999 where id = auth.uid()$$,
  '42501',
  null,
  'o cliente não edita saldo de pontos nem XP'
);

select throws_ok(
  $$select public.award_points(auth.uid(), 1000, 'manual', 1, false)$$,
  '42501',
  null,
  'o cliente não chama a função interna de concessão'
);

reset role;
set local role anon;
select throws_ok(
  $$select * from public.get_city_ranking(1)$$,
  '42501',
  null,
  'visitantes não autenticados não consultam o ranking'
);
reset role;

-- ---------------------------------------------------------------------------
-- Consistência e legado
-- ---------------------------------------------------------------------------

select ok(
  not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.post_supports'::regclass and not tgisinternal
  )
  and to_regprocedure('public.trg_points_support_received()') is null
  and to_regprocedure('public.trg_xp_support_given()') is null,
  'triggers legados da antiga tabela de apoios foram removidos'
);

select is(
  (select count(*) from public.profiles profile
   where profile.id::text like '30000000-%'
     and profile.current_points <> coalesce((select sum(tx.points_delta) from public.xp_transactions tx where tx.user_id = profile.id), 0)),
  0::bigint,
  'nenhum saldo de pontos diverge do histórico transacional'
);

select * from finish();
rollback;
