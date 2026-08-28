-- Unique-name Supabase tier for marketplace searchbar/autocomplete.
-- This is a derived cache from Oracle Postgres, not a marketplace replica.
-- One row represents one language-local search name and stores the card IDs
-- that should be hydrated from Oracle when the name is predicted.

create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

create or replace function public.marketplace_search_normalize(value text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(lower(extensions.unaccent(coalesce(value, ''))), '[^a-z0-9]+', ' ', 'g'));
$$;

create or replace function public.marketplace_search_compact(value text)
returns text
language sql
immutable
as $$
  select regexp_replace(lower(extensions.unaccent(coalesce(value, ''))), '[^a-z0-9]', '', 'g');
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

create table if not exists public.marketplace_card_name_tokens (
  language text not null default 'en',
  display_name text not null,
  canonical_name text not null,
  canonical_names text[] not null default '{}'::text[],
  search_name text not null,
  normalized_name text not null,
  compact_name text not null,
  name_tokens text[] not null default '{}'::text[],
  card_ids bigint[] not null default '{}'::bigint[],
  representative_labels jsonb not null default '[]'::jsonb,
  row_count integer not null default 0,
  search_weight real not null default 0,
  oracle_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (language, search_name),
  constraint marketplace_card_name_tokens_card_ids_not_empty
    check (cardinality(card_ids) = row_count and row_count > 0),
  constraint marketplace_card_name_tokens_labels_array
    check (jsonb_typeof(representative_labels) = 'array')
);

alter table public.marketplace_card_name_tokens enable row level security;

create index if not exists marketplace_card_name_tokens_prefix_idx
  on public.marketplace_card_name_tokens (
    language,
    compact_name text_pattern_ops,
    search_weight desc,
    row_count desc
  );

create index if not exists marketplace_card_name_tokens_tokens_idx
  on public.marketplace_card_name_tokens using gin (name_tokens);

create index if not exists marketplace_card_name_tokens_normalized_trgm_idx
  on public.marketplace_card_name_tokens using gin (normalized_name gin_trgm_ops);

create index if not exists marketplace_card_name_tokens_card_ids_idx
  on public.marketplace_card_name_tokens using gin (card_ids);
