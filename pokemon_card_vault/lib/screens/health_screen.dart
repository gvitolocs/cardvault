import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/project_links.dart';

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
      _checkJson('wPKN reserve manifest', ProjectLinks.reserve,
          (data) => data['status'] == 'live'),
      _checkHead('wPKN logo asset', ProjectLinks.logo),
    ]);
    Map<String, dynamic>? chainStatus;
    for (final check in checks) {
      if (check.label == 'Chain status') {
        chainStatus = check.data;
        break;
      }
    }
    return HealthReport(checks: checks, chainStatus: chainStatus);
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
      appBar: AppBar(
        backgroundColor: const Color(0xE60A1026),
        title: const Text('CardVault Network Health'),
        leading: IconButton(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _checks = _runChecks()),
            child: const Text('Refresh'),
          ),
        ],
      ),
      body: FutureBuilder<HealthReport>(
        future: _checks,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final report = snapshot.data;
          final checks = report?.checks ?? const <HealthCheck>[];
          final allOk = checks.isNotEmpty && checks.every((check) => check.ok);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusHero(loading: loading, allOk: allOk),
                    const SizedBox(height: 22),
                    if (loading)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator()))
                    else ...[
                      _PeerPieCard(status: report?.chainStatus),
                      const SizedBox(height: 14),
                      for (final check in checks) _HealthTile(check: check),
                    ],
                    const SizedBox(height: 22),
                    const _ReferencePanel(),
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

class HealthReport {
  final List<HealthCheck> checks;
  final Map<String, dynamic>? chainStatus;

  const HealthReport({required this.checks, required this.chainStatus});
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

class _StatusHero extends StatelessWidget {
  final bool loading;
  final bool allOk;

  const _StatusHero({required this.loading, required this.allOk});

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
            ? 'All public systems responding'
            : 'Some checks need attention';

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.health_and_safety, color: color, size: 44),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Live checks for PokoinPoS RPC, explorer assets, wPKN reserve proof, and BNB Chain token pages.',
                  style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerPieCard extends StatelessWidget {
  final Map<String, dynamic>? status;

  const _PeerPieCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final peerCount = _intValue('peerCount');
    final remotePeers = math.max(peerCount, 0);
    final localNodes = 1;
    final totalNodes = remotePeers + localNodes;
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
                  remotePeers: remotePeers, localNodes: localNodes),
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
                    const Text('visible nodes',
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
                'Live peer view from the public PokoinPoS status endpoint.',
                style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
              ),
              const SizedBox(height: 18),
              _LegendRow(
                  color: const Color(0xFF38BDF8),
                  label: 'Remote peers',
                  value: '$remotePeers connected'),
              const SizedBox(height: 10),
              const _LegendRow(
                  color: Color(0xFFFDE68A),
                  label: 'Public RPC node',
                  value: '1 serving health checks'),
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
  final int remotePeers;
  final int localNodes;

  const _PeerPiePainter({required this.remotePeers, required this.localNodes});

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

    final total = math.max(remotePeers + localNodes, 1);
    var start = -math.pi / 2;
    for (final segment in [
      _PieSegment(remotePeers.toDouble(), const Color(0xFF38BDF8)),
      _PieSegment(localNodes.toDouble(), const Color(0xFFFDE68A)),
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
    return oldDelegate.remotePeers != remotePeers ||
        oldDelegate.localNodes != localNodes;
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
    return Card(
      color: const Color(0xB30B1024),
      child: ListTile(
        leading: Icon(check.ok ? Icons.check_circle : Icons.warning_amber,
            color: check.ok ? Colors.greenAccent : Colors.orangeAccent),
        title: Text(check.label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(
          check.error ??
              'HTTP ${check.status} · ${check.latencyMs} ms${check.detail == null || check.detail!.isEmpty ? '' : ' · ${check.detail}'}\\n${check.url}',
          style: const TextStyle(color: Color(0xFFB8C4E6)),
        ),
        isThreeLine: true,
        trailing: IconButton(
          onPressed: () => launchUrl(Uri.parse(check.url),
              mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new, color: Colors.white70),
        ),
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
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Public references',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          SizedBox(height: 14),
          SelectableText('wPKN: ${ProjectLinks.wpknContract}',
              style:
                  TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'monospace')),
          SizedBox(height: 8),
          SelectableText('Pair: ${ProjectLinks.pancakePairAddress}',
              style:
                  TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'monospace')),
          SizedBox(height: 8),
          SelectableText('Treasury: ${ProjectLinks.nativeTreasury}',
              style:
                  TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'monospace')),
          SizedBox(height: 8),
          Text(
              'External references: BscScan token page and PancakeSwap pool are linked from the Scan page; they are not probed here because browser CORS can make healthy third-party pages look like warnings.',
              style: TextStyle(color: Color(0xFF93A4C8), height: 1.4)),
        ],
      ),
    );
  }
}
