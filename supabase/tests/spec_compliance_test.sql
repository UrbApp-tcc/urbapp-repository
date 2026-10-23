-- Aderência à Especificação Mestre (seções 6, 13, 30, 35, 36, 37, 40, 42 e 44.8).
-- Cobre lacunas das demais suítes: parâmetros padrão do MVP, quórum de 3 sem
-- o iniciador, voto único, cooldown por usuário, ciclo concorrente, crédito de
-- vereador só com ação concreta, ausência de double counting com vários
-- vereadores, competência não municipal, duplicidade consolidada e escrita
-- direta pela API. As verificações rodam com o papel real da API.
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

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

-- Executa um comando como o cliente e informa quantas linhas ele alterou.
-- Uma recusa por privilégio/RLS volta como 'denied'; 0 linhas também é recusa
-- (RLS filtra silenciosamente em UPDATE/DELETE).
create or replace function pg_temp.client_write(statement text)
returns text
language plpgsql
as $$
declare
  affected integer;
begin
  execute statement;
  get diagnostics affected = row_count;
  return case when affected = 0 then 'denied' else 'changed:' || affected end;
exception
  when insufficient_privilege or check_violation or raise_exception then
    return 'denied';
end;
$$;

select plan(88);

create temporary table refs (key text primary key, id bigint not null) on commit drop;
grant select, insert on refs to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures (superusuário)
-- ---------------------------------------------------------------------------

with created as (
  insert into public.cities (name, state) values ('Cidade Spec UrbApp', 'rs') returning id
)
insert into refs select 'city', id from created;

with created as (
  insert into public.problem_categories (name, slug, requires_resolution_evidence)
  values ('Categoria Spec UrbApp', 'categoria-spec-urbapp', false)
  returning id
)
insert into refs select 'category', id from created;

with created as (
  insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
  values ((select id from refs where key = 'city'), 'Orgao Spec', 'secretaria', 'spec@urbapp.test', 'verified')
  returning id
)
insert into refs select 'agency', id from created;

update public.agency_responsibilities
set agency_id = (select id from refs where key = 'agency')
where city_id = (select id from refs where key = 'city') and ends_on is null;

insert into refs
select 'administration', administration.id
from public.municipal_administrations administration
where administration.city_id = (select id from refs where key = 'city')
order by administration.id desc
limit 1;

-- Sem validation_settings da cidade: vale o padrão da plataforma.

insert into auth.users (id, email, raw_user_meta_data)
select seed.id, seed.email,
       jsonb_build_object('username', seed.username, 'full_name', seed.full_name,
                          'city_id', (select id::text from refs where key = 'city'))
from (values
  ('50000000-0000-0000-0000-000000000001'::uuid, 'sp1@urbapp.test', 'spec_autor', 'Spec Autor'),
  ('50000000-0000-0000-0000-000000000002'::uuid, 'sp2@urbapp.test', 'spec_v1', 'Spec Votante Um'),
  ('50000000-0000-0000-0000-000000000003'::uuid, 'sp3@urbapp.test', 'spec_v2', 'Spec Votante Dois'),
  ('50000000-0000-0000-0000-000000000004'::uuid, 'sp4@urbapp.test', 'spec_v3', 'Spec Votante Tres'),
  ('50000000-0000-0000-0000-000000000005'::uuid, 'sp5@urbapp.test', 'spec_v4', 'Spec Votante Quatro'),
  ('50000000-0000-0000-0000-000000000006'::uuid, 'sp6@urbapp.test', 'spec_ver_a', 'Spec Vereador A'),
  ('50000000-0000-0000-0000-000000000007'::uuid, 'sp7@urbapp.test', 'spec_ver_b', 'Spec Vereador B'),
  ('50000000-0000-0000-0000-000000000008'::uuid, 'sp8@urbapp.test', 'spec_ver_nv', 'Spec Vereador NV'),
  ('50000000-0000-0000-0000-000000000009'::uuid, 'sp9@urbapp.test', 'spec_orgao', 'Spec Servidor Orgao'),
  ('50000000-0000-0000-0000-000000000010'::uuid, 'sp10@urbapp.test', 'spec_gestao', 'Spec Servidor Gestao'),
  ('50000000-0000-0000-0000-000000000011'::uuid, 'sp11@urbapp.test', 'spec_moderador', 'Spec Moderador')
) as seed(id, email, username, full_name);

