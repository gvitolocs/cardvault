import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late Future<ScanSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = _loadSnapshot();
  }

  Future<ScanSnapshot> _loadSnapshot() async {
    final results = await Future.wait<Object?>([
      _rpc('eth_chainId', const <Object>[]),
      _rpc('eth_blockNumber', const <Object>[]),
      _rpc('eth_gasPrice', const <Object>[]),
      _rpc('eth_getBalance', <Object>[ProjectLinks.nativeTreasury, 'latest']),
      _getJson(ProjectLinks.chainStatus),
    ]);

    return ScanSnapshot(
      chainId: _hexToBigInt(results[0] as String).toString(),
      latestBlock: _hexToBigInt(results[1] as String).toString(),
      gasPriceWei: _hexToBigInt(results[2] as String).toString(),
      treasuryBalance: _formatWei(_hexToBigInt(results[3] as String)),
      chainStatus: results[4] as Map<String, dynamic>?,
      refreshedAt: DateTime.now(),
    );
  }

  Future<Object?> _rpc(String method, List<Object> params) async {
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

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || payload['error'] != null) {
      throw Exception(payload['error'] ?? 'RPC HTTP ${response.statusCode}');
    }
    return payload['result'];
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xE60A1026),
        leading: IconButton(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Pokoin Scan'),
        actions: [
          TextButton(
            onPressed: () => context.go('/wallet'),
            child: const Text('Wallet'),
          ),
          TextButton(
            onPressed: () => context.go('/health'),
            child: const Text('Health'),
          ),
          TextButton(
            onPressed: () => _open(ProjectLinks.explorer),
            child: const Text('Explorer'),
          ),
        ],
      ),
      body: FutureBuilder<ScanSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _snapshot = _loadSnapshot()),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Hero(
                          snapshot: data,
                          loading:
                              snapshot.connectionState != ConnectionState.done),
                      const SizedBox(height: 22),
                      if (snapshot.hasError)
                        _Notice(
                          title: 'Live RPC snapshot unavailable',
                          body: snapshot.error.toString(),
                        ),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _MetricCard(
                            label: 'Chain ID',
                            value: data?.chainId ?? '26062026',
                            note: 'EVM-compatible PokoinPoS network',
                          ),
                          _MetricCard(
                            label: 'Latest block',
                            value: data?.latestBlock ?? '...',
                            note: 'Read from public JSON-RPC',
                          ),
                          _MetricCard(
                            label: 'Gas price',
                            value: data == null
                                ? '...'
                                : '${data.gasPriceWei} wei',
                            note: 'Native gas token: PKN',
                          ),
                          _MetricCard(
                            label: 'Treasury balance',
                            value: data == null
                                ? '...'
                                : '${data.treasuryBalance} PKN',
                            note: 'Native reserve/watch address',
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const _SectionTitle(
                        title: 'Network References',
                        body:
                            'Everything needed to connect wallets, inspect the native chain, verify the wrapped token, and follow public reserve information.',
                      ),
                      const SizedBox(height: 14),
                      const Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _ReferenceCard(
                            icon: Icons.account_tree_outlined,
                            title: 'PokoinPoS RPC',
                            rows: [
                              InfoRow('RPC URL', ProjectLinks.rpc),
                              InfoRow('Explorer', ProjectLinks.explorer),
                              InfoRow('Currency', 'PKN, 18 decimals'),
                              InfoRow(
                                  'Wallet path', 'https://pokoin.com/wallet'),
                            ],
                            links: [
                              LinkTarget(
                                  'Open explorer', ProjectLinks.explorer),
                              LinkTarget(
                                  'Open wallet', 'https://pokoin.com/wallet'),
                            ],
                          ),
                          _ReferenceCard(
                            icon: Icons.verified_outlined,
                            title: 'wPKN on BNB Chain',
                            rows: [
                              InfoRow('Contract', ProjectLinks.wpknContract),
                              InfoRow('Pair', ProjectLinks.pancakePairAddress),
                              InfoRow('Backing', '2,000,000 PKN reserve'),
                              InfoRow('Standard', 'BEP-20 / ERC-20 style'),
                            ],
                            links: [
                              LinkTarget(
                                  'BscScan token', ProjectLinks.bscToken),
                              LinkTarget(
                                  'Trade wPKN', ProjectLinks.pancakeSwap),
                            ],
                          ),
                          _ReferenceCard(
                            icon: Icons.security_outlined,
                            title: 'Reserve and Operations',
                            rows: [
                              InfoRow('Treasury', ProjectLinks.nativeTreasury),
                              InfoRow('Reserve manifest', ProjectLinks.reserve),
                              InfoRow('Health API', ProjectLinks.health),
                              InfoRow('Ready API', ProjectLinks.ready),
                            ],
                            links: [
                              LinkTarget('Reserve proof', ProjectLinks.reserve),
                              LinkTarget(
                                  'Health page', 'https://pokoin.com/health'),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _LiveStatusPanel(
                          status: data?.chainStatus,
                          refreshedAt: data?.refreshedAt),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static BigInt _hexToBigInt(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.isEmpty) {
      return BigInt.zero;
    }
    return BigInt.parse(clean, radix: 16);
  }

  static String _formatWei(BigInt wei) {
    final base = BigInt.from(10).pow(18);
    final whole = wei ~/ base;
    final fraction =
        wei.remainder(base).toString().padLeft(18, '0').substring(0, 4);
    return '$whole.$fraction';
  }
}

class ScanSnapshot {
  final String chainId;
  final String latestBlock;
  final String gasPriceWei;
  final String treasuryBalance;
  final Map<String, dynamic>? chainStatus;
  final DateTime refreshedAt;

  const ScanSnapshot({
    required this.chainId,
    required this.latestBlock,
    required this.gasPriceWei,
    required this.treasuryBalance,
    required this.chainStatus,
    required this.refreshedAt,
  });
}

class _Hero extends StatelessWidget {
  final ScanSnapshot? snapshot;
  final bool loading;

  const _Hero({required this.snapshot, required this.loading});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final heroTitleSize = width < 420 ? 26.0 : (compact ? 30.0 : 34.0);

    return Container(
      padding: EdgeInsets.all(compact ? 20 : 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF111B3F), Color(0xFF0B1020)]),
        borderRadius: BorderRadius.circular(compact ? 24 : 30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Flex(
        direction: compact ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: compact ? 0 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pokoin Scan',
                    style: TextStyle(
                        color: Color(0xFFFDE68A), fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  'Blockchain overview for PokoinPoS, PKN, wPKN, reserve proof, wallet setup, and public chain endpoints.',
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: heroTitleSize,
                      fontWeight: FontWeight.w900,
                      height: 1.12),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Use this page as the public scan dashboard while the full explorer remains available at explorer.pokoin.com.',
                  style: TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 0 : 22, height: compact ? 22 : 0),
          Container(
            width: compact ? double.infinity : 260,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0x99050816),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  loading ? Icons.sync : Icons.check_circle,
                  color: loading
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF22C55E),
                  size: 34,
                ),
                const SizedBox(height: 12),
                Text(
                  loading ? 'Refreshing chain data' : 'Live snapshot loaded',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot == null
                      ? 'Querying RPC...'
                      : 'Updated ${_formatTime(snapshot!.refreshedAt)}',
                  style: const TextStyle(color: Color(0xFFB8C4E6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String note;

  const _MetricCard(
      {required this.label, required this.value, required this.note});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xCC0B1024),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
            const SizedBox(height: 10),
            SelectableText(
              value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(note, style: const TextStyle(color: Color(0xFFB8C4E6))),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String body;

  const _SectionTitle({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(body,
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.5)),
      ],
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<InfoRow> rows;
  final List<LinkTarget> links;

  const _ReferenceCard({
    required this.icon,
    required this.title,
    required this.rows,
    required this.links,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 365,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xB30B1024),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFACC15), size: 32),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            for (final row in rows) _InfoLine(row: row),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final link in links)
                  OutlinedButton.icon(
                    onPressed: () => _open(link.url),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(link.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class InfoRow {
  final String label;
  final String value;

  const InfoRow(this.label, this.value);
}

class LinkTarget {
  final String label;
  final String url;

  const LinkTarget(this.label, this.url);
}

class _InfoLine extends StatelessWidget {
  final InfoRow row;

  const _InfoLine({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.label,
              style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12)),
          const SizedBox(height: 3),
          SelectableText(
            row.value,
            style: const TextStyle(
                color: Color(0xFFE5E7EB), fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class _LiveStatusPanel extends StatelessWidget {
  final Map<String, dynamic>? status;
  final DateTime? refreshedAt;

  const _LiveStatusPanel({required this.status, required this.refreshedAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC111936),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Operational Snapshot',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          if (status == null)
            const Text(
              'The operational chain status endpoint did not return JSON, but the EVM RPC snapshot above can still be live.',
              style: TextStyle(color: Color(0xFFB8C4E6)),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in status!.entries.take(12))
                  Chip(
                    backgroundColor: const Color(0xFF0B1020),
                    label: Text('${entry.key}: ${entry.value}',
                        style: const TextStyle(color: Colors.white)),
                  ),
              ],
            ),
          if (refreshedAt != null) ...[
            const SizedBox(height: 14),
            Text(
              'Last refreshed at ${refreshedAt!.toLocal()}',
              style: const TextStyle(color: Color(0xFF93A4C8)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String title;
  final String body;

  const _Notice({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
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
                  color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: Color(0xFFFFEDD5))),
        ],
      ),
    );
  }
}
