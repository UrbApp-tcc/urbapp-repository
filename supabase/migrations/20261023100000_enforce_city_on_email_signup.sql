-- O cadastro por e-mail passa a exigir cidade também no backend.
-- A migration 20260428212000 lia `city_id` dos metadados, mas aceitava a conta
-- sem ela: um cadastro feito direto pela API criava perfil sem cidade.
--
-- Provedores OAuth (Google) não enviam metadados próprios no cadastro; essas
-- contas continuam sendo criadas sem cidade e o app pede a escolha no primeiro
-- acesso. Contas criadas pelo superusuário sem `provider` (seed e testes)
-- seguem a regra antiga.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    metadata jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
    signup_provider text := coalesce(new.raw_app_meta_data ->> 'provider', '');
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
    if signup_provider = 'email' then
        if resolved_city_id is null then
            raise exception 'Selecione a sua cidade para concluir o cadastro.'
                using errcode = '23502';
        end if;

        if not exists (select 1 from public.cities city where city.id = resolved_city_id) then
            raise exception 'Cidade não encontrada.'
                using errcode = '23503';
        end if;
    end if;

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
