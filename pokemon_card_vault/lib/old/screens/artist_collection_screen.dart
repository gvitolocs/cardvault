import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../services/card_service.dart';
import '../utils/card_navigation.dart';
import '../utils/card_palette.dart';
import '../utils/card_url.dart';
import '../utils/twitter_handle_links.dart';
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

const int _artistCardsBatchSize = 40;
const int _artistCardsPreloadRows = 5;
const double _artistCardsFallbackPreloadExtent = 1600;

enum ArtistCardFilter { all, illustrations, fullArts, normalCards }

extension ArtistCardFilterMatch on ArtistCardFilter {
  bool matches(PokemonCard card) {
    return switch (this) {
      ArtistCardFilter.all => true,
      ArtistCardFilter.illustrations => _isIllustrationCard(card),
      ArtistCardFilter.fullArts => _isFullArtCard(card),
      ArtistCardFilter.normalCards => _isNormalCard(card),
    };
  }

  String get pathSegment {
    return switch (this) {
      ArtistCardFilter.all => '',
      ArtistCardFilter.illustrations => 'illustration',
      ArtistCardFilter.fullArts => 'full-arts',
      ArtistCardFilter.normalCards => 'normal-cards',
    };
  }

  String get emptyMessage {
    return switch (this) {
      ArtistCardFilter.all => 'No cards were found for this artist yet.',
      ArtistCardFilter.illustrations =>
        'No illustration cards were found for this artist yet.',
      ArtistCardFilter.fullArts =>
        'No full-art cards were found for this artist yet.',
      ArtistCardFilter.normalCards =>
        'No normal cards were found for this artist yet.',
    };
  }
}

enum ArtistPageView { collection, profile }

class ArtistProfileRouteExtra {
  const ArtistProfileRouteExtra({
    required this.snapshot,
    required this.heroSourceSlug,
  });

  final MarketplaceArtistSnapshot snapshot;
  final String heroSourceSlug;
}

class ArtistCollectionScreen extends ConsumerStatefulWidget {
  const ArtistCollectionScreen({
    super.key,
    required this.artistSlug,
    this.language = 'en',
    ArtistCardFilter? initialFilter,
    bool initialIllustrationsOnly = false,
    this.initialView = ArtistPageView.collection,
    this.initialSnapshot,
    this.heroSourceSlug,
  }) : initialFilter = initialFilter ??
            (initialIllustrationsOnly
                ? ArtistCardFilter.illustrations
                : ArtistCardFilter.all);

  final String artistSlug;
  final String language;
  final ArtistCardFilter initialFilter;
  final ArtistPageView initialView;
  final MarketplaceArtistSnapshot? initialSnapshot;
  final String? heroSourceSlug;

  @override
  ConsumerState<ArtistCollectionScreen> createState() =>
      _ArtistCollectionScreenState();
}

