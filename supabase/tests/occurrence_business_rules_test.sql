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

select plan(84);

create temporary table test_refs (
  key text primary key,
  bigint_value bigint not null
) on commit drop;

with created as (
  insert into public.cities (name, state)
  values ('Cidade Teste UrbApp', 'mg')
  returning id
)
insert into test_refs select 'city', id from created;

with created as (
  insert into public.problem_categories (name, slug, description)
  values ('Categoria Teste UrbApp', 'categoria-teste-urbapp', 'Categoria isolada para testes.')
  returning id
)
insert into test_refs select 'category', id from created;

with created as (
  insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
  values (
    (select bigint_value from test_refs where key = 'city'),
    'Orgao Teste UrbApp',
    'generic',
    'orgao@urbapp.test',
    'verified'
  )
  returning id
)
insert into test_refs select 'agency', id from created;

-- Cidades e categorias novas recebem vínculo institucional provisório; o teste
-- encerra esse vínculo antes de cadastrar a gestão e o órgão reais.
update public.municipal_administrations
set ends_on = current_date - 31
where city_id = (select bigint_value from test_refs where key = 'city')
  and is_placeholder;

update public.agency_responsibilities
set ends_on = current_date - 31
where city_id = (select bigint_value from test_refs where key = 'city')
  and category_id = (select bigint_value from test_refs where key = 'category')
  and ends_on is null;

with created as (
  insert into public.municipal_administrations (
    city_id,
    name,
    mayor_name,
    starts_on,
    is_placeholder,
    is_verified
  )
  values (
    (select bigint_value from test_refs where key = 'city'),
    'Gestao Teste UrbApp',
    'Prefeitura Teste',
    current_date - 30,
    false,
    true
  )
  returning id
)
insert into test_refs select 'administration', id from created;

insert into public.agency_responsibilities (
  city_id,
  category_id,
  agency_id,
  starts_on,
  reason
)
values (
  (select bigint_value from test_refs where key = 'city'),
  (select bigint_value from test_refs where key = 'category'),
  (select bigint_value from test_refs where key = 'agency'),
  current_date - 30,
  'Responsabilidade criada para o teste funcional.'
);

insert into public.validation_settings (
  city_id,
  confirmations_required,
  rejections_required,
  radius_km,
  cycle_duration,
  initiator_cooldown
)
values (
  (select bigint_value from test_refs where key = 'city'),
  2,
  2,
  5,
  interval '72 hours',
  interval '24 hours'
);

insert into auth.users (id, email, raw_user_meta_data)
select
  seed.id,
  seed.email,
  jsonb_build_object(
    'username', seed.username,
    'full_name', seed.full_name,
    'city_id', (select bigint_value::text from test_refs where key = 'city')
  )
from (
  values
    ('00000000-0000-0000-0000-000000000001'::uuid, 'autor1@urbapp.test', 'autor1_teste', 'Autor Um'),
    ('00000000-0000-0000-0000-000000000002'::uuid, 'autor2@urbapp.test', 'autor2_teste', 'Autor Dois'),
    ('00000000-0000-0000-0000-000000000003'::uuid, 'votante1@urbapp.test', 'votante1_teste', 'Votante Um'),
    ('00000000-0000-0000-0000-000000000004'::uuid, 'votante2@urbapp.test', 'votante2_teste', 'Votante Dois'),
    ('00000000-0000-0000-0000-000000000005'::uuid, 'agente@urbapp.test', 'agente_teste', 'Agente Publico'),
    ('00000000-0000-0000-0000-000000000006'::uuid, 'denunciante@urbapp.test', 'denunciante_teste', 'Denunciante'),
    ('00000000-0000-0000-0000-000000000007'::uuid, 'moderador@urbapp.test', 'moderador_teste', 'Moderador')
) as seed(id, email, username, full_name);

with created as (
  insert into public.councilor_profiles (
    profile_id,
    city_id,
    public_name,
    party,
    mandate_starts_on,
    mandate_ends_on,
    profile_status,
    verified_at
  )
  values (
    '00000000-0000-0000-0000-000000000006',
    (select bigint_value from test_refs where key = 'city'),
    'Vereador Teste',
    'TST',
    current_date - 30,
    current_date + 365,
    'verified',
    now()
  )
  returning id
)
insert into test_refs select 'councilor', id from created;

