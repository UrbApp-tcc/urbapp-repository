-- Opcional: bancos que já rodaram migrações antigas com colunas bigint renomeadas.
-- Instalações novas não criam essas colunas; os IF EXISTS não fazem nada.

alter table public.posts
    drop column if exists legacy_user_id;

alter table public.profiles
    drop column if exists legacy_user_id;

alter table public.post_status_history
    drop column if exists legacy_changed_by;
