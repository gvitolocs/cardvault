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

create table if not exists public.marketplace_card_names_en (
  language text not null default 'en',
  name text primary key references public.marketplace_card_names(name) on delete cascade,
  localized_name text not null,
  normalized_name text not null,
  compact_name text not null,
  name_tokens text[] not null default '{}'::text[],
  source text not null default 'fixture',
  source_card_id text,
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_card_names_it (like public.marketplace_card_names_en including all);
create table if not exists public.marketplace_card_names_fr (like public.marketplace_card_names_en including all);
create table if not exists public.marketplace_card_names_de (like public.marketplace_card_names_en including all);
create table if not exists public.marketplace_card_names_es (like public.marketplace_card_names_en including all);
create table if not exists public.marketplace_card_names_pt (like public.marketplace_card_names_en including all);
create table if not exists public.marketplace_card_names_ja (like public.marketplace_card_names_en including all);
create table if not exists public.marketplace_card_names_zh_cn (like public.marketplace_card_names_en including all);
create table if not exists public.marketplace_card_names_zh_tw (like public.marketplace_card_names_en including all);

create index if not exists marketplace_card_names_en_normalized_trgm_idx
  on public.marketplace_card_names_en using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_en_compact_idx
  on public.marketplace_card_names_en (compact_name);

create index if not exists marketplace_card_names_it_normalized_trgm_idx
  on public.marketplace_card_names_it using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_it_compact_idx
  on public.marketplace_card_names_it (compact_name);

create index if not exists marketplace_card_names_fr_normalized_trgm_idx
  on public.marketplace_card_names_fr using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_fr_compact_idx
  on public.marketplace_card_names_fr (compact_name);

create index if not exists marketplace_card_names_de_normalized_trgm_idx
  on public.marketplace_card_names_de using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_de_compact_idx
  on public.marketplace_card_names_de (compact_name);

create index if not exists marketplace_card_names_es_normalized_trgm_idx
  on public.marketplace_card_names_es using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_es_compact_idx
  on public.marketplace_card_names_es (compact_name);

create index if not exists marketplace_card_names_pt_normalized_trgm_idx
  on public.marketplace_card_names_pt using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_pt_compact_idx
  on public.marketplace_card_names_pt (compact_name);

create index if not exists marketplace_card_names_ja_normalized_trgm_idx
  on public.marketplace_card_names_ja using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_ja_compact_idx
  on public.marketplace_card_names_ja (compact_name);

create index if not exists marketplace_card_names_zh_cn_normalized_trgm_idx
  on public.marketplace_card_names_zh_cn using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_zh_cn_compact_idx
  on public.marketplace_card_names_zh_cn (compact_name);

create index if not exists marketplace_card_names_zh_tw_normalized_trgm_idx
  on public.marketplace_card_names_zh_tw using gin (normalized_name gin_trgm_ops);
create index if not exists marketplace_card_names_zh_tw_compact_idx
  on public.marketplace_card_names_zh_tw (compact_name);

create or replace function public.marketplace_card_names_for_language(search_language text default 'en')
returns table (
  language text,
  name text,
  localized_name text,
  normalized_name text,
  compact_name text,
  name_tokens text[],
  source text,
  source_card_id text,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with normalized as (
    select case
      when lower(coalesce(nullif(search_language, ''), 'en')) in ('it', 'fr', 'de', 'es', 'pt', 'ja', 'zh-cn', 'zh-tw')
        then lower(coalesce(nullif(search_language, ''), 'en'))
      else 'en'
    end as language
  ),
  selected as (
    select n.* from normalized l join public.marketplace_card_names_en n on l.language = 'en'
    union all
    select n.* from normalized l join public.marketplace_card_names_it n on l.language = 'it'
    union all
    select n.* from normalized l join public.marketplace_card_names_fr n on l.language = 'fr'
    union all
    select n.* from normalized l join public.marketplace_card_names_de n on l.language = 'de'
    union all
    select n.* from normalized l join public.marketplace_card_names_es n on l.language = 'es'
    union all
    select n.* from normalized l join public.marketplace_card_names_pt n on l.language = 'pt'
    union all
    select n.* from normalized l join public.marketplace_card_names_ja n on l.language = 'ja'
    union all
    select n.* from normalized l join public.marketplace_card_names_zh_cn n on l.language = 'zh-cn'
    union all
    select n.* from normalized l join public.marketplace_card_names_zh_tw n on l.language = 'zh-tw'
  )
  select * from selected
  union all
  select en.*
  from normalized l
  join public.marketplace_card_names_en en on l.language <> 'en'
  where not exists (
    select 1
    from selected s
    where s.name = en.name
  );
$$;
