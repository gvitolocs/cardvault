import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../providers/card_provider.dart';
import '../providers/user_card_collection_provider.dart';
import '../services/card_service.dart';
import '../utils/card_url.dart';

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({
    super.key,
    this.initialExpansionName,
    this.initialExpansionSlug,
  });

  final String? initialExpansionName;
  final String? initialExpansionSlug;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class CollectionExpansionScreen extends ConsumerWidget {
  const CollectionExpansionScreen({super.key, required this.expansionSlug});

  final String expansionSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotState =
        ref.watch(_collectionExpansionSnapshotProvider(expansionSlug));
    final collectionOwnedIds = ref.watch(userOwnedBlueprintIdsProvider);
    final ownedIds = collectionOwnedIds;
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: snapshotState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _CollectionLoadError(error: '$error'),
              data: (snapshot) {
                if (snapshot == null) {
                  return const _EmptyCollection(
                    message: 'Expansion not found.',
                  );
                }
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(22),
                      sliver: SliverToBoxAdapter(
                        child: _SelectedExpansionHeader(
                          name: snapshot.expansion.name,
                          count: snapshot.cards.length,
                          onBack: () => context.go('/collection'),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                      sliver: _CollectionSliverGrid(
                        cards: snapshot.cards,
                        ownedIds: ownedIds,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  String? _selectedExpansion;
  _ExpansionRegion _region = _ExpansionRegion.occidental;
  bool _resolvedInitialExpansion = false;

  @override
  void initState() {
    super.initState();
    _selectedExpansion = widget.initialExpansionName;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveInitialExpansionSlug();
    });
  }

  @override
  void didUpdateWidget(covariant CollectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialExpansionSlug != widget.initialExpansionSlug ||
        oldWidget.initialExpansionName != widget.initialExpansionName) {
      _resolvedInitialExpansion = false;
      _selectedExpansion = widget.initialExpansionName;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolveInitialExpansionSlug();
      });
    }
  }

  Future<void> _resolveInitialExpansionSlug() async {
    final slug = widget.initialExpansionSlug?.trim();
    if (_resolvedInitialExpansion || slug == null || slug.isEmpty) {
      return;
    }
    _resolvedInitialExpansion = true;
    final expansion = await CardService().getMarketplaceExpansionBySlug(slug);
    if (mounted && expansion != null && expansion.name.isNotEmpty) {
      setState(() {
        _selectedExpansion = expansion.name;
        _region = _regionForExpansion(expansion.name);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardState = ref.watch(cardProvider);
    final marketplaceExpansionsState = ref.watch(_marketplaceExpansionsProvider);
    final collectionOwnedIds = ref.watch(userOwnedBlueprintIdsProvider);
    final ownedIds = collectionOwnedIds;
    final cards =
        cardState.cards.where((card) => card.productType == 'card').toList();
    final expansions = _expansions(
      cards,
      ownedIds,
      marketplaceExpansionsState.valueOrNull ?? const <MarketplaceExpansion>[],
    )
        .where((expansion) => expansion.region == _region)
        .toList();
    final selectedExpansion = _selectedExpansion;
    final selectedExpansionState = selectedExpansion == null
        ? null
        : ref.watch(_collectionExpansionCardsProvider(selectedExpansion));
    final localExpansionCards = selectedExpansion == null
        ? const <PokemonCard>[]
        : _sortExpansionCards(
            cards
                .where((card) =>
                    card.set == selectedExpansion && card.productType == 'card')
                .toList(),
          );
    final remoteExpansionCards = selectedExpansionState?.valueOrNull;
    final visibleCards = remoteExpansionCards?.isNotEmpty == true
        ? remoteExpansionCards!
        : localExpansionCards;

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                _CollectionHeader(
                  ownedCount: ownedIds.length,
                  totalCount: cards.length,
                  onBack: () => context.go('/profile'),
                ),
                const SizedBox(height: 18),
                _CollectionRegionTabs(
                  selected: _region,
                  onSelected: (value) => setState(() {
                    _region = value;
                    _selectedExpansion = null;
                  }),
                ),
                const SizedBox(height: 18),
                if (cardState.isLoading && marketplaceExpansionsState.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (selectedExpansion == null)
                  _ExpansionGrid(
                    expansions: expansions,
                    onSelected: (value) => context.go(
                      '/collection/${collectionExpansionSlug(value)}',
                    ),
                  )
                else if (selectedExpansionState?.isLoading == true &&
                    visibleCards.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (visibleCards.isEmpty)
                  const _EmptyCollection()
                else ...[
                  _SelectedExpansionHeader(
                    name: selectedExpansion,
                    count: visibleCards.length,
                    onBack: () => setState(() => _selectedExpansion = null),
                  ),
                  const SizedBox(height: 14),
                  _CollectionGrid(cards: visibleCards, ownedIds: ownedIds),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_ExpansionSummary> _expansions(
    List<PokemonCard> cards,
    Set<String> ownedIds,
    List<MarketplaceExpansion> marketplaceExpansions,
  ) {
    final grouped = <String, List<PokemonCard>>{};
    for (final card in cards) {
      final set = card.set.trim();
      if (set.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(set, () => <PokemonCard>[]).add(card);
    }
    final summaries = <_ExpansionSummary>[];
    final seen = <String>{};
    for (final marketplaceExpansion in marketplaceExpansions) {
      final name = marketplaceExpansion.name.trim();
      if (name.isEmpty) {
        continue;
      }
      final expansionCards = grouped[name] ?? const <PokemonCard>[];
      seen.add(name);
      summaries.add(_ExpansionSummary(
        name: name,
        cardCount: marketplaceExpansion.cardCount,
        ownedCount:
            expansionCards.where((card) => ownedIds.contains(card.id)).length,
        region: _regionForExpansion(name),
        imageUrl: marketplaceExpansion.symbolImageUrl,
      ));
    }
    for (final entry in grouped.entries) {
      if (seen.contains(entry.key)) {
        continue;
      }
      final expansionCards = entry.value;
      final symbolUrl = expansionCards
          .map((card) => card.expansionSymbolUrl.trim())
          .firstWhere((url) => url.isNotEmpty, orElse: () => '');
      summaries.add(_ExpansionSummary(
        name: entry.key,
        cardCount: expansionCards.length,
        ownedCount:
            expansionCards.where((card) => ownedIds.contains(card.id)).length,
        region: _regionForExpansion(entry.key),
        imageUrl: symbolUrl,
      ));
    }
    summaries.sort((a, b) {
      final count = b.cardCount.compareTo(a.cardCount);
      if (count != 0) {
        return count;
      }
      return a.name.compareTo(b.name);
    });
    return summaries;
  }
}

enum _ExpansionRegion { occidental, chinese, japanese }

final _collectionExpansionCardsProvider =
    FutureProvider.family<List<PokemonCard>, String>((ref, expansion) {
  return CardService().getCardsByExpansion(expansion);
});

final _collectionExpansionSnapshotProvider =
    FutureProvider.family<MarketplaceExpansionSnapshot?, String>((ref, slug) {
  return CardService().getMarketplaceExpansionSnapshotBySlug(slug);
});

final _marketplaceExpansionsProvider =
    FutureProvider<List<MarketplaceExpansion>>((ref) {
  return CardService().getMarketplaceExpansions();
});

class _ExpansionSummary {
  const _ExpansionSummary({
    required this.name,
    required this.cardCount,
    required this.ownedCount,
    required this.region,
    required this.imageUrl,
  });

  final String name;
  final int cardCount;
  final int ownedCount;
  final _ExpansionRegion region;
  final String imageUrl;
}

_ExpansionRegion _regionForExpansion(String expansion) {
  final lower = expansion.toLowerCase();
  final compact = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (RegExp(r'[\u3400-\u9fff]').hasMatch(expansion) ||
      lower.contains('chinese') ||
      lower.contains('china') ||
      lower.contains('simplified chinese') ||
      lower.contains('traditional chinese') ||
      lower.contains('happy combination') ||
      lower.contains('happy set') ||
      lower.contains('happy pack') ||
      lower.contains('reward pack') ||
      lower.contains('transformation pack') ||
      lower.contains('southeast asia') ||
      (RegExp(r'^c(sv|svh|sma|sm|smp|s[0-9])').hasMatch(compact) &&
          !lower.contains('start deck'))) {
    return _ExpansionRegion.chinese;
  }
  if (RegExp(r'[\u3040-\u30ff]').hasMatch(expansion) ||
      lower.contains('japanese') ||
      lower.contains(' jp') ||
      lower.endsWith('jp') ||
      lower.contains('start deck') ||
      lower.contains('battle collection') ||
      lower.contains('future flash') ||
      lower.contains('ancient roar') ||
      lower.contains('ruler of the black flame') ||
      lower.contains('shiny treasure') ||
      lower.contains('wild force') ||
      lower.contains('cyber judge') ||
      lower.contains('crimson haze') ||
      lower.contains('mask of change') ||
      compact.contains('svjp') ||
      compact.endsWith('jp')) {
    return _ExpansionRegion.japanese;
  }
  return _ExpansionRegion.occidental;
}

List<PokemonCard> _sortExpansionCards(List<PokemonCard> cards) {
  return [...cards]..sort((a, b) {
      final number = _compareCollectorNumberSortKeys(
        _collectorNumberSortKey(a.number),
        _collectorNumberSortKey(b.number),
      );
      if (number != 0) {
        return number;
      }
      return a.name.compareTo(b.name);
    });
}

int _compareCollectorNumberSortKeys(
  ({int group, int number, String suffix}) a,
  ({int group, int number, String suffix}) b,
) {
  final group = a.group.compareTo(b.group);
  if (group != 0) return group;
  final number = a.number.compareTo(b.number);
  if (number != 0) return number;
  return a.suffix.compareTo(b.suffix);
}

({int group, int number, String suffix}) _collectorNumberSortKey(
  String number,
) {
  final normalized = number.trim().toLowerCase();
  final firstNumber = RegExp(r'\d+').firstMatch(normalized);
  final parsedNumber =
      firstNumber == null ? 1 << 30 : int.tryParse(firstNumber.group(0)!) ?? 1 << 30;
  final normalNumber =
      RegExp(r'[a-z]*\d+[a-z]?\s*/\s*\d+', caseSensitive: false)
              .hasMatch(normalized) ||
          RegExp(r'^\s*\d+[a-z]?\s*$').hasMatch(normalized);
  return (
    group: normalNumber ? 0 : 1,
    number: parsedNumber,
    suffix: normalized,
  );
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.ownedCount,
    required this.totalCount,
    required this.onBack,
  });

  final int ownedCount;
  final int totalCount;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My collection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Welcome! Here you can keep track of your collection. $ownedCount owned signals across $totalCount catalog cards.',
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CollectionRegionTabs extends StatelessWidget {
  const _CollectionRegionTabs({
    required this.selected,
    required this.onSelected,
  });

  final _ExpansionRegion selected;
  final ValueChanged<_ExpansionRegion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final entry in const [
          (region: _ExpansionRegion.occidental, label: 'Occidental'),
          (region: _ExpansionRegion.chinese, label: 'Chinese'),
          (region: _ExpansionRegion.japanese, label: 'Japanese'),
        ])
          ChoiceChip(
            label: Text(entry.label),
            selected: selected == entry.region,
            onSelected: (_) => onSelected(entry.region),
          ),
      ],
    );
  }
}

class _ExpansionGrid extends StatelessWidget {
  const _ExpansionGrid({required this.expansions, required this.onSelected});

  final List<_ExpansionSummary> expansions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (expansions.isEmpty) {
      return const _EmptyCollection(
        message: 'No expansions found for this collection group yet.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1100
            ? 4
            : width > 760
                ? 3
                : width > 480
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: expansions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 150,
          ),
          itemBuilder: (context, index) => _ExpansionCard(
            expansion: expansions[index],
            onTap: () => onSelected(expansions[index].name),
          ),
        );
      },
    );
  }
}

