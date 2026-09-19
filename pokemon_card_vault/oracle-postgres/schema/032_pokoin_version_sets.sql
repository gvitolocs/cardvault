-- 032: CardTrader version-set key on the main candidate table.
-- One pokoin_version_sets row per same-card illustration group.
-- marketplace_search_candidates.version is that key. Do not store sibling
-- id arrays on the candidate row.

create table if not exists public.pokoin_version_sets (
  version text primary key,
  gameplay_name text not null default '',
  member_count integer not null default 1,
  source text not null default 'singleton',
  updated_at timestamptz not null default now()
);

alter table public.marketplace_search_candidates
  add column if not exists version text;

create index if not exists marketplace_search_candidates_version_idx
  on public.marketplace_search_candidates (version);

create or replace function public.pokoin_version_assign()
returns trigger
language plpgsql
as $$
begin
  if new.version is null or new.version = '' then
    new.version := 'v' || new.card_id::text;
  end if;
  insert into public.pokoin_version_sets (version, gameplay_name, member_count, source)
  values (new.version, coalesce(new.name, ''), 1, 'singleton')
  on conflict (version) do nothing;
  return new;
end;
$$;

drop trigger if exists pokoin_version_assign_trg on public.marketplace_search_candidates;
create trigger pokoin_version_assign_trg
before insert on public.marketplace_search_candidates
for each row
execute function public.pokoin_version_assign();

create or replace function public.pokoin_version_sets_recount()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' and old.version is not distinct from new.version then
    return new;
  end if;
  if tg_op in ('UPDATE', 'DELETE') and old.version is not null then
    update public.pokoin_version_sets
       set member_count = (
             select count(*)::integer
               from public.marketplace_search_candidates
              where version = old.version
           ),
           updated_at = now()
     where version = old.version;
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.version is not null then
    update public.pokoin_version_sets
       set member_count = (
             select count(*)::integer
               from public.marketplace_search_candidates
              where version = new.version
           ),
           updated_at = now()
     where version = new.version;
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists pokoin_version_sets_recount_trg on public.marketplace_search_candidates;
create trigger pokoin_version_sets_recount_trg
after insert or update of version or delete on public.marketplace_search_candidates
for each row
execute function public.pokoin_version_sets_recount();

grant select, insert, update, delete on public.pokoin_version_sets to pokoin_marketplace;
