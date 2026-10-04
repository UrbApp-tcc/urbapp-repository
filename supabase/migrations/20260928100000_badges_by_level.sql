alter table public.badges
    add column if not exists min_level integer references public.levels(level);
update public.badges
   set min_level = case slug
       when 'urbapp-bronze'   then 1
       when 'urbapp-prata'    then 2
       when 'urbapp-ouro'     then 3
       when 'urbapp-diamante' then 4
       when 'urbapp-safira'   then 5
   end
 where slug in ('urbapp-bronze', 'urbapp-prata', 'urbapp-ouro', 'urbapp-diamante', 'urbapp-safira');
create unique index if not exists badges_min_level_key
    on public.badges (min_level)
    where min_level is not null;
create or replace function public.grant_level_badges(
    p_user_id uuid,
    p_notify  boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_level integer;
    v_badge record;
begin
    select current_level into v_level from public.profiles where id = p_user_id;
    if v_level is null then
        return;
    end if;

    for v_badge in
        insert into public.user_badges (user_id, badge_id)
        select p_user_id, b.id
          from public.badges b
         where b.min_level is not null
           and b.min_level <= v_level
        on conflict (user_id, badge_id) do nothing
        returning badge_id
    loop
        if p_notify then
            perform public.notify_user(
                p_user_id,
                'badge_awarded',
                'Nova insígnia!',
                (select 'Você conquistou a insígnia "' || name || '".'
                   from public.badges where id = v_badge.badge_id),
                jsonb_build_object('badge_id', v_badge.badge_id)
            );
        end if;
    end loop;

    update public.profiles p
       set featured_badge_id = (
               select b.id
                 from public.user_badges ub
                 join public.badges b on b.id = ub.badge_id
                where ub.user_id = p_user_id
                order by b.min_level desc nulls last
                limit 1
           )
     where p.id = p_user_id
       and p.featured_badge_id is null;
end;
$$;
revoke all on function public.grant_level_badges(uuid, boolean) from public, anon, authenticated;
create or replace function public.trg_badges_on_level_up()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.current_level > coalesce(old.current_level, 0) then
        perform public.grant_level_badges(new.id, true);
    end if;
    return new;
end;
$$;
drop trigger if exists badges_on_level_up on public.profiles;
create trigger badges_on_level_up
after update of current_level on public.profiles
for each row
when (old.current_level is distinct from new.current_level)
execute function public.trg_badges_on_level_up();
create or replace function public.trg_badges_on_profile_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.grant_level_badges(new.id, false);
    return new;
end;
$$;
drop trigger if exists badges_on_profile_created on public.profiles;
create trigger badges_on_profile_created
after insert on public.profiles
for each row
execute function public.trg_badges_on_profile_created();
update public.profiles p
   set featured_badge_id = null
  from public.badges b
 where b.id = p.featured_badge_id
   and b.min_level is not null
   and b.min_level > p.current_level;
delete from public.user_badges ub
 using public.badges b, public.profiles p
 where ub.badge_id = b.id
   and ub.user_id = p.id
   and b.min_level is not null
   and b.min_level > p.current_level;
do $$
declare
    r record;
begin
    for r in select id from public.profiles loop
        perform public.grant_level_badges(r.id, false);
    end loop;
end;
$$;