class _ExpansionCard extends StatelessWidget {
  const _ExpansionCard({required this.expansion, required this.onTap});

  final _ExpansionSummary expansion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = expansion.cardCount == 0
        ? 0.0
        : expansion.ownedCount / expansion.cardCount;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xDD0B1020),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ExpansionLogo(imageUrl: expansion.imageUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    expansion.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              'Owned ${expansion.ownedCount}/${expansion.cardCount}',
              style: const TextStyle(color: Color(0xFF93A4C8)),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.clamp(0, 1),
              color: const Color(0xFFFACC15),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpansionLogo extends StatelessWidget {
  const _ExpansionLogo({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const Icon(Icons.auto_awesome_motion, color: Color(0xFFFACC15));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.auto_awesome_motion, color: Color(0xFFFACC15)),
      ),
    );
  }
}

class _SelectedExpansionHeader extends StatelessWidget {
  const _SelectedExpansionHeader({
    required this.name,
    required this.count,
    required this.onBack,
  });

  final String name;
  final int count;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Expansions'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            '$name · $count cards',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _CollectionGrid extends StatelessWidget {
  const _CollectionGrid({required this.cards, required this.ownedIds});

  final List<PokemonCard> cards;
  final Set<String> ownedIds;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1120
            ? 5
            : width > 860
                ? 4
                : width > 620
                    ? 3
                    : width > 420
                        ? 2
                        : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 360,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            return _CollectionCard(
              card: card,
              owned: ownedIds.contains(card.id),
            );
          },
        );
      },
    );
  }
}

