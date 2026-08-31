import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/link.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pokemon_card.dart';
import '../services/card_scan_service.dart';
import '../services/card_service.dart';
import '../utils/card_url.dart';
import '../utils/public_home.dart';
import '../utils/scan_marketplace.dart';

typedef CardScanImagePicker = Future<XFile?> Function(ImageSource source);
typedef CardScanMarketplaceLookup = Future<List<PokemonCard>> Function(
  String query,
);

class CardScanScreen extends StatefulWidget {
  const CardScanScreen({
    super.key,
    this.pickImage,
    this.scanService,
    this.lookupMarketplace,
  });

  final CardScanImagePicker? pickImage;
  final CardScanService? scanService;
  final CardScanMarketplaceLookup? lookupMarketplace;

  @override
  State<CardScanScreen> createState() => _CardScanScreenState();
}

class _CardScanScreenState extends State<CardScanScreen> {
  final ImagePicker _picker = ImagePicker();
  late final CardScanService _scanService =
      widget.scanService ?? CardScanService();

  Uint8List? _preview;
  String _status = '';
  bool _busy = false;
  List<_ResolvedScanHit> _hits = const [];

  Future<XFile?> _pick(ImageSource source) {
    final custom = widget.pickImage;
    if (custom != null) {
      return custom(source);
    }
    return _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
  }

  Future<void> _capture(ImageSource source) async {
    if (_busy) {
      return;
    }
    final file = await _pick(source);
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _preview = bytes;
      _busy = true;
      _status = 'Identifying…';
      _hits = const [];
    });
    final identified = await _scanService.identifyBytes(bytes);
    if (!mounted) {
      return;
    }
    if (identified.error.isNotEmpty) {
      setState(() {
        _busy = false;
        _status = identified.error;
      });
      return;
    }
    if (identified.hits.isEmpty) {
      setState(() {
        _busy = false;
        _status = 'No card box. Try a closer, flatter photo.';
      });
      return;
    }
    final resolved = <_ResolvedScanHit>[];
    for (final hit in identified.hits) {
      resolved.add(await _resolve(hit));
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _hits = resolved;
      _status =
          '${identified.detectMs.round()} ms detect · ${identified.identifyMs.round()} ms identify';
    });
  }

  Future<_ResolvedScanHit> _resolve(CardScanHit hit) async {
    PokemonCard? matched;
    final lookup = widget.lookupMarketplace;
    final query = scanHitAutocompleteQuery(
      name: hit.name,
      collectorNumber: hit.collectorNumber,
    );
    if (query.isNotEmpty) {
      try {
        final cards = lookup == null
            ? await CardService().searchAutocompleteCards(query, limit: 8)
            : await lookup(query);
        matched = pickMarketplaceCardForScanHit(
          name: hit.name,
          collectorNumber: hit.collectorNumber,
          setName: hit.setName,
          candidates: cards,
        );
      } catch (_) {
        matched = null;
      }
    }
    final path = scanHitMarketplacePath(
      name: hit.name,
      collectorNumber: hit.collectorNumber,
      setName: hit.setName,
      cardtraderBlueprintId: hit.cardtraderBlueprintId,
      matchedCard: matched,
    );
    final shortLink = matched == null
        ? ''
        : marketplacePublicShortLinkPath(matched);
    return _ResolvedScanHit(
      hit: hit,
      card: matched,
      marketplacePath: path,
      shortLinkPath: shortLink,
    );
  }

  Future<void> _openMarketplace(String path) async {
    if (path.isEmpty) {
      return;
    }
    if (path.startsWith('/')) {
      context.go(path);
      return;
    }
    final uri = Uri.tryParse(path);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    onPressed: () => goPublicHome(context),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pokoin',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    ),
                  ),
                  const Text(
                    'Card scan',
                    style: TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Photograph a Pokémon card. Matches open the marketplace page with the doubled public-number URL.',
                    style: TextStyle(color: Color(0xFF94A3B8), height: 1.45),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0x14FFFFFF)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_preview != null)
                              Image.memory(_preview!, fit: BoxFit.cover)
                            else
                              const ColoredBox(color: Colors.black),
                            if (_preview == null)
                              const Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'Hold the card in frame, then Scan.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Color(0xFF94A3B8)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _capture(ImageSource.camera),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4ADE80),
                            foregroundColor: const Color(0xFF052E16),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Scan'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _capture(ImageSource.gallery),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E293B),
                            foregroundColor: const Color(0xFFE5E7EB),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Library'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _status,
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  if (_hits.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 4,
                      child: ListView.builder(
                        itemCount: _hits.length,
                        itemBuilder: (context, i) {
                          return _HitCard(
                            resolved: _hits[i],
                            best: i == 0,
                            onMarketplace: () =>
                                _openMarketplace(_hits[i].marketplacePath),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResolvedScanHit {
  const _ResolvedScanHit({
    required this.hit,
    required this.marketplacePath,
    this.card,
    this.shortLinkPath = '',
  });

  final CardScanHit hit;
  final PokemonCard? card;
  final String marketplacePath;
  final String shortLinkPath;
}

class _HitCard extends StatelessWidget {
  const _HitCard({
    required this.resolved,
    required this.best,
    required this.onMarketplace,
  });

  final _ResolvedScanHit resolved;
  final bool best;
  final VoidCallback onMarketplace;

  @override
  Widget build(BuildContext context) {
    final hit = resolved.hit;
    final meta = [
      hit.collectorNumber,
      hit.setName,
    ].where((part) => part.isNotEmpty).join(' · ');
    final href = resolved.shortLinkPath.isNotEmpty
        ? resolved.shortLinkPath
        : resolved.marketplacePath;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1224),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: best ? const Color(0x664ADE80) : const Color(0x14FFFFFF),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hit.name.isEmpty ? 'Unknown' : hit.name,
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${meta.isEmpty ? 'TCGplayer' : meta} · ${(hit.score * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              if (href.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  href,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                children: [
                  if (href.isNotEmpty)
                    Link(
                      uri: Uri.parse(
                        href.startsWith('/')
                            ? 'https://pokoin.com$href'
                            : href,
                      ),
                      target: LinkTarget.self,
                      builder: (context, followLink) {
                        return TextButton(
                          onPressed: followLink ?? onMarketplace,
                          child: const Text('Marketplace'),
                        );
                      },
                    )
                  else
                    TextButton(
                      onPressed: onMarketplace,
                      child: const Text('Marketplace'),
                    ),
                  if (hit.tcgplayerId.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        final uri = Uri.parse(
                          'https://www.tcgplayer.com/product/${hit.tcgplayerId}',
                        );
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      child: const Text('TCGplayer'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