insert into public.councilor_profiles (
  profile_id, city_id, public_name, party, mandate_starts_on, mandate_ends_on, profile_status, verified_at
)
values
  ('50000000-0000-0000-0000-000000000006', (select id from refs where key = 'city'),
   'Vereadora A Spec', 'AAA', current_date - 30, current_date + 365, 'verified', now()),
  ('50000000-0000-0000-0000-000000000007', (select id from refs where key = 'city'),
   'Vereador B Spec', 'BBB', current_date - 30, current_date + 365, 'verified', now()),
  ('50000000-0000-0000-0000-000000000008', (select id from refs where key = 'city'),
   'Vereador Nao Verificado', 'CCC', current_date - 30, current_date + 365, 'unclaimed', null);

insert into public.agency_users (agency_id, user_id, role, is_active)
values ((select id from refs where key = 'agency'), '50000000-0000-0000-0000-000000000009', 'agent', true);

insert into public.administration_users (administration_id, user_id, role, is_active)
values ((select id from refs where key = 'administration'), '50000000-0000-0000-0000-000000000010', 'manager', true);

insert into public.platform_user_roles (user_id, role)
values ('50000000-0000-0000-0000-000000000011', 'moderator');

-- ---------------------------------------------------------------------------
-- §42 Parâmetros iniciais do MVP
-- ---------------------------------------------------------------------------

select is((select confirmations_required from public.validation_settings where city_id is null), 3,
  '§42 padrão: 3 confirmações para resolver');
select is((select rejections_required from public.validation_settings where city_id is null), 2,
  '§42 padrão: 2 rejeições rejeitam a tentativa');
select is((select radius_km from public.validation_settings where city_id is null), 5::numeric,
  '§42 padrão: raio de 5 km');
select is((select cycle_duration from public.validation_settings where city_id is null), interval '72 hours',
  '§42 padrão: ciclo de 72 horas');
select is((select initiator_cooldown from public.validation_settings where city_id is null), interval '24 hours',
  '§42 padrão: cooldown de 24 horas');

-- ---------------------------------------------------------------------------
-- §6.2 / §18 Resolução só pela comunidade, sem vereador nem ação oficial
-- ---------------------------------------------------------------------------

select pg_temp.act_as('50000000-0000-0000-0000-000000000001');
set local role authenticated;

insert into refs
select 'o1', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city'), (select id from refs where key = 'category'),
  'Buraco na Rua Spec', 'Buraco grande perto do ponto de ônibus.',
  -30.0300, -51.2300, 'Rua Spec, 10', 'Centro', false,
  pg_temp.test_photo('50000000-0000-0000-0000-000000000001'));

select is(
  (select status::text from public.occurrences where id = (select id from refs where key = 'o1')),
  'open', '§31 nova ocorrência começa ABERTO');

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');
insert into refs
select 'o1_cycle', public.open_resolution_cycle((select id from refs where key = 'o1'), 'O buraco foi tapado.', 'citizen');

select is(
  (select confirmations_required from public.resolution_cycles where id = (select id from refs where key = 'o1_cycle')),
  3, '§30 sem regra da cidade, o ciclo usa o quórum padrão de 3');

select pg_temp.act_as('50000000-0000-0000-0000-000000000003');
select throws_ok(
  $$select public.open_resolution_cycle((select id from refs where key = 'o1'), 'Outra tentativa simultânea.', 'citizen')$$,
  'P0001', null,
  '§30 não é possível abrir um segundo ciclo enquanto outro está aberto');

select is(
  public.vote_resolution_cycle((select id from refs where key = 'o1_cycle'), 'confirm', -30.0305, -51.2305) ->> 'cycle_status',
  'pending', '§30 1ª confirmação mantém o ciclo aberto');
select throws_ok(
  $$select public.vote_resolution_cycle((select id from refs where key = 'o1_cycle'), 'confirm', -30.0305, -51.2305)$$,
  null, null,
  '§40 um voto por usuário por ciclo (segundo voto recusado)');
select throws_ok(
  $$select public.vote_resolution_cycle((select id from refs where key = 'o1_cycle'), 'reject', -30.0305, -51.2305)$$,
  null, null,
  '§40 o usuário não troca o voto já registrado');

