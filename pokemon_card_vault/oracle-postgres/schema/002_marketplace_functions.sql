create or replace function public.marketplace_search_normalize(value text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]+', ' ', 'g'));
$$;

create or replace function public.marketplace_search_compact(value text)
returns text
language sql
immutable
as $$
  select regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]', '', 'g');
$$;

create or replace function public.marketplace_search_tokenize(value text)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(token order by token), '{}'::text[])
  from (
    select distinct token
    from regexp_split_to_table(public.marketplace_search_normalize(value), ' ') token
    where token <> ''
      and (length(token) >= 2 or token = 'v' or token ~ '^[0-9]+$')
  ) tokens;
$$;

create or replace function public.marketplace_edit_distance(left_text text, right_text text)
returns integer
language plpgsql
immutable
as $$
declare
  source text := coalesce(left_text, '');
  target text := coalesce(right_text, '');
  source_length integer := char_length(coalesce(left_text, ''));
  target_length integer := char_length(coalesce(right_text, ''));
  previous_row integer[];
  current_row integer[];
  source_index integer;
  target_index integer;
  cost integer;
begin
  if source = target then
    return 0;
  end if;
  if source_length = 0 then
    return target_length;
  end if;
  if target_length = 0 then
    return source_length;
  end if;

  previous_row := array(select generate_series(0, target_length));

  for source_index in 1..source_length loop
    current_row := array[source_index];
    for target_index in 1..target_length loop
      cost := case
        when substr(source, source_index, 1) = substr(target, target_index, 1) then 0
        else 1
      end;
      current_row := current_row || least(
        previous_row[target_index + 1] + 1,
        current_row[target_index] + 1,
        previous_row[target_index] + cost
      );
    end loop;
    previous_row := current_row;
  end loop;

  return previous_row[target_length + 1];
end;
$$;

create or replace function public.marketplace_seed_variations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  insert into public.marketplace_variations (
    variation_key, label, aliases, normalized_aliases, compact_aliases, updated_at
  )
  select
    source.variation_key,
    source.label,
    source.aliases,
    array(select public.marketplace_search_normalize(alias_value) from unnest(source.aliases) alias_value),
    array(select public.marketplace_search_compact(alias_value) from unnest(source.aliases) alias_value),
    now()
  from (
    values
      ('ex', 'ex', array['ex', 'e x']::text[]),
      ('v', 'V', array['v']::text[]),
      ('vmax', 'VMAX', array['vmax', 'v max']::text[]),
      ('vstar', 'VSTAR', array['vstar', 'v star']::text[]),
      ('gx', 'GX', array['gx', 'g x']::text[]),
      ('lvx', 'LV.X', array['lv.x', 'lv x', 'lvx', 'liv x', 'liv. x', 'level x', 'lv x.']::text[]),
      ('mega', 'Mega', array['mega']::text[]),
      ('delta', 'Delta Species', array['delta', 'delta species', 'δ', 'd species']::text[]),
      ('gold_star', 'Gold Star', array['gold star', 'goldstar', '☆']::text[]),
      ('shining', 'Shining', array['shining', 'shiny']::text[]),
      ('radiant', 'Radiant', array['radiant']::text[]),
      ('prime', 'Prime', array['prime']::text[]),
      ('break', 'BREAK', array['break']::text[]),
      ('tag_team', 'TAG TEAM', array['tag team', 'tagteam']::text[]),
      ('ace_spec', 'ACE SPEC', array['ace spec', 'acespec']::text[])
  ) as source(variation_key, label, aliases)
  on conflict (variation_key) do update set
    label = excluded.label,
    aliases = excluded.aliases,
    normalized_aliases = excluded.normalized_aliases,
    compact_aliases = excluded.compact_aliases,
    updated_at = now();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.marketplace_seed_expansion_aliases()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  insert into public.marketplace_expansion_aliases (
    alias,
    normalized_alias,
    compact_alias,
    expansion_name,
    normalized_expansion_name,
    source,
    priority,
    updated_at
  )
  select
    source.alias,
    source.normalized_alias,
    source.compact_alias,
    source.expansion_name,
    source.normalized_expansion_name,
    source.source,
    source.priority,
    now()
  from (
    select distinct on (normalized_alias, normalized_expansion_name)
      alias,
      normalized_alias,
      compact_alias,
      expansion_name,
      normalized_expansion_name,
      source,
      priority
    from (
      select
        raw.alias,
        public.marketplace_search_normalize(raw.alias) as normalized_alias,
        public.marketplace_search_compact(raw.alias) as compact_alias,
        raw.expansion_name,
        public.marketplace_search_normalize(raw.expansion_name) as normalized_expansion_name,
        raw.source,
        raw.priority
      from (
        select name as alias, name as expansion_name, 'expansion_name'::text as source, 300 as priority
        from public.cardtrader_pokemon_expansions
        where name <> ''
        union all
        select code as alias, name as expansion_name, 'cardtrader_code'::text as source, 160 as priority
        from public.cardtrader_pokemon_expansions
        where coalesce(code, '') <> ''
        union all
        select cardmarket_set_code as alias, expansion_name, 'cardmarket_set_code'::text as source, 140 as priority
        from public.marketplace_cm_expansion_parsing
        where coalesce(cardmarket_set_code, '') <> ''
          and coalesce(expansion_name, '') <> ''
          and confidence <> 'rejected'
        union all
        select cardtrader_expansion_code as alias, expansion_name, 'cardmarket_cardtrader_code'::text as source, 150 as priority
        from public.marketplace_cm_expansion_parsing
        where coalesce(cardtrader_expansion_code, '') <> ''
          and coalesce(expansion_name, '') <> ''
          and confidence <> 'rejected'
        union all
        select replace(cardmarket_expansion_slug, '-', ' ') as alias, expansion_name, 'cardmarket_slug'::text as source, 220 as priority
        from public.marketplace_cm_expansion_parsing
        where coalesce(cardmarket_expansion_slug, '') <> ''
          and coalesce(expansion_name, '') <> ''
          and confidence <> 'rejected'
        union all
        select *
        from (
          values
            ('col', 'Call of Legends', 'manual', 40),
            ('call legends', 'Call of Legends', 'manual', 80),
            ('call of legends', 'Call of Legends', 'manual', 20),
            ('hgss', 'HeartGold & SoulSilver', 'manual', 40),
            ('hgss', 'Unleashed', 'manual', 55),
            ('hgss', 'Undaunted', 'manual', 55),
            ('hgss', 'Triumphant', 'manual', 55),
            ('hgss', 'Call of Legends', 'manual', 70),
            ('heartgold', 'HeartGold & SoulSilver', 'manual', 60),
            ('heartgold', 'HeartGold Collection', 'manual', 65),
            ('heartgold', 'Unleashed', 'manual', 75),
            ('heartgold', 'Undaunted', 'manual', 75),
            ('heartgold', 'Triumphant', 'manual', 75),
            ('heartgold', 'Call of Legends', 'manual', 90),
            ('soulsilver', 'HeartGold & SoulSilver', 'manual', 60),
            ('soulsilver', 'SoulSilver Collection', 'manual', 65),
            ('soulsilver', 'Unleashed', 'manual', 75),
            ('soulsilver', 'Undaunted', 'manual', 75),
            ('soulsilver', 'Triumphant', 'manual', 75),
            ('soulsilver', 'Call of Legends', 'manual', 90),
            ('151', '151', 'manual', 20),
            ('151', 'Pokémon Card 151', 'manual', 25),
            ('151', 'Collect 151', 'manual', 25),
            ('pokemon 151', 'Pokémon Card 151', 'manual', 40),
            ('pokemon card 151', 'Pokémon Card 151', 'manual', 30),
            ('collect 151', 'Collect 151', 'manual', 30),
            ('cel', 'Celebrations', 'manual', 50),
            ('celebrations', 'Celebrations', 'manual', 20),
            ('pal', 'Paldea Evolved', 'manual', 60),
            ('obf', 'Obsidian Flames', 'manual', 60),
            ('obs', 'Obsidian Flames', 'manual', 80),
            ('svi', 'Scarlet & Violet', 'manual', 60),
            ('sv', 'Scarlet & Violet', 'manual', 90)
        ) as manual(alias, expansion_name, source, priority)
      ) raw(alias, expansion_name, source, priority)
      where raw.alias <> ''
        and raw.expansion_name <> ''
    ) normalized
    order by normalized_alias, normalized_expansion_name, priority
  ) source
  where source.alias <> ''
    and source.expansion_name <> ''
  on conflict (normalized_alias, normalized_expansion_name) do update set
    alias = excluded.alias,
    compact_alias = excluded.compact_alias,
    expansion_name = excluded.expansion_name,
    source = excluded.source,
    priority = least(public.marketplace_expansion_aliases.priority, excluded.priority),
    updated_at = now();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.marketplace_expansion_number_int(value text)
