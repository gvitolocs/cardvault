import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/cache/marketplace_home_cache.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/provider/cache_directory_provider.dart';
import 'package:pokoin/rebuild/provider/cache_file_provider.dart';
import 'package:pokoin/rebuild/provider/image_cache_file_system.dart';
import 'package:pokoin/rebuild/service/marketplace_home_service.dart';
import 'marketplace_home_service_test.dart' as fixtures;

class _SlowCacheStorage extends CacheFileProvider {
  final writing = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String contents) async {
    if (!writing.isCompleted) writing.complete();
    await release.future;
  }
}

class _DelayedRestoreCache extends MarketplaceHomeCache {
  _DelayedRestoreCache(this.saved, this.delay);
  final MarketplaceHomeData saved;
  final Duration delay;

  @override
  Future<MarketplaceHomeData?> read(String namespace) =>
      Future.delayed(delay, () => saved);

  @override
  Future<void> save(String namespace, MarketplaceHomeData data) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late CacheDirectoryProvider directories;
  late CacheFileProvider storage;
  var time = DateTime.utc(2026, 10, 9);
  MarketplaceHomeCache cache() =>
      MarketplaceHomeCache(storage: storage, now: () => time);
  MarketplaceHomeData data() => MarketplaceHomeData(
      expansions: List.generate(
          20,
          (i) => MarketplaceExpansion(
              name: 'Set $i',
              slug: 'set-$i',
              cardCount: 100,
              imageUrl: '/set-$i.png')),
      topSellers: List.generate(
          20,
          (i) => MarketplaceCardPreview(
              id: '$i',
              name: 'Carta $i',
              expansion: 'Set',
              number: '$i/100',
              imageUrl: '/card-images/$i.jpg',
              fullImageUrl: '/card-images/${i}_full.jpg',
              pricePkn: 12.5,
              canonicalPath: '/cards/$i')));
  setUp(() async {
    time = DateTime.utc(2026, 10, 9);
    root = await Directory.systemTemp.createTemp('rebuild-cache-test-');
    final createdRoot = root;
    directories =
        CacheDirectoryProvider(loadDirectory: () async => createdRoot);
    storage = CacheFileProvider(directories: directories);
  });
  tearDown(() async {
    expect(root.parent.absolute.path, Directory.systemTemp.absolute.path);
    expect(root.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('rebuild-cache-test-'));
    await root.delete(recursive: true);
  });

  test('a new cache instance restores only twelve entries with their metadata',
      () async {
    await cache().save('api-A', data());
    final restored = (await cache().read('api-A'))!;
    expect(restored.fromCache, isTrue);
    expect(restored.expansions, hasLength(12));
    expect(restored.topSellers, hasLength(12));
    expect(restored.topSellers.first.imageUrl, '/card-images/0.jpg');
    expect(restored.topSellers.first.fullImageUrl, '/card-images/0_full.jpg');
    expect(restored.topSellers.first.pricePkn, 12.5);
    expect(restored.topSellers.first.canonicalPath, '/cards/0');
    expect(await cache().read('api-B'), isNull);
  });

  test('partial updates do not renew the age of a cached failed rail',
      () async {
    await cache().save('api-A', data());
    time = time.add(const Duration(days: 6));
    await cache().save(
        'api-A',
        MarketplaceHomeData(
            expansions: data().expansions,
            topSellers: data().topSellers,
            topSellersFromCache: true,
            refreshFailed: true));
    time = time.add(const Duration(days: 2));
    final restored = (await cache().read('api-A'))!;
    expect(restored.expansions, hasLength(12));
    expect(restored.topSellers, isEmpty);
    expect(restored.topSellersUnavailable, isTrue);
    await storage.write('{broken');
    expect(await cache().read('api-A'), isNull);
  });

