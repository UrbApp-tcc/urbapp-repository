create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
    requested_username text := coalesce(
        nullif(trim(metadata ->> 'username'), ''),
        split_part(coalesce(new.email, ''), '@', 1),
        'user'
    );
    resolved_username text := public.generate_unique_username(requested_username, new.id);
    resolved_full_name text := coalesce(
        nullif(trim(metadata ->> 'full_name'), ''),
        nullif(trim(metadata ->> 'name'), ''),
        resolved_username
    );
    resolved_avatar_url text := nullif(trim(metadata ->> 'avatar_url'), '');
    resolved_city_id bigint := nullif(trim(metadata ->> 'city_id'), '')::bigint;
begin
    insert into public.profiles (
        id,
        city_id,
        full_name,
        username,
        avatar_url
    )
    values (
        new.id,
        resolved_city_id,
        resolved_full_name,
        resolved_username,
        resolved_avatar_url
    )
    on conflict (id) do nothing;

    return new;
end;
$$;
