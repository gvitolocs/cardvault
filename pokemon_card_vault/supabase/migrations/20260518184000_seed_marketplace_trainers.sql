insert into public.marketplace_trainers (trainer_name, aliases)
values
  ('Cynthia', array['Camilla', 'Shirona', 'C']),
  ('Lance', array['Camus']),
  ('Misty', array['Ondine', 'Kasumi']),
  ('Brock', array['Pierre', 'Takeshi']),
  ('Clair', array['Sandra']),
  ('Steven', array['Rochard']),
  ('Lillie', array['Lilia']),
  ('Gladion', array['Gladio']),
  ('Marnie', array['Mary']),
  ('Leon', array['Dandel']),
  ('Raihan', array['Roy']),
  ('Iono', array['Kissara']),
  ('N', array[]::text[]),
  ('Erika', array[]::text[]),
  ('Giovanni', array[]::text[]),
  ('Sabrina', array[]::text[]),
  ('Iris', array[]::text[]),
  ('Diantha', array[]::text[]),
  ('Hop', array[]::text[]),
  ('Nemona', array[]::text[]),
  ('Peonia', array[]::text[])
on conflict (trainer_name) do update set
  aliases = excluded.aliases,
  updated_at = now();

create or replace function public.extract_marketplace_trainer_name(item_name text)
returns text
language sql
immutable
as $$
  with normalized as (
    select trim(coalesce(item_name, '')) as name
  ),
  candidate as (
    select case
      when name ~* '^(Cynthia|Lance|Misty|Brock|Clair|Steven|Lillie|Gladion|Marnie|Leon|Raihan|Iono|N|Erika|Giovanni|Sabrina|Iris|Diantha|Hop|Nemona|Peonia)''s[[:space:]]+.+$'
      then nullif(trim((regexp_match(name, '^(Cynthia|Lance|Misty|Brock|Clair|Steven|Lillie|Gladion|Marnie|Leon|Raihan|Iono|N|Erika|Giovanni|Sabrina|Iris|Diantha|Hop|Nemona|Peonia)''s[[:space:]]+.+$', 'i'))[1]), '')
      when name ~* '(^|[[:space:]])C([[:space:]]+LV\.[0-9X]+|$)'
      then 'Cynthia'
      else ''
    end as trainer_name
    from normalized
  )
  select coalesce(trainer_name, '')
  from candidate;
$$;

update public.marketplace_cards c
set trainer_name = public.extract_marketplace_trainer_name(c.name)
where c.trainer_name is distinct from public.extract_marketplace_trainer_name(c.name);

update public.marketplace_card_versions v
set trainer_name = public.extract_marketplace_trainer_name(v.name)
where v.trainer_name is distinct from public.extract_marketplace_trainer_name(v.name);

insert into public.marketplace_trainers (trainer_name, aliases)
select distinct trainer_name, '{}'::text[]
from public.marketplace_cards
where trainer_name <> ''
on conflict (trainer_name) do nothing;