class _ArtistCollectionScreenState
    extends ConsumerState<ArtistCollectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final CardService _cardService = CardService();
  MarketplaceArtistSnapshot? _snapshot;
  bool _loading = true;
  bool _searchFocused = false;
  int _visibleCardLimit = _artistCardsBatchSize;
  double _artistCardsPreloadExtent = _artistCardsFallbackPreloadExtent;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    _loading = widget.initialSnapshot == null;
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _scrollController.addListener(_handleArtistScroll);
    _loadArtist();
  }

  @override
  void didUpdateWidget(covariant ArtistCollectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistSlug != widget.artistSlug) {
      _snapshot = widget.initialSnapshot;
      _visibleCardLimit = _artistCardsBatchSize;
      _loadArtist();
    } else if (oldWidget.initialSnapshot != widget.initialSnapshot &&
        widget.initialSnapshot != null) {
      _snapshot = widget.initialSnapshot;
    }
    if (oldWidget.initialFilter != widget.initialFilter ||
        oldWidget.initialView != widget.initialView) {
      _visibleCardLimit = _artistCardsBatchSize;
      _scheduleArtistScrollCheck();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleArtistScroll);
    _scrollController.dispose();
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
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

  Future<void> _loadArtist() async {
    setState(() => _loading = _snapshot == null);
    final snapshot = await _cardService
        .getMarketplaceArtistSnapshotBySlug(widget.artistSlug);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
    _scheduleArtistScrollCheck();
  }

  int get _currentVisibleArtistCardCount {
    final cards = _snapshot?.cards ?? const <PokemonCard>[];
    return cards.where(widget.initialFilter.matches).length;
  }

  void _handleArtistScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final totalCards = _currentVisibleArtistCardCount;
    if (_visibleCardLimit >= totalCards) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions) {
      return;
    }
    final remainingExtent = position.maxScrollExtent - position.pixels;
    if (remainingExtent <= _artistCardsPreloadExtent) {
      _showNextCardBatch(totalCards);
    }
  }

  void _showNextCardBatch(int totalCards) {
    if (_visibleCardLimit >= totalCards) {
      return;
    }
    setState(() {
      _visibleCardLimit = math.min(
        totalCards,
        _visibleCardLimit + _artistCardsBatchSize,
      );
    });
    _scheduleArtistScrollCheck();
  }

  void _scheduleArtistScrollCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleArtistScroll();
      }
    });
  }

  void _handleGridPreloadExtentChanged(double preloadExtent) {
    if (!preloadExtent.isFinite || preloadExtent <= 0) {
      return;
    }
    _artistCardsPreloadExtent = preloadExtent;
    _scheduleArtistScrollCheck();
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
        controller: _scrollController,
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
                        source: 'artist_search_preview',
                      );
                  navigateToCanonicalCardDetail(
                    context,
                    card,
                    language: widget.language,
                    source: 'artist_search_preview',
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
                keyValue: 'artist-marketplace-actions',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _ArtistBody(
              snapshot: _snapshot,
              artistSlug: widget.artistSlug,
              language: widget.language,
              loading: _loading,
              cardFilter: widget.initialFilter,
              view: widget.initialView,
              heroSourceSlug: widget.heroSourceSlug,
              visibleCardLimit: _visibleCardLimit,
              onPreloadExtentChanged: _handleGridPreloadExtentChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistBody extends StatelessWidget {
  const _ArtistBody({
    required this.snapshot,
    required this.artistSlug,
    required this.language,
    required this.loading,
    required this.cardFilter,
    required this.view,
    required this.visibleCardLimit,
    required this.onPreloadExtentChanged,
    this.heroSourceSlug,
  });

  final MarketplaceArtistSnapshot? snapshot;
  final String artistSlug;
  final String language;
  final bool loading;
  final ArtistCardFilter cardFilter;
  final ArtistPageView view;
  final int visibleCardLimit;
  final ValueChanged<double> onPreloadExtentChanged;
  final String? heroSourceSlug;

  @override
  Widget build(BuildContext context) {
    if (loading && snapshot == null) {
      return _ArtistLoadingBody(
        artistName: _titleFromSlug(artistSlug),
        isProfileView: view == ArtistPageView.profile,
      );
    }
    final cards = snapshot?.cards ?? const <PokemonCard>[];
    final visibleCards =
        cards.where(cardFilter.matches).toList(growable: false);
    final renderedCards =
        visibleCards.take(visibleCardLimit).toList(growable: false);
    final artistName = snapshot?.name ?? _titleFromSlug(artistSlug);
    final profile = snapshot?.profile ?? const MarketplaceArtistProfile();
    final displayName =
        profile.displayName.isEmpty ? artistName : profile.displayName;
    final isProfileView = view == ArtistPageView.profile;
    final profilePath = _artistProfilePath(
      language: language,
      artistSlug: artistSlug,
    );
    final resolvedHeroSlug = heroSourceSlug?.trim().isNotEmpty == true
        ? heroSourceSlug!.trim()
        : snapshot?.slug.trim().isNotEmpty == true
            ? snapshot!.slug
            : artistSlug;
    final profileHeroTag = _artistProfileHeroTag(resolvedHeroSlug);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.go('/marketplace'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to market'),
                  ),
                  OutlinedButton.icon(
                    onPressed: cards.isEmpty
                        ? null
                        : () => context.go(collectionArtistPath(artistName)),
                    icon: const Icon(Icons.collections_bookmark_outlined),
                    label: const Text('Collection view'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go(profilePath),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Profile'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 680;
                  final titleBlock = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artistName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _artistFilterCountText(
                          filter: cardFilter,
                          totalCount: snapshot?.cardCount ?? cards.length,
                          visibleCount: visibleCards.length,
                        ),
                        style: const TextStyle(
                          color: Color(0xFFB8C4E6),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilterChip(
                            selected: cardFilter == ArtistCardFilter.all &&
                                !isProfileView,
                            avatar: const Icon(
                              Icons.grid_view_rounded,
                              size: 18,
                            ),
                            label: const Text('Cards'),
                            onSelected: (_) => context.go(
                              _artistCollectionFilterPath(
                                language: language,
                                artistSlug: artistSlug,
                                filter: ArtistCardFilter.all,
                              ),
                            ),
                          ),
                          FilterChip(
                            selected:
                                cardFilter == ArtistCardFilter.illustrations,
                            avatar:
                                const Icon(Icons.palette_outlined, size: 18),
                            label: const Text('Illustrations'),
                            onSelected: cards.isEmpty
                                ? null
                                : (value) => context.go(
                                      _artistCollectionFilterPath(
                                        language: language,
                                        artistSlug: artistSlug,
                                        filter: value
                                            ? ArtistCardFilter.illustrations
                                            : ArtistCardFilter.all,
                                      ),
                                    ),
                          ),
                          FilterChip(
                            selected: cardFilter == ArtistCardFilter.fullArts,
                            avatar: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Full arts'),
                            onSelected: cards.isEmpty
                                ? null
                                : (value) => context.go(
                                      _artistCollectionFilterPath(
                                        language: language,
                                        artistSlug: artistSlug,
                                        filter: value
                                            ? ArtistCardFilter.fullArts
                                            : ArtistCardFilter.all,
                                      ),
                                    ),
                          ),
                          FilterChip(
                            selected:
                                cardFilter == ArtistCardFilter.normalCards,
                            avatar: const Icon(Icons.style_outlined, size: 18),
                            label: const Text('Normal cards'),
                            onSelected: cards.isEmpty
                                ? null
                                : (value) => context.go(
                                      _artistCollectionFilterPath(
                                        language: language,
                                        artistSlug: artistSlug,
                                        filter: value
                                            ? ArtistCardFilter.normalCards
                                            : ArtistCardFilter.all,
                                      ),
                                    ),
                          ),
                          FilterChip(
                            selected: isProfileView,
                            avatar: const Icon(Icons.person_outline, size: 18),
                            label: const Text('Profile'),
                            onSelected: (_) => context.go(profilePath),
                          ),
                        ],
                      ),
                    ],
                  );
                  final avatar = _ArtistHeaderAvatar(
                    imageUrl: profile.imageUrl.trim(),
                    name: displayName,
                    heroTag: profileHeroTag,
                    onTap: () {
                      if (isProfileView) {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                          return;
                        }
                        context.go(
                          _artistCollectionFilterPath(
                            language: language,
                            artistSlug: artistSlug,
                            filter: ArtistCardFilter.all,
                          ),
                        );
                      } else {
                        final snapshot = this.snapshot;
                        context.push(
                          profilePath,
                          extra: snapshot == null
                              ? null
                              : ArtistProfileRouteExtra(
                                  snapshot: snapshot,
                                  heroSourceSlug: resolvedHeroSlug,
                                ),
                        );
                      }
                    },
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: avatar,
                        ),
                        const SizedBox(height: 16),
                        titleBlock,
                      ],
                    );
                  }
                  if (isProfileView) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatar,
                        const SizedBox(width: 24),
                        Expanded(child: titleBlock),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleBlock),
                      const SizedBox(width: 24),
                      avatar,
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              if (isProfileView)
                _ArtistProfilePanel(
                  artistName: artistName,
                  artistSlug: artistSlug,
                  language: language,
                  cardCount: snapshot?.cardCount ?? cards.length,
                  illustrationCount: cards.where(_isIllustrationCard).length,
                  profile: profile,
                  profileHeroTag: profileHeroTag,
                  cards: cards,
                  showPortrait: false,
                )
              else if (visibleCards.isEmpty)
                _EmptyArtistCard(
                  message: cardFilter.emptyMessage,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final columns = width >= 1100
                        ? 4
                        : width >= 820
                            ? 3
                            : 2;
                    final childAspectRatio =
                        columns == 2 && width < 560 ? 0.72 : 0.86;
                    final tileWidth = (width - (columns - 1) * 14) / columns;
                    final rowExtent = tileWidth / childAspectRatio + 14;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      onPreloadExtentChanged(
                        rowExtent * _artistCardsPreloadRows,
                      );
                    });
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: renderedCards.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: childAspectRatio,
                          ),
                          itemBuilder: (context, index) {
                            final card = renderedCards[index];
                            return _ArtistCard(
                              card: card,
                              heroTag: _artistHeroTag(card, index),
                              language: language,
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleFromSlug(String slug) {
    final normalizedSlug = slug
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalizedSlug == '2017-pikachu-project' ||
        normalizedSlug == 'pikachu-project-2017' ||
        normalizedSlug == 'pikachu-project') {
      return 'Pikachu Project';
    }
    return slug
        .split('-')
        .where((part) => part.isNotEmpty)
        .map((part) => part.length <= 1
            ? part.toUpperCase()
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _ArtistLoadingBody extends StatelessWidget {
  const _ArtistLoadingBody({
    required this.artistName,
    required this.isProfileView,
  });

  final String artistName;
  final bool isProfileView;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ArtistSkeletonChip(width: 150),
                  _ArtistSkeletonChip(width: 165),
                  _ArtistSkeletonChip(width: 108),
                ],
              ),
              const SizedBox(height: 18),
              _ArtistSkeletonBlock(
                width: math.min(
                  math.max(MediaQuery.sizeOf(context).width - 44, 0),
                  artistName.length <= 14 ? 280 : 360,
                ),
                height: 40,
                radius: 12,
              ),
              const SizedBox(height: 8),
              const _ArtistSkeletonBlock(width: 210, height: 18, radius: 9),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  const _ArtistSkeletonChip(width: 92),
                  const _ArtistSkeletonChip(width: 136),
                  _ArtistSkeletonChip(
                    width: 98,
                    highlighted: isProfileView,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              isProfileView
                  ? const _ArtistProfileLoadingPanel()
                  : const _ArtistGridLoadingPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistProfileLoadingPanel extends StatelessWidget {
  const _ArtistProfileLoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          const portrait = _ArtistProfilePortraitSkeleton();
          const story = _ArtistProfileStorySkeleton();
          if (compact) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ArtistProfilePortraitSkeleton(),
                SizedBox(height: 18),
                _ArtistProfileStorySkeleton(),
              ],
            );
          }
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 280, child: portrait),
              SizedBox(width: 24),
              Expanded(child: story),
            ],
          );
        },
      ),
    );
  }
}

