-- Regras da camada social, privilégios de cliente e indicadores.
-- Diferente da suíte original, as verificações de permissão rodam com o papel
-- real da API (`authenticated` / `anon`), não como superusuário.
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

select plan(44);

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

-- ---------------------------------------------------------------------------
-- Fixtures (superusuário)
-- ---------------------------------------------------------------------------

with created as (
  insert into public.cities (name, state) values ('Cidade Social UrbApp', 'sp') returning id
)
insert into refs select 'city', id from created;

select ok(
  exists (select 1 from public.municipal_administrations where city_id = (select id from refs where key = 'city')),
  'uma cidade nova recebe gestão municipal provisória automaticamente'
);

with created as (
  insert into public.problem_categories (name, slug, requires_resolution_evidence)
  values ('Categoria Social UrbApp', 'categoria-social-urbapp', false)
  returning id
)
insert into refs select 'category', id from created;

with created as (
  insert into public.problem_categories (name, slug, requires_resolution_evidence)
  values ('Categoria Com Evidencia', 'categoria-com-evidencia', true)
  returning id
)
insert into refs select 'evidence_category', id from created;

select ok(
  exists (
    select 1 from public.agency_responsibilities
    where city_id = (select id from refs where key = 'city')
      and category_id = (select id from refs where key = 'category')
      and ends_on is null
  ),
  'uma categoria nova recebe órgão responsável em todas as cidades'
);

with created as (
  insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
  values ((select id from refs where key = 'city'), 'Orgao Social A', 'secretaria', 'a@urbapp.test', 'verified')
  returning id
)
insert into refs select 'agency_a', id from created;

with created as (
  insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
  values ((select id from refs where key = 'city'), 'Orgao Social B', 'secretaria', 'b@urbapp.test', 'participant')
  returning id
)
insert into refs select 'agency_b', id from created;

update public.agency_responsibilities
set agency_id = (select id from refs where key = 'agency_a')
where city_id = (select id from refs where key = 'city') and ends_on is null;

insert into public.validation_settings (city_id, confirmations_required, rejections_required, radius_km)
values ((select id from refs where key = 'city'), 2, 2, 5);

insert into auth.users (id, email, raw_user_meta_data)
select seed.id, seed.email,
       jsonb_build_object('username', seed.username, 'full_name', seed.full_name,
                          'city_id', (select id::text from refs where key = 'city'))
from (values
  ('10000000-0000-0000-0000-000000000001'::uuid, 's1@urbapp.test', 'social_um', 'Social Um'),
  ('10000000-0000-0000-0000-000000000002'::uuid, 's2@urbapp.test', 'social_dois', 'Social Dois'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 's3@urbapp.test', 'social_tres', 'Social Tres'),
  ('10000000-0000-0000-0000-000000000004'::uuid, 's4@urbapp.test', 'social_quatro', 'Social Quatro'),
  ('10000000-0000-0000-0000-000000000005'::uuid, 's5@urbapp.test', 'social_gestao', 'Social Gestao')
) as seed(id, email, username, full_name);

insert into public.administration_users (administration_id, user_id, role, is_active)
select administration.id, '10000000-0000-0000-0000-000000000005', 'manager', true
from public.municipal_administrations administration
where administration.city_id = (select id from refs where key = 'city');

insert into public.agency_users (agency_id, user_id, role, is_active)
values ((select id from refs where key = 'agency_b'), '10000000-0000-0000-0000-000000000004', 'agent', true);

-- ---------------------------------------------------------------------------
-- Privilégios de escrita do cliente
-- ---------------------------------------------------------------------------

select pg_temp.act_as('10000000-0000-0000-0000-000000000001');
set local role authenticated;

