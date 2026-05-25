import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_user_profile.dart';
import '../providers/auth_provider.dart';
import '../services/pokoin_api_client.dart';
import '../widgets/artist_suggestion_field.dart';

class MarketplaceDebugScreen extends ConsumerWidget {
  const MarketplaceDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DebugGate(
      child: Scaffold(
        backgroundColor: const Color(0xFF050816),
        appBar: AppBar(
          backgroundColor: const Color(0xE60A1026),
          title: const Text('Marketplace Debug'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                const _DebugHero(),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    const _CardTraderBlueprintImportCard(),
                    _DebugToolCard(
                      title: 'Cardmarket refinement',
                      body:
                          'Random human-review queue for Cardmarket product URL refinement.',
                      icon: Icons.manage_search,
                      actionLabel: 'Open queue',
                      onTap: () => context.go('/marketplace/debug/refinement'),
                    ),
                    _DebugToolCard(
                      title: 'Cardmarket guesses',
                      body:
                          'Review risky verified links, exact-only imports, and missing expansion rules.',
                      icon: Icons.fact_check_outlined,
                      actionLabel: 'Review',
                      onTap: () =>
                          context.go('/marketplace/debug/cardmarket-guesses'),
                    ),
                    _DebugToolCard(
                      title: 'Artist curation',
                      body:
                          'Show one clear card image and choose from known artists for the same Pokémon.',
                      icon: Icons.brush_outlined,
                      actionLabel: 'Curate',
                      onTap: () => context.go('/marketplace/debug/artists'),
                    ),
                    _DebugToolCard(
                      title: 'Marketplace search',
                      body:
                          'Open marketplace with search debug capture enabled.',
                      icon: Icons.bug_report_outlined,
                      actionLabel: 'Open',
                      onTap: () => context.go('/marketplace?searchDebug=1'),
                    ),
                    _DebugToolCard(
                      title: 'Event log',
                      body:
                          'Track recent card views, searches, clicks, cart adds, reserves, and sales.',
                      icon: Icons.receipt_long_outlined,
                      actionLabel: 'Open tracker',
                      onTap: () => context.go('/marketplace/debug/events'),
                    ),
                    _DebugToolCard(
                      title: 'Marketplace Logo Editor',
                      body: 'Match expansion names to persistent logo URLs.',
                      icon: Icons.image_search_outlined,
                      actionLabel: 'Edit',
                      onTap: () => context.go('/marketplace/admin/edit'),
                    ),
                    _DebugToolCard(
                      title: 'Marketplace',
                      body: 'Open the public marketplace home.',
                      icon: Icons.storefront_outlined,
                      actionLabel: 'Open',
                      onTap: () => context.go('/marketplace'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardTraderBlueprintImportCard extends ConsumerStatefulWidget {
  const _CardTraderBlueprintImportCard();

  @override
  ConsumerState<_CardTraderBlueprintImportCard> createState() =>
      _CardTraderBlueprintImportCardState();
}

class _CardTraderBlueprintImportCardState
    extends ConsumerState<_CardTraderBlueprintImportCard> {
  CardTraderImportJob? _job;
  bool _loading = false;
  bool _acting = false;
  String _error = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _schedulePollIfActive() {
    _pollTimer?.cancel();
    if (_job?.active != true) return;
    _pollTimer = Timer(const Duration(seconds: 5), _loadStatus);
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient
          .get(
            Uri.base.resolve(
              '/api/marketplace-debug-cardtrader-blueprints?game=pokemon',
            ),
          )
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      if (decoded is! Map) {
        throw StateError('Unexpected CardTrader import status payload.');
      }
      setState(() {
        final job = decoded['job'];
        _job = job is Map ? CardTraderImportJob.fromJson(job) : null;
      });
      _schedulePollIfActive();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _enqueue(String mode) async {
    if (mode == 'apply') {
      final missing = _job?.missingRaw ?? 0;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import CardTrader blueprints?'),
          content: Text(
            'This queues an Oracle Cloud worker job for Pokemon. '
            'Vercel will not run the import. The worker will import up to '
            '5000 missing rows, generate CDN images, refresh projections, and '
            'sync search tokens. Last dry-run found $missing missing raw rows.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Queue import'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _acting = true;
      _error = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final apply = mode == 'apply';
      final response = await apiClient.postJson(
        Uri.base.resolve('/api/marketplace-debug-cardtrader-blueprints'),
        body: {
          'game': 'pokemon',
          'mode': mode,
          'streamAll': true,
          'limit': apply ? '5000' : 'all',
          'images': apply,
          'refresh': apply,
          'syncSearch': apply,
          'batchSize': 500,
          'concurrency': apply ? 4 : 6,
          'imageConcurrency': 4,
          'imageChunkSize': 50,
        },
      ).timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      if (decoded is! Map || decoded['job'] is! Map) {
        throw StateError('Unexpected CardTrader import queue payload.');
      }
      setState(() {
        _job = CardTraderImportJob.fromJson(decoded['job'] as Map);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              apply
                  ? 'Oracle import job queued.'
                  : 'Oracle dry-run check queued.',
            ),
          ),
        );
      }
      _schedulePollIfActive();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final busy = _loading || _acting || (job?.active ?? false);
    final statusText = _error.isNotEmpty
        ? _error
        : job == null
            ? 'Queue a dry-run on Oracle Cloud to check CardTrader for missing Pokemon blueprints.'
            : job.message;
    return SizedBox(
      width: 660,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1020),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _error.isNotEmpty
                ? const Color(0xFFEF4444)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_sync_outlined, color: Color(0xFFFACC15)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CardTrader blueprint import',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Admin-only control surface. Vercel only queues/reads Oracle jobs; the Oracle VM worker performs imports, CDN images, projection refresh, and token sync.',
              style: TextStyle(color: Color(0xFF93A4C8)),
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: TextStyle(
                color: _error.isNotEmpty
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFFE2E8F0),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (job != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChipText(job.status),
                  _ChipText(job.mode == 'apply' ? 'apply' : 'dry-run'),
                  _ChipText('${job.missingRaw} missing'),
                  _ChipText('${job.inserted} inserted'),
                  if (job.failedExpansions > 0)
                    _ChipText('${job.failedExpansions} failed expansions'),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : () => _enqueue('dry_run'),
                  icon: _loading || _acting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(busy ? 'Checking' : 'Check new blueprints'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                  ),
                  onPressed: busy || (job?.missingRaw ?? 0) <= 0
                      ? null
                      : () => _enqueue('apply'),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Queue Oracle import'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _loadStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh status'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CardTraderImportJob {
  const CardTraderImportJob({
    required this.jobId,
    required this.game,
    required this.mode,
    required this.status,
    required this.active,
    required this.progress,
    required this.summary,
    required this.errorMessage,
    required this.requestedAt,
    required this.heartbeatAt,
    required this.finishedAt,
  });

  factory CardTraderImportJob.fromJson(Map<dynamic, dynamic> json) {
    return CardTraderImportJob(
      jobId: '${json['jobId'] ?? ''}',
      game: '${json['game'] ?? 'pokemon'}',
      mode: '${json['mode'] ?? 'dry_run'}',
      status: '${json['status'] ?? ''}',
      active: json['active'] == true,
      progress: json['progress'] is Map
          ? Map<String, dynamic>.from(json['progress'] as Map)
          : const {},
      summary: json['summary'] is Map
          ? Map<String, dynamic>.from(json['summary'] as Map)
          : const {},
      errorMessage: '${json['errorMessage'] ?? ''}',
      requestedAt: '${json['requestedAt'] ?? ''}',
      heartbeatAt: '${json['heartbeatAt'] ?? ''}',
      finishedAt: '${json['finishedAt'] ?? ''}',
    );
  }

  final String jobId;
  final String game;
  final String mode;
  final String status;
  final bool active;
  final Map<String, dynamic> progress;
  final Map<String, dynamic> summary;
  final String errorMessage;
  final String requestedAt;
  final String heartbeatAt;
  final String finishedAt;

  Map<dynamic, dynamic> get _counts {
    final summaryCounts = summary['counts'];
    if (summaryCounts is Map) return summaryCounts;
    final progressCounts = progress['counts'];
    if (progressCounts is Map) return progressCounts;
    return const {};
  }

  int _count(String key) {
    final value = _counts[key];
    return value is num ? value.toInt() : 0;
  }

  int get missingRaw => _count('missingRaw');
  int get inserted => _count('inserted');
  int get failedExpansions => _count('failedExpansions');

  String get message {
    if (errorMessage.isNotEmpty) return errorMessage;
    if (active) {
      final when = heartbeatAt.isEmpty ? requestedAt : heartbeatAt;
      return 'Oracle job $status${when.isEmpty ? '' : ' • $when'}';
    }
    if (status == 'succeeded') {
      return 'Last Oracle job succeeded: $missingRaw missing, $inserted inserted.';
    }
    if (status == 'queued') return 'Oracle job queued.';
    if (status == 'failed') return 'Oracle job failed.';
    return 'Last Oracle job status: $status.';
  }
}

class MarketplaceDebugRefinementScreen extends ConsumerStatefulWidget {
  const MarketplaceDebugRefinementScreen({super.key});

  @override
  ConsumerState<MarketplaceDebugRefinementScreen> createState() =>
      _MarketplaceDebugRefinementScreenState();
}

class _MarketplaceDebugRefinementScreenState
    extends ConsumerState<MarketplaceDebugRefinementScreen> {
  List<CardmarketRefinementRow> _rows = const [];
  bool _loading = false;
  String _error = '';
  String _generatedAt = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRows());
  }

  Future<void> _loadRows() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient
          .get(
            Uri.base.resolve('/api/marketplace-debug-refinement?limit=1000'),
          )
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      if (decoded is! Map || decoded['rows'] is! List) {
        throw StateError('Unexpected debug payload.');
      }
      setState(() {
        _rows = (decoded['rows'] as List)
            .whereType<Map>()
            .map((row) => CardmarketRefinementRow.fromJson(row))
            .toList(growable: false);
        _generatedAt = '${decoded['generatedAt'] ?? ''}';
      });
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DebugGate(
      child: Scaffold(
        backgroundColor: const Color(0xFF050816),
        appBar: AppBar(
          backgroundColor: const Color(0xE60A1026),
          title: const Text('Cardmarket Refinement'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _loadRows,
              tooltip: 'Pick another random 1000',
              icon: const Icon(Icons.shuffle),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: _RefinementHeader(
                    count: _rows.length,
                    loading: _loading,
                    generatedAt: _generatedAt,
                    error: _error,
                    onRefresh: _loadRows,
                  ),
                ),
                Expanded(
                  child: _loading && _rows.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _RefinementRowTile(row: _rows[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CardmarketRefinementRow {
  const CardmarketRefinementRow({
    required this.blueprintId,
    required this.name,
    required this.expansionName,
    required this.collectorNumber,
    required this.productVariant,
    required this.imageUrl,
    required this.cardMarketIds,
    required this.cardmarketUrl,
    required this.cardmarketRedirectUrl,
    required this.status,
    required this.reviewBucket,
  });

  factory CardmarketRefinementRow.fromJson(Map<dynamic, dynamic> json) {
    return CardmarketRefinementRow(
      blueprintId: '${json['blueprintId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      expansionName: '${json['expansionName'] ?? ''}',
      collectorNumber: '${json['collectorNumber'] ?? ''}',
      productVariant: '${json['productVariant'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      cardMarketIds: (json['cardMarketIds'] as List<dynamic>? ?? const [])
          .map((value) => '$value')
          .toList(growable: false),
      cardmarketUrl: '${json['cardmarketUrl'] ?? ''}',
      cardmarketRedirectUrl: '${json['cardmarketRedirectUrl'] ?? ''}',
      status: '${json['status'] ?? ''}',
      reviewBucket: '${json['reviewBucket'] ?? ''}',
    );
  }

  final String blueprintId;
  final String name;
  final String expansionName;
  final String collectorNumber;
  final String productVariant;
  final String imageUrl;
  final List<String> cardMarketIds;
  final String cardmarketUrl;
  final String cardmarketRedirectUrl;
  final String status;
  final String reviewBucket;
}

class MarketplaceDebugArtistScreen extends ConsumerStatefulWidget {
  const MarketplaceDebugArtistScreen({super.key});

  @override
  ConsumerState<MarketplaceDebugArtistScreen> createState() =>
      _MarketplaceDebugArtistScreenState();
}

class _MarketplaceDebugArtistScreenState
    extends ConsumerState<MarketplaceDebugArtistScreen> {
  final TextEditingController _artistSearchController = TextEditingController();
  ArtistCurationCandidate? _candidate;
  bool _loading = false;
  bool _acting = false;
  String _error = '';
  String _message = '';
  String _generatedAt = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNext());
  }

  @override
  void dispose() {
    _artistSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadNext() async {
    setState(() {
      _loading = true;
      _error = '';
      _message = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient
          .get(Uri.base.resolve('/api/marketplace-debug-artists'))
          .timeout(const Duration(seconds: 16));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      if (decoded is! Map) {
        throw StateError('Unexpected artist debug payload.');
      }
      setState(() {
        final candidateJson = decoded['candidate'];
        _candidate = candidateJson is Map
            ? ArtistCurationCandidate.fromJson(candidateJson)
            : null;
        _artistSearchController.clear();
        _generatedAt = '${decoded['generatedAt'] ?? ''}';
        if (_candidate == null) {
          _message =
              '${decoded['reason'] ?? 'No artist candidates are available.'}';
        }
      });
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _postAction(Map<String, dynamic> body, String success) async {
    final candidate = _candidate;
    if (candidate == null) return;
    setState(() {
      _acting = true;
      _error = '';
      _message = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient.postJson(
        Uri.base.resolve('/api/marketplace-debug-artists'),
        body: {
          'blueprintId': candidate.blueprintId,
          ...body,
        },
      ).timeout(const Duration(seconds: 16));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success)),
        );
      }
      await _loadNext();
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  Future<void> _selectArtist(ArtistOption option) => _postAction(
        {
          'action': 'select_artist',
          'normalizedArtist': option.normalizedArtist,
        },
        'Saved ${option.artist}',
      );

  Future<void> _selectSuggestedArtist(ArtistSuggestion artist) => _postAction(
        {
          'action': 'select_artist',
          'normalizedArtist': artist.normalizedArtist,
          'allowAnyArtist': true,
        },
        'Saved ${artist.name}',
      );

  Future<void> _classifyProduct() => _postAction(
        {
          'action': 'classify_product',
          'productType': 'sealed_product',
        },
        'Classified as product',
      );

  Future<void> _skip() => _postAction(
        {'action': 'skip'},
        'Skipped for now',
      );

  @override
  Widget build(BuildContext context) {
    final candidate = _candidate;
    return _DebugGate(
      child: Scaffold(
        backgroundColor: const Color(0xFF050816),
        appBar: AppBar(
          backgroundColor: const Color(0xE60A1026),
          title: const Text('Artist Curation'),
          actions: [
            IconButton(
              onPressed: _loading || _acting ? null : _loadNext,
              tooltip: 'Load next card',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: _loading && candidate == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _ArtistCurationHeader(
                        loading: _loading || _acting,
                        generatedAt: _generatedAt,
                        error: _error,
                        message: _message,
                        onRefresh: _loadNext,
                      ),
                      const SizedBox(height: 16),
                      if (candidate == null)
                        const _EmptyArtistCurationState()
                      else
                        _ArtistCurationCard(
                          candidate: candidate,
                          acting: _acting,
                          artistSearchController: _artistSearchController,
                          onArtistSearchChanged: (_) => setState(() {}),
                          onSelectArtist: _selectArtist,
                          onSelectSuggestedArtist: _selectSuggestedArtist,
                          onClassifyProduct: _classifyProduct,
                          onSkip: _skip,
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class ArtistCurationCandidate {
  const ArtistCurationCandidate({
    required this.blueprintId,
    required this.name,
    required this.displayName,
    required this.canonicalName,
    required this.expansionName,
    required this.collectorNumber,
    required this.productVariant,
    required this.rarity,
    required this.cardType,
    required this.itemKind,
    required this.productType,
    required this.imageUrl,
    required this.previewImageUrl,
    required this.currentArtist,
    required this.currentArtistSource,
    required this.currentConfidence,
    required this.currentMatchReason,
    required this.missingReason,
    required this.artists,
  });

  factory ArtistCurationCandidate.fromJson(Map<dynamic, dynamic> json) {
    return ArtistCurationCandidate(
      blueprintId: '${json['blueprintId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      displayName: '${json['displayName'] ?? json['name'] ?? ''}',
      canonicalName: '${json['canonicalName'] ?? ''}',
      expansionName: '${json['expansionName'] ?? ''}',
      collectorNumber: '${json['collectorNumber'] ?? ''}',
      productVariant: '${json['productVariant'] ?? ''}',
      rarity: '${json['rarity'] ?? ''}',
      cardType: '${json['cardType'] ?? ''}',
      itemKind: '${json['itemKind'] ?? 'single'}',
      productType: '${json['productType'] ?? 'card'}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      previewImageUrl: '${json['previewImageUrl'] ?? ''}',
      currentArtist: '${json['currentArtist'] ?? ''}',
      currentArtistSource: '${json['currentArtistSource'] ?? ''}',
      currentConfidence: json['currentConfidence'] is num
          ? (json['currentConfidence'] as num).toDouble()
          : 0,
      currentMatchReason: '${json['currentMatchReason'] ?? ''}',
      missingReason: '${json['missingReason'] ?? ''}',
      artists: (json['artists'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(ArtistOption.fromJson)
          .toList(growable: false),
    );
  }

  final String blueprintId;
  final String name;
  final String displayName;
  final String canonicalName;
  final String expansionName;
  final String collectorNumber;
  final String productVariant;
  final String rarity;
  final String cardType;
  final String itemKind;
  final String productType;
  final String imageUrl;
  final String previewImageUrl;
  final String currentArtist;
  final String currentArtistSource;
  final double currentConfidence;
  final String currentMatchReason;
  final String missingReason;
  final List<ArtistOption> artists;
}

class ArtistOption {
  const ArtistOption({
    required this.normalizedArtist,
    required this.artist,
    required this.knownCount,
    required this.examples,
  });

  factory ArtistOption.fromJson(Map<dynamic, dynamic> json) {
    return ArtistOption(
      normalizedArtist: '${json['normalizedArtist'] ?? ''}',
      artist: '${json['artist'] ?? ''}',
      knownCount:
          json['knownCount'] is num ? (json['knownCount'] as num).toInt() : 0,
      examples: (json['examples'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(ArtistExample.fromJson)
          .toList(growable: false),
    );
  }

  final String normalizedArtist;
  final String artist;
  final int knownCount;
  final List<ArtistExample> examples;

  ArtistSuggestion toSuggestion() {
    return ArtistSuggestion(
      name: artist,
      normalizedArtist: normalizedArtist,
      slug: '',
      knownCount: knownCount,
    );
  }
}

class ArtistExample {
  const ArtistExample({
    required this.blueprintId,
    required this.name,
    required this.setName,
    required this.collectorNumber,
  });

  factory ArtistExample.fromJson(Map<dynamic, dynamic> json) {
    return ArtistExample(
      blueprintId: '${json['blueprintId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      setName: '${json['setName'] ?? ''}',
      collectorNumber: '${json['collectorNumber'] ?? ''}',
    );
  }

  final String blueprintId;
  final String name;
  final String setName;
  final String collectorNumber;
}

class MarketplaceCardmarketGuessReviewScreen extends ConsumerStatefulWidget {
  const MarketplaceCardmarketGuessReviewScreen({super.key});

  @override
  ConsumerState<MarketplaceCardmarketGuessReviewScreen> createState() =>
      _MarketplaceCardmarketGuessReviewScreenState();
}

class _MarketplaceCardmarketGuessReviewScreenState
    extends ConsumerState<MarketplaceCardmarketGuessReviewScreen> {
  List<CardmarketGuessRow> _guesses = const [];
  List<CardmarketGuessRow> _riskyGuesses = const [];
  List<MissingCardmarketExpansion> _missingExpansions = const [];
  bool _loading = false;
  String _error = '';
  String _generatedAt = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRows());
  }

  Future<void> _loadRows() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient
          .get(
            Uri.base.resolve(
              '/api/marketplace-cardmarket-guess-review?limit=220&missingLimit=160',
            ),
          )
          .timeout(const Duration(seconds: 16));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      if (decoded is! Map) {
        throw StateError('Unexpected guess-review payload.');
      }
      setState(() {
        _guesses = (decoded['guesses'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => CardmarketGuessRow.fromJson(row))
            .toList(growable: false);
        _riskyGuesses = (decoded['riskyGuesses'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => CardmarketGuessRow.fromJson(row))
            .toList(growable: false);
        _missingExpansions =
            (decoded['missingExpansions'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((row) => MissingCardmarketExpansion.fromJson(row))
                .toList(growable: false);
        _generatedAt = '${decoded['generatedAt'] ?? ''}';
      });
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayGuesses =
        _riskyGuesses.isEmpty ? _guesses.take(80).toList() : _riskyGuesses;
    return _DebugGate(
      child: Scaffold(
        backgroundColor: const Color(0xFF050816),
        appBar: AppBar(
          backgroundColor: const Color(0xE60A1026),
          title: const Text('Cardmarket Guess Review'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _loadRows,
              tooltip: 'Refresh guesses',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: _loading && _guesses.isEmpty && _error.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _GuessReviewHeader(
                        loading: _loading,
                        generatedAt: _generatedAt,
                        error: _error,
                        totalGuesses: _guesses.length,
                        riskyGuesses: _riskyGuesses.length,
                        missingExpansions: _missingExpansions.length,
                        onRefresh: _loadRows,
                      ),
                      const SizedBox(height: 14),
                      if (_missingExpansions.isNotEmpty)
                        _MissingExpansionPanel(rows: _missingExpansions),
                      const SizedBox(height: 14),
                      Text(
                        _riskyGuesses.isEmpty
                            ? 'Recent Verified Imports'
                            : 'Risky / Exact-Only Guesses To Double Check',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final row in displayGuesses) ...[
                        _CardmarketGuessTile(row: row),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class MarketplaceDebugEventsScreen extends ConsumerStatefulWidget {
  const MarketplaceDebugEventsScreen({super.key});

  @override
  ConsumerState<MarketplaceDebugEventsScreen> createState() =>
      _MarketplaceDebugEventsScreenState();
}

class _MarketplaceDebugEventsScreenState
    extends ConsumerState<MarketplaceDebugEventsScreen> {
  static const _eventTypes = [
    '',
    'view',
    'search',
    'click',
    'cart_add',
    'reserve',
    'sale'
  ];
  static const _windows = ['15m', '1h', '24h', '7d'];

  final TextEditingController _cardIdController = TextEditingController();
  final TextEditingController _userUidController = TextEditingController();
  List<MarketplaceDebugEventRow> _events = const [];
  Map<String, int> _summary = const {};
  bool _loading = false;
  String _error = '';
  String _generatedAt = '';
  String _eventType = '';
  String _window = '24h';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEvents());
  }

  @override
  void dispose() {
    _cardIdController.dispose();
    _userUidController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final params = <String, String>{
        'limit': '220',
        'window': _window,
        if (_eventType.isNotEmpty) 'eventType': _eventType,
        if (_cardIdController.text.trim().isNotEmpty)
          'cardId': _cardIdController.text.trim(),
        if (_userUidController.text.trim().isNotEmpty)
          'userUid': _userUidController.text.trim(),
      };
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient
          .get(
            Uri.base.resolve('/api/marketplace-debug-events').replace(
                  queryParameters: params,
                ),
          )
          .timeout(const Duration(seconds: 14));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      if (decoded is! Map || decoded['rows'] is! List) {
        throw StateError('Unexpected event-log payload.');
      }
      setState(() {
        _events = (decoded['rows'] as List<dynamic>)
            .whereType<Map>()
            .map(MarketplaceDebugEventRow.fromJson)
            .toList(growable: false);
        _summary = (decoded['summary'] as Map<dynamic, dynamic>? ?? const {})
            .map((key, value) =>
                MapEntry('$key', value is num ? value.toInt() : 0));
        _generatedAt = '${decoded['generatedAt'] ?? ''}';
      });
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DebugGate(
      child: Scaffold(
        backgroundColor: const Color(0xFF050816),
        appBar: AppBar(
          backgroundColor: const Color(0xE60A1026),
          title: const Text('Marketplace Event Log'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _loadEvents,
              tooltip: 'Refresh events',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: Column(
              children: [
                _EventLogFilters(
                  loading: _loading,
                  generatedAt: _generatedAt,
                  error: _error,
                  eventType: _eventType,
                  eventTypes: _eventTypes,
                  window: _window,
                  windows: _windows,
                  cardIdController: _cardIdController,
                  userUidController: _userUidController,
                  summary: _summary,
                  onEventTypeChanged: (value) {
                    setState(() => _eventType = value ?? '');
                    _loadEvents();
                  },
                  onWindowChanged: (value) {
                    setState(() => _window = value ?? '24h');
                    _loadEvents();
                  },
                  onApply: _loading ? null : _loadEvents,
                ),
                Expanded(
                  child: _loading && _events.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _events.isEmpty
                          ? const Center(
                              child: Text(
                                'No events found for these filters.',
                                style: TextStyle(color: Color(0xFF93A4C8)),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: _events.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _EventLogTile(event: _events[index]),
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MarketplaceDebugEventRow {
  const MarketplaceDebugEventRow({
    required this.id,
    required this.cardId,
    required this.userUid,
    required this.eventType,
    required this.weight,
    required this.occurredAt,
    required this.metadata,
    required this.cardName,
    required this.setName,
    required this.collectorNumber,
    required this.imageUrl,
  });

  factory MarketplaceDebugEventRow.fromJson(Map<dynamic, dynamic> json) {
    final card = json['card'] is Map ? json['card'] as Map : const {};
    return MarketplaceDebugEventRow(
      id: '${json['id'] ?? ''}',
      cardId: '${json['cardId'] ?? ''}',
      userUid: '${json['userUid'] ?? ''}',
      eventType: '${json['eventType'] ?? ''}',
      weight: json['weight'] is num ? (json['weight'] as num).toDouble() : 0,
      occurredAt: '${json['occurredAt'] ?? ''}',
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      cardName: '${card['name'] ?? ''}',
      setName: '${card['setName'] ?? ''}',
      collectorNumber: '${card['collectorNumber'] ?? ''}',
      imageUrl: '${card['imageUrl'] ?? ''}',
    );
  }

  final String id;
  final String cardId;
  final String userUid;
  final String eventType;
  final double weight;
  final String occurredAt;
  final Map<String, dynamic> metadata;
  final String cardName;
  final String setName;
  final String collectorNumber;
  final String imageUrl;
}

class _EventLogFilters extends StatelessWidget {
  const _EventLogFilters({
    required this.loading,
    required this.generatedAt,
    required this.error,
    required this.eventType,
    required this.eventTypes,
    required this.window,
    required this.windows,
    required this.cardIdController,
    required this.userUidController,
    required this.summary,
    required this.onEventTypeChanged,
    required this.onWindowChanged,
    required this.onApply,
  });

  final bool loading;
  final String generatedAt;
  final String error;
  final String eventType;
  final List<String> eventTypes;
  final String window;
  final List<String> windows;
  final TextEditingController cardIdController;
  final TextEditingController userUidController;
  final Map<String, int> summary;
  final ValueChanged<String?> onEventTypeChanged;
  final ValueChanged<String?> onWindowChanged;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final summaryEntries = summary.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: Color(0xFFFACC15)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error.isNotEmpty
                      ? error
                      : 'Recent marketplace events${generatedAt.isEmpty ? '' : ' • $generatedAt'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: error.isNotEmpty
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFE2E8F0),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: loading ? null : onApply,
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(loading ? 'Loading' : 'Apply'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  initialValue: window,
                  items: [
                    for (final value in windows)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ),
                  ],
                  onChanged: loading ? null : onWindowChanged,
                  decoration: const InputDecoration(
                    labelText: 'Window',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  initialValue: eventType,
                  items: [
                    for (final value in eventTypes)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value.isEmpty ? 'all events' : value),
                      ),
                  ],
                  onChanged: loading ? null : onEventTypeChanged,
                  decoration: const InputDecoration(
                    labelText: 'Event type',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: cardIdController,
                  enabled: !loading,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Card ID',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onApply?.call(),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: userUidController,
                  enabled: !loading,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'User UID',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onApply?.call(),
                ),
              ),
            ],
          ),
          if (summaryEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in summaryEntries)
                  Chip(
                    label: Text('${entry.key}: ${entry.value}'),
                    backgroundColor: const Color(0xFF111936),
                    labelStyle: const TextStyle(color: Color(0xFFE2E8F0)),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EventLogTile extends StatelessWidget {
  const _EventLogTile({required this.event});

  final MarketplaceDebugEventRow event;

  @override
  Widget build(BuildContext context) {
    final title = event.cardName.isEmpty
        ? 'Card ${event.cardId}'
        : '${event.cardName} #${event.cardId}';
    final metadataEntries = event.metadata.entries
        .where((entry) => '${entry.value}'.trim().isNotEmpty)
        .toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: event.imageUrl.isEmpty
                ? Container(
                    width: 58,
                    height: 80,
                    color: const Color(0xFF111936),
                    child: const Icon(Icons.image_not_supported_outlined),
                  )
                : Image.network(
                    event.imageUrl,
                    width: 58,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 58,
                      height: 80,
                      color: const Color(0xFF111936),
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(event.eventType),
                      backgroundColor: const Color(0x3322C55E),
                      labelStyle: const TextStyle(color: Color(0xFFBBF7D0)),
                      side: BorderSide.none,
                    ),
                    Chip(
                      label: Text('weight ${event.weight.toStringAsFixed(0)}'),
                      backgroundColor: const Color(0x3314B8A6),
                      labelStyle: const TextStyle(color: Color(0xFF99F6E4)),
                      side: BorderSide.none,
                    ),
                    if (event.userUid.isNotEmpty)
                      Chip(
                        label: Text('user ${event.userUid}'),
                        backgroundColor: const Color(0x331E40AF),
                        labelStyle: const TextStyle(color: Color(0xFFBFDBFE)),
                        side: BorderSide.none,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    event.setName,
                    event.collectorNumber,
                    event.occurredAt,
                  ].where((part) => part.trim().isNotEmpty).join(' • '),
                  style: const TextStyle(color: Color(0xFF93A4C8)),
                ),
                if (metadataEntries.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in metadataEntries.take(10))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111936),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            '${entry.key}: ${entry.value}',
                            style: const TextStyle(
                              color: Color(0xFFE2E8F0),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CardmarketGuessRow {
  const CardmarketGuessRow({
    required this.blueprintId,
    required this.name,
    required this.cardmarketName,
    required this.expansionName,
    required this.cardmarketExpansionSlug,
    required this.collectorNumber,
    required this.normalizedCollectorNumber,
    required this.productVariant,
    required this.imageUrl,
    required this.cardMarketIds,
    required this.cardmarketUrl,
    required this.cardmarketProductSlug,
    required this.cardmarketSetCode,
    required this.cardmarketContextCode,
    required this.cardmarketVariantMarker,
    required this.verificationMethod,
    required this.verificationSource,
    required this.notes,
    required this.reviewStatus,
    required this.ruleSetCode,
    required this.ruleNumberFormatRule,
    required this.ruleSource,
  });

  factory CardmarketGuessRow.fromJson(Map<dynamic, dynamic> json) {
    return CardmarketGuessRow(
      blueprintId: '${json['blueprintId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      cardmarketName: '${json['cardmarketName'] ?? ''}',
      expansionName: '${json['expansionName'] ?? ''}',
      cardmarketExpansionSlug: '${json['cardmarketExpansionSlug'] ?? ''}',
      collectorNumber: '${json['collectorNumber'] ?? ''}',
      normalizedCollectorNumber: '${json['normalizedCollectorNumber'] ?? ''}',
      productVariant: '${json['productVariant'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      cardMarketIds: (json['cardMarketIds'] as List<dynamic>? ?? const [])
          .map((value) => '$value')
          .toList(growable: false),
      cardmarketUrl: '${json['cardmarketUrl'] ?? ''}',
      cardmarketProductSlug: '${json['cardmarketProductSlug'] ?? ''}',
      cardmarketSetCode: '${json['cardmarketSetCode'] ?? ''}',
      cardmarketContextCode: '${json['cardmarketContextCode'] ?? ''}',
      cardmarketVariantMarker: '${json['cardmarketVariantMarker'] ?? ''}',
      verificationMethod: '${json['verificationMethod'] ?? ''}',
      verificationSource: '${json['verificationSource'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      reviewStatus: '${json['reviewStatus'] ?? ''}',
      ruleSetCode: '${json['ruleSetCode'] ?? ''}',
      ruleNumberFormatRule: '${json['ruleNumberFormatRule'] ?? ''}',
      ruleSource: '${json['ruleSource'] ?? ''}',
    );
  }

  final String blueprintId;
  final String name;
  final String cardmarketName;
  final String expansionName;
  final String cardmarketExpansionSlug;
  final String collectorNumber;
  final String normalizedCollectorNumber;
  final String productVariant;
  final String imageUrl;
  final List<String> cardMarketIds;
  final String cardmarketUrl;
  final String cardmarketProductSlug;
  final String cardmarketSetCode;
  final String cardmarketContextCode;
  final String cardmarketVariantMarker;
  final String verificationMethod;
  final String verificationSource;
  final String notes;
  final String reviewStatus;
  final String ruleSetCode;
  final String ruleNumberFormatRule;
  final String ruleSource;
}

class MissingCardmarketExpansion {
  const MissingCardmarketExpansion({
    required this.expansionName,
    required this.appliesToCardType,
    required this.cardCount,
    required this.verifiedCount,
    required this.sampleBlueprintId,
    required this.sampleName,
    required this.sampleCollectorNumber,
    required this.sampleImageUrl,
  });

  factory MissingCardmarketExpansion.fromJson(Map<dynamic, dynamic> json) {
    return MissingCardmarketExpansion(
      expansionName: '${json['expansionName'] ?? ''}',
      appliesToCardType: '${json['appliesToCardType'] ?? ''}',
      cardCount:
          json['cardCount'] is num ? (json['cardCount'] as num).toInt() : 0,
      verifiedCount: json['verifiedCount'] is num
          ? (json['verifiedCount'] as num).toInt()
          : 0,
      sampleBlueprintId: '${json['sampleBlueprintId'] ?? ''}',
      sampleName: '${json['sampleName'] ?? ''}',
      sampleCollectorNumber: '${json['sampleCollectorNumber'] ?? ''}',
      sampleImageUrl: '${json['sampleImageUrl'] ?? ''}',
    );
  }

  final String expansionName;
  final String appliesToCardType;
  final int cardCount;
  final int verifiedCount;
  final String sampleBlueprintId;
  final String sampleName;
  final String sampleCollectorNumber;
  final String sampleImageUrl;
}

class _DebugGate extends ConsumerWidget {
  const _DebugGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profileState = ref.watch(userProfileProvider);
    final profile = profileState.valueOrNull;
    if (user == null) {
      return _DebugAccessMessage(
        title: 'Sign in required',
        body: 'Log in with a debug-enabled account to open marketplace debug.',
        actionLabel: 'Sign in',
        onAction: () =>
            context.go('/auth?from=${Uri.encodeComponent(Uri.base.path)}'),
      );
    }
    if (profileState.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF050816),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isDebugProfile(profile)) {
      return const _DebugAccessMessage(
        title: 'Debug access required',
        body:
            'This account is signed in, but marketplace debug is not enabled.',
      );
    }
    return child;
  }
}

bool _isDebugProfile(AppUserProfile? profile) {
  final username = profile?.username.trim().toLowerCase() ?? '';
  final email = profile?.email.trim().toLowerCase() ?? '';
  return username == 'vitologiuseppe17' ||
      email == 'vitologiuseppe17@gmail.com' ||
      email == 'pokoinpos@gmail.com' ||
      (profile?.hasAdminAccess ?? false);
}

class _DebugHero extends StatelessWidget {
  const _DebugHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Marketplace Debug Panel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Human tools for refinement jobs that are not deterministic enough for automation.',
            style: TextStyle(color: Color(0xFF93A4C8)),
          ),
        ],
      ),
    );
  }
}

class _DebugToolCard extends StatelessWidget {
  const _DebugToolCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String body;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1020),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFFACC15), size: 30),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(body, style: const TextStyle(color: Color(0xFF93A4C8))),
              const SizedBox(height: 18),
              FilledButton(onPressed: onTap, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefinementHeader extends StatelessWidget {
  const _RefinementHeader({
    required this.count,
    required this.loading,
    required this.generatedAt,
    required this.error,
    required this.onRefresh,
  });

  final int count;
  final bool loading;
  final String generatedAt;
  final String error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.manage_search, color: Color(0xFFFACC15)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error.isNotEmpty
                  ? error
                  : '$count random cards loaded${generatedAt.isEmpty ? '' : ' • $generatedAt'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: error.isNotEmpty
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFFE2E8F0),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.shuffle),
            label: Text(loading ? 'Loading' : 'Random 1000'),
          ),
        ],
      ),
    );
  }
}

class _GuessReviewHeader extends StatelessWidget {
  const _GuessReviewHeader({
    required this.loading,
    required this.generatedAt,
    required this.error,
    required this.totalGuesses,
    required this.riskyGuesses,
    required this.missingExpansions,
    required this.onRefresh,
  });

  final bool loading;
  final String generatedAt;
  final String error;
  final int totalGuesses;
  final int riskyGuesses;
  final int missingExpansions;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: Color(0xFFFACC15)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  error.isNotEmpty
                      ? error
                      : 'Review guesses and missing expansion mappings${generatedAt.isEmpty ? '' : ' • $generatedAt'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: error.isNotEmpty
                        ? const Color(0xFFFCA5A5)
                        : Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: Text(loading ? 'Loading' : 'Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipText('$totalGuesses verified imports'),
              _ChipText('$riskyGuesses to double check'),
              _ChipText('$missingExpansions missing expansion rules'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArtistCurationHeader extends StatelessWidget {
  const _ArtistCurationHeader({
    required this.loading,
    required this.generatedAt,
    required this.error,
    required this.message,
    required this.onRefresh,
  });

  final bool loading;
  final String generatedAt;
  final String error;
  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final hasError = error.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.brush_outlined, color: Color(0xFFFACC15)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasError
                  ? error
                  : message.isNotEmpty
                      ? message
                      : 'Choose the correct artist from existing same-Pokémon artists${generatedAt.isEmpty ? '' : ' • $generatedAt'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hasError ? const Color(0xFFFCA5A5) : Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(loading ? 'Loading' : 'Next'),
          ),
        ],
      ),
    );
  }
}

class _ArtistCurationCard extends StatelessWidget {
  const _ArtistCurationCard({
    required this.candidate,
    required this.acting,
    required this.artistSearchController,
    required this.onArtistSearchChanged,
    required this.onSelectArtist,
    required this.onSelectSuggestedArtist,
    required this.onClassifyProduct,
    required this.onSkip,
  });

  final ArtistCurationCandidate candidate;
  final bool acting;
  final TextEditingController artistSearchController;
  final ValueChanged<String> onArtistSearchChanged;
  final ValueChanged<ArtistOption> onSelectArtist;
  final ValueChanged<ArtistSuggestion> onSelectSuggestedArtist;
  final VoidCallback onClassifyProduct;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final imageUrl = candidate.imageUrl.isNotEmpty
        ? candidate.imageUrl
        : candidate.previewImageUrl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final imagePanel = _LargeArtistCardImage(
          imageUrl: imageUrl,
        );
        final detailPanel = _ArtistCurationDetails(
          candidate: candidate,
          acting: acting,
          artistSearchController: artistSearchController,
          onArtistSearchChanged: onArtistSearchChanged,
          onSelectArtist: onSelectArtist,
          onSelectSuggestedArtist: onSelectSuggestedArtist,
          onClassifyProduct: onClassifyProduct,
          onSkip: onSkip,
        );
        if (!wide) {
          return Column(
            children: [
              imagePanel,
              const SizedBox(height: 16),
              detailPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 520, child: imagePanel),
            const SizedBox(width: 18),
            Expanded(child: detailPanel),
          ],
        );
      },
    );
  }
}

class _LargeArtistCardImage extends StatelessWidget {
  const _LargeArtistCardImage({
    required this.imageUrl,
  });

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: imageUrl.isEmpty
                  ? Container(
                      height: 720,
                      alignment: Alignment.center,
                      color: const Color(0xFF111936),
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        size: 54,
                        color: Color(0xFF93A4C8),
                      ),
                    )
                  : Image.network(
                      imageUrl,
                      height: 720,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Container(
                        height: 720,
                        alignment: Alignment.center,
                        color: const Color(0xFF111936),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 54,
                          color: Color(0xFFFCA5A5),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  imageUrl,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Color(0xFF93C5FD),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: imageUrl.isEmpty
                    ? null
                    : () => launchUrl(
                          Uri.parse(imageUrl),
                          mode: LaunchMode.externalApplication,
                          webOnlyWindowName: '_blank',
                        ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open image'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArtistCurationDetails extends StatelessWidget {
  const _ArtistCurationDetails({
    required this.candidate,
    required this.acting,
    required this.artistSearchController,
    required this.onArtistSearchChanged,
    required this.onSelectArtist,
    required this.onSelectSuggestedArtist,
    required this.onClassifyProduct,
    required this.onSkip,
  });

  final ArtistCurationCandidate candidate;
  final bool acting;
  final TextEditingController artistSearchController;
  final ValueChanged<String> onArtistSearchChanged;
  final ValueChanged<ArtistOption> onSelectArtist;
  final ValueChanged<ArtistSuggestion> onSelectSuggestedArtist;
  final VoidCallback onClassifyProduct;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final detailPath = '/marketplace/en/cards/${candidate.blueprintId}';
    final artistSearchQuery = artistSearchController.text.trim().toLowerCase();
    final visibleArtists = artistSearchQuery.isEmpty
        ? candidate.artists
        : candidate.artists
            .where(
              (option) =>
                  option.artist.toLowerCase().contains(artistSearchQuery),
            )
            .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            candidate.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${candidate.expansionName} • ${candidate.collectorNumber}',
            style: const TextStyle(color: Color(0xFF93A4C8)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipText('Blueprint ${candidate.blueprintId}'),
              _ChipText('Identity ${candidate.canonicalName}'),
              _ChipText(candidate.missingReason),
              _ChipText('${candidate.itemKind}/${candidate.productType}'),
              if (candidate.productVariant.isNotEmpty)
                _ChipText('Variant ${candidate.productVariant}'),
              if (candidate.rarity.isNotEmpty) _ChipText(candidate.rarity),
            ],
          ),
          if (candidate.currentArtist.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Current: ${candidate.currentArtist} (${candidate.currentArtistSource}, ${(candidate.currentConfidence * 100).round()}%)',
              style: const TextStyle(color: Color(0xFFFDE68A)),
            ),
            if (candidate.currentMatchReason.isNotEmpty)
              Text(
                candidate.currentMatchReason,
                style: const TextStyle(color: Color(0xFFB8C4E6)),
              ),
          ],
          const SizedBox(height: 18),
          const Text(
            'Possible Artists',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          if (candidate.artists.isNotEmpty) ...[
            ArtistSuggestionField(
              controller: artistSearchController,
              enabled: !acting,
              helperText: artistSearchQuery.isEmpty
                  ? null
                  : '${visibleArtists.length} of ${candidate.artists.length} same-Pokemon artists',
              fallbackSuggestions: candidate.artists
                  .map((option) => option.toSuggestion())
                  .toList(growable: false),
              onChanged: onArtistSearchChanged,
              onSelected: onSelectSuggestedArtist,
            ),
            const SizedBox(height: 10),
          ],
          if (candidate.artists.isEmpty)
            const Text(
              'No known same-Pokémon artists were found.',
              style: TextStyle(color: Color(0xFFFCA5A5)),
            )
          else if (visibleArtists.isEmpty)
            const Text(
              'No possible artists match this search.',
              style: TextStyle(color: Color(0xFFFCA5A5)),
            )
          else
            for (final option in visibleArtists) ...[
              _ArtistOptionButton(
                option: option,
                disabled: acting,
                onPressed: () => onSelectArtist(option),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: acting ? null : () => context.go(detailPath),
                child: const Text('Open Pokoin card'),
              ),
              OutlinedButton.icon(
                onPressed: acting ? null : onSkip,
                icon: const Icon(Icons.skip_next),
                label: const Text('Skip'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                ),
                onPressed: acting ? null : onClassifyProduct,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Classify as product'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArtistOptionButton extends StatelessWidget {
  const _ArtistOptionButton({
    required this.option,
    required this.disabled,
    required this.onPressed,
  });

  final ArtistOption option;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final examples = option.examples
        .map(
          (example) =>
              '${example.name} ${example.collectorNumber} (${example.setName})',
        )
        .join(' • ');
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: disabled ? null : onPressed,
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.all(14),
          backgroundColor: const Color(0xFF1E3A8A),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${option.artist} • ${option.knownCount} known',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (examples.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                examples,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFBFDBFE),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyArtistCurationState extends StatelessWidget {
  const _EmptyArtistCurationState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Text(
        'No card is available for artist curation right now.',
        style: TextStyle(color: Color(0xFF93A4C8)),
      ),
    );
  }
}

class _MissingExpansionPanel extends StatelessWidget {
  const _MissingExpansionPanel({required this.rows});

  final List<MissingCardmarketExpansion> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF190B12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEF4444)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF87171)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Missing Expansion Matching',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'These expansion/type combinations do not have a reusable Cardmarket expansion rule yet. They stay red until a safe slug/code rule is learned.',
            style: TextStyle(color: Color(0xFFFECACA)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: rows
                .take(80)
                .map((row) => _MissingExpansionChip(row: row))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _MissingExpansionChip extends StatelessWidget {
  const _MissingExpansionChip({required this.row});

  final MissingCardmarketExpansion row;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 286,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0E17),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDC2626)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: row.sampleImageUrl.isEmpty
                ? Container(
                    width: 42,
                    height: 58,
                    color: const Color(0xFF111936),
                    child: const Icon(Icons.image_not_supported_outlined),
                  )
                : Image.network(
                    row.sampleImageUrl,
                    width: 42,
                    height: 58,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 42,
                      height: 58,
                      color: const Color(0xFF111936),
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.expansionName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${row.appliesToCardType} • ${row.cardCount} cards • ${row.verifiedCount} links',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${row.sampleName} ${row.sampleCollectorNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFECACA),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardmarketGuessTile extends StatelessWidget {
  const _CardmarketGuessTile({required this.row});

  final CardmarketGuessRow row;

  Color get _statusColor {
    switch (row.reviewStatus) {
      case 'safe_verified':
        return const Color(0xFF22C55E);
      case 'variant_marker':
        return const Color(0xFFFACC15);
      case 'exact_only_name_or_special_slug':
        return const Color(0xFFF97316);
      default:
        return const Color(0xFFEF4444);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailPath = '/marketplace/en/cards/${row.blueprintId}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _statusColor.withValues(alpha: 0.75)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: row.imageUrl.isEmpty
                ? Container(
                    width: 92,
                    height: 128,
                    color: const Color(0xFF111936),
                    child: const Icon(Icons.image_not_supported_outlined),
                  )
                : Image.network(
                    row.imageUrl,
                    width: 92,
                    height: 128,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 92,
                      height: 128,
                      color: const Color(0xFF111936),
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _StatusPill(text: row.reviewStatus, color: _statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${row.expansionName} • ${row.collectorNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF93A4C8)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ChipText('Blueprint ${row.blueprintId}'),
                    if (row.cardMarketIds.isNotEmpty)
                      _ChipText('CM id ${row.cardMarketIds.join(', ')}'),
                    _ChipText('slug ${row.cardmarketExpansionSlug}'),
                    if (row.cardmarketSetCode.isNotEmpty)
                      _ChipText('code ${row.cardmarketSetCode}'),
                    if (row.cardmarketVariantMarker.isNotEmpty)
                      _ChipText('variant ${row.cardmarketVariantMarker}'),
                    if (row.ruleSetCode.isNotEmpty)
                      _ChipText('rule ${row.ruleSetCode}'),
                    _ChipText(row.verificationMethod),
                  ],
                ),
                if (row.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    row.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SelectableText(
                  row.cardmarketUrl,
                  style: const TextStyle(
                    color: Color(0xFF93C5FD),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => context.go(detailPath),
                child: const Text('Pokoin'),
              ),
              FilledButton.icon(
                onPressed: row.cardmarketUrl.isEmpty
                    ? null
                    : () => launchUrl(
                          Uri.parse(row.cardmarketUrl),
                          mode: LaunchMode.externalApplication,
                          webOnlyWindowName: '_blank',
                        ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Cardmarket'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RefinementRowTile extends ConsumerStatefulWidget {
  const _RefinementRowTile({required this.row});

  final CardmarketRefinementRow row;

  @override
  ConsumerState<_RefinementRowTile> createState() => _RefinementRowTileState();
}

class _RefinementRowTileState extends ConsumerState<_RefinementRowTile> {
  late final TextEditingController _urlController;
  Timer? _autoSaveTimer;
  bool _saving = false;
  bool _saved = false;
  bool _confirming = false;
  bool _confirmed = false;
  String _error = '';
  String _lastSubmittedUrl = '';
  String _lastSavedUrl = '';

  CardmarketRefinementRow get row => widget.row;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _urlController.addListener(_scheduleAutoSave);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _urlController.removeListener(_scheduleAutoSave);
    _urlController.dispose();
    super.dispose();
  }

  void _scheduleAutoSave() {
    final pastedUrl = _urlController.text.trim();
    if (pastedUrl != _lastSavedUrl) {
      setState(() => _saved = false);
    }
    _autoSaveTimer?.cancel();
    if (!_looksLikeCardmarketSinglesUrl(pastedUrl) ||
        pastedUrl == _lastSubmittedUrl ||
        pastedUrl == _lastSavedUrl) {
      return;
    }
    _autoSaveTimer = Timer(const Duration(milliseconds: 650), _save);
  }

  bool _looksLikeCardmarketSinglesUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'www.cardmarket.com' || uri.host == 'cardmarket.com') &&
        uri.path.startsWith('/en/Pokemon/Products/Singles');
  }

  Future<void> _save() async {
    final pastedUrl = _urlController.text.trim();
    if (pastedUrl.isEmpty) {
      setState(() => _error = 'Paste the correct Cardmarket URL first.');
      return;
    }
    if (pastedUrl == _lastSubmittedUrl || pastedUrl == _lastSavedUrl) {
      return;
    }
    _lastSubmittedUrl = pastedUrl;
    setState(() {
      _saving = true;
      _saved = false;
      _error = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient.postJson(
        Uri.base.resolve('/api/marketplace-debug-refinement'),
        body: {
          'blueprintId': row.blueprintId,
          'cardmarketUrl': pastedUrl,
          'candidateCardmarketUrl': row.cardmarketUrl,
          'cardName': row.name,
          'expansionName': row.expansionName,
          'collectorNumber': row.collectorNumber,
          'cardMarketIds': row.cardMarketIds,
        },
      ).timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      setState(() {
        _saved = true;
        _lastSavedUrl = pastedUrl;
      });
    } catch (error) {
      _lastSubmittedUrl = '';
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _confirmCurrentUrl() async {
    if (row.cardmarketUrl.isEmpty) {
      setState(() => _error = 'No Cardmarket URL to confirm.');
      return;
    }
    setState(() {
      _confirming = true;
      _error = '';
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        throw StateError('Sign in with a debug-enabled account first.');
      }
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient.postJson(
        Uri.base.resolve('/api/marketplace-debug-refinement'),
        body: {
          'action': 'confirm_current_url',
          'blueprintId': row.blueprintId,
          'cardmarketUrl': row.cardmarketUrl,
          'cardName': row.name,
          'expansionName': row.expansionName,
          'collectorNumber': row.collectorNumber,
          'cardMarketIds': row.cardMarketIds,
        },
      ).timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map ? decoded['error'] : null;
        throw StateError('$message');
      }
      setState(() => _confirmed = true);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _confirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailPath = '/marketplace/en/cards/${row.blueprintId}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: row.imageUrl.isEmpty
                      ? Container(
                          width: 84,
                          height: 116,
                          color: const Color(0xFF111936),
                          child: const Icon(Icons.image_not_supported_outlined),
                        )
                      : Image.network(
                          row.imageUrl,
                          width: 84,
                          height: 116,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 84,
                            height: 116,
                            color: const Color(0xFF111936),
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _urlController,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Paste URL, autosaves',
                    hintStyle: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF111936),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: Icon(_saved ? Icons.check : Icons.save_outlined),
                    label: Text(_saving
                        ? 'Saving'
                        : _saved
                            ? 'Saved'
                            : 'Save now'),
                  ),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${row.expansionName} • ${row.collectorNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF93A4C8)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ChipText('Blueprint ${row.blueprintId}'),
                    if (row.productVariant.isNotEmpty)
                      _ChipText('Variant ${row.productVariant}'),
                    if (row.cardMarketIds.isNotEmpty)
                      _ChipText('CM id ${row.cardMarketIds.join(', ')}'),
                    if (row.reviewBucket == 'verified_audit')
                      const _ChipText('audit verified')
                    else
                      const _ChipText('candidate review'),
                    _ChipText(row.status),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => context.go(detailPath),
                child: const Text('Pokoin'),
              ),
              FilledButton.icon(
                onPressed: row.cardmarketUrl.isEmpty
                    ? null
                    : () => launchUrl(
                          Uri.parse(row.cardmarketUrl),
                          mode: LaunchMode.externalApplication,
                          webOnlyWindowName: '_blank',
                        ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Cardmarket'),
              ),
              OutlinedButton.icon(
                onPressed:
                    row.cardmarketUrl.isEmpty || _confirming || _confirmed
                        ? null
                        : _confirmCurrentUrl,
                icon: Icon(
                  _confirmed ? Icons.verified : Icons.check_circle_outline,
                ),
                label: Text(
                  _confirming
                      ? 'Confirming'
                      : _confirmed
                          ? 'Already OK'
                          : 'Already OK',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipText extends StatelessWidget {
  const _ChipText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DebugAccessMessage extends StatelessWidget {
  const _DebugAccessMessage({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: Center(
        child: Container(
          width: 420,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1020),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(color: Color(0xFF93A4C8))),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