select pg_temp.act_as('50000000-0000-0000-0000-000000000004');
select is(
  public.vote_resolution_cycle((select id from refs where key = 'o1_cycle'), 'confirm', -30.0302, -51.2298) ->> 'cycle_status',
  'pending', '§30 2 confirmações ainda não resolvem (quórum é 3)');
select is(
  (select status::text from public.occurrences where id = (select id from refs where key = 'o1')),
  'awaiting_validation', '§30 com 2 de 3 confirmações a ocorrência segue AGUARDANDO_VALIDACAO');

-- Exatamente no limite de 5 km não conta como fora do raio; 5,5 km sim.
select pg_temp.act_as('50000000-0000-0000-0000-000000000005');
select throws_ok(
  $$select public.vote_resolution_cycle((select id from refs where key = 'o1_cycle'), 'confirm', -30.0300 + (5.5 / 111.195), -51.2300)$$,
  'P0001', null,
  '§30 voto a ~5,5 km da ocorrência é recusado');
select is(
  public.vote_resolution_cycle((select id from refs where key = 'o1_cycle'), 'confirm', -30.0300 + (4.9 / 111.195), -51.2300) ->> 'cycle_status',
  'approved', '§30 a 3ª confirmação elegível (a 4,9 km) resolve');
select is(
  (select status::text from public.occurrences where id = (select id from refs where key = 'o1')),
  'completed', '§6.2 resolvida pela comunidade sem vereador e sem ação oficial');
select is(
  (select count(*) from public.institutional_actions where occurrence_id = (select id from refs where key = 'o1')),
  0::bigint, '§18 não aparece como conclusão oficialmente informada pela Prefeitura');

select pg_temp.act_as('50000000-0000-0000-0000-000000000003');
select throws_ok(
  $$select public.vote_resolution_cycle((select id from refs where key = 'o1_cycle'), 'confirm', -30.0305, -51.2305)$$,
  'P0001', null,
  '§40 votar em ciclo já encerrado é recusado');
select throws_ok(
  $$select public.open_resolution_cycle((select id from refs where key = 'o1'), 'Já resolvida, nova tentativa.', 'citizen')$$,
  'P0001', null,
  '§31 ocorrência RESOLVIDO não aceita novo ciclo (precisa reabrir)');

reset role;
select is(
  (select resolved_occurrences from public.city_occurrence_metrics where city_id = (select id from refs where key = 'city')),
  1::bigint, '§6.2 conta como resolvida para a cidade');
select is(
  (select resolved_occurrences from public.agency_occurrence_metrics where agency_id = (select id from refs where key = 'agency')),
  1::bigint, '§6.2 conta como resolvida para o órgão responsável');
select is(
  (select resolved_during_period from public.administration_occurrence_metrics where administration_id = (select id from refs where key = 'administration')),
  1::bigint, '§6.2 conta como resolvida durante a gestão vigente');
select is(
  (select confirmed_conclusions from public.administration_occurrence_metrics where administration_id = (select id from refs where key = 'administration')),
  0::bigint, '§18 não conta como conclusão administrativa confirmada');
select is(
  (select coalesce(sum(followed_demands), 0) from public.councilor_activity_metrics where city_id = (select id from refs where key = 'city')),
  0::numeric, '§6.2 não conta para nenhum vereador');

-- ---------------------------------------------------------------------------
-- §30 Rejeição, retorno ao estado anterior e cooldown por usuário
-- ---------------------------------------------------------------------------

select pg_temp.act_as('50000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into refs
select 'o2', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city'), (select id from refs where key = 'category'),
  'Lixo acumulado Spec', 'Lixo acumulado na esquina há uma semana.',
  -30.0500, -51.2100, 'Rua Spec, 200', 'Bairro Spec', false,
  pg_temp.test_photo('50000000-0000-0000-0000-000000000001'));

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');
insert into refs
select 'o2_cycle_a', public.open_resolution_cycle((select id from refs where key = 'o2'), 'Parece que recolheram.', 'citizen');