select throws_ok(
  $$insert into public.posts (user_id, city_id, category_id, title, description, latitude, longitude, status)
    values (auth.uid(), (select id from refs where key = 'city'), (select id from refs where key = 'category'),
            'Relato direto', 'Tentativa sem RPC', -23.5, -46.6, 'completed')$$,
  '42501',
  null,
  'relatos não podem ser inseridos diretamente (status e contadores forjáveis)'
);
select throws_ok(
  $$insert into public.problem_categories (name, slug) values ('Invasora', 'invasora')$$,
  '42501',
  null,
  'categorias não podem ser criadas pelo cliente'
);
select throws_ok(
  $$update public.profiles set current_points = 99999 where id = auth.uid()$$,
  '42501',
  null,
  'pontos não podem ser alterados pelo cliente'
);
select throws_ok(
  $$insert into public.post_status_history (post_id, to_status) values (1, 'completed')$$,
  '42501',
  null,
  'o histórico de status não pode ser forjado'
);
select ok(
  not has_column_privilege('authenticated', 'public.post_status_history', 'changed_by', 'select'),
  'o histórico público não expõe o autor de cada mudança'
);
select ok(
  not has_column_privilege('authenticated', 'public.resolution_cycles', 'initiated_by', 'select'),
  'o ciclo público não expõe quem informou a possível resolução'
);
select ok(
  to_regprocedure('public.vote_post_resolution(bigint, boolean, double precision, double precision)') is null
    and to_regprocedure('public.request_post_resolution(bigint, text)') is null,
  'a validação legada por relato foi removida'
);

reset role;
select is(
  (select count(*) from cron.job where jobname = 'urbapp-expiracao-diaria'),
  0::bigint,
  'a expiração automática de relatos sem movimento não está mais agendada'
);

-- ---------------------------------------------------------------------------
-- Ocorrência única com vários relatos, apoios e comentários
-- ---------------------------------------------------------------------------

select pg_temp.act_as('10000000-0000-0000-0000-000000000001');
set local role authenticated;

insert into refs
select 'occurrence', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city'),
  (select id from refs where key = 'category'),
  'Lâmpada queimada na praça',
  'A praça está sem iluminação há dias.',
  -23.5000, -46.6000, 'Rua das Flores', 'Centro', false,
  pg_temp.test_photo((select current_setting('request.jwt.claim.sub')::uuid))
);

select is(
  (select count(*) from public.occurrence_events
   where occurrence_id = (select id from refs where key = 'occurrence') and event_type = 'report_added'),
  0::bigint,
  'o relato inicial não gera evento duplicado de "novo relato"'
);

select throws_ok(
  $$insert into public.occurrence_supports (occurrence_id, user_id)
    values ((select id from refs where key = 'occurrence'), auth.uid())$$,
  '42501',
  null,
  'quem relatou não apoia a própria ocorrência'
);

select pg_temp.act_as('10000000-0000-0000-0000-000000000002');
select lives_ok(
  $$select public.add_report_to_occurrence((select id from refs where key = 'occurrence'),
     'Mesma lâmpada', 'Confirmo que continua apagada.', true)$$,
  'outro cidadão adiciona relato anônimo à mesma ocorrência'
);
select lives_ok(
  $$select public.add_report_to_occurrence((select id from refs where key = 'occurrence'),
     'Mais um relato', 'Também passei e vi.', true)$$,
  'o mesmo cidadão pode complementar com outro relato'
);
select is(
  (select current_points from public.profiles where id = auth.uid()),
  50::bigint,
  'a recompensa por contribuição vale uma vez por ocorrência'
);

select pg_temp.act_as('10000000-0000-0000-0000-000000000003');
select lives_ok(
  $$insert into public.occurrence_supports (occurrence_id, user_id)
    values ((select id from refs where key = 'occurrence'), auth.uid())$$,
  'um cidadão apoia a ocorrência de outra pessoa'
);
select throws_ok(
  $$insert into public.occurrence_supports (occurrence_id, user_id)
    values ((select id from refs where key = 'occurrence'), auth.uid())$$,
  '23505',
  null,
  'cada cidadão apoia uma ocorrência uma única vez'
);

with created as (
  insert into public.comments (occurrence_id, body, user_id)
  values ((select id from refs where key = 'occurrence'), 'Passei hoje e continua escuro.', auth.uid())
  returning id
)
insert into refs select 'comment', id from created;

select pg_temp.act_as('10000000-0000-0000-0000-000000000004');
with created as (
  insert into public.comments (occurrence_id, body, parent_comment_id, user_id)
  values ((select id from refs where key = 'occurrence'), 'Confirmo.', (select id from refs where key = 'comment'), auth.uid())
  returning id
)
insert into refs select 'reply', id from created;

