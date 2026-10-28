-- Perfil privado passa a valer também na API, e não apenas nas telas do app.
--
-- Antes: a política "Profiles are viewable by everyone" (using true) deixava qualquer
-- pessoa, inclusive sem login, ler nome, biografia, cidade, XP e pontos de perfis com
-- is_public = false. Insígnias, contadores de participação e os registros individuais de
-- apoio e de acompanhamento também eram legíveis por qualquer pessoa.
--
-- Agora:
-- - a tabela profiles só devolve perfis públicos, o próprio perfil ou, para administradores
--   e moderadores da plataforma (is_platform_admin), qualquer perfil;
-- - quem abre um perfil privado de outra pessoa recebe apenas a identificação básica
--   (nome, usuário e foto) por get_profile_card, suficiente para a tela "Perfil privado"
--   e para o botão de seguir;
-- - insígnias e contadores de participação seguem a mesma regra;
-- - cada pessoa só lê os próprios registros de apoio e de acompanhamento. Os totais
--   públicos continuam nas views de feed, que agregam sem identificar quem apoiou.
-- As views de feed e de comentários continuam exibindo o nome do autor, pois rodam com
-- o dono da view e já tratam o anonimato dos relatos.

drop policy if exists "Profiles are viewable by everyone" on public.profiles;
drop policy if exists "Profiles visible when public, to the owner or to admins" on public.profiles;
create policy "Profiles visible when public, to the owner or to admins"
  on public.profiles
  for select
  to anon, authenticated
  using (
    is_public
    or id = (select auth.uid())
    or (select public.is_platform_admin())
  );

-- Usada apenas dentro de funções security definer; não é exposta à API.
create or replace function public.can_view_profile_details(target_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select target_profile_id = auth.uid()
    or public.is_platform_admin()
    or exists (
      select 1 from public.profiles profile
      where profile.id = target_profile_id and profile.is_public
    );
$$;

revoke all on function public.can_view_profile_details(uuid) from public, anon, authenticated;
grant execute on function public.can_view_profile_details(uuid) to service_role;

-- Identificação mínima de qualquer perfil, inclusive privado.
create or replace function public.get_profile_card(target_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', profile.id,
    'full_name', profile.full_name,
    'username', profile.username,
    'avatar_url', profile.avatar_url,
    'is_public', profile.is_public
  )
  from public.profiles profile
  where profile.id = target_profile_id;
$$;

revoke all on function public.get_profile_card(uuid) from public, anon;
grant execute on function public.get_profile_card(uuid) to authenticated, service_role;

drop policy if exists "User badges are viewable by everyone" on public.user_badges;
drop policy if exists "User badges follow profile visibility" on public.user_badges;
create policy "User badges follow profile visibility"
  on public.user_badges
  for select
  to anon, authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_platform_admin())
    -- a subconsulta respeita a política de profiles: só encontra perfis visíveis
    or exists (select 1 from public.profiles profile where profile.id = user_id and profile.is_public)
  );

-- Registros individuais de apoio e acompanhamento: só o próprio usuário e a administração.
drop policy if exists "Occurrence supports are public" on public.occurrence_supports;
drop policy if exists "Users view their own occurrence supports" on public.occurrence_supports;
create policy "Users view their own occurrence supports"
  on public.occurrence_supports
  for select
  to authenticated
  using (user_id = (select auth.uid()) or (select public.is_platform_admin()));

drop policy if exists "Occurrence followers are public" on public.occurrence_followers;
drop policy if exists "Users view their own occurrence follows" on public.occurrence_followers;
create policy "Users view their own occurrence follows"
  on public.occurrence_followers
  for select
  to authenticated
  using (user_id = (select auth.uid()) or (select public.is_platform_admin()));

-- Tabela legada (apoios por relato), mantida apenas como histórico.
drop policy if exists "Post supports are viewable by everyone" on public.post_supports;
drop policy if exists "Users view their own legacy post supports" on public.post_supports;
create policy "Users view their own legacy post supports"
  on public.post_supports
  for select
  to authenticated
  using (user_id = (select auth.uid()) or (select public.is_platform_admin()));

-- Contadores do perfil: zerados para perfis privados de terceiros.
create or replace function public.get_participation_summary(target_profile_id uuid default auth.uid())
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public.can_view_profile_details(target_profile_id) then
      jsonb_build_object('reports', 0, 'supports', 0, 'validations', 0, 'following', 0)
    else jsonb_build_object(
      'reports', (
        select count(distinct post.occurrence_id) from public.posts post
        where post.user_id = target_profile_id and post.hidden_at is null
          and (target_profile_id = auth.uid() or not post.anonymity)
      ),
      'supports', (
        select count(*) from public.occurrence_supports support
        where support.user_id = target_profile_id
      ),
      'validations', (
        select count(*) from public.resolution_votes vote
        where vote.voter_id = target_profile_id
      ),
      'following', (
        select count(*) from public.occurrence_followers follower
        where follower.user_id = target_profile_id
      )
    )
  end;
$$;
