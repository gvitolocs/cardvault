/// La route web /card-images/ rimanda allo stesso file sul CDN.
/// Il client mobile lo richiede direttamente, evitando un redirect per immagine.
Uri? marketplaceImageUri(String value) {
  final source = Uri.tryParse(value.trim());
  if (value.trim().isEmpty || source == null) return null;
  if (source.hasScheme && source.scheme != 'https' && source.scheme != 'http') {
    return null;
  }
  final resolved = Uri.parse('https://pokoin.com').resolveUri(source);
  if (resolved.host == 'pokoin.com' &&
      resolved.path.startsWith('/card-images/')) {
    return resolved.replace(
        scheme: 'https',
        host: 'cdn.pokoin.com',
        path: resolved.path.substring('/card-images'.length));
  }
  return resolved;
}