with created as (
  insert into public.comments (occurrence_id, body, parent_comment_id, user_id)
  values ((select id from refs where key = 'occurrence'), 'Eu também.', (select id from refs where key = 'reply'), auth.uid())
  returning id
)
insert into refs select 'reply_of_reply', id from created;

select is(
  (select parent_comment_id from public.comments where id = (select id from refs where key = 'reply_of_reply')),
  (select id from refs where key = 'comment'),
  'respostas ficam em um único nível na conversa da ocorrência'
);
select throws_ok(
  $$update public.comments set occurrence_id = 1 where id = (select id from refs where key = 'reply')$$,
  '42501',
  null,
  'o comentário não pode ser movido para outra ocorrência'
);

select is(
  (select reports_count from public.occurrence_feed_rows where id = (select id from refs where key = 'occurrence')),
  3,
  'o feed agrupa os relatos na mesma ocorrência'
);
select is(
  (select count(*) from public.occurrence_feed_rows where id = (select id from refs where key = 'occurrence')),
  1::bigint,
  'a ocorrência aparece uma única vez no feed, independentemente do número de relatos'
);
select is(
  (select supports_count from public.occurrence_feed_rows where id = (select id from refs where key = 'occurrence')),
  1,
  'apoios são contados na ocorrência'
);
select is(
  (select comments_count from public.occurrence_feed_rows where id = (select id from refs where key = 'occurrence')),
  3,
  'comentários pertencem à ocorrência como um todo'
);
select is(
  (select current_points from public.profiles where id = '10000000-0000-0000-0000-000000000001'),
  75::bigint,
  'quem iniciou recebe pontos por apoio (15) e por comentário recebido de cada pessoa (5)'
);
select ok(
  exists (
    select 1 from public.search_occurrences('lâmpada praça', (select id from refs where key = 'city'))
    where id = (select id from refs where key = 'occurrence')
  ),
  'a busca no servidor encontra a ocorrência por texto'
);
select ok(
  exists (
    select 1 from public.get_trending_occurrences((select id from refs where key = 'city'))
    where id = (select id from refs where key = 'occurrence')
  ),
  'ocorrências mobilizando a comunidade aparecem em "Em alta"'
);
select is(
  (select author_display_name from public.post_feed_rows
   where occurrence_id = (select id from refs where key = 'occurrence') and is_anonymous limit 1),
  'Anônimo',
  'relatos anônimos permanecem anônimos para os demais cidadãos'
);

-- Moderação de comentário
reset role;
select pg_temp.act_as('10000000-0000-0000-0000-000000000003');
set local role authenticated;
select lives_ok(
  $$insert into public.moderation_reports (reporter_user_id, target_type, target_id, reason)
    values (auth.uid(), 'comment', (select id from refs where key = 'reply'), 'Comentário ofensivo no teste.')$$,
  'cidadãos podem denunciar comentários'
);

-- ---------------------------------------------------------------------------
-- Ações institucionais e indicadores
-- ---------------------------------------------------------------------------

select pg_temp.act_as('10000000-0000-0000-0000-000000000005');
select lives_ok(
  $$select public.register_institutional_action((select id from refs where key = 'occurrence'),
     'forwarding', 'Encaminhada ao órgão B.', (select id from refs where key = 'agency_b'), null, null)$$,
  'a gestão reencaminha a ocorrência ao órgão competente'
);

select pg_temp.act_as('10000000-0000-0000-0000-000000000004');
select lives_ok(
  $$select public.register_institutional_action((select id from refs where key = 'occurrence'),
     'received', 'Recebimento confirmado pela equipe.', null, null, null)$$,
  'o órgão confirma recebimento'
);
select is(
  (select status from public.occurrence_feed_rows where id = (select id from refs where key = 'occurrence')),
  'in_analysis'::public.report_status,
  'confirmar recebimento coloca a ocorrência em análise'
);
select ok(
  exists (
    select 1 from public.occurrence_events
    where occurrence_id = (select id from refs where key = 'occurrence')
      and event_type = 'status_changed'
      and metadata ->> 'to' = 'in_analysis'
  ),
  'toda transição de status fica registrada com origem e destino'
);
select is(
  (select assigned_occurrences from public.agency_occurrence_metrics where agency_id = (select id from refs where key = 'agency_a')),
  1::bigint,
  'o órgão anterior mantém a ocorrência no histórico de responsabilidade'
);
select is(
  (select in_progress_occurrences from public.agency_occurrence_metrics where agency_id = (select id from refs where key = 'agency_a')),
  0::bigint,
  'estados correntes não são creditados ao órgão anterior'
);
select is(
  (select in_progress_occurrences from public.agency_occurrence_metrics where agency_id = (select id from refs where key = 'agency_b')),
  1::bigint,
  'estados correntes pertencem ao órgão responsável atual'
);