class _CollectionSliverGrid extends StatelessWidget {
  const _CollectionSliverGrid({required this.cards, required this.ownedIds});

  final List<PokemonCard> cards;
  final Set<String> ownedIds;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width.clamp(0, 1280).toDouble();
    final columns = width > 1120
        ? 5
        : width > 860
            ? 4
            : width > 620
                ? 3
                : width > 420
                    ? 2
                    : 1;
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: 360,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final card = cards[index];
          return _CollectionCard(
            card: card,
            owned: ownedIds.contains(card.id),
          );
        },
        childCount: cards.length,
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.card, required this.owned});

  final PokemonCard card;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(cardDetailPath(card)),
      borderRadius: BorderRadius.circular(22),
      child: Opacity(
        opacity: owned ? 1 : 0.42,
        child: ColorFiltered(
          colorFilter: owned
              ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
              : const ColorFilter.matrix(<double>[
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xDD0B1020),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: owned
                    ? const Color(0x66FACC15)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CollectionCardImage(imageUrl: card.previewImageUrl),
                ),
                const SizedBox(height: 10),
                Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  card.number.trim().isEmpty
                      ? card.set
                      : '${card.set} #${card.number}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed:
                          owned ? () => context.go(cardDetailPath(card)) : null,
                      child: const Text('Sell'),
                    ),
                    OutlinedButton(
                      onPressed: owned
                          ? () => context.go('/nft?card=${card.id}')
                          : null,
                      child: const Text('NFT'),
                    ),
                    OutlinedButton(
                      onPressed: owned ? () {} : null,
                      child: const Text('Trade'),
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

class _CollectionCardImage extends StatelessWidget {
  const _CollectionCardImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final resolvedImageUrl = imageUrl.trim();
    if (resolvedImageUrl.isEmpty) {
      return const Icon(
        Icons.style,
        color: Color(0xFFFACC15),
        size: 46,
      );
    }
    return Image.network(
      resolvedImageUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.style,
        color: Color(0xFFFACC15),
        size: 46,
      ),
    );
  }
}

class _CollectionLoadError extends StatelessWidget {
  const _CollectionLoadError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: _EmptyCollection(message: 'Collection failed to load: $error'),
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({
    this.message =
        'The collection catalog is loading. Visit the marketplace to warm the card catalog.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFB8C4E6)),
      ),
    );
  }
}
