import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../services/card_service.dart';
import 'home_screen.dart';

final competitiveSnapshotProvider = FutureProvider.autoDispose
    .family<CompetitiveSnapshot?, CompetitiveQuery>((ref, query) {
  return CardService().getCompetitiveSnapshot(
    game: query.game,
    format: query.format,
    year: query.year,
    tournamentId: query.tournamentId,
    deckId: query.deckId,
  );
});

@immutable
class CompetitiveQuery {
  const CompetitiveQuery({
    this.game = '',
    this.format = '',
    this.year,
    this.tournamentId = '',
    this.deckId = '',
    this.decklistId = '',
  });

  final String game;
  final String format;
  final int? year;
  final String tournamentId;
  final String deckId;
  final String decklistId;

  @override
  bool operator ==(Object other) {
    return other is CompetitiveQuery &&
        other.game == game &&
        other.format == format &&
        other.year == year &&
        other.tournamentId == tournamentId &&
        other.deckId == deckId &&
        other.decklistId == decklistId;
  }

  @override
  int get hashCode =>
      Object.hash(game, format, year, tournamentId, deckId, decklistId);
}

class MarketplaceCompetitiveScreen extends ConsumerWidget {
  const MarketplaceCompetitiveScreen({
    super.key,
    this.initialDeckId = '',
    this.initialDecklistId = '',
  });

  // Kept for route compatibility while the competitive hub is in renovation.
  final String initialDeckId;
  final String initialDecklistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final cartState = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: marketplaceTopBarColor,
        toolbarHeight: marketplaceTopBarHeight,
        elevation: 0,
        titleSpacing: 16,
        title: MarketplaceTopBar(
          compactExpanded: false,
          logo: MarketplaceLogoButton(
            onTap: compactTopBar
                ? () => showMarketplaceSideMenu(context)
                : () => context.go('/marketplace'),
          ),
          search: const _CompetitiveTitle(),
          languageMenu: const SizedBox.shrink(),
          actions: marketplaceTopBarActions(
            context: context,
            balance: balance,
            itemCount: cartState.itemCount,
            compactTopBar: compactTopBar,
            compactSearchExpanded: false,
            keyValue: 'competitive-actions',
          ),
        ),
      ),
      body: const _CompetitiveRenovationPage(),
    );
  }
}