select lives_ok(
  $$select public.register_institutional_action((select id from refs where key = 'occurrence'),
     'conclusion', 'Lâmpada substituída.', null, null, null)$$,
  'o órgão informa conclusão'
);
select is(
  (select status from public.occurrences where id = (select id from refs where key = 'occurrence')),
  'awaiting_validation'::public.report_status,
  'a conclusão institucional abre validação comunitária e não resolve sozinha'
);
select lives_ok(
  $$select public.register_institutional_action((select id from refs where key = 'occurrence'),
     'conclusion', 'Reforço da conclusão informada.', null, null, null)$$,
  'uma conclusão repetida durante o ciclo é registrada sem abrir outro ciclo'
);

select pg_temp.act_as('10000000-0000-0000-0000-000000000003');
select is(
  public.get_resolution_context((select id from refs where key = 'occurrence')) -> 'cycle' ->> 'my_vote',
  null,
  'o contexto de validação informa que o usuário ainda não votou'
);
select is(
  public.vote_resolution_cycle(
    (select (public.get_resolution_context((select id from refs where key = 'occurrence')) -> 'cycle' ->> 'id')::bigint),
    'confirm', -23.5001, -46.6001
  ) ->> 'cycle_status',
  'pending',
  'o voto é contabilizado pelo backend'
);
select is(
  public.get_resolution_context((select id from refs where key = 'occurrence')) -> 'cycle' ->> 'my_vote',
  'confirm',
  'o contexto de validação mostra o voto já registrado'
);

-- ---------------------------------------------------------------------------
-- Evidência por categoria e preferências de notificação
-- ---------------------------------------------------------------------------

select pg_temp.act_as('10000000-0000-0000-0000-000000000001');
insert into refs
select 'evidence_occurrence', occurrence_id
from public.publish_occurrence_report(
  (select id from refs where key = 'city'),
  (select id from refs where key = 'evidence_category'),
  'Árvore caída', 'Árvore bloqueando a calçada.', -23.51, -46.61, null, null, false,
  pg_temp.test_photo('10000000-0000-0000-0000-000000000001')
);

select pg_temp.act_as('10000000-0000-0000-0000-000000000003');
select throws_ok(
  $$select public.open_resolution_cycle_with_evidence((select id from refs where key = 'evidence_occurrence'),
     'Já retiraram a árvore.', 'citizen', null)$$,
  'P0001',
  'Esta categoria exige uma foto recente para informar a resolução.',
  'categorias de risco podem exigir foto para informar resolução'
);

select pg_temp.act_as('10000000-0000-0000-0000-000000000001');
insert into public.notification_preferences (user_id, validations) values (auth.uid(), false);

reset role;
delete from public.notifications where user_id = '10000000-0000-0000-0000-000000000001';
insert into storage.objects (bucket_id, name, owner)
values ('post-images',
        format('occurrences/%s/resolution/foto.jpg', (select id from refs where key = 'evidence_occurrence')),
        '10000000-0000-0000-0000-000000000003');

select pg_temp.act_as('10000000-0000-0000-0000-000000000003');
set local role authenticated;
select lives_ok(
  $$select public.open_resolution_cycle_with_evidence((select id from refs where key = 'evidence_occurrence'),
     'Já retiraram a árvore.', 'citizen',
     format('occurrences/%s/resolution/foto.jpg', (select id from refs where key = 'evidence_occurrence')))$$,
  'com foto enviada, a possível resolução é aceita'
);

reset role;
select is(
  (select count(*) from public.notifications
   where user_id = '10000000-0000-0000-0000-000000000001' and payload ->> 'event_type' = 'validation_opened'),
  0::bigint,
  'preferências de alerta do usuário são respeitadas pelo backend'
);

select * from finish();
rollback;
