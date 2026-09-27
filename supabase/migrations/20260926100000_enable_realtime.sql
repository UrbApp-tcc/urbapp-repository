-- Liga o Realtime para as tabelas usadas pelo app (feed, apoios e comentários).
-- Pode rodar mais de uma vez sem erro: só adiciona a tabela se ela ainda não estiver.
do $$
declare
    t text;
begin
    foreach t in array array['posts', 'post_supports', 'comments'] loop
        if not exists (
            select 1 from pg_publication_tables
             where pubname = 'supabase_realtime'
               and schemaname = 'public'
               and tablename = t
        ) then
            execute format('alter publication supabase_realtime add table public.%I', t);
        end if;
    end loop;
end;
$$;

-- Necessário para o Realtime mandar os dados completos quando algo é apagado
-- (ex.: tirar um apoio ou apagar um comentário), e não só o id.
alter table public.post_supports replica identity full;
alter table public.comments replica identity full;