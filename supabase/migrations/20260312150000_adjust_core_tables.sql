-- atualização na tabela posts
-- adição de colunas
alter table public.posts
  add column title text,
  add column category_id bigint,
  add column agency_id bigint,
  add column supports_count integer not null default 0,
  add column comments_count integer not null default 0,
  add column updated_at timestamptz,
  add column resolved_at timestamptz;

-- relações de colunas
alter table public.posts
  add constraint posts_category_id_fkey
    foreign key (category_id) references public.problem_categories(id),
  add constraint posts_agency_id_fkey
    foreign key (agency_id) references public.public_agencies(id);

-- remoção de colunas
alter table public.posts
  drop column image_url;


-- atualização na tabela comments
-- renomeação de colunas
alter table public.comments
  rename column text to body;

-- adição de colunas
alter table public.comments
  add column parent_comment_id bigint,
  add column updated_at timestamptz;

-- relação de colunas
alter table public.comments
  add constraint comments_parent_comment_id_fkey
    foreign key (parent_comment_id) references public.comments(id);

-- remoção de colunas
alter table public.comments
  drop column reply;