returns integer
language sql
immutable
as $$
  select nullif(
    coalesce(
      substring(coalesce(value, '') from '([0-9]{1,4})/[0-9]{1,4}'),
      substring(coalesce(value, '') from '([0-9]+)')
    ),
    ''
  )::integer;
$$;

create or replace function public.classify_marketplace_product_type(
  card_name text,
  expansion_name text default '',
  category_name text default '',
  blueprint_type text default '',
  card_number text default '',
  version text default '',
  blueprint_id bigint default null
)
returns text
language sql
immutable
as $$
  with normalized as (
    select
      lower(coalesce(card_name, '')) as name,
      lower(coalesce(expansion_name, '')) as expansion,
      lower(coalesce(category_name, '')) as category,
      lower(coalesce(blueprint_type, '')) as type,
      lower(coalesce(card_number, '')) as number,
      lower(coalesce(version, '')) as version_text,
      coalesce(blueprint_id::text, '') as id_text
  ),
  signals as (
    select
      *,
      nullif(trim(version_text), '') is not null as has_version,
      number ~ '^[0-9]{1,4}[a-z]?/[0-9]{1,4}' as has_collector_number,
      number = id_text or number ~ '^[0-9]{5,}$' as looks_like_blueprint_number,
      expansion ~ 'world championship decks|world championships .* deck' as is_championship_set
    from normalized
  )
  select case
    when has_collector_number
    then 'card'
    when name ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory)([^a-z0-9]|$)'
    then 'accessory'
    when name ~ '(^|[^a-z0-9])(booster box|display box|sealed box)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(booster box|display box|sealed box)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(booster box|display box|sealed box)([^a-z0-9]|$)'
    then 'booster_box'
    when name ~ '(^|[^a-z0-9])(booster bundle|bundle)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(booster bundle|bundle)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(booster bundle|bundle)([^a-z0-9]|$)'
    then 'booster_bundle'
    when name ~ '(^|[^a-z0-9])(booster|booster pack|pack)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(booster|booster pack|pack)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(booster|booster pack|pack)([^a-z0-9]|$)'
    then 'booster_pack'
    when name ~ '(^|[^a-z0-9])(elite trainer box|etb)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(elite trainer box|etb)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(elite trainer box|etb)([^a-z0-9]|$)'
    then 'elite_trainer_box'
    when name ~ '(^|[^a-z0-9])(tin|tins)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(tin|tins)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(tin|tins)([^a-z0-9]|$)'
    then 'tin'
    when name ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection|collector.?s? chest|empty mini|blister|case|toolkit|figure|pin)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection|collector.?s? chest|empty mini|blister|case|toolkit|figure|pin)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection|collector.?s? chest|empty mini|blister|case|toolkit|figure|pin)([^a-z0-9]|$)'
    then 'collection_box'
    when name ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
      or category ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(theme deck|starter deck|battle deck|deck)([^a-z0-9]|$)'
    then 'deck'
    when is_championship_set and not has_collector_number and (not has_version or looks_like_blueprint_number)
    then 'championship_deck'
    when (category ~ '(^|[^a-z0-9])(sealed|sealed product|product)([^a-z0-9]|$)'
      or type ~ '(^|[^a-z0-9])(sealed|sealed product|product)([^a-z0-9]|$)'
      or name ~ '(^|[^a-z0-9])(sealed product|sealed case|product)([^a-z0-9]|$)')
      and not has_collector_number
    then 'sealed_product'
    else 'card'
  end
  from signals;
$$;

create or replace function public.marketplace_palette_key(
  card_type text,
  card_name text,
  rarity text default '',
  tags text default ''
)
returns text
language sql
immutable
as $$
  with normalized as (
    select
      case
        when lower(coalesce(card_type, '')) in ('card', 'pokemon', 'pokémon', 'trading card', 'pokemon card', 'pokémon card') then ''
        else lower(coalesce(card_type, ''))
      end as direct,
      lower(concat_ws(' ', card_name, rarity, tags)) as text
  )
  select case
    when direct in ('fire', 'water', 'lightning', 'grass', 'psychic', 'fighting', 'darkness', 'metal', 'fairy', 'dragon', 'colorless') then direct
    when direct = 'dark' then 'darkness'
    when direct = 'electric' then 'lightning'
    when direct = 'steel' then 'metal'
    when direct = 'normal' then 'colorless'
    when text ~ '(electric|lightning|electrike|manectric|pikachu|raichu|zapdos|jolteon|luxio|luxray|mareep|flaaffy|ampharos|voltorb|electabuzz|heliolisk|helioptile|magnemite|magneton|magnezone)' then 'lightning'
    when text ~ '(water|squirtle|wartortle|blastoise|buizel|floatzel|kingler|krabby|vaporeon|gyarados|lapras|psyduck|golduck|totodile|croconaw|feraligatr|mudkip|marshtomp|swampert|piplup|prinplup|empoleon|oshawott|dewott|samurott|froakie|frogadier|greninja|sobble|drizzile|inteleon|quaxly|quaxwell|quaquaval)' then 'water'
    when text ~ '(fire|charmander|charmeleon|charizard|flareon|vulpix|ninetales|growlithe|arcanine|ponyta|rapidash|magmar|magmortar|moltres|cyndaquil|quilava|typhlosion|torchic|combusken|blaziken|chimchar|monferno|infernape|tepig|pignite|emboar|fennekin|braixen|delphox|litten|torracat|incineroar|scorbunny|raboot|cinderace|fuecoco|crocalor|skeledirge)' then 'fire'
    when text ~ '(grass|bulbasaur|ivysaur|venusaur|celebi|chikorita|bayleef|meganium|treecko|grovyle|sceptile|turtwig|grotle|torterra|snivy|servine|serperior|chespin|quilladin|chesnaught|rowlet|dartrix|decidueye|grookey|thwackey|rillaboom|sprigatito|floragato|meowscarada)' then 'grass'
    when text ~ '(psychic|mew|mewtwo|abra|kadabra|alakazam|kirlia|ralts|gardevoir|gallade|espeon|mr\. mime|mime jr|solosis|duosion|reuniclus)' then 'psychic'
    when text ~ '(fighting|rockruff|lycanroc|hawlucha|machop|machoke|machamp|lucario|riolu|hitmonlee|hitmonchan|hitmontop|makuhita|hariyama|meditite|medicham)' then 'fighting'
    when text ~ '(metal|steel|aggron|aron|lairon|steelix|scizor|skarmory|mawile|beldum|metang|metagross|dialga)' then 'metal'
    when text ~ '(fairy|alcremie|milcery|sylveon|clefairy|clefable|cleffa|jigglypuff|wigglytuff|igglybuff|togepi|togetic|togekiss|flabebe|floette|florges|comfey|ribombee|cutiefly)' then 'fairy'
    else direct
  end
  from normalized;
