import 'package:flutter/material.dart';
import '../models/pokemon_card.dart';
import '../models/marketplace_expansion.dart';
import 'marketplace_network_image.dart';
export 'marketplace_cart_navigation.dart';

/// Prefer release dates when supplied. The legacy API has no dates, so use
/// live home new-arrival hints and the bundled catalog insertion order instead.
/// Catalog IDs are an ordering fallback, not invented release timestamps.
List<MarketplaceExpansion> recentHomeExpansions(
  List<MarketplaceExpansion> expansions, {
  Map<String, int> catalogOrder = const {},
  List<String> newArrivalSets = const [],
  int limit = 12,
}) {
  final hints = <String, int>{};
  for (final name in newArrivalSets) {
    hints.putIfAbsent(name.trim().toLowerCase(), () => hints.length);
  }
  final order = {
    for (final entry in catalogOrder.entries)
      entry.key.trim().toLowerCase(): entry.value
  };
  final unique = <String, MarketplaceExpansion>{};
  for (final expansion in expansions) {
    final key = expansion.name.trim().toLowerCase();
    if (key.isNotEmpty &&
        expansion.slug.isNotEmpty &&
        expansion.cardCount > 0) {
      unique.putIfAbsent(key, () => expansion);
    }
  }
  final result = unique.values.toList()
    ..sort((a, b) {
      final aKey = a.name.trim().toLowerCase();
      final bKey = b.name.trim().toLowerCase();
      final aHint = hints[aKey];
      final bHint = hints[bKey];
      if (aHint != null || bHint != null) {
        final byHint = (aHint ?? hints.length).compareTo(bHint ?? hints.length);
        if (byHint != 0) return byHint;
      }
      if (a.releaseDate != null || b.releaseDate != null) {
        if (a.releaseDate == null) return 1;
        if (b.releaseDate == null) return -1;
        final byDate = b.releaseDate!.compareTo(a.releaseDate!);
        if (byDate != 0) return byDate;
      }
      final byOrder = (b.expansionId ?? order[bKey] ?? 0)
          .compareTo(a.expansionId ?? order[aKey] ?? 0);
      return byOrder != 0 ? byOrder : aKey.compareTo(bKey);
    });
  return result.take(limit < 0 ? 0 : limit).toList(growable: false);
}

/// Only backend-ranked IDs are best sellers; price is not evidence of sales.
List<PokemonCard> marketplaceBestSellers(
  List<PokemonCard> cards,
  List<String> rankedIds,
) =>
    marketplaceCardsForRankedIds(cards, rankedIds);

/// Keep only the records needed by the two mobile discovery rails.
List<PokemonCard> marketplaceDiscoverySourceCards(
  List<PokemonCard> cards,
  Iterable<String> wantedIds,
) {
  final wanted = wantedIds.toSet();
  if (wanted.isEmpty) return const [];
  return cards
      .where((card) => wanted.contains(card.id))
      .toList(growable: false);
}

List<PokemonCard> marketplaceCardsForRankedIds(
  List<PokemonCard> cards,
  List<String> rankedIds,
) {
  if (rankedIds.isEmpty) return const [];
  final wanted = rankedIds.toSet();
  final byId = {
    for (final card in cards)
      if (wanted.contains(card.id)) card.id: card,
  };
  final seen = <String>{};
  return rankedIds
      .where(seen.add)
      .map((id) => byId[id])
      .whereType<PokemonCard>()
      .take(12)
      .toList(growable: false);
}

class RecentExpansionsCarousel extends StatefulWidget {
  const RecentExpansionsCarousel({
    super.key,
    required this.expansions,
    required this.onSelected,
    this.isLoading = false,
    this.onRetry,
  });

  final List<MarketplaceExpansion> expansions;
  final ValueChanged<MarketplaceExpansion> onSelected;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  State<RecentExpansionsCarousel> createState() =>
      _RecentExpansionsCarouselState();
}

class _RecentExpansionsCarouselState extends State<RecentExpansionsCarousel> {
  final _controller = ScrollController();
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!mounted || !_controller.hasClients) return;
    final back = _controller.offset > 2;
    final forward =
        _controller.offset < _controller.position.maxScrollExtent - 2;
    if (back != _canGoBack || forward != _canGoForward) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  void _move(int direction) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset +
            direction * _controller.position.viewportDimension * .85)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final inset = width >= 1264 ? (width - 1220) / 2 : 22.0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Row(
            children: [
              const Expanded(
                  child: Text('Nuove Espansioni',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800))),
              IconButton(
                tooltip: 'Espansioni precedenti',
                color: const Color(0xFFC4B5FD),
                disabledColor: const Color(0xFF64748B),
                onPressed: _canGoBack ? () => _move(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Espansioni successive',
                color: const Color(0xFFC4B5FD),
                disabledColor: const Color(0xFF64748B),
                onPressed: _canGoForward ? () => _move(1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!widget.isLoading && widget.expansions.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Column(
              children: [
                const Text('Le espansioni non sono disponibili al momento.',
                    style: TextStyle(color: Color(0xFF9CAAC9))),
                if (widget.onRetry != null)
                  TextButton(
                      onPressed: widget.onRetry, child: const Text('Riprova')),
              ],
            ),
          )
        else
          SizedBox(
            height: 196,
            child: ListView.separated(
              key: const ValueKey('recent-expansions-slider'),
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: inset),
              itemCount: widget.isLoading ? 4 : widget.expansions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                if (widget.isLoading) {
                  return Container(
                    width: width < 560 ? 218 : 260,
                    decoration: BoxDecoration(
                      color: const Color(0xFF11182E),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final expansion = widget.expansions[index];
                final image = expansion.logoImageUrl.isNotEmpty
                    ? expansion.logoImageUrl
                    : expansion.symbolImageUrl.isNotEmpty
                        ? expansion.symbolImageUrl
                        : expansion.defaultSymbolUrl;
                return SizedBox(
                  width: width < 560 ? 218 : 260,
                  child: Material(
                    color: const Color(0xFF11182E),
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => widget.onSelected(expansion),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Expanded(
                              child: image.isEmpty
                                  ? const Icon(Icons.style_outlined,
                                      size: 48, color: Color(0xFFA78BFA))
                                  : MarketplaceNetworkImage(
                                      imageUrl: image,
                                      errorWidget: (_, __, ___) => const Icon(
                                          Icons.style_outlined,
                                          size: 48,
                                          color: Color(0xFFA78BFA)),
                                    ),
                            ),
                            const SizedBox(height: 12),
                            Text(expansion.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            const SizedBox(height: 4),
                            Text('${expansion.cardCount} carte',
                                style: const TextStyle(
                                    color: Color(0xFF9CAAC9), fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
