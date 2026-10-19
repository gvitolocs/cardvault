/// Normalized window within a standard portrait scan (not a server crop).
/// A conservative upper illustration area avoids headers and lower effects.
/// Special/full-art layouts can frame the subject differently; no inference
/// or per-card hydration is performed just to render the album.
abstract final class CardexArtworkConstants {
  static const left = .05;
  static const top = .12;
  static const width = .90;
  static const height = .34;
  // A taller pocket leaves a separate metadata footer below the illustration.
  static const pocketAspectRatio = 1.3;
  static const minimumPocketHeight = 136.0;
  static const largeTextMinimumPocketHeight = 196.0;
}