class _ArtistProfilePortraitSkeleton extends StatelessWidget {
  const _ArtistProfilePortraitSkeleton();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Center(
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFFACC15).withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFACC15).withValues(alpha: 0.20),
                ),
              ),
              child: const Icon(
                Icons.person_outline,
                color: Color(0xFFFACC15),
                size: 38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistProfileStorySkeleton extends StatelessWidget {
  const _ArtistProfileStorySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ArtistSkeletonBlock(width: 260, height: 34, radius: 12),
        SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ArtistSkeletonChip(width: 88, highlighted: true),
            _ArtistSkeletonChip(width: 136, highlighted: true),
          ],
        ),
        SizedBox(height: 22),
        _ArtistSkeletonBlock(width: double.infinity, height: 18, radius: 9),
        SizedBox(height: 10),
        _ArtistSkeletonBlock(width: double.infinity, height: 18, radius: 9),
        SizedBox(height: 10),
        _ArtistSkeletonBlock(width: 420, height: 18, radius: 9),
        SizedBox(height: 20),
        _ArtistSkeletonBlock(width: double.infinity, height: 14, radius: 7),
        SizedBox(height: 9),
        _ArtistSkeletonBlock(width: double.infinity, height: 14, radius: 7),
        SizedBox(height: 9),
        _ArtistSkeletonBlock(width: 360, height: 14, radius: 7),
        SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ArtistSkeletonChip(width: 144),
            _ArtistSkeletonChip(width: 118),
            _ArtistSkeletonChip(width: 156),
          ],
        ),
      ],
    );
  }
}

