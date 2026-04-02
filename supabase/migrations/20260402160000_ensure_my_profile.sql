-- Garante linha em profiles para o usuário autenticado (contas sem trigger / dados antigos).
create or replace function public.ensure_my_profile()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    u record;
    metadata jsonb;
    requested_username text;
    resolved_username text;
    resolved_full_name text;
    resolved_avatar_url text;
begin
    if uid is null then
        raise exception 'not authenticated';
    end if;

    if exists (select 1 from public.profiles where id = uid) then
        return;
    end if;

    select * into u from auth.users where id = uid;
    if u.id is null then
        raise exception 'user not found in auth';
    end if;

    metadata := coalesce(u.raw_user_meta_data, '{}'::jsonb);
    requested_username := coalesce(
        nullif(trim(metadata ->> 'username'), ''),
        split_part(coalesce(u.email, ''), '@', 1),
        'user'
    );
    resolved_username := public.generate_unique_username(requested_username, u.id);
    resolved_full_name := coalesce(
        nullif(trim(metadata ->> 'full_name'), ''),
        nullif(trim(metadata ->> 'name'), ''),
        resolved_username
    );
    resolved_avatar_url := nullif(trim(metadata ->> 'avatar_url'), '');

    insert into public.profiles (id, full_name, username, avatar_url)
    values (u.id, resolved_full_name, resolved_username, resolved_avatar_url)
    on conflict (id) do nothing;
end;
$$;

grant execute on function public.ensure_my_profile() to authenticated;

-- Backfill: usuários em auth sem profile (uma vez).
insert into public.profiles (id, full_name, username, avatar_url)
select
    u.id,
    coalesce(
        nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
        nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
        public.generate_unique_username(
            coalesce(
                nullif(trim(u.raw_user_meta_data ->> 'username'), ''),
                split_part(coalesce(u.email, ''), '@', 1),
                'user'
            ),
            u.id
        )
    ),
    public.generate_unique_username(
        coalesce(
            nullif(trim(u.raw_user_meta_data ->> 'username'), ''),
            split_part(coalesce(u.email, ''), '@', 1),
            'user'
        ),
        u.id
    ),
    nullif(trim(u.raw_user_meta_data ->> 'avatar_url'), '')
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;
