# Shared presentation atomics

Small reusable Flutter UI assets shared by multiple Rebuild screens. These are
code-native widgets, not images that have to be fetched, decoded or precached.
Keep colors/themes in `style/`, account evidence in models/services and network
access in providers; atomics receive state and paint it synchronously.

- `card_ownership_frame.dart`: the rounded green/yellow owned-card outline and
  neutral sleeve, using constant decorations. Used by Cardex and Portfolio via
  `AlbumCard`; pass `owned` only for validated positive account evidence.
- `card_language_flag.dart`: local flag glyph and the fixed-size corner badge,
  shared by loading evidence, the ready selector and its menu. Unknown language
  uses a globe; it does not guess a language or fetch a raster flag.
  Collection pockets use its compact, top-aligned visual with the same 48px
  touch target; `component/card_ownership_edge_controls.dart` straddles the
  top outline with language/final quantity. Owned capsules share the outline's
  yellow color; missing-language capsules remain neutral/grey. Portfolio
  reserves half the text-scaled rail outside the frame and half in its header.
  Cardex instead uses the fully external variant, touching the top outline,
  so its artwork can sit flush against the frame without an inner dark band.
  Both keep the painted controls off the scan. Details keep default presentation.
- `collection_quantity_badge.dart`: final reconciled totals only. Early positive
  evidence must not be displayed as a complete count or absence classification.
  The compact collection variant remains separate from the caption/image.
- `marketplace_thumbnail.dart`: the common cached network image, with bounded
  decoding; ownership decorations do not wait for this image's frame callback.

Example:

```dart
CardOwnershipFrame(
  owned: ownership.hasConfirmedCopies,
  child: artwork,
)
```

The early language badge is noninteractive until complete ownership is ready.
Guest/unavailable state must never reuse evidence from another account.