select pg_temp.act_as('50000000-0000-0000-0000-000000000003');
select is(
  public.vote_resolution_cycle((select id from refs where key = 'o2_cycle_a'), 'reject', -30.0501, -51.2101) ->> 'cycle_status',
  'pending', '§30 1 rejeição não encerra o ciclo');
select pg_temp.act_as('50000000-0000-0000-0000-000000000004');
select is(
  public.vote_resolution_cycle((select id from refs where key = 'o2_cycle_a'), 'reject', -30.0502, -51.2102) ->> 'cycle_status',
  'rejected', '§30 2 rejeições rejeitam a tentativa');
select is(
  (select status::text from public.occurrences where id = (select id from refs where key = 'o2')),
  'open', '§30 rejeição devolve a ocorrência ao estado anterior (ABERTO)');

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');
select throws_ok(
  $$select public.open_resolution_cycle((select id from refs where key = 'o2'), 'Tentando de novo logo em seguida.', 'citizen')$$,
  'P0001', null,
  '§30 o mesmo usuário aguarda 24 h para nova tentativa');

select pg_temp.act_as('50000000-0000-0000-0000-000000000003');
insert into refs
select 'o2_cycle_b', public.open_resolution_cycle((select id from refs where key = 'o2'), 'Agora recolheram de verdade.', 'citizen');
select ok(
  (select id > 0 from refs where key = 'o2_cycle_b'),
  '§30 o cooldown é por usuário: outro cidadão pode abrir novo ciclo');

select pg_temp.act_as('50000000-0000-0000-0000-000000000004');
select public.vote_resolution_cycle((select id from refs where key = 'o2_cycle_b'), 'reject', -30.0502, -51.2102);
select pg_temp.act_as('50000000-0000-0000-0000-000000000005');
select is(
  public.vote_resolution_cycle((select id from refs where key = 'o2_cycle_b'), 'reject', -30.0503, -51.2103) ->> 'cycle_status',
  'rejected', '§30 segunda tentativa também pode ser rejeitada');

reset role;
update public.resolution_cycles
set opened_at = now() - interval '26 hours',
    expires_at = now() - interval '25 hours' + interval '72 hours',
    closed_at = now() - interval '25 hours'
where id = (select id from refs where key = 'o2_cycle_a');

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');
set local role authenticated;
select lives_ok(
  $$select public.open_resolution_cycle((select id from refs where key = 'o2'), 'Passado o cooldown, nova tentativa.', 'citizen')$$,
  '§30 depois de 24 h o mesmo usuário pode tentar de novo');

reset role;
select is(
  (select count(*) from public.occurrence_events
   where occurrence_id = (select id from refs where key = 'o2') and event_type = 'validation_rejected'),
  2::bigint, '§31 cada rejeição gera evento na linha do tempo');

-- ---------------------------------------------------------------------------
-- §35 / §13 Vereadores: crédito só com ação concreta e sem double counting
-- §6.5 Gestão + vereador
-- ---------------------------------------------------------------------------

select pg_temp.act_as('50000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into refs
select 'o3', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city'), (select id from refs where key = 'category'),
  'Poste apagado Spec', 'Poste apagado deixando a rua escura à noite.',
  -30.0700, -51.1900, 'Rua Spec, 300', 'Vila Spec', false,
  pg_temp.test_photo('50000000-0000-0000-0000-000000000001'));

select pg_temp.act_as('50000000-0000-0000-0000-000000000008');
select throws_ok(
  $$select public.start_councilor_following((select id from refs where key = 'o3'))$$,
  null, null,
  '§3.4 vereador não verificado não inicia acompanhamento');

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');
select throws_ok(
  $$select public.start_councilor_following((select id from refs where key = 'o3'))$$,
  null, null,
  '§3.4 cidadão comum não se apresenta como vereador');

select pg_temp.act_as('50000000-0000-0000-0000-000000000006');
insert into refs select 'following_a', public.start_councilor_following((select id from refs where key = 'o3'));
select ok(
  public.register_councilor_action((select id from refs where key = 'following_a'), 'official_letter',
    'Ofício enviado ao órgão de iluminação.', null) > 0,
  '§35 vereadora A registra ação concreta (ofício)');
select throws_ok(
  $$select public.register_institutional_action((select id from refs where key = 'o3'), 'priority', 'Vereadora tentando priorizar como gestão.', null, null, null)$$,
  '42501', null,
  '§14 vereador não registra ação oficial do Executivo');