class _CompetitiveRenovationPage extends StatelessWidget {
  const _CompetitiveRenovationPage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF101B3E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x33FACC15)),
                ),
                child: const Icon(
                  Icons.construction_rounded,
                  color: Color(0xFFFACC15),
                  size: 36,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Page in renovation',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'The competitive meta hub and top decks view are being rebuilt. Check back soon.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFB8C4E6),
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => context.go('/marketplace'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFACC15),
                  foregroundColor: const Color(0xFF111827),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text(
                  'Back to marketplace',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompetitiveTitle extends StatelessWidget {
  const _CompetitiveTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.emoji_events_outlined, color: Color(0xFFFACC15)),
        SizedBox(width: 10),
        Flexible(
          child: Text(
            'Competitive',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompetitiveContent extends StatelessWidget {
  const _CompetitiveContent({
    required this.snapshot,
    required this.selectedGame,
    required this.selectedFormat,
    required this.selectedYear,
    required this.selectedTournamentId,
    required this.onDeckSelected,
    required this.onGameChanged,
    required this.onFormatChanged,
    required this.onYearChanged,
    required this.onTournamentSelected,
    required this.onDecklistSelected,
    required this.onBackToList,
  });

  final CompetitiveSnapshot snapshot;
  final String selectedGame;
  final String selectedFormat;
  final int? selectedYear;
  final String selectedTournamentId;
  final ValueChanged<String> onDeckSelected;
  final ValueChanged<String> onGameChanged;
  final ValueChanged<String> onFormatChanged;
  final ValueChanged<int?> onYearChanged;
  final ValueChanged<String> onTournamentSelected;
  final ValueChanged<String> onDecklistSelected;
  final VoidCallback onBackToList;

  @override
  Widget build(BuildContext context) {
    final deckDetailMode = snapshot.selectedDeck != null;
    final decklistDetailMode = snapshot.selectedDecklist != null;
    final detailMode =
        selectedTournamentId.isNotEmpty || deckDetailMode || decklistDetailMode;
    final dashboard = snapshot.dashboard;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CompetitiveHero(summary: snapshot.summary),
                    const SizedBox(height: 18),
                    if (!detailMode) ...[
                      _CompetitiveFilters(
                        games: snapshot.games,
                        selectedGame: selectedGame,
                        selectedFormat: selectedFormat,
                        selectedYear: selectedYear,
                        years: snapshot.years,
                        onGameChanged: onGameChanged,
                        onFormatChanged: onFormatChanged,
                        onYearChanged: onYearChanged,
                      ),
                      const SizedBox(height: 18),
                      _CompetitiveDashboardLayout(
                        dashboard: dashboard,
                        fallbackTournaments: snapshot.tournaments,
                        onDeckSelected: onDeckSelected,
                        onTournamentSelected: onTournamentSelected,
                      ),
                    ] else ...[
                      if (deckDetailMode)
                        _DeckDetail(
                          deck: snapshot.selectedDeck!,
                          coreCards: snapshot.coreCards,
                          results: snapshot.deckResults,
                          players: snapshot.deckPlayers,
                          decklists: snapshot.decklists,
                          onTournamentSelected: onTournamentSelected,
                          onDecklistSelected: onDecklistSelected,
                          onBack: onBackToList,
                        )
                      else if (decklistDetailMode)
                        _DecklistDetail(
                          decklist: snapshot.selectedDecklist!,
                          cards: snapshot.decklistCards,
                          onTournamentSelected: onTournamentSelected,
                          onBack: onBackToList,
                        )
                      else
                        _TournamentDetail(
                          tournament: snapshot.selectedTournament,
                          standings: snapshot.standings,
                          pairings: snapshot.pairings,
                          onBack: onBackToList,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompetitiveHero extends StatelessWidget {
  const _CompetitiveHero({required this.summary});

  final CompetitiveSummary summary;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101B3E), Color(0xFF0B1020)],
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Pill('Competitive dashboard'),
                SizedBox(height: 12),
                Text(
                  'Pokoin meta hub',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Top archetypes, public tournament results, upcoming events and local league activity from the synced competitive feed.',
                  style: TextStyle(
                    color: Color(0xFFB8C4E6),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                label: 'Events',
                value: '${summary.tournamentCount}',
                icon: Icons.emoji_events_outlined,
              ),
              _StatCard(
                label: 'Players',
                value: '${summary.totalPlayers}',
                icon: Icons.groups_2_outlined,
              ),
              _StatCard(
                label: 'Standings',
                value: '${summary.tournamentsWithStandings}',
                icon: Icons.leaderboard_outlined,
              ),
              _StatCard(
                label: 'Matches',
                value: '${summary.tournamentsWithPairings}',
                icon: Icons.table_rows_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompetitiveFilters extends StatelessWidget {
  const _CompetitiveFilters({
    required this.games,
    required this.selectedGame,
    required this.selectedFormat,
    required this.selectedYear,
    required this.years,
    required this.onGameChanged,
    required this.onFormatChanged,
    required this.onYearChanged,
  });

  final List<CompetitiveGame> games;
  final String selectedGame;
  final String selectedFormat;
  final int? selectedYear;
  final List<int> years;
  final ValueChanged<String> onGameChanged;
  final ValueChanged<String> onFormatChanged;
  final ValueChanged<int?> onYearChanged;

  @override
  Widget build(BuildContext context) {
    CompetitiveGame? selected;
    for (final game in games) {
      if (game.id == selectedGame) {
        selected = game;
        break;
      }
    }
    final formats = selected?.formats.entries.toList() ?? const [];
    return _Panel(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _FilterChipButton(
            selected: selectedGame.isEmpty,
            label: 'All games',
            onTap: () => onGameChanged(''),
          ),
          for (final game in games.take(8))
            _FilterChipButton(
              selected: selectedGame == game.id,
              label: game.id,
              onTap: () => onGameChanged(game.id),
            ),
          if (formats.isNotEmpty) const SizedBox(width: 8),
          if (formats.isNotEmpty)
            _FilterChipButton(
              selected: selectedFormat.isEmpty,
              label: 'All formats',
              onTap: () => onFormatChanged(''),
            ),
          for (final format in formats.take(8))
            _FilterChipButton(
              selected: selectedFormat == format.key,
              label: format.key,
              tooltip: format.value,
              onTap: () => onFormatChanged(format.key),
            ),
          if (years.isNotEmpty) const SizedBox(width: 8),
          if (years.isNotEmpty)
            _FilterChipButton(
              selected: selectedYear == null,
              label: 'All years',
              onTap: () => onYearChanged(null),
            ),
          for (final year in years.take(8))
            _FilterChipButton(
              selected: selectedYear == year,
              label: '$year',
              onTap: () => onYearChanged(year),
            ),
        ],
      ),
    );
  }
}

class _CompetitiveDashboardLayout extends StatelessWidget {
  const _CompetitiveDashboardLayout({
    required this.dashboard,
    required this.fallbackTournaments,
    required this.onDeckSelected,
    required this.onTournamentSelected,
  });

  final CompetitiveDashboard dashboard;
  final List<CompetitiveTournament> fallbackTournaments;
  final ValueChanged<String> onDeckSelected;
  final ValueChanged<String> onTournamentSelected;

  @override
  Widget build(BuildContext context) {
    final recent = dashboard.recentTournaments.isNotEmpty
        ? dashboard.recentTournaments
        : fallbackTournaments;
    final upcoming = dashboard.upcomingTournaments;
    final cityLeagues = dashboard.cityLeagues.isNotEmpty
        ? dashboard.cityLeagues
        : fallbackTournaments
            .where((tournament) => !tournament.isOnline)
            .toList();
    final wide = MediaQuery.sizeOf(context).width >= 1040;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: _TopDecksPanel(
                  decks: dashboard.topDecks,
                  onDeckSelected: onDeckSelected,
                  onTournamentSelected: onTournamentSelected,
                ),
              ),
              const SizedBox(width: 18),
              const SizedBox(width: 330, child: _CompetitiveNetworkPanel()),
            ],
          )
        else ...[
          _TopDecksPanel(
            decks: dashboard.topDecks,
            onDeckSelected: onDeckSelected,
            onTournamentSelected: onTournamentSelected,
          ),
          const SizedBox(height: 18),
          const _CompetitiveNetworkPanel(),
        ],
        const SizedBox(height: 18),
        _TournamentDashboardColumns(
          recent: recent,
          upcoming: upcoming,
          cityLeagues: cityLeagues,
          onTournamentSelected: onTournamentSelected,
        ),
      ],
    );
  }
}

class _TopDecksPanel extends StatelessWidget {
  const _TopDecksPanel({
    required this.decks,
    required this.onDeckSelected,
    required this.onTournamentSelected,
  });

  final List<CompetitiveTopDeck> decks;
  final ValueChanged<String> onDeckSelected;
  final ValueChanged<String> onTournamentSelected;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.auto_graph_outlined,
            title: 'Top Decks',
            subtitle: 'Synced archetype share from public standings',
          ),
          if (decks.isEmpty)
            const _EmptyTableMessage(
              'No deck archetypes have been synced for this filter yet.',
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 720 ? 2 : 1;
                  final cardWidth =
                      (constraints.maxWidth - ((columns - 1) * 12)) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final entry in decks.take(8).indexed)
                        SizedBox(
                          width: cardWidth,
                          child: _TopDeckCard(
                            rank: entry.$1 + 1,
                            deck: entry.$2,
                            onTap: entry.$2.deckId.isNotEmpty
                                ? () => onDeckSelected(entry.$2.deckId)
                                : entry.$2.featuredTournamentId.isEmpty
                                    ? null
                                    : () => onTournamentSelected(
                                          entry.$2.featuredTournamentId,
                                        ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TopDeckCard extends StatelessWidget {
  const _TopDeckCard({
    required this.rank,
    required this.deck,
    required this.onTap,
  });

  final int rank;
  final CompetitiveTopDeck deck;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        deck.cardImageUrl.isNotEmpty ? deck.cardImageUrl : deck.imageUrl;
    final representativeCardName = deck.representativeCardName.trim();
    final tournamentDate = deck.featuredTournamentDate == null
        ? ''
        : DateFormat('MMM d').format(deck.featuredTournamentDate!.toLocal());
    final subtitle = [
      if (deck.featuredPlayer.isNotEmpty) deck.featuredPlayer,
      if (deck.featuredPlacing != null) '#${deck.featuredPlacing}',
      if (deck.featuredTournamentName.isNotEmpty) deck.featuredTournamentName,
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x18FFFFFF)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DeckArtwork(
                rank: rank,
                label: deck.archetype,
                imageUrl: imageUrl,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            deck.archetype,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              height: 1.1,
                            ),
                          ),
                        ),
                        _ShareBadge(deck.share),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle.isEmpty
                          ? 'Featured standings pending'
                          : subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB8C4E6),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (representativeCardName.isNotEmpty) ...[
                      Text(
                        'Representative card: $representativeCardName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFDE68A),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniChip('${deck.count} lists'),
                        if (deck.formatLabel.isNotEmpty)
                          _MiniChip(deck.formatLabel),
                        if (deck.featuredPlayer.isNotEmpty)
                          _MiniChip(
                            '${deck.featuredWins}-${deck.featuredLosses}-${deck.featuredTies}',
                          ),
                        if (deck.points > 0) _MiniChip('${deck.points} pts'),
                        if (tournamentDate.isNotEmpty)
                          _MiniChip(tournamentDate),
                        if (deck.representativeCardSetName.isNotEmpty)
                          _MiniChip(deck.representativeCardSetName),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DeckActionBar(deck: deck),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckArtwork extends StatelessWidget {
  const _DeckArtwork({
    required this.rank,
    required this.label,
    required this.imageUrl,
  });

  final int rank;
  final String label;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final colors = _deckGradient(label);
    final image = imageUrl.trim();
    return Container(
      width: 72,
      height: 92,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x44FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (image.isNotEmpty)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.network(
                  image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _DeckArtworkFallback(),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const _DeckArtworkFallback();
                  },
                ),
              ),
            )
          else
            const _DeckArtworkFallback(),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xAA050816)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xCC050816),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '#$rank',
                style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckArtworkFallback extends StatelessWidget {
  const _DeckArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Icon(
          Icons.style_outlined,
          color: Color(0x99FFFFFF),
          size: 28,
        ),
      ),
    );
  }
}

