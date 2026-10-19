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
- `collection_quantity_badge.dart`: final reconciled totals only. Early positive
  evidence must not be displayed as a complete count or absence classification.
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
