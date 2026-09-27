-- Let the DB populate user_id from the authenticated session,
-- so clients never need to (and cannot spoof) the field.
alter table public.posts
  alter column user_id set default auth.uid();

alter table public.comments
  alter column user_id set default auth.uid();

-- Block status changes on posts that have already reached a final state.
create or replace function public.validate_post_status_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status in ('completed', 'closed', 'expired') then
    raise exception 'Reporte no estado "%" nao pode ter o status alterado.', old.status
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists check_post_status_transition on public.posts;

create trigger check_post_status_transition
before update of status on public.posts
for each row
when (new.status is distinct from old.status)
execute function public.validate_post_status_transition();
