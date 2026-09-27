-- Finaliza o backend de likes:
-- 1) padroniza RLS/policies de post_supports
-- 2) sincroniza posts.supports_count via trigger
-- 3) backfill da contagem para os dados já existentes

-- Índices úteis para consultas e manutenção
create index if not exists post_supports_post_id_idx
  on public.post_supports (post_id);

create index if not exists post_supports_user_id_idx
  on public.post_supports (user_id);

-- Grants explícitos (mantém comportamento previsível)
grant select on table public.post_supports to anon;
grant select, insert, delete on table public.post_supports to authenticated;
grant all on table public.post_supports to service_role;

-- Habilita RLS para likes
alter table public.post_supports enable row level security;

-- Policies de leitura/escrita para likes
drop policy if exists "Post supports are viewable by everyone" on public.post_supports;
create policy "Post supports are viewable by everyone"
on public.post_supports
for select
to anon, authenticated
using (true);

drop policy if exists "Authenticated users can insert their own post support" on public.post_supports;
create policy "Authenticated users can insert their own post support"
on public.post_supports
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own post support" on public.post_supports;
create policy "Users can delete their own post support"
on public.post_supports
for delete
to authenticated
using (auth.uid() = user_id);

-- Função para manter supports_count consistente em posts
create or replace function public.sync_post_supports_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
       set supports_count = coalesce(supports_count, 0) + 1
     where id = new.post_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.posts
       set supports_count = greatest(0, coalesce(supports_count, 0) - 1)
     where id = old.post_id;
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_post_supports_count_sync on public.post_supports;
create trigger trg_post_supports_count_sync
after insert or delete on public.post_supports
for each row
execute function public.sync_post_supports_count();

-- Recalcula supports_count para alinhar dados antigos
update public.posts p
set supports_count = coalesce(src.cnt, 0)
from (
  select post_id, count(*)::integer as cnt
  from public.post_supports
  group by post_id
) src
where p.id = src.post_id;

-- Garante zero para posts sem likes
update public.posts
set supports_count = 0
where supports_count is null;

