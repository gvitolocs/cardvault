import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';
import '../widgets/site_footer.dart';

class ScanScreen extends StatefulWidget {
  final String? initialQuery;

  const ScanScreen({super.key, this.initialQuery});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TextEditingController _searchController = TextEditingController();
  ExplorerSnapshot? _snapshot;
  bool _isRefreshingSnapshot = true;
  Object? _snapshotError;
  Future<SearchResult?>? _search;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
    _applyInitialQuery();
  }

  @override
  void didUpdateWidget(covariant ScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery) {
      _applyInitialQuery();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    _loadSnapshot(force: true);
  }

  Future<void> _loadSnapshot({bool force = false}) async {
    if (!force) {
      final cached = await ExplorerSnapshot.cached();
      if (mounted && cached != null) {
        setState(() {
          _snapshot = cached;
          _isRefreshingSnapshot = true;
          _snapshotError = null;
        });
      }
    } else if (mounted) {
      setState(() {
        _isRefreshingSnapshot = true;
        _snapshotError = null;
      });
    }

    try {
      final fresh = await ExplorerSnapshot.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = fresh;
        _isRefreshingSnapshot = false;
        _snapshotError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRefreshingSnapshot = false;
        _snapshotError = error;
      });
    }
  }

  void _applyInitialQuery() {
    final query = widget.initialQuery?.trim();
    if (query == null || query.isEmpty) {
      return;
    }
    _searchController.text = query;
    _search = SearchResult.search(query);
  }

  void _runSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return;
    }
    setState(() {
      _search = SearchResult.search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: _ExplorerTopBar(onRefresh: _refresh),
      body: Builder(
        builder: (context) {
          final data = _snapshot;
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroSearch(
                      loading: _isRefreshingSnapshot && data == null,
                      controller: _searchController,
                      onSearch: _runSearch,
                    ),
                    if (_snapshotError != null) ...[
                      const SizedBox(height: 16),
                      _Notice(
                        title: 'Explorer data unavailable',
                        body: _snapshotError.toString(),
                      ),
                    ],
                    if (_search != null) ...[
                      const SizedBox(height: 16),
                      FutureBuilder<SearchResult?>(
                        future: _search,
                        builder: (context, result) => _SearchPanel(
                          loading:
                              result.connectionState != ConnectionState.done,
                          result: result.data,
                          error: result.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _StatsGrid(snapshot: data),
                    const SizedBox(height: 18),
                    _TransactionsPanel(
                        transactions: data?.transactions ?? const []),
                    const SizedBox(height: 18),
                    _ResponsiveColumns(
                      left: _BlocksPanel(blocks: data?.blocks ?? const []),
                      right: _ExplorerSideStack(
                        children: [
                          _ValidatorsPanel(
                            validators: data?.validators ?? const [],
                            bootstrapRegistry: data?.bootstrapRegistry,
                          ),
                          _LotteryPanel(status: data?.status),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _WPKNPanel(reserve: data?.reserve),
                    const SiteFooter(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ExplorerSnapshot {
  static const String _cacheBoxName = 'explorer_public_cache';
  static const String _snapshotCacheKey = 'snapshot';
  static const int _cacheSchemaVersion = 1;
  static const Duration _cacheTtl = Duration(minutes: 2);

  final Map<String, dynamic> status;
  final List<ExplorerBlock> blocks;
  final List<ExplorerTransaction> transactions;
  final List<ValidatorInfo> validators;
  final Map<String, dynamic>? bootstrapRegistry;
  final Map<String, dynamic>? reserve;
  final int totalSupply;
  final int circulatingSupply;
  final DateTime refreshedAt;

  const ExplorerSnapshot({
    required this.status,
    required this.blocks,
    required this.transactions,
    required this.validators,
    required this.bootstrapRegistry,
    required this.reserve,
    required this.totalSupply,
    required this.circulatingSupply,
    required this.refreshedAt,
  });

  static Future<ExplorerSnapshot> load() async {
    final responses = await Future.wait<Object?>([
      _getJson('${ProjectLinks.rpcBase}/chain/status'),
      _getJson('${ProjectLinks.rpcBase}/explorer/blocks?limit=12'),
      _getJson('${ProjectLinks.rpcBase}/chain/validators'),
      _getJson(
          '${ProjectLinks.rpcBase}/explorer/address/${ProjectLinks.nativeTreasury}'),
      _getJson(ProjectLinks.bootstrapPeers),
      _getJson(ProjectLinks.reserve),
      _getText('${ProjectLinks.rpcBase}/chain/supply/total.txt'),
      _getText('${ProjectLinks.rpcBase}/chain/supply/circulating.txt'),
    ]);

    final status =
        responses[0] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final blockPayload =
        responses[1] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final validatorPayload =
        responses[2] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final treasuryPayload =
        responses[3] as Map<String, dynamic>? ?? const <String, dynamic>{};

    final blocks = ((blockPayload['blocks'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ExplorerBlock.fromJson)
        .toList();
    final validators = _dedupeValidators(
      ((validatorPayload['validators'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ValidatorInfo.fromJson)
          .toList(),
    );
    final transactions =
        ((treasuryPayload['transactions'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ExplorerTransaction.fromJson)
            .toList();
    transactions.sort((a, b) {
      final blockCompare = b.blockNumber.compareTo(a.blockNumber);
      if (blockCompare != 0) {
        return blockCompare;
      }
      return b.transactionIndex.compareTo(a.transactionIndex);
    });

    final snapshot = ExplorerSnapshot(
      status: status,
      blocks: blocks,
      transactions: transactions,
      validators: validators,
      bootstrapRegistry: responses[4] as Map<String, dynamic>?,
      reserve: responses[5] as Map<String, dynamic>?,
      totalSupply: int.tryParse((responses[6] as String? ?? '').trim()) ?? 0,
      circulatingSupply:
          int.tryParse((responses[7] as String? ?? '').trim()) ?? 0,
      refreshedAt: DateTime.now(),
    );
    await snapshot.saveToCache();
    return snapshot;
  }

  static Future<ExplorerSnapshot?> cached() async {
    try {
      final box = await Hive.openBox<Map>(_cacheBoxName);
      final raw = box.get(_snapshotCacheKey);
      if (raw == null) {
        return null;
      }
      final data = Map<String, dynamic>.from(raw);
      final schema = (data['_schemaVersion'] as num?)?.toInt();
      final cachedAtMs = (data['_cachedAtMs'] as num?)?.toInt();
      if (schema != _cacheSchemaVersion || cachedAtMs == null) {
        return null;
      }
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(cachedAtMs),
      );
      if (age > _cacheTtl) {
        return null;
      }
      return ExplorerSnapshot.fromJson(
        Map<String, dynamic>.from(data['payload'] as Map? ?? const {}),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToCache() async {
    try {
      final box = await Hive.openBox<Map>(_cacheBoxName);
      await box.put(_snapshotCacheKey, {
        '_schemaVersion': _cacheSchemaVersion,
        '_cachedAtMs': DateTime.now().millisecondsSinceEpoch,
        'payload': toJson(),
      });
    } catch (_) {
      // Explorer cache is best-effort and should never block live data.
    }
  }

  factory ExplorerSnapshot.fromJson(Map<String, dynamic> json) {
    return ExplorerSnapshot(
      status: Map<String, dynamic>.from(json['status'] as Map? ?? const {}),
      blocks: (json['blocks'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => ExplorerBlock.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      transactions: (json['transactions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              ExplorerTransaction.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      validators: (json['validators'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => ValidatorInfo.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      bootstrapRegistry: Map<String, dynamic>.from(
          json['bootstrapRegistry'] as Map? ?? const {}),
      reserve: Map<String, dynamic>.from(json['reserve'] as Map? ?? const {}),
      totalSupply: (json['totalSupply'] as num?)?.toInt() ?? 0,
      circulatingSupply: (json['circulatingSupply'] as num?)?.toInt() ?? 0,
      refreshedAt: DateTime.tryParse('${json['refreshedAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'blocks': blocks.map((block) => block.toJson()).toList(),
      'transactions':
          transactions.map((transaction) => transaction.toJson()).toList(),
      'validators': validators.map((validator) => validator.toJson()).toList(),
      'bootstrapRegistry': bootstrapRegistry,
      'reserve': reserve,
      'totalSupply': totalSupply,
      'circulatingSupply': circulatingSupply,
      'refreshedAt': refreshedAt.toIso8601String(),
    };
  }

  static List<ValidatorInfo> _dedupeValidators(List<ValidatorInfo> validators) {
    final byIdentity = <String, ValidatorInfo>{};
    for (final validator in validators) {
      final key = validator.validator.trim().isNotEmpty
          ? validator.validator.trim()
          : validator.peerId.trim();
      if (key.isEmpty) {
        continue;
      }
      final current = byIdentity[key];
      if (current == null || validator.isBetterDisplayThan(current)) {
        byIdentity[key] = validator;
      }
    }
    final unique = byIdentity.values.toList()
      ..sort((a, b) => b.stake.compareTo(a.stake));
    return unique;
  }

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<String?> _getText(String url) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    return response.body;
  }
}

class _ExplorerTopBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onRefresh;

  const _ExplorerTopBar({required this.onRefresh});

  @override
  Size get preferredSize => const Size.fromHeight(78);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 860;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2050816),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(
                height: 68,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => context.go('/'),
                      borderRadius: BorderRadius.circular(20),
                      child: const _ExplorerBrand(),
                    ),
                    const Spacer(),
                    if (!compact) ...[
                      const _ExplorerNavPill(),
                      const SizedBox(width: 12),
                    ],
                    _ExplorerCta(
                      label: 'Buy PKN',
                      icon: Icons.add_card_outlined,
                      primary: false,
                      onPressed: () => context.go('/wallet'),
                    ),
                    const SizedBox(width: 10),
                    _ExplorerCta(
                      label: 'Refresh',
                      icon: Icons.refresh,
                      primary: true,
                      onPressed: onRefresh,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExplorerBrand extends StatelessWidget {
  const _ExplorerBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.network(
              ProjectLinks.logo,
              filterQuality: FilterQuality.none,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PokoinScan',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Live PKN explorer',
              style: TextStyle(
                color: Color(0xFF93A4C8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExplorerNavPill extends StatelessWidget {
  const _ExplorerNavPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ExplorerNavAction(
              label: 'Marketplace',
              path: '/marketplace',
              icon: Icons.storefront),
          _ExplorerNavAction(
              label: 'Wallet',
              path: '/wallet',
              icon: Icons.account_balance_wallet_outlined),
          _ExplorerNavAction(
              label: 'Health',
              path: '/health',
              icon: Icons.health_and_safety_outlined),
        ],
      ),
    );
  }
}

class _ExplorerNavAction extends StatelessWidget {
  final String label;
  final String path;
  final IconData icon;

  const _ExplorerNavAction({
    required this.label,
    required this.path,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.go(path),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFFFACC15)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ExplorerCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  const _ExplorerCta({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor:
            primary ? const Color(0xFFFACC15) : const Color(0xFF111936),
        foregroundColor:
            primary ? const Color(0xFF111827) : const Color(0xFFE2E8F0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: primary
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
      ),
    );
  }
}

class SearchResult {
  final String type;
  final Map<String, dynamic> result;

  const SearchResult({required this.type, required this.result});

  static Future<SearchResult?> search(String query) async {
    final uri = Uri.parse('${ProjectLinks.rpcBase}/explorer/search').replace(
      queryParameters: {'q': query},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Search failed: HTTP ${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return SearchResult(
      type: payload['type'] as String? ?? 'unknown',
      result: payload['result'] as Map<String, dynamic>? ?? const {},
    );
  }
}

class ExplorerBlock {
  final int number;
  final String hash;
  final String parentHash;
  final int slot;
  final int draw;
  final String miner;
  final int transactionCount;
  final bool finalized;

  const ExplorerBlock({
    required this.number,
    required this.hash,
    required this.parentHash,
    required this.slot,
    required this.draw,
    required this.miner,
    required this.transactionCount,
    required this.finalized,
  });

  factory ExplorerBlock.fromJson(Map<String, dynamic> json) {
    return ExplorerBlock(
      number: _asInt(json['number']),
      hash: json['hash'] as String? ?? '',
      parentHash: json['parentHash'] as String? ?? '',
      slot: _asInt(json['slot']),
      draw: _asInt(json['draw']),
      miner: json['miner'] as String? ?? '',
      transactionCount: _asInt(json['transactionCount']),
      finalized: json['finalized'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'hash': hash,
      'parentHash': parentHash,
      'slot': slot,
      'draw': draw,
      'miner': miner,
      'transactionCount': transactionCount,
      'finalized': finalized,
    };
  }
}

class ExplorerTransaction {
  final String hash;
  final String from;
  final String to;
  final int amount;
  final String kind;
  final int nonce;
  final int blockNumber;
  final int transactionIndex;
  final bool finalized;

  const ExplorerTransaction({
    required this.hash,
    required this.from,
    required this.to,
    required this.amount,
    required this.kind,
    required this.nonce,
    required this.blockNumber,
    required this.transactionIndex,
    required this.finalized,
  });

  factory ExplorerTransaction.fromJson(Map<String, dynamic> json) {
    return ExplorerTransaction(
      hash: json['hash'] as String? ?? '',
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      amount: _asInt(json['amount']),
      kind: json['kind'] as String? ?? 'transfer',
      nonce: _asInt(json['nonce']),
      blockNumber: _asInt(json['blockNumber']),
      transactionIndex: _asInt(json['transactionIndex']),
      finalized: json['finalized'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hash': hash,
      'from': from,
      'to': to,
      'amount': amount,
      'kind': kind,
      'nonce': nonce,
      'blockNumber': blockNumber,
      'transactionIndex': transactionIndex,
      'finalized': finalized,
    };
  }
}

class ValidatorInfo {
  final String peerId;
  final String validator;
  final int stake;
  final bool authorized;
  final bool local;
  final bool connected;

  const ValidatorInfo({
    required this.peerId,
    required this.validator,
    required this.stake,
    required this.authorized,
    required this.local,
    required this.connected,
  });

  factory ValidatorInfo.fromJson(Map<String, dynamic> json) {
    return ValidatorInfo(
      peerId: json['peerId'] as String? ?? '',
      validator: json['validator'] as String? ?? '',
      stake: _asInt(json['stake']),
      authorized: json['authorized'] == true,
      local: json['local'] == true,
      connected: json['connected'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peerId': peerId,
      'validator': validator,
      'stake': stake,
      'authorized': authorized,
      'local': local,
      'connected': connected,
    };
  }

  bool isBetterDisplayThan(ValidatorInfo other) {
    if (stake != other.stake) {
      return stake > other.stake;
    }
    if ((connected || local) != (other.connected || other.local)) {
      return connected || local;
    }
    if (authorized != other.authorized) {
      return authorized;
    }
    return peerId.length > other.peerId.length;
  }

  String get displayPeerId {
    final value = peerId.trim();
    final hash = value.startsWith('peer-') ? value.substring(5) : value;
    if (hash.isEmpty) {
      return 'peer';
    }
    final suffix = hash.length <= 5 ? hash : hash.substring(hash.length - 5);
    return 'peer-$suffix';
  }
}

class _HeroSearch extends StatelessWidget {
  final bool loading;
  final TextEditingController controller;
  final VoidCallback onSearch;

  const _HeroSearch({
    required this.loading,
    required this.controller,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        onSubmitted: (_) => onSearch(),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xEE050816),
          hintText: 'Search block number, tx hash, block hash, or 0x address',
          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
          prefixIcon: Icon(
            loading ? Icons.sync : Icons.search,
            color: const Color(0xFFFACC15),
          ),
          suffixIcon: Padding(
            padding: const EdgeInsets.all(6),
            child: FilledButton(
              onPressed: onSearch,
              child: const Text('Search'),
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final ExplorerSnapshot? snapshot;

  const _StatsGrid({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final status = snapshot?.status ?? const <String, dynamic>{};
    final validators = snapshot?.validators ?? const <ValidatorInfo>[];
    final registryNodes = _bootstrapNodes(snapshot?.bootstrapRegistry);
    final matureValidators =
        registryNodes.where((node) => _nodeStatus(node) == 'bootstrap').length;
    final authorizedValidators = validators.where((v) => v.authorized).length;
    final bootstrapValidators =
        matureValidators == 0 ? authorizedValidators : matureValidators;
    final reserve = snapshot?.reserve;
    final latestHeight = _asInt(status['height']);
    final reserveAmount =
        _formatWholeNumber(reserve?['reservedNativeAmount'] ?? 2000000);
    final totalSupply = snapshot?.totalSupply ?? 0;
    final circulatingSupply = snapshot?.circulatingSupply ?? 0;
    final cards = [
      _StatCard(
        label: 'Chain Height',
        value:
            latestHeight == 0 ? '...' : '#${_formatWholeNumber(latestHeight)}',
        icon: Icons.view_in_ar,
      ),
      _StatCard(
        label: 'PKN Transfers',
        value: _formatWholeNumber(status['txCount'] ?? 0),
        icon: Icons.swap_horiz,
      ),
      _StatCard(
        label: 'Total Supply',
        value:
            totalSupply == 0 ? '...' : '${_formatWholeNumber(totalSupply)} PKN',
        icon: Icons.toll_outlined,
      ),
      _StatCard(
        label: 'Circulating',
        value: circulatingSupply == 0
            ? '...'
            : '${_formatWholeNumber(circulatingSupply)} PKN',
        icon: Icons.public,
      ),
      _StatCard(
        label: 'Bootstrap Validators',
        value: '${_formatWholeNumber(bootstrapValidators)} active',
        icon: Icons.verified_user_outlined,
      ),
      _StatCard(
        label: 'BEP-20 wPKN backing',
        value: '$reserveAmount PKN',
        icon: Icons.account_balance,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 700
            ? 2
            : width < 980
                ? 3
                : 6;
        const gap = 14.0;
        final cardWidth = (width - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 172),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFACC15)),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8))),
          const SizedBox(height: 8),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: SelectableText(
              value.replaceAll(' PKN', '\u00A0PKN'),
              style: const TextStyle(
                color: Colors.white,
                decoration: TextDecoration.none,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlocksPanel extends StatelessWidget {
  final List<ExplorerBlock> blocks;

  const _BlocksPanel({required this.blocks});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'Latest Blocks',
            subtitle: 'Newest canonical PokoinPoS blocks',
            icon: Icons.layers_outlined,
          ),
          const SizedBox(height: 12),
          for (final block in blocks.take(8))
            _ListRow(
              leading: '#${block.number}',
              title: 'Slot ${block.slot} · ${block.transactionCount} tx',
              subtitle: 'Miner ${_short(block.miner, head: 18, tail: 10)}',
              trailing: block.finalized ? 'Finalized' : 'Tip',
              onTap: () => _open(
                  '${ProjectLinks.rpcBase}/explorer/blocks/${block.number}'),
            ),
          if (blocks.isEmpty) const _EmptyLine('No blocks loaded yet.'),
        ],
      ),
    );
  }
}

class _TransactionsPanel extends StatelessWidget {
  final List<ExplorerTransaction> transactions;

  const _TransactionsPanel({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'Latest PKN Transactions',
            subtitle: 'Recent native treasury/address activity',
            icon: Icons.receipt_long_outlined,
          ),
          const SizedBox(height: 12),
          if (transactions.isEmpty)
            const _EmptyLine('No recent treasury transactions loaded.')
          else
            _TransactionList(transactions: transactions.take(12).toList()),
        ],
      ),
    );
  }
}

class _ValidatorsPanel extends StatelessWidget {
  final List<ValidatorInfo> validators;
  final Map<String, dynamic>? bootstrapRegistry;

  const _ValidatorsPanel({
    required this.validators,
    required this.bootstrapRegistry,
  });

  @override
  Widget build(BuildContext context) {
    final registryNodes = _bootstrapNodes(bootstrapRegistry);
    final bootstrapNodes =
        registryNodes.where((node) => _nodeStatus(node) == 'bootstrap').length;
    final vettingNodes =
        registryNodes.where((node) => _nodeStatus(node) == 'vetting').length;
    final authorizedValidators = validators.where((v) => v.authorized).length;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            title: 'Authorized peer identities',
            subtitle: registryNodes.isEmpty
                ? 'Public P2P identities reported by the node'
                : '$bootstrapNodes bootstrap validators · $vettingNodes vetting nodes · $authorizedValidators authorized identities',
            icon: Icons.security_outlined,
          ),
          const SizedBox(height: 12),
          for (final validator in validators)
            _ListRow(
              leading: validator.displayPeerId,
              title: '${validator.stake} PKN stake',
              subtitle: _short(validator.validator, head: 22, tail: 14),
              trailing: validator.connected || validator.local
                  ? 'Connected'
                  : 'Offline',
              trailingColor: validator.connected || validator.local
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
            ),
          if (validators.isEmpty) const _EmptyLine('No validator data loaded.'),
        ],
      ),
    );
  }
}

class _LotteryPanel extends StatelessWidget {
  final Map<String, dynamic>? status;

  const _LotteryPanel({required this.status});

  @override
  Widget build(BuildContext context) {
    final data = status ?? const <String, dynamic>{};
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'Consensus Lottery',
            subtitle: 'Live local validator participation counters',
            icon: Icons.casino_outlined,
          ),
          const SizedBox(height: 12),
          _ProgressLine(
              label: 'Attempts', value: _display(data['lotteryAttempts'])),
          _ProgressLine(label: 'Wins', value: _display(data['lotteryWins'])),
          _ProgressLine(
              label: 'Misses', value: _display(data['lotteryMisses'])),
          _ProgressLine(
              label: 'No ticket', value: _display(data['lotteryNoTicket'])),
          const SizedBox(height: 12),
          const Text(
            'Only validators with a positive PKN balance receive mining weight. Zero-balance validators stay connected but receive no lottery tickets.',
            style: TextStyle(color: Color(0xFFCBD5E1), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _WPKNPanel extends StatelessWidget {
  final Map<String, dynamic>? reserve;

  const _WPKNPanel({required this.reserve});

  @override
  Widget build(BuildContext context) {
    final wrapped = reserve?['wrappedToken'] as Map<String, dynamic>?;
    final pancake = reserve?['pancakeSwap'] as Map<String, dynamic>?;
    final nativeTreasury = reserve?['nativeTreasury'] as Map<String, dynamic>?;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'wPKN and Native Swap View',
            subtitle:
                'BNB Chain wPKN reserve proof plus native PokoinSwap accounting',
            icon: Icons.hub_outlined,
          ),
          const SizedBox(height: 10),
          const Text(
            'Native PokoinSwap WPKN is an internal PokoinPoS accounting balance. It tracks a claim inside the PokoinPoS ledger, but it is not automatically the BEP-20 wPKN token in MetaMask on BNB Chain until a bridge/withdrawal settlement moves value across chains.',
            style: TextStyle(color: Color(0xFFCBD5E1), height: 1.45),
          ),
          const SizedBox(height: 10),
          const Text(
            'BTC, ETH, and BNB are also supported as native PokoinSwap accounting assets. External deposits/withdrawals still need an operator or bridge service for settlement, then those claims trade against PKN on PokoinSwap.',
            style: TextStyle(color: Color(0xFF93A4C8), height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _InfoBox(
                  label: 'Contract',
                  value:
                      wrapped?['contractAddress'] ?? ProjectLinks.wpknContract),
              _InfoBox(
                  label: 'Supply',
                  value: '${wrapped?['totalSupply'] ?? '2000000'} wPKN'),
              _InfoBox(
                  label: 'Native reserve',
                  value:
                      '${nativeTreasury?['reservedAmount'] ?? '2000000'} PKN'),
              _InfoBox(
                  label: 'Pancake pair',
                  value: pancake?['poolAddress'] ??
                      ProjectLinks.pancakePairAddress),
            ],
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoBox(label: 'Native swap asset', value: 'WPKN accounting'),
              _InfoBox(label: 'External token', value: 'BEP-20 wPKN on BNB'),
              _InfoBox(label: 'Active assets', value: 'BTC / ETH / BNB claims'),
            ],
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LinkButton(label: 'BscScan token', url: ProjectLinks.bscToken),
              _LinkButton(label: 'PancakeSwap', url: ProjectLinks.pancakeSwap),
              _LinkButton(label: 'Reserve manifest', url: ProjectLinks.reserve),
              _LinkButton(
                  label: 'Native treasury',
                  url:
                      '${ProjectLinks.rpcBase}/explorer/address/${ProjectLinks.nativeTreasury}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  final bool loading;
  final SearchResult? result;
  final Object? error;

  const _SearchPanel(
      {required this.loading, required this.result, required this.error});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _Panel(child: LinearProgressIndicator());
    }
    if (error != null) {
      return _Notice(title: 'Search failed', body: error.toString());
    }
    if (result == null) {
      return const _Notice(
          title: 'No result', body: 'Nothing matched that query.');
    }
    final transactions = ((result!.result['transactions'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ExplorerTransaction.fromJson)
        .toList();
    final rows = result!.result.entries
        .where((e) => e.key != 'transactions')
        .take(10)
        .map((e) => _InfoBox(label: e.key, value: e.value.toString()))
        .toList();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PanelHeader(
            title: 'Search result: ${result!.type}',
            subtitle: 'Canonical explorer API response',
            icon: Icons.manage_search,
          ),
          const SizedBox(height: 14),
          if (transactions.isNotEmpty) ...[
            _TransactionList(transactions: transactions),
            if (rows.isNotEmpty) const SizedBox(height: 14),
          ],
          if (rows.isNotEmpty)
            Wrap(spacing: 12, runSpacing: 12, children: rows),
        ],
      ),
    );
  }
}

class _ResponsiveColumns extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _ResponsiveColumns({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    if (!wide) {
      return Column(children: [left, const SizedBox(height: 18), right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 18),
        Expanded(child: right),
      ],
    );
  }
}

class _ExplorerSideStack extends StatelessWidget {
  final List<Widget> children;

  const _ExplorerSideStack({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 18),
          children[i],
        ],
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PanelHeader(
      {required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFFACC15)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Color(0xFF94A3B8))),
            ],
          ),
        ),
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  final String leading;
  final String title;
  final String subtitle;
  final String trailing;
  final Color trailingColor;
  final VoidCallback? onTap;

  const _ListRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.trailingColor = const Color(0xFF22C55E),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 78,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                leading,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFFFACC15), fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  SelectableText(
                    subtitle,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(trailing,
                style: TextStyle(color: trailingColor, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String label;
  final String value;

  const _InfoBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final address = _addressValue(value);
    final box = Container(
      width: 270,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              decoration: address == null ? null : TextDecoration.underline,
              decorationColor: const Color(0xFFFACC15),
            ),
          ),
        ],
      ),
    );
    if (address == null) {
      return box;
    }
    return InkWell(
      onTap: () => _open('${ProjectLinks.rpcBase}/explorer/address/$address'),
      borderRadius: BorderRadius.circular(16),
      child: box,
    );
  }
}

class _TransactionList extends StatelessWidget {
  final List<ExplorerTransaction> transactions;

  const _TransactionList({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF121A2D),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              if (!compact) const _TransactionHeader(),
              for (var i = 0; i < transactions.length; i++)
                _TransactionRow(
                  transaction: transactions[i],
                  compact: compact,
                  showDivider: i > 0 || !compact,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TransactionHeader extends StatelessWidget {
  const _TransactionHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1A2438),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 5, child: _HeaderLabel('Transaction')),
          Expanded(flex: 1, child: _HeaderLabel('Action', alignCenter: true)),
          Expanded(child: _HeaderLabel('Block')),
          Expanded(flex: 2, child: _HeaderLabel('From')),
          Expanded(flex: 2, child: _HeaderLabel('To')),
          Expanded(flex: 2, child: _HeaderLabel('Amount', alignEnd: true)),
          Expanded(child: _HeaderLabel('Status', alignEnd: true)),
        ],
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String text;
  final bool alignEnd;
  final bool alignCenter;

  const _HeaderLabel(this.text,
      {this.alignEnd = false, this.alignCenter = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: alignCenter
          ? TextAlign.center
          : (alignEnd ? TextAlign.end : TextAlign.start),
      style: const TextStyle(
        color: Color(0xFFE2E8F0),
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final ExplorerTransaction transaction;
  final bool compact;
  final bool showDivider;

  const _TransactionRow({
    required this.transaction,
    required this.compact,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    const rowTextStyle = TextStyle(
      color: Color(0xFFE2E8F0),
      fontWeight: FontWeight.w700,
    );
    final tx = transaction;
    final hashLink = _ExplorerCellLink(
      label: compact ? _short(tx.hash, head: 12, tail: 6) : tx.hash,
      url: '${ProjectLinks.rpcBase}/explorer/tx/${tx.hash}',
    );
    final fromLink = _ExplorerCellLink(
      label: compact ? _short(tx.from, head: 10, tail: 6) : tx.from,
      url: '${ProjectLinks.rpcBase}/explorer/address/${tx.from}',
    );
    final toLink = _ExplorerCellLink(
      label: compact ? _short(tx.to, head: 10, tail: 6) : tx.to,
      url: '${ProjectLinks.rpcBase}/explorer/address/${tx.to}',
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08)))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: hashLink),
                      const SizedBox(width: 10),
                      _ActionPill(label: tx.kind),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _TxMeta(
                        label: 'Block',
                        child: Text(
                          '${tx.blockNumber}',
                          style: rowTextStyle,
                        ),
                      ),
                      _TxMeta(label: 'From', child: fromLink),
                      _TxMeta(label: 'To', child: toLink),
                      _TxMeta(
                          label: 'Amount',
                          child: Text(
                            '${_formatAmount(tx.amount)} PKN',
                            style: rowTextStyle,
                          )),
                      _TxMeta(
                          label: 'Status',
                          child: Text(
                            tx.finalized ? 'Final' : 'Pending',
                            style: rowTextStyle,
                          )),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 5, child: hashLink),
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.center,
                      child: _ActionPill(label: tx.kind),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${tx.blockNumber}',
                      style: rowTextStyle,
                    ),
                  ),
                  Expanded(flex: 2, child: fromLink),
                  Expanded(flex: 2, child: toLink),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${_formatAmount(tx.amount)} PKN',
                      textAlign: TextAlign.end,
                      style: rowTextStyle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tx.finalized ? 'Final' : 'Pending',
                      textAlign: TextAlign.end,
                      style: rowTextStyle,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TxMeta extends StatelessWidget {
  final String label;
  final Widget child;

  const _TxMeta({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 12),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ExplorerCellLink extends StatelessWidget {
  final String label;
  final String url;

  const _ExplorerCellLink({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(url),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: const TextStyle(
          color: Color(0xFF38BDF8),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String label;

  const _ActionPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final text = label.trim().isEmpty ? 'Transfer' : label.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF25324A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Text(
        text[0].toUpperCase() + text.substring(1),
        style: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final String label;
  final String value;

  const _ProgressLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Color(0xFFCBD5E1)))),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final String url;

  const _LinkButton({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _open(url),
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text(label),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: Color(0xFF94A3B8)));
  }
}

class _Notice extends StatelessWidget {
  final String title;
  final String body;

  const _Notice({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x33F97316),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x99F97316)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: Color(0xFFFFEDD5))),
        ],
      ),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _display(Object? value) {
  if (value == null) return '...';
  return value.toString();
}

String _formatWholeNumber(Object? value) {
  final number = _asInt(value);
  if (number == 0 && value == null) return '...';
  return _formatAmount(number);
}

List<Map<String, dynamic>> _bootstrapNodes(Map<String, dynamic>? registry) {
  final candidates = registry?['candidates'];
  if (candidates is List && candidates.isNotEmpty) {
    return candidates.whereType<Map<String, dynamic>>().toList(growable: false);
  }
  final peers = registry?['peers'];
  if (peers is List) {
    return peers.whereType<Map<String, dynamic>>().toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

String _nodeStatus(Map<String, dynamic> node) {
  final status = node['status'];
  return status is String ? status.toLowerCase() : 'peer';
}

String _short(String value, {int head = 10, int tail = 8}) {
  if (value.length <= head + tail + 3) return value;
  return '${value.substring(0, head)}...${value.substring(value.length - tail)}';
}

String _formatAmount(int amount) {
  final text = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final remaining = text.length - i;
    buffer.write(text[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

String? _addressValue(String value) {
  final trimmed = value.trim();
  return RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(trimmed)
      ? trimmed.toLowerCase()
      : null;
}

Future<void> _open(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
