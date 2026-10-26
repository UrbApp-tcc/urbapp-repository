-- Verificação institucional pela administração (spec §3.5, §19 e §40):
-- fila com dados completos, motivo obrigatório na rejeição, bloqueio de
-- autoaprovação, notificação do solicitante e histórico de decisões.
-- As chamadas rodam com o papel real da API (`authenticated` / `anon`).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

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

select plan(38);

create temporary table refs (key text primary key, id bigint not null) on commit drop;
grant select, insert on refs to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures (superusuário)
-- ---------------------------------------------------------------------------

with created as (
  insert into public.cities (name, state) values ('Cidade Verificacao UrbApp', 'pr') returning id
)
insert into refs select 'city', id from created;

insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
values ((select id from refs where key = 'city'), 'Secretaria Existente Verif', 'Secretaria', 'existente@verif.test', 'unclaimed');

insert into auth.users (id, email, raw_user_meta_data)
select seed.id, seed.email,
       jsonb_build_object('username', seed.username, 'full_name', seed.full_name,
                          'city_id', (select id::text from refs where key = 'city'))
from (values
  ('60000000-0000-0000-0000-000000000001'::uuid, 'orgao@verif.test', 'verif_orgao', 'Servidora do Órgão'),
  ('60000000-0000-0000-0000-000000000002'::uuid, 'vereador@verif.test', 'verif_vereador', 'Vereador Pedinte'),
  ('60000000-0000-0000-0000-000000000003'::uuid, 'gestao@verif.test', 'verif_gestao', 'Servidor da Gestão'),
  ('60000000-0000-0000-0000-000000000004'::uuid, 'admin@verif.test', 'verif_admin', 'Admin Verificador'),
  ('60000000-0000-0000-0000-000000000005'::uuid, 'moderador@verif.test', 'verif_moderador', 'Moderadora Verif'),
  ('60000000-0000-0000-0000-000000000006'::uuid, 'cidadao@verif.test', 'verif_cidadao', 'Cidadão Curioso')
) as seed(id, email, username, full_name);

insert into public.platform_user_roles (user_id, role)
values
  ('60000000-0000-0000-0000-000000000004', 'admin'),
  ('60000000-0000-0000-0000-000000000005', 'moderator');

-- Pedido anterior já rejeitado da servidora do órgão (histórico do solicitante).
insert into public.agency_profile_requests (
  requester_user_id, city_id, agency_name, agency_type, request_kind, institutional_email,
  proof_summary, status, review_notes, reviewed_at, reviewed_by, created_at
)
values (
  '60000000-0000-0000-0000-000000000001', (select id from refs where key = 'city'),
  'Pedido Antigo Verif', 'Secretaria', 'agency', 'antigo@gmail.com',
  'Sem comprovação.', 'rejected', 'Sem comprovação do vínculo.', now() - interval '3 days',
  '60000000-0000-0000-0000-000000000004', now() - interval '4 days'
);

-- ---------------------------------------------------------------------------
-- Pedidos enviados pelo app
-- ---------------------------------------------------------------------------

select pg_temp.act_as('60000000-0000-0000-0000-000000000001');
set local role authenticated;
insert into refs
select 'agency_request', (public.create_institutional_profile_request(
  (select id from refs where key = 'city'), 'Secretaria Existente Verif', 'Secretaria',
  'servidora@cidadeverif.pr.gov.br', 'Coordenadora',
  'Portaria de nomeação publicada no Diário Oficial.',
  'https://diario.cidadeverif.pr.gov.br/portaria-123', 'agency'
)).id;

select pg_temp.act_as('60000000-0000-0000-0000-000000000003');
insert into refs
select 'administration_request', (public.create_institutional_profile_request(
  (select id from refs where key = 'city'), 'Prefeitura Verif', 'Prefeitura Municipal',
  'gabinete@cidadeverif.pr.gov.br', 'Chefe de gabinete',
  'Termo de posse e e-mail funcional.', null, 'administration'
)).id;

select pg_temp.act_as('60000000-0000-0000-0000-000000000002');
with created as (
  insert into public.councilor_profile_requests (
    requester_user_id, city_id, public_name, party, mandate_starts_on, mandate_ends_on,
    institutional_email, proof_summary, proof_links
  )
  values (
    auth.uid(), (select id from refs where key = 'city'), 'Vereador Pedinte', 'PEX',
    date '2025-01-01', date '2028-12-31', 'vereador@camaraverif.pr.gov.br',
    'Diploma emitido pelo TRE.', 'https://tre.jus.br/diploma'
  )
  returning id
)
insert into refs select 'councilor_request', id from created;

