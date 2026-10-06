-- Nova ocorrência exige pelo menos uma foto e uma descrição de verdade.
--
-- A foto é enviada ao Storage ANTES de publicar (pasta `reports/pending/`),
-- e a publicação a vincula ao primeiro relato na mesma transação. Assim o
-- servidor consegue exigir a foto, em vez de depender só da tela
-- (spec §29.1: regras críticas não ficam apenas no frontend).
--
-- Relato adicional em ocorrência existente continua sem foto obrigatória:
-- a ocorrência já tem título, categoria, localização e foto original.

create or replace function public.publish_occurrence_report(
  target_city_id bigint,
  target_category_id bigint,
  report_title text,
  report_description text,
  report_latitude double precision,
  report_longitude double precision,
  report_street text,
  report_neighborhood text,
  report_anonymous boolean,
  report_photo_paths text[]
)
returns table (occurrence_id bigint, post_id bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  photo_path text;
  photo_position integer := 0;
  new_occurrence_id bigint;
  new_post_id bigint;
begin
  if current_user_id is null then
    raise exception 'Usuário autenticado é obrigatório.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(report_description, ''))) < 10 then
    raise exception 'A descrição deve ter pelo menos 10 caracteres.';
  end if;

  if report_photo_paths is null or cardinality(report_photo_paths) = 0 then
    raise exception 'Adicione pelo menos uma foto do problema.';
  end if;

  if cardinality(report_photo_paths) > 4 then
    raise exception 'Envie no máximo 4 fotos.';
  end if;

  if (select count(distinct path) from unnest(report_photo_paths) as path)
     <> cardinality(report_photo_paths) then
    raise exception 'A mesma foto foi enviada mais de uma vez.';
  end if;

  foreach photo_path in array report_photo_paths loop
    if photo_path is null or photo_path not like 'reports/pending/%' then
      raise exception 'Caminho de foto inválido.';
    end if;

    if not exists (
      select 1
      from storage.objects object
      where object.bucket_id = 'post-images'
        and object.name = photo_path
        and (object.owner = current_user_id or object.owner_id = current_user_id::text)
    ) then
      raise exception 'Não encontramos a foto enviada. Adicione-a novamente.';
    end if;
  end loop;

  select created.occurrence_id, created.post_id
    into new_occurrence_id, new_post_id
  from public.create_occurrence_report(
    target_city_id,
    target_category_id,
    report_title,
    report_description,
    report_latitude,
    report_longitude,
    report_street,
    report_neighborhood,
    coalesce(report_anonymous, false)
  ) as created;

  foreach photo_path in array report_photo_paths loop
    photo_position := photo_position + 1;
    insert into public.post_images (post_id, storage_path, position)
    values (new_post_id, photo_path, photo_position);
  end loop;

  return query select new_occurrence_id, new_post_id;
end;
$$;

revoke all on function public.publish_occurrence_report(
  bigint, bigint, text, text, double precision, double precision, text, text, boolean, text[]
) from public, anon, authenticated;

grant execute on function public.publish_occurrence_report(
  bigint, bigint, text, text, double precision, double precision, text, text, boolean, text[]
) to authenticated;

-- A função antiga não valida foto: deixa de ser chamável pelo cliente. Ela
-- segue disponível para as rotinas internas (seed, manutenção e a própria
-- publicação acima).
revoke execute on function public.create_occurrence_report(
  bigint, bigint, text, text, double precision, double precision, text, text, boolean
) from authenticated;
