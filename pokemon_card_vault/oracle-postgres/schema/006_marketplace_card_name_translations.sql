create table if not exists public.marketplace_card_name_translations (
  language text not null,
  name text not null references public.marketplace_card_names(name) on delete cascade,
  localized_name text not null,
  normalized_localized_name text not null,
  compact_localized_name text not null,
  localized_name_tokens text[] not null default '{}'::text[],
  source text not null default 'tcgdex',
  source_card_id text,
  updated_at timestamptz not null default now(),
  primary key (language, name)
);

create index if not exists marketplace_card_name_translations_language_normalized_trgm_idx
  on public.marketplace_card_name_translations using gin (normalized_localized_name gin_trgm_ops);

create index if not exists marketplace_card_name_translations_language_compact_idx
  on public.marketplace_card_name_translations (language, compact_localized_name);

create index if not exists marketplace_card_name_translations_name_idx
  on public.marketplace_card_name_translations (name);
