import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/project_links.dart';
import '../widgets/site_footer.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  late Future<HealthReport> _checks;

  @override
  void initState() {
    super.initState();
    _checks = _runChecks();
  }

  Future<HealthReport> _runChecks() async {
    final checks = await Future.wait([
      _checkJson('Pokoin RPC health', ProjectLinks.health,
          (data) => data['status'] == 'ok'),
      _checkRpc('Pokoin EVM RPC chain ID', 'eth_chainId', const <Object>[]),
      _checkRpc(
          'Pokoin EVM RPC latest block', 'eth_blockNumber', const <Object>[]),
      _checkJson(
        'Chain status',
        ProjectLinks.chainStatus,
        (data) =>
            data['status'] == 'ok' ||
            data.containsKey('height') ||
            data.containsKey('chainHeight'),
      ),
      _checkJson(
        'Bootstrap registry',
        ProjectLinks.bootstrapPeers,
        (data) => data.containsKey('candidates') || data.containsKey('peers'),
      ),
      _checkJson('wPKN reserve manifest', ProjectLinks.reserve,
          (data) => data['status'] == 'live'),
      _checkHead('wPKN logo asset', ProjectLinks.logo),
    ]);
    Map<String, dynamic>? chainStatus;
    Map<String, dynamic>? bootstrapRegistry;
    for (final check in checks) {
      if (check.label == 'Chain status') {
        chainStatus = check.data;
      }
      if (check.label == 'Bootstrap registry') {
        bootstrapRegistry = check.data;
      }
    }
    return HealthReport(
      checks: checks,
      chainStatus: chainStatus,
      bootstrapRegistry: bootstrapRegistry,
    );
  }

  Future<HealthCheck> _checkRpc(
    String label,
    String method,
    List<Object> params,
  ) async {
    final started = DateTime.now();
    try {
      final response = await http
          .post(
            Uri.parse(ProjectLinks.rpc),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(<String, Object>{
              'jsonrpc': '2.0',
              'id': DateTime.now().microsecondsSinceEpoch,
              'method': method,
              'params': params,
            }),
          )
          .timeout(const Duration(seconds: 8));
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['result'] != null;
      return HealthCheck(
        label: label,
        url: ProjectLinks.rpc,
        ok: ok,
        status: response.statusCode,
        latencyMs: elapsed,
        detail: data['result']?.toString(),
      );
    } catch (error) {
      return HealthCheck(
          label: label,
          url: ProjectLinks.rpc,
          ok: false,
          error: error.toString());
    }
  }

  Future<HealthCheck> _checkJson(
    String label,
    String url,
    bool Function(Map<String, dynamic>) validate,
  ) async {
    final started = DateTime.now();
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = response.statusCode >= 200 &&
          response.statusCode < 300 &&
          validate(data);
      return HealthCheck(
        label: label,
        url: url,
        ok: ok,
        status: response.statusCode,
        latencyMs: elapsed,
        detail: _summarizeJson(data),
        data: data,
      );
    } catch (error) {
      return HealthCheck(
          label: label, url: url, ok: false, error: error.toString());
    }
  }

  Future<HealthCheck> _checkHead(String label, String url) async {
    final started = DateTime.now();
    try {
      final response =
          await http.head(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final ok = response.statusCode >= 200 && response.statusCode < 400;
      return HealthCheck(
          label: label,
          url: url,
          ok: ok,
          status: response.statusCode,
          latencyMs: elapsed);
    } catch (error) {
      return HealthCheck(
          label: label, url: url, ok: false, error: error.toString());
    }
  }

  String _summarizeJson(Map<String, dynamic> data) {
    final interesting = <String>[
      'status',
      'height',
      'chainHeight',
      'committedHeight',
      'mempoolDepth',
      'peerCount',
      'currencySymbol',
      'asset',
    ];
    final parts = <String>[];
    for (final key in interesting) {
      if (data.containsKey(key)) {
        parts.add('$key: ${data[key]}');
      }
    }
    return parts.take(4).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: _HealthTopBar(
        onRefresh: () => setState(() => _checks = _runChecks()),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.25,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: FutureBuilder<HealthReport>(
          future: _checks,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final report = snapshot.data;
            final checks = report?.checks ?? const <HealthCheck>[];
            final healthyCount = checks.where((check) => check.ok).length;
            final allOk = checks.isNotEmpty && healthyCount == checks.length;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatusHero(
                        loading: loading,
                        allOk: allOk,
                        healthyCount: healthyCount,
                        totalCount: checks.length,
                      ),
                      const SizedBox(height: 18),
                      _HealthSignalStrip(checks: checks, loading: loading),
                      const SizedBox(height: 22),
                      if (loading)
                        const _LoadingPanel()
                      else ...[
                        _PeerPieCard(
                          status: report?.chainStatus,
                          bootstrap: report?.bootstrapRegistry,
                        ),
                        const SizedBox(height: 14),
                        for (final check in checks) _HealthTile(check: check),
                      ],
                      const SizedBox(height: 22),
                      const _ReferencePanel(),
                      const SiteFooter(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class HealthReport {
  final List<HealthCheck> checks;
  final Map<String, dynamic>? chainStatus;
  final Map<String, dynamic>? bootstrapRegistry;

  const HealthReport({
    required this.checks,
    required this.chainStatus,
    required this.bootstrapRegistry,
  });
}

class HealthCheck {
  final String label;
  final String url;
  final bool ok;
  final int? status;
  final int? latencyMs;
  final String? error;
  final String? detail;
  final Map<String, dynamic>? data;

  const HealthCheck({
    required this.label,
    required this.url,
    required this.ok,
    this.status,
    this.latencyMs,
    this.error,
    this.detail,
    this.data,
  });
}

class _HealthTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _HealthTopBar({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 820;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF2050816),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(
                height: 68,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => context.go('/scan'),
                      borderRadius: BorderRadius.circular(20),
                      child: const _HealthBrand(),
                    ),
                    const Spacer(),
                    if (!compact) ...[
                      const _HealthNavPill(),
                      const SizedBox(width: 12),
                    ],
                    _HealthCta(
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

class _HealthBrand extends StatelessWidget {
  const _HealthBrand();

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
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PokoinHealth',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Live public systems',
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

class _HealthNavPill extends StatelessWidget {
  const _HealthNavPill();

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
          _HealthNavAction(label: 'Home', path: '/', icon: Icons.home_outlined),
          _HealthNavAction(label: 'Scan', path: '/scan', icon: Icons.query_stats),
          _HealthNavAction(label: 'Wallet', path: '/wallet', icon: Icons.account_balance_wallet_outlined),
        ],
      ),
    );
  }
}

class _HealthNavAction extends StatelessWidget {
  const _HealthNavAction({
    required this.label,
    required this.path,
    required this.icon,
  });

  final String label;
  final String path;
  final IconData icon;

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

class _HealthCta extends StatelessWidget {
  const _HealthCta({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: primary ? const Color(0xFFFACC15) : const Color(0xFF111936),
        foregroundColor: primary ? const Color(0xFF111827) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  final bool loading;
  final bool allOk;
  final int healthyCount;
  final int totalCount;

  const _StatusHero({
    required this.loading,
    required this.allOk,
    required this.healthyCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final color = loading
        ? const Color(0xFF38BDF8)
        : allOk
            ? const Color(0xFF22C55E)
            : const Color(0xFFF97316);
    final label = loading
        ? 'Checking live systems'
        : allOk
            ? 'All Pokoin public systems responding'
            : 'Some public checks need attention';
    final statusText = loading
        ? 'Running RPC, reserve and metadata checks'
        : '$healthyCount of $totalCount checks healthy';

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111B3F), Color(0xFF0B1020)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0x33FACC15)),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 34, offset: Offset(0, 18)),
        ],
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 22,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.42)),
                  ),
                  child: Icon(Icons.health_and_safety, color: color, size: 34),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Infrastructure status',
                        style: TextStyle(
                          color: Color(0xFFFDE68A),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Live monitoring for PokoinPoS RPC, explorer assets, reserve proof, token metadata and BNB Chain references.',
                        style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 220,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0x99050816),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loading ? 'Status' : (allOk ? 'Operational' : 'Attention'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Refresh on demand',
                  style: TextStyle(color: Color(0xFF93A4C8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthSignalStrip extends StatelessWidget {
  const _HealthSignalStrip({required this.checks, required this.loading});

  final List<HealthCheck> checks;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final okCount = checks.where((check) => check.ok).length;
    final avgLatency = checks
        .where((check) => check.latencyMs != null)
        .map((check) => check.latencyMs!)
        .toList();
    final latency = avgLatency.isEmpty
        ? '-'
        : '${(avgLatency.reduce((a, b) => a + b) / avgLatency.length).round()} ms';

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _HealthSignalCard(
          icon: Icons.verified_outlined,
          label: 'Healthy checks',
          value: loading ? '...' : '$okCount / ${checks.length}',
        ),
        _HealthSignalCard(
          icon: Icons.speed_outlined,
          label: 'Average latency',
          value: loading ? '...' : latency,
        ),
        const _HealthSignalCard(
          icon: Icons.public,
          label: 'Gateway',
          value: 'rpc.pokoin.com',
        ),
        const _HealthSignalCard(
          icon: Icons.account_balance,
          label: 'Reserve asset',
          value: 'wPKN live',
        ),
      ],
    );
  }
}

class _HealthSignalCard extends StatelessWidget {
  const _HealthSignalCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xB30B1024),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFACC15), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
                const SizedBox(height: 6),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
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

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(color: Color(0xFFFACC15)),
          SizedBox(height: 16),
          Text(
            'Running live health checks...',
            style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PeerPieCard extends StatelessWidget {
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? bootstrap;

  const _PeerPieCard({required this.status, required this.bootstrap});

  @override
  Widget build(BuildContext context) {
    final peerCount = _intValue('peerCount');
    final remotePeers = math.max(peerCount, 0);
    final candidates = _listValue(bootstrap?['candidates']);
    final manifestPeers = _listValue(bootstrap?['peers']);
    final registryNodes = candidates.isNotEmpty ? candidates : manifestPeers;
    final vettingNodes = registryNodes.where((node) => _statusOf(node) == 'vetting').length;
    final bootstrapNodes = registryNodes.where((node) => _statusOf(node) == 'bootstrap').length;
    final peerNodes = registryNodes
        .where((node) => _statusOf(node) == 'peer' || _statusOf(node) == 'candidate')
        .length;
    final totalNodes = math.max(registryNodes.length, remotePeers);
    final height = _intValue('height');
    final committedHeight = _intValue('committedHeight');
    final mempoolDepth = _intValue('mempoolDepth');
    final finalityDepth = _intValue('finalityDepth');
    final uptimeSeconds = _intValue('uptimeSeconds');

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC111936),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final chart = SizedBox(
            width: compact ? 190 : 220,
            height: compact ? 190 : 220,
            child: CustomPaint(
              painter: _PeerPiePainter(
                vettingNodes: vettingNodes,
                peerNodes: peerNodes,
                bootstrapNodes: bootstrapNodes,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$totalNodes',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    const Text('network nodes',
                        style: TextStyle(
                            color: Color(0xFF93A4C8),
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Peer topology',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text(
                'Network registry view: vetting nodes, regular peers and bootstrap peers. The RPC peer count is the live P2P connections seen by the gateway.',
                style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
              ),
              const SizedBox(height: 18),
              _LegendRow(
                  color: const Color(0xFFFDE68A),
                  label: 'Vetting nodes',
                  value: '$vettingNodes online candidates'),
              const SizedBox(height: 10),
              _LegendRow(
                  color: const Color(0xFF38BDF8),
                  label: 'Regular peers',
                  value: '$peerNodes peer nodes'),
              const SizedBox(height: 10),
              _LegendRow(
                  color: const Color(0xFF22C55E),
                  label: 'Bootstrap peers',
                  value: '$bootstrapNodes mature nodes'),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _PeerMetric(
                      label: 'Tip height', value: height < 0 ? '-' : '$height'),
                  _PeerMetric(
                      label: 'Committed',
                      value: committedHeight < 0 ? '-' : '$committedHeight'),
                  _PeerMetric(
                      label: 'Finality depth',
                      value: finalityDepth < 0 ? '-' : '$finalityDepth'),
                  _PeerMetric(
                      label: 'Mempool',
                      value: mempoolDepth < 0 ? '-' : '$mempoolDepth'),
                  _PeerMetric(
                      label: 'Uptime',
                      value: uptimeSeconds < 0
                          ? '-'
                          : _formatDuration(uptimeSeconds)),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: chart),
                const SizedBox(height: 20),
                details,
              ],
            );
          }

          return Row(
            children: [
              chart,
              const SizedBox(width: 26),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }

  int _intValue(String key) {
    final value = status?[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? -1;
    }
    return -1;
  }

  List<Map<String, dynamic>> _listValue(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  String _statusOf(Map<String, dynamic> node) {
    final value = node['status'];
    return value is String ? value.toLowerCase() : 'peer';
  }

  static String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    if (days > 0) {
      return '${days}d ${hours}h';
    }
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${math.max(minutes, 1)}m';
  }
}

class _PeerPiePainter extends CustomPainter {
  final int vettingNodes;
  final int peerNodes;
  final int bootstrapNodes;

  const _PeerPiePainter({
    required this.vettingNodes,
    required this.peerNodes,
    required this.bootstrapNodes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.2;
    final chartRect =
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);
    final backgroundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1E293B);

    canvas.drawCircle(center, radius - strokeWidth / 2, backgroundPaint);

    final total = math.max(vettingNodes + peerNodes + bootstrapNodes, 1);
    var start = -math.pi / 2;
    for (final segment in [
      _PieSegment(vettingNodes.toDouble(), const Color(0xFFFDE68A)),
      _PieSegment(peerNodes.toDouble(), const Color(0xFF38BDF8)),
      _PieSegment(bootstrapNodes.toDouble(), const Color(0xFF22C55E)),
    ]) {
      if (segment.value <= 0) {
        continue;
      }
      final sweep = (segment.value / total) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = segment.color;
      canvas.drawArc(chartRect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PeerPiePainter oldDelegate) {
    return oldDelegate.vettingNodes != vettingNodes ||
        oldDelegate.peerNodes != peerNodes ||
        oldDelegate.bootstrapNodes != bootstrapNodes;
  }
}

class _PieSegment {
  final double value;
  final Color color;

  const _PieSegment(this.value, this.color);
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendRow(
      {required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700))),
        Text(value, style: const TextStyle(color: Color(0xFFB8C4E6))),
      ],
    );
  }
}

