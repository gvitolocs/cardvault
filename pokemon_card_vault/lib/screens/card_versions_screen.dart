import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../services/card_service.dart';
import '../utils/card_navigation.dart';
import '../utils/card_palette.dart';
import '../utils/card_url.dart';
import 'home_screen.dart'
    show
        MarketplaceLogoButton,
        MarketplaceTopBar,
        MarketplaceTopBarSearch,
        SearchLanguageMenu,
        marketplaceSearchPreviewHeroHoldDuration,
        marketplaceTopBarColor,
        marketplaceTopBarHeight,
        marketplaceTopBarActions,
        showMarketplaceEmptyFocusSearchPreviews,
        showMarketplaceSideMenu;

class CardVersionsScreen extends ConsumerStatefulWidget {
  const CardVersionsScreen({
    super.key,
    required this.cardId,
    this.cardSlug,
    this.language = 'en',
  });

  final String cardId;
  final String? cardSlug;
  final String language;

  @override
  ConsumerState<CardVersionsScreen> createState() => _CardVersionsScreenState();
}

class _CardVersionsScreenState extends ConsumerState<CardVersionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final CardService _cardService = CardService();
  bool _searchFocused = false;
  String? _resolvedCardId;
  PokemonCard? _titleCard;
  List<PokemonCard> _versions = const [];
  List<PokemonCard> _similar = const [];
  bool _versionsLoading = true;
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _loadVersions();
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CardVersionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId ||
        oldWidget.cardSlug != widget.cardSlug ||
        oldWidget.language != widget.language) {
      setState(() {
        _resolvedCardId = null;
        _titleCard = null;
        _versions = const [];
        _similar = const [];
        _versionsLoading = true;
      });
      _loadVersions();
    }
  }

  void _handleSearchFocusChanged() {
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    if (!compactTopBar &&
        _searchFocusNode.hasFocus &&
        _searchController.text.trim().isEmpty) {
      showMarketplaceEmptyFocusSearchPreviews(ref);
    }
    if (mounted) {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    }
  }

  Future<void> _loadVersions() async {
    final requestId = ++_loadRequestId;
    final currentCard = await _resolveCurrentCard(
      widget.cardId,
      widget.cardSlug,
    );
    if (!mounted || requestId != _loadRequestId) {
      return;
    }
    final resolvedCurrentCard = currentCard;
    if (resolvedCurrentCard == null) {
      setState(() => _versionsLoading = false);
      return;
    }
    final currentCardId = resolvedCurrentCard.id;
    final versions = await _cardService.getOtherVersionCards(currentCardId);
    if (!mounted || requestId != _loadRequestId) {
      return;
    }
    final cards = _mergeCurrentCard(resolvedCurrentCard, versions);
    setState(() {
      _resolvedCardId = currentCardId;
      _titleCard = currentCard;
      _versions = cards;
      _versionsLoading = cards.isEmpty;
    });
    final similar = await _cardService.getSimilarVersionCards(
      currentCardId,
      versionCards: cards,
    );
    if (!mounted || requestId != _loadRequestId) {
      return;
    }
    setState(() {
      _similar = similar;
      _versionsLoading = false;
    });
  }

  Future<PokemonCard?> _resolveCurrentCard(
    String cardPage,
    String? cardSlug,
  ) async {
    final slug = normalizeCardDetailSlug(cardSlug ?? '');
    if (slug.isNotEmpty) {
      final card = await _cardService.getCardByDetailSlug(slug);
      if (card != null) {
        return card;
      }
    }
    final id = cardIdFromSlug(cardPage);
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      return null;
    }
    return _cardService.getCardById(id);
  }

  List<PokemonCard> _mergeCurrentCard(
    PokemonCard current,
    List<PokemonCard> versions,
  ) {
    final merged = <String, PokemonCard>{current.id: current};
    for (final card in versions) {
      if (card.id.isNotEmpty) {
        merged[card.id] = card;
      }
    }
    return merged.values.toList();
  }

  void _resetHeaderSearch() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    ref.read(cardProvider.notifier).clearSearchPreviews();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardProvider.select((state) => state.cards));
    final currentCardId = _resolvedCardId ?? cardIdFromSlug(widget.cardId);
    PokemonCard? currentCard;
    for (final card in cards) {
      if (card.id == currentCardId) {
        currentCard = card;
        break;
      }
    }
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final cartState = ref.watch(cartProvider);
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final compactSearchExpanded = compactTopBar &&
        (_searchFocused || _searchController.text.trim().isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: marketplaceTopBarColor,
            toolbarHeight: marketplaceTopBarHeight,
            elevation: 0,
            titleSpacing: 16,
            title: MarketplaceTopBar(
              compactExpanded: compactSearchExpanded,
              logo: MarketplaceLogoButton(
                onTap: compactTopBar
                    ? () => showMarketplaceSideMenu(context)
                    : () => context.go('/marketplace'),
              ),
              search: MarketplaceTopBarSearch(
                controller: _searchController,
                focusNode: _searchFocusNode,
                compactTopBar: compactTopBar,
                onSearchFocusedChanged: (hasFocus) {
                  if (mounted) {
                    setState(() => _searchFocused = hasFocus);
                  }
                },
                onSelected: (selection) {
                  final card = selection.card;
                  ref.read(cardProvider.notifier).recordCardInteraction(
                        card,
                        'click',
                        source: 'versions_search_preview',
                      );
                  navigateToCanonicalCardDetail(
                    context,
                    card,
                    language: widget.language,
                    source: 'versions_search_preview',
                    extra: selection.heroTag,
                  );
                  Future<void>.delayed(marketplaceSearchPreviewHeroHoldDuration,
                      () {
                    if (mounted) {
                      _resetHeaderSearch();
                    }
                  });
                },
              ),
              languageMenu: Consumer(
                builder: (context, ref, _) {
                  final searchLanguage = ref.watch(
                    cardProvider.select((state) => state.searchLanguage),
                  );
                  return SearchLanguageMenu(
                    value: searchLanguage,
                    onChanged: (language) => ref
                        .read(cardProvider.notifier)
                        .setSearchLanguage(language),
                  );
                },
              ),
              actions: marketplaceTopBarActions(
                context: context,
                balance: balance,
                itemCount: cartState.itemCount,
                compactTopBar: compactTopBar,
                compactSearchExpanded: compactSearchExpanded,
                keyValue: 'versions-marketplace-actions',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _versionsLoading && _versions.isEmpty
                ? const SizedBox(
                    height: 420,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _VersionsBody(
                    cardId: currentCardId,
                    language: widget.language,
                    titleCard: currentCard ??
                        _titleCard ??
                        (_versions.isNotEmpty ? _versions.first : null),
                    cards: _versions,
                    similarCards: _similar,
                  ),
          ),
        ],
      ),
    );
  }
}