select pg_temp.act_as('50000000-0000-0000-0000-000000000007');
insert into refs select 'following_b', public.start_councilor_following((select id from refs where key = 'o3'));
select ok((select id > 0 from refs where key = 'following_b'),
  '§35 mais de um vereador acompanha a mesma ocorrência (sem exclusividade)');

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');
select throws_ok(
  $$select public.register_institutional_action((select id from refs where key = 'o3'), 'priority', 'Cidadão tentando priorizar.', null, null, null)$$,
  '42501', null,
  '§3.2 cidadão não marca prioridade administrativa');

select pg_temp.act_as('50000000-0000-0000-0000-000000000010');
select ok(
  public.register_institutional_action((select id from refs where key = 'o3'), 'priority',
    'Prioridade reconhecida pela gestão municipal.', null, null, null) > 0,
  '§15 a gestão registra prioridade administrativa');
select is(
  (select status::text from public.occurrences where id = (select id from refs where key = 'o3')),
  'open', '§15 prioridade não altera o estado do problema');

select pg_temp.act_as('50000000-0000-0000-0000-000000000009');
select ok(
  public.register_institutional_action((select id from refs where key = 'o3'), 'scheduled',
    'Serviço programado.', null, now() + interval '2 days', null) > 0,
  '§3.3 o órgão informa programação do serviço');
select is(
  (select status::text from public.occurrences where id = (select id from refs where key = 'o3')),
  'in_progress', '§31 programação de serviço coloca a ocorrência EM_ANDAMENTO');
select ok(
  public.register_institutional_action((select id from refs where key = 'o3'), 'conclusion',
    'Órgão informa serviço concluído.', null, null, null) > 0,
  '§3.3 o órgão informa conclusão');
select is(
  (select status::text from public.occurrences where id = (select id from refs where key = 'o3')),
  'awaiting_validation', '§5.3 informar conclusão ≠ confirmar resolução');

insert into refs
select 'o3_cycle', cycle.id
from public.resolution_cycles cycle
where cycle.occurrence_id = (select id from refs where key = 'o3') and cycle.status = 'pending';

-- O servidor que abriu o ciclo em nome do órgão não valida a própria conclusão.
select throws_ok(
  $$select public.vote_resolution_cycle((select id from refs where key = 'o3_cycle'), 'confirm', -30.0701, -51.1901)$$,
  'P0001', null,
  '§40 quem informou a conclusão (órgão) não valida a própria informação');

-- Dentro da transação now() é constante: recua o acompanhamento e a ação para
-- que fiquem estritamente antes da resolução, como no uso real.
reset role;
update public.councilor_followings
set started_at = now() - interval '2 hours'
where id in ((select id from refs where key = 'following_a'), (select id from refs where key = 'following_b'));
update public.councilor_actions
set created_at = now() - interval '1 hour'
where following_id = (select id from refs where key = 'following_a');
update public.occurrence_agency_assignments
set starts_at = now() - interval '3 hours'
where occurrence_id = (select id from refs where key = 'o3');
update public.institutional_actions
set created_at = now() - interval '1 hour'
where occurrence_id = (select id from refs where key = 'o3');

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');
set local role authenticated;
select public.vote_resolution_cycle((select id from refs where key = 'o3_cycle'), 'confirm', -30.0701, -51.1901);
select pg_temp.act_as('50000000-0000-0000-0000-000000000003');
select public.vote_resolution_cycle((select id from refs where key = 'o3_cycle'), 'confirm', -30.0702, -51.1902);
select pg_temp.act_as('50000000-0000-0000-0000-000000000004');
select is(
  public.vote_resolution_cycle((select id from refs where key = 'o3_cycle'), 'confirm', -30.0703, -51.1903) ->> 'cycle_status',
  'approved', '§6.5 comunidade valida a conclusão do órgão');

reset role;
select is(
  (select followed_demands_that_reached_resolution from public.councilor_activity_metrics
   where profile_id = '50000000-0000-0000-0000-000000000006'),
  1::bigint, '§35 vereadora com ação concreta: +1 demanda acompanhada que chegou à resolução');
