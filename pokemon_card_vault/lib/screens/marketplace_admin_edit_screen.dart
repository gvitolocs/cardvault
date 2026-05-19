import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../providers/auth_provider.dart';

class MarketplaceAdminEditScreen extends ConsumerStatefulWidget {
  const MarketplaceAdminEditScreen({super.key});

  @override
  ConsumerState<MarketplaceAdminEditScreen> createState() =>
      _MarketplaceAdminEditScreenState();
}

class _MarketplaceAdminEditScreenState
    extends ConsumerState<MarketplaceAdminEditScreen> {
  final _queryController = TextEditingController();
  List<_ExpansionSymbolRow> _rows = const [];
  bool _loading = true;
  bool _missingOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRows());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadRows() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in before opening marketplace admin tools.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await user.getIdToken();
      final uri = Uri(
        path: '/api/marketplace-expansion-symbols',
        queryParameters: {
          if (_queryController.text.trim().isNotEmpty)
            'query': _queryController.text.trim(),
          if (_missingOnly) 'missingOnly': '1',
          'limit': '500',
        },
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(payload['error'] as String? ?? 'Load failed.');
      }
      final rows = (payload['expansions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => _ExpansionSymbolRow.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .toList();
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _saveRow(_ExpansionSymbolRow row) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      setState(() => _error = 'Sign in before saving.');
      return;
    }
    setState(() {
      row.saving = true;
      row.error = null;
    });
    try {
      final token = await user.getIdToken();
      final response = await http.post(
        Uri.parse('/api/marketplace-expansion-symbols'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': row.name,
          'symbolImageUrl': row.controller.text.trim(),
          'sourceAssetCode': row.sourceController.text.trim(),
        }),
      );
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(payload['error'] as String? ?? 'Save failed.');
      }
      final updated = _ExpansionSymbolRow.fromJson(
        Map<String, dynamic>.from(payload['expansion'] as Map? ?? const {}),
      );
      row.controller.text = updated.symbolImageUrl;
      row.sourceController.text = updated.sourceAssetCode;
      row.symbolImageUrl = updated.symbolImageUrl;
      row.sourceAssetCode = updated.sourceAssetCode;
      row.defaultSymbolUrl = updated.defaultSymbolUrl;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${row.name}')),
        );
      }
    } catch (error) {
      row.error = '$error';
    } finally {
      if (mounted) {
        setState(() => row.saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xE60A1026),
        title: const Text('Marketplace Admin Edit'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              _AdminHero(user: user),
              const SizedBox(height: 18),
              _Toolbar(
                controller: _queryController,
                missingOnly: _missingOnly,
                loading: _loading,
                onMissingOnlyChanged: (value) {
                  setState(() => _missingOnly = value);
                  _loadRows();
                },
                onSearch: _loadRows,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFCA5A5)),
                ),
              ],
              const SizedBox(height: 18),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_rows.isEmpty)
                const _EmptyAdminState()
              else
                for (final row in _rows) ...[
                  _ExpansionSymbolEditor(
                    row: row,
                    onUseDefault: () {
                      setState(() => row.controller.text = row.defaultSymbolUrl);
                    },
                    onSave: () => _saveRow(row),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpansionSymbolRow {
  _ExpansionSymbolRow({
    required this.name,
    required this.cardCount,
    required this.symbolImageUrl,
    required this.defaultSymbolUrl,
    required this.sourceAssetCode,
  })  : controller = TextEditingController(text: symbolImageUrl),
        sourceController = TextEditingController(text: sourceAssetCode);

  factory _ExpansionSymbolRow.fromJson(Map<String, dynamic> json) {
    return _ExpansionSymbolRow(
      name: '${json['name'] ?? ''}',
      cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
      symbolImageUrl: '${json['symbolImageUrl'] ?? ''}',
      defaultSymbolUrl: '${json['defaultSymbolUrl'] ?? ''}',
      sourceAssetCode: '${json['sourceAssetCode'] ?? ''}',
    );
  }

  final String name;
  final int cardCount;
  String symbolImageUrl;
  String defaultSymbolUrl;
  String sourceAssetCode;
  final TextEditingController controller;
  final TextEditingController sourceController;
  bool saving = false;
  String? error;
}

class _AdminHero extends StatelessWidget {
  const _AdminHero({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Expansion Logo Matching',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user == null
                ? 'You are not signed in.'
                : 'Signed in as ${user!.email ?? user!.uid}. Changes persist in the marketplace expansion symbol table.',
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.missingOnly,
    required this.loading,
    required this.onMissingOnlyChanged,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool missingOnly;
  final bool loading;
  final ValueChanged<bool> onMissingOnlyChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            onSubmitted: (_) => onSearch(),
            decoration: const InputDecoration(
              labelText: 'Search expansion name',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        FilterChip(
          label: const Text('Missing logos only'),
          selected: missingOnly,
          onSelected: onMissingOnlyChanged,
        ),
        FilledButton.icon(
          onPressed: loading ? null : onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Load'),
        ),
      ],
    );
  }
}

class _ExpansionSymbolEditor extends StatelessWidget {
  const _ExpansionSymbolEditor({
    required this.row,
    required this.onUseDefault,
    required this.onSave,
  });

  final _ExpansionSymbolRow row;
  final VoidCallback onUseDefault;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final previewUrl = row.controller.text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SymbolPreview(url: previewUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      '${row.cardCount} cards',
                      style: const TextStyle(color: Color(0xFF93A4C8)),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: row.saving ? null : onSave,
                child: row.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: row.controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Logo URL',
              hintText: 'https://cdn.pokoin.com/expansions/symbols/...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: row.sourceController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Source asset code',
              hintText: 'Optional, e.g. sv4pt5',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: row.defaultSymbolUrl.isEmpty ? null : onUseDefault,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Use static CDN path'),
              ),
              if (row.defaultSymbolUrl.isNotEmpty)
                SelectableText(
                  row.defaultSymbolUrl,
                  style: const TextStyle(color: Color(0xFF93A4C8)),
                ),
            ],
          ),
          if (row.error != null) ...[
            const SizedBox(height: 10),
            Text(row.error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
          ],
        ],
      ),
    );
  }
}

class _SymbolPreview extends StatelessWidget {
  const _SymbolPreview({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: url.isEmpty
          ? const Icon(Icons.image_not_supported_outlined,
              color: Color(0xFF93A4C8))
          : Image.network(
              url,
              width: 42,
              height: 42,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Color(0xFFFCA5A5),
              ),
            ),
    );
  }
}

class _EmptyAdminState extends StatelessWidget {
  const _EmptyAdminState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        'No expansions found.',
        style: TextStyle(color: Color(0xFF93A4C8)),
      ),
    );
  }
}
