import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../models/user_card_collection_item.dart';
import '../providers/card_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/user_card_collection_provider.dart';
import '../services/card_service.dart';
import '../utils/card_navigation.dart';
import '../utils/card_palette.dart';
import '../utils/card_url.dart';
import '../widgets/artist_suggestion_field.dart';

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
    final ownership = ref.watch(userCollectionOwnershipIndexProvider);
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
                          count: snapshot.expansion.cardCount,
                          onBack: () => context.go('/collection'),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                      sliver: _CollectionSliverGrid(
                        cards: snapshot.cards,
                        ownership: ownership,
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

class CollectionArtistScreen extends ConsumerWidget {
  const CollectionArtistScreen({super.key, required this.artistSlug});

  final String artistSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotState =
        ref.watch(_collectionArtistSnapshotProvider(artistSlug));
    final ownership = ref.watch(userCollectionOwnershipIndexProvider);
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
                    message: 'Artist collection not found.',
                  );
                }
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(22),
                      sliver: SliverToBoxAdapter(
                        child: _SelectedCollectionHeader(
                          backLabel: 'Collection',
                          name: snapshot.name,
                          count: snapshot.cardCount,
                          subtitle: 'Artist collection',
                          onBack: () => context.go('/collection'),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                      sliver: _CollectionSliverGrid(
                        cards: snapshot.cards,
                        ownership: ownership,
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
  final TextEditingController _artistSearchController = TextEditingController();
  String? _selectedExpansion;
  _ExpansionRegion _region = _ExpansionRegion.occidental;
  bool _showArtistCollections = false;
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

  @override
  void dispose() {
    _artistSearchController.dispose();
    super.dispose();
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
    final marketplaceExpansionsState =
        ref.watch(_marketplaceExpansionsProvider);
    final marketplaceArtistsState = ref.watch(_marketplaceArtistsProvider);
    final ownership = ref.watch(userCollectionOwnershipIndexProvider);
    final cards =
        cardState.cards.where((card) => card.productType == 'card').toList();
    final expansions = _expansions(
      cards,
      ownership,
      marketplaceExpansionsState.valueOrNull ?? const <MarketplaceExpansion>[],
    ).where((expansion) => expansion.region == _region).toList();
    final selectedExpansion = _selectedExpansion;
    final artistSummaries = _artistSummaries(
      cards,
      ownership,
      marketplaceArtistsState.valueOrNull ?? const <MarketplaceArtistSummary>[],
    );
    final artistSearchQuery = _artistSearchController.text.trim().toLowerCase();
    final visibleArtistSummaries = artistSearchQuery.isEmpty
        ? artistSummaries
        : artistSummaries
            .where(
              (artist) => artist.name.toLowerCase().contains(artistSearchQuery),
            )
            .toList(growable: false);
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
                  ownedCount: ownership.ownedCardCount,
                  nftCount: ownership.nftCardCount,
                  totalCount: cards.length,
                  onBack: () => context.go('/profile'),
                ),
                const SizedBox(height: 18),
                _CollectionRegionTabs(
                  selected: _region,
                  onSelected: (value) => setState(() {
                    _region = value;
                    _selectedExpansion = null;
                    _showArtistCollections = false;
                  }),
                ),
                const SizedBox(height: 18),
                if (cardState.isLoading && marketplaceExpansionsState.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (selectedExpansion == null) ...[
                  _CollectionModeActions(
                    showArtistCollections: _showArtistCollections,
                    onShowArtists: () => setState(
                      () => _showArtistCollections = !_showArtistCollections,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_showArtistCollections)
                    _ArtistCollectionGrid(
                      summaries: visibleArtistSummaries,
                      totalCount: artistSummaries.length,
                      searchController: _artistSearchController,
                      searchQuery: _artistSearchController.text.trim(),
                      onSearchChanged: (_) => setState(() {}),
                      onSuggestedArtistSelected: (artist) {
                        final slug = artist.slug.trim().isEmpty
                            ? artistSlug(artist.normalizedArtist)
                            : artist.slug;
                        context.go(collectionArtistPath(slug));
                      },
                      onSelected: (artist) => context.go(
                        collectionArtistPath(artist),
                      ),
                    )
                  else
                    _ExpansionGrid(
                      expansions: expansions,
                      onSelected: (value) => context.go(
                        '/collection/${collectionExpansionSlug(value)}',
                      ),
                    ),
                ] else if (selectedExpansionState?.isLoading == true &&
                    visibleCards.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (visibleCards.isEmpty)
                  const _EmptyCollection()
                else ...[
                  _SelectedExpansionHeader(
                    name: selectedExpansion,
                    count: _selectedExpansionCount(
                      selectedExpansion,
                      visibleCards,
                      marketplaceExpansionsState.valueOrNull ??
                          const <MarketplaceExpansion>[],
                    ),
                    onBack: () => setState(() => _selectedExpansion = null),
                  ),
                  const SizedBox(height: 14),
                  _CollectionGrid(cards: visibleCards, ownership: ownership),
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
    CollectionOwnershipIndex ownership,
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
        ownedCount: expansionCards.where(ownership.ownsCard).length,
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
        ownedCount: expansionCards.where(ownership.ownsCard).length,
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

  List<_ArtistSummary> _artistSummaries(
    List<PokemonCard> cards,
    CollectionOwnershipIndex ownership,
    List<MarketplaceArtistSummary> marketplaceArtists,
  ) {
    final grouped = <String, List<PokemonCard>>{};
    for (final card in cards) {
      final artist = card.artist.trim();
      if (artist.isEmpty) {
        continue;
      }
      final slug = artistSlug(artist);
      if (slug.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(slug, () => <PokemonCard>[]).add(card);
    }
    final summaries = <_ArtistSummary>[];
    final seen = <String>{};
    for (final marketplaceArtist in marketplaceArtists) {
      final name = marketplaceArtist.name.trim();
      final slug = marketplaceArtist.slug.trim();
      if (name.isEmpty || slug.isEmpty) {
        continue;
      }
      final artistCards = grouped[slug] ?? const <PokemonCard>[];
      seen.add(slug);
      summaries.add(_ArtistSummary(
        name: name,
        slug: slug,
        cardCount: marketplaceArtist.cardCount,
        ownedCount: artistCards.where(ownership.ownsCard).length,
        imageUrl: marketplaceArtist.imageUrl,
      ));
    }
    for (final entry in grouped.entries) {
      if (seen.contains(entry.key)) {
        continue;
      }
      final artistCards = entry.value;
      summaries.add(_ArtistSummary(
        name: _artistSummaryTitleFromSlug(entry.key),
        slug: entry.key,
        cardCount: artistCards.length,
        ownedCount: artistCards.where(ownership.ownsCard).length,
        imageUrl: artistCards
            .map((card) =>
                card.imageUrl.isNotEmpty ? card.imageUrl : card.previewImageUrl)
            .firstWhere((url) => url.trim().isNotEmpty, orElse: () => ''),
      ));
    }
    summaries.sort((a, b) {
      final owned = b.ownedCount.compareTo(a.ownedCount);
      if (owned != 0) {
        return owned;
      }
      final count = b.cardCount.compareTo(a.cardCount);
      if (count != 0) {
        return count;
      }
      return a.name.compareTo(b.name);
    });
    return summaries;
  }

  int _selectedExpansionCount(
    String selectedExpansion,
    List<PokemonCard> visibleCards,
    List<MarketplaceExpansion> marketplaceExpansions,
  ) {
    for (final expansion in marketplaceExpansions) {
      if (expansion.name.trim() == selectedExpansion.trim()) {
        return expansion.cardCount;
      }
    }
    return visibleCards.length;
  }
}

enum _ExpansionRegion { occidental, chinese, japanese }

class CollectionOwnershipIndex {
  CollectionOwnershipIndex(Iterable<UserCardCollectionItem> items) {
    for (final item in items) {
      final id = item.cardId.trim();
      if (id.isNotEmpty) {
        _ids.add(id);
        if (item.isNft) {
          _nftIds.add(id);
        }
      }
      final signature = _collectionSignature(
        name: item.cardName,
        setName: item.setName,
        number: item.collectorNumber,
      );
      if (signature.isNotEmpty) {
        _signatures.add(signature);
        if (item.isNft) {
          _nftSignatures.add(signature);
        }
      }
    }
  }

  final Set<String> _ids = {};
  final Set<String> _signatures = {};
  final Set<String> _nftIds = {};
  final Set<String> _nftSignatures = {};

  int get ownedCardCount =>
      _signatures.isNotEmpty ? _signatures.length : _ids.length;

  int get nftCardCount =>
      _nftSignatures.isNotEmpty ? _nftSignatures.length : _nftIds.length;

  bool ownsCard(PokemonCard card) {
    if (_ids.contains(card.id.trim())) {
      return true;
    }
    final signature = _collectionSignature(
      name: card.name,
      setName: card.set,
      number: card.number,
    );
    return signature.isNotEmpty && _signatures.contains(signature);
  }
}

final userCollectionOwnershipIndexProvider =
    Provider<CollectionOwnershipIndex>((ref) {
  final items = ref.watch(userCardCollectionProvider).valueOrNull ?? const [];
  return CollectionOwnershipIndex(items);
});

String _collectionSignature({
  required String name,
  required String setName,
  required String number,
}) {
  final normalizedName = _collectionKeyPart(name);
  final normalizedSet = _collectionKeyPart(setName);
  final normalizedNumber = _collectionNumberKey(number);
  if (normalizedName.isEmpty ||
      normalizedSet.isEmpty ||
      normalizedNumber.isEmpty) {
    return '';
  }
  return '$normalizedName|$normalizedSet|$normalizedNumber';
}

String _collectionKeyPart(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _collectionNumberKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

final _collectionExpansionCardsProvider =
    FutureProvider.family<List<PokemonCard>, String>((ref, expansion) {
  return CardService().getCardsByExpansion(expansion);
});

final _collectionExpansionSnapshotProvider =
    FutureProvider.family<MarketplaceExpansionSnapshot?, String>((ref, slug) {
  return CardService().getMarketplaceExpansionSnapshotBySlug(slug);
});

final _collectionArtistSnapshotProvider =
    FutureProvider.family<MarketplaceArtistSnapshot?, String>((ref, slug) {
  return CardService().getMarketplaceArtistSnapshotBySlug(slug);
});

final _marketplaceExpansionsProvider =
    FutureProvider<List<MarketplaceExpansion>>((ref) {
  return CardService().getMarketplaceExpansions();
});

final _marketplaceArtistsProvider =
    FutureProvider<List<MarketplaceArtistSummary>>((ref) {
  return CardService().getMarketplaceArtistSummaries();
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

class _ArtistSummary {
  const _ArtistSummary({
    required this.name,
    required this.slug,
    required this.cardCount,
    required this.ownedCount,
    required this.imageUrl,
  });

  final String name;
  final String slug;
  final int cardCount;
  final int ownedCount;
  final String imageUrl;

  ArtistSuggestion toSuggestion() {
    return ArtistSuggestion(
      name: name,
      normalizedArtist: name.toLowerCase(),
      slug: slug,
      knownCount: cardCount,
      imageUrl: imageUrl,
    );
  }
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

String _artistSummaryTitleFromSlug(String slug) {
  return slug
      .split('-')
      .where((part) => part.isNotEmpty)
      .map((part) => part.length <= 1
          ? part.toUpperCase()
          : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
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
  final parsedNumber = firstNumber == null
      ? 1 << 30
      : int.tryParse(firstNumber.group(0)!) ?? 1 << 30;
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
    required this.nftCount,
    required this.totalCount,
    required this.onBack,
  });

  final int ownedCount;
  final int nftCount;
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
                'Welcome! Here you can keep track of your collection. $ownedCount owned signals, including $nftCount NFTs, across $totalCount catalog cards.',
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

class _CollectionModeActions extends StatelessWidget {
  const _CollectionModeActions({
    required this.showArtistCollections,
    required this.onShowArtists,
  });

  final bool showArtistCollections;
  final VoidCallback onShowArtists;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          selected: !showArtistCollections,
          label: const Text('Expansions'),
          onSelected: showArtistCollections ? (_) => onShowArtists() : null,
        ),
        FilterChip(
          selected: showArtistCollections,
          label: const Text('Artists'),
          avatar: const Icon(Icons.brush_outlined, size: 18),
          onSelected: showArtistCollections ? null : (_) => onShowArtists(),
        ),
      ],
    );
  }
}

class _ArtistCollectionGrid extends StatelessWidget {
  const _ArtistCollectionGrid({
    required this.summaries,
    required this.totalCount,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSuggestedArtistSelected,
    required this.onSelected,
  });

  final List<_ArtistSummary> summaries;
  final int totalCount;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ArtistSuggestion> onSuggestedArtistSelected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty && searchQuery.isEmpty) {
      return const _EmptyCollection(
        message: 'No artist collections are warmed locally yet.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ArtistSearchField(
          controller: searchController,
          resultCount: summaries.length,
          totalCount: totalCount,
          fallbackSuggestions:
              summaries.map((summary) => summary.toSuggestion()).toList(),
          onChanged: onSearchChanged,
          onSelected: onSuggestedArtistSelected,
        ),
        const SizedBox(height: 14),
        if (summaries.isEmpty)
          const _EmptyCollection(
            message: 'No artist collections match this search.',
          )
        else
          LayoutBuilder(
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
                itemCount: summaries.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 164,
                ),
                itemBuilder: (context, index) => _ArtistCollectionCard(
                  summary: summaries[index],
                  onTap: () => onSelected(summaries[index].slug),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ArtistSearchField extends StatelessWidget {
  const _ArtistSearchField({
    required this.controller,
    required this.resultCount,
    required this.totalCount,
    required this.fallbackSuggestions,
    required this.onChanged,
    required this.onSelected,
  });

  final TextEditingController controller;
  final int resultCount;
  final int totalCount;
  final List<ArtistSuggestion> fallbackSuggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<ArtistSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.trim().isNotEmpty;
    return ArtistSuggestionField(
      controller: controller,
      helperText: hasQuery ? '$resultCount of $totalCount artists' : null,
      fillColor: const Color(0xDD0B1020),
      borderRadius: 18,
      fallbackSuggestions: fallbackSuggestions,
      onChanged: onChanged,
      onSelected: onSelected,
    );
  }
}

class _ArtistCollectionCard extends StatelessWidget {
  const _ArtistCollectionCard({required this.summary, required this.onTap});

  final _ArtistSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress =
        summary.cardCount == 0 ? 0.0 : summary.ownedCount / summary.cardCount;
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
        child: Row(
          children: [
            _ArtistThumb(imageUrl: summary.imageUrl),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Owned ${summary.ownedCount}/${summary.cardCount}',
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
          ],
        ),
      ),
    );
  }
}

class _ArtistThumb extends StatelessWidget {
  const _ArtistThumb({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final resolved = imageUrl.trim();
    if (resolved.isEmpty) {
      return const Icon(Icons.brush_outlined, color: Color(0xFFFACC15));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        resolved,
        width: 54,
        height: 72,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.brush_outlined, color: Color(0xFFFACC15)),
      ),
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

class _SelectedCollectionHeader extends StatelessWidget {
  const _SelectedCollectionHeader({
    required this.backLabel,
    required this.name,
    required this.count,
    required this.subtitle,
    required this.onBack,
  });

  final String backLabel;
  final String name;
  final int count;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
          label: Text(backLabel),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name · $count cards',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CollectionGrid extends ConsumerWidget {
  const _CollectionGrid({required this.cards, required this.ownership});

  final List<PokemonCard> cards;
  final CollectionOwnershipIndex ownership;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
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
              owned: ownership.ownsCard(card),
              watchlisted: favorites.isFavorite(card.id),
            );
          },
        );
      },
    );
  }
}

class _CollectionSliverGrid extends ConsumerWidget {
  const _CollectionSliverGrid({required this.cards, required this.ownership});

  final List<PokemonCard> cards;
  final CollectionOwnershipIndex ownership;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
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
            owned: ownership.ownsCard(card),
            watchlisted: favorites.isFavorite(card.id),
          );
        },
        childCount: cards.length,
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.card,
    required this.owned,
    required this.watchlisted,
  });

  final PokemonCard card;
  final bool owned;
  final bool watchlisted;

  @override
  Widget build(BuildContext context) {
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final watchlistGradient = cardDarkSurfaceGradientForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final tile = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: watchlisted ? null : const Color(0xDD0B1020),
        gradient: watchlisted ? watchlistGradient : null,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: owned
              ? const Color(0x66FACC15)
              : watchlisted
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _CollectionCardImage(
              imageUrl: card.imageUrl.isNotEmpty
                  ? card.imageUrl
                  : card.previewImageUrl,
              grayscale: !owned,
            ),
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
                : '${card.set} ${card.number}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: owned
                    ? () => navigateToCanonicalCardDetail(
                          context,
                          card,
                          source: 'collection_sell_button',
                        )
                    : null,
                child: const Text('Sell'),
              ),
              OutlinedButton(
                onPressed:
                    owned ? () => context.go('/nft?card=${card.id}') : null,
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
    );

    return InkWell(
      onTap: () => navigateToCanonicalCardDetail(
        context,
        card,
        source: 'collection_card',
      ),
      borderRadius: BorderRadius.circular(22),
      child: owned
          ? tile
          : watchlisted
              ? Opacity(opacity: 0.72, child: tile)
              : Opacity(
                  opacity: 0.42,
                  child: ColorFiltered(
                    colorFilter: _collectionGrayscaleFilter,
                    child: tile,
                  ),
                ),
    );
  }
}

class _CollectionCardImage extends StatelessWidget {
  const _CollectionCardImage({
    required this.imageUrl,
    required this.grayscale,
  });

  final String imageUrl;
  final bool grayscale;

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
    final image = Image.network(
      resolvedImageUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.style,
        color: Color(0xFFFACC15),
        size: 46,
      ),
    );
    if (!grayscale) {
      return image;
    }
    return ColorFiltered(
      colorFilter: _collectionGrayscaleFilter,
      child: image,
    );
  }
}

const _collectionGrayscaleFilter = ColorFilter.matrix(<double>[
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
]);

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
