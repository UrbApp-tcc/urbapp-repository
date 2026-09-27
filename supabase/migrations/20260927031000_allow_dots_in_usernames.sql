-- Permite identificadores institucionais como sec.mobilidade.sorocaba.sp.
create or replace function public.normalize_username(raw_username text)
returns text
language sql
immutable
as $$
  with normalized as (
    select coalesce(
      nullif(
        trim(
          both '._'
          from regexp_replace(
            lower(coalesce(raw_username, '')),
            '[^a-z0-9._]+',
            '_',
            'g'
          )
        ),
        ''
      ),
      'user'
    ) as value
  )
  select case
    when char_length(value) >= 3 then left(value, 48)
    else rpad(value, 3, 'x')
  end
  from normalized;
$$;

create or replace function public.generate_unique_username(
  base_username text,
  desired_id uuid default null
)
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
  candidate := left(normalized, 48);

  loop
    exit when not exists (
      select 1
      from public.profiles profile
      where lower(profile.username) = lower(candidate)
        and (desired_id is null or profile.id <> desired_id)
    );

    suffix := suffix + 1;
    candidate := left(
      normalized,
      greatest(1, 48 - length(suffix::text) - 1)
    ) || '_' || suffix;
  end loop;

  return candidate;
end;
$$;