select is(
  (select followed_demands_that_reached_resolution from public.councilor_activity_metrics
   where profile_id = '50000000-0000-0000-0000-000000000007'),
  0::bigint, '§35 só clicar em Acompanhar não entra no indicador de resolução');
select is(
  (select followed_demands from public.councilor_activity_metrics
   where profile_id = '50000000-0000-0000-0000-000000000007'),
  1::bigint, '§13 o acompanhamento sem ação continua listado como demanda acompanhada');
select is(
  (select resolved_occurrences from public.city_occurrence_metrics where city_id = (select id from refs where key = 'city')),
  2::bigint, '§10/§25.8 dois vereadores na mesma ocorrência: cidade conta 1 resolução (total 2)');
select is(
  (select confirmed_conclusions from public.agency_occurrence_metrics where agency_id = (select id from refs where key = 'agency')),
  1::bigint, '§12 órgão: conclusão confirmada pela comunidade');
select is(
  (select prioritized_occurrences from public.administration_occurrence_metrics where administration_id = (select id from refs where key = 'administration')),
  1::bigint, '§11 gestão: ocorrência priorizada contabilizada');
select ok(
  (select status = 'resolved' from public.councilor_followings where id = (select id from refs where key = 'following_b')),
  '§9 o status do acompanhamento é separado do status da ocorrência');

select ok(
  (
    select array_agg(event_type order by id) filter (where event_type <> 'status_changed')
    from public.occurrence_events
    where occurrence_id = (select id from refs where key = 'o3')
  ) = array[
    'occurrence_created', 'agency_assigned',
    'councilor_following_started', 'councilor_official_letter', 'councilor_following_started',
    'institutional_priority', 'institutional_scheduled', 'institutional_conclusion',
    'validation_opened', 'resolution_confirmed'
  ],
  '§7 linha do tempo segue a ordem do exemplo: criação → órgão → vereadores → gestão → órgão → validação → resolução');
select ok(
  not exists (
    select 1 from public.occurrence_events
    where occurrence_id = (select id from refs where key = 'o3')
      and (actor_kind is null or event_type is null or created_at is null)
  ),
  '§7 todo evento registra ator, tipo e data/hora');

-- ---------------------------------------------------------------------------
-- §36 Fora da competência municipal
-- ---------------------------------------------------------------------------

select pg_temp.act_as('50000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into refs
select 'o4', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city'), (select id from refs where key = 'category'),
  'Fio solto da concessionária', 'Fio de energia solto pendurado no poste.',
  -30.0900, -51.1700, 'Rua Spec, 400', 'Vila Spec', false,
  pg_temp.test_photo('50000000-0000-0000-0000-000000000001'));

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');
select throws_ok(
  $$select public.set_occurrence_jurisdiction((select id from refs where key = 'o4'), 'concessionaire', 'Cia Energia', 'Cidadão tentando reclassificar.')$$,
  '42501', null,
  '§36 cidadão não reclassifica competência');

select pg_temp.act_as('50000000-0000-0000-0000-000000000010');
select lives_ok(
  $$select public.set_occurrence_jurisdiction((select id from refs where key = 'o4'), 'concessionaire', 'Cia Energia Spec', 'Rede elétrica é da concessionária.')$$,
  '§36 a gestão indica que não é competência municipal');

reset role;
select is(
  (select outside_municipal_occurrences from public.city_occurrence_metrics where city_id = (select id from refs where key = 'city')),
  1::bigint, '§36 a ocorrência é preservada e contada à parte');
select is(
  (select total_occurrences from public.city_occurrence_metrics where city_id = (select id from refs where key = 'city')),
  3::bigint, '§36 caso fora da competência não entra nos indicadores municipais');
select is(
  (select external_responsible_name from public.occurrences where id = (select id from refs where key = 'o4')),
  'Cia Energia Spec', '§36 o responsável externo conhecido é associado');

-- ---------------------------------------------------------------------------
-- §29.3 Duplicidade consolidada e §31 ENCERRADO nunca é RESOLVIDO
-- ---------------------------------------------------------------------------

select pg_temp.act_as('50000000-0000-0000-0000-000000000003');
set local role authenticated;
insert into refs
select 'o5', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city'), (select id from refs where key = 'category'),
  'Calçada quebrada Spec', 'Calçada quebrada em frente à escola.',
  -30.1100, -51.1500, 'Rua Spec, 500', 'Bairro Escola', false,
  pg_temp.test_photo('50000000-0000-0000-0000-000000000003'));