  testWidgets('fresh metadata restored after 260 ms avoids network requests',
      (tester) async {
    final original = data();
    final saved = MarketplaceHomeData(
        cachedAt: DateTime.now(),
        expansions: original.expansions,
        topSellers: original.topSellers,
        expansionsFromCache: true,
        topSellersFromCache: true);
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{}', 503);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        cache: _DelayedRestoreCache(saved, const Duration(milliseconds: 260)),
        loadCatalogOrder: () async => {});
    addTearDown(service.dispose);
    final pending = service.load();
    await tester.pump(const Duration(milliseconds: 260));
    final result = await pending;
    expect(requests, 0);
    expect(result.topSellers, saved.topSellers);
    expect(result.fromCache, isTrue);
  });

  testWidgets('restoration exceeding 280 ms falls back to network',
      (tester) async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return fixtures.jsonResponse(request.url.path.contains('expansion')
          ? fixtures.expansionsPayload
          : fixtures.homePayload);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        cache: _DelayedRestoreCache(data(), const Duration(milliseconds: 320)),
        loadCatalogOrder: () async => {});
    addTearDown(service.dispose);
    final pending = service.load();
    await tester.pump(const Duration(milliseconds: 300));
    final result = await pending;
    expect(requests, 2);
    expect(result.fromCache, isFalse);
    expect(result.topSellers.first.id, '24');
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('a recent complete snapshot avoids GETs across service restarts',
      () async {
    time = DateTime.now().subtract(const Duration(minutes: 1));
    const namespace = 'https://api.pokoin.com';
    final saved = cache();
    await saved.save(namespace, data());
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return fixtures.jsonResponse(request.url.path.contains('expansion')
          ? fixtures.expansionsPayload
          : fixtures.homePayload);
    });
    addTearDown(client.close);
    final restoredCache = cache();
    MarketplaceHomeService service() => MarketplaceHomeService(
        client: client, cache: restoredCache, loadCatalogOrder: () async => {});
    final first = await service().load();
    final restarted = service();
    final second = await restarted.load();
    expect(first.fromCache, isTrue);
    expect(second.topSellers, hasLength(12));
    expect(requests, 0);
    await restarted.load(forceRefresh: true);
    expect(requests, 2);
    await restoredCache.flush;
  });

  test('a recent single rail does not hide a missing peer rail', () async {
    time = DateTime.now().subtract(const Duration(minutes: 1));
    await cache().save(
        'https://api.pokoin.com',
        MarketplaceHomeData(
            expansions: data().expansions,
            topSellers: [],
            topSellersUnavailable: true));
    expect((await cache().read('https://api.pokoin.com'))!.cachedAt, isNull);
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{}', 503);
    });
    addTearDown(client.close);
    final retryCache = cache();
    final service = MarketplaceHomeService(
        client: client, cache: retryCache, loadCatalogOrder: () async => {});
    final result = await service.load();
    expect(requests, 2);
    expect(result.expansions, hasLength(12));
    expect(result.topSellersUnavailable, isTrue);
    await retryCache.flush;
  });

  test(
      'restart shows saved rails before network and keeps them on failed refresh',
      () async {
    const namespace = 'https://api.pokoin.com';
    await cache().save(namespace, data());
    final home = Completer<http.Response>();
    final sets = Completer<http.Response>();
    final client = MockClient((request) =>
        request.url.path.contains('expansion') ? sets.future : home.future);
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client, cache: cache(), loadCatalogOrder: () async => {});
    final ready = Completer<MarketplaceHomeData>();
    final pending = service.load(onProgress: (snapshot) {
      if (!ready.isCompleted) ready.complete(snapshot);
    });
    final saved = await ready.future;
    expect(saved.topSellers, hasLength(12));
    expect(saved.expansions.map((set) => set.name),
        data().expansions.take(12).map((set) => set.name));
    expect(saved.topSellersLoading, isTrue);
    expect(saved.expansionsLoading, isTrue);
    expect(home.isCompleted, isFalse);
    expect(sets.isCompleted, isFalse);
    home.complete(http.Response('{}', 503));
    sets.complete(http.Response('{}', 503));
    final result = await pending;
    expect(result.fromCache, isTrue);
    expect(result.refreshFailed, isTrue);
    expect(result.topSellersUnavailable, isFalse);
    expect(result.expansionsUnavailable, isFalse);
    expect(result.topSellers, hasLength(12));
    expect(result.expansions, hasLength(12));
    final freshClient = MockClient((request) async => fixtures.jsonResponse(
        request.url.path.contains('expansion')
            ? fixtures.expansionsPayload
            : fixtures.homePayload));
    addTearDown(freshClient.close);
    final refreshCache = cache();
    final refresh = MarketplaceHomeService(
        client: freshClient,
        cache: refreshCache,
        loadCatalogOrder: () async => {});
    final fresh = await refresh.load();
    expect(fresh.fromCache, isFalse);
    expect(fresh.refreshFailed, isFalse);
    await refreshCache.flush;
    expect((await cache().read(namespace))!.topSellers.first.id, '24');
  });

  test('image bytes are reusable after closing and reopening the disk manager',
      () async {
    final imageDirectory = await directories.directory('images');
    final index = '${imageDirectory.path}/index.json';
    CacheManager manager() => CacheManager(Config('test-image-cache',
        repo: JsonCacheInfoRepository(path: index),
        fileSystem: ImageCacheFileSystem(directories: directories)));
    final first = manager();
    const url = 'https://cdn.pokoin.com/card.jpg';
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await first.putFile(url, bytes, fileExtension: 'jpg');
    await first
        .getFileFromCache(url); // Complete the metadata insert before closing.
    await first.dispose();
    final second = manager();
    final restored = await second.getSingleFile(url);
    expect(await restored.readAsBytes(), bytes);
    expect(restored.parent.path, imageDirectory.path);
    await second.dispose();
  });

  test('slow disk writes do not delay completion or a forced retry', () async {
    final slowStorage = _SlowCacheStorage();
    final saved = MarketplaceHomeCache(storage: slowStorage);
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return fixtures.jsonResponse(request.url.path.contains('expansion')
          ? fixtures.expansionsPayload
          : fixtures.homePayload);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client, cache: saved, loadCatalogOrder: () async => {});
    try {
      final result = await service.load();
      await slowStorage.writing.future;
      expect(result.topSellers, hasLength(2));
      expect(slowStorage.release.isCompleted, isFalse);
      await service.load(forceRefresh: true);
      expect(requests, 4);
    } finally {
      slowStorage.release.complete();
      await saved.flush;
    }
  });
}
