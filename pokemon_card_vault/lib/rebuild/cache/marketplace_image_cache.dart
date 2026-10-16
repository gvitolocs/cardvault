import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../provider/image_cache_file_system.dart';

/// Una sola istanza per app. Scarica i file richiesti dai widget visibili.
abstract final class MarketplaceImageCache {
  static const key = 'rebuild-marketplace-images-v1';
  static const maxConcurrentDownloads = 2;
  static final instance = CacheManager(Config(key,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 80,
      fileService: HttpFileService()
        ..concurrentFetches = maxConcurrentDownloads,
      fileSystem: ImageCacheFileSystem()));
}
