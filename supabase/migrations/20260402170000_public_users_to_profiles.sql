-- Remove public.users (legado bigint). Todas as referências passam a public.profiles (uuid = auth).
-- Espera-se tabelas vazias ou dados descartáveis nas colunas bigint.

-- 1) FKs apontando para public.users
do $$
declare
  r record;
begin
  for r in
    select c.conname as cname,
           format('%I.%I', ns.nspname, rel.relname) as tbl
    from pg_constraint c
    join pg_class rel on rel.oid = c.conrelid
    join pg_namespace ns on ns.oid = rel.relnamespace
    join pg_class ref on ref.oid = c.confrelid
    join pg_namespace nsref on nsref.oid = ref.relnamespace
    where c.contype = 'f'
      and nsref.nspname = 'public'
      and ref.relname = 'users'
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.cname);
  end loop;
end $$;

-- 2) Substituir colunas bigint por uuid -> profiles(id)

alter table public.comments
  drop column if exists user_id cascade;
alter table public.comments
  add column user_id uuid not null references public.profiles(id) on delete cascade;

alter table public.agency_users
  drop column if exists user_id cascade;
alter table public.agency_users
  add column user_id uuid not null references public.profiles(id) on delete cascade,
  add constraint agency_users_agency_id_user_id_key unique (agency_id, user_id);

alter table public.post_supports
  drop column if exists user_id cascade;
alter table public.post_supports
  add column user_id uuid not null references public.profiles(id) on delete cascade,
  add constraint post_supports_post_id_user_id_key unique (post_id, user_id);

alter table public.notifications
  drop column if exists user_id cascade;
alter table public.notifications
  add column user_id uuid not null references public.profiles(id) on delete cascade;

alter table public.user_devices
  drop column if exists user_id cascade;
alter table public.user_devices
  add column user_id uuid not null references public.profiles(id) on delete cascade;

alter table public.user_badges
  drop column if exists user_id cascade;
alter table public.user_badges
  add column user_id uuid not null references public.profiles(id) on delete cascade,
  add constraint user_badges_user_id_badge_id_key unique (user_id, badge_id);

alter table public.xp_transactions
  drop column if exists user_id cascade;
alter table public.xp_transactions
  add column user_id uuid not null references public.profiles(id) on delete cascade;

alter table public.moderation_reports
  drop column if exists reporter_user_id cascade;
alter table public.moderation_reports
  add column reporter_user_id uuid not null references public.profiles(id) on delete cascade;

alter table public.activity_events
  drop column if exists user_id cascade;
alter table public.activity_events
  add column user_id uuid references public.profiles(id) on delete set null;

-- 3) Tabela legada
drop table if exists public.users cascade;