class _VersionsBody extends StatelessWidget {
  const _VersionsBody({
    required this.cardId,
    required this.language,
    required this.titleCard,
    required this.cards,
    required this.similarCards,
  });

  final String cardId;
  final String language;
  final PokemonCard? titleCard;
  final List<PokemonCard> cards;
  final List<PokemonCard> similarCards;

  @override
  Widget build(BuildContext context) {
    final title = titleCard?.name ?? 'Other versions';
    final subtitle = titleCard == null
        ? 'Same-name cards in the same expansion'
        : '${titleCard!.set} · ${cards.length} version${cards.length == 1 ? '' : 's'}';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: titleCard == null
                        ? () => context.go('/marketplace')
                        : () => navigateToCanonicalCardDetail(
                              context,
                              titleCard!,
                              language: language,
                              source: 'card_versions_title',
                            ),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(
                        titleCard == null ? 'Back to market' : 'Back to card'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFFB8C4E6),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (cards.length <= 1) ...[
                const SizedBox(height: 14),
                const Text(
                  'No alternate versions found in this expansion yet.',
                  style: TextStyle(color: Color(0xFF93A4C8)),
                ),
              ],
              const SizedBox(height: 22),
              if (cards.isEmpty)
                const _EmptyVersionsCard()
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final columns = width >= 1100
                        ? 4
                        : width >= 820
                            ? 3
                            : 2;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cards.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: columns == 2 && width < 560
                            ? 0.72
                            : columns == 1
                                ? 1.9
                                : 0.86,
                      ),
                      itemBuilder: (context, index) {
                        final card = cards[index];
                        return _VersionCard(
                          card: card,
                          heroTag: _versionHeroTag(card, 'versions', index),
                          language: language,
                          isCurrent: card.id == cardId,
                        );
                      },
                    );
                  },
                ),
              if (similarCards.isNotEmpty) ...[
                const SizedBox(height: 30),
                const Text(
                  'Similar results',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final columns = width >= 1100
                        ? 4
                        : width >= 820
                            ? 3
                            : 2;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: similarCards.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: columns == 2 && width < 560
                            ? 0.72
                            : columns == 1
                                ? 1.9
                                : 0.86,
                      ),
                      itemBuilder: (context, index) {
                        final card = similarCards[index];
                        return _VersionCard(
                          card: card,
                          heroTag: _versionHeroTag(card, 'similar', index),
                          language: language,
                          isCurrent: false,
                        );
                      },
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyVersionsCard extends StatelessWidget {
  const _EmptyVersionsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Text(
        'This card could not be loaded yet. Try opening it from the card detail page.',
        style: TextStyle(color: Color(0xFFB8C4E6)),
      ),
    );
  }
}

