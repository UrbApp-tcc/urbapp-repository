grant select on table public.public_agencies to anon;
grant select, insert on table public.public_agencies to authenticated;
grant all on table public.public_agencies to service_role;

alter table public.public_agencies enable row level security;

drop policy if exists "Public agencies are viewable by everyone" on public.public_agencies;
create policy "Public agencies are viewable by everyone"
on public.public_agencies
for select
to anon, authenticated
using (true);

drop policy if exists "Authenticated users can create public agencies" on public.public_agencies;
create policy "Authenticated users can create public agencies"
on public.public_agencies
for insert
to authenticated
with check (true);

create or replace function public.create_public_agency_profile(
  target_city_id bigint,
  agency_name text,
  agency_type text,
  contact_email text
)
returns public.public_agencies
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  created_agency public.public_agencies%rowtype;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.';
  end if;

  if target_city_id is null then
    raise exception 'A cidade da secretaria é obrigatória.';
  end if;

  if trim(coalesce(agency_name, '')) = '' then
    raise exception 'O nome da secretaria/órgão é obrigatório.';
  end if;

  if trim(coalesce(agency_type, '')) = '' then
    raise exception 'O tipo da secretaria/órgão é obrigatório.';
  end if;

  if trim(coalesce(contact_email, '')) = '' then
    raise exception 'O e-mail institucional é obrigatório.';
  end if;

  insert into public.public_agencies (
    city_id,
    name,
    type,
    contact_email
  )
  values (
    target_city_id,
    trim(agency_name),
    trim(agency_type),
    lower(trim(contact_email))
  )
  returning * into created_agency;

  insert into public.agency_users (
    agency_id,
    user_id,
    role,
    is_active
  )
  values (
    created_agency.id,
    current_user_id,
    'admin',
    true
  )
  on conflict (agency_id, user_id) do update
  set role = excluded.role,
      is_active = true;

  return created_agency;
end;
$$;

grant execute on function public.create_public_agency_profile(bigint, text, text, text) to authenticated;
grant execute on function public.create_public_agency_profile(bigint, text, text, text) to service_role;
