-- =====================================================================
-- Etapa 1 / Itens 3, 4 e 6
--
-- 3. Validação comunitária: o autor pede a validação; vizinhos a até
--    500 m confirmam. Com 3 confirmações o reporte vira "completed".
--    Com 2 votos "ainda não" o pedido é cancelado.
-- 4. Expiração automática (pg_cron, todo dia): pedidos sem validação em
--    15 dias são encerrados e reportes abertos sem movimento há 60 dias
--    viram "expired".
-- 6. Notificação de mudança de status para o autor e quem apoiou.
--
-- O autor não pode mais marcar o próprio reporte como concluído direto.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) Regras (um lugar só para ajustar)
-- ---------------------------------------------------------------------
create or replace function public.validation_rules()
returns table (
    radius_m             integer,
    confirmations_needed integer,
    rejections_to_cancel integer,
    request_days         integer,
    stale_days           integer
)
language sql
immutable
as $$
    select 500, 3, 2, 15, 60
$$;
-- Distância em metros entre dois pontos (fórmula de Haversine).
create or replace function public.distance_meters(
    lat1 double precision, lon1 double precision,
    lat2 double precision, lon2 double precision
)
returns double precision
language sql
immutable
as $$
    select 2 * 6371000 * asin(sqrt(
        power(sin(radians(lat2 - lat1) / 2), 2)
        + cos(radians(lat1)) * cos(radians(lat2))
        * power(sin(radians(lon2 - lon1) / 2), 2)
    ))
$$;
create or replace function public.status_label(p_status public.report_status)
returns text
language sql
immutable
as $$
    select case p_status
        when 'open'        then 'Aberto'
        when 'in_analysis' then 'Em análise'
        when 'in_progress' then 'Em andamento'
        when 'completed'   then 'Concluído'
        when 'closed'      then 'Encerrado'
        when 'expired'     then 'Expirado'
    end;
$$;
-- ---------------------------------------------------------------------
-- 2) Tabelas
-- ---------------------------------------------------------------------
create table if not exists public.post_resolution_requests (
    id           bigint generated always as identity primary key,
    post_id      bigint not null references public.posts(id) on delete cascade,
    requested_by uuid not null references public.profiles(id) on delete cascade,
    note         text not null check (length(trim(note)) between 5 and 1000),
    status       text not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected', 'expired')),
    created_at   timestamptz not null default now(),
    decided_at   timestamptz
);
-- Só um pedido pendente por reporte.
create unique index if not exists post_resolution_requests_one_pending
    on public.post_resolution_requests (post_id)
    where status = 'pending';
create table if not exists public.post_resolution_votes (
    id         bigint generated always as identity primary key,
    request_id bigint not null references public.post_resolution_requests(id) on delete cascade,
    user_id    uuid not null references public.profiles(id) on delete cascade,
    confirmed  boolean not null,
    distance_m integer not null,
    created_at timestamptz not null default now(),
    unique (request_id, user_id)
);
-- Acesso só pelas funções abaixo.
alter table public.post_resolution_requests enable row level security;
alter table public.post_resolution_votes enable row level security;
revoke all on public.post_resolution_requests, public.post_resolution_votes from anon, authenticated;
grant all on public.post_resolution_requests, public.post_resolution_votes to service_role;
-- ---------------------------------------------------------------------
-- 3) O autor não conclui o próprio reporte direto
-- ---------------------------------------------------------------------
create or replace function public.guard_author_completion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status in ('completed', 'closed')
       and auth.uid() is not null
       and auth.uid() = new.user_id
       and coalesce(current_setting('urbapp.system_status_change', true), '') <> 'on' then
        raise exception 'A conclusão do reporte precisa ser confirmada pela comunidade.'
            using errcode = 'P0001';
    end if;
    return new;
end;
$$;
drop trigger if exists guard_author_completion on public.posts;
create trigger guard_author_completion
before update of status on public.posts
for each row
when (new.status is distinct from old.status)
execute function public.guard_author_completion();
-- ---------------------------------------------------------------------
-- 4) Item 6: notificação de mudança de status
-- ---------------------------------------------------------------------
create or replace function public.trg_notify_post_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_actor   uuid := auth.uid();
    v_title   text := coalesce(nullif(trim(new.title), ''), 'Seu reporte');
    v_label   text := public.status_label(new.status);
    v_payload jsonb := jsonb_build_object(
        'post_id', new.id,
        'from_status', old.status,
        'to_status', new.status
    );
begin
    if new.user_id is distinct from v_actor then
        perform public.notify_user(
            new.user_id,
            'post_status_changed',
            'Seu reporte foi atualizado',
            format('"%s" agora está: %s.', v_title, v_label),
            v_payload
        );
    end if;

    insert into public.notifications (user_id, type, title, body, payload)
    select s.user_id,
           'supported_post_status_changed',
           'Um reporte que você apoiou foi atualizado',
           format('"%s" agora está: %s.', v_title, v_label),
           v_payload
      from public.post_supports s
     where s.post_id = new.id
       and s.user_id <> new.user_id
       and s.user_id is distinct from v_actor;

    return new;
