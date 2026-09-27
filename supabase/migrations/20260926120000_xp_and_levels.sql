-- =====================================================================
-- Etapa 1 / Item 1: XP e nível
--
-- - Tabela de níveis (5 níveis, um para cada insígnia existente).
-- - Função award_xp: grava em xp_transactions, soma current_xp,
--   recalcula current_level e cria a notificação "subiu de nível".
-- - Triggers que dão XP: criar reporte, apoiar reporte de outra pessoa,
--   comentar (com limite diário). Apagar o reporte devolve o XP.
-- - RLS em levels, xp_transactions e notifications.
-- - Realtime em notifications (para o aviso aparecer na hora no app).
-- - Backfill silencioso do XP das ações que já existem.
--
-- As insígnias por nível (item 2) ficam numa migration separada.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) NÍVEIS
-- ---------------------------------------------------------------------
create table if not exists public.levels (
    level  integer primary key check (level >= 1),
    min_xp integer not null unique check (min_xp >= 0),
    title  text not null
);

insert into public.levels (level, min_xp, title) values
    (1,    0, 'Observador'),
    (2,  100, 'Morador Atento'),
    (3,  300, 'Vizinho Ativo'),
    (4,  600, 'Fiscal do Bairro'),
    (5, 1000, 'Guardião da Cidade')
on conflict (level) do update
    set min_xp = excluded.min_xp,
        title  = excluded.title;


-- ---------------------------------------------------------------------
-- 2) VALORES DE XP (um lugar só para ajustar)
-- ---------------------------------------------------------------------
create or replace function public.xp_value(p_action text)
returns integer
language sql
immutable
as $$
    select case p_action
        when 'post_created'     then 20  -- criou um reporte
        when 'support_given'    then 5   -- apoiou o reporte de outra pessoa
        when 'comment'          then 5   -- comentou (limite diário abaixo)
        when 'validation_given' then 10  -- confirmou a resolução (item 3)
        when 'post_validated'   then 50  -- reporte confirmado pela comunidade (item 3)
        else 0
    end;
$$;

-- Máximo de comentários por dia que dão XP (evita farm de XP com spam).
create or replace function public.xp_daily_comment_cap()
returns integer
language sql
immutable
as $$ select 5 $$;


-- ---------------------------------------------------------------------
-- 3) ÍNDICES
-- ---------------------------------------------------------------------

-- A mesma ação não dá XP duas vezes (ex.: tirar e dar apoio de novo).
-- Estornos usam source_type diferente (ex.: 'post_deleted').
create unique index if not exists xp_transactions_unique_source
    on public.xp_transactions (user_id, source_type, source_id)
    where source_id is not null;

create index if not exists xp_transactions_user_created_idx
    on public.xp_transactions (user_id, created_at desc);

create index if not exists notifications_user_created_idx
    on public.notifications (user_id, created_at desc);


-- ---------------------------------------------------------------------
-- 4) FUNÇÕES DE APOIO
-- ---------------------------------------------------------------------
create or replace function public.level_for_xp(p_xp integer)
returns integer
language sql
stable
set search_path = public
as $$
    select coalesce(max(level), 1)
      from public.levels
     where min_xp <= greatest(coalesce(p_xp, 0), 0);
$$;

create or replace function public.notify_user(
    p_user_id uuid,
    p_type    text,
    p_title   text,
    p_body    text,
    p_payload jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_user_id is null then
        return;
    end if;

    insert into public.notifications (user_id, type, title, body, payload)
    values (p_user_id, p_type, p_title, p_body, p_payload);
end;
$$;


-- ---------------------------------------------------------------------
-- 5) FUNÇÃO CENTRAL: award_xp
-- ---------------------------------------------------------------------
create or replace function public.award_xp(
    p_user_id     uuid,
    p_xp          integer,
    p_source_type text,
    p_source_id   bigint  default null,
    p_notify      boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_tx_id      bigint;
    v_old_level  integer;
    v_new_xp     integer;
    v_new_level  integer;
    v_level_name text;
begin
    if p_user_id is null or coalesce(p_xp, 0) = 0 then
        return;
    end if;

    -- Trava o perfil para duas ações simultâneas não se atropelarem.
    select current_level
      into v_old_level
      from public.profiles
     where id = p_user_id
       for update;

    if not found then
        return;
    end if;

    insert into public.xp_transactions (user_id, source_type, source_id, xp_delta)
    values (p_user_id, p_source_type, p_source_id, p_xp)
    on conflict do nothing
    returning id into v_tx_id;

    -- Essa ação já tinha dado XP.
    if v_tx_id is null then
        return;
    end if;

    update public.profiles
       set current_xp = greatest(current_xp + p_xp, 0)
     where id = p_user_id
    returning current_xp into v_new_xp;

    v_new_level := public.level_for_xp(v_new_xp);

    if v_new_level is distinct from v_old_level then
        update public.profiles
           set current_level = v_new_level
         where id = p_user_id;
    end if;

    if p_notify and v_new_level > v_old_level then
        select title into v_level_name from public.levels where level = v_new_level;

        perform public.notify_user(
            p_user_id,
            'level_up',
            'Você subiu de nível!',
            format('Parabéns! Você chegou ao nível %s: %s.', v_new_level, v_level_name),
            jsonb_build_object(
                'old_level',   v_old_level,
                'new_level',   v_new_level,
                'level_title', v_level_name,
                'current_xp',  v_new_xp
            )
        );
    end if;
end;
$$;

-- Só os triggers (que rodam como dono) chamam essas funções.
revoke all on function public.award_xp(uuid, integer, text, bigint, boolean) from public, anon, authenticated;
revoke all on function public.notify_user(uuid, text, text, text, jsonb) from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 6) TRIGGERS QUE DÃO (OU DEVOLVEM) XP
-- ---------------------------------------------------------------------

