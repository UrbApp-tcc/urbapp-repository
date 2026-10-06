-- Corrige a acentuação da notificação de pontos e dos registros já enviados.

create or replace function public.award_points(
  target_user_id uuid,
  points integer,
  source_type text,
  source_id bigint,
  send_notification boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  created_transaction_id bigint;
  resulting_points bigint;
begin
  if target_user_id is null or coalesce(points, 0) = 0 then
    return false;
  end if;

  insert into public.xp_transactions (
    user_id,
    source_type,
    source_id,
    xp_delta,
    points_delta
  )
  values (target_user_id, source_type, source_id, 0, points)
  on conflict do nothing
  returning id into created_transaction_id;

  if created_transaction_id is null then
    return false;
  end if;

  update public.profiles
  set current_points = greatest(current_points + points, 0)
  where id = target_user_id
  returning current_points into resulting_points;

  if send_notification and points > 0 then
    perform public.notify_user(
      target_user_id,
      'points_awarded',
      'Você ganhou pontos',
      format('+%s pontos por uma contribuição útil.', points),
      jsonb_build_object(
        'points', points,
        'source_type', source_type,
        'source_id', source_id,
        'current_points', resulting_points
      )
    );
  end if;

  return true;
end;
$$;

revoke all on function public.award_points(uuid, integer, text, bigint, boolean)
  from public, anon, authenticated;

update public.notifications
set title = 'Você ganhou pontos',
    body = replace(body, 'contribuicao util', 'contribuição útil')
where type = 'points_awarded'
  and title = 'Voce ganhou pontos';