end;
$$;
drop trigger if exists notify_on_post_status_change on public.posts;
create trigger notify_on_post_status_change
after update of status on public.posts
for each row
when (old.status is distinct from new.status)
execute function public.trg_notify_post_status();
-- ---------------------------------------------------------------------
-- 5) Pedir a validação (autor)
-- ---------------------------------------------------------------------
create or replace function public.request_post_resolution(p_post_id bigint, p_note text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
    v_post       public.posts;
    v_request_id bigint;
begin
    select * into v_post from public.posts where id = p_post_id;

    if v_post.id is null then
        raise exception 'Reporte não encontrado.' using errcode = 'P0001';
    end if;
    if v_post.user_id is distinct from auth.uid() then
        raise exception 'Só o autor pode informar a resolução do reporte.' using errcode = 'P0001';
    end if;
    if v_post.status in ('completed', 'closed', 'expired') then
        raise exception 'Este reporte já está encerrado.' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.post_resolution_requests where post_id = p_post_id and status = 'pending') then
        raise exception 'Já existe um pedido de validação aguardando a comunidade.' using errcode = 'P0001';
    end if;
    if length(trim(coalesce(p_note, ''))) < 5 then
        raise exception 'Descreva em poucas palavras o que foi feito.' using errcode = 'P0001';
    end if;

    insert into public.post_resolution_requests (post_id, requested_by, note)
    values (p_post_id, auth.uid(), trim(p_note))
    returning id into v_request_id;

    -- Avisa quem apoiou: são os mais prováveis de passar pelo local.
    insert into public.notifications (user_id, type, title, body, payload)
    select s.user_id,
           'resolution_requested',
           'Foi resolvido mesmo?',
           format('O autor de "%s" disse que o problema foi resolvido. Se passar por lá, confirme!', v_post.title),
           jsonb_build_object('post_id', p_post_id, 'request_id', v_request_id)
      from public.post_supports s
     where s.post_id = p_post_id
       and s.user_id <> v_post.user_id;

    return v_request_id;
end;
$$;
-- ---------------------------------------------------------------------
-- 6) Votar (vizinhos a até 500 m)
-- ---------------------------------------------------------------------
create or replace function public.vote_post_resolution(
    p_post_id   bigint,
    p_confirmed boolean,
    p_latitude  double precision,
    p_longitude double precision
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_rules     record;
    v_post      public.posts;
    v_request   public.post_resolution_requests;
    v_distance  double precision;
    v_confirmed integer;
    v_rejected  integer;
    v_result    text := 'pending';
begin
    select * into v_rules from public.validation_rules();
    select * into v_post from public.posts where id = p_post_id;

    if v_post.id is null then
        raise exception 'Reporte não encontrado.' using errcode = 'P0001';
    end if;

    select * into v_request
      from public.post_resolution_requests
     where post_id = p_post_id and status = 'pending';

    if v_request.id is null then
        raise exception 'Este reporte não está aguardando validação.' using errcode = 'P0001';
    end if;
    if auth.uid() is null then
        raise exception 'Entre na sua conta para validar.' using errcode = 'P0001';
    end if;
    if auth.uid() = v_post.user_id then
        raise exception 'O autor não pode validar o próprio reporte.' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.post_resolution_votes where request_id = v_request.id and user_id = auth.uid()) then
        raise exception 'Você já deu sua opinião sobre esta resolução.' using errcode = 'P0001';
    end if;

    v_distance := public.distance_meters(p_latitude, p_longitude, v_post.latitude, v_post.longitude);
    if v_distance > v_rules.radius_m then
        raise exception 'Você precisa estar a até % m do local para validar (está a % m).',
            v_rules.radius_m, round(v_distance)
            using errcode = 'P0001';
    end if;

    insert into public.post_resolution_votes (request_id, user_id, confirmed, distance_m)
    values (v_request.id, auth.uid(), p_confirmed, round(v_distance));

    -- Quem ajuda a validar ganha XP (1x por pedido).
    perform public.award_xp(auth.uid(), public.xp_value('validation_given'), 'validation_given', v_request.id);

    select count(*) filter (where confirmed), count(*) filter (where not confirmed)
      into v_confirmed, v_rejected
      from public.post_resolution_votes
     where request_id = v_request.id;

    if v_confirmed >= v_rules.confirmations_needed then
        v_result := 'approved';

        update public.post_resolution_requests
           set status = 'approved', decided_at = now()
         where id = v_request.id;

        perform set_config('urbapp.system_status_change', 'on', true);
        update public.posts
           set status = 'completed', resolved_at = now()
         where id = p_post_id;
        perform set_config('urbapp.system_status_change', 'off', true);

        insert into public.post_status_history (post_id, from_status, to_status, note, changed_by)
        values (p_post_id, v_post.status, 'completed',
                'Resolução confirmada pela comunidade: ' || v_request.note, auth.uid());

        perform public.award_xp(v_post.user_id, public.xp_value('post_validated'), 'post_validated', p_post_id);

    elsif v_rejected >= v_rules.rejections_to_cancel then
        v_result := 'rejected';

        update public.post_resolution_requests
           set status = 'rejected', decided_at = now()
         where id = v_request.id;

        perform public.notify_user(
            v_post.user_id,
            'resolution_rejected',
            'A comunidade disse que ainda não foi resolvido',
            format('Vizinhos que passaram por "%s" disseram que o problema continua. O reporte segue aberto.', v_post.title),
            jsonb_build_object('post_id', p_post_id)
        );
    end if;

    return jsonb_build_object(
        'result', v_result,
        'confirmations', v_confirmed,
        'rejections', v_rejected,
        'needed', v_rules.confirmations_needed
    );
