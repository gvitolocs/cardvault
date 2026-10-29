# Rebuild constants

This folder contains shared, compile-time values used by the active Pokoin
Rebuild application: display labels, lookup tables, identifiers and other static
metadata that do not belong inside services or controllers.

## Current files

- `app_appearance_constants.dart`: names and short descriptions for optional
  app appearances; icon manifests and visual styling stay in `style/`.
- `cardex_album_layout_constants.dart`: Cardex margins, leaf insets, tight
  pocket gaps and page-number metrics; no effect on Portfolio grid geometry.
- `cardex_pagination_constants.dart`: catalog prefetch distance measured in
  album spreads; separate from private inventory request sizes and image loads.
- `cardex_artwork_constants.dart`: normalized scan window, shared portrait
  proportions and derived illustration ratio for the artwork-only Cardex;
  pockets fit that ratio instead of a fixed minimum/letterbox. No URLs, generated images or
  per-card crop detection; Portfolio keeps full-card presentation.
- `card_language_constants.dart`: collection language labels, flag symbols and
  API spelling/locale aliases. These are display options, not a per-card printing
  availability catalog; quantities always come from authenticated ownership.
- `expansion_era_constants.dart`: maps canonical era identifiers to their
  Italian display titles and defines `otherExpansionEraId` for unclassified
  expansions. `ExpansionEraService` imports these constants while retaining
  responsibility for grouping and filtering expansions.

## Guidelines

- Group constants by feature or domain in descriptive `snake_case.dart` files.
  Avoid one large file containing unrelated strings.
- Prefer immutable, explicitly typed `const` values for shared data.
- Keep this folder independent of Flutter widgets, services, controllers,
  providers and storage. Consumers import constants, not the other way around.
- Keep API requests, parsing, grouping rules and other behavior in their
  respective layers. This folder holds data, not application logic.
- Do not store credentials, tokens, user data or runtime configuration here.
- Do not move every one-off UI sentence into this folder. Feature-wide static
  labels belong here; a future localization system should own translated UI
  messages when introduced.
- Generated catalog data stays in its existing generated source. Do not copy
  the expansion-to-era catalog here: these constants only provide display
  titles, while the shared TCG catalog remains the source for era membership.

Changing a constant's value can affect multiple consumers. Update the relevant
tests whenever labels, identifiers or mappings intentionally change.