class _ArtistGridLoadingPanel extends StatelessWidget {
  const _ArtistGridLoadingPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
          itemCount: columns * 2,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: columns == 2 && width < 560 ? 0.72 : 0.86,
          ),
          itemBuilder: (context, index) => const _ArtistCardSkeleton(),
        );
      },
    );
  }
}

class _ArtistCardSkeleton extends StatelessWidget {
  const _ArtistCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111936), Color(0xFF0B1024)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ArtistSkeletonBlock(
              width: double.infinity,
              height: double.infinity,
              radius: 18,
            ),
          ),
          SizedBox(height: 12),
          _ArtistSkeletonBlock(width: double.infinity, height: 18, radius: 9),
          SizedBox(height: 8),
          _ArtistSkeletonBlock(width: 128, height: 14, radius: 7),
        ],
      ),
    );
  }
}

class _ArtistSkeletonChip extends StatelessWidget {
  const _ArtistSkeletonChip({
    required this.width,
    this.highlighted = false,
  });

  final double width;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return _ArtistSkeletonBlock(
      width: width,
      height: 36,
      radius: 999,
      color:
          highlighted ? const Color(0xFFFACC15).withValues(alpha: 0.14) : null,
      borderColor:
          highlighted ? const Color(0xFFFACC15).withValues(alpha: 0.28) : null,
    );
  }
}

