-- Lista quais reportes estão aguardando validação (para os cartões do app).
-- ---------------------------------------------------------------------
create or replace function public.get_awaiting_validation_post_ids(p_post_ids bigint[])
returns setof bigint
language sql
stable
security definer
set search_path = public
as $$
    select distinct post_id
      from public.post_resolution_requests
     where status = 'pending'
       and post_id = any(p_post_ids)
$$;

revoke all on function public.get_awaiting_validation_post_ids(bigint[]) from public, anon;
grant execute on function public.get_awaiting_validation_post_ids(bigint[]) to authenticated;