import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Card art on Flutter web uses the browser <img> decoder (progressive JPEG
/// and VP8X WebP). CanvasKit's ImageCodec cannot decode those, which is why
/// tiles and detail art go black/yellow when navigating on pokoin.com.
class MarketplaceNetworkImage extends StatelessWidget {
  const MarketplaceNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    required this.errorWidget,
  });

  final String imageUrl;
  final BoxFit fit;
  final Alignment alignment;
  final Widget Function(BuildContext context, String url, Object error)
      errorWidget;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        imageUrl,
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.medium,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (context, error, stackTrace) {
          return errorWidget(context, imageUrl, error);
        },
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      alignment: alignment,
      errorWidget: errorWidget,
    );
  }
}