-- O próprio administrador também pede um perfil (para testar a autoaprovação).
select pg_temp.act_as('60000000-0000-0000-0000-000000000004');
insert into refs
select 'admin_own_request', (public.create_institutional_profile_request(
  (select id from refs where key = 'city'), 'Secretaria do Admin Verif', 'Secretaria',
  'admin@cidadeverif.pr.gov.br', 'Secretário', 'Nomeação publicada no Diário Oficial.', null, 'agency'
)).id;

-- ---------------------------------------------------------------------------
-- Acesso à fila
-- ---------------------------------------------------------------------------

reset role;
-- Dentro da transação now() é constante: espaça os envios como no uso real.
update public.agency_profile_requests set created_at = now() - interval '4 hours'
where id = (select id from refs where key = 'agency_request');
update public.agency_profile_requests set created_at = now() - interval '3 hours'
where id = (select id from refs where key = 'administration_request');
update public.councilor_profile_requests set created_at = now() - interval '2 hours'
where id = (select id from refs where key = 'councilor_request');
update public.agency_profile_requests set created_at = now() - interval '1 hour'
where id = (select id from refs where key = 'admin_own_request');

select ok(
  not has_function_privilege('anon', 'public.get_institutional_verification_requests(text, integer, integer)', 'execute'),
  'visitante sem login não consulta a fila de verificação');
select ok(
  not has_function_privilege('authenticated', 'public.notify_institutional_review(text, bigint, uuid, text, text, text, text)', 'execute'),
  'a notificação da decisão não pode ser disparada pelo cliente');

select pg_temp.act_as('60000000-0000-0000-0000-000000000006');
set local role authenticated;
select throws_ok(
  $$select * from public.get_institutional_verification_requests('pending')$$,
  '42501', 'Apenas administradores podem consultar verificações institucionais.',
  'cidadão comum não consulta a fila de verificação');
select is(
  (select count(*) from public.agency_profile_requests where city_id = (select id from refs where key = 'city')),
  0::bigint, 'cidadão comum não lê pedidos de outras pessoas');

select pg_temp.act_as('60000000-0000-0000-0000-000000000004');
select throws_ok(
  $$select * from public.get_institutional_verification_requests('todos')$$,
  'P0001', 'Filtro de verificação inválido.',
  'filtro desconhecido é recusado');

select is(
  (select count(*) from public.get_institutional_verification_requests('pending')
   where city_id = (select id from refs where key = 'city')),
  4::bigint, 'a fila reúne pedidos de órgão, gestão e vereador');
select is(
  (select array_agg(queue.request_type order by queue.position)
   from (
     select request_type, city_id, row_number() over () as position
     from public.get_institutional_verification_requests('pending')
   ) queue
   where queue.city_id = (select id from refs where key = 'city')),
  array['agency', 'administration', 'councilor', 'agency'],
  'pendentes aparecem em ordem de chegada');

select is(
  (select requester_username || ' | ' || requester_account_email || ' | ' || requester_name
   from public.get_institutional_verification_requests('pending')
   where request_type = 'agency' and request_id = (select id from refs where key = 'agency_request')),
  'verif_orgao | orgao@verif.test | Servidora do Órgão',
  'o admin vê quem pediu: nome, @usuário e e-mail da conta');
select is(
  (select proof_links || ' | ' || requester_role || ' | ' || agency_type
   from public.get_institutional_verification_requests('pending')
   where request_type = 'agency' and request_id = (select id from refs where key = 'agency_request')),
  'https://diario.cidadeverif.pr.gov.br/portaria-123 | Coordenadora | Secretaria',
  'o admin vê links de comprovação, cargo e tipo do órgão');
select is(
  (select previous_requests::text || '/' || previous_rejections::text
   from public.get_institutional_verification_requests('pending')
   where request_type = 'agency' and request_id = (select id from refs where key = 'agency_request')),
  '1/1', 'pedidos anteriores e rejeições do solicitante são informados');