class _VersionCard extends ConsumerWidget {
  const _VersionCard({
    required this.card,
    required this.heroTag,
    required this.language,
    required this.isCurrent,
  });

  final PokemonCard card;
  final String heroTag;
  final String language;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayNumber = _versionDisplayNumber(card.number);
    final expansionName = card.set.trim();
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final frameColor = cardImageFrameColorForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    return InkWell(
      onTap: () {
        ref.read(cardProvider.notifier).recordCardInteraction(
              card,
              'click',
              source: isCurrent ? 'card_versions_current' : 'card_versions',
            );
        navigateToCanonicalCardDetail(
          context,
          card,
          language: language,
          source: isCurrent ? 'card_versions_current' : 'card_versions',
          extra: heroTag,
        );
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1024),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isCurrent
                ? const Color(0xFFFACC15)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: Hero(
                  tag: heroTag,
                  flightShuttleBuilder: (
                    _,
                    animation,
                    __,
                    ___,
                    toHeroContext,
                  ) {
                    return ScaleTransition(
                      scale: Tween<double>(begin: 0.985, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: toHeroContext.widget,
                      ),
                    );
                  },
                  child: AspectRatio(
                    aspectRatio: 0.72,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: frameColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.none,
                      child: card.imageUrl.trim().isEmpty
                          ? const Icon(
                              Icons.style,
                              color: Color(0xFFFACC15),
                              size: 54,
                            )
                          : CachedNetworkImage(
                              imageUrl: card.imageUrl,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.style,
                                color: Color(0xFFFACC15),
                                size: 54,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              displayNumber.isEmpty ? card.name : '${card.name} $displayNumber',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              expansionName.isEmpty ? 'Expansion unknown' : expansionName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB8C4E6),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(height: 8),
              const Text(
                'Current card',
                style: TextStyle(
                  color: Color(0xFFFACC15),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _versionHeroTag(PokemonCard card, String section, int index) {
  return 'market-card-image-${card.id}-versions-$section-$index';
}

String _versionDisplayNumber(String rawNumber) {
  final text = rawNumber.trim();
  if (text.isEmpty) {
    return '';
  }
  final parts = text
      .split(RegExp(r'\s*(?:\||•|-{2,}|–|—)\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  for (final part in parts.reversed) {
    if (RegExp(r'\d+\s*/\s*\d+').hasMatch(part)) {
      return part.replaceAll(RegExp(r'\s+'), '');
    }
  }
  for (final part in parts.reversed) {
    if (RegExp(r'\d').hasMatch(part)) {
      return part;
    }
  }
  return text;
}