class _ArtistSkeletonBlock extends StatelessWidget {
  const _ArtistSkeletonBlock({
    required this.width,
    required this.height,
    required this.radius,
    this.color,
    this.borderColor,
  });

  final double width;
  final double height;
  final double radius;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      constraints: const BoxConstraints(minWidth: 0),
      decoration: BoxDecoration(
        color: color ?? Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.05),
        ),
      ),
    );
  }
}

class _EmptyArtistCard extends StatelessWidget {
  const _EmptyArtistCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFB8C4E6)),
      ),
    );
  }
}

class _ArtistHeaderAvatar extends StatefulWidget {
  const _ArtistHeaderAvatar({
    required this.imageUrl,
    required this.name,
    required this.heroTag,
    required this.onTap,
  });

  final String imageUrl;
  final String name;
  final String heroTag;
  final VoidCallback? onTap;

  @override
  State<_ArtistHeaderAvatar> createState() => _ArtistHeaderAvatarState();
}

class _ArtistHeaderAvatarState extends State<_ArtistHeaderAvatar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final portrait = SizedBox(
      width: 174,
      child: AspectRatio(
        aspectRatio: 1,
        child: _ArtistProfileImage(
          imageUrl: widget.imageUrl,
          name: widget.name,
          borderRadius: 26,
          initialsFontSize: 42,
        ),
      ),
    );
    final avatar = Hero(
      tag: widget.heroTag,
      flightShuttleBuilder: _artistProfileFlightShuttleBuilder,
      child: portrait,
    );
    return Semantics(
      button: enabled,
      label: 'Open ${widget.name} profile',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(28),
          hoverColor: Colors.transparent,
          splashColor: Colors.white.withValues(alpha: 0.05),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: _ArtistAvatarHoverFrame(
            hovered: enabled && _hovered,
            borderRadius: 28,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: avatar,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFACC15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF050816),
                        width: 3,
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.person_outline,
                        color: Color(0xFF111827),
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistAvatarHoverFrame extends StatelessWidget {
  const _ArtistAvatarHoverFrame({
    required this.hovered,
    required this.borderRadius,
    required this.child,
  });

  final bool hovered;
  final double borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sigma = hovered ? 1.2 : 0.0;
    return AnimatedScale(
      scale: hovered ? 1.01 : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: hovered
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.0),
          ),
          color: hovered
              ? Colors.white.withValues(alpha: 0.035)
              : Colors.transparent,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            children: [
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: child,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: hovered ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.12),
                            const Color(0xFF38BDF8).withValues(alpha: 0.06),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _artistCollectionFilterPath({
  required String language,
  required String artistSlug,
  required ArtistCardFilter filter,
}) {
  final cleanLanguage = language.trim().isEmpty ? 'en' : language.trim();
  final cleanSlug = artistSlug.trim();
  final basePath = '/marketplace/$cleanLanguage/artists/$cleanSlug';
  final segment = filter.pathSegment;
  return segment.isEmpty ? basePath : '$basePath/$segment';
}

String _artistProfilePath({
  required String language,
  required String artistSlug,
}) {
  final cleanLanguage = language.trim().isEmpty ? 'en' : language.trim();
  final cleanSlug = artistSlug.trim();
  return '/marketplace/$cleanLanguage/artists/$cleanSlug/profile';
}

bool _isIllustrationCard(PokemonCard card) {
  return _artistCardFilterHaystack(card).contains('illustration');
}

bool _isFullArtCard(PokemonCard card) {
  final haystack = _artistCardFilterHaystack(card);
  return haystack.contains('full art') ||
      haystack.contains('fullart') ||
      haystack.contains('special illustration rare') ||
      haystack.contains('special art rare') ||
      haystack.contains('illustration rare') ||
      haystack.contains('art rare') ||
      haystack.contains('alternate art') ||
      haystack.contains('alt art') ||
      haystack.contains('ultra rare');
}

bool _isNormalCard(PokemonCard card) {
  return !_isFullArtCard(card);
}

String _artistCardFilterHaystack(PokemonCard card) {
  return [
    card.rarity,
    card.name,
    card.type,
    card.number,
    card.productType,
    card.itemKind,
    card.trainerName,
    ...card.tags,
  ].join(' ').toLowerCase().replaceAll(RegExp(r'[-_]+'), ' ');
}

Map<String, dynamic> _generatedProfileImageSourceCard(
  Map<String, dynamic> generatedProfileImage,
) {
  final sourceCard = generatedProfileImage['sourceCard'];
  if (sourceCard is Map) {
    return Map<String, dynamic>.from(sourceCard);
  }
  return const <String, dynamic>{};
}

String _artistFilterCountText({
  required ArtistCardFilter filter,
  required int totalCount,
  required int visibleCount,
}) {
  return switch (filter) {
    ArtistCardFilter.all =>
      '$totalCount artist card${totalCount == 1 ? '' : 's'}',
    ArtistCardFilter.illustrations =>
      '$visibleCount illustration card${visibleCount == 1 ? '' : 's'}',
    ArtistCardFilter.fullArts =>
      '$visibleCount full-art card${visibleCount == 1 ? '' : 's'}',
    ArtistCardFilter.normalCards =>
      '$visibleCount normal card${visibleCount == 1 ? '' : 's'}',
  };
}

String _artistProfileComparableText(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

class _ArtistProfilePanel extends StatelessWidget {
  const _ArtistProfilePanel({
    required this.artistName,
    required this.artistSlug,
    required this.language,
    required this.cardCount,
    required this.illustrationCount,
    required this.profile,
    required this.profileHeroTag,
    required this.cards,
    required this.showPortrait,
  });

  final String artistName;
  final String artistSlug;
  final String language;
  final int cardCount;
  final int illustrationCount;
  final MarketplaceArtistProfile profile;
  final String profileHeroTag;
  final List<PokemonCard> cards;
  final bool showPortrait;

  @override
  Widget build(BuildContext context) {
    final displayName =
        profile.displayName.isEmpty ? artistName : profile.displayName;
    final imageUrl = profile.imageUrl.trim();
    final sourceLabel = profile.hasGeneratedProfileImage
        ? 'Avatar generated from card art'
        : profile.sourceName.isEmpty
            ? 'Trusted source pending'
            : 'Source: ${profile.sourceName}';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final portrait = _ArtistProfilePortrait(
            imageUrl: imageUrl,
            name: displayName,
            heroTag: profileHeroTag,
          );
          final story = _ArtistProfileStory(
            artistName: displayName,
            artistSlug: artistSlug,
            language: language,
            cardCount: cardCount,
            illustrationCount: illustrationCount,
            profile: profile,
            sourceLabel: sourceLabel,
            sampleCards: cards.take(3).toList(growable: false),
          );
          if (!showPortrait) {
            return story;
          }
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                portrait,
                const SizedBox(height: 18),
                story,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 280, child: portrait),
              const SizedBox(width: 24),
              Expanded(child: story),
            ],
          );
        },
      ),
    );
  }
}