$$;

create or replace function public.marketplace_direct_palette_key(card_type text)
returns text
language sql
immutable
as $$
  with normalized as (
    select
      case
        when lower(coalesce(card_type, '')) in ('card', 'pokemon', 'pokémon', 'trading card', 'pokemon card', 'pokémon card') then ''
        else lower(coalesce(card_type, ''))
      end as direct
  )
  select case
    when direct in ('fire', 'water', 'lightning', 'grass', 'psychic', 'fighting', 'darkness', 'metal', 'fairy', 'dragon', 'colorless') then direct
    when direct = 'dark' then 'darkness'
    when direct = 'electric' then 'lightning'
    when direct = 'steel' then 'metal'
    when direct = 'normal' then 'colorless'
    else ''
  end
  from normalized;
$$;

create or replace function public.marketplace_seed_cards_type()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  seeded_count integer;
begin
  insert into public.cards_type (type_key, label, aliases, palette_key, sort_order, updated_at)
  values
    ('grass', 'Grass', array['leaf', 'plant'], 'grass', 10, now()),
    ('fire', 'Fire', array['flame'], 'fire', 20, now()),
    ('water', 'Water', array['ice', 'aqua'], 'water', 30, now()),
    ('lightning', 'Lightning', array['electric', 'thunder'], 'lightning', 40, now()),
    ('psychic', 'Psychic', array['ghost', 'mind'], 'psychic', 50, now()),
    ('fighting', 'Fighting', array['rock', 'ground'], 'fighting', 60, now()),
    ('darkness', 'Darkness', array['dark'], 'darkness', 70, now()),
    ('metal', 'Metal', array['steel'], 'metal', 80, now()),
    ('fairy', 'Fairy', array['sweet'], 'fairy', 90, now()),
    ('dragon', 'Dragon', array['drake'], 'dragon', 100, now()),
    ('colorless', 'Colorless', array['normal'], 'colorless', 110, now()),
    ('item', 'Item', array['goods', 'tool'], 'colorless', 200, now()),
    ('supporter', 'Supporter', array['trainer'], 'psychic', 210, now()),
    ('stadium', 'Stadium', array['arena'], 'metal', 220, now()),
    ('energy', 'Energy', array['basic energy', 'special energy'], 'lightning', 230, now())
  on conflict (type_key) do update set
    label = excluded.label,
    aliases = excluded.aliases,
    palette_key = excluded.palette_key,
    sort_order = excluded.sort_order,
    updated_at = now();

  get diagnostics seeded_count = row_count;
  return seeded_count;
end;
$$;

create or replace function public.marketplace_seed_cards_name_type()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  seeded_count integer;
begin
  perform public.marketplace_seed_cards_type();

  insert into public.cards_name_type (name, type_key, priority, source, updated_at)
  select distinct n.name, direct.type_key, 5, 'cardtrader-type', now()
  from public.cardtrader_pokemon_blueprints b
  join public.marketplace_card_names n on n.name = b.name
  join lateral (
    select public.marketplace_direct_palette_key(
      coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''))
    ) as type_key
  ) direct on direct.type_key <> ''
  join public.cards_type ct on ct.type_key = direct.type_key
  on conflict (name, type_key) do update set
    priority = least(public.cards_name_type.priority, excluded.priority),
    source = excluded.source,
    updated_at = now();

  insert into public.cards_name_type (name, type_key, priority, source, updated_at)
  select distinct n.name, direct.type_key, 30, 'trainer-type', now()
  from public.cardtrader_pokemon_blueprints b
  join public.marketplace_card_names n on n.name = b.name
  join lateral (
    select case
      when lower(concat_ws(' ', b.blueprint->>'card_type', b.blueprint->>'type', b.blueprint->>'category_name', b.name)) ~ 'supporter' then 'supporter'
      when lower(concat_ws(' ', b.blueprint->>'card_type', b.blueprint->>'type', b.blueprint->>'category_name', b.name)) ~ 'stadium' then 'stadium'
      when lower(concat_ws(' ', b.blueprint->>'card_type', b.blueprint->>'type', b.blueprint->>'category_name', b.name)) ~ 'energy' then 'energy'
      when lower(concat_ws(' ', b.blueprint->>'card_type', b.blueprint->>'type', b.blueprint->>'category_name', b.name)) ~ '(item|tool|goods)' then 'item'
      else ''
    end as type_key
  ) direct on direct.type_key <> ''
  on conflict (name, type_key) do update set
    priority = least(public.cards_name_type.priority, excluded.priority),
    source = excluded.source,
    updated_at = now();

  insert into public.cards_name_type (name, type_key, priority, source, updated_at)
  select distinct source.name, source.type_key, source.priority, 'seed-rule', now()
  from public.marketplace_card_names n
  join lateral (
    values
      ('water', 10, '(chien-pao|squirtle|wartortle|blastoise|buizel|floatzel|kingler|krabby|vaporeon|gyarados|lapras|psyduck|golduck|totodile|croconaw|feraligatr|mudkip|marshtomp|swampert|piplup|prinplup|empoleon|oshawott|dewott|samurott|froakie|frogadier|greninja|sobble|drizzile|inteleon|quaxly|quaxwell|quaquaval)'),
      ('darkness', 20, '(chien-pao|darkrai|umbreon|absol|zoroark|houndoom|houndour|sneasel|weavile|murkrow|honchkrow|poochyena|mightyena|yveltal)'),
      ('lightning', 10, '(electric|lightning|electrike|manectric|pikachu|raichu|zapdos|jolteon|luxio|luxray|mareep|flaaffy|ampharos|voltorb|electabuzz|heliolisk|helioptile|magnemite|magneton|magnezone|pawmot|pawmo|pawmi)'),
      ('fire', 10, '(charmander|charmeleon|charizard|flareon|vulpix|ninetales|growlithe|arcanine|ponyta|rapidash|magmar|magmortar|moltres|cyndaquil|quilava|typhlosion|torchic|combusken|blaziken|chimchar|monferno|infernape|tepig|pignite|emboar|fennekin|braixen|delphox|litten|torracat|incineroar|scorbunny|raboot|cinderace|fuecoco|crocalor|skeledirge)'),
      ('grass', 10, '(bulbasaur|ivysaur|venusaur|celebi|chikorita|bayleef|meganium|treecko|grovyle|sceptile|turtwig|grotle|torterra|snivy|servine|serperior|chespin|quilladin|chesnaught|rowlet|dartrix|decidueye|grookey|thwackey|rillaboom|sprigatito|floragato|meowscarada)'),
      ('psychic', 10, '(mewtwo|mew|abra|kadabra|alakazam|kirlia|ralts|gardevoir|gallade|espeon|mr\\. mime|mime jr|solosis|duosion|reuniclus|hatenna|hattrem|hatterene)'),
      ('fighting', 10, '(rockruff|lycanroc|hawlucha|machop|machoke|machamp|lucario|riolu|hitmonlee|hitmonchan|hitmontop|makuhita|hariyama|meditite|medicham|geodude|graveler|golem|onix|cubone|marowak)'),
      ('metal', 10, '(aggron|aron|lairon|steelix|scizor|skarmory|mawile|beldum|metang|metagross|dialga|meltan|melmetal|tinkatink|tinkatuff|tinkaton)'),
      ('fairy', 10, '(alcremie|milcery|sylveon|clefairy|clefable|cleffa|jigglypuff|wigglytuff|igglybuff|togepi|togetic|togekiss|flabebe|floette|florges|comfey|ribombee|cutiefly)'),
      ('dragon', 10, '(dratini|dragonair|dragonite|rayquaza|salamence|bagon|shelgon|gible|gabite|garchomp|axew|fraxure|haxorus|druddigon|deino|zweilous|hydreigon|goomy|sliggoo|goodra|jangmo-o|hakamo-o|kommo-o|duraludon|regidrago|frigibax|arctibax|baxcalibur)')
  ) as rule(type_key, priority, pattern) on lower(n.name) ~ rule.pattern
  cross join lateral (select n.name, rule.type_key, rule.priority) source
  on conflict (name, type_key) do update set
    priority = least(public.cards_name_type.priority, excluded.priority),
    source = excluded.source,
    updated_at = now();

  get diagnostics seeded_count = row_count;
  return seeded_count;
