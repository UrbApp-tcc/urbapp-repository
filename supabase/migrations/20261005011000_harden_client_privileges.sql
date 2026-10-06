-- UrbApp: privilégio mínimo para clientes (spec §44.8 "Segurança / RLS").
--
-- O Supabase concede ALL em tabelas novas para anon/authenticated e a proteção
-- dependia apenas de RLS. Algumas tabelas estavam sem RLS (categorias, eventos de
-- atividade, dispositivos) e outras aceitavam colunas sensíveis em INSERT/UPDATE
-- (status e contadores de relatos, XP/pontos de perfil, histórico de status).
-- A partir daqui, toda escrita do cliente é concedida coluna a coluna e as
-- operações de negócio continuam exclusivamente nas funções `security definer`.

-- 1. Remove escrita implícita em todas as tabelas e views públicas.
do $$
declare
  relation record;
begin
  for relation in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'v', 'm', 'p')
  loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on table public.%I from anon, authenticated',
      relation.relname
    );
  end loop;
end;
$$;

alter default privileges in schema public
  revoke insert, update, delete, truncate, references, trigger on tables from anon, authenticated;

-- 2. Tabelas que estavam sem RLS.
alter table public.problem_categories enable row level security;
drop policy if exists "Problem categories are public" on public.problem_categories;
create policy "Problem categories are public"
on public.problem_categories for select to anon, authenticated using (true);

alter table public.activity_events enable row level security;
revoke select on public.activity_events from anon, authenticated;
drop policy if exists "Admins read activity events" on public.activity_events;
create policy "Admins read activity events"
on public.activity_events for select to authenticated
using (public.is_platform_admin(auth.uid()));
grant select on public.activity_events to authenticated;

alter table public.user_devices enable row level security;
revoke select on public.user_devices from anon;
drop policy if exists "Users manage their devices" on public.user_devices;
create policy "Users manage their devices"
on public.user_devices for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
grant select, delete on public.user_devices to authenticated;
grant insert (user_id, platform, push_token, last_seen_at) on public.user_devices to authenticated;
grant update (platform, push_token, last_seen_at) on public.user_devices to authenticated;

-- 3. Relatos só nascem pelas RPCs `create_occurrence_report` e
--    `add_report_to_occurrence`; não podem ser apagados para preservar histórico.
drop policy if exists "Authenticated users can create their own posts" on public.posts;
drop policy if exists "Users can delete their own posts" on public.posts;
drop policy if exists "Users can update their own posts" on public.posts;
drop policy if exists "Agency members can update posts assigned to their agency" on public.posts;
drop trigger if exists xp_on_post_deleted on public.posts;

-- O histórico de status legado é gravado apenas pelo backend.
drop policy if exists "Users can create status history for owned or managed posts"
  on public.post_status_history;

-- 4. Perfis: o cliente edita apenas dados de apresentação.
drop policy if exists "Users can insert their own profile" on public.profiles;
grant update (full_name, username, avatar_url, biography, city_id, featured_badge_id)
  on public.profiles to authenticated;

-- 5. Interações sociais (políticas de RLS já existentes restringem ao próprio usuário).
grant insert (comment_id, user_id) on public.comment_likes to authenticated;
grant delete on public.comment_likes to authenticated;
grant insert (follower_id, followed_id) on public.profile_followers to authenticated;
grant delete on public.profile_followers to authenticated;
grant insert (occurrence_id, user_id) on public.occurrence_followers to authenticated;
grant delete on public.occurrence_followers to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant delete on public.notifications to authenticated;

-- Imagens de relatos: o autor anexa imagens ao próprio relato; não reescreve depois.
drop policy if exists "Users can update images from their own posts" on public.post_images;
drop policy if exists "Users can delete images from their own posts" on public.post_images;
grant insert (post_id, storage_path, caption, position) on public.post_images to authenticated;

-- 6. Solicitações institucionais: somente campos declarados pelo solicitante.
grant insert (
  requester_user_id,
  city_id,
  public_name,
  party,
  mandate_starts_on,
  mandate_ends_on,
  institutional_email,
  proof_summary,
  proof_links
) on public.councilor_profile_requests to authenticated;

-- 7. Denúncias: o gatilho `prepare_moderation_report` define estado e ocorrência.
grant insert (reporter_user_id, target_type, target_id, reason)
  on public.moderation_reports to authenticated;

-- 8. Evidências no Storage não podem ser sobrescritas nem apagadas depois de
--    publicadas; a janela curta permite apenas limpar uploads que falharam.
drop policy if exists "Users can update their own post images in storage" on storage.objects;
drop policy if exists "Users can delete their own post images in storage" on storage.objects;
create policy "Users can discard their recent post image uploads"
on storage.objects for delete to authenticated
using (
  bucket_id = 'post-images'
  and (owner = auth.uid() or owner_id = auth.uid()::text)
  and created_at > now() - interval '15 minutes'
);

-- 9. Funções que alteram estado não são executáveis por visitantes anônimos.
revoke execute on function public.end_councilor_following(bigint, text) from anon, public;
revoke execute on function public.create_agency_profile_request(bigint, text, text, text, text, text, text)
  from anon, public;
revoke execute on function public.create_public_agency_profile(bigint, text, text, text)
  from anon, public, authenticated;
revoke execute on function public.ensure_my_profile() from anon, public;
revoke execute on function public.generate_unique_username(text, uuid) from anon, public, authenticated;
grant execute on function public.ensure_my_profile() to authenticated;

notify pgrst, 'reload schema';