class _PeerMetric extends StatelessWidget {
  final String label;
  final String value;

  const _PeerMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x99050816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF93A4C8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _HealthTile extends StatelessWidget {
  final HealthCheck check;

  const _HealthTile({required this.check});

  @override
  Widget build(BuildContext context) {
    final color = check.ok ? const Color(0xFF22C55E) : const Color(0xFFF97316);
    final detail = check.error ??
        'HTTP ${check.status} · ${check.latencyMs} ms${check.detail == null || check.detail!.isEmpty ? '' : ' · ${check.detail}'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xB30B1024),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              check.ok ? Icons.check_circle : Icons.warning_amber,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.35),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  check.url,
                  style: const TextStyle(
                    color: Color(0xFF93A4C8),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => launchUrl(
              Uri.parse(check.url),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, color: Color(0xFFCBD5E1)),
            tooltip: 'Open endpoint',
          ),
        ],
      ),
    );
  }
}

class _ReferencePanel extends StatelessWidget {
  const _ReferencePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC111936),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, color: Color(0xFFFACC15)),
              SizedBox(width: 10),
              Text(
                'Public references',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          SelectableText(
            'wPKN: ${ProjectLinks.wpknContract}',
            style: TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'monospace'),
          ),
          SizedBox(height: 8),
          SelectableText(
            'Pair: ${ProjectLinks.pancakePairAddress}',
            style: TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'monospace'),
          ),
          SizedBox(height: 8),
          SelectableText(
            'Treasury: ${ProjectLinks.nativeTreasury}',
            style: TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'monospace'),
          ),
          SizedBox(height: 12),
          Text(
            'External references stay linked from PokoinScan; third-party pages are not probed here because browser CORS can report healthy pages as warnings.',
            style: TextStyle(color: Color(0xFF93A4C8), height: 1.4),
          ),
        ],
      ),
    );
  }
}