class _ArtistProfilePortrait extends StatefulWidget {
  const _ArtistProfilePortrait({
    required this.imageUrl,
    required this.name,
    required this.heroTag,
  });

  final String imageUrl;
  final String name;
  final String heroTag;

  @override
  State<_ArtistProfilePortrait> createState() => _ArtistProfilePortraitState();
}

class _ArtistProfilePortraitState extends State<_ArtistProfilePortrait> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _ArtistAvatarHoverFrame(
        hovered: _hovered,
        borderRadius: 26,
        child: AspectRatio(
          aspectRatio: 1,
          child: Hero(
            tag: widget.heroTag,
            flightShuttleBuilder: _artistProfileFlightShuttleBuilder,
            child: _ArtistProfileImage(
              imageUrl: widget.imageUrl,
              name: widget.name,
              borderRadius: 24,
              initialsFontSize: 54,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistProfileImage extends StatelessWidget {
  const _ArtistProfileImage({
    required this.imageUrl,
    required this.name,
    required this.borderRadius,
    required this.initialsFontSize,
  });

  final String imageUrl;
  final String name;
  final double borderRadius;
  final double initialsFontSize;

  @override
  Widget build(BuildContext context) {
    final initials = _artistInitials(name);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111936),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: imageUrl.isEmpty
            ? _ArtistInitials(initials: initials, fontSize: initialsFontSize)
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _ArtistInitials(
                  initials: initials,
                  fontSize: initialsFontSize,
                ),
              ),
      ),
    );
  }
}