end;
$$;
-- ---------------------------------------------------------------------
-- 7) Situação da validação (para a tela do reporte)
-- ---------------------------------------------------------------------
create or replace function public.get_post_resolution_status(p_post_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_rules   record;
    v_request public.post_resolution_requests;
    v_my_vote boolean;
begin
    select * into v_rules from public.validation_rules();
    select * into v_request
      from public.post_resolution_requests
     where post_id = p_post_id and status = 'pending';

    if v_request.id is null then
        return null;
    end if;

    select confirmed into v_my_vote
      from public.post_resolution_votes
     where request_id = v_request.id and user_id = auth.uid();

    return jsonb_build_object(
        'request_id', v_request.id,
        'note', v_request.note,
        'created_at', v_request.created_at,
        'expires_at', v_request.created_at + make_interval(days => v_rules.request_days),
        'confirmations', (select count(*) from public.post_resolution_votes where request_id = v_request.id and confirmed),
        'rejections', (select count(*) from public.post_resolution_votes where request_id = v_request.id and not confirmed),
        'needed', v_rules.confirmations_needed,
        'radius_m', v_rules.radius_m,
        'my_vote', v_my_vote
    );
end;
$$;
revoke all on function public.request_post_resolution(bigint, text) from public, anon;
revoke all on function public.vote_post_resolution(bigint, boolean, double precision, double precision) from public, anon;
revoke all on function public.get_post_resolution_status(bigint) from public, anon;
grant execute on function public.request_post_resolution(bigint, text) to authenticated;
grant execute on function public.vote_post_resolution(bigint, boolean, double precision, double precision) to authenticated;
grant execute on function public.get_post_resolution_status(bigint) to authenticated;
-- ---------------------------------------------------------------------
-- 8) Item 4: expiração diária
-- ---------------------------------------------------------------------
create or replace function public.run_daily_expiration()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_rules record;
    r       record;
begin
    select * into v_rules from public.validation_rules();

    -- 8a) Pedidos de validação vencidos: encerra e avisa o autor.
    for r in
        update public.post_resolution_requests req
           set status = 'expired', decided_at = now()
         where req.status = 'pending'
           and req.created_at < now() - make_interval(days => v_rules.request_days)
        returning req.post_id, req.requested_by
    loop
        perform public.notify_user(
            r.requested_by,
            'resolution_expired',
            'A validação não foi concluída',
            'Ninguém confirmou a resolução a tempo. O reporte segue aberto; você pode pedir a validação de novo.',
            jsonb_build_object('post_id', r.post_id)
        );
    end loop;

    -- 8b) Reportes abertos sem nenhum movimento no período viram "expired".
    update public.posts p
       set status = 'expired'
     where p.status = 'open'
       and p.created_at < now() - make_interval(days => v_rules.stale_days)
       and not exists (
           select 1 from public.post_supports s
            where s.post_id = p.id
              and s.created_at > now() - make_interval(days => v_rules.stale_days))
       and not exists (
           select 1 from public.comments c
            where c.post_id = p.id
              and c.created_at > now() - make_interval(days => v_rules.stale_days))
       and not exists (
           select 1 from public.post_resolution_requests req
            where req.post_id = p.id and req.status = 'pending');
end;
$$;
revoke all on function public.run_daily_expiration() from public, anon, authenticated;
create extension if not exists pg_cron with schema pg_catalog;
do $$
begin
    perform cron.unschedule(jobid) from cron.job where jobname = 'urbapp-expiracao-diaria';
    -- Todo dia às 06:00 UTC (03:00 em Brasília).
    perform cron.schedule('urbapp-expiracao-diaria', '0 6 * * *', 'select public.run_daily_expiration()');
end;
$$;