select pg_temp.act_as('50000000-0000-0000-0000-000000000004');
insert into refs
select 'o6', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city'), (select id from refs where key = 'category'),
  'Calçada da escola quebrada', 'A calçada da escola está toda quebrada.',
  -30.1101, -51.1501, 'Rua Spec, 502', 'Bairro Escola', true,
  pg_temp.test_photo('50000000-0000-0000-0000-000000000004'));

select throws_ok(
  $$select public.merge_duplicate_occurrences((select id from refs where key = 'o5'), (select id from refs where key = 'o6'), 'Cidadão tentando consolidar.')$$,
  '42501', null,
  '§29.3 cidadão não consolida duplicidades');

select pg_temp.act_as('50000000-0000-0000-0000-000000000011');
select lives_ok(
  $$select public.merge_duplicate_occurrences((select id from refs where key = 'o5'), (select id from refs where key = 'o6'), 'Mesmo problema na calçada da escola.')$$,
  '§29.3 a moderação consolida a duplicidade');

reset role;
select is(
  (select count(*) from public.posts where occurrence_id = (select id from refs where key = 'o5')),
  2::bigint, '§29.3 os relatos passam para a ocorrência principal');
select is(
  (select user_id from public.posts where occurrence_id = (select id from refs where key = 'o5') and anonymity),
  '50000000-0000-0000-0000-000000000004'::uuid, '§29.3 o relato movido mantém a autoria interna');
select ok(
  (select status = 'closed' and resolved_at is null and merged_into_occurrence_id = (select id from refs where key = 'o5')
   from public.occurrences where id = (select id from refs where key = 'o6')),
  '§31 a duplicada vira ENCERRADO, nunca RESOLVIDO');
select is(
  (select total_occurrences from public.city_occurrence_metrics where city_id = (select id from refs where key = 'city')),
  4::bigint, '§29.3 a ocorrência urbana consolidada conta uma vez nos indicadores');

-- ---------------------------------------------------------------------------
-- §37 Anonimato perante vereadores e órgãos
-- ---------------------------------------------------------------------------

select pg_temp.act_as('50000000-0000-0000-0000-000000000006');
set local role authenticated;
select is(
  (select author_id from public.post_feed_rows
   where occurrence_id = (select id from refs where key = 'o5') and is_anonymous),
  null::uuid, '§37 o vereador não vê a identidade do relato anônimo');
select pg_temp.act_as('50000000-0000-0000-0000-000000000009');
select is(
  (select author_id from public.post_feed_rows
   where occurrence_id = (select id from refs where key = 'o5') and is_anonymous),
  null::uuid, '§37 o servidor do órgão não vê a identidade do relato anônimo');

-- ---------------------------------------------------------------------------
-- §44.8 Segurança: o cliente não escreve direto em dados críticos
-- ---------------------------------------------------------------------------

select pg_temp.act_as('50000000-0000-0000-0000-000000000002');

-- Controle positivo: o helper reconhece uma escrita permitida.
select is(
  pg_temp.client_write($$update public.profiles set biography = 'Morador do bairro.' where id = auth.uid()$$),
  'changed:1', 'controle: o cliente edita a própria biografia');
select is(
  pg_temp.client_write($$update public.profiles set biography = 'invadido' where id = '50000000-0000-0000-0000-000000000003'$$),
  'denied', '§44.8 cliente não edita o perfil de outra pessoa');
select is(
  pg_temp.client_write(format(
    $$update public.occurrences set status = 'completed', resolved_at = now() where id = %s$$,
    (select id from refs where key = 'o4'))),
  'denied', '§44.8 cliente não marca ocorrência como resolvida diretamente');
select is(
  pg_temp.client_write(format(
    $$update public.occurrences set agency_id = null, administration_id = null where id = %s$$,
    (select id from refs where key = 'o4'))),
  'denied', '§44.8 cliente não altera gestão/órgão da ocorrência');
