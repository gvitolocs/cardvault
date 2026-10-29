/// Normalized window within a standard portrait scan (not a server crop).
/// A conservative upper illustration area avoids headers and lower effects.
/// Special/full-art layouts can frame the subject differently; no inference
/// or per-card hydration is performed just to render the album.
abstract final class CardexArtworkConstants {
  static const left = .05;
  static const top = .12;
  static const width = .90;
  static const height = .34;
  static const portraitAspectRatio = .716;
  // Fit the normalized illustration itself, with no fixed-height letterbox.
  static const artworkAspectRatio = width * portraitAspectRatio / height;
}
