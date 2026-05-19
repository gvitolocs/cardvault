import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/recent_views_provider.dart';
import '../services/card_service.dart';
import '../utils/card_url.dart';
import 'home_screen.dart'
    show
        MarketplaceLogoButton,
        MarketplaceTopBar,
        MarketplaceTopSearch,
        ProfileIconButton,
        SearchLanguageMenu,
        WalletBalanceButton;

class CardVersionsScreen extends ConsumerStatefulWidget {
  const CardVersionsScreen({
    super.key,
    required this.cardId,
  });

  final String cardId;

  @override
  ConsumerState<CardVersionsScreen> createState() => _CardVersionsScreenState();
}

class _CardVersionsScreenState extends ConsumerState<CardVersionsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _searchFocused = false;
  late final Future<List<PokemonCard>> _versionsFuture;
  late final Future<List<PokemonCard>> _similarFuture;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _versionsFuture = CardService().getOtherVersionCards(widget.cardId);
    _similarFuture = CardService().getSimilarVersionCards(widget.cardId);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    if (mounted) {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    }
  }

  void _resetHeaderSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(cardProvider.notifier).clearFilters();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardState = ref.watch(cardProvider);
    PokemonCard? currentCard;
    for (final card in cardState.cards) {
      if (card.id == widget.cardId) {
        currentCard = card;
        break;
      }
    }
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final compactSearchExpanded = compactTopBar &&
        (_searchFocused || _searchController.text.trim().isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xF20A1026),
            titleSpacing: 16,
            title: MarketplaceTopBar(
              compactExpanded: compactSearchExpanded,
              logo: MarketplaceLogoButton(
                onTap: () => context.go('/marketplace'),
              ),
              search: MarketplaceTopSearch(
                controller: _searchController,
                focusNode: _searchFocusNode,
                query: cardState.previewQuery,
                isSearching: cardState.isSearchingPreviews,
                previews: cardState.searchPreviews,
                hintText: 'Search cards, sets, products...',
                onChanged: (value) {
                  setState(() {});
                  ref.read(cardProvider.notifier).searchPreviewsOnly(value);
                },
                onSelected: (selection) {
                  final card = selection.card;
                  ref.read(cardProvider.notifier).recordCardInteraction(
                        card,
                        'click',
                        source: 'versions_search_preview',
                      );
                  ref.read(recentViewsProvider.notifier).remember(card);
                  _resetHeaderSearch();
                  context.go(cardDetailPath(card), extra: selection.heroTag);
                },
                onShowAll: (query) => context.go(
                  Uri(
                    path: '/marketplace/search',
                    queryParameters: {
                      'q': query,
                      if (cardState.searchLanguage != 'en')
                        'lang': cardState.searchLanguage,
                    },
                  ).toString(),
                ),
              ),
              languageMenu: SearchLanguageMenu(
                value: cardState.searchLanguage,
                onChanged: (language) =>
                    ref.read(cardProvider.notifier).setSearchLanguage(language),
              ),
            ),
            actions: [
              if (!compactTopBar) ...[
                TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Home')),
                TextButton(
                    onPressed: () => context.go('/forum'),
                    child: const Text('Forum')),
                TextButton(
                    onPressed: () => context.go('/marketplace/signal'),
                    child: const Text('Signal')),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: compactSearchExpanded
                    ? const SizedBox.shrink()
                    : Row(
                        key: const ValueKey('versions-marketplace-actions'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WalletBalanceButton(
                            balance: balance,
                            onTap: () => context.go('/wallet'),
                          ),
                          const SizedBox(width: 8),
                          const ProfileIconButton(),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: FilledButton.icon(
                              onPressed: () => context.go('/cart'),
                              icon: const Icon(Icons.shopping_bag_outlined,
                                  size: 18),
                              label:
                                  Text('${ref.watch(cartProvider).itemCount}'),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<List<List<PokemonCard>>>(
              future: Future.wait([_versionsFuture, _similarFuture]),
              builder: (context, snapshot) {
                final versions = snapshot.data?.first ?? const <PokemonCard>[];
                final similar = snapshot.data == null
                    ? const <PokemonCard>[]
                    : snapshot.data![1];
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 420,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final titleCard = currentCard ??
                    (versions.isNotEmpty ? versions.first : null);
                return _VersionsBody(
                  cardId: widget.cardId,
                  titleCard: titleCard,
                  cards: versions,
                  similarCards: similar,
                );
              },
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
    required this.titleCard,
    required this.cards,
    required this.similarCards,
  });

  final String cardId;
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
                        : () => context.go(cardDetailPath(titleCard!)),
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
                            : width >= 560
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
                        childAspectRatio: columns == 1 ? 1.9 : 0.86,
                      ),
                      itemBuilder: (context, index) => _VersionCard(
                        card: cards[index],
                        isCurrent: cards[index].id == cardId,
                      ),
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
                            : width >= 560
                                ? 2
                                : 1;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: similarCards.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: columns == 1 ? 1.9 : 0.86,
                      ),
                      itemBuilder: (context, index) => _VersionCard(
                        card: similarCards[index],
                        isCurrent: false,
                      ),
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
    required this.isCurrent,
  });

  final PokemonCard card;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: isCurrent
          ? null
          : () {
              ref.read(cardProvider.notifier).recordCardInteraction(
                    card,
                    'click',
                    source: 'card_versions',
                  );
              ref.read(recentViewsProvider.notifier).remember(card);
              context.go(cardDetailPath(card));
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
                child: card.imageUrl.trim().isEmpty
                    ? const Icon(
                        Icons.style,
                        color: Color(0xFFFACC15),
                        size: 54,
                      )
                    : CachedNetworkImage(
                        imageUrl: card.imageUrl,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.style,
                          color: Color(0xFFFACC15),
                          size: 54,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              card.name,
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
              '#${card.number}',
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