end;
$$;

create or replace function public.marketplace_name_palette_key(card_name text)
returns text
language sql
stable
set search_path = public
as $$
  select ct.palette_key
  from public.cards_name_type cnt
  join public.cards_type ct on ct.type_key = cnt.type_key
  where lower(cnt.name) = lower(coalesce(card_name, ''))
  order by cnt.priority asc, ct.sort_order asc, ct.type_key asc
  limit 1;
$$;

create or replace function public.marketplace_card_palette(
  card_type text,
  card_name text,
  rarity text default '',
  tags text default ''
)
returns jsonb
language sql
stable
as $$
  with key as (
    select coalesce(
      nullif(public.marketplace_direct_palette_key(card_type), ''),
      nullif(public.marketplace_name_palette_key(card_name), ''),
      nullif(public.marketplace_palette_key(card_type, card_name, rarity, tags), ''),
      'fallback'
    ) as value
  ),
  palette as (
    select
      value,
      case value
        when 'fire' then array['#FFFF6B3D', '#FFFFB020']
        when 'water' then array['#FF38BDF8', '#FF2563EB']
        when 'lightning' then array['#FFFDE047', '#FFF59E0B']
        when 'grass' then array['#FF34D399', '#FF65A30D']
        when 'psychic' then array['#FFA78BFA', '#FFEC4899']
        when 'fighting' then array['#FFB45309', '#FFEF4444']
        when 'darkness' then array['#FF64748B', '#FF111827']
        when 'metal' then array['#FFCBD5E1', '#FF64748B']
        when 'fairy' then array['#FFF9A8D4', '#FFC084FC']
        when 'dragon' then array['#FF818CF8', '#FFF59E0B']
        when 'colorless' then array['#FFE5E7EB', '#FF94A3B8']
        else array['#FF94A3B8', '#FF475569']
      end as type_gradient,
      case value
        when 'fire' then array['#FF4F292B', '#FF3C2D18']
        when 'water' then array['#FF18405F', '#FF0C1C45']
        when 'lightning' then array['#FF3A392B', '#FF3A2914']
        when 'grass' then array['#FF164745', '#FF1A2A14']
        when 'psychic' then array['#FF373260', '#FF381633']
        when 'fighting' then array['#FF3A231C', '#FF381520']
        when 'darkness' then array['#FF242C41', '#FF080C1A']
        when 'metal' then array['#FF313749', '#FF1A2030']
        when 'fairy' then array['#FF4E3B55', '#FF2E2349']
        when 'dragon' then array['#FF2C335F', '#FF3A2914']
        when 'colorless' then array['#FF363A4B', '#FF242A3A']
        else array['#FF31394D', '#FF141928']
      end as dark_surface_gradient,
      case value
        when 'fire' then array['#FFFFE7E0', '#FFFFF7E9']
        when 'water' then array['#FFDFF4FE', '#FFE9EFFD']
        when 'lightning' then array['#FFFFFFEA', '#FFFEF5E7']
        when 'grass' then array['#FFDFF8EF', '#FFF0F6E7']
        when 'psychic' then array['#FFF1ECFE', '#FFFDEDF5']
        when 'fighting' then array['#FFF3E3D8', '#FFFDECEC']
        when 'darkness' then array['#FFE6E9EC', '#FFE7E8E9']
        when 'metal' then array['#FFF9FAFC', '#FFF0F1F3']
        when 'fairy' then array['#FFFEF1F8', '#FFF9F3FF']
        when 'dragon' then array['#FFEBEDFE', '#FFFEF5E7']
        when 'colorless' then array['#FFFCFCFD', '#FFF4F6F8']
        else array['#FFEEF0F4', '#FFEDEEF0']
      end as light_surface_gradient,
      case value
        when 'fire' then '#FF8F4A24'
        when 'water' then '#FF155E9C'
        when 'lightning' then '#FF8A691B'
        when 'grass' then '#FF1F7A49'
        when 'psychic' then '#FF6D3D86'
        when 'fighting' then '#FF7F3028'
        when 'darkness' then '#FF303A52'
        when 'metal' then '#FF5A6378'
        when 'fairy' then '#FF7F5A9D'
        when 'dragon' then '#FF70613D'
        when 'colorless' then '#FF576174'
        else '#FF243E68'
      end as image_frame_color
    from key
  )
  select jsonb_build_object(
    'key', value,
    'typeGradient', type_gradient,
    'darkSurfaceGradient', dark_surface_gradient,
    'lightSurfaceGradient', light_surface_gradient,
    'imageFrameColor', image_frame_color
  )
  from palette;
$$;

