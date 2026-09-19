-- Crown Zenith GG31/GG70 is the English version of VSTAR Universe 206/172.
-- Both share the full-art forest illustration and must not be grouped with
-- the Majestic Dawn / PPP / Holiday Calendar Ken Sugimori artwork.

begin;
set local statement_timeout = 0;

insert into public.pokoin_version_sets (version, gameplay_name, member_count, source)
values ('v467794', 'Turtwig', 2, 'artbox-pin')
on conflict (version) do update
  set gameplay_name = excluded.gameplay_name,
      member_count = excluded.member_count,
      source = excluded.source,
      updated_at = now();

update public.marketplace_search_candidates
set version = 'v467794'
where card_id in (
  467794, -- VSTAR Universe Secret Rare 206/172
  470272  -- Crown Zenith Illustration Rare GG31/GG70
);

update public.pokoin_version_sets
set member_count = 4,
    updated_at = now()
where version = 'v245782';

delete from public.pokoin_version_sets s
where s.version = 'v470272'
  and not exists (
    select 1
    from public.marketplace_search_candidates c
    where c.version = s.version
  );

commit;
