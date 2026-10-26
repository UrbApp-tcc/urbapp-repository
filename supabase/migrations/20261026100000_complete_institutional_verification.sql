-- Verificação institucional completa para a administração do UrbApp
-- (spec §3.5, §19 e §40):
--   * fila única de pedidos (órgão, gestão e vereador) com os dados do pedido,
--     de quem pediu e o contexto para decidir; também lista o histórico;
--   * rejeição exige motivo, que é enviado ao solicitante;
--   * quem pediu não revisa o próprio pedido (antifraude);
--   * o solicitante é notificado da decisão.
-- As funções de revisão são recriadas a partir da definição vigente
-- (20261005016000); o comportamento de aprovação não muda.

create or replace function public.get_institutional_verification_requests(
  review_status text default 'pending',
  page_size integer default 50,
  page_offset integer default 0
)
returns table (
  request_type text,
  request_id bigint,
  status text,
  city_id bigint,
  city_name text,
  display_name text,
  agency_type text,
  requester_role text,
  party text,
  mandate_starts_on date,
  mandate_ends_on date,
  institutional_email text,
  proof_summary text,
  proof_links text,
  requester_user_id uuid,
  requester_name text,
  requester_username text,
  requester_account_email text,
  requester_since timestamptz,
  previous_requests integer,
  previous_rejections integer,
  existing_profile_status text,
  created_at timestamptz,
  reviewed_at timestamptz,
  reviewer_name text,
  review_notes text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin(auth.uid()) then
    raise exception 'Apenas administradores podem consultar verificações institucionais.'
      using errcode = '42501';
  end if;

  if review_status not in ('pending', 'reviewed') then
    raise exception 'Filtro de verificação inválido.';
  end if;

  return query
  with requests as (
    select
      request.request_kind as request_type,
      request.id as request_id,
      request.status,
      request.city_id,
      request.agency_name as display_name,
      request.agency_type,
      request.requester_role,
      null::text as party,
      null::date as mandate_starts_on,
      null::date as mandate_ends_on,
      request.institutional_email,
      request.proof_summary,
      request.proof_links,
      request.requester_user_id,
      request.created_at,
      request.reviewed_at,
      request.reviewed_by,
      request.review_notes
    from public.agency_profile_requests request
    union all
    select
      'councilor',
      request.id,
      request.status,
      request.city_id,
      request.public_name,
      null,
      null,
      request.party,
      request.mandate_starts_on,
      request.mandate_ends_on,
      request.institutional_email,
      request.proof_summary,
      request.proof_links,
      request.requester_user_id,
      request.created_at,
      request.reviewed_at,
      request.reviewed_by,
      request.review_notes
    from public.councilor_profile_requests request
  ),
  history as (
    select
      requests.requester_user_id,
      requests.request_type,
      requests.request_id,
      requests.status
    from requests
  )
  select
    requests.request_type,
    requests.request_id,
    requests.status,
    requests.city_id,
    city.name::text,
    requests.display_name,
    requests.agency_type,
    requests.requester_role,
    requests.party,
    requests.mandate_starts_on,
    requests.mandate_ends_on,
    requests.institutional_email,
    requests.proof_summary,
    requests.proof_links,
    requests.requester_user_id,
    requester.full_name,
    requester.username,
    account.email::text,
    account.created_at,
    (
      select count(*)::integer from history
      where history.requester_user_id = requests.requester_user_id
        and (history.request_type, history.request_id) <> (requests.request_type, requests.request_id)
    ),
    (
      select count(*)::integer from history
      where history.requester_user_id = requests.requester_user_id
        and (history.request_type, history.request_id) <> (requests.request_type, requests.request_id)
        and history.status = 'rejected'
    ),
    case requests.request_type
      when 'agency' then (
        select agency.profile_status
        from public.public_agencies agency
        where agency.city_id = requests.city_id
          and lower(agency.name) = lower(requests.display_name)
        limit 1
      )
      when 'administration' then (
        select case when exists (
          select 1 from public.administration_users member
          where member.administration_id = administration.id
            and member.is_active
        ) then 'participant' else 'unclaimed' end
        from public.municipal_administrations administration
        where administration.city_id = requests.city_id
          and administration.starts_on <= current_date
          and (administration.ends_on is null or administration.ends_on >= current_date)
        order by administration.starts_on desc
        limit 1
      )
      else (
        select councilor.profile_status
        from public.councilor_profiles councilor
        where councilor.profile_id = requests.requester_user_id
      )
    end,
    requests.created_at,
    requests.reviewed_at,
    reviewer.full_name,
    requests.review_notes
  from requests
  join public.cities city on city.id = requests.city_id
  left join public.profiles requester on requester.id = requests.requester_user_id
  left join auth.users account on account.id = requests.requester_user_id
  left join public.profiles reviewer on reviewer.id = requests.reviewed_by
  where (review_status = 'pending' and requests.status = 'pending')
     or (review_status = 'reviewed' and requests.status in ('approved', 'rejected'))
  order by
    case when review_status = 'pending' then requests.created_at end asc,
    requests.reviewed_at desc nulls last,
    requests.request_id desc
  limit least(greatest(coalesce(page_size, 50), 1), 200)
  offset greatest(coalesce(page_offset, 0), 0);
end;
$$;

revoke all on function public.get_institutional_verification_requests(text, integer, integer) from public, anon;
grant execute on function public.get_institutional_verification_requests(text, integer, integer) to authenticated;

-- Regras comuns da decisão; levanta exceção quando a revisão não é permitida.
create or replace function public.assert_institutional_review_allowed(
  reviewer_id uuid,
  requester_id uuid,
  decision text,
  notes text
)
returns void
language plpgsql
stable
set search_path = public
as $$
begin
  if requester_id = reviewer_id then
    raise exception 'Você não pode revisar a sua própria solicitação.'
      using errcode = '42501';
  end if;

  if decision = 'rejected' and char_length(trim(coalesce(notes, ''))) < 10 then
    raise exception 'Informe o motivo da rejeição (pelo menos 10 caracteres).';
  end if;
end;
$$;

revoke all on function public.assert_institutional_review_allowed(uuid, uuid, text, text) from public, anon, authenticated;

create or replace function public.notify_institutional_review(
  request_type text,
  request_id bigint,
  requester_id uuid,
  profile_name text,
  city_name text,
  decision text,
  notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_notes text := nullif(trim(coalesce(notes, '')), '');
  kind_label text := case request_type
    when 'councilor' then 'perfil de vereador'
    when 'administration' then 'acesso à gestão municipal'
    else 'perfil de órgão municipal'
  end;
begin
  perform public.notify_user(
    requester_id,
    'institutional_review',
    case when decision = 'approved'
      then 'Perfil institucional aprovado'
      else 'Solicitação institucional não aprovada'
    end,
    case when decision = 'approved'
      then format('Seu pedido de %s (%s · %s) foi aprovado. As funções institucionais já estão disponíveis.',
                  kind_label, profile_name, city_name)
      else format('Seu pedido de %s (%s · %s) não foi aprovado. Motivo: %s',
                  kind_label, profile_name, city_name, clean_notes)
    end,
    jsonb_build_object(
      'request_type', request_type,
      'request_id', request_id,
      'decision', decision,
      'profile_name', profile_name,
      'city_name', city_name,
      'review_notes', clean_notes
    )
  );
end;
$$;

revoke all on function public.notify_institutional_review(text, bigint, uuid, text, text, text, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.review_agency_profile_request(target_request_id bigint, decision text, notes text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    raise exception 'Decisão inválida.';
  end if;

  select * into target_request
  from public.agency_profile_requests request
  where request.id = target_request_id
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'Solicitação pendente não encontrada.';
  end if;

  perform public.assert_institutional_review_allowed(
    current_user_id, target_request.requester_user_id, decision, notes
  );

  update public.agency_profile_requests
  set status = decision,
      review_notes = nullif(trim(coalesce(notes, '')), ''),
      reviewed_at = now(),
      reviewed_by = current_user_id
  where id = target_request.id;

  if decision = 'approved' then
    if target_request.request_kind = 'administration' then
      select administration.id into resolved_profile_id
      from public.municipal_administrations administration
      where administration.city_id = target_request.city_id
        and administration.starts_on <= current_date
        and (administration.ends_on is null or administration.ends_on >= current_date)
      order by administration.starts_on desc
      limit 1;

      if resolved_profile_id is null then
        raise exception 'A cidade não possui gestão municipal vigente.';
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
    else
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
    end if;
  end if;

  perform public.notify_institutional_review(
    target_request.request_kind,
    target_request.id,
    target_request.requester_user_id,
    target_request.agency_name,
    (select city.name from public.cities city where city.id = target_request.city_id),
    decision,
    notes
  );

  return resolved_profile_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_councilor_profile_request(target_request_id bigint, decision text, notes text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  current_user_id uuid := auth.uid();
  target_request public.councilor_profile_requests%rowtype;
  resolved_profile_id bigint;
begin
  if not public.is_platform_admin(current_user_id) then
    raise exception 'Apenas administradores podem revisar vereadores.' using errcode = '42501';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Decisão inválida.';
  end if;

  select * into target_request
  from public.councilor_profile_requests request
  where request.id = target_request_id
    and request.status = 'pending'
  for update;

  if not found then
    raise exception 'Solicitação pendente não encontrada.';
  end if;

  perform public.assert_institutional_review_allowed(
    current_user_id, target_request.requester_user_id, decision, notes
  );

  update public.councilor_profile_requests
  set status = decision,
      review_notes = nullif(trim(coalesce(notes, '')), ''),
      reviewed_at = now(),
      reviewed_by = current_user_id
  where id = target_request.id;

  if decision = 'approved' then
    insert into public.councilor_profiles (
      profile_id,
      city_id,
      public_name,
      party,
      mandate_starts_on,
      mandate_ends_on,
      profile_status,
      verified_at
    )
    values (
      target_request.requester_user_id,
      target_request.city_id,
      target_request.public_name,
      target_request.party,
      target_request.mandate_starts_on,
      target_request.mandate_ends_on,
      'participant',
      now()
    )
    on conflict (profile_id) do update
      set city_id = excluded.city_id,
          public_name = excluded.public_name,
          party = excluded.party,
          mandate_starts_on = excluded.mandate_starts_on,
          mandate_ends_on = excluded.mandate_ends_on,
          profile_status = 'participant',
          verified_at = now(),
          updated_at = now()
    returning id into resolved_profile_id;
  end if;

  perform public.notify_institutional_review(
    'councilor',
    target_request.id,
    target_request.requester_user_id,
    target_request.public_name,
    (select city.name from public.cities city where city.id = target_request.city_id),
    decision,
    notes
  );

  return resolved_profile_id;
end;
$function$;
