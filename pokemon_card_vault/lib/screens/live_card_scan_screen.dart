import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../scan_v2/live_scan_page.dart';

/// Android V2 / iOS Fast scan from pokoin-cardapp, embedded in CardVault.
class LiveCardScanScreen extends StatelessWidget {
  const LiveCardScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CameraScanPage(
      onOpenMarketplaceUri: (uri) {
        final parts = uri.pathSegments;
        // /marketplace/en/cards/{publicId}/...
        final cardsIdx = parts.indexOf('cards');
        if (cardsIdx >= 0 && cardsIdx + 1 < parts.length) {
          final publicId = parts[cardsIdx + 1];
          if (RegExp(r'^\d+$').hasMatch(publicId)) {
            final slug =
                cardsIdx + 2 < parts.length ? parts[cardsIdx + 2] : null;
            final path = slug == null || slug.isEmpty
                ? '/marketplace/en/cards/$publicId'
                : '/marketplace/en/cards/$publicId/$slug';
            context.go(path);
            return true;
          }
        }
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
        if (RegExp(r'^\d+$').hasMatch(id)) {
          context.go('/marketplace/en/cards/$id');
          return true;
        }
        return false;
      },
    );
  }
}
