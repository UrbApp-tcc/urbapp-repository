create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    legacy_user_id bigint unique references public.users(id) on delete set null,
    city_id bigint references public.cities(id),
    full_name text not null,
    username text not null,
    avatar_url text,
    verified boolean not null default false,
    current_xp integer not null default 0,
    current_level integer not null default 1,
    current_points bigint not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint profiles_username_min_length check (char_length(trim(username)) >= 3)
);

create unique index profiles_username_key on public.profiles (lower(username));
create index profiles_city_id_idx on public.profiles (city_id);

alter table public.profiles enable row level security;

create or replace function public.normalize_username(raw_username text)
returns text
language sql
immutable
as $$
  with normalized as (
    select coalesce(
      nullif(
        trim(
          both '_'
          from regexp_replace(lower(coalesce(raw_username, '')), '[^a-z0-9_]+', '_', 'g')
        ),
        ''
      ),
      'user'
    ) as value
  )
  select case
    when char_length(value) >= 3 then value
    else rpad(value, 3, 'x')
  end
  from normalized;
$$;

create or replace function public.generate_unique_username(base_username text, desired_id uuid default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    normalized text := public.normalize_username(base_username);
    candidate text;
    suffix integer := 0;
begin
    candidate := left(normalized, 24);

    if candidate = '' then
        candidate := 'user';
    end if;

    loop
        exit when not exists (
            select 1
            from public.profiles profile
            where lower(profile.username) = lower(candidate)
              and (desired_id is null or profile.id <> desired_id)
        );

        suffix := suffix + 1;
        candidate := left(normalized, greatest(1, 24 - length(suffix::text) - 1)) || '_' || suffix;
    end loop;

    return candidate;
end;
$$;

create or replace function public.handle_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists set_profiles_updated_at on public.profiles;

create trigger set_profiles_updated_at
before update on public.profiles
for each row
execute function public.handle_profile_updated_at();

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
begin
    insert into public.profiles (
        id,
        full_name,
        username,
        avatar_url
    )
    values (
        new.id,
        resolved_full_name,
        resolved_username,
        resolved_avatar_url
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

drop policy if exists "Profiles are viewable by everyone" on public.profiles;

create policy "Profiles are viewable by everyone"
on public.profiles
for select
to anon, authenticated
using (true);

drop policy if exists "Users can insert their own profile" on public.profiles;

create policy "Users can insert their own profile"
on public.profiles
for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.profiles;

create policy "Users can update their own profile"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);
