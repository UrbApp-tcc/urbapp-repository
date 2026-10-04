-- Solicitação e aprovação de acesso à gestão municipal vigente.

alter table public.agency_profile_requests
  add column if not exists request_kind text not null default 'agency';

alter table public.agency_profile_requests
  drop constraint if exists agency_profile_requests_kind_check;
alter table public.agency_profile_requests
  add constraint agency_profile_requests_kind_check
  check (request_kind in ('agency', 'administration'));

create or replace function public.create_institutional_profile_request(
  target_city_id bigint,
  institution_name text,
  institution_type text,
  institutional_email text,
  requester_role text default null,
  proof_summary text default null,
  proof_links text default null,
  request_kind text default 'agency'
)
returns public.agency_profile_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  created_request public.agency_profile_requests%rowtype;
begin
  if current_user_id is null then
    raise exception 'Usuario autenticado e obrigatorio.' using errcode = '42501';
  end if;

  if request_kind not in ('agency', 'administration') then
    raise exception 'Tipo de perfil institucional invalido.';
  end if;

  if target_city_id is null
     or not exists (select 1 from public.cities city where city.id = target_city_id) then
    raise exception 'A cidade da solicitacao e obrigatoria.';
  end if;

  if char_length(trim(coalesce(institution_name, ''))) < 3 then
    raise exception 'Informe o nome da instituicao.';
  end if;

  if char_length(trim(coalesce(institution_type, ''))) < 3 then
    raise exception 'Informe o tipo da instituicao.';
  end if;

  if position('@' in coalesce(institutional_email, '')) = 0 then
    raise exception 'Informe um e-mail institucional valido.';
  end if;

  if char_length(trim(coalesce(proof_summary, ''))) < 3 then
    raise exception 'Descreva as provas institucionais para analise.';
  end if;

  if exists (
    select 1
    from public.agency_profile_requests request
    where request.requester_user_id = current_user_id
      and request.city_id = target_city_id
      and request.request_kind = create_institutional_profile_request.request_kind
      and request.status = 'pending'
  ) then
    raise exception 'Ja existe uma solicitacao institucional pendente para esta cidade.';
  end if;

  insert into public.agency_profile_requests (
    requester_user_id,
    city_id,
    agency_name,
    agency_type,
    institutional_email,
    requester_role,
    proof_summary,
    proof_links,
    request_kind
  )
  values (
    current_user_id,
    target_city_id,
    trim(institution_name),
    trim(institution_type),
    lower(trim(institutional_email)),
    nullif(trim(coalesce(requester_role, '')), ''),
    trim(proof_summary),
    nullif(trim(coalesce(proof_links, '')), ''),
    request_kind
  )
  returning * into created_request;

  return created_request;
end;
$$;

create or replace function public.review_agency_profile_request(
  target_request_id bigint,
  decision text,
  notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_request public.agency_profile_requests%rowtype;
  resolved_profile_id bigint;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores podem revisar perfis institucionais.'
      using errcode = '42501';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Decisao invalida.';
  end if;

  select * into target_request
  from public.agency_profile_requests request
  where request.id = target_request_id
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'Solicitacao pendente nao encontrada.';
  end if;

  update public.agency_profile_requests
  set status = decision,
      review_notes = nullif(trim(coalesce(notes, '')), ''),
      reviewed_at = now(),
      reviewed_by = current_user_id
  where id = target_request.id;

  if decision = 'rejected' then
    return null;
  end if;

  if target_request.request_kind = 'administration' then
    select administration.id into resolved_profile_id
    from public.municipal_administrations administration
    where administration.city_id = target_request.city_id
      and administration.starts_on <= current_date
      and (administration.ends_on is null or administration.ends_on >= current_date)
    order by administration.starts_on desc
    limit 1;

    if resolved_profile_id is null then
      raise exception 'A cidade nao possui gestao municipal vigente.';
    end if;

    insert into public.administration_users (
      administration_id,
      user_id,
      role,
      is_active
    )
    values (
      resolved_profile_id,
      target_request.requester_user_id,
      'agent',
      true
    )
    on conflict (administration_id, user_id) do update
      set role = excluded.role,
          is_active = true;

    return resolved_profile_id;
  end if;

  insert into public.public_agencies (
    city_id,
    name,
    type,
    contact_email,
    profile_status,
    verified_at,
    claimed_at
  )
  values (
    target_request.city_id,
    target_request.agency_name,
    target_request.agency_type,
    lower(target_request.institutional_email),
    'participant',
    now(),
    now()
  )
  on conflict (city_id, name) do update
    set type = excluded.type,
        contact_email = excluded.contact_email,
        profile_status = 'participant',
        verified_at = now(),
        claimed_at = coalesce(public.public_agencies.claimed_at, now())
  returning id into resolved_profile_id;

  insert into public.agency_users (agency_id, user_id, role, is_active)
  values (resolved_profile_id, target_request.requester_user_id, 'admin', true)
  on conflict (agency_id, user_id) do update
    set role = 'admin',
        is_active = true;

  return resolved_profile_id;
end;
$$;

revoke all on function public.create_institutional_profile_request(
  bigint, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_institutional_profile_request(
  bigint, text, text, text, text, text, text, text
) to authenticated;

revoke all on function public.review_agency_profile_request(bigint, text, text)
  from public, anon, authenticated;
grant execute on function public.review_agency_profile_request(bigint, text, text)
  to authenticated;

grant execute on function public.rollover_municipal_administration(
  bigint, text, text, date, date
) to authenticated;

notify pgrst, 'reload schema';
