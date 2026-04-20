insert into public.badges (name, slug, description, icon)
values
  (
    'UrbApp Bronze',
    'urbapp-bronze',
    'Insignia de teste bronze do UrbApp.',
    'tier:bronze'
  ),
  (
    'UrbApp Prata',
    'urbapp-prata',
    'Insignia de teste prata do UrbApp.',
    'tier:silver'
  ),
  (
    'UrbApp Ouro',
    'urbapp-ouro',
    'Insignia de teste ouro do UrbApp.',
    'tier:gold'
  ),
  (
    'UrbApp Diamante',
    'urbapp-diamante',
    'Insignia de teste diamante do UrbApp.',
    'tier:diamond'
  ),
  (
    'UrbApp Safira',
    'urbapp-safira',
    'Insignia de teste safira do UrbApp.',
    'tier:sapphire'
  )
on conflict (slug) do update
set
  name = excluded.name,
  description = excluded.description,
  icon = excluded.icon;

insert into public.user_badges (user_id, badge_id)
select
  profile.id,
  badge.id
from public.profiles profile
cross join public.badges badge
where badge.slug in (
  'urbapp-bronze',
  'urbapp-prata',
  'urbapp-ouro',
  'urbapp-diamante',
  'urbapp-safira'
)
on conflict (user_id, badge_id) do nothing;