create or replace function public.marketplace_card_emoji(
  card_type text,
  card_name text,
  rarity text default '',
  product_variant text default ''
)
returns text
language sql
immutable
as $$
  with normalized as (
    select
      coalesce(nullif(public.marketplace_palette_key(card_type, card_name, rarity, product_variant), ''), 'fallback') as palette_key,
      lower(concat_ws(' ', card_name, rarity, product_variant)) as text,
      lower(coalesce(card_name, '')) as name_text,
      abs(hashtext(lower(coalesce(card_name, '')))) as name_hash
  ),
  parts as (
    select
      case
        when text ~ '(zubat|golbat|crobat|noibat|noivern|woobat|swoobat)' then '🦇'
        when text ~ '(caterpie|metapod|butterfree|weedle|kakuna|beedrill|pinsir|scyther|scizor|heracross|yanma|yanmega|wurmple|silcoon|cascoon|beautifly|dustox|kricketot|kricketune|burmy|wormadam|mothim|combee|vespiquen|sewaddle|swadloon|leavanny|venipede|whirlipede|scolipede|dwebble|crustle|joltik|galvantula|larvesta|volcarona|grubbin|charjabug|vikavolt|cutiefly|ribombee|sizzlipede|centiskorch|tarountula|spidops|nymble|lokix|rellor|rabsca)' then '🐛'
        when text ~ '(ekans|arbok|seviper|snivy|servine|serperior|silicobra|sandaconda)' then '🐍'
        when text ~ '(magikarp|goldeen|seaking|qwilfish|remoraid|octillery|feebas|milotic|basculin|wishiwashi|bruxish|arrokuda|barraskewda|finizen|palafin|veluza|dondozo|chi-yu)' then '🐟'
        when text ~ '(squirtle|wartortle|blastoise|torkoal|turtwig|grotle|torterra|chewtle|drednaw)' then '🐢'
        when text ~ '(psyduck|golduck|farfetch|ducklett|swanna|quaxly|quaxwell|quaquaval)' then '🦆'
        when text ~ '(pidgey|pidgeotto|pidgeot|spearow|fearow|doduo|dodrio|hoothoot|noctowl|natu|xatu|taillow|swellow|wingull|pelipper|starly|staravia|staraptor|pidove|tranquill|unfezant|rufflet|braviary|fletchling|fletchinder|talonflame|pikipek|trumbeak|toucannon|rookidee|corvisquire|corviknight|cramorant|wattrel|kilowattrel|bombirdier|flamigo)' then '🪽'
        when text ~ '(meowth|persian|skitty|delcatty|glameow|purugly|purrloin|liepard|litten|torracat|incineroar|sprigatito|floragato|meowscarada)' then '🐱'
        when text ~ '(growlithe|arcanine|houndour|houndoom|poochyena|mightyena|rockruff|lycanroc|yamper|boltund|fidough|dachsbun|greavard|houndstone)' then '🐶'
        when text ~ '(pikachu|raichu|pichu|plusle|minun|pachirisu|emolga|dedenne|togedemaru|morpeko|pawmi|pawmo|pawmot)' then '🐭'
        when text ~ '(rattata|raticate|sentret|furret|zigzagoon|linoone|bidoof|bibarel|patrat|watchog|skwovet|greedent|lechonk|oinkologne)' then '🐾'
        when text ~ '(ponyta|rapidash|mudbray|mudsdale|glastrier|spectrier|koraidon|miraidon)' then '🐴'
        when text ~ '(mankey|primeape|aipom|ambipom|chimchar|monferno|infernape|panpour|simipour|pansage|simisage|pansear|simisear|grookey|thwackey|rillaboom|zarude)' then '🐵'
        when text ~ '(teddiursa|ursaring|cubchoo|beartic|stufful|bewear|ursaluna)' then '🐻'
        when text ~ '(eevee|vaporeon|jolteon|flareon|espeon|umbreon|leafeon|glaceon|sylveon|vulpix|ninetales|fennekin|braixen|delphox|nickit|thievul|zorua|zoroark|fennekin)' then '🦊'
        when text ~ '(charizard|charmander|charmeleon|dratini|dragonair|dragonite|rayquaza|salamence|bagon|shelgon|gible|gabite|garchomp|axew|fraxure|haxorus|druddigon|deino|zweilous|hydreigon|goomy|sliggoo|goodra|jangmo-o|hakamo-o|kommo-o|duraludon|dracozolt|dracovish|regidrago|frigibax|arctibax|baxcalibur)' then '🐉'
        when text ~ '(mewtwo|mew|abra|kadabra|alakazam|drowzee|hypno|mr\. mime|jynx|espeon|ralts|kirlia|gardevoir|gallade|solosis|duosion|reuniclus|gothita|gothorita|gothitelle|elgyem|beheeyem|hatenna|hattrem|hatterene)' then '🔮'
        when text ~ '(bulbasaur|ivysaur|venusaur|oddish|gloom|vileplume|bellsprout|weepinbell|victreebel|exeggcute|exeggutor|chikorita|bayleef|meganium|treecko|grovyle|sceptile|seedot|nuzleaf|shiftry|budew|roselia|roserade|cherubi|cherrim|carnivine|snover|abomasnow|petilil|lilligant|maractus|chespin|quilladin|chesnaught|bounsweet|steenee|tsareena|smoliv|dolliv|arboliva)' then '🌿'
        when text ~ '(diglett|dugtrio|sandshrew|sandslash|geodude|graveler|golem|onix|cubone|marowak|rhyhorn|rhydon|rhyperior|phanpy|donphan|larvitar|pupitar|tyranitar|nosepass|probopass|hippopotas|hippowdon|drilbur|excadrill|sandile|krokorok|krookodile|mudbray|mudsdale|silicobra|sandaconda|orthworm)' then '🪨'
        when text ~ '(gastly|haunter|gengar|misdreavus|mismagius|sableye|shuppet|banette|duskull|dusclops|dusknoir|drifloon|drifblim|spiritomb|litwick|lampent|chandelure|phantump|trevenant|pumpkaboo|gourgeist|mimikyu|sinistea|polteageist|dreepy|drakloak|dragapult|annihilape|greavard|houndstone)' then '👻'
        when text ~ '(muk|grimer|koffing|weezing|trubbish|garbodor|skrelp|dragalge|toxapex|mareanie|toxel|toxtricity|glimmet|glimmora)' then '☠️'
        when text ~ '(magnemite|magneton|magnezone|voltorb|electrode|beldum|metang|metagross|bronzor|bronzong|klink|klang|klinklang|honedge|doublade|aegislash|klefki|togedemaru|meltan|melmetal|cufant|copperajah|tinkatink|tinkatuff|tinkaton)' then '⚙️'
        when text ~ '(ditto|castform|rotom|unown|porygon|porygon2|porygon-z|smeargle|kecleon|zorua|zoroark|mimikyu)' then '🌀'
        when text ~ '(snorlax|munchlax|slaking|slakoth|vigoroth|komala|drowzee|hypno)' then '💤'
        when text ~ '(chansey|blissey|happiny|audino|alomomola|indeedee|clefairy|clefable|cleffa|igglybuff|jigglypuff|wigglytuff|togepi|togetic|togekiss)' then '💖'
        when text ~ '(articuno|zapdos|moltres|raikou|entei|suicune|lugia|ho-oh|celebi|groudon|kyogre|rayquaza|jirachi|deoxys|dialga|palkia|giratina|darkrai|shaymin|arceus|victini|reshiram|zekrom|kyurem|xerneas|yveltal|zygarde|diancie|hoopa|volcanion|cosmog|cosmoem|solgaleo|lunala|necrozma|zacian|zamazenta|eternatus|calyrex|miraidon|koraidon)' then '🌟'
        else ''
      end as pokemon_emoji_a,
      case
        when text ~ '(zubat|golbat|crobat|noibat|noivern|woobat|swoobat)' then '🌙'
        when text ~ '(caterpie|metapod|butterfree|weedle|kakuna|beedrill|pinsir|scyther|scizor|heracross|yanma|yanmega|wurmple|silcoon|cascoon|beautifly|dustox|kricketot|kricketune|burmy|wormadam|mothim|combee|vespiquen|sewaddle|swadloon|leavanny|venipede|whirlipede|scolipede|dwebble|crustle|joltik|galvantula|larvesta|volcarona|grubbin|charjabug|vikavolt|cutiefly|ribombee|sizzlipede|centiskorch|tarountula|spidops|nymble|lokix|rellor|rabsca)' then '🪽'
        when text ~ '(ekans|arbok|seviper|snivy|servine|serperior|silicobra|sandaconda)' then '🌿'
        when text ~ '(magikarp|goldeen|seaking|qwilfish|remoraid|octillery|feebas|milotic|basculin|wishiwashi|bruxish|arrokuda|barraskewda|finizen|palafin|veluza|dondozo|chi-yu)' then '🌊'
        when text ~ '(meowth|persian|skitty|delcatty|glameow|purugly|purrloin|liepard|litten|torracat|incineroar|sprigatito|floragato|meowscarada)' then '✨'
        when text ~ '(growlithe|arcanine|houndour|houndoom|poochyena|mightyena|rockruff|lycanroc|yamper|boltund|fidough|dachsbun|greavard|houndstone)' then '🐾'
        when text ~ '(pikachu|raichu|pichu|plusle|minun|pachirisu|emolga|dedenne|togedemaru|morpeko|pawmi|pawmo|pawmot)' then '⚡'
        when text ~ '(eevee|vaporeon|jolteon|flareon|espeon|umbreon|leafeon|glaceon|sylveon|vulpix|ninetales|fennekin|braixen|delphox|nickit|thievul|zorua|zoroark)' then '✨'
        when text ~ '(charizard|charmander|charmeleon|dratini|dragonair|dragonite|rayquaza|salamence|bagon|shelgon|gible|gabite|garchomp|axew|fraxure|haxorus|druddigon|deino|zweilous|hydreigon|goomy|sliggoo|goodra|jangmo-o|hakamo-o|kommo-o|duraludon|dracozolt|dracovish|regidrago|frigibax|arctibax|baxcalibur)' then '🔥'
        when text ~ '(gastly|haunter|gengar|misdreavus|mismagius|sableye|shuppet|banette|duskull|dusclops|dusknoir|drifloon|drifblim|spiritomb|litwick|lampent|chandelure|phantump|trevenant|pumpkaboo|gourgeist|mimikyu|sinistea|polteageist|dreepy|drakloak|dragapult|annihilape|greavard|houndstone)' then '🌫️'
        when text ~ '(muk|grimer|koffing|weezing|trubbish|garbodor|skrelp|dragalge|toxapex|mareanie|toxel|toxtricity|glimmet|glimmora)' then '🧪'
        when text ~ '(snorlax|munchlax|slaking|slakoth|vigoroth|komala|drowzee|hypno)' then '🌙'
        when text ~ '(chansey|blissey|happiny|audino|alomomola|indeedee|clefairy|clefable|cleffa|igglybuff|jigglypuff|wigglytuff|togepi|togetic|togekiss)' then '✨'
        else ''
      end as pokemon_emoji_b,
      case
        when text ~ '(promo|stamped|stamp)' then '🎟️'
        when text ~ '(special illustration rare|special art rare|illustration rare|art rare|alternate art|alt art|full[- ]?art)' then '🎨'
        when text ~ '(gold secret|secret rare|hyper rare|gold)' then '🏆'
        when text ~ '(holo|foil|reverse)' then '✨'
        when text ~ '(^|[^a-z0-9])(vmax|v max)([^a-z0-9]|$)' then '👑'
        when text ~ '(^|[^a-z0-9])(vstar|v star)([^a-z0-9]|$)' then '🌟'
        when text ~ '(^|[^a-z0-9])(gx|g x)([^a-z0-9]|$)' then '💥'
        when text ~ '(^|[^a-z0-9])(ex|e x)([^a-z0-9]|$)' then '💎'
        when text ~ '(^|[^a-z0-9])(lv\.?x|lv x|level x)([^a-z0-9]|$)' then '⬆️'
        when text ~ '(^|[^a-z0-9])v([^a-z0-9]|$)' then '🛡️'
        when text ~ '(gold star|goldstar)' then '🌟'
        when text ~ '(shining|shiny)' then '✨'
        when text ~ '(radiant)' then '🌈'
        when text ~ '(mega)' then '🔺'
        when text ~ '(delta)' then '🔻'
        when text ~ '(tag team|tagteam)' then '🤝'
        when text ~ '(prime)' then '🏅'
        when text ~ '(^|[^a-z0-9])break([^a-z0-9]|$)' then '⚡'
        when text ~ '(^|[^a-z0-9])rare([^a-z0-9]|$)' then '⭐'
        when text ~ '(^|[^a-z0-9])uncommon([^a-z0-9]|$)' then '🔷'
        when text ~ '(^|[^a-z0-9])common([^a-z0-9]|$)' then '⚪'
        else ''
      end as variant_emoji
    from normalized
  )
  select concat_ws(' ', nullif(pokemon_emoji_a, ''), nullif(pokemon_emoji_b, ''), nullif(variant_emoji, ''))
  from parts;
