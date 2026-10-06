-- Dados de demonstração para desenvolvimento LOCAL (`supabase db reset`).
-- Não é aplicado em produção. Senha de todas as contas de teste: urbapp123
--
-- Contas:
--   cidadao@urbapp.test     Gabriel Alves (cidadão)
--   mariana@urbapp.test     Mariana Lopes (cidadã)
--   rafael@urbapp.test      Rafael Nunes (cidadão)
--   camila@urbapp.test      Camila Souza (cidadã)
--   vereadora@urbapp.test   Ana Souza (vereadora verificada)
--   saae@urbapp.test        Servidor do SAAE Sorocaba (órgão participante)
--   prefeitura@urbapp.test  Gestão municipal de Sorocaba
--   admin@urbapp.test       Administração do UrbApp

do $$
declare
  sorocaba bigint;
  administration bigint;
  saae bigint;
  obras bigint;
  servicos bigint;
  iluminacao bigint;
  occ_alagamento bigint;
  occ_buraco bigint;
  occ_poste bigint;
  occ_residuos bigint;
  occ_arvore bigint;
  occ_calcada bigint;
  occ_semaforo bigint;
  following bigint;
  cycle bigint;
  comment_id bigint;
  post bigint;
  cat_saneamento bigint := (select id from public.problem_categories where slug = 'sanitation');
  cat_obras bigint := (select id from public.problem_categories where slug = 'public-maintenance');
  cat_iluminacao bigint := (select id from public.problem_categories where slug = 'public-lighting');
  cat_limpeza bigint := (select id from public.problem_categories where slug = 'urban-cleaning');
  cat_arvores bigint := (select id from public.problem_categories where slug = 'urban-trees');
  cat_acessibilidade bigint := (select id from public.problem_categories where slug = 'accessibility');
  cat_transito bigint := (select id from public.problem_categories where slug = 'traffic');
  u_gabriel uuid := '20000000-0000-0000-0000-000000000001';
  u_mariana uuid := '20000000-0000-0000-0000-000000000002';
  u_rafael uuid := '20000000-0000-0000-0000-000000000003';
  u_camila uuid := '20000000-0000-0000-0000-000000000004';
  u_ana uuid := '20000000-0000-0000-0000-000000000005';
  u_saae uuid := '20000000-0000-0000-0000-000000000006';
  u_prefeitura uuid := '20000000-0000-0000-0000-000000000007';
  u_admin uuid := '20000000-0000-0000-0000-000000000008';
