alter table public.cardtrader_pokemon_blueprints enable row level security;

drop policy if exists "CardTrader blueprints are publicly readable"
  on public.cardtrader_pokemon_blueprints;

create policy "CardTrader blueprints are publicly readable"
  on public.cardtrader_pokemon_blueprints
  for select
  to anon, authenticated
  using (true);