$$;

create or replace function public.marketplace_card_name_emoji(card_name text)
returns text
language sql
immutable
as $$
  select public.marketplace_card_emoji('', card_name, '', '');
$$;

create or replace function public.marketplace_card_variant_emoji(
  card_name text default '',
  rarity text default '',
  product_variant text default ''
)
returns text
language sql
immutable
as $$
  with normalized as (
    select lower(concat_ws(' ', card_name, rarity, product_variant)) as text
  )
  select case
    when text ~ '(promo|stamped|stamp)' then '🎟️'
    when text ~ '(special illustration rare|special art rare|illustration rare|art rare|alternate art|alt art|full[- ]?art)' then '🎨'
    when text ~ '(gold secret|secret rare|hyper rare|gold)' then '🏆'
    when text ~ '(holo|foil|reverse)' then '✨'
    when text ~ '(^|[^a-z0-9])(vmax|v max)([^a-z0-9]|$)' then '👑'
    when text ~ '(^|[^a-z0-9])(vstar|v star)([^a-z0-9]|$)' then '🌟'
    when text ~ '(^|[^a-z0-9])(gx|g x)([^a-z0-9]|$)' then '💥'
    when text ~ '(^|[^a-z0-9])(ex|e x)([^a-z0-9]|$)' then '💎'
    when text ~ '(^|[^a-z0-9])(lv\.?x|lv x|level x)([^a-z0-9]|$)' then '⬆️'
    when text ~ '(^|[^a-z0-9])v([^a-z0-9]|$)' then '🛡️'
    when text ~ '(gold star|goldstar)' then '🌟'
    when text ~ '(shining|shiny)' then '✨'
    when text ~ '(radiant)' then '🌈'
    when text ~ '(mega)' then '🔺'
    when text ~ '(delta)' then '🔻'
    when text ~ '(tag team|tagteam)' then '🤝'
    when text ~ '(prime)' then '🏅'
    when text ~ '(^|[^a-z0-9])break([^a-z0-9]|$)' then '⚡'
    when text ~ '(^|[^a-z0-9])rare([^a-z0-9]|$)' then '⭐'
    when text ~ '(^|[^a-z0-9])uncommon([^a-z0-9]|$)' then '🔷'
    when text ~ '(^|[^a-z0-9])common([^a-z0-9]|$)' then '⚪'
    else ''
  end
  from normalized;
