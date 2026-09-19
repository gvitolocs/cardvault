-- Fezandipiti ex regular UR (takuyoa pose): same illustration across
-- Night Wanderer / Shrouded Fable / Terastal Festival / MEGA reprints /
-- prize packs / WCD stamps / CN. CLIP unique-nearest split them into
-- several keys (v589958 had 3). Full-Art and SIR stay apart.
--
-- source artbox-pin: cluster-name-version-sets.py --all must not reset these.

begin;
set local statement_timeout = 0;

insert into public.pokoin_version_sets (version, gameplay_name, member_count, source)
values ('v589958', 'Fezandipiti ex', 16, 'artbox-pin')
on conflict (version) do update
  set gameplay_name = excluded.gameplay_name,
      source = excluded.source,
      updated_at = now();

update public.marketplace_search_candidates
   set version = 'v589958'
 where card_id in (
   581062, -- Night Wanderer UR 038/064
   589958, -- Shrouded Fable UR 038/064
   626566, -- Terastal Festival ex UR 104/187
   629958, -- Battle Partners Deck Build Box 002/045
   643628, -- Prize Pack Series 038/064
   655276, -- WCD 2024 Sakuya Ota
   655364, -- WCD 2024 Jesse Parker
   689580, -- Premium Trainer Box MEGA UR 003/043
   701808, -- Prize Pack Series 038/064
   718400, -- MEGA Dream ex UR 114/193
   728310, -- MEGA Start Deck 100 UR 489/742
   741560, -- Ascended Heroes UR 142/217
   757432, -- CSV8 Brilliant Fantasy UR 135/207
   771036, -- WCD 2025 Yuya Okita
   771184, -- WCD 2025 Jose Cruz Galindo-Resendiz
   782476  -- CSVNC Land of Kitakami 027/040
 );

commit;