select is(
  (select count(*) from cron.job where jobname = 'urbapp-expire-resolution-cycles'),
  1::bigint,
  'a expiração automática dos ciclos possui agendamento ativo'
);

with created as (
  insert into public.occurrences (
    city_id,
    administration_id,
    created_administration_id,
    category_id,
    agency_id,
    title,
    summary,
    latitude,
    longitude
  )
  values (
    (select bigint_value from test_refs where key = 'city'),
    (select bigint_value from test_refs where key = 'administration'),
    (select bigint_value from test_refs where key = 'administration'),
    (select bigint_value from test_refs where key = 'category'),
    (select bigint_value from test_refs where key = 'agency'),
    'Ocorrência para expiração automática',
    'Cenário isolado de teste do prazo de validação.',
    -19.9180,
    -43.9370
  )
  returning id
)
insert into test_refs select 'expiration_occurrence', id from created;

-- Evidências referenciadas precisam existir no Storage.
insert into storage.objects (bucket_id, name, owner)
values (
  'post-images',
  format('occurrences/%s/resolution/resolution-evidence.jpg',
         (select bigint_value from test_refs where key = 'expiration_occurrence')),
  '00000000-0000-0000-0000-000000000003'
);

set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000003';
select throws_ok(
  $$select public.open_resolution_cycle_with_evidence(
    (select bigint_value from test_refs where key = 'expiration_occurrence'),
    'Tentativa com evidência de caminho arbitrário.',
    'citizen',
    'outro-usuario/imagem.jpg'
  )$$,
  'P0001',
  'Caminho de evidência inválido para esta ocorrência.',
  'a API rejeita evidência arbitrária ou de outra ocorrência'
);
with created as (
  select public.open_resolution_cycle_with_evidence(
    (select bigint_value from test_refs where key = 'expiration_occurrence'),
    'Possível resolução usada para testar o vencimento.',
    'citizen',
    format(
      'occurrences/%s/resolution/resolution-evidence.jpg',
      (select bigint_value from test_refs where key = 'expiration_occurrence')
    )
  ) as id
)
insert into test_refs select 'expiration_cycle', id from created;

select is(
  (
    select evidence_storage_path
    from public.resolution_cycles
    where id = (select bigint_value from test_refs where key = 'expiration_cycle')
  ),
  format(
    'occurrences/%s/resolution/resolution-evidence.jpg',
    (select bigint_value from test_refs where key = 'expiration_occurrence')
  ),
  'a possível resolução pode preservar evidência atualizada'
);

reset role;
update public.resolution_cycles
set opened_at = now() - interval '2 minutes',
    expires_at = now() - interval '1 minute'
where id = (select bigint_value from test_refs where key = 'expiration_cycle');
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000004';
select is(
  public.expire_resolution_cycles((select bigint_value from test_refs where key = 'expiration_occurrence')),
  1,
  'um ciclo vencido é expirado sem depender da interface'
);
select is(
  (select status from public.occurrences where id = (select bigint_value from test_refs where key = 'expiration_occurrence')),
  'open'::public.report_status,
  'a expiração sem quórum restaura o estado operacional anterior'
);
select is(
  (
    select count(*)
    from public.occurrence_events
    where occurrence_id = (select bigint_value from test_refs where key = 'expiration_occurrence')
      and event_type = 'validation_expired'
  ),
  1::bigint,
  'a expiração automática permanece na linha do tempo auditável'
);
reset role;
delete from public.occurrences
where id = (select bigint_value from test_refs where key = 'expiration_occurrence');

set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';

with created as (
  select *
  from public.publish_occurrence_report(
    (select bigint_value from test_refs where key = 'city'),
    (select bigint_value from test_refs where key = 'category'),
    'Buraco perigoso na via',
    'Buraco profundo próximo à faixa de pedestres.',
    -19.9191,
    -43.9386,
    'Rua do Teste, 100',
    'Centro',
    false,
    pg_temp.test_photo('00000000-0000-0000-0000-000000000001')
  )
)
insert into test_refs
select 'occurrence', occurrence_id from created
union all
select 'first_post', post_id from created;