-- 6a) Criou um reporte
create or replace function public.trg_xp_post_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.award_xp(new.user_id, public.xp_value('post_created'), 'post_created', new.id);
    return new;
end;
$$;

drop trigger if exists xp_on_post_created on public.posts;
create trigger xp_on_post_created
after insert on public.posts
for each row execute function public.trg_xp_post_created();

-- 6b) Apagou o reporte: devolve o XP de criação (evita criar/apagar para farmar)
create or replace function public.trg_xp_post_deleted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_given integer;
begin
    select xp_delta
      into v_given
      from public.xp_transactions
     where user_id = old.user_id
       and source_type = 'post_created'
       and source_id = old.id;

    if v_given is not null then
        perform public.award_xp(old.user_id, -v_given, 'post_deleted', old.id, false);
    end if;

    return old;
end;
$$;

drop trigger if exists xp_on_post_deleted on public.posts;
create trigger xp_on_post_deleted
after delete on public.posts
for each row execute function public.trg_xp_post_deleted();

-- 6c) Apoiou o reporte de outra pessoa (1x por reporte, mesmo tirando e dando de novo)
create or replace function public.trg_xp_support_given()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (
        select 1 from public.posts
         where id = new.post_id and user_id = new.user_id
    ) then
        return new; -- apoio no próprio reporte não conta
    end if;

    perform public.award_xp(new.user_id, public.xp_value('support_given'), 'support_given', new.post_id);
    return new;
end;
$$;

drop trigger if exists xp_on_support_given on public.post_supports;
create trigger xp_on_support_given
after insert on public.post_supports
for each row execute function public.trg_xp_support_given();

-- 6d) Comentou (até o limite diário)
create or replace function public.trg_xp_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_today_count integer;
begin
    select count(*)
      into v_today_count
      from public.xp_transactions
     where user_id = new.user_id
       and source_type = 'comment'
       and created_at >= date_trunc('day', now());

    if v_today_count < public.xp_daily_comment_cap() then
        perform public.award_xp(new.user_id, public.xp_value('comment'), 'comment', new.id);
    end if;

    return new;
end;
$$;

drop trigger if exists xp_on_comment on public.comments;
create trigger xp_on_comment
after insert on public.comments
for each row execute function public.trg_xp_comment();


-- ---------------------------------------------------------------------
-- 7) SEGURANÇA
-- ---------------------------------------------------------------------

-- levels: leitura pública
alter table public.levels enable row level security;
revoke all on public.levels from anon, authenticated;
grant select on public.levels to anon, authenticated;
grant all on public.levels to service_role;

drop policy if exists "Levels are viewable by everyone" on public.levels;
create policy "Levels are viewable by everyone"
on public.levels for select to anon, authenticated using (true);

-- xp_transactions: cada um vê só o próprio extrato; ninguém escreve pelo app
alter table public.xp_transactions enable row level security;
revoke all on public.xp_transactions from anon, authenticated;
grant select on public.xp_transactions to authenticated;
grant all on public.xp_transactions to service_role;

drop policy if exists "Users can view their own xp" on public.xp_transactions;
create policy "Users can view their own xp"
on public.xp_transactions for select to authenticated
using (auth.uid() = user_id);

-- notifications: ver, marcar como lida e apagar as próprias
alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant all on public.notifications to service_role;

drop policy if exists "Users can view their own notifications" on public.notifications;
create policy "Users can view their own notifications"
on public.notifications for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can mark their own notifications as read" on public.notifications;
create policy "Users can mark their own notifications as read"
on public.notifications for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own notifications" on public.notifications;
create policy "Users can delete their own notifications"
on public.notifications for delete to authenticated
using (auth.uid() = user_id);


-- ---------------------------------------------------------------------
-- 8) REALTIME em notifications
-- ---------------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (
           select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = 'notifications'
       ) then
        alter publication supabase_realtime add table public.notifications;
    end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 9) BACKFILL: XP retroativo das ações que já existem (sem notificações)
-- ---------------------------------------------------------------------
do $$
declare
    r record;
begin
    for r in select id, user_id from public.posts loop
        perform public.award_xp(r.user_id, public.xp_value('post_created'), 'post_created', r.id, false);
    end loop;

    for r in
        select s.user_id, s.post_id
          from public.post_supports s
          join public.posts p on p.id = s.post_id
         where s.user_id <> p.user_id
    loop
        perform public.award_xp(r.user_id, public.xp_value('support_given'), 'support_given', r.post_id, false);
    end loop;

    -- Comentários antigos: respeita o limite de 5 por usuário por dia.
    for r in
        select id, user_id
          from (
              select c.id,
                     c.user_id,
                     row_number() over (
                         partition by c.user_id, date_trunc('day', c.created_at)
                         order by c.created_at, c.id
                     ) as n
                from public.comments c
          ) ranked
         where ranked.n <= public.xp_daily_comment_cap()
    loop
        perform public.award_xp(r.user_id, public.xp_value('comment'), 'comment', r.id, false);
    end loop;
end;
$$;

-- Garante que o nível de todo mundo bate com o XP.
update public.profiles
   set current_level = public.level_for_xp(current_xp)
 where current_level is distinct from public.level_for_xp(current_xp);