select is(
  (select existing_profile_status from public.get_institutional_verification_requests('pending')
   where request_type = 'agency' and request_id = (select id from refs where key = 'agency_request')),
  'unclaimed', 'o admin vê que o órgão já existe e não foi reivindicado');
select is(
  (select existing_profile_status from public.get_institutional_verification_requests('pending')
   where request_type = 'agency' and request_id = (select id from refs where key = 'admin_own_request')),
  null, 'órgão novo não tem situação prévia');
select is(
  (select party || ' | ' || mandate_starts_on::text || ' | ' || mandate_ends_on::text
   from public.get_institutional_verification_requests('pending')
   where request_type = 'councilor' and request_id = (select id from refs where key = 'councilor_request')),
  'PEX | 2025-01-01 | 2028-12-31', 'pedido de vereador mostra partido e mandato');
select is(
  (select existing_profile_status from public.get_institutional_verification_requests('pending')
   where request_type = 'administration' and request_id = (select id from refs where key = 'administration_request')),
  'unclaimed', 'primeiro acesso à gestão vigente é identificado');

-- ---------------------------------------------------------------------------
-- Regras da decisão
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.review_agency_profile_request((select id from refs where key = 'admin_own_request'), 'approved', null)$$,
  '42501', 'Você não pode revisar a sua própria solicitação.',
  'o administrador não aprova o próprio pedido');
select throws_ok(
  $$select public.review_agency_profile_request((select id from refs where key = 'admin_own_request'), 'rejected', 'Desisti do pedido feito.')$$,
  '42501', 'Você não pode revisar a sua própria solicitação.',
  'o administrador também não rejeita o próprio pedido');
select throws_ok(
  $$select public.review_councilor_profile_request((select id from refs where key = 'councilor_request'), 'rejected', null)$$,
  'P0001', 'Informe o motivo da rejeição (pelo menos 10 caracteres).',
  'rejeitar sem motivo é recusado');
select throws_ok(
  $$select public.review_councilor_profile_request((select id from refs where key = 'councilor_request'), 'rejected', '  curto  ')$$,
  'P0001', 'Informe o motivo da rejeição (pelo menos 10 caracteres).',
  'motivo curto demais é recusado');

select pg_temp.act_as('60000000-0000-0000-0000-000000000006');
select throws_ok(
  $$select public.review_councilor_profile_request((select id from refs where key = 'councilor_request'), 'approved', null)$$,
  '42501', null,
  'cidadão comum não aprova pedidos');

-- ---------------------------------------------------------------------------
-- Rejeição: motivo registrado e enviado ao solicitante
-- ---------------------------------------------------------------------------

select pg_temp.act_as('60000000-0000-0000-0000-000000000004');
select lives_ok(
  $$select public.review_councilor_profile_request((select id from refs where key = 'councilor_request'), 'rejected', 'Diploma ilegível; envie uma cópia legível.')$$,
  'rejeitar com motivo é aceito');

reset role;
select ok(
  (select status = 'rejected' and review_notes = 'Diploma ilegível; envie uma cópia legível.'
          and reviewed_by = '60000000-0000-0000-0000-000000000004' and reviewed_at is not null
   from public.councilor_profile_requests where id = (select id from refs where key = 'councilor_request')),
  'a rejeição registra motivo, quem decidiu e quando');
select ok(
  not exists (select 1 from public.councilor_profiles where profile_id = '60000000-0000-0000-0000-000000000002'),
  'pedido rejeitado não cria perfil de vereador');
select is(
  (select title from public.notifications
   where user_id = '60000000-0000-0000-0000-000000000002' and type = 'institutional_review'),
  'Solicitação institucional não aprovada', 'o solicitante é notificado da rejeição');
select ok(
  (select body like '%Motivo: Diploma ilegível; envie uma cópia legível.'
          and payload ->> 'decision' = 'rejected'
          and payload ->> 'review_notes' = 'Diploma ilegível; envie uma cópia legível.'
          and (payload ->> 'request_id')::bigint = (select id from refs where key = 'councilor_request')
   from public.notifications
   where user_id = '60000000-0000-0000-0000-000000000002' and type = 'institutional_review'),
  'a notificação traz o motivo e identifica o pedido');

-- ---------------------------------------------------------------------------
-- Aprovação: acesso liberado e solicitante avisado
-- ---------------------------------------------------------------------------