$$;

create or replace function public.refresh_marketplace_cards_from_blueprints()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  alter table public.cardtrader_pokemon_blueprints
    add column if not exists emoji text not null default '';

  alter table public.marketplace_cards
    add column if not exists product_variant text not null default '';
  alter table public.marketplace_cards
    add column if not exists card_palette jsonb not null default '{}'::jsonb;
  alter table public.marketplace_cards
    add column if not exists emoji text not null default '';
  perform public.marketplace_seed_cards_type();

  alter table public.marketplace_card_names
    add column if not exists emoji text not null default '';

  insert into public.marketplace_card_names (name, normalized_name, compact_name, emoji, name_tokens, updated_at)
  select
    name,
    public.marketplace_search_normalize(name),
    public.marketplace_search_compact(name),
    public.marketplace_card_name_emoji(name),
    public.marketplace_search_tokenize(name),
    now()
  from (select distinct name from public.cardtrader_pokemon_blueprints where name <> '') source
  on conflict (name) do update set
    normalized_name = excluded.normalized_name,
    compact_name = excluded.compact_name,
    emoji = excluded.emoji,
    name_tokens = excluded.name_tokens,
    updated_at = now();

  perform public.marketplace_seed_cards_name_type();

  update public.cardtrader_pokemon_blueprints b
  set
    card_palette = public.marketplace_card_palette(
      coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
      b.name,
      coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
      concat_ws(' ', coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'), b.version)
    ),
    emoji = concat_ws(
      ' ',
      nullif(n.emoji, ''),
      public.marketplace_card_variant_emoji(
        b.name,
        coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
        b.version
      )
    )
  from public.marketplace_card_names n
  where n.name = b.name;

  insert into public.marketplace_cards (
    card_id, name, version, product_variant, image_url, cdn_image_url, preview_image_url,
    set_name, rarity, card_type, card_number, is_holo, is_foil,
    imported_at, projected_at, item_kind, product_type, trainer_name, card_palette, emoji
  )
  select
    source.id,
    source.name,
    source.version,
    case when source.product_type = 'card' then '' else coalesce(source.version, '') end,
    source.image_url,
    source.cdn_image_url,
    source.preview_image_url,
    source.set_name,
    source.rarity,
    source.card_type,
    case when source.product_type = 'card' then coalesce(source.explicit_card_number, source.version, source.id::text) else coalesce(source.explicit_card_number, '') end,
    lower(coalesce(source.rarity, '')) like '%holo%',
    lower(coalesce(source.rarity, '')) like '%holo%',
    source.imported_at,
    now(),
    case when source.product_type = 'card' then 'single' else 'product' end,
    source.product_type,
    source.trainer_name,
    source.card_palette,
    source.emoji
  from (
    select
      b.id,
      b.name,
      b.version,
      b.image_url,
      b.cdn_image_url,
      b.preview_image_url,
      coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon') as set_name,
      coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card') as rarity,
      coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card') as card_type,
      coalesce(nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', '')) as explicit_card_number,
      public.classify_marketplace_product_type(
        b.name,
        coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'),
        b.blueprint->>'category_name',
        b.blueprint->>'type',
        coalesce(nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, b.id::text),
        b.version,
        b.id
      ) as product_type,
      coalesce(nullif(b.blueprint->>'trainer_name', ''), '') as trainer_name,
      public.marketplace_card_palette(
        coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
        b.name,
        coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
        concat_ws(' ', coalesce(nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', ''), 'Pokemon'), b.version)
      ) as card_palette,
      coalesce(
        nullif(b.emoji, ''),
        public.marketplace_card_emoji(
          coalesce(nullif(b.blueprint->>'card_type', ''), nullif(b.blueprint->>'type', ''), nullif(b.blueprint->>'category_name', ''), 'Trading card'),
          b.name,
          coalesce(nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), 'Card'),
          b.version
        )
      ) as emoji,
      b.imported_at
    from public.cardtrader_pokemon_blueprints b
  ) source
  where coalesce(source.preview_image_url, source.cdn_image_url, source.image_url) is not null
  on conflict (card_id) do update set
    name = excluded.name,
    version = excluded.version,
    product_variant = excluded.product_variant,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    set_name = excluded.set_name,
    rarity = excluded.rarity,
    card_type = excluded.card_type,
    card_number = excluded.card_number,
    is_holo = excluded.is_holo,
    is_foil = excluded.is_foil,
    imported_at = excluded.imported_at,
    projected_at = now(),
    item_kind = excluded.item_kind,
    product_type = excluded.product_type,
    trainer_name = excluded.trainer_name,
    card_palette = excluded.card_palette,
    emoji = excluded.emoji;

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.refresh_marketplace_search_candidates()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  alter table public.marketplace_search_candidates
    add column if not exists product_variant text not null default '';
  alter table public.marketplace_search_candidates
    add column if not exists card_palette jsonb not null default '{}'::jsonb;
  alter table public.marketplace_search_candidates
    add column if not exists emoji text not null default '';

  insert into public.marketplace_search_candidates (
    card_id, name, set_name, card_number, product_variant, rarity, card_type, item_kind,
    product_type, trainer_name, image_url, cdn_image_url, preview_image_url,
    card_palette, emoji, search_text, name_prefix, set_prefix, expansion_name, search_weight,
    imported_at, projected_at
  )
  select
    c.card_id,
    c.name,
    c.set_name,
    c.card_number,
    c.product_variant,
    c.rarity,
    c.card_type,
    c.item_kind,
    c.product_type,
    c.trainer_name,
    c.image_url,
    c.cdn_image_url,
    c.preview_image_url,
    c.card_palette,
    c.emoji,
    lower(concat_ws(' ', c.name, c.set_name, c.card_number, c.product_variant, c.rarity, c.card_type, c.item_kind, c.product_type, c.trainer_name, array_to_string(coalesce(t.aliases, '{}'::text[]), ' '))),
    left(public.marketplace_search_compact(c.name), 3),
    left(public.marketplace_search_compact(c.set_name), 3),
    public.marketplace_search_normalize(c.set_name),
    (
      case when c.item_kind = 'product' then 12 else 0 end +
      case when c.rarity ilike '%rare%' then 8 else 0 end +
      case when c.name ~* '(^|[^a-z0-9])(ex|vmax|vstar|gx|lv\.x)([^a-z0-9]|$)' then 10 else 0 end +
      case when c.card_number ~ '/' then 10 else 0 end +
      case when c.trainer_name <> '' then 6 else 0 end +
      case when c.preview_image_url is not null then 4 else 0 end
    )::numeric,
    c.imported_at,
    now()
  from public.marketplace_cards c
  left join public.marketplace_trainers t on lower(t.trainer_name) = lower(c.trainer_name)
  where coalesce(c.preview_image_url, c.cdn_image_url, c.image_url) is not null
  on conflict (card_id) do update set
    name = excluded.name,
    set_name = excluded.set_name,
    card_number = excluded.card_number,
    product_variant = excluded.product_variant,
    rarity = excluded.rarity,
    card_type = excluded.card_type,
    item_kind = excluded.item_kind,
    product_type = excluded.product_type,
    trainer_name = excluded.trainer_name,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    card_palette = excluded.card_palette,
    emoji = excluded.emoji,
    search_text = excluded.search_text,
    name_prefix = excluded.name_prefix,
    set_prefix = excluded.set_prefix,
    expansion_name = excluded.expansion_name,
    search_weight = excluded.search_weight,
    imported_at = excluded.imported_at,
    projected_at = now();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.refresh_marketplace_card_versions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  alter table public.marketplace_card_versions
    add column if not exists product_variant text not null default '';
  alter table public.marketplace_card_versions
    add column if not exists card_palette jsonb not null default '{}'::jsonb;
  alter table public.marketplace_card_versions
    add column if not exists emoji text not null default '';

  insert into public.marketplace_card_versions (
    card_id,
    name,
    expansion_name,
    expansion_number,
    expansion_number_int,
    product_variant,
    blueprint_id,
    image_url,
    cdn_image_url,
    preview_image_url,
    product_type,
    trainer_name,
    card_palette,
    emoji,
    projected_at
  )
  select
    c.card_id,
    c.name,
    c.set_name,
    c.card_number,
    public.marketplace_expansion_number_int(c.card_number),
    c.product_variant,
    c.card_id,
    c.image_url,
    c.cdn_image_url,
    c.preview_image_url,
    c.product_type,
    c.trainer_name,
    c.card_palette,
    c.emoji,
    now()
  from public.marketplace_cards c
  where coalesce(c.preview_image_url, c.cdn_image_url, c.image_url) is not null
  on conflict (card_id) do update set
    name = excluded.name,
    expansion_name = excluded.expansion_name,
    expansion_number = excluded.expansion_number,
    expansion_number_int = excluded.expansion_number_int,
    product_variant = excluded.product_variant,
    blueprint_id = excluded.blueprint_id,
    image_url = excluded.image_url,
    cdn_image_url = excluded.cdn_image_url,
    preview_image_url = excluded.preview_image_url,
    product_type = excluded.product_type,
    trainer_name = excluded.trainer_name,
    card_palette = excluded.card_palette,
    emoji = excluded.emoji,
    projected_at = now();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

create or replace function public.refresh_marketplace_token_search_index()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  refreshed_count integer;
begin
  perform public.marketplace_seed_variations();

  alter table public.marketplace_card_names
    add column if not exists emoji text not null default '';

  insert into public.marketplace_card_names (name, normalized_name, compact_name, emoji, name_tokens, updated_at)
  select
    name,
    public.marketplace_search_normalize(name),
    public.marketplace_search_compact(name),
    public.marketplace_card_name_emoji(name),
    public.marketplace_search_tokenize(name),
    now()
  from (select distinct name from public.marketplace_search_candidates where name <> '') source
  on conflict (name) do update set
    normalized_name = excluded.normalized_name,
    compact_name = excluded.compact_name,
    emoji = excluded.emoji,
    name_tokens = excluded.name_tokens,
    updated_at = now();

  insert into public.marketplace_rarities (rarity, normalized_rarity, compact_rarity, rarity_tokens, updated_at)
  select rarity, public.marketplace_search_normalize(rarity), public.marketplace_search_compact(rarity), public.marketplace_search_tokenize(rarity), now()
  from (select distinct rarity from public.marketplace_search_candidates where rarity <> '') source
  on conflict (rarity) do update set
    normalized_rarity = excluded.normalized_rarity,
    compact_rarity = excluded.compact_rarity,
    rarity_tokens = excluded.rarity_tokens,
    updated_at = now();

  insert into public.marketplace_expansion_numbers (card_number, number_int, normalized_number, compact_number, number_tokens, updated_at)
  select card_number, public.marketplace_expansion_number_int(card_number), public.marketplace_search_normalize(card_number), public.marketplace_search_compact(card_number), public.marketplace_search_tokenize(card_number), now()
  from (select distinct card_number from public.marketplace_search_candidates where card_number <> '') source
  on conflict (card_number) do update set
    number_int = excluded.number_int,
    normalized_number = excluded.normalized_number,
    compact_number = excluded.compact_number,
    number_tokens = excluded.number_tokens,
    updated_at = now();

  delete from public.marketplace_card_variations;

  insert into public.marketplace_card_variations (
    card_id, variation_key, label, source_text, updated_at
  )
  select distinct
    c.card_id,
    v.variation_key,
    v.label,
    source.source_text,
    now()
  from public.marketplace_search_candidates c
  cross join lateral (
    select
      public.marketplace_search_normalize(concat_ws(' ', c.name, c.rarity, c.card_type, c.product_variant)) as normalized_text,
      public.marketplace_search_compact(concat_ws(' ', c.name, c.rarity, c.card_type, c.product_variant)) as compact_text,
      concat_ws(' ', c.name, c.rarity, c.card_type, c.product_variant) as source_text
  ) source
  join public.marketplace_variations v
    on exists (
      select 1
      from unnest(v.normalized_aliases, v.compact_aliases) as alias_pair(normalized_alias, compact_alias)
      where (
        (
          alias_pair.normalized_alias <> ''
          and source.normalized_text ~ ('(^|[^a-z0-9])' || regexp_replace(alias_pair.normalized_alias, '([\\^$.|?*+()\\[\\]{}])', '\\\1', 'g') || '([^a-z0-9]|$)')
        )
        or (
          length(alias_pair.compact_alias) >= 2
          and source.compact_text like '%' || alias_pair.compact_alias || '%'
        )
      )
    )
  on conflict (card_id, variation_key) do update set
    label = excluded.label,
    source_text = excluded.source_text,
    updated_at = now();

  insert into public.cardtrader_pokemon_expansions (
    expansion_id, game_id, code, name, normalized_name, compact_name, name_tokens, updated_at
  )
  select
    max(b.expansion_id),
    max(b.game_id),
    max(nullif(b.expansion->>'code', '')),
    source.set_name,
    public.marketplace_search_normalize(source.set_name),
    public.marketplace_search_compact(source.set_name),
    public.marketplace_search_tokenize(source.set_name),
    now()
  from (select distinct set_name from public.marketplace_search_candidates where set_name <> '') source
  left join public.cardtrader_pokemon_blueprints b
    on public.marketplace_search_normalize(coalesce(b.expansion->>'name', b.blueprint->>'expansion_name', '')) = public.marketplace_search_normalize(source.set_name)
  group by source.set_name
  on conflict (normalized_name) do update set
    expansion_id = coalesce(public.cardtrader_pokemon_expansions.expansion_id, excluded.expansion_id),
    code = coalesce(public.cardtrader_pokemon_expansions.code, excluded.code),
    name = excluded.name,
    compact_name = excluded.compact_name,
    name_tokens = excluded.name_tokens,
    updated_at = now();

  perform public.marketplace_seed_expansion_aliases();

  get diagnostics refreshed_count = row_count;
  return refreshed_count;
end;
$$;