begin
  insert into public.cities (name, state) values ('Sorocaba', 'sp')
  on conflict do nothing;
  select id into sorocaba from public.cities where name = 'Sorocaba' and state = 'sp';

  -- Gestão vigente com período definido (a provisória fica no histórico).
  update public.municipal_administrations
  set ends_on = date '2024-12-31'
  where city_id = sorocaba and is_placeholder and ends_on is null;

  insert into public.municipal_administrations (city_id, name, mayor_name, starts_on, ends_on, is_verified)
  values (sorocaba, 'Gestão 2025–2028', 'Paulo H. Vieira', date '2025-01-01', date '2028-12-31', true)
  returning id into administration;

  insert into public.public_agencies (city_id, name, type, contact_email, profile_status, verified_at, claimed_at)
  values (sorocaba, 'SAAE Sorocaba', 'autarquia', 'saae@sorocaba.test', 'participant', now(), now())
  returning id into saae;
  insert into public.public_agencies (city_id, name, type, contact_email, profile_status, verified_at)
  values (sorocaba, 'Secretaria de Obras', 'secretaria', 'obras@sorocaba.test', 'verified', now())
  returning id into obras;
  insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
  values (sorocaba, 'Secretaria de Serviços Públicos', 'secretaria', 'servicos@sorocaba.test', 'unclaimed')
  returning id into servicos;
  insert into public.public_agencies (city_id, name, type, contact_email, profile_status)
  values (sorocaba, 'Iluminação Pública', 'departamento', 'iluminacao@sorocaba.test', 'unclaimed')
  returning id into iluminacao;

  update public.agency_responsibilities set agency_id = saae
  where city_id = sorocaba and category_id = cat_saneamento and ends_on is null;
  update public.agency_responsibilities set agency_id = obras
  where city_id = sorocaba and category_id in (cat_obras, cat_acessibilidade, cat_transito) and ends_on is null;
  update public.agency_responsibilities set agency_id = servicos
  where city_id = sorocaba and category_id in (cat_limpeza, cat_arvores) and ends_on is null;
  update public.agency_responsibilities set agency_id = iluminacao
  where city_id = sorocaba and category_id = cat_iluminacao and ends_on is null;

  -- Contas de teste.
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  )
  select
    '00000000-0000-0000-0000-000000000000', seed.id, 'authenticated', 'authenticated', seed.email,
    extensions.crypt('urbapp123', extensions.gen_salt('bf')), now(), '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('username', seed.username, 'full_name', seed.full_name, 'city_id', sorocaba::text),
    now() - interval '200 days', now()
  from (values
    (u_gabriel, 'cidadao@urbapp.test', 'gabriel.alves', 'Gabriel Alves'),
    (u_mariana, 'mariana@urbapp.test', 'mariana.lopes', 'Mariana Lopes'),
    (u_rafael, 'rafael@urbapp.test', 'rafael.nunes', 'Rafael Nunes'),
    (u_camila, 'camila@urbapp.test', 'camila.souza', 'Camila Souza'),
    (u_ana, 'vereadora@urbapp.test', 'ana.souza', 'Ana Souza'),
    (u_saae, 'saae@urbapp.test', 'saae.sorocaba', 'Equipe SAAE'),
    (u_prefeitura, 'prefeitura@urbapp.test', 'prefeitura.sorocaba', 'Gestão Sorocaba'),
    (u_admin, 'admin@urbapp.test', 'admin.urbapp', 'Administração UrbApp')
  ) as seed(id, email, username, full_name);

  insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  select gen_random_uuid(), users.id::text, users.id,
         jsonb_build_object('sub', users.id::text, 'email', users.email, 'email_verified', true),
         'email', now(), now(), now()
  from auth.users users
  where users.email like '%@urbapp.test';

  update public.profiles set biography = 'Morador do Jardim Santa Rosália.' where id = u_gabriel;

  insert into public.platform_user_roles (user_id, role) values (u_admin, 'admin');
  insert into public.agency_users (agency_id, user_id, role, is_active) values (saae, u_saae, 'agent', true);
  insert into public.administration_users (administration_id, user_id, role, is_active)
  values (administration, u_prefeitura, 'manager', true);
  insert into public.councilor_profiles (profile_id, city_id, public_name, party, mandate_starts_on, mandate_ends_on, profile_status, verified_at)
  values (u_ana, sorocaba, 'Ana Souza', 'PSD', date '2025-01-01', date '2028-12-31', 'verified', now());

  -- Ocorrências criadas pelas operações de negócio, como no app.
  perform set_config('request.jwt.claim.sub', u_mariana::text, true);
  select occurrence_id into occ_alagamento from public.create_occurrence_report(
    sorocaba, cat_saneamento, 'Alagamento recorrente na Av. Dom Aguirre',
    'Moradores relatam alagamentos recorrentes neste trecho da avenida durante chuvas fortes. A água invade a faixa da direita e dificulta a passagem de veículos e pedestres.',
    -23.4952, -47.4510, 'Av. Dom Aguirre', 'Jardim Santa Rosália', false);

  perform set_config('request.jwt.claim.sub', u_gabriel::text, true);
  select occurrence_id into occ_buraco from public.create_occurrence_report(
    sorocaba, cat_obras, 'Buraco aumenta após as chuvas',
    'O buraco aumentou depois das últimas chuvas e ocupa parte da faixa, oferecendo risco principalmente à noite.',
    -23.5072, -47.4601, 'Rua Aparecida', 'Jardim Europa', false);

  perform set_config('request.jwt.claim.sub', u_camila::text, true);
  select occurrence_id into occ_poste from public.create_occurrence_report(
    sorocaba, cat_iluminacao, 'Poste apagado na praça',
    'O poste ao lado da praça está apagado há vários dias e deixa o ponto de ônibus sem iluminação.',
    -23.4990, -47.4470, 'Praça Frei Baraúna', 'Vila Carvalho', false);

  perform set_config('request.jwt.claim.sub', u_rafael::text, true);
  select occurrence_id into occ_residuos from public.create_occurrence_report(
    sorocaba, cat_limpeza, 'Descarte irregular na calçada',
    'Há acúmulo recorrente de resíduos na calçada, bloqueando a passagem e atraindo animais.',
    -23.5010, -47.4580, 'Rua XV de Novembro', 'Centro', true);

  perform set_config('request.jwt.claim.sub', u_mariana::text, true);
  select occurrence_id into occ_arvore from public.create_occurrence_report(
    sorocaba, cat_arvores, 'Árvore com galhos sobre a fiação',
    'Galhos grandes encostando na rede elétrica em frente à escola municipal.',
    -23.5100, -47.4450, 'Rua Coronel Nogueira Padilha', 'Vila Hortência', false);

  perform set_config('request.jwt.claim.sub', u_camila::text, true);
  select occurrence_id into occ_calcada from public.create_occurrence_report(
    sorocaba, cat_acessibilidade, 'Calçada quebrada impede passagem de cadeirantes',
    'Trecho de calçada com placas soltas e degrau alto próximo à UBS.',
    -23.4925, -47.4620, 'Av. Itavuvu', 'Vila Santana', false);

  perform set_config('request.jwt.claim.sub', u_gabriel::text, true);
  select occurrence_id into occ_semaforo from public.create_occurrence_report(
    sorocaba, cat_transito, 'Semáforo intermitente no cruzamento',
    'O semáforo fica piscando amarelo nos horários de pico, causando risco de acidentes.',
    -23.5040, -47.4500, 'Av. General Osório', 'Centro', false);

  -- Novos relatos na mesma ocorrência (sem duplicar a ocorrência).
  perform set_config('request.jwt.claim.sub', u_rafael::text, true);
  perform public.add_report_to_occurrence(occ_alagamento, null, 'O alagamento também dificulta o acesso ao ponto de ônibus.', true);
  perform set_config('request.jwt.claim.sub', u_camila::text, true);
  perform public.add_report_to_occurrence(occ_alagamento, null, 'Nova evidência registrada depois da chuva desta manhã.', false);
  perform set_config('request.jwt.claim.sub', u_rafael::text, true);
  perform public.add_report_to_occurrence(occ_buraco, null, 'Passei hoje cedo e a água acumulada esconde o buraco.', false);

  -- Apoios e comentários na ocorrência.
  insert into public.occurrence_supports (occurrence_id, user_id) values
    (occ_alagamento, u_gabriel), (occ_alagamento, u_ana), (occ_alagamento, u_prefeitura), (occ_alagamento, u_admin),
    (occ_buraco, u_mariana), (occ_buraco, u_camila), (occ_poste, u_gabriel), (occ_poste, u_mariana),
    (occ_semaforo, u_mariana), (occ_calcada, u_rafael), (occ_arvore, u_rafael);

  perform set_config('request.jwt.claim.sub', u_mariana::text, true);
  insert into public.comments (occurrence_id, body, user_id)
  values (occ_alagamento, 'Passei por aqui hoje cedo e a água ainda estava cobrindo parte da faixa.', u_mariana)
  returning id into comment_id;
  perform set_config('request.jwt.claim.sub', u_rafael::text, true);
  insert into public.comments (occurrence_id, body, parent_comment_id, user_id)
  values (occ_alagamento, 'Passei às 10h e continuava igual.', comment_id, u_rafael);
  insert into public.comments (occurrence_id, body, user_id)
  values (occ_alagamento, 'O problema acontece sempre que a chuva fica mais forte. Precisamos acompanhar a obra.', u_rafael);
  perform set_config('request.jwt.claim.sub', u_gabriel::text, true);
  insert into public.comments (occurrence_id, body, user_id)
  values (occ_buraco, 'Já vi dois motociclistas desviando de última hora.', u_gabriel);

  -- Atuação institucional e parlamentar.
  perform set_config('request.jwt.claim.sub', u_prefeitura::text, true);
  perform public.register_institutional_action(occ_alagamento, 'priority', 'Prioridade reconhecida pela gestão municipal pelo risco aos pedestres.');
  perform public.register_institutional_action(occ_alagamento, 'request', 'Providência solicitada ao SAAE para drenagem do trecho.');

  perform set_config('request.jwt.claim.sub', u_saae::text, true);
  perform public.register_institutional_action(occ_alagamento, 'received', 'Recebimento confirmado pela equipe de drenagem.');
  perform public.register_institutional_action(occ_alagamento, 'scheduled', 'Serviço incluído na programação operacional.');
  perform public.register_institutional_action(occ_alagamento, 'in_progress', 'Serviço de drenagem em execução no local.');

  perform set_config('request.jwt.claim.sub', u_ana::text, true);
  following := public.start_councilor_following(occ_alagamento);
  perform public.register_councilor_action(following, 'charge', 'Cobrança registrada junto ao SAAE sobre o prazo da obra.');
  following := public.start_councilor_following(occ_buraco);
  perform public.register_councilor_action(following, 'official_letter', 'Ofício encaminhado à Secretaria de Obras.');

  -- Validação em andamento: Gabriel pode validar o poste (está perto).
  perform set_config('request.jwt.claim.sub', u_rafael::text, true);
  cycle := public.open_resolution_cycle(occ_poste, 'Passei pela praça e o poste voltou a funcionar.', 'citizen');
  perform set_config('request.jwt.claim.sub', u_mariana::text, true);
  perform public.vote_resolution_cycle(cycle, 'confirm', -23.4991, -47.4471);

  -- Resolução confirmada pela comunidade.
  perform set_config('request.jwt.claim.sub', u_camila::text, true);
  cycle := public.open_resolution_cycle(occ_residuos, 'A calçada foi limpa e recebeu lixeiras novas.', 'citizen');
  perform set_config('request.jwt.claim.sub', u_mariana::text, true);
  perform public.vote_resolution_cycle(cycle, 'confirm', -23.5011, -47.4581);
  perform set_config('request.jwt.claim.sub', u_ana::text, true);
  perform public.vote_resolution_cycle(cycle, 'confirm', -23.5012, -47.4579);
  perform set_config('request.jwt.claim.sub', u_saae::text, true);
  perform public.vote_resolution_cycle(cycle, 'confirm', -23.5009, -47.4582);

  -- Imagens dos relatos (arquivos enviados ao Storage local pelo script de seed de mídia).
  for post in select id from public.posts where occurrence_id = occ_alagamento order by id loop
    insert into public.post_images (post_id, storage_path, position)
    values (post, format('reports/%s/evidencia-%s.jpg', post, post), 1);
  end loop;
  insert into public.post_images (post_id, storage_path, position)
  select id, format('reports/%s/evidencia-%s.jpg', id, id), 1
  from public.posts
  where occurrence_id in (occ_buraco, occ_poste, occ_residuos)
    and id = (select min(first_post.id) from public.posts first_post where first_post.occurrence_id = posts.occurrence_id);

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- Outras cidades, para os rankings de cidades e de cidadãos.
-- Contas adicionais (senha urbapp123):
--   lucas@urbapp.test, beatriz@urbapp.test   moradores de Campinas
--   pedro@urbapp.test, julia@urbapp.test     moradores de Belo Horizonte
--   tiago@urbapp.test                        morador de Recife
do $$
declare
  demo record;
  spot record;
  categories bigint[] := array(
    select id from public.problem_categories
    where slug in ('public-maintenance', 'public-lighting', 'urban-cleaning', 'urban-trees', 'sanitation', 'accessibility')
    order by slug
  );
  titles text[] := array[
    'Buraco na faixa de pedestres', 'Lâmpada queimada na rua', 'Lixo acumulado na esquina',
    'Galho caído na calçada', 'Bueiro entupido', 'Rampa de acessibilidade danificada',
    'Calçada afundada', 'Poste piscando à noite', 'Entulho em terreno baldio',
    'Árvore inclinada sobre a via', 'Vazamento de água na rua', 'Piso tátil arrancado',
    'Tampa de bueiro solta', 'Praça sem iluminação'
  ];
  reporters uuid[];
  voters uuid[];
  occurrence bigint;
  cycle bigint;
  reporter uuid;
  index integer;
  voter_index integer;
  voted integer;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  )
  select
    '00000000-0000-0000-0000-000000000000', seed.id, 'authenticated', 'authenticated', seed.email,
    extensions.crypt('urbapp123', extensions.gen_salt('bf')), now(), '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'username', seed.username, 'full_name', seed.full_name,
      'city_id', (select id from public.cities where name = seed.city_name)::text
    ),
    now() - interval '150 days', now()
  from (values
    ('20000000-0000-0000-0000-000000000011'::uuid, 'lucas@urbapp.test', 'lucas.prado', 'Lucas Prado', 'Campinas'),
    ('20000000-0000-0000-0000-000000000012'::uuid, 'beatriz@urbapp.test', 'beatriz.melo', 'Beatriz Melo', 'Campinas'),
    ('20000000-0000-0000-0000-000000000013'::uuid, 'pedro@urbapp.test', 'pedro.ramos', 'Pedro Ramos', 'Belo Horizonte'),
    ('20000000-0000-0000-0000-000000000014'::uuid, 'julia@urbapp.test', 'julia.castro', 'Júlia Castro', 'Belo Horizonte'),
    ('20000000-0000-0000-0000-000000000015'::uuid, 'tiago@urbapp.test', 'tiago.lima', 'Tiago Lima', 'Recife')
  ) as seed(id, email, username, full_name, city_name);

  insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  select gen_random_uuid(), users.id::text, users.id,
         jsonb_build_object('sub', users.id::text, 'email', users.email, 'email_verified', true),
         'email', now(), now(), now()
  from auth.users users
  where users.email in ('lucas@urbapp.test', 'beatriz@urbapp.test', 'pedro@urbapp.test', 'julia@urbapp.test', 'tiago@urbapp.test');

  -- Validadores de apoio: os moradores de Sorocaba também votam nas outras cidades.
  voters := array[
    '20000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000003',
    '20000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001'
  ]::uuid[];

  for demo in
    select * from (values
      ('Campinas', -22.9056, -47.0608, 12, 7, array['20000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000012']::uuid[]),
      ('Belo Horizonte', -19.9167, -43.9345, 14, 6, array['20000000-0000-0000-0000-000000000013', '20000000-0000-0000-0000-000000000014']::uuid[]),
      ('Recife', -8.0476, -34.8770, 5, 4, array['20000000-0000-0000-0000-000000000015']::uuid[])
    ) as cities(city_name, latitude, longitude, total, resolved, city_reporters)
  loop
    reporters := demo.city_reporters;
    for index in 1..demo.total loop
      select demo.latitude + ((index % 5) - 2) * 0.006 as latitude,
             demo.longitude + ((index % 3) - 1) * 0.007 as longitude
      into spot;
      reporter := reporters[1 + (index % array_length(reporters, 1))];

      perform set_config('request.jwt.claim.sub', reporter::text, true);
      select created.occurrence_id into occurrence from public.create_occurrence_report(
        (select id from public.cities where name = demo.city_name),
        categories[1 + (index % array_length(categories, 1))],
        titles[1 + ((index - 1) % array_length(titles, 1))],
        'Registro de demonstração para o ambiente local do UrbApp.',
        spot.latitude, spot.longitude, null, 'Centro', false
      ) created;

      -- Datas distribuídas nos últimos meses para os tempos de resolução.
      update public.occurrences
      set created_at = now() - make_interval(days => 3 + index * 4)
      where id = occurrence;

      if index <= demo.resolved then
        cycle := public.open_resolution_cycle(occurrence, 'O problema foi corrigido no local.', 'citizen');
        voted := 0;
        voter_index := 1;
        while voted < 3 loop
          if voters[voter_index] <> reporter then
            perform set_config('request.jwt.claim.sub', voters[voter_index]::text, true);
            perform public.vote_resolution_cycle(cycle, 'confirm', spot.latitude, spot.longitude);
            voted := voted + 1;
          end if;
          voter_index := voter_index + 1;
        end loop;
      end if;
    end loop;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;

-- Toda ocorrência chega com pelo menos uma foto no relato inicial, como exige
-- a publicação no app. Os arquivos são enviados por `supabase/seed-media.sh`.
insert into public.post_images (post_id, storage_path, position)
select first_post.id, format('reports/%s/evidencia-%s.jpg', first_post.id, first_post.id), 1
from (
  select distinct on (post.occurrence_id) post.id
  from public.posts post
  where post.occurrence_id is not null
  order by post.occurrence_id, post.id
) first_post
where not exists (
  select 1 from public.post_images image where image.post_id = first_post.id
);