class _DeckActionBar extends StatelessWidget {
  const _DeckActionBar({required this.deck});

  final CompetitiveTopDeck deck;

  @override
  Widget build(BuildContext context) {
    final searchLabel =
        deck.representativeCardName.isNotEmpty ? 'Find card' : 'Search deck';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (deck.deckId.isNotEmpty)
          const _InlineHintChip(
            icon: Icons.analytics_outlined,
            label: 'Tap for deck details',
          ),
        _InlineActionChip(
          icon: Icons.search_outlined,
          label: searchLabel,
          onTap: () => _goToMarketplaceSearch(
            context,
            deck.representativeCardName.isNotEmpty
                ? deck.representativeCardName
                : deck.archetype,
          ),
        ),
        if (deck.representativeCardPath.isNotEmpty)
          _InlineActionChip(
            icon: Icons.style_outlined,
            label: 'Open card',
            onTap: () => context.go(deck.representativeCardPath),
          ),
        if (deck.featuredTournamentId.isNotEmpty)
          const _InlineHintChip(
            icon: Icons.leaderboard_outlined,
            label: 'Tap card for event',
          ),
      ],
    );
  }
}

class _ShareBadge extends StatelessWidget {
  const _ShareBadge(this.share);

  final double share;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x22FACC15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x44FACC15)),
      ),
      child: Text(
        '${share.toStringAsFixed(share.truncateToDouble() == share ? 0 : 1)}%',
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CompetitiveNetworkPanel extends StatelessWidget {
  const _CompetitiveNetworkPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.hub_outlined,
            title: 'Pokoin Network',
            subtitle: 'Tools for competitive collectors',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                _NetworkCard(
                  icon: Icons.emoji_events_outlined,
                  title: 'Tournament platform',
                  body: 'Browse public events and open standings instantly.',
                  onTap: () => context.go('/marketplace/competitive'),
                ),
                const SizedBox(height: 10),
                _NetworkCard(
                  icon: Icons.search_outlined,
                  title: 'Deck card search',
                  body: 'Find singles and versions for cards in the meta.',
                  onTap: () => _goToMarketplaceSearch(context, 'meta deck'),
                ),
                const SizedBox(height: 10),
                _NetworkCard(
                  icon: Icons.leaderboard_outlined,
                  title: 'Rankings and results',
                  body: 'Use synced standings to spot emerging archetypes.',
                  onTap: () => context.go('/marketplace/competitive'),
                ),
                const SizedBox(height: 10),
                _NetworkCard(
                  icon: Icons.account_balance_outlined,
                  title: 'Shard review',
                  body: 'Send cards or a decklist for PKN review.',
                  onTap: () => context.go('/shard-review'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF172554), Color(0xFF111936)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x18FFFFFF)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0x22FACC15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFFFACC15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Color(0xFF64748B),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TournamentDashboardColumns extends StatelessWidget {
  const _TournamentDashboardColumns({
    required this.recent,
    required this.upcoming,
    required this.cityLeagues,
    required this.onTournamentSelected,
  });

  final List<CompetitiveTournament> recent;
  final List<CompetitiveTournament> upcoming;
  final List<CompetitiveTournament> cityLeagues;
  final ValueChanged<String> onTournamentSelected;

  @override
  Widget build(BuildContext context) {
    final columns = [
      _TournamentColumnData(
        icon: Icons.history_outlined,
        title: 'Recent Tournaments',
        empty: 'No recent tournaments for this filter.',
        tournaments: recent,
      ),
      _TournamentColumnData(
        icon: Icons.event_available_outlined,
        title: 'Upcoming Tournaments',
        empty: 'No upcoming tournaments are synced yet.',
        tournaments: upcoming,
      ),
      _TournamentColumnData(
        icon: Icons.location_city_outlined,
        title: 'Recent City Leagues',
        empty: 'No local leagues are synced for this filter.',
        tournaments: cityLeagues,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        if (!wide) {
          return Column(
            children: [
              for (final column in columns) ...[
                _TournamentListPanel(
                  data: column,
                  onTournamentSelected: onTournamentSelected,
                ),
                if (column != columns.last) const SizedBox(height: 18),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final column in columns) ...[
              Expanded(
                child: _TournamentListPanel(
                  data: column,
                  onTournamentSelected: onTournamentSelected,
                ),
              ),
              if (column != columns.last) const SizedBox(width: 18),
            ],
          ],
        );
      },
    );
  }
}

class _TournamentColumnData {
  const _TournamentColumnData({
    required this.icon,
    required this.title,
    required this.empty,
    required this.tournaments,
  });

  final IconData icon;
  final String title;
  final String empty;
  final List<CompetitiveTournament> tournaments;
}

class _TournamentListPanel extends StatelessWidget {
  const _TournamentListPanel({
    required this.data,
    required this.onTournamentSelected,
  });

  final _TournamentColumnData data;
  final ValueChanged<String> onTournamentSelected;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(icon: data.icon, title: data.title),
          if (data.tournaments.isEmpty)
            _EmptyTableMessage(data.empty)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  for (final entry in data.tournaments.take(8).indexed) ...[
                    _TournamentEventCard(
                      tournament: entry.$2,
                      onTap: () => onTournamentSelected(entry.$2.id),
                    ),
                    if (entry.$1 < data.tournaments.take(8).length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TournamentEventCard extends StatelessWidget {
  const _TournamentEventCard({
    required this.tournament,
    required this.onTap,
  });

  final CompetitiveTournament tournament;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = tournament.date == null
        ? 'TBD'
        : DateFormat('MMM d, HH:mm').format(tournament.date!.toLocal());
    final badges = [
      tournament.isOnline ? 'Online' : 'Local',
      if (tournament.platform.isNotEmpty) tournament.platform,
      if (tournament.decklistsAvailable) 'Decklists',
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x18FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _DateBadge(date: date),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tournament.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                [
                  if (tournament.organizerName.isNotEmpty)
                    tournament.organizerName,
                  tournament.formatLabel.isNotEmpty
                      ? tournament.formatLabel
                      : tournament.gameName,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MiniChip('${tournament.players} players'),
                  for (final badge in badges) _MiniChip(badge),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Text(
        date,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontSize: 11,
          height: 1.15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TournamentDetail extends StatelessWidget {
  const _TournamentDetail({
    required this.tournament,
    required this.standings,
    required this.pairings,
    required this.onBack,
  });

  final CompetitiveTournament? tournament;
  final List<CompetitiveStanding> standings;
  final List<CompetitivePairing> pairings;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    if (tournament == null) {
      return _Panel(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to tournaments'),
              ),
              const Text(
                'Tournament not found.',
                style: TextStyle(color: Color(0xFFB8C4E6)),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to tournaments'),
              ),
              const SizedBox(height: 8),
              Text(
                tournament!.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniChip(tournament!.gameName),
                  _MiniChip(tournament!.formatLabel),
                  _MiniChip('${tournament!.players} players'),
                  if (tournament!.decklistsAvailable)
                    const _MiniChip('Decklists advertised'),
                  if (tournament!.sourceUrl.isNotEmpty)
                    _InlineActionChip(
                      icon: Icons.open_in_new,
                      label: 'Open source',
                      onTap: () => _openExternalUrl(tournament!.sourceUrl),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _StandingsTable(standings: standings),
        const SizedBox(height: 18),
        _PairingsTable(pairings: pairings),
      ],
    );
  }
}

class _DeckDetail extends StatelessWidget {
  const _DeckDetail({
    required this.deck,
    required this.coreCards,
    required this.results,
    required this.players,
    required this.decklists,
    required this.onTournamentSelected,
    required this.onDecklistSelected,
    required this.onBack,
  });

  final CompetitiveDeckDetail deck;
  final List<CompetitiveDeckCard> coreCards;
  final List<CompetitiveDeckResult> results;
  final List<CompetitiveDeckPlayer> players;
  final List<CompetitiveDecklist> decklists;
  final ValueChanged<String> onTournamentSelected;
  final ValueChanged<String> onDecklistSelected;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to competitive'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Pill('Deck profile'),
                        const SizedBox(height: 12),
                        Text(
                          deck.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Competitive archetype snapshot with Pokoin marketplace artwork, core card usage, recent results, and representative public decklists.',
                          style: TextStyle(
                            color: Color(0xFFB8C4E6),
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _DeckHeroCards(cards: coreCards),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (deck.rank != null) _MiniChip('#${deck.rank} meta deck'),
                  if (deck.formatLabel.isNotEmpty) _MiniChip(deck.formatLabel),
                  if (deck.format.isNotEmpty) _MiniChip(deck.format),
                  _MiniChip('${deck.share.toStringAsFixed(1)}% share'),
                  if (deck.points > 0) _MiniChip('${deck.points} points'),
                  if (deck.earningsText.isNotEmpty)
                    _MiniChip(deck.earningsText),
                  _MiniChip('${deck.regionalTop8} Regional Top 8'),
                  _MiniChip('${deck.regionalWins} Regional wins'),
                  _MiniChip('${deck.internationalTop8} International Top 8'),
                  if (deck.sourceUrl.isNotEmpty)
                    _InlineActionChip(
                      icon: Icons.open_in_new,
                      label: 'Open source',
                      onTap: () => _openExternalUrl(deck.sourceUrl),
                    ),
                ],
              ),
              if (deck.variants.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final variant in deck.variants.take(10))
                      _MiniChip(variant),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _DeckCoreCardsPanel(cards: coreCards),
        const SizedBox(height: 18),
        _DecklistsPanel(
          decklists: decklists,
          onDecklistSelected: onDecklistSelected,
        ),
        const SizedBox(height: 18),
        _DeckResultsPanel(
          results: results,
          onTournamentSelected: onTournamentSelected,
        ),
        const SizedBox(height: 18),
        _DeckPlayersPanel(players: players),
      ],
    );
  }
}

class _DeckHeroCards extends StatelessWidget {
  const _DeckHeroCards({required this.cards});

  final List<CompetitiveDeckCard> cards;

  @override
  Widget build(BuildContext context) {
    final picturedCards =
        cards.where((card) => card.imageUrl.trim().isNotEmpty).take(4).toList();
    if (picturedCards.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: 260,
      height: 158,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final entry in picturedCards.indexed)
            Positioned(
              left: entry.$1 * 52,
              top: entry.$1.isEven ? 8 : 0,
              child: Transform.rotate(
                angle: (entry.$1 - 1.5) * 0.055,
                child: _DeckCardImage(
                  card: entry.$2,
                  width: 92,
                  height: 128,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckCoreCardsPanel extends StatelessWidget {
  const _DeckCoreCardsPanel({required this.cards});

  final List<CompetitiveDeckCard> cards;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.style_outlined,
            title: 'Core Cards',
            subtitle: 'Most common cards in the public Limitless deck profile',
          ),
          if (cards.isEmpty)
            const _EmptyTableMessage('Core card data is not imported yet.')
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 980
                      ? 6
                      : constraints.maxWidth >= 760
                          ? 5
                          : constraints.maxWidth >= 540
                              ? 4
                              : 2;
                  final cardWidth =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final card in cards.take(24))
                        SizedBox(
                          width: cardWidth,
                          child: _DeckCardTile(card: card),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckCardTile extends StatelessWidget {
  const _DeckCardTile({required this.card});

  final CompetitiveDeckCard card;

  @override
  Widget build(BuildContext context) {
    final count = _formatDeckCardCount(card);
    final share = card.inclusionShare == null
        ? ''
        : '${card.inclusionShare!.toStringAsFixed(1)}%';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDeckCard(context, card),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x18FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: _DeckCardImage(
                  card: card,
                  width: 104,
                  height: 146,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                card.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (count.isNotEmpty) '${count}x',
                  if (share.isNotEmpty) share,
                  _cardSetLabel(card),
                ].where((value) => value.isNotEmpty).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFB8C4E6),
                  fontSize: 11,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeckCardImage extends StatelessWidget {
  const _DeckCardImage({
    required this.card,
    required this.width,
    required this.height,
  });

  final CompetitiveDeckCard card;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final image = card.imageUrl.trim();
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _deckGradient(card.name),
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x22FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: image.isEmpty
            ? _DeckCardImageFallback(card: card)
            : Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _DeckCardImageFallback(card: card),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _DeckCardImageFallback(card: card);
                },
              ),
      ),
    );
  }
}

class _DeckCardImageFallback extends StatelessWidget {
  const _DeckCardImageFallback({required this.card});

  final CompetitiveDeckCard card;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.style_outlined, color: Color(0xCCFFFFFF), size: 24),
          const SizedBox(height: 8),
          Text(
            card.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DecklistDetail extends StatefulWidget {
  const _DecklistDetail({
    required this.decklist,
    required this.cards,
    required this.onTournamentSelected,
    required this.onBack,
  });

  final CompetitiveDecklist decklist;
  final List<CompetitiveDeckCard> cards;
  final ValueChanged<String> onTournamentSelected;
  final VoidCallback onBack;

  @override
  State<_DecklistDetail> createState() => _DecklistDetailState();
}

class _DecklistDetailState extends State<_DecklistDetail> {
  CompetitiveDeckCard? _previewCard;

  CompetitiveDeckCard? get _activePreviewCard {
    if (_previewCard != null && widget.cards.contains(_previewCard)) {
      return _previewCard;
    }
    return widget.cards.isEmpty ? null : widget.cards.first;
  }

  void _setPreviewCard(CompetitiveDeckCard card) {
    if (_previewCard == card) return;
    setState(() {
      _previewCard = card;
    });
  }

  @override
  Widget build(BuildContext context) {
    final decklist = widget.decklist;
    final cards = widget.cards;
    final previewCard = _activePreviewCard;
    final date = decklist.tournamentDate == null
        ? ''
        : DateFormat('MMM d, yyyy').format(decklist.tournamentDate!.toLocal());
    final title = decklist.deckName.isEmpty
        ? 'Decklist ${decklist.decklistId}'
        : decklist.deckName;
    final playerLine = [
      if (decklist.playerName.isNotEmpty) decklist.playerName,
      if (decklist.placingLabel.isNotEmpty)
        decklist.placingLabel
      else if (decklist.placing != null)
        '#${decklist.placing}',
      if (decklist.tournamentName.isNotEmpty) decklist.tournamentName,
      if (date.isNotEmpty) date,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to competitive'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Pill('Limitless decklist'),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (playerLine.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            playerLine,
                            style: const TextStyle(
                              color: Color(0xFFB8C4E6),
                              fontSize: 14,
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _DeckHeroCards(cards: cards),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniChip('List ${decklist.decklistId}'),
                  if (decklist.formatLabel.isNotEmpty)
                    _MiniChip(decklist.formatLabel),
                  if (decklist.variant.isNotEmpty) _MiniChip(decklist.variant),
                  _MiniChip('${_decklistTotalCards(cards)} cards'),
                  if (decklist.deckId.isNotEmpty)
                    _InlineActionChip(
                      icon: Icons.analytics_outlined,
                      label: 'Deck profile',
                      onTap: () => context.go(
                        '/marketplace/competitive/decks/${decklist.deckId}',
                      ),
                    ),
                  if (decklist.tournamentId.isNotEmpty)
                    _InlineActionChip(
                      icon: Icons.emoji_events_outlined,
                      label: 'Tournament',
                      onTap: () =>
                          widget.onTournamentSelected(decklist.tournamentId),
                    ),
                  if (decklist.sourceUrl.isNotEmpty)
                    _InlineActionChip(
                      icon: Icons.open_in_new,
                      label: 'Open source',
                      onTap: () => _openExternalUrl(decklist.sourceUrl),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Panel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle(
                icon: Icons.style_outlined,
                title: 'Deck Cards',
                subtitle:
                    'Pokemon, Trainer, and Energy sections with Pokoin marketplace images.',
              ),
              if (cards.isEmpty)
                const _EmptyTableMessage(
                  'This decklist has no imported card rows yet.',
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 920;
                      final preview = _DecklistPreviewPane(card: previewCard);
                      final sections = _DecklistSections(
                        cards: cards,
                        previewCard: previewCard,
                        onPreviewCardChanged: _setPreviewCard,
                      );
                      if (!wide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            preview,
                            const SizedBox(height: 14),
                            sections,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: sections),
                          const SizedBox(width: 18),
                          SizedBox(width: 300, child: preview),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeckResultsPanel extends StatelessWidget {
  const _DeckResultsPanel({
    required this.results,
    required this.onTournamentSelected,
  });

  final List<CompetitiveDeckResult> results;
  final ValueChanged<String> onTournamentSelected;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.emoji_events_outlined,
            title: 'Latest Results',
          ),
          if (results.isEmpty)
            const _EmptyTableMessage(
                'No public results have been imported yet.')
          else
            for (final result in results.take(30))
              _DeckResultRow(
                result: result,
                onTap: result.tournamentId.isEmpty
                    ? null
                    : () => onTournamentSelected(result.tournamentId),
              ),
        ],
      ),
    );
  }
}

class _DeckResultRow extends StatelessWidget {
  const _DeckResultRow({required this.result, this.onTap});

  final CompetitiveDeckResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final date = result.tournamentDate == null
        ? ''
        : DateFormat('MMM d, yyyy').format(result.tournamentDate!.toLocal());
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  result.placingLabel.isNotEmpty
                      ? result.placingLabel
                      : result.placing == null
                          ? '-'
                          : '#${result.placing}',
                  style: const TextStyle(
                    color: Color(0xFFFACC15),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  result.playerName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  [
                    result.tournamentName,
                    if (date.isNotEmpty) date,
                    if (result.variant.isNotEmpty) result.variant,
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFB8C4E6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecklistsPanel extends StatelessWidget {
  const _DecklistsPanel({
    required this.decklists,
    required this.onDecklistSelected,
  });

  final List<CompetitiveDecklist> decklists;
  final ValueChanged<String> onDecklistSelected;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.list_alt_outlined,
            title: 'Featured Decklists',
          ),
          if (decklists.isEmpty)
            const _EmptyTableMessage(
                'Representative decklists are not imported yet.')
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final decklist in decklists.take(4)) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _decklistTitle(decklist),
                            style: const TextStyle(
                              color: Color(0xFFFDE68A),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _InlineActionChip(
                          icon: Icons.open_in_new,
                          label: 'Open list',
                          onTap: () => onDecklistSelected(decklist.decklistId),
                        ),
                      ],
                    ),
                    if (_decklistSubtitle(decklist).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _decklistSubtitle(decklist),
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _DecklistSections(cards: decklist.cards),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DecklistSections extends StatelessWidget {
  const _DecklistSections({
    required this.cards,
    this.previewCard,
    this.onPreviewCardChanged,
  });

  final List<CompetitiveDeckCard> cards;
  final CompetitiveDeckCard? previewCard;
  final ValueChanged<CompetitiveDeckCard>? onPreviewCardChanged;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CompetitiveDeckCard>>{};
    for (final card in cards) {
      final key = _deckSectionLabel(card.section);
      groups.putIfAbsent(key, () => []).add(card);
    }
    final orderedKeys = [
      'Pokemon',
      'Trainer',
      'Energy',
      ...groups.keys.where(
        (key) => key != 'Pokemon' && key != 'Trainer' && key != 'Energy',
      ),
    ].where(groups.containsKey).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final sectionCount = orderedKeys.length.clamp(1, 3);
        final sectionWidth = wide
            ? (constraints.maxWidth - ((sectionCount - 1) * 12)) / sectionCount
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final key in orderedKeys)
              SizedBox(
                width: sectionWidth,
                child: _DecklistSection(
                  title: key,
                  cards: groups[key] ?? const [],
                  previewCard: previewCard,
                  onPreviewCardChanged: onPreviewCardChanged,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DecklistSection extends StatelessWidget {
  const _DecklistSection({
    required this.title,
    required this.cards,
    this.previewCard,
    this.onPreviewCardChanged,
  });

  final String title;
  final List<CompetitiveDeckCard> cards;
  final CompetitiveDeckCard? previewCard;
  final ValueChanged<CompetitiveDeckCard>? onPreviewCardChanged;

  @override
  Widget build(BuildContext context) {
    final total = cards.fold<double>(
      0,
      (sum, card) => sum + (card.count ?? 0),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _MiniChip(
                '${total.toStringAsFixed(total.truncateToDouble() == total ? 0 : 1)} cards',
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final card in cards.take(80)) ...[
            _DecklistCardRow(
              card: card,
              selected: identical(card, previewCard),
              onPreview: onPreviewCardChanged,
            ),
            if (card != cards.take(80).last)
              const Divider(height: 10, color: Color(0x14FFFFFF)),
          ],
        ],
      ),
    );
  }
}

class _DecklistCardRow extends StatelessWidget {
  const _DecklistCardRow({
    required this.card,
    this.selected = false,
    this.onPreview,
  });

  final CompetitiveDeckCard card;
  final bool selected;
  final ValueChanged<CompetitiveDeckCard>? onPreview;

  @override
  Widget build(BuildContext context) {
    final count = _formatDeckCardCount(card);
    return Material(
      color: Colors.transparent,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (hasFocus) {
          if (hasFocus) onPreview?.call(card);
        },
        onShowHoverHighlight: (hovering) {
          if (hovering) onPreview?.call(card);
        },
        child: InkWell(
          onTap: () => _openDeckCard(context, card),
          onFocusChange: (hasFocus) {
            if (hasFocus) onPreview?.call(card);
          },
          onHover: (hovering) {
            if (hovering) onPreview?.call(card);
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? const Color(0x2214B8A6) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? const Color(0x6614B8A6) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    count.isEmpty ? '-' : '$count x',
                    style: const TextStyle(
                      color: Color(0xFFFACC15),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _cardSetLabel(card).isEmpty
                            ? 'Pokoin marketplace search'
                            : _cardSetLabel(card),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  card.marketplacePath.isEmpty
                      ? Icons.search_outlined
                      : Icons.shopping_bag_outlined,
                  color: const Color(0xFF67E8F9),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DecklistPreviewPane extends StatelessWidget {
  const _DecklistPreviewPane({required this.card});

  final CompetitiveDeckCard? card;

  @override
  Widget build(BuildContext context) {
    final active = card;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172554), Color(0xFF0B1020)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: active == null
          ? const Text(
              'Hover a decklist card to preview it here.',
              style: TextStyle(color: Color(0xFFB8C4E6), height: 1.4),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _DeckCardImage(
                    card: active,
                    width: 210,
                    height: 294,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  active.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_formatDeckCardCount(active).isNotEmpty)
                      _MiniChip('${_formatDeckCardCount(active)} copies'),
                    if (_cardSetLabel(active).isNotEmpty)
                      _MiniChip(_cardSetLabel(active)),
                    if (active.marketplaceCardId.isNotEmpty)
                      _MiniChip('Pokoin #${active.marketplaceCardId}'),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.center,
                  child: _InlineActionChip(
                    icon: active.marketplacePath.isEmpty
                        ? Icons.search_outlined
                        : Icons.shopping_bag_outlined,
                    label: active.marketplacePath.isEmpty
                        ? 'Search marketplace'
                        : 'Open marketplace',
                    onTap: () => _openDeckCard(context, active),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DeckPlayersPanel extends StatelessWidget {
  const _DeckPlayersPanel({required this.players});

  final List<CompetitiveDeckPlayer> players;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.groups_2_outlined,
            title: 'Most Successful Players',
          ),
          if (players.isEmpty)
            const _EmptyTableMessage('Player ranking is not imported yet.')
          else
            for (final player in players.take(10))
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      child: Text(
                        player.rank == null ? '-' : '#${player.rank}',
                        style: const TextStyle(
                          color: Color(0xFFFACC15),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        player.country.isEmpty
                            ? player.playerName
                            : '${player.playerName} (${player.country})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    _MiniChip('${player.points} pts'),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.standings});

  final List<CompetitiveStanding> standings;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.leaderboard_outlined,
            title: 'Standings and Decks',
          ),
          if (standings.isEmpty)
            const _EmptyTableMessage(
              'No standings have been synced for this event yet.',
            )
          else
            for (final standing in standings.take(80))
              _StandingRow(standing: standing),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.standing});

  final CompetitiveStanding standing;

  @override
  Widget build(BuildContext context) {
    final deckLabel = standing.deckArchetype.isNotEmpty
        ? standing.deckArchetype
        : standing.deckName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              standing.placing == null ? '-' : '#${standing.placing}',
              style: const TextStyle(
                color: Color(0xFFFACC15),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              standing.country.isEmpty
                  ? standing.name
                  : '${standing.name} (${standing.country})',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 86,
            child: Text(
              '${standing.wins}-${standing.losses}-${standing.ties}',
              style: const TextStyle(color: Color(0xFFE2E8F0)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: deckLabel.isEmpty
                  ? const Text(
                      'Deck pending',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xFFB8C4E6)),
                    )
                  : _InlineActionChip(
                      icon: Icons.search_outlined,
                      label: deckLabel,
                      onTap: () => _goToMarketplaceSearch(context, deckLabel),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingsTable extends StatelessWidget {
  const _PairingsTable({required this.pairings});

  final List<CompetitivePairing> pairings;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(
            icon: Icons.table_rows_outlined,
            title: 'Recent Matches',
          ),
          if (pairings.isEmpty)
            const _EmptyTableMessage(
              'No pairings have been synced for this event yet.',
            )
          else
            for (final pairing in pairings.take(80))
              _PairingRow(pairing: pairing),
        ],
      ),
    );
  }
}

class _PairingRow extends StatelessWidget {
  const _PairingRow({required this.pairing});

  final CompetitivePairing pairing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              'R${pairing.round} · T${pairing.table}',
              style: const TextStyle(
                color: Color(0xFFFACC15),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${pairing.player1Name} vs ${pairing.player2Name}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFACC15), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!.trim(),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTableMessage extends StatelessWidget {
  const _EmptyTableMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFB8C4E6)),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.selected,
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFACC15) : const Color(0xFF111936),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFFACC15) : const Color(0x22FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF111827) : Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFB8C4E6),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InlineActionChip extends StatelessWidget {
  const _InlineActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x2214B8A6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x4414B8A6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF67E8F9), size: 13),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE0F2FE),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineHintChip extends StatelessWidget {
  const _InlineHintChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF94A3B8), size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB8C4E6),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFACC15), size: 20),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x22FACC15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x44FACC15)),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        gradient: gradient,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x18FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 24,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CompetitiveLoading extends StatelessWidget {
  const _CompetitiveLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFFFACC15)),
    );
  }
}

class _CompetitiveError extends StatelessWidget {
  const _CompetitiveError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _Panel(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
          ),
        ),
      ),
    );
  }
}

List<Color> _deckGradient(String seed) {
  const palettes = [
    [Color(0xFF7C3AED), Color(0xFF1D4ED8)],
    [Color(0xFFEA580C), Color(0xFFBE123C)],
    [Color(0xFF059669), Color(0xFF0F766E)],
    [Color(0xFFEAB308), Color(0xFFB45309)],
    [Color(0xFF2563EB), Color(0xFF0891B2)],
    [Color(0xFFDB2777), Color(0xFF7E22CE)],
  ];
  final index =
      seed.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % palettes.length;
  return palettes[index];
}

void _goToMarketplaceSearch(BuildContext context, String query) {
  final trimmed = query.trim();
  context.go(
    Uri(
      path: '/marketplace/search',
      queryParameters: {
        if (trimmed.isNotEmpty) 'q': trimmed,
        'productType': 'card',
      },
    ).toString(),
  );
}

void _openDeckCard(BuildContext context, CompetitiveDeckCard card) {
  if (card.marketplacePath.isNotEmpty) {
    context.go(card.marketplacePath);
    return;
  }
  _goToMarketplaceSearch(context, card.name);
}

String _formatDeckCardCount(CompetitiveDeckCard card) {
  final count = card.count;
  if (count == null) return '';
  return count.toStringAsFixed(count.truncateToDouble() == count ? 0 : 1);
}

String _cardSetLabel(CompetitiveDeckCard card) {
  return [
    card.setCode,
    if (card.collectorNumber.isNotEmpty) '#${card.collectorNumber}',
  ].where((value) => value.trim().isNotEmpty).join(' ');
}

String _decklistTitle(CompetitiveDecklist decklist) {
  final player = decklist.playerName.trim();
  if (player.isEmpty) return 'Decklist ${decklist.decklistId}';
  return '$player - decklist ${decklist.decklistId}';
}

String _decklistSubtitle(CompetitiveDecklist decklist) {
  final date = decklist.tournamentDate == null
      ? ''
      : DateFormat('MMM d, yyyy').format(decklist.tournamentDate!.toLocal());
  return [
    if (decklist.placingLabel.isNotEmpty)
      decklist.placingLabel
    else if (decklist.placing != null)
      '#${decklist.placing}',
    if (decklist.tournamentName.isNotEmpty) decklist.tournamentName,
    if (date.isNotEmpty) date,
    if (decklist.variant.isNotEmpty) decklist.variant,
  ].join(' · ');
}

String _decklistTotalCards(List<CompetitiveDeckCard> cards) {
  final total = cards.fold<double>(0, (sum, card) => sum + (card.count ?? 0));
  return total.toStringAsFixed(total.truncateToDouble() == total ? 0 : 1);
}

String _deckSectionLabel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('pok')) return 'Pokemon';
  if (normalized.contains('trainer')) return 'Trainer';
  if (normalized.contains('energy')) return 'Energy';
  if (normalized.isEmpty) return 'Other';
  return normalized[0].toUpperCase() + normalized.substring(1);
}

Future<void> _openExternalUrl(String value) async {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