class _ArtistInitials extends StatelessWidget {
  const _ArtistInitials({
    required this.initials,
    required this.fontSize,
  });

  final String initials;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: const Color(0xFFFACC15),
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ArtistProfileStory extends StatelessWidget {
  const _ArtistProfileStory({
    required this.artistName,
    required this.artistSlug,
    required this.language,
    required this.cardCount,
    required this.illustrationCount,
    required this.profile,
    required this.sourceLabel,
    required this.sampleCards,
  });

  final String artistName;
  final String artistSlug;
  final String language;
  final int cardCount;
  final int illustrationCount;
  final MarketplaceArtistProfile profile;
  final String sourceLabel;
  final List<PokemonCard> sampleCards;

  @override
  Widget build(BuildContext context) {
    final summaryText = profile.summary.trim();
    final bioText = profile.bio.trim();
    final hasSummary = summaryText.isNotEmpty;
    final hasDistinctBio = bioText.isNotEmpty &&
        _artistProfileComparableText(bioText) !=
            _artistProfileComparableText(summaryText);
    final overviewText = hasDistinctBio
        ? bioText
        : 'This artist profile is being curated from trusted public sources. The collection is already live, and a sourced story will appear here once it has been verified.';
    final hasExternalSources = profile.pocketmonstersUrl.isNotEmpty ||
        profile.bulbapediaUrl.isNotEmpty ||
        profile.sourceUrl.isNotEmpty;
    final generatedSourceCard =
        _generatedProfileImageSourceCard(profile.generatedProfileImage);
    final generatedSourceName = '${generatedSourceCard['name'] ?? ''}'.trim();
    final generatedSourceRarity =
        '${generatedSourceCard['rarity'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          artistName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        _ArtistInfoPanel(
          title: 'Artist profile',
          icon: Icons.auto_stories_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasSummary) ...[
                Text(
                  summaryText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!hasSummary || hasDistinctBio)
                _ArtistProfileBioText(
                  text: overviewText,
                  style: const TextStyle(
                    color: Color(0xFFB8C4E6),
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.go(
                  _artistCollectionFilterPath(
                    language: language,
                    artistSlug: artistSlug,
                    filter: ArtistCardFilter.all,
                  ),
                ),
                icon: const Icon(Icons.collections_bookmark_outlined),
                label: const Text('View collection'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final statsPanel = _ArtistInfoPanel(
              title: 'Collection stats',
              icon: Icons.query_stats_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ArtistProfilePill(label: '$cardCount cards'),
                      _ArtistProfilePill(
                        label: '$illustrationCount illustrations',
                      ),
                    ],
                  ),
                  if (sampleCards.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Featured cards',
                      style: TextStyle(
                        color: Color(0xFF93A4C8),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final card in sampleCards)
                          _ArtistProfilePill(label: card.name),
                      ],
                    ),
                  ],
                ],
              ),
            );
            final sourcesPanel = _ArtistInfoPanel(
              title: 'Sources',
              icon: Icons.travel_explore_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.hasGeneratedProfileImage
                        ? 'The portrait is a square top-center crop from one illustrated card by this artist.'
                        : hasExternalSources
                            ? 'Reference links and attribution for this profile.'
                            : 'Trusted references are being reviewed for this artist.',
                    style: const TextStyle(
                      color: Color(0xFFB8C4E6),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (profile.pocketmonstersUrl.isNotEmpty)
                        _ArtistSourceButton(
                          label: 'PocketMonsters.Net profile',
                          url: profile.pocketmonstersUrl,
                        ),
                      if (profile.bulbapediaUrl.isNotEmpty)
                        _ArtistSourceButton(
                          label: 'Bulbapedia reference',
                          url: profile.bulbapediaUrl,
                        ),
                    ],
                  ),
                  if (profile.hasGeneratedProfileImage) ...[
                    const SizedBox(height: 10),
                    Text(
                      generatedSourceName.isEmpty
                          ? 'Avatar generated from card art.'
                          : [
                              'Avatar generated from $generatedSourceName',
                              if (generatedSourceRarity.isNotEmpty)
                                '($generatedSourceRarity)',
                            ].join(' '),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (profile.bulbapediaUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Bulbapedia reference content is attributed to Bulbapedia and its contributors under CC BY-NC-SA.',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (profile.sourceUrl.isEmpty)
                    Text(
                      sourceLabel,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(profile.sourceUrl),
                        mode: LaunchMode.externalApplication,
                        webOnlyWindowName: '_blank',
                      ),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: Text(sourceLabel),
                    ),
                ],
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  statsPanel,
                  const SizedBox(height: 14),
                  sourcesPanel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: statsPanel),
                const SizedBox(width: 14),
                Expanded(child: sourcesPanel),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ArtistProfileBioText extends StatelessWidget {
  const _ArtistProfileBioText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final links = findTwitterHandleLinks(text);
    if (links.isEmpty) {
      return Text(text, style: style);
    }

    final linkStyle = style.copyWith(
      color: const Color(0xFF38BDF8),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF38BDF8),
      fontWeight: FontWeight.w700,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final link in links) {
      if (link.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, link.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            link: true,
            label: 'Open ${link.text} on X',
            child: InkWell(
              onTap: () => launchUrl(
                link.uri,
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              ),
              child: Text(link.text, style: linkStyle),
            ),
          ),
        ),
      );
      cursor = link.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _ArtistInfoPanel extends StatelessWidget {
  const _ArtistInfoPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1735),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFACC15), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ArtistSourceButton extends StatelessWidget {
  const _ArtistSourceButton({
    required this.label,
    required this.url,
  });

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      ),
      icon: const Icon(Icons.open_in_new, size: 15),
      label: Text(label),
    );
  }
}

