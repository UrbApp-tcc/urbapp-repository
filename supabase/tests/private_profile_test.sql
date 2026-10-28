-- Perfil privado na API (RLS de profiles, insígnias, contadores e cartão básico).
-- As consultas rodam com os papéis da API (`anon` e `authenticated`).
begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(21);

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

insert into public.cities (name, state) values ('Cidade Privacidade', 'sp');

insert into auth.users (id, email, raw_user_meta_data)
select seed.id, seed.email,
       jsonb_build_object('username', seed.username, 'full_name', seed.full_name,
                          'city_id', (select id::text from public.cities where name = 'Cidade Privacidade'))
from (values
  ('40000000-0000-0000-0000-000000000001'::uuid, 'privado@urbapp.test', 'perfil_privado', 'Pessoa Privada'),
  ('40000000-0000-0000-0000-000000000002'::uuid, 'publico@urbapp.test', 'perfil_publico', 'Pessoa Pública'),
  ('40000000-0000-0000-0000-000000000003'::uuid, 'adm.priv@urbapp.test', 'admin_privacidade', 'Admin Privacidade')
) as seed(id, email, username, full_name);

update public.profiles set is_public = false, biography = 'Bio que não deve vazar'
where id = '40000000-0000-0000-0000-000000000001';
insert into public.platform_user_roles (user_id, role) values ('40000000-0000-0000-0000-000000000003', 'admin');
insert into public.user_badges (user_id, badge_id)
select '40000000-0000-0000-0000-000000000001', id from public.badges order by min_level limit 1
on conflict do nothing;

-- Atividade da pessoa privada, para que os contadores ocultos não sejam zero por acaso.
-- Usa uma ocorrência do seed local; o teste não depende de qual.
insert into public.occurrence_supports (occurrence_id, user_id)
select id, '40000000-0000-0000-0000-000000000001' from public.occurrences order by id limit 1;
insert into public.occurrence_followers (occurrence_id, user_id)
select id, '40000000-0000-0000-0000-000000000001' from public.occurrences order by id limit 1;

-- ---------------------------------------------------------------------------
-- Visitante sem login
-- ---------------------------------------------------------------------------

set local role anon;
select pg_temp.act_as('');
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is(
  (select count(*)::int from public.profiles where id = '40000000-0000-0000-0000-000000000001'),
  0,
  'visitante sem login não lê perfil privado'
);
select is(
  (select count(*)::int from public.profiles where id = '40000000-0000-0000-0000-000000000002'),
  1,
  'visitante sem login lê perfil público'
);
select is(
  (select count(*)::int from public.user_badges where user_id = '40000000-0000-0000-0000-000000000001'),
  0,
  'visitante sem login não lê insígnias de perfil privado'
);
select throws_ok(
  $$ select public.get_profile_card('40000000-0000-0000-0000-000000000001') $$,
  '42501',
  null,
  'visitante sem login não consulta o cartão de perfil'
);
select is(
  (select count(*)::int from public.occurrence_supports where user_id = '40000000-0000-0000-0000-000000000001'),
  0,
  'visitante sem login não lê registros individuais de apoio'
);

reset role;

-- ---------------------------------------------------------------------------
-- Outro usuário autenticado
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.act_as('40000000-0000-0000-0000-000000000002');

select is(
  (select count(*)::int from public.profiles where id = '40000000-0000-0000-0000-000000000001'),
  0,
  'outro usuário não lê a linha do perfil privado'
);
select is(
  (select count(*)::int from public.profiles where biography = 'Bio que não deve vazar'),
  0,
  'a biografia do perfil privado não aparece em consulta aberta'
);
select is(
  (select count(*)::int from public.profiles where id = '40000000-0000-0000-0000-000000000002'),
  1,
  'o próprio perfil público continua visível'
);
select is(
  public.get_profile_card('40000000-0000-0000-0000-000000000001') ->> 'username',
  'perfil_privado',
  'o cartão do perfil privado traz o nome de usuário'
);
select is(
  public.get_profile_card('40000000-0000-0000-0000-000000000001') ->> 'is_public',
  'false',
  'o cartão informa que o perfil é privado'
);
select ok(
  not (public.get_profile_card('40000000-0000-0000-0000-000000000001') ?| array['biography', 'city_id', 'current_xp', 'current_points']),
  'o cartão não expõe biografia, cidade, XP nem pontos'
);
select is(
  public.get_participation_summary('40000000-0000-0000-0000-000000000001'),
  '{"reports": 0, "supports": 0, "validations": 0, "following": 0}'::jsonb,
  'os contadores de participação de perfil privado são zerados para terceiros'
);
select is(
  (select count(*)::int from public.user_badges where user_id = '40000000-0000-0000-0000-000000000001'),
  0,
  'outro usuário não lê insígnias de perfil privado'
);
select is(
  (select count(*)::int from public.occurrence_supports where user_id = '40000000-0000-0000-0000-000000000001'),
  0,
  'outro usuário não descobre o que a pessoa privada apoiou'
);
select is(
  (select count(*)::int from public.occurrence_followers where user_id = '40000000-0000-0000-0000-000000000001'),
  0,
  'outro usuário não descobre o que a pessoa privada acompanha'
);

reset role;

-- ---------------------------------------------------------------------------
-- Dono do perfil privado e administração
-- ---------------------------------------------------------------------------

set local role authenticated;
select pg_temp.act_as('40000000-0000-0000-0000-000000000001');

select is(
  (select biography from public.profiles where id = '40000000-0000-0000-0000-000000000001'),
  'Bio que não deve vazar',
  'o dono continua lendo o próprio perfil privado'
);
select ok(
  (select count(*) from public.user_badges where user_id = '40000000-0000-0000-0000-000000000001') >= 1,
  'o dono continua lendo as próprias insígnias'
);
select is(
  (select count(*)::int from public.occurrence_supports where user_id = '40000000-0000-0000-0000-000000000001'),
  1,
  'o dono continua lendo os próprios apoios'
);
select is(
  (public.get_participation_summary('40000000-0000-0000-0000-000000000001') ->> 'supports')::int,
  1,
  'o dono vê os próprios contadores, que não são zero'
);

reset role;
set local role authenticated;
select pg_temp.act_as('40000000-0000-0000-0000-000000000003');

select is(
  (select count(*)::int from public.profiles where id = '40000000-0000-0000-0000-000000000001'),
  1,
  'a administração lê perfil privado'
);
select is(
  (public.get_participation_summary('40000000-0000-0000-0000-000000000001') ->> 'following')::int,
  1,
  'a administração consulta os contadores de perfil privado'
);

reset role;

select * from finish();
rollback;