select pg_temp.act_as('60000000-0000-0000-0000-000000000004');
set local role authenticated;
insert into refs
select 'approved_agency', public.review_agency_profile_request((select id from refs where key = 'agency_request'), 'approved', null);

reset role;
select ok(
  (select profile_status = 'participant' and verified_at is not null
   from public.public_agencies where id = (select id from refs where key = 'approved_agency')),
  'a aprovação reivindica o perfil existente do órgão');
select is(
  (select count(*) from public.public_agencies
   where city_id = (select id from refs where key = 'city') and name = 'Secretaria Existente Verif'),
  1::bigint, 'a aprovação não duplica o órgão');
select ok(
  exists (select 1 from public.agency_users
          where agency_id = (select id from refs where key = 'approved_agency')
            and user_id = '60000000-0000-0000-0000-000000000001' and is_active),
  'a servidora passa a atuar pelo órgão');
select ok(
  (select title = 'Perfil institucional aprovado' and payload ->> 'decision' = 'approved'
   from public.notifications
   where user_id = '60000000-0000-0000-0000-000000000001' and type = 'institutional_review'),
  'o solicitante é notificado da aprovação');

select pg_temp.act_as('60000000-0000-0000-0000-000000000004');
set local role authenticated;
select lives_ok(
  $$select public.review_agency_profile_request((select id from refs where key = 'administration_request'), 'approved', 'Vínculo confirmado por telefone.')$$,
  'a aprovação do acesso à gestão é aceita');
reset role;
select ok(
  exists (select 1 from public.administration_users member
          join public.municipal_administrations administration on administration.id = member.administration_id
          where administration.city_id = (select id from refs where key = 'city')
            and member.user_id = '60000000-0000-0000-0000-000000000003' and member.is_active),
  'o servidor passa a atuar pela gestão vigente');

select pg_temp.act_as('60000000-0000-0000-0000-000000000004');
set local role authenticated;
select throws_ok(
  $$select public.review_agency_profile_request((select id from refs where key = 'agency_request'), 'rejected', 'Mudei de ideia sobre o pedido.')$$,
  'P0001', 'Solicitação pendente não encontrada.',
  'um pedido já decidido não é revisado de novo');

-- Outro administrador pode decidir o pedido do colega.
select pg_temp.act_as('60000000-0000-0000-0000-000000000005');
select lives_ok(
  $$select public.review_agency_profile_request((select id from refs where key = 'admin_own_request'), 'approved', null)$$,
  'outro administrador decide o pedido do colega');

-- ---------------------------------------------------------------------------
-- Histórico
-- ---------------------------------------------------------------------------

select pg_temp.act_as('60000000-0000-0000-0000-000000000004');
select is(
  (select count(*) from public.get_institutional_verification_requests('pending')
   where city_id = (select id from refs where key = 'city')),
  0::bigint, 'pedidos decididos saem da fila de pendentes');
select is(
  (select count(*) from public.get_institutional_verification_requests('reviewed')
   where city_id = (select id from refs where key = 'city')),
  5::bigint, 'o histórico reúne aprovações e rejeições, inclusive antigas');
select is(
  (select reviewer_name || ' | ' || review_notes
   from public.get_institutional_verification_requests('reviewed')
   where request_type = 'councilor' and request_id = (select id from refs where key = 'councilor_request')),
  'Admin Verificador | Diploma ilegível; envie uma cópia legível.',
  'o histórico mostra quem decidiu e o motivo');
select is(
  (select reviewer_name from public.get_institutional_verification_requests('reviewed')
   where request_type = 'agency' and request_id = (select id from refs where key = 'admin_own_request')),
  'Moderadora Verif', 'o histórico registra o revisor de cada decisão');

reset role;
select is(
  (select count(*) from public.notifications
   where type = 'institutional_review'
     and user_id in ('60000000-0000-0000-0000-000000000005', '60000000-0000-0000-0000-000000000006')),
  0::bigint, 'só o solicitante recebe a notificação da decisão');

select pg_temp.act_as('60000000-0000-0000-0000-000000000002');
set local role authenticated;
select is(
  (select review_notes from public.councilor_profile_requests
   where id = (select id from refs where key = 'councilor_request')),
  'Diploma ilegível; envie uma cópia legível.',
  'o solicitante lê o motivo no próprio pedido');

select * from finish();
rollback;