class _ArtistProfilePill extends StatelessWidget {
  const _ArtistProfilePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFACC15).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ArtistCard extends ConsumerWidget {
  const _ArtistCard({
    required this.card,
    required this.heroTag,
    required this.language,
  });

  final PokemonCard card;
  final String heroTag;
  final String language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailHeroTag = heroTag.trim();
    final paletteHint = cardPaletteHint(
      type: card.type,
      name: card.name,
      tags: card.tags,
    );
    final frameColor = cardImageFrameColorForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final surfaceGradient = cardDarkSurfaceGradientForPayload(
      card.cardPalette,
      fallbackType: paletteHint,
    );
    final tile = InkWell(
      onTap: () async {
        ref.read(cardProvider.notifier).recordCardInteraction(
              card,
              'click',
              source: 'artist_collection',
            );
        await navigateToCanonicalCardDetail(
          context,
          card,
          language: language,
          source: 'artist_collection',
          extra: detailHeroTag.isEmpty ? null : detailHeroTag,
        );
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: surfaceGradient,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 0.72,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: frameColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.none,
                    child: _artistCardImageUrl(card).isEmpty
                        ? const Icon(
                            Icons.style,
                            color: Color(0xFFFACC15),
                            size: 54,
                          )
                        : CachedNetworkImage(
                            imageUrl: _artistCardImageUrl(card),
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
            const SizedBox(height: 12),
            Text(
              card.number.trim().isEmpty
                  ? card.name
                  : '${card.name} ${card.number}',
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
              card.set.trim().isEmpty ? 'Expansion unknown' : card.set,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB8C4E6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
    return _ArtistHeroCardTile(heroTag: detailHeroTag, child: tile);
  }
}

class _ArtistHeroCardTile extends StatelessWidget {
  const _ArtistHeroCardTile({
    required this.heroTag,
    required this.child,
  });

  final String? heroTag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tag = heroTag;
    if (tag == null || tag.isEmpty) {
      return child;
    }
    return Hero(
      tag: tag,
      flightShuttleBuilder: (
        _,
        animation,
        __,
        ___,
        toHeroContext,
      ) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: Material(
            color: Colors.transparent,
            child: toHeroContext.widget,
          ),
        );
      },
      child: child,
    );
  }
}

String _artistCardImageUrl(PokemonCard card) {
  final homepage = card.homepageImageUrl.trim();
  if (homepage.isNotEmpty) {
    return homepage;
  }
  final preview = card.previewImageUrl.trim();
  if (preview.isNotEmpty) {
    return preview;
  }
  return card.imageUrl.trim();
}

String _artistHeroTag(PokemonCard card, int index) {
  return 'market-card-image-${card.id}-artist-$index';
}

String _artistProfileHeroTag(String artistSlugValue) {
  final normalized = artistSlug(artistSlugValue);
  return 'artist-profile-image-${normalized.isEmpty ? 'unknown' : normalized}';
}

String _artistInitials(String name) {
  return name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part.characters.first.toUpperCase())
      .join();
}

Widget _artistProfileFlightShuttleBuilder(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
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
}