-- Nova ocorrência exige foto e descrição de verdade (publicação com foto).
select is(
  (select count(*) from public.post_images
   where post_id = (select bigint_value from test_refs where key = 'first_post')),
  1::bigint,
  'a foto enviada fica vinculada ao primeiro relato'
);
select throws_ok(
  format($$select public.publish_occurrence_report(%s, %s, 'Sem foto', 'Descrição com tamanho suficiente.', -19.9, -43.9, null, null, false, array[]::text[])$$,
    (select bigint_value from test_refs where key = 'city'), (select bigint_value from test_refs where key = 'category')),
  'P0001', 'Adicione pelo menos uma foto do problema.',
  'publicar sem foto é recusado'
);
select throws_ok(
  format($$select public.publish_occurrence_report(%s, %s, 'Descrição curta', 'curta', -19.9, -43.9, null, null, false, pg_temp.test_photo('00000000-0000-0000-0000-000000000001'))$$,
    (select bigint_value from test_refs where key = 'city'), (select bigint_value from test_refs where key = 'category')),
  'P0001', 'A descrição deve ter pelo menos 10 caracteres.',
  'descrição curta demais é recusada'
);
select throws_ok(
  format($$select public.publish_occurrence_report(%s, %s, 'Foto falsa', 'Descrição com tamanho suficiente.', -19.9, -43.9, null, null, false, array['reports/pending/nao-existe/1.jpg'])$$,
    (select bigint_value from test_refs where key = 'city'), (select bigint_value from test_refs where key = 'category')),
  'P0001', 'Não encontramos a foto enviada. Adicione-a novamente.',
  'caminho de foto que não foi enviado é recusado'
);
select throws_ok(
  format($$select public.publish_occurrence_report(%s, %s, 'Caminho fora da pasta', 'Descrição com tamanho suficiente.', -19.9, -43.9, null, null, false, array['reports/1/evidencia-1.jpg'])$$,
    (select bigint_value from test_refs where key = 'city'), (select bigint_value from test_refs where key = 'category')),
  'P0001', 'Caminho de foto inválido.',
  'foto fora da pasta de pendentes é recusada'
);
select throws_ok(
  format($$select public.publish_occurrence_report(%s, %s, 'Foto de outra pessoa', 'Descrição com tamanho suficiente.', -19.9, -43.9, null, null, false, pg_temp.test_photo('00000000-0000-0000-0000-000000000099'))$$,
    (select bigint_value from test_refs where key = 'city'), (select bigint_value from test_refs where key = 'category')),
  'P0001', 'Não encontramos a foto enviada. Adicione-a novamente.',
  'a foto precisa ter sido enviada pelo próprio autor'
);
select is(
  (select count(*) from public.occurrences where title in ('Sem foto', 'Descrição curta', 'Foto falsa', 'Caminho fora da pasta', 'Foto de outra pessoa')),
  0::bigint,
  'publicações recusadas não deixam ocorrência criada'
);

