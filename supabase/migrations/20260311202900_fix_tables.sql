-- correção do nome da coluna popularity
alter table public.users rename column "populatiry" to "popularity";

-- adição da coluna city_id
alter table public.users add column city_id bigint references public.cities(id);

-- remoção da coluna city
alter table public.users drop column city;

-- criação do índice único na coluna name e state da tabela cities
create unique index if not exists cities_name_state_key on public.cities(name, state);

-- definição de not null de colunas da tabela cities
alter table public.cities alter column name set not null;

alter table public.cities alter column state set not null;

alter table public.cities alter column created_at set not null;

-- definição de not null de colunas da tabela users
alter table public.users alter column created_at set not null;

alter table public.users alter column first_name set not null;

alter table public.users alter column last_name set not null;

alter table public.users alter column email set not null;

alter table public.users alter column xp set default 0;
alter table public.users alter column xp set not null;

alter table public.users alter column level set default 0;
alter table public.users alter column level set not null;

alter table public.users alter column verified set default false;
alter table public.users alter column verified set not null;

alter table public.users alter column popularity set default 0;
alter table public.users alter column popularity set not null;

alter table public.users alter column points set default 0;
alter table public.users alter column points set not null;

-- definição de not null de colunas da tabela posts
alter table public.posts alter column created_at set not null;

alter table public.posts rename column "user" to user_id;

alter table public.posts rename column city to city_id;

alter table public.posts alter column user_id set not null;

alter table public.posts alter column city_id set not null;

alter table public.posts alter column likes set default 0;
alter table public.posts alter column likes set not null;

alter table public.posts alter column status set default 'open'::public.report_status;
alter table public.posts alter column status set not null;

alter table public.posts alter column latitude set not null;

alter table public.posts alter column longitude set not null;

alter table public.posts alter column anonymity set default false;
alter table public.posts alter column anonymity set not null;

-- definição de not null de colunas da tabela comments
alter table public.comments alter column created_at set not null;

alter table public.comments rename column "user" to user_id;

alter table public.comments rename column post to post_id;

alter table public.comments alter column user_id set not null;

alter table public.comments alter column post_id set not null;

alter table public.comments alter column text set not null;

alter table public.comments alter column likes set default 0;
alter table public.comments alter column likes set not null;