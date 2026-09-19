-- Air Balloon item reprints share one leftover painting: SWSH 156/202, gold
-- 213/202, JP Sword, Shiny Star V / VMAX Climax / trainer boxes, Black Bolt,
-- Mega Evolution golds, and WCD stamps. CLIP split the uncommon stack
-- (v258636) from Black Bolt / gold (v258812).
--
-- source artbox-pin: cluster-name-version-sets.py --all must not split this.
-- Item trainers keep regular+gold together; illustrated supporters (Misty
-- at a pool) still split.

begin;
set local statement_timeout = 0;

insert into public.pokoin_version_sets (version, gameplay_name, member_count, source)
values ('v258812', 'Air Balloon', 32, 'artbox-pin')
on conflict (version) do update
  set gameplay_name = excluded.gameplay_name,
      member_count = excluded.member_count,
      source = excluded.source,
      updated_at = now();

update public.marketplace_search_candidates
   set version = 'v258812'
 where card_id in (
   258636, -- Sword & Shield 156/202
   258812, -- Sword & Shield Secret Rare 213/202
   286738, -- Sword 57/060
   286774, -- Sword Ultra Rare 75/060
   450356, -- Shiny Star V 171/190
   465800, -- VMAX Climax 145/184
   467332, -- Premium Trainer Box VSTAR 021/030
   480480, -- Single Strike & Rapid Strike Premium Trainer Boxes 017/033
   485136, -- Play! Pokémon Prize Pack Series 156/202
   641958, -- V Starter Decks 105/127
   664852, -- Black Bolt sv11B 082/086
   684690, -- Black Bolt 079/086
   686838, -- Black Bolt Poké Ball Reverse Holo 079/086
   689448, -- Mega Brave Ultra Rare 084/063
   689668, -- Premium Trainer Box MEGA 030/043
   691652, -- Starter Set MEGA Mega Gengar ex 018/021
   691700, -- Starter Set MEGA Mega Diancie ex 017/021
   703348, -- Mega Evolution Ultra Rare 166/132
   716642, -- M-P Promos 050/M-P
   718096, -- MEGA Dream ex 165/193
   719958, -- Black Bolt sv11B Poké Ball Reverse Holo 082/086
   728708, -- MEGA Start Deck 100 Battle Collection 688/742
   729904, -- Play! Pokémon Prize Pack Series Cosmos Holo 079/085
   738620, -- CS1b: Dynamax Clash - Flame 128/136
   738758, -- CS1b: Dynamax Clash - Flame Gold Secret Rare 197/136
   741638, -- Ascended Heroes 181/217
   749840, -- M-P Promos 081/M-P
   771094, -- World Championship Decks 2025 Liao Fu Guan
   771190, -- World Championship Decks 2025 Jose Cruz Galindo-Resendiz
   805924, -- MEGA Starter Set Sprigatito & Meowscarada ex 013/208
   805960, -- MEGA Starter Set Zorua & Zoroark ex 014/208
   805998  -- MEGA Starter Set Eevee ex 014/208
 );

delete from public.pokoin_version_sets s
 where s.version in ('v258636', 'v771094')
   and not exists (
     select 1
       from public.marketplace_search_candidates c
      where c.version = s.version
   );

commit;