select is(
  pg_temp.client_write(format(
    $$insert into public.resolution_votes (cycle_id, voter_id, decision, latitude, longitude, distance_km)
      values (%s, auth.uid(), 'confirm', -30.05, -51.21, 0)$$,
    (select id from refs where key = 'o2_cycle_b'))),
  'denied', '§44.8 cliente não insere voto sem a RPC (sem checar raio)');
select is(
  pg_temp.client_write(format(
    $$update public.resolution_cycles set status = 'approved' where occurrence_id = %s$$,
    (select id from refs where key = 'o2'))),
  'denied', '§44.8 cliente não aprova ciclo de validação diretamente');
select is(
  pg_temp.client_write(format(
    $$update public.occurrence_events set description = 'adulterado' where occurrence_id = %s$$,
    (select id from refs where key = 'o3'))),
  'denied', '§44.8 cliente não altera a linha do tempo');
select is(
  pg_temp.client_write(format(
    $$delete from public.occurrence_events where occurrence_id = %s$$,
    (select id from refs where key = 'o3'))),
  'denied', '§44.8 cliente não apaga a linha do tempo');
select is(
  pg_temp.client_write(format(
    $$insert into public.institutional_actions (occurrence_id, actor_kind, action_type, description)
      values (%s, 'administration', 'priority', 'forjado')$$,
    (select id from refs where key = 'o4'))),
  'denied', '§44.8 cliente não registra ação institucional sem papel');
select is(
  pg_temp.client_write($$insert into public.platform_user_roles (user_id, role) values (auth.uid(), 'admin')$$),
  'denied', '§44.8 cliente não se promove a administrador');
select is(
  pg_temp.client_write(format(
    $$insert into public.agency_users (agency_id, user_id, role, is_active) values (%s, auth.uid(), 'agent', true)$$,
    (select id from refs where key = 'agency'))),
  'denied', '§44.8 cliente não se vincula a um órgão');
select is(
  pg_temp.client_write($$update public.councilor_profiles set profile_status = 'verified' where profile_id = '50000000-0000-0000-0000-000000000008'$$),
  'denied', '§44.8 cliente não altera verificação de vereador');
select is(
  pg_temp.client_write($$update public.validation_settings set confirmations_required = 1$$),
  'denied', '§44.8 cliente não altera parâmetros de validação');

reset role;
select ok(
  not has_function_privilege('anon', 'public.vote_resolution_cycle(bigint, text, double precision, double precision)', 'execute'),
  '§44.8 visitante não autenticado não vota');

-- ---------------------------------------------------------------------------
-- Cadastro: cidade obrigatória por e-mail; OAuth escolhe no primeiro acesso
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
    values ('50000000-0000-0000-0000-000000000020', 'semcidade@urbapp.test',
            '{"provider":"email","providers":["email"]}', '{"username":"spec_sem_cidade"}')$$,
  '23502', 'Selecione a sua cidade para concluir o cadastro.',
  'cadastro por e-mail sem cidade é recusado');
select throws_ok(
  $$insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
    values ('50000000-0000-0000-0000-000000000021', 'cidadefalsa@urbapp.test',
            '{"provider":"email","providers":["email"]}', '{"username":"spec_cidade_falsa","city_id":"999999999"}')$$,
  '23503', 'Cidade não encontrada.',
  'cadastro por e-mail com cidade inexistente é recusado');
select lives_ok(
  format(
    $$insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
      values ('50000000-0000-0000-0000-000000000022', 'comcidade@urbapp.test',
              '{"provider":"email","providers":["email"]}', '{"username":"spec_com_cidade","city_id":"%s"}')$$,
    (select id from refs where key = 'city')),
  'cadastro por e-mail com cidade é aceito');
select is(
  (select city_id from public.profiles where id = '50000000-0000-0000-0000-000000000022'),
  (select id from refs where key = 'city'),
  'o perfil nasce com a cidade escolhida no cadastro');
select lives_ok(
  $$insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
    values ('50000000-0000-0000-0000-000000000023', 'google@urbapp.test',
            '{"provider":"google","providers":["google"]}', '{"full_name":"Conta Google"}')$$,
  'login com Google (sem cidade) continua criando a conta');
select ok(
  (select city_id is null from public.profiles where id = '50000000-0000-0000-0000-000000000023'),
  'a conta Google fica sem cidade até a escolha no app');

select * from finish();
rollback;
