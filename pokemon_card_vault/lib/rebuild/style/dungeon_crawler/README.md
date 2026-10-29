# Dungeon Crawler

Optional, device-local Pokoin appearance. The app still starts with Default
unless the user has saved another choice via the palette beside their email
in Profile -> Tema dell'app (also available beside the guest description).

`dungeon_crawler_theme.dart` owns the icon-slot manifest, illustrated surfaces
and warm brown/cream/gold toolbar and navigation palette. The main five-tab
shell uses Mappa.png as its background and Botttom_bar.png behind the existing
navigation controls. Default retains its original palette and Flutter icons.
Cardex and Portfolio use supplied custom icons; unfilled slots retain Flutter
icons. Portfolio is also used by the collection shortcut in Profile.

## Adding artwork

Keep bitmap files under `assets/`, not under `lib/style/`. Register their exact
case-sensitive path in pubspec when required, then add an AppThemeIcon slot to
the manifest. The existing `assets/icons/` declaration already bundles
`assets/icons/Cardex.png` and `assets/icons/Portfolio.png`; no duplicate copy or
network download is needed.
The explicit `assets/images/Dungeon Crawler Themed/` bundle contains Mappa.png
and Botttom_bar.png. Original colours are preserved: the map covers the body
proportionally, aligned at the top; the chest fills the navigation height,
including the safe bottom inset. Labels and touch targets remain unchanged.
AppThemeSurfaces configures local backgrounds separately from AppThemeIcons.
No card cropping, API fetching or image processing is involved. Existing panels
keep their own readable surfaces. The map does not replace pushed detail pages.

Navigation slots: market, scanner, portfolio, cardex, profile. Shared marketplace
slots: cart, filters, search, wallet, clipboard. Reuse ThemedIcon for new themed
surfaces so missing or broken assets retain a functional Flutter icon.
Pixel art is drawn without smoothing and with bounded dimensions; changing the
theme must not fetch card images, recreate services, log out users, clear the
cart, or affect API/search/inventory data. Existing card-specific palettes and
album crops remain independent of this app-wide appearance.
