import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../cache/marketplace_image_cache.dart';
import '../marketplace_image_url.dart';

/// Cache in memoria e su disco; niente precache dell'intero slider.
class MarketplaceThumbnail extends StatelessWidget {
  const MarketplaceThumbnail({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fallbackIcon = Icons.style_outlined,
    this.gaplessPlayback = false,
  });

  final String imageUrl;
  final double width;
  final double height;
  final IconData fallbackIcon;
  final bool gaplessPlayback;

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(child: Icon(fallbackIcon, size: 40));
    final uri = marketplaceImageUri(imageUrl);
    return SizedBox(
      width: width,
      height: height,
      child: uri == null
          ? placeholder
          : Image(
              image: ResizeImage.resizeIfNeeded(
                  (width * MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(1, 768),
                  null,
                  CachedNetworkImageProvider(uri.toString(),
                      cacheManager: MarketplaceImageCache.instance)),
              fit: BoxFit.contain,
              gaplessPlayback: gaplessPlayback,
              frameBuilder: (_, child, frame, synchronous) =>
                  synchronous || frame != null ? child : placeholder,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}