select ok(
  (select bigint_value > 0 from test_refs where key = 'occurrence'),
  'a primeira denúncia cria uma ocorrência'
);
select ok(
  (select bigint_value > 0 from test_refs where key = 'first_post'),
  'a primeira denúncia cria seu relato'
);
select is(
  (select administration_id from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  (select bigint_value from test_refs where key = 'administration'),
  'a ocorrência é vinculada à gestão vigente'
);
select is(
  (select agency_id from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  (select bigint_value from test_refs where key = 'agency'),
  'a categoria encaminha automaticamente ao órgão responsável'
);
select is(
  (select current_points from public.profiles where id = '00000000-0000-0000-0000-000000000001'),
  50::bigint,
  'uma contribuição válida concede 50 pontos'
);
select is(
  (
    select occurrence_id
    from public.find_potential_duplicate_occurrences(
      (select bigint_value from test_refs where key = 'city'),
      (select bigint_value from test_refs where key = 'category'),
      -19.9191,
      -43.9386,
      'Buraco perigoso',
      1
    )
    limit 1
  ),
  (select bigint_value from test_refs where key = 'occurrence'),
  'a busca de duplicidade encontra a ocorrência próxima'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000002';
with created as (
  select public.add_report_to_occurrence(
    (select bigint_value from test_refs where key = 'occurrence'),
    'Mesmo buraco, novo relato',
    'O problema continua e aumentou desde ontem.',
    true
  ) as id
)
insert into test_refs select 'second_post', id from created;

select ok(
  (select bigint_value > 0 from test_refs where key = 'second_post'),
  'outro cidadão adiciona um relato à mesma ocorrência'
);
select is(
  (select count(*) from public.posts where occurrence_id = (select bigint_value from test_refs where key = 'occurrence')),
  2::bigint,
  'relatos semelhantes permanecem agrupados sem duplicar a ocorrência'
);
select is(
  (select current_points from public.profiles where id = '00000000-0000-0000-0000-000000000002'),
  50::bigint,
  'o segundo autor também recebe pontos pela contribuição'
);
insert into public.post_images (post_id, storage_path, position)
values
  (
    (select bigint_value from test_refs where key = 'second_post'),
    '00000000-0000-0000-0000-000000000002/posts/legacy.jpg',
    1
  ),
  (
    (select bigint_value from test_refs where key = 'second_post'),
    'reports/anonymous/safe.jpg',
    2
  );
select is(
  (select image_count from public.post_feed_rows where id = (select bigint_value from test_refs where key = 'second_post')),
  2,
  'o autor continua vendo todas as imagens do próprio relato anônimo'
);
select is(
  (select author_id from public.post_feed_rows where id = (select bigint_value from test_refs where key = 'second_post')),
  '00000000-0000-0000-0000-000000000002'::uuid,
  'o autor mantém acesso interno à própria autoria anônima'
);
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000003';
select is(
  (select author_id from public.post_feed_rows where id = (select bigint_value from test_refs where key = 'second_post')),
  null::uuid,
  'outros usuários não recebem a identidade de um relato anônimo'
);
select is(
  (select image_count from public.post_feed_rows where id = (select bigint_value from test_refs where key = 'second_post')),
  1,
  'a API pública oculta mídia anônima legada cujo caminho revela o autor'
);
select is(
  (select primary_image_path from public.post_feed_rows where id = (select bigint_value from test_refs where key = 'second_post')),
  'reports/anonymous/safe.jpg',
  'mídia anônima no novo padrão continua disponível sem expor identificador'
);
select ok(
  not has_column_privilege('authenticated', 'public.posts', 'user_id', 'select'),
  'a API autenticada não pode consultar diretamente a coluna de autoria'
);
select ok(
  not has_column_privilege('authenticated', 'public.occurrence_events', 'actor_id', 'select'),
  'a linha do tempo pública não expõe UUIDs internos de cidadãos'
);
select ok(
  not has_column_privilege('authenticated', 'public.institutional_actions', 'created_by', 'select'),
  'ações oficiais públicas identificam o órgão, não a conta pessoal do servidor'
);
select ok(
  (select changed_by is null from public.post_status_history where post_id = (select bigint_value from test_refs where key = 'second_post') order by id limit 1),
  'o histórico público também preserva a autoria anônima'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000006';
with created as (
  select public.start_councilor_following(
    (select bigint_value from test_refs where key = 'occurrence')
  ) as id
)
insert into test_refs select 'councilor_following', id from created;

select ok(
  (select bigint_value > 0 from test_refs where key = 'councilor_following'),
  'um vereador verificado inicia acompanhamento independente'
);
select is(
  (select status from public.councilor_followings where id = (select bigint_value from test_refs where key = 'councilor_following')),
  'started',
  'o acompanhamento começa com estado próprio'
);
select ok(
  public.register_councilor_action(
    (select bigint_value from test_refs where key = 'councilor_following'),
    'request',
    'Solicitação formal enviada ao órgão responsável.',
    null
  ) > 0,
  'o vereador registra uma solicitação pública'
);
select is(
  (select status from public.councilor_followings where id = (select bigint_value from test_refs where key = 'councilor_following')),
  'awaiting_response',
  'uma solicitação coloca o acompanhamento aguardando retorno'
);
select ok(
  public.register_councilor_action(
    (select bigint_value from test_refs where key = 'councilor_following'),
    'response_received',
    'O órgão respondeu à solicitação registrada.',
    null
  ) > 0,
  'o vereador registra o retorno recebido'
);
select is(
  (select status from public.councilor_followings where id = (select bigint_value from test_refs where key = 'councilor_following')),
  'action_registered',
  'o retorno recebido encerra o estado de espera'
);
select is(
  (
    select count(distinct notification.user_id)
    from public.notifications notification
    where notification.type = 'occurrence_event'
      and notification.user_id in (
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000002'
      )
  ),
  2::bigint,
  'ações públicas notificam todos os autores, inclusive o autor anônimo internamente'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000005';
select throws_ok(
  $$select public.open_resolution_cycle((select bigint_value from test_refs where key = 'occurrence'), 'Conclusão falsa', 'agency')$$,
  '42501',
  'Usuário não está autorizado a atuar com esse papel.',
  'um usuário comum não pode se apresentar como órgão público'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';
with created as (
  select public.open_resolution_cycle(
    (select bigint_value from test_refs where key = 'occurrence'),
    'O reparo foi visto no local.',
    'citizen'
  ) as id
)
insert into test_refs select 'first_cycle', id from created;

select ok(
  (select bigint_value > 0 from test_refs where key = 'first_cycle'),
  'um cidadão pode abrir validação comunitária'
);
select is(
  (select status from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  'awaiting_validation'::public.report_status,
  'a ocorrência aguarda validação sem ser encerrada antecipadamente'
);
select is(
  (select confirmations_required from public.resolution_cycles where id = (select bigint_value from test_refs where key = 'first_cycle')),
  2,
  'o ciclo registra o quórum vigente como snapshot'
);
select is(
  (select radius_km from public.resolution_cycles where id = (select bigint_value from test_refs where key = 'first_cycle')),
  5::numeric,
  'o ciclo registra o raio vigente como snapshot'
);

update public.validation_settings
set confirmations_required = 5,
    radius_km = 10
where city_id = (select bigint_value from test_refs where key = 'city');

select is(
  (select confirmations_required from public.resolution_cycles where id = (select bigint_value from test_refs where key = 'first_cycle')),
  2,
  'alterações futuras de regra não mudam um ciclo em andamento'
);
select throws_ok(
  $$select public.vote_resolution_cycle((select bigint_value from test_refs where key = 'first_cycle'), 'confirm', -19.9191, -43.9386)$$,
  'P0001',
  'Quem iniciou o ciclo não pode votar nele.',
  'quem abriu a validação não pode votar'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000003';
select throws_ok(
  $$select public.vote_resolution_cycle((select bigint_value from test_refs where key = 'first_cycle'), 'confirm', -20.50, -44.50)$$,
  'P0001',
  'Usuário fora do raio permitido para validação.',
  'um voto fora do raio é rejeitado'
);
select is(
  public.vote_resolution_cycle(
    (select bigint_value from test_refs where key = 'first_cycle'),
    'confirm',
    -19.9190,
    -43.9385
  ) ->> 'cycle_status',
  'pending',
  'um voto abaixo do quórum mantém o ciclo aberto'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000004';
select is(
  public.vote_resolution_cycle(
    (select bigint_value from test_refs where key = 'first_cycle'),
    'confirm',
    -19.9192,
    -43.9387
  ) ->> 'cycle_status',
  'approved',
  'o quórum comunitário aprova a resolução'
);
select is(
  (select status from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  'completed'::public.report_status,
  'somente a aprovação comunitária marca a ocorrência como resolvida'
);
select is(
  (select count(*) from public.posts where occurrence_id = (select bigint_value from test_refs where key = 'occurrence') and status = 'completed'),
  2::bigint,
  'a resolução é refletida em todos os relatos agrupados'
);
select ok(
  (select resolved_at is not null from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  'uma ocorrência resolvida recebe data de resolução'
);
select is(
  (select count(*) from public.profiles where id in ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002') and current_points = 150),
  2::bigint,
  'cada autor recebe os 100 pontos adicionais pela resolução relacionada'
);
select is(
  (select status from public.councilor_followings where id = (select bigint_value from test_refs where key = 'councilor_following')),
  'resolved',
  'a resolução é refletida separadamente no acompanhamento do vereador'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000006';
select throws_ok(
  $$select public.start_councilor_following((select bigint_value from test_refs where key = 'occurrence'))$$,
  'P0001',
  'Não é possível iniciar acompanhamento em ocorrência finalizada.',
  'não se inicia novo acompanhamento em ocorrência finalizada'
);

reset role;
insert into storage.objects (bucket_id, name, owner)
values (
  'post-images',
  format('occurrences/%s/reopening/teste.jpg', (select bigint_value from test_refs where key = 'occurrence')),
  '00000000-0000-0000-0000-000000000002'
);
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000002';
select public.reopen_occurrence(
  (select bigint_value from test_refs where key = 'occurrence'),
  'O asfalto cedeu novamente.',
  format(
    'occurrences/%s/reopening/teste.jpg',
    (select bigint_value from test_refs where key = 'occurrence')
  )
);
select is(
  (select status from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  'reopened'::public.report_status,
  'nova evidência reabre uma ocorrência resolvida'
);
select is(
  (select count(*) from public.posts where occurrence_id = (select bigint_value from test_refs where key = 'occurrence') and status = 'reopened'),
  2::bigint,
  'a reabertura é refletida em todos os relatos'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000006';
select is(
  public.start_councilor_following((select bigint_value from test_refs where key = 'occurrence')),
  (select bigint_value from test_refs where key = 'councilor_following'),
  'o vereador pode retomar acompanhamento após reabertura'
);
select lives_ok(
  $$select public.end_councilor_following(
    (select bigint_value from test_refs where key = 'councilor_following'),
    'Acompanhamento encerrado com registro público.'
  )$$,
  'o vereador pode encerrar voluntariamente o acompanhamento'
);
select is(
  (select status from public.councilor_followings where id = (select bigint_value from test_refs where key = 'councilor_following')),
  'ended',
  'o encerramento possui estado e data próprios'
);

reset role;
insert into public.agency_users (agency_id, user_id, role, is_active)
values (
  (select bigint_value from test_refs where key = 'agency'),
  '00000000-0000-0000-0000-000000000005',
  'agent',
  true
);
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000005';

select ok(
  public.register_institutional_action(
    (select bigint_value from test_refs where key = 'occurrence'),
    'analysis',
    'Equipe técnica iniciou nova análise.',
    null,
    null,
    null
  ) > 0,
  'um agente autorizado registra ação institucional'
);
select is(
  (select status from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  'in_analysis'::public.report_status,
  'a ação institucional atualiza o estado operacional'
);
select ok(
  public.register_institutional_action(
    (select bigint_value from test_refs where key = 'occurrence'),
    'conclusion',
    'O órgão concluiu o reparo e solicita validação.',
    null,
    null,
    null
  ) > 0,
  'a conclusão oficial abre validação sem se autodeclarar resolvida'
);

with selected as (
  select id
  from public.resolution_cycles
  where occurrence_id = (select bigint_value from test_refs where key = 'occurrence')
    and status = 'pending'
  order by id desc
  limit 1
)
insert into test_refs select 'second_cycle', id from selected;

select is(
  (select initiator_kind from public.resolution_cycles where id = (select bigint_value from test_refs where key = 'second_cycle')),
  'agency',
  'a validação aberta pelo órgão preserva a autoria institucional'
);
select is(
  (select assigned_occurrences from public.agency_occurrence_metrics where agency_id = (select bigint_value from test_refs where key = 'agency')),
  1::bigint,
  'o indicador do órgão contabiliza a ocorrência uma única vez'
);
select is(
  (select official_actions from public.agency_occurrence_metrics where agency_id = (select bigint_value from test_refs where key = 'agency')),
  2::bigint,
  'o indicador do órgão separa ações oficiais registradas'
);
select is(
  (select registered_during_period from public.administration_occurrence_metrics where administration_id = (select bigint_value from test_refs where key = 'administration')),
  1::bigint,
  'o indicador da gestão contabiliza ocorrências do próprio período'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000003';
select is(
  public.vote_resolution_cycle(
    (select bigint_value from test_refs where key = 'second_cycle'),
    'reject',
    -19.9190,
    -43.9385
  ) ->> 'cycle_status',
  'pending',
  'uma rejeição abaixo do quórum mantém a validação aberta'
);
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000004';
select is(
  public.vote_resolution_cycle(
    (select bigint_value from test_refs where key = 'second_cycle'),
    'reject',
    -19.9192,
    -43.9387
  ) ->> 'cycle_status',
  'rejected',
  'o quórum de rejeição informa que o problema continua'
);
select is(
  (select status from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  'in_analysis'::public.report_status,
  'a rejeição restaura o estado operacional anterior'
);

set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000006';
with created as (
  insert into public.moderation_reports (reporter_user_id, target_type, target_id, reason)
  values (
    '00000000-0000-0000-0000-000000000006',
    'post',
    (select bigint_value from test_refs where key = 'first_post'),
    'Conteúdo inválido criado para o teste.'
  )
  returning id
)
insert into test_refs select 'moderation_report', id from created;

select is(
  (select occurrence_id from public.moderation_reports where id = (select bigint_value from test_refs where key = 'moderation_report')),
  (select bigint_value from test_refs where key = 'occurrence'),
  'a denúncia de conteúdo é ligada automaticamente à ocorrência'
);
select is(
  (select status from public.moderation_reports where id = (select bigint_value from test_refs where key = 'moderation_report')),
  'pending',
  'a denúncia entra na fila pendente'
);
select throws_ok(
  $$select public.start_moderation_review((select bigint_value from test_refs where key = 'moderation_report'))$$,
  '42501',
  'Apenas a moderação pode analisar denúncias.',
  'um cidadão não pode assumir uma análise de moderação'
);

with created as (
  select (
    public.create_institutional_profile_request(
      (select bigint_value from test_refs where key = 'city'),
      'Prefeitura da Cidade Teste',
      'Prefeitura Municipal',
      'gestao@urbapp.test',
      'Servidor público',
      'Vínculo funcional comprovado para o teste.',
      'https://example.test/comprovacao',
      'administration'
    )
  ).id as id
)
insert into test_refs select 'administration_request', id from created;

select is(
  (select request_kind from public.agency_profile_requests where id = (select bigint_value from test_refs where key = 'administration_request')),
  'administration',
  'um usuário pode solicitar verificação para a gestão municipal'
);

reset role;
insert into public.platform_user_roles (user_id, role)
values ('00000000-0000-0000-0000-000000000007', 'moderator');
set local "request.jwt.claim.role" = 'authenticated';
set local "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000007';

select is(
  public.review_agency_profile_request(
    (select bigint_value from test_refs where key = 'administration_request'),
    'approved',
    'Vínculo confirmado no teste.'
  ),
  (select bigint_value from test_refs where key = 'administration'),
  'a moderação aprova acesso à gestão vigente'
);
select is(
  (
    select count(*)
    from public.administration_users
    where administration_id = (select bigint_value from test_refs where key = 'administration')
      and user_id = '00000000-0000-0000-0000-000000000006'
      and is_active = true
  ),
  1::bigint,
  'a aprovação cria a associação institucional ativa'
);

with created as (
  select public.rollover_municipal_administration(
    (select bigint_value from test_refs where key = 'city'),
    'Nova Gestão Teste',
    'Prefeita Teste',
    current_date,
    current_date + 1460
  ) as id
)
insert into test_refs select 'new_administration', id from created;

select is(
  (select administration_id from public.occurrences where id = (select bigint_value from test_refs where key = 'occurrence')),
  (select bigint_value from test_refs where key = 'new_administration'),
  'a mudança de gestão transfere ocorrências ativas como herdadas'
);
select is(
  (
    select count(*)
    from public.occurrence_events
    where occurrence_id = (select bigint_value from test_refs where key = 'occurrence')
      and event_type = 'administration_changed'
  ),
  1::bigint,
  'a mudança de gestão permanece registrada na linha do tempo'
);

select public.start_moderation_review((select bigint_value from test_refs where key = 'moderation_report'));
select is(
  (select status from public.moderation_reports where id = (select bigint_value from test_refs where key = 'moderation_report')),
  'in_analysis',
  'a moderação registra o início da análise'
);
select public.review_moderation_report(
  (select bigint_value from test_refs where key = 'moderation_report'),
  'upheld',
  'A ocorrência inteira é inválida no cenário de teste.',
  true
);
select is(
  (select status from public.moderation_reports where id = (select bigint_value from test_refs where key = 'moderation_report')),
  'upheld',
  'a decisão de moderação fica auditável'
);
select ok(
  (
    select status = 'closed'
      and invalidated_at is not null
      and resolved_at is null
    from public.occurrences
    where id = (select bigint_value from test_refs where key = 'occurrence')
  ),
  'conteúdo invalidado é encerrado sem ser contado como resolvido'
);
select is(
  (select count(*) from public.posts where occurrence_id = (select bigint_value from test_refs where key = 'occurrence') and hidden_at is not null),
  2::bigint,
  'a invalidação integral oculta todos os relatos associados'
);
select is(
  (select count(*) from public.profiles where id in ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002') and current_points = 0),
  2::bigint,
  'a moderação reverte os pontos concedidos pelo conteúdo inválido'
);
select is(
  (select total_occurrences from public.city_occurrence_metrics where city_id = (select bigint_value from test_refs where key = 'city')),
  0::bigint,
  'indicadores públicos excluem ocorrências invalidadas'
);
select ok(
  (
    select count(*) >= 2
    from public.occurrence_events
    where occurrence_id = (select bigint_value from test_refs where key = 'occurrence')
      and event_type in ('resolution_confirmed', 'occurrence_invalidated')
  ),
  'resolução e invalidação permanecem no histórico auditável'
);

select * from finish();
rollback;
