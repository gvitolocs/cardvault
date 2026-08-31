import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/pokemon_card.dart';
import '../utils/card_url.dart';
import 'pokoin_api_auth.dart';
import 'search_debug_trace.dart';

const String _cardImageProxyOrigin = 'https://pokoin.com';
const String _cardImageProxyPrefix = '/card-images';
const String _cardImageCdnHost = 'cdn.pokoin.com';
const String _competitiveApiBaseUrl = String.fromEnvironment(
    'COMPETITIVE_API_BASE_URL',
    defaultValue: 'https://api.pokoin.com');
const int _marketplaceArtistSnapshotLimit = 300;

Map<String, dynamic> _mapFromJson(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

double? _readPositiveDouble(Object? value) {
  if (value is num && value > 0) {
    return value.toDouble();
  }
  final parsed = double.tryParse('${value ?? ''}'.trim());
  return parsed != null && parsed > 0 ? parsed : null;
}

int _readIntValue(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}

class MarketplaceCardCanonicalUrl {
  const MarketplaceCardCanonicalUrl({
    required this.cardId,
    required this.canonicalPath,
    required this.language,
    this.publicNumber = '',
  });

  factory MarketplaceCardCanonicalUrl.fromJson(Map<String, dynamic> json) {
    return MarketplaceCardCanonicalUrl(
      cardId: '${json['cardId'] ?? json['card_id'] ?? ''}'.trim(),
      canonicalPath:
          '${json['canonicalPath'] ?? json['canonical_path'] ?? ''}'.trim(),
      language: '${json['language'] ?? 'en'}'.trim(),
      publicNumber:
          '${json['publicNumber'] ?? json['public_number'] ?? ''}'.trim(),
    );
  }

  final String cardId;
  final String canonicalPath;
  final String language;
  final String publicNumber;
}

class MarketplaceExpansion {
  const MarketplaceExpansion({
    required this.name,
    required this.slug,
    required this.cardCount,
    required this.symbolImageUrl,
    required this.logoImageUrl,
    required this.defaultSymbolUrl,
  });

  factory MarketplaceExpansion.fromJson(Map<String, dynamic> json) {
    return MarketplaceExpansion(
      name: '${json['name'] ?? ''}',
      slug: '${json['slug'] ?? ''}',
      cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
      symbolImageUrl: '${json['symbolImageUrl'] ?? ''}',
      logoImageUrl: '${json['logoImageUrl'] ?? ''}',
      defaultSymbolUrl: '${json['defaultSymbolUrl'] ?? ''}',
    );
  }

  final String name;
  final String slug;
  final int cardCount;
  final String symbolImageUrl;
  final String logoImageUrl;
  final String defaultSymbolUrl;
}

class MarketplaceExpansionSnapshot {
  const MarketplaceExpansionSnapshot({
    required this.expansion,
    required this.cards,
  });

  final MarketplaceExpansion expansion;
  final List<PokemonCard> cards;
}

class MarketplaceCheapestPrice {
  const MarketplaceCheapestPrice({
    required this.cardId,
    required this.pricePkn,
    required this.available,
    required this.listingCount,
    required this.listedQuantity,
    this.publicNumber = '',
    this.canonicalPath = '',
    this.source = '',
    this.name = '',
    this.setName = '',
    this.number = '',
  });

  factory MarketplaceCheapestPrice.fromJson(Map<String, dynamic> json) {
    final cardtrader = _mapFromJson(json['cardtrader']);
    final price = _readPositiveDouble(
      json['pricePkn'] ?? json['price'] ?? cardtrader['pricePkn'],
    );
    final listingCount = _readIntValue(
      json['listingCount'] ?? cardtrader['listingCount'],
    );
    final listedQuantity = _readIntValue(
      json['listedQuantity'] ?? cardtrader['listedQuantity'],
    );
    return MarketplaceCheapestPrice(
      cardId: '${json['cardId'] ?? json['card_id'] ?? ''}'.trim(),
      pricePkn: price,
      available: json['available'] == true ||
          json['inStock'] == true ||
          listingCount > 0,
      listingCount: listingCount,
      listedQuantity: listedQuantity,
      publicNumber:
          '${json['publicNumber'] ?? json['public_number'] ?? ''}'.trim(),
      canonicalPath:
          '${json['canonicalPath'] ?? json['canonical_path'] ?? ''}'.trim(),
      source: '${json['source'] ?? cardtrader['source'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      setName:
          '${json['set'] ?? json['setName'] ?? json['set_name'] ?? ''}'.trim(),
      number:
          '${json['number'] ?? json['cardNumber'] ?? json['card_number'] ?? ''}'
              .trim(),
    );
  }

  final String cardId;
  final double? pricePkn;
  final bool available;
  final int listingCount;
  final int listedQuantity;
  final String publicNumber;
  final String canonicalPath;
  final String source;
  final String name;
  final String setName;
  final String number;
}

class MarketplaceArtistSnapshot {
  const MarketplaceArtistSnapshot({
    required this.name,
    required this.slug,
    required this.cardCount,
    required this.cards,
    this.profile = const MarketplaceArtistProfile(),
  });

  final String name;
  final String slug;
  final int cardCount;
  final List<PokemonCard> cards;
  final MarketplaceArtistProfile profile;
}

class MarketplaceArtistProfile {
  const MarketplaceArtistProfile({
    this.displayName = '',
    this.summary = '',
    this.bio = '',
    this.imageUrl = '',
    this.sourceImageUrl = '',
    this.imageObjectKey = '',
    this.pocketmonstersUrl = '',
    this.pocketmonstersId = '',
    this.bulbapediaUrl = '',
    this.bulbapediaTitle = '',
    this.sourceName = '',
    this.sourceUrl = '',
    this.generatedProfileImage = const <String, dynamic>{},
  });

  factory MarketplaceArtistProfile.fromJson(Map<String, dynamic> json) {
    return MarketplaceArtistProfile(
      displayName:
          '${json['displayName'] ?? json['display_name'] ?? ''}'.trim(),
      summary: '${json['summary'] ?? ''}'.trim(),
      bio: '${json['bio'] ?? ''}'.trim(),
      imageUrl: '${json['imageUrl'] ?? json['image_url'] ?? ''}'.trim(),
      sourceImageUrl:
          '${json['sourceImageUrl'] ?? json['source_image_url'] ?? ''}'.trim(),
      imageObjectKey:
          '${json['imageObjectKey'] ?? json['image_object_key'] ?? ''}'.trim(),
      pocketmonstersUrl:
          '${json['pocketmonstersUrl'] ?? json['pocketmonsters_url'] ?? ''}'
              .trim(),
      pocketmonstersId:
          '${json['pocketmonstersId'] ?? json['pocketmonsters_id'] ?? ''}'
              .trim(),
      bulbapediaUrl:
          '${json['bulbapediaUrl'] ?? json['bulbapedia_url'] ?? ''}'.trim(),
      bulbapediaTitle:
          '${json['bulbapediaTitle'] ?? json['bulbapedia_title'] ?? ''}'.trim(),
      sourceName: '${json['sourceName'] ?? json['source_name'] ?? ''}'.trim(),
      sourceUrl: '${json['sourceUrl'] ?? json['source_url'] ?? ''}'.trim(),
      generatedProfileImage: _mapFromJson(
        json['generatedProfileImage'] ?? json['generated_profile_image'],
      ),
    );
  }

  final String displayName;
  final String summary;
  final String bio;
  final String imageUrl;
  final String sourceImageUrl;
  final String imageObjectKey;
  final String pocketmonstersUrl;
  final String pocketmonstersId;
  final String bulbapediaUrl;
  final String bulbapediaTitle;
  final String sourceName;
  final String sourceUrl;
  final Map<String, dynamic> generatedProfileImage;

  bool get hasGeneratedProfileImage => generatedProfileImage.isNotEmpty;

  bool get hasContent =>
      summary.isNotEmpty ||
      bio.isNotEmpty ||
      imageUrl.isNotEmpty ||
      pocketmonstersUrl.isNotEmpty ||
      bulbapediaUrl.isNotEmpty;
}

class MarketplaceArtistSummary {
  const MarketplaceArtistSummary({
    required this.name,
    required this.slug,
    required this.cardCount,
    required this.imageUrl,
  });

  factory MarketplaceArtistSummary.fromJson(Map<String, dynamic> json) {
    return MarketplaceArtistSummary(
      name: '${json['name'] ?? ''}'.trim(),
      slug: artistSlug('${json['slug'] ?? json['name'] ?? ''}'),
      cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
      imageUrl: '${json['imageUrl'] ?? json['image_url'] ?? ''}'.trim(),
    );
  }

  final String name;
  final String slug;
  final int cardCount;
  final String imageUrl;
}

class CompetitiveGame {
  const CompetitiveGame({
    required this.id,
    required this.name,
    required this.formats,
    required this.metagame,
  });

  factory CompetitiveGame.fromJson(Map<String, dynamic> json) {
    return CompetitiveGame(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? json['id'] ?? ''}'.trim(),
      formats: Map<String, String>.fromEntries(
        (json['formats'] as Map? ?? const {}).entries.map(
              (entry) => MapEntry('${entry.key}', '${entry.value}'),
            ),
      ),
      metagame: json['metagame'] == true,
    );
  }

  final String id;
  final String name;
  final Map<String, String> formats;
  final bool metagame;
}

class CompetitiveSummary {
  const CompetitiveSummary({
    required this.tournamentCount,
    required this.totalPlayers,
    required this.tournamentsWithStandings,
    required this.tournamentsWithPairings,
    this.updatedAt,
  });

  factory CompetitiveSummary.fromJson(Map<String, dynamic> json) {
    return CompetitiveSummary(
      tournamentCount: (json['tournamentCount'] as num?)?.toInt() ?? 0,
      totalPlayers: (json['totalPlayers'] as num?)?.toInt() ?? 0,
      tournamentsWithStandings:
          (json['tournamentsWithStandings'] as num?)?.toInt() ?? 0,
      tournamentsWithPairings:
          (json['tournamentsWithPairings'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }

  final int tournamentCount;
  final int totalPlayers;
  final int tournamentsWithStandings;
  final int tournamentsWithPairings;
  final DateTime? updatedAt;
}

class CompetitiveTopDeck {
  const CompetitiveTopDeck({
    required this.deckId,
    required this.archetype,
    required this.game,
    required this.format,
    required this.formatLabel,
    required this.count,
    required this.share,
    this.points = 0,
    required this.featuredPlayer,
    required this.featuredPlacing,
    required this.featuredWins,
    required this.featuredLosses,
    required this.featuredTies,
    required this.featuredTournamentId,
    required this.featuredTournamentName,
    required this.featuredTournamentDate,
    required this.featuredDecklistId,
    this.representativeCardId = '',
    this.representativeCardName = '',
    this.representativeCardSetName = '',
    this.representativeCardNumber = '',
    this.representativeCardPath = '',
    this.imageUrl = '',
    this.cardImageUrl = '',
  });

  factory CompetitiveTopDeck.fromJson(Map<String, dynamic> json) {
    final featuredRecord =
        Map<String, dynamic>.from(json['featuredRecord'] as Map? ?? {});
    return CompetitiveTopDeck(
      deckId: '${json['deckId'] ?? json['deck_id'] ?? ''}'.trim(),
      archetype: '${json['archetype'] ?? ''}'.trim(),
      game: '${json['game'] ?? ''}'.trim(),
      format: '${json['format'] ?? ''}'.trim(),
      formatLabel: '${json['formatLabel'] ?? json['format'] ?? ''}'.trim(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      share: (json['share'] as num?)?.toDouble() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      featuredPlayer: '${json['featuredPlayer'] ?? ''}'.trim(),
      featuredPlacing: (json['featuredPlacing'] as num?)?.toInt(),
      featuredWins: (featuredRecord['wins'] as num?)?.toInt() ?? 0,
      featuredLosses: (featuredRecord['losses'] as num?)?.toInt() ?? 0,
      featuredTies: (featuredRecord['ties'] as num?)?.toInt() ?? 0,
      featuredTournamentId: '${json['featuredTournamentId'] ?? ''}'.trim(),
      featuredTournamentName: '${json['featuredTournamentName'] ?? ''}'.trim(),
      featuredTournamentDate:
          DateTime.tryParse('${json['featuredTournamentDate'] ?? ''}'),
      featuredDecklistId: '${json['featuredDecklistId'] ?? ''}'.trim(),
      representativeCardId: '${json['representativeCardId'] ?? ''}'.trim(),
      representativeCardName: '${json['representativeCardName'] ?? ''}'.trim(),
      representativeCardSetName:
          '${json['representativeCardSetName'] ?? ''}'.trim(),
      representativeCardNumber:
          '${json['representativeCardNumber'] ?? ''}'.trim(),
      representativeCardPath: '${json['representativeCardPath'] ?? ''}'.trim(),
      imageUrl: '${json['imageUrl'] ?? json['image_url'] ?? ''}'.trim(),
      cardImageUrl:
          '${json['cardImageUrl'] ?? json['card_image_url'] ?? ''}'.trim(),
    );
  }

  final String archetype;
  final String deckId;
  final String game;
  final String format;
  final String formatLabel;
  final int count;
  final double share;
  final int points;
  final String featuredPlayer;
  final int? featuredPlacing;
  final int featuredWins;
  final int featuredLosses;
  final int featuredTies;
  final String featuredTournamentId;
  final String featuredTournamentName;
  final DateTime? featuredTournamentDate;
  final String featuredDecklistId;
  final String representativeCardId;
  final String representativeCardName;
  final String representativeCardSetName;
  final String representativeCardNumber;
  final String representativeCardPath;
  final String imageUrl;
  final String cardImageUrl;
}

class CompetitiveTournament {
  const CompetitiveTournament({
    required this.id,
    required this.name,
    required this.game,
    required this.gameName,
    required this.format,
    required this.formatLabel,
    required this.date,
    required this.players,
    required this.organizerName,
    required this.platform,
    required this.decklistsAvailable,
    required this.isOnline,
    required this.phases,
    required this.sourceUrl,
    this.standingsFetchedAt,
    this.pairingsFetchedAt,
  });

  factory CompetitiveTournament.fromJson(Map<String, dynamic> json) {
    return CompetitiveTournament(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      game: '${json['game'] ?? ''}'.trim(),
      gameName: '${json['gameName'] ?? json['game'] ?? ''}'.trim(),
      format: '${json['format'] ?? ''}'.trim(),
      formatLabel: '${json['formatLabel'] ?? json['format'] ?? ''}'.trim(),
      date: DateTime.tryParse('${json['date'] ?? ''}'),
      players: (json['players'] as num?)?.toInt() ?? 0,
      organizerName: '${json['organizerName'] ?? ''}'.trim(),
      platform: '${json['platform'] ?? ''}'.trim(),
      decklistsAvailable: json['decklistsAvailable'] == true,
      isOnline: json['isOnline'] == true,
      phases: (json['phases'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
      sourceUrl: '${json['sourceUrl'] ?? ''}'.trim(),
      standingsFetchedAt:
          DateTime.tryParse('${json['standingsFetchedAt'] ?? ''}'),
      pairingsFetchedAt:
          DateTime.tryParse('${json['pairingsFetchedAt'] ?? ''}'),
    );
  }

  final String id;
  final String name;
  final String game;
  final String gameName;
  final String format;
  final String formatLabel;
  final DateTime? date;
  final int players;
  final String organizerName;
  final String platform;
  final bool decklistsAvailable;
  final bool isOnline;
  final List<Map<String, dynamic>> phases;
  final String sourceUrl;
  final DateTime? standingsFetchedAt;
  final DateTime? pairingsFetchedAt;
}

class CompetitiveDashboard {
  const CompetitiveDashboard({
    this.topDecks = const [],
    this.recentTournaments = const [],
    this.upcomingTournaments = const [],
    this.cityLeagues = const [],
  });

  factory CompetitiveDashboard.fromJson(Map<String, dynamic> json) {
    return CompetitiveDashboard(
      topDecks: (json['topDecks'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveTopDeck.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      recentTournaments:
          (json['recentTournaments'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((row) => CompetitiveTournament.fromJson(
                    Map<String, dynamic>.from(row),
                  ))
              .toList(),
      upcomingTournaments:
          (json['upcomingTournaments'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((row) => CompetitiveTournament.fromJson(
                    Map<String, dynamic>.from(row),
                  ))
              .toList(),
      cityLeagues: (json['cityLeagues'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => CompetitiveTournament.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .toList(),
    );
  }

  final List<CompetitiveTopDeck> topDecks;
  final List<CompetitiveTournament> recentTournaments;
  final List<CompetitiveTournament> upcomingTournaments;
  final List<CompetitiveTournament> cityLeagues;
}

class CompetitiveStanding {
  const CompetitiveStanding({
    required this.placing,
    required this.playerId,
    required this.name,
    required this.country,
    required this.wins,
    required this.losses,
    required this.ties,
    required this.deckName,
    required this.deckArchetype,
    required this.decklistId,
  });

  factory CompetitiveStanding.fromJson(Map<String, dynamic> json) {
    final record = Map<String, dynamic>.from(json['record'] as Map? ?? {});
    return CompetitiveStanding(
      placing: (json['placing'] as num?)?.toInt(),
      playerId: '${json['playerId'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      country: '${json['country'] ?? ''}'.trim(),
      wins: (record['wins'] as num?)?.toInt() ?? 0,
      losses: (record['losses'] as num?)?.toInt() ?? 0,
      ties: (record['ties'] as num?)?.toInt() ?? 0,
      deckName: '${json['deckName'] ?? ''}'.trim(),
      deckArchetype: '${json['deckArchetype'] ?? ''}'.trim(),
      decklistId: '${json['decklistId'] ?? ''}'.trim(),
    );
  }

  final int? placing;
  final String playerId;
  final String name;
  final String country;
  final int wins;
  final int losses;
  final int ties;
  final String deckName;
  final String deckArchetype;
  final String decklistId;
}

class CompetitivePairing {
  const CompetitivePairing({
    required this.phase,
    required this.round,
    required this.table,
    required this.player1Name,
    required this.player2Name,
    required this.winnerPlayerId,
  });

  factory CompetitivePairing.fromJson(Map<String, dynamic> json) {
    return CompetitivePairing(
      phase: (json['phase'] as num?)?.toInt() ?? 0,
      round: (json['round'] as num?)?.toInt() ?? 0,
      table: (json['table'] as num?)?.toInt() ?? 0,
      player1Name: '${json['player1Name'] ?? json['player1Id'] ?? ''}'.trim(),
      player2Name: '${json['player2Name'] ?? json['player2Id'] ?? ''}'.trim(),
      winnerPlayerId: '${json['winnerPlayerId'] ?? ''}'.trim(),
    );
  }

  final int phase;
  final int round;
  final int table;
  final String player1Name;
  final String player2Name;
  final String winnerPlayerId;
}

class CompetitiveDeckCard {
  const CompetitiveDeckCard({
    required this.name,
    this.count,
    this.inclusionShare,
    this.section = '',
    this.setCode = '',
    this.collectorNumber = '',
    this.marketplaceCardId = '',
    this.marketplacePath = '',
    this.imageUrl = '',
  });

  factory CompetitiveDeckCard.fromJson(Map<String, dynamic> json) {
    return CompetitiveDeckCard(
      name: '${json['name'] ?? json['cardName'] ?? ''}'.trim(),
      count: (json['count'] as num?)?.toDouble(),
      inclusionShare: (json['inclusionShare'] as num?)?.toDouble(),
      section: '${json['section'] ?? ''}'.trim(),
      setCode: '${json['setCode'] ?? ''}'.trim(),
      collectorNumber: '${json['collectorNumber'] ?? ''}'.trim(),
      marketplaceCardId: '${json['marketplaceCardId'] ?? ''}'.trim(),
      marketplacePath: '${json['marketplacePath'] ?? ''}'.trim(),
      imageUrl: '${json['imageUrl'] ?? ''}'.trim(),
    );
  }

  final String name;
  final double? count;
  final double? inclusionShare;
  final String section;
  final String setCode;
  final String collectorNumber;
  final String marketplaceCardId;
  final String marketplacePath;
  final String imageUrl;
}

class CompetitiveDeckResult {
  const CompetitiveDeckResult({
    required this.tournamentId,
    required this.tournamentName,
    required this.playerName,
    this.tournamentDate,
    this.format = '',
    this.placing,
    this.placingLabel = '',
    this.variant = '',
    this.playerId = '',
    this.decklistId = '',
    this.sourceUrl = '',
  });

  factory CompetitiveDeckResult.fromJson(Map<String, dynamic> json) {
    return CompetitiveDeckResult(
      tournamentId: '${json['tournamentId'] ?? ''}'.trim(),
      tournamentName: '${json['tournamentName'] ?? ''}'.trim(),
      tournamentDate: DateTime.tryParse('${json['tournamentDate'] ?? ''}'),
      format: '${json['format'] ?? ''}'.trim(),
      placing: (json['placing'] as num?)?.toInt(),
      placingLabel: '${json['placingLabel'] ?? ''}'.trim(),
      variant: '${json['variant'] ?? ''}'.trim(),
      playerId: '${json['playerId'] ?? ''}'.trim(),
      playerName: '${json['playerName'] ?? ''}'.trim(),
      decklistId: '${json['decklistId'] ?? ''}'.trim(),
      sourceUrl: '${json['sourceUrl'] ?? ''}'.trim(),
    );
  }

  final String tournamentId;
  final String tournamentName;
  final DateTime? tournamentDate;
  final String format;
  final int? placing;
  final String placingLabel;
  final String variant;
  final String playerId;
  final String playerName;
  final String decklistId;
  final String sourceUrl;
}

class CompetitiveDeckPlayer {
  const CompetitiveDeckPlayer({
    required this.playerName,
    this.playerId = '',
    this.country = '',
    this.rank,
    this.points = 0,
    this.sourceUrl = '',
  });

  factory CompetitiveDeckPlayer.fromJson(Map<String, dynamic> json) {
    return CompetitiveDeckPlayer(
      playerId: '${json['playerId'] ?? ''}'.trim(),
      playerName: '${json['playerName'] ?? ''}'.trim(),
      country: '${json['country'] ?? ''}'.trim(),
      rank: (json['rank'] as num?)?.toInt(),
      points: (json['points'] as num?)?.toInt() ?? 0,
      sourceUrl: '${json['sourceUrl'] ?? ''}'.trim(),
    );
  }

  final String playerId;
  final String playerName;
  final String country;
  final int? rank;
  final int points;
  final String sourceUrl;
}

class CompetitiveDecklist {
  const CompetitiveDecklist({
    required this.decklistId,
    this.deckId = '',
    this.deckName = '',
    this.format = '',
    this.formatLabel = '',
    this.tournamentId = '',
    this.tournamentName = '',
    this.tournamentDate,
    this.placing,
    this.placingLabel = '',
    this.variant = '',
    this.playerId = '',
    this.playerName = '',
    this.sourceUrl = '',
    this.deckSourceUrl = '',
    this.tournamentSourceUrl = '',
    this.cards = const [],
  });

  factory CompetitiveDecklist.fromJson(Map<String, dynamic> json) {
    return CompetitiveDecklist(
      decklistId: '${json['decklistId'] ?? ''}'.trim(),
      deckId: '${json['deckId'] ?? ''}'.trim(),
      deckName: '${json['deckName'] ?? ''}'.trim(),
      format: '${json['format'] ?? ''}'.trim(),
      formatLabel: '${json['formatLabel'] ?? json['format'] ?? ''}'.trim(),
      tournamentId: '${json['tournamentId'] ?? ''}'.trim(),
      tournamentName: '${json['tournamentName'] ?? ''}'.trim(),
      tournamentDate: DateTime.tryParse('${json['tournamentDate'] ?? ''}'),
      placing: (json['placing'] as num?)?.toInt(),
      placingLabel: '${json['placingLabel'] ?? ''}'.trim(),
      variant: '${json['variant'] ?? ''}'.trim(),
      playerId: '${json['playerId'] ?? ''}'.trim(),
      playerName: '${json['playerName'] ?? ''}'.trim(),
      sourceUrl: '${json['sourceUrl'] ?? ''}'.trim(),
      deckSourceUrl: '${json['deckSourceUrl'] ?? ''}'.trim(),
      tournamentSourceUrl: '${json['tournamentSourceUrl'] ?? ''}'.trim(),
      cards: (json['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveDeckCard.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }

  final String decklistId;
  final String deckId;
  final String deckName;
  final String format;
  final String formatLabel;
  final String tournamentId;
  final String tournamentName;
  final DateTime? tournamentDate;
  final int? placing;
  final String placingLabel;
  final String variant;
  final String playerId;
  final String playerName;
  final String sourceUrl;
  final String deckSourceUrl;
  final String tournamentSourceUrl;
  final List<CompetitiveDeckCard> cards;
}

class CompetitiveDeckDetail {
  const CompetitiveDeckDetail({
    required this.id,
    required this.name,
    this.format = '',
    this.formatLabel = '',
    this.rank,
    this.points = 0,
    this.share = 0,
    this.earningsText = '',
    this.totalPoints = 0,
    this.regionalTop8 = 0,
    this.regionalWins = 0,
    this.internationalTop8 = 0,
    this.internationalWins = 0,
    this.variants = const [],
    this.sourceUrl = '',
    this.updatedAt,
  });

  factory CompetitiveDeckDetail.fromJson(Map<String, dynamic> json) {
    return CompetitiveDeckDetail(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      format: '${json['format'] ?? ''}'.trim(),
      formatLabel: '${json['formatLabel'] ?? json['format'] ?? ''}'.trim(),
      rank: (json['rank'] as num?)?.toInt(),
      points: (json['points'] as num?)?.toInt() ?? 0,
      share: (json['share'] as num?)?.toDouble() ?? 0,
      earningsText: '${json['earningsText'] ?? ''}'.trim(),
      totalPoints: (json['totalPoints'] as num?)?.toInt() ?? 0,
      regionalTop8: (json['regionalTop8'] as num?)?.toInt() ?? 0,
      regionalWins: (json['regionalWins'] as num?)?.toInt() ?? 0,
      internationalTop8: (json['internationalTop8'] as num?)?.toInt() ?? 0,
      internationalWins: (json['internationalWins'] as num?)?.toInt() ?? 0,
      variants: (json['variants'] as List<dynamic>? ?? const [])
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      sourceUrl: '${json['sourceUrl'] ?? ''}'.trim(),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }

  final String id;
  final String name;
  final String format;
  final String formatLabel;
  final int? rank;
  final int points;
  final double share;
  final String earningsText;
  final int totalPoints;
  final int regionalTop8;
  final int regionalWins;
  final int internationalTop8;
  final int internationalWins;
  final List<String> variants;
  final String sourceUrl;
  final DateTime? updatedAt;
}

class CompetitiveSnapshot {
  const CompetitiveSnapshot({
    required this.summary,
    required this.games,
    required this.tournaments,
    this.years = const [],
    this.dashboard = const CompetitiveDashboard(),
    this.selectedDeck,
    this.coreCards = const [],
    this.deckResults = const [],
    this.deckPlayers = const [],
    this.decklists = const [],
    this.selectedDecklist,
    this.decklistCards = const [],
    this.selectedTournament,
    this.standings = const [],
    this.pairings = const [],
  });

  factory CompetitiveSnapshot.fromJson(Map<String, dynamic> json) {
    return CompetitiveSnapshot(
      summary: CompetitiveSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as Map? ?? {}),
      ),
      games: (json['games'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
              (row) => CompetitiveGame.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      tournaments: (json['tournaments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveTournament.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      years: (json['years'] as List<dynamic>? ?? const [])
          .map((year) => (year as num?)?.toInt() ?? 0)
          .where((year) => year > 0)
          .toList(),
      dashboard: CompetitiveDashboard.fromJson(
        Map<String, dynamic>.from(json['dashboard'] as Map? ?? {}),
      ),
      selectedDeck: json['deck'] is Map
          ? CompetitiveDeckDetail.fromJson(
              Map<String, dynamic>.from(json['deck'] as Map),
            )
          : null,
      coreCards: (json['coreCards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveDeckCard.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      deckResults: (json['results'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveDeckResult.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      deckPlayers: (json['players'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveDeckPlayer.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      decklists: (json['decklists'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveDecklist.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      selectedDecklist: json['decklist'] is Map
          ? CompetitiveDecklist.fromJson(
              Map<String, dynamic>.from(json['decklist'] as Map),
            )
          : null,
      decklistCards: (json['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveDeckCard.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      selectedTournament: json['tournament'] is Map
          ? CompetitiveTournament.fromJson(
              Map<String, dynamic>.from(json['tournament'] as Map),
            )
          : null,
      standings: (json['standings'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitiveStanding.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      pairings: (json['pairings'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              CompetitivePairing.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }

  final CompetitiveSummary summary;
  final List<CompetitiveGame> games;
  final List<CompetitiveTournament> tournaments;
  final List<int> years;
  final CompetitiveDashboard dashboard;
  final CompetitiveDeckDetail? selectedDeck;
  final List<CompetitiveDeckCard> coreCards;
  final List<CompetitiveDeckResult> deckResults;
  final List<CompetitiveDeckPlayer> deckPlayers;
  final List<CompetitiveDecklist> decklists;
  final CompetitiveDecklist? selectedDecklist;
  final List<CompetitiveDeckCard> decklistCards;
  final CompetitiveTournament? selectedTournament;
  final List<CompetitiveStanding> standings;
  final List<CompetitivePairing> pairings;
}

class MarketplaceProductFacet {
  const MarketplaceProductFacet({
    required this.productType,
    required this.count,
  });

  factory MarketplaceProductFacet.fromJson(Map<String, dynamic> json) {
    return MarketplaceProductFacet(
      productType:
          '${json['productType'] ?? json['product_type'] ?? ''}'.trim(),
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  final String productType;
  final int count;
}

class SearchCandidateLabel {
  const SearchCandidateLabel({
    required this.id,
    required this.name,
    this.itemKind = 'single',
    this.productType = 'card',
    this.setName = '',
    this.number = '',
    this.trainerName = '',
  });

  factory SearchCandidateLabel.fromJson(Map<String, dynamic> json) {
    return SearchCandidateLabel(
      id: '${json['id'] ?? json['card_id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      itemKind: '${json['itemKind'] ?? json['item_kind'] ?? 'single'}'.trim(),
      productType:
          '${json['productType'] ?? json['product_type'] ?? 'card'}'.trim(),
      setName: '${json['setName'] ?? json['set_name'] ?? ''}'.trim(),
      number: '${json['number'] ?? json['card_number'] ?? ''}'.trim(),
      trainerName:
          '${json['trainerName'] ?? json['trainer_name'] ?? ''}'.trim(),
    );
  }

  final String id;
  final String name;
  final String itemKind;
  final String productType;
  final String setName;
  final String number;
  final String trainerName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (itemKind.isNotEmpty) 'item_kind': itemKind,
        if (productType.isNotEmpty) 'product_type': productType,
        if (setName.isNotEmpty) 'set_name': setName,
        if (number.isNotEmpty) 'card_number': number,
        if (trainerName.isNotEmpty) 'trainer_name': trainerName,
      };
}

class CardSaleEvent {
  const CardSaleEvent({
    required this.cardId,
    required this.condition,
    required this.pricePkn,
    required this.quantity,
    required this.soldAt,
    required this.graded,
    required this.gradingCompany,
    required this.grade,
  });

  factory CardSaleEvent.fromJson(Map<String, dynamic> json) {
    return CardSaleEvent(
      cardId: '${json['cardId'] ?? json['card_id'] ?? ''}'.trim(),
      condition: '${json['condition'] ?? 'NM'}'.trim(),
      pricePkn: (json['pricePkn'] as num?)?.toDouble() ??
          (json['price_pkn'] as num?)?.toDouble() ??
          0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      soldAt: DateTime.tryParse('${json['soldAt'] ?? json['sold_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      graded: json['graded'] == true,
      gradingCompany:
          '${json['gradingCompany'] ?? json['grading_company'] ?? ''}'.trim(),
      grade: '${json['grade'] ?? ''}'.trim(),
    );
  }

  final String cardId;
  final String condition;
  final double pricePkn;
  final int quantity;
  final DateTime soldAt;
  final bool graded;
  final String gradingCompany;
  final String grade;
}

class MarketplaceBlueprintPrice {
  const MarketplaceBlueprintPrice({
    required this.cardId,
    required this.blueprintId,
    required this.pricePkn,
    required this.source,
    required this.listingCount,
    required this.listedQuantity,
    this.updatedAt,
  });

  factory MarketplaceBlueprintPrice.fromJson(Map<String, dynamic> json) {
    final price = (json['price_pkn'] as num?)?.toDouble() ??
        (json['pricePkn'] as num?)?.toDouble();
    return MarketplaceBlueprintPrice(
      cardId: '${json['card_id'] ?? json['cardId'] ?? ''}'.trim(),
      blueprintId:
          '${json['blueprint_id'] ?? json['blueprintId'] ?? ''}'.trim(),
      pricePkn: price,
      source: '${json['source'] ?? ''}'.trim(),
      listingCount: (json['listing_count'] as num?)?.toInt() ??
          (json['listingCount'] as num?)?.toInt() ??
          0,
      listedQuantity: (json['listed_quantity'] as num?)?.toInt() ??
          (json['listedQuantity'] as num?)?.toInt() ??
          0,
      updatedAt:
          DateTime.tryParse('${json['updated_at'] ?? json['updatedAt'] ?? ''}'),
    );
  }

  final String cardId;
  final String blueprintId;
  final double? pricePkn;
  final String source;
  final int listingCount;
  final int listedQuantity;
  final DateTime? updatedAt;

  bool get hasPrice => pricePkn != null && pricePkn! > 0;
}

class SearchAutocompleteContext {
  const SearchAutocompleteContext({
    required this.query,
    required this.language,
    required this.cardIds,
    required this.createdAtMs,
    required this.strategy,
    this.candidateIdLadder = const {},
    this.depthScores = const {},
    this.latestDepths = const {},
    this.latestOrders = const {},
    this.nonNameContext = const {},
    this.candidateLabels = const [],
    this.predictedNameTokens = const [],
  });

  factory SearchAutocompleteContext.fromJson(Map<String, dynamic> json) {
    final cardIds = (json['card_ids'] as List<dynamic>? ?? const [])
        .map((id) => '$id'.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .take(5000)
        .toList(growable: false);
    final nonNameContext = json['non_name_context'] is Map
        ? Map<String, dynamic>.from(json['non_name_context'] as Map)
        : const <String, dynamic>{};
    final cardIdSet = cardIds.toSet();
    final depthScores = _depthScoresFromContext(nonNameContext, cardIdSet);
    final latestDepths = _latestDepthsFromContext(nonNameContext, cardIdSet);
    final latestOrders = _latestOrdersFromContext(nonNameContext, cardIdSet);
    final normalizedNonNameContext = _nonNameContextWithDepthScores(
      nonNameContext,
      depthScores,
      latestDepths,
      latestOrders,
    );
    return SearchAutocompleteContext(
      query: '${json['query'] ?? ''}',
      language: '${json['language'] ?? 'en'}',
      cardIds: cardIds,
      createdAtMs: (json['created_at_ms'] as num?)?.toInt() ?? 0,
      strategy: '${json['strategy'] ?? ''}',
      candidateIdLadder: _stringKeyedIntMap(json['candidate_id_ladder']),
      depthScores: depthScores,
      latestDepths: latestDepths,
      latestOrders: latestOrders,
      nonNameContext: normalizedNonNameContext,
      candidateLabels: _candidateLabelsFromJson(json['candidate_labels'],
          limit: cardIds.length),
      predictedNameTokens:
          _predictedNameTokensFromContext(normalizedNonNameContext),
    );
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'language': language,
        'card_ids': cardIds,
        'created_at_ms': createdAtMs,
        'strategy': strategy,
        if (candidateIdLadder.isNotEmpty)
          'candidate_id_ladder': candidateIdLadder,
        if (nonNameContext.isNotEmpty) 'non_name_context': nonNameContext,
        if (candidateLabels.isNotEmpty)
          'candidate_labels':
              candidateLabels.map((label) => label.toJson()).toList(),
      };

  bool canRefine(String nextQuery, String nextLanguage) {
    final normalizedNext = nextQuery.trim();
    return cardIds.isNotEmpty &&
        normalizedNext.startsWith(query) &&
        normalizedNext != query &&
        language == nextLanguage &&
        DateTime.now().millisecondsSinceEpoch - createdAtMs < 60000;
  }

  final String query;
  final String language;
  final List<String> cardIds;
  final int createdAtMs;
  final String strategy;
  final Map<String, int> candidateIdLadder;
  final Map<String, int> depthScores;
  final Map<String, int> latestDepths;
  final Map<String, int> latestOrders;
  final Map<String, dynamic> nonNameContext;
  final List<SearchCandidateLabel> candidateLabels;
  final List<SearchPredictedNameToken> predictedNameTokens;
}

class SearchPredictedNameToken {
  const SearchPredictedNameToken({
    required this.normalized,
    required this.display,
    this.confidence = 0,
    this.sourceRank = 0,
    this.language = '',
    this.source = '',
    this.nameFragment = '',
    this.representativeCardIds = const [],
    this.representativeLabels = const [],
  });

  factory SearchPredictedNameToken.fromJson(
    Map<String, dynamic> json, {
    String source = '',
  }) {
    final jsonSource = '${json['source'] ?? source}'.trim();
    return SearchPredictedNameToken(
      normalized:
          '${json['normalized'] ?? json['normalized_token'] ?? ''}'.trim(),
      display: '${json['display'] ?? json['display_token'] ?? ''}'.trim(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      sourceRank: (json['source_rank'] as num?)?.toInt() ?? 0,
      language: '${json['language'] ?? ''}'.trim(),
      source: jsonSource,
      nameFragment:
          '${json['name_fragment'] ?? json['nameFragment'] ?? ''}'.trim(),
      representativeCardIds:
          _stringListFromJson(json['representative_card_ids']),
      representativeLabels: _candidateLabelsFromJson(
        json['representative_labels'],
        limit: 8,
      ),
    );
  }

  final String normalized;
  final String display;
  final double confidence;
  final int sourceRank;
  final String language;
  final String source;
  final String nameFragment;
  final List<String> representativeCardIds;
  final List<SearchCandidateLabel> representativeLabels;

  Map<String, dynamic> toJson() => {
        'normalized': normalized,
        'display': display,
        if (confidence > 0) 'confidence': confidence,
        if (sourceRank > 0) 'source_rank': sourceRank,
        if (language.isNotEmpty) 'language': language,
        if (source.isNotEmpty) 'source': source,
        if (nameFragment.isNotEmpty) 'name_fragment': nameFragment,
        if (representativeCardIds.isNotEmpty)
          'representative_card_ids': representativeCardIds,
        if (representativeLabels.isNotEmpty)
          'representative_labels':
              representativeLabels.map((label) => label.toJson()).toList(),
      };

  bool get isStructuredDimension =>
      source == 'oracle_dimension_alias' || source.startsWith('oracle_');
}

class SearchTokenPredictionContext {
  const SearchTokenPredictionContext({
    required this.query,
    required this.fragment,
    required this.normalizedFragment,
    required this.language,
    required this.createdAtMs,
    this.predictionFragment = '',
    this.depth = 0,
    this.source = '',
    this.candidates = const [],
  });

  factory SearchTokenPredictionContext.fromJson(Map<String, dynamic> json) {
    return SearchTokenPredictionContext(
      query: '${json['query'] ?? ''}'.trim(),
      fragment: '${json['fragment'] ?? ''}'.trim(),
      predictionFragment:
          '${json['prediction_fragment'] ?? json['predictionFragment'] ?? ''}'
              .trim(),
      normalizedFragment:
          '${json['normalized_fragment'] ?? json['normalizedFragment'] ?? ''}'
              .trim(),
      language: '${json['language'] ?? json['search_language'] ?? ''}'.trim(),
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      createdAtMs: (json['created_at_ms'] as num?)?.toInt() ??
          (json['createdAtMs'] as num?)?.toInt() ??
          0,
      source: '${json['source'] ?? ''}'.trim(),
      candidates: _predictedNameTokensFromJson(
        json['candidates'],
        source: 'token_predict.context',
        limit: 20,
      ),
    );
  }

  final String query;
  final String fragment;
  final String predictionFragment;
  final String normalizedFragment;
  final String language;
  final int depth;
  final int createdAtMs;
  final String source;
  final List<SearchPredictedNameToken> candidates;

  Map<String, dynamic> toJson() => {
        'query': query,
        'fragment': fragment,
        if (predictionFragment.isNotEmpty)
          'prediction_fragment': predictionFragment,
        'normalized_fragment': normalizedFragment,
        'language': language,
        if (depth > 0) 'depth': depth,
        'created_at_ms': createdAtMs,
        if (source.isNotEmpty) 'source': source,
        'candidates':
            candidates.map((candidate) => candidate.toJson()).toList(),
      };

  bool canRefine(String nextQuery, String nextLanguage) {
    final normalizedNext = _compactTokenPredictionText(nextQuery);
    return normalizedFragment.isNotEmpty &&
        candidates.isNotEmpty &&
        normalizedNext.startsWith(normalizedFragment) &&
        normalizedNext != normalizedFragment &&
        language.toLowerCase() == nextLanguage.toLowerCase() &&
        DateTime.now().millisecondsSinceEpoch - createdAtMs < 60000;
  }
}

String _compactTokenPredictionText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class SearchTokenPredictionResult {
  const SearchTokenPredictionResult({
    this.tokens = const [],
    this.context,
  });

  final List<SearchPredictedNameToken> tokens;
  final SearchTokenPredictionContext? context;
}

class SearchFirstCharWarmupResult {
  const SearchFirstCharWarmupResult({
    required this.language,
    required this.generatedAtMs,
    this.sourceLanguage = '',
    this.suggestions = const {},
  });

  factory SearchFirstCharWarmupResult.fromJson(Map<String, dynamic> json) {
    final suggestionsJson = json['suggestions'];
    final suggestions = <String, SearchPredictedNameToken>{};
    if (suggestionsJson is Map) {
      suggestionsJson.forEach((key, value) {
        final letter = _compactTokenPredictionText('$key');
        if (letter.length != 1 || value is! Map) {
          return;
        }
        final token = SearchPredictedNameToken.fromJson(
          Map<String, dynamic>.from(value),
          source: 'first_char_warmup',
        );
        if (token.normalized.isNotEmpty && token.display.isNotEmpty) {
          suggestions[letter] = token;
        }
      });
    }
    return SearchFirstCharWarmupResult(
      language: '${json['language'] ?? ''}'.trim(),
      sourceLanguage:
          '${json['source_language'] ?? json['sourceLanguage'] ?? ''}'.trim(),
      generatedAtMs: (json['generated_at_ms'] as num?)?.toInt() ??
          (json['generatedAtMs'] as num?)?.toInt() ??
          0,
      suggestions: Map.unmodifiable(suggestions),
    );
  }

  final String language;
  final String sourceLanguage;
  final int generatedAtMs;
  final Map<String, SearchPredictedNameToken> suggestions;
}

List<String> _stringListFromJson(Object? value, {int limit = 8}) {
  if (value is! List) {
    return const [];
  }
  return List.unmodifiable(value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .take(limit));
}

List<SearchCandidateLabel> _candidateLabelsFromJson(
  Object? value, {
  required int limit,
}) {
  if (value is! List) {
    return const [];
  }
  final labels = <SearchCandidateLabel>[];
  final seen = <String>{};
  for (final item in value.whereType<Map>()) {
    final label = SearchCandidateLabel.fromJson(
      Map<String, dynamic>.from(item),
    );
    if (label.id.isEmpty || label.name.isEmpty || !seen.add(label.id)) {
      continue;
    }
    labels.add(label);
    if (labels.length >= math.min(math.max(limit, 0), 10000)) {
      break;
    }
  }
  return List.unmodifiable(labels);
}

Map<String, int> _stringKeyedIntMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final mapped = <String, int>{};
  for (final entry in value.entries) {
    final key = '${entry.key}'.trim();
    final numeric = entry.value is num
        ? (entry.value as num).toInt()
        : int.tryParse('${entry.value}');
    if (key.isNotEmpty && numeric != null) {
      mapped[key] = numeric;
    }
  }
  return Map.unmodifiable(mapped);
}

Map<String, int> _depthScoresFromContext(
  Map<String, dynamic> nonNameContext,
  Set<String> cardIds,
) {
  return _boundedContextIntMap(
    nonNameContext['depth_scores'],
    cardIds,
    maxValue: 512,
  );
}

Map<String, int> _latestDepthsFromContext(
  Map<String, dynamic> nonNameContext,
  Set<String> cardIds,
) {
  return _boundedContextIntMap(
    nonNameContext['latest_depths'],
    cardIds,
    maxValue: 512,
  );
}

Map<String, int> _latestOrdersFromContext(
  Map<String, dynamic> nonNameContext,
  Set<String> cardIds,
) {
  return _boundedContextIntMap(
    nonNameContext['latest_orders'],
    cardIds,
    minValue: 0,
    maxValue: 10000,
  );
}

Map<String, int> _boundedContextIntMap(
  Object? rawValue,
  Set<String> cardIds, {
  int minValue = 1,
  required int maxValue,
}) {
  if (rawValue is! Map) {
    return const {};
  }
  final values = <String, int>{};
  for (final entry in rawValue.entries) {
    final id = '${entry.key}'.trim();
    if (id.isEmpty || !cardIds.contains(id)) {
      continue;
    }
    final value = entry.value is num
        ? (entry.value as num).toInt()
        : int.tryParse('${entry.value}');
    if (value == null || value < minValue) {
      continue;
    }
    values[id] = math.min(value, maxValue);
  }
  return Map.unmodifiable(values);
}

Map<String, dynamic> _nonNameContextWithDepthScores(
  Map<String, dynamic> nonNameContext,
  Map<String, int> depthScores,
  Map<String, int> latestDepths,
  Map<String, int> latestOrders,
) {
  if (nonNameContext.isEmpty &&
      depthScores.isEmpty &&
      latestDepths.isEmpty &&
      latestOrders.isEmpty) {
    return const {};
  }
  final normalized = Map<String, dynamic>.from(nonNameContext)
    ..remove('depth_scores')
    ..remove('latest_depths')
    ..remove('latest_orders');
  if (depthScores.isNotEmpty) {
    normalized['depth_scores'] = depthScores;
  }
  if (latestDepths.isNotEmpty) {
    normalized['latest_depths'] = latestDepths;
  }
  if (latestOrders.isNotEmpty) {
    normalized['latest_orders'] = latestOrders;
  }
  return Map.unmodifiable(normalized);
}

List<SearchPredictedNameToken> _predictedNameTokensFromContext(
  Map<String, dynamic> nonNameContext,
) {
  final predictivePool = nonNameContext['predictive_pool'];
  if (predictivePool is! Map) {
    return const [];
  }
  return _predictedNameTokensFromJson(
    predictivePool['predicted_tokens'] ?? predictivePool['predictedTokens'],
    source: 'search_context.predictive_pool',
  );
}

List<SearchPredictedNameToken> _predictedNameTokensFromJson(
  Object? value, {
  String source = '',
  int limit = 8,
}) {
  if (value is! List) {
    return const [];
  }
  final tokens = <SearchPredictedNameToken>[];
  final seen = <String>{};
  for (final item in value.whereType<Map>()) {
    final token = SearchPredictedNameToken.fromJson(
      Map<String, dynamic>.from(item),
      source: source,
    );
    final normalized = token.normalized;
    final display = token.display;
    if (normalized.isEmpty || display.isEmpty || !seen.add(normalized)) {
      continue;
    }
    tokens.add(token);
    if (tokens.length >= limit) {
      break;
    }
  }
  return List.unmodifiable(tokens);
}

class SearchAutocompleteResult {
  const SearchAutocompleteResult({
    required this.cards,
    this.context,
    this.poolSize = 0,
    this.poolSource = '',
    this.predictedNameTokens = const [],
  });

  final List<PokemonCard> cards;
  final SearchAutocompleteContext? context;
  final int poolSize;
  final String poolSource;
  final List<SearchPredictedNameToken> predictedNameTokens;
}

class CardService {
  // Local storage
  static const String _cardsBoxName = 'pokemon_cards';
  static const String _homeSnapshotBoxName = 'marketplace_home_snapshot';
  static const String _homeSnapshotKey = 'snapshot_v3_cdn_hero';
  static const String _spotlightCardsKey = 'spotlightCards';
  static const String _listCacheBoxName = 'marketplace_card_list_cache';
  static const String _cacheMetaBoxName = 'pokoin_cache_meta';
  static const String _cacheSchemaKey = 'schemaVersion';
  static const String _cacheCachedAtKey = 'cachedAtMs';
  static const int _cacheSchemaVersion = 2;
  static const Duration _catalogCacheTtl = Duration(days: 7);
  static const Duration _homeSnapshotCacheTtl = Duration(minutes: 2);
  static const Duration _detailCacheTtl = Duration(days: 7);
  static const Duration _listCacheTtl = Duration(days: 3);
  static const Map<String, double> _pknPrices = <String, double>{
    '1': 495,
    '2': 149995,
    '3': 99995,
    '4': 74995,
    '5': 44995,
    '6': 39995,
  };
  static const int catalogPageSize = 500;
  static const Map<String, String> _raritySearchAliases = {
    'goldstar': 'gold star',
    'shiningrare': 'shining rare',
    'shinystar': 'shiny star',
    'ill': 'illustration rare',
    'illus': 'illustration rare',
    'illustrationrare': 'illustration rare',
    'specialillustrationrare': 'special illustration rare',
    'amazingerare': 'amazing rare',
    'radiantrare': 'radiant rare',
    'ultrarare': 'ultra rare',
    'secretrare': 'secret rare',
    'hyperrare': 'hyper rare',
    'doublerare': 'double rare',
    'rareholo': 'rare holo',
    'holographicrare': 'holographic rare',
    'holorare': 'holo rare',
  };
  static const Map<String, String> _trainerSearchAliases = {
    'camilla': 'cynthia',
    'cynthia': 'cynthia',
    'shirona': 'cynthia',
    'n': 'n',
    'lance': 'lance',
    'camus': 'lance',
    'misty': 'misty',
    'ondine': 'misty',
    'kasumi': 'misty',
    'brock': 'brock',
    'pierre': 'brock',
    'takeshi': 'brock',
    'erika': 'erika',
    'giovanni': 'giovanni',
    'sabrina': 'sabrina',
    'sandra': 'clair',
    'clair': 'clair',
    'iris': 'iris',
    'steven': 'steven',
    'rochard': 'steven',
    'diantha': 'diantha',
    'lilia': 'lillie',
    'lillie': 'lillie',
    'gladio': 'gladion',
    'gladion': 'gladion',
    'marnie': 'marnie',
    'mary': 'marnie',
    'hop': 'hop',
    'dandel': 'leon',
    'leon': 'leon',
    'roy': 'raihan',
    'raihan': 'raihan',
    'nemona': 'nemona',
    'peonia': 'peonia',
    'iono': 'iono',
    'kissara': 'iono',
  };
  static const Set<String> _ownershipStopWords = {
    'di',
    'de',
    'del',
    'della',
    'da',
    'du',
    'des',
    'of',
    'the',
    'owned',
    'owner',
  };

  Future<void> _initHive() async {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PokemonCardAdapter());
    }
  }

  Future<List<PokemonCard>> getAllCards() async {
    await _initHive();

    try {
      final marketplaceCards = await _getMarketplaceCards();
      if (marketplaceCards.isNotEmpty) {
        await _saveCardsToLocal(marketplaceCards);
        return marketplaceCards;
      }

      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      if (box.isNotEmpty) {
        final cards = _normalizeCards(box.values.toList());
        return cards;
      }

      final cards = _getSampleCards();
      await _saveCardsToLocal(cards);
      return cards;
    } catch (e) {
      debugPrint('Error getting cards: $e');
      return _getSampleCards();
    }
  }

  Future<List<PokemonCard>> getCachedCards() async {
    await _initHive();
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final metadata = await _cacheMetadata('cards');
      final hasLegacyCards = metadata == null && box.isNotEmpty;
      if (!_cacheMapIsUsable(metadata, _catalogCacheTtl,
          allowLegacy: hasLegacyCards)) {
        return const [];
      }
      if (hasLegacyCards) {
        await _writeCacheMetadata('cards');
      }
      return _normalizeCards(box.values.toList());
    } catch (error) {
      debugPrint('Cached cards load failed: $error');
      return const [];
    }
  }

  Future<MarketplaceHomeSnapshot?> getCachedMarketplaceHomeSnapshot() async {
    try {
      final box = await Hive.openBox<Map>(_homeSnapshotBoxName);
      final cached = box.get(_homeSnapshotKey);
      if (cached == null) {
        return null;
      }
      final data = Map<String, dynamic>.from(cached);
      final hasLegacySnapshot = data[_cacheSchemaKey] == null;
      if (!_cacheMapIsUsable(
        data,
        _homeSnapshotCacheTtl,
        allowLegacy: hasLegacySnapshot,
      )) {
        return null;
      }
      if (hasLegacySnapshot) {
        await box.put(_homeSnapshotKey, _withCacheMeta(data));
      }
      return _homeSnapshotFromMap(data);
    } catch (error) {
      debugPrint('Cached marketplace home snapshot failed: $error');
      return null;
    }
  }

  Future<List<PokemonCard>> getCachedSpotlightCards() async {
    return _cachedCardList(_spotlightCardsKey);
  }

  Future<MarketplaceHomeSnapshot?> getMarketplaceHomeSnapshot() async {
    try {
      final response = await _getMarketplaceHomeResponse();
      if (response == null || response.statusCode >= 400) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final snapshot = _homeSnapshotFromMap(data);
      await _saveMarketplaceHomeSnapshot(snapshot);
      if (snapshot.cards.isNotEmpty) {
        await _mergeCardsToLocal(snapshot.cards);
        await _saveSpotlightCardsFromSnapshot(snapshot);
      }
      return snapshot;
    } catch (error) {
      debugPrint('Marketplace home snapshot failed: $error');
      return null;
    }
  }

  MarketplaceHomeSnapshot _homeSnapshotFromMap(Map<String, dynamic> data) {
    final cards = (data['cards'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => PokemonCard.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    final sectionData =
        Map<String, dynamic>.from(data['sections'] as Map? ?? {});
    return MarketplaceHomeSnapshot(
      cards: cards,
      sections: MarketplaceHomeSections(
        recentlySeenIds: _stringList(sectionData['recentlySeenIds']),
        bestSellerIds: _stringList(sectionData['bestSellerIds']),
        featuredIds: _stringList(sectionData['featuredIds']),
        newArrivalIds: _stringList(sectionData['newArrivalIds']),
      ),
    );
  }

  Future<void> _saveMarketplaceHomeSnapshot(
    MarketplaceHomeSnapshot snapshot,
  ) async {
    try {
      final box = await Hive.openBox<Map>(_homeSnapshotBoxName);
      await box.put(_homeSnapshotKey, _withCacheMeta(snapshot.toJson()));
    } catch (error) {
      debugPrint('Marketplace home cache save failed: $error');
    }
  }

  Future<void> _saveSpotlightCardsFromSnapshot(
    MarketplaceHomeSnapshot snapshot,
  ) async {
    final byId = {
      for (final card in snapshot.cards)
        if (card.id.isNotEmpty) card.id: card,
    };
    final orderedIds = [
      ...snapshot.sections.featuredIds,
      ...snapshot.sections.bestSellerIds,
      ...snapshot.sections.recentlySeenIds,
    ];
    final seen = <String>{};
    final cards = <PokemonCard>[];
    for (final id in orderedIds) {
      if (seen.add(id)) {
        final card = byId[id];
        if (card != null &&
            card.itemKind != 'product' &&
            card.productType == 'card') {
          cards.add(card);
        }
      }
    }
    for (final card in snapshot.cards) {
      if (cards.length >= 48) {
        break;
      }
      if (card.id.isNotEmpty &&
          seen.add(card.id) &&
          card.itemKind != 'product' &&
          card.productType == 'card') {
        cards.add(card);
      }
    }
    await _saveCardList(_spotlightCardsKey, cards.take(48).toList());
  }

  Future<http.Response?> _getMarketplaceHomeResponse() {
    final uri = Uri.base.resolve('/api/marketplace-home');
    return http.get(uri).timeout(const Duration(seconds: 8));
  }

  Future<Map<String, MarketplaceCheapestPrice>> getCheapestPricesForCardIds(
    Iterable<String> cardIds,
  ) async {
    final querySets = marketplaceCheapestPriceQueriesForTest(cardIds);
    if (querySets.isEmpty) {
      return const {};
    }
    final pricesById = <String, MarketplaceCheapestPrice>{};
    for (final queryParameters in querySets) {
      try {
        final uri = Uri.base
            .resolve('/api/marketplace-card-cheapest-price')
            .replace(queryParameters: queryParameters);
        final response =
            await http.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode >= 400) {
          debugPrint(
              'Marketplace cheapest price load failed: ${response.statusCode}');
          continue;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final prices = (data['prices'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((row) => MarketplaceCheapestPrice.fromJson(
                  Map<String, dynamic>.from(row),
                ))
            .where((price) => price.cardId.isNotEmpty)
            .toList();
        for (final price in prices) {
          pricesById.putIfAbsent(price.cardId, () => price);
        }
      } catch (error) {
        debugPrint('Marketplace cheapest price load failed: $error');
        continue;
      }
    }
    return pricesById;
  }

  @visibleForTesting
  Map<String, String> marketplaceCheapestPriceQueryForTest(
    Iterable<String> cardIds,
  ) {
    final queries = marketplaceCheapestPriceQueriesForTest(cardIds);
    return queries.isEmpty ? const {} : queries.first;
  }

  @visibleForTesting
  List<Map<String, String>> marketplaceCheapestPriceQueriesForTest(
    Iterable<String> cardIds,
  ) {
    final ids = <String>[];
    final canonicalPaths = <String>[];
    final structuredQueries = <Map<String, String>>[];
    final seenIds = <String>{};
    final seenPaths = <String>{};
    final seenStructured = <String>{};
    for (final rawValue in cardIds) {
      final value = rawValue.trim();
      if (value.isEmpty) {
        continue;
      }
      if (value.startsWith('/marketplace/') && value.contains('/cards/')) {
        if (seenPaths.add(value)) {
          canonicalPaths.add(value);
        }
        final publicNumber = _publicNumberFromMarketplacePath(value);
        final internalId = cardIdFromDoubledId(publicNumber);
        for (final id in [publicNumber, internalId]) {
          if (id.isNotEmpty && seenIds.add(id) && ids.length < 50) {
            ids.add(id);
          }
        }
      } else if (RegExp(r'^[0-9]+$').hasMatch(value) &&
          seenIds.add(value) &&
          ids.length < 50) {
        ids.add(value);
      } else if (value.startsWith('structured:') &&
          seenStructured.add(value) &&
          structuredQueries.length < 9) {
        final query = _structuredCheapestLookupQuery(value);
        if (query.isNotEmpty) {
          structuredQueries.add(query);
        }
      }
      if (ids.length >= 50) {
        break;
      }
    }
    final primaryQuery = {
      if (ids.isNotEmpty) 'cardIds': ids.join(','),
      if (canonicalPaths.isNotEmpty) 'canonicalPath': canonicalPaths.first,
    };
    return [
      if (primaryQuery.isNotEmpty) primaryQuery,
      ...structuredQueries,
    ];
  }

  static String _publicNumberFromMarketplacePath(String canonicalPath) {
    final match = RegExp(r'/cards/([0-9]+)(?:/|$)').firstMatch(canonicalPath);
    return match?.group(1) ?? '';
  }

  static Map<String, String> _structuredCheapestLookupQuery(String value) {
    final parts = value.substring('structured:'.length).split('|');
    if (parts.length != 3) {
      return const {};
    }
    final name = parts[0].trim();
    final setName = parts[1].trim();
    final number = parts[2].trim();
    if (name.isEmpty || (setName.isEmpty && number.isEmpty)) {
      return const {};
    }
    return {
      'name': name,
      if (setName.isNotEmpty) 'setName': setName,
      if (number.isNotEmpty) 'number': number,
      'limit': '1',
    };
  }

  static List<String> _stringList(Object? value) {
    return (value as List<dynamic>? ?? const [])
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  @visibleForTesting
  PokemonCard cardFromBlueprintForTest(Map<String, dynamic> row) {
    return _cardFromBlueprint(row);
  }

  @visibleForTesting
  PokemonCard cardFromVersionRowForTest(Map<String, dynamic> row) {
    return _cardFromVersionRow(row);
  }

  @visibleForTesting
  PokemonCard cardFromMarketplaceRowForTest(Map<String, dynamic> row) {
    return _cardFromMarketplaceRow(row);
  }

  @visibleForTesting
  List<PokemonCard> rankSearchCandidatesForTest(
    List<PokemonCard> cards,
    String query, {
    int limit = 20,
  }) {
    return _rankLocalCards(cards, query, limit);
  }

  @visibleForTesting
  List<PokemonCard> searchCandidateCardsFromRowsForTest(
    List<Map<String, dynamic>> rows, {
    int limit = 20,
  }) {
    return _dedupeCards(rows.map(_cardFromSearchCandidate).toList())
        .take(limit)
        .toList();
  }

  @visibleForTesting
  List<PokemonCard> searchAutocompletePreviewCardsFromRowsForTest(
    List<Map<String, dynamic>> rows, {
    int limit = 20,
  }) {
    return _searchAutocompletePreviewCardsFromRows(rows, limit);
  }

  @visibleForTesting
  List<SearchPredictedNameToken> predictedNameTokensFromJsonForTest(
    Object? value, {
    String source = 'token_predict',
  }) {
    return _predictedNameTokensFromJson(value, source: source);
  }

  @visibleForTesting
  SearchFirstCharWarmupResult firstCharWarmupResultFromJsonForTest(
    Map<String, dynamic> json,
  ) {
    return SearchFirstCharWarmupResult.fromJson(json);
  }

  @visibleForTesting
  List<String> searchQueryVariantsForTest(String query) {
    return _searchQueryVariants([query]);
  }

  @visibleForTesting
  Map<String, dynamic> searchCancelPayloadForTest({
    required String sessionId,
    required String lastQuery,
    String reason = 'exit',
  }) {
    return _searchCancelPayload(
      sessionId: sessionId,
      lastQuery: lastQuery,
      reason: reason,
    );
  }

  @visibleForTesting
  List<PokemonCard> excludeSimilarVersionCardsForTest(
    PokemonCard current,
    List<PokemonCard> versionCards,
    List<PokemonCard> similarCards,
  ) {
    return _excludeVersionBlueprintCards(
      current,
      versionCards,
      similarCards,
    );
  }

  Future<List<PokemonCard>> _getMarketplaceCards() async {
    try {
      final uri = Uri.base.resolve('/api/marketplace-cards').replace(
        queryParameters: {'limit': '$catalogPageSize'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 400) {
        debugPrint('Marketplace cards load failed: ${response.statusCode}');
        return const [];
      }

      final rows = jsonDecode(response.body) as List<dynamic>;
      return _normalizeCards(rows
          .whereType<Map>()
          .map((row) => _cardFromMarketplaceRow(Map<String, dynamic>.from(row)))
          .toList());
    } catch (error) {
      debugPrint('Marketplace cards load failed: $error');
      return const [];
    }
  }

  PokemonCard _cardFromMarketplaceRow(Map<String, dynamic> row) {
    final id = '${row['card_id'] ?? row['id'] ?? ''}';
    final rarity = _cleanLabel(row['rarity'], fallback: 'Card');
    final setName = _cleanLabel(row['set_name'], fallback: 'Pokemon');
    final rawNumber = '${row['card_number'] ?? ''}';
    final productVariant = '${row['product_variant'] ?? row['version'] ?? ''}';
    final itemKind = _itemKindForProjectedRow(
      itemKind: row['item_kind'],
      productType: row['product_type'],
      number: rawNumber,
    );
    final productType = _productTypeForProjectedRow(
      productType: row['product_type'],
      itemKind: itemKind,
      number: rawNumber,
    );
    final number = itemKind == 'product' ? productVariant : rawNumber;
    final trainerName = _cleanLabel(row['trainer_name'], fallback: '');
    final type = _marketplaceDisplayType(
      productType,
      fallback: _cleanLabel(row['card_type'], fallback: 'Card'),
    );
    final imageUrl =
        _normalizeImageUrl(row['cdn_image_url'] ?? row['image_url'], cardId: id, ctId: row['ct_id'] ?? row['ctId']);
    final previewImageUrl = _normalizeImageUrl(
      row['preview_image_url'] ?? row['cdn_image_url'] ?? row['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'],
    );
    final homepageImageUrl = _normalizeImageUrl(
      row['homepage_image_url'] ??
          row['homepageImageUrl'] ??
          row['preview_image_url'] ??
          row['cdn_image_url'] ??
          row['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'],
    );
    final listedQuantity = (row['listed_quantity'] as num?)?.toInt() ?? 0;
    final listedPrice = _readMarketplaceTilePrice(row);
    final hasCardTraderListing = _readCardTraderAvailability(row);
    final cardTraderListingCount = _readCardTraderEligibleListingCount(row);
    final isGraded = _readBoolish(
      row['isGraded'] ?? row['is_graded'] ?? row['graded'],
    );
    final artist = _cleanLabel(
      row['artist'] ?? row['illustrator'],
      fallback: '',
    );
    return PokemonCard(
      id: id,
      name: '${row['name'] ?? 'Pokemon card'}',
      imageUrl: imageUrl,
      previewImageUrl: previewImageUrl,
      homepageImageUrl: homepageImageUrl,
      rarity: rarity,
      type: type,
      hp: 0,
      attacks: const [],
      price: listedPrice ?? 0,
      description: itemKind == 'product'
          ? 'Imported from the Pokoin marketplace product projection.'
          : 'Imported from the Pokoin marketplace projection. Full blueprint data is loaded on card detail.',
      set: setName,
      number: number,
      artist: artist,
      stock: listedQuantity,
      rating: _readWatchlistCount(row).toDouble(),
      reviewCount: 0,
      isFoil: row['is_foil'] == true,
      isHolo: row['is_holo'] == true,
      releaseDate: _parseDate(row['imported_at']),
      tags: [
        setName,
        rarity,
        type,
        itemKind,
        productType,
        if (trainerName.isNotEmpty) trainerName,
      ],
      condition: 'NM',
      isGraded: isGraded,
      grade: _cleanLabel(row['grade'], fallback: ''),
      gradingCompany: _cleanLabel(
        row['gradingCompany'] ?? row['grading_company'],
        fallback: '',
      ),
      itemKind: itemKind,
      productType: productType,
      trainerName: trainerName,
      expansionSymbolUrl: _normalizeImageUrl(row['expansion_symbol_url']),
      expansionLogoUrl: _normalizeImageUrl(row['expansion_logo_url']),
      canonicalPath: _cleanCanonicalPath(row),
      hasCardTraderListing: hasCardTraderListing,
      cardtraderEligibleListingCount: cardTraderListingCount,
      watchlistCount: _readWatchlistCount(row),
      cartHolderCount: _readCartHolderCount(row),
      cardPalette: _readCardPalette(row),
      emoji: _readEmoji(row),
    );
  }

  PokemonCard _cardFromVersionRow(Map<String, dynamic> row) {
    final id = '${row['card_id'] ?? row['id'] ?? ''}';
    final setName = _cleanLabel(row['expansion_name'], fallback: 'Pokemon');
    final rawNumber = '${row['expansion_number'] ?? ''}';
    final productVariant = '${row['product_variant'] ?? ''}';
    final itemKind = _itemKindForProjectedRow(
      itemKind: row['item_kind'],
      productType: row['product_type'],
      number: rawNumber,
    );
    final productType = _productTypeForProjectedRow(
      productType: row['product_type'],
      itemKind: itemKind,
      number: rawNumber,
    );
    final number = itemKind == 'product' ? productVariant : rawNumber;
    final rarity = _cleanLabel(row['rarity'], fallback: 'Card');
    final type = _marketplaceDisplayType(
      productType,
      fallback: _cleanLabel(row['card_type'], fallback: 'Card'),
    );
    final trainerName = _cleanLabel(row['trainer_name'], fallback: '');
    final imageUrl =
        _normalizeImageUrl(row['cdn_image_url'] ?? row['image_url'], cardId: id, ctId: row['ct_id'] ?? row['ctId']);
    final previewImageUrl = _normalizeImageUrl(
      row['preview_image_url'] ?? row['cdn_image_url'] ?? row['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'],
    );
    final homepageImageUrl = _normalizeImageUrl(
      row['homepage_image_url'] ??
          row['homepageImageUrl'] ??
          row['preview_image_url'] ??
          row['cdn_image_url'] ??
          row['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'],
    );
    final listedQuantity = (row['listed_quantity'] as num?)?.toInt() ?? 0;
    final listedPrice = _readMarketplaceTilePrice(row);
    final hasCardTraderListing = _readCardTraderAvailability(row);
    final cardTraderListingCount = _readCardTraderEligibleListingCount(row);
    final isGraded = _readBoolish(
      row['isGraded'] ?? row['is_graded'] ?? row['graded'],
    );
    final artist = _cleanLabel(
      row['artist'] ?? row['illustrator'],
      fallback: '',
    );
    return PokemonCard(
      id: id,
      name: '${row['name'] ?? 'Pokemon card'}',
      imageUrl: imageUrl,
      previewImageUrl: previewImageUrl,
      homepageImageUrl: homepageImageUrl,
      rarity: itemKind == 'product' ? type : rarity,
      type: type,
      hp: 0,
      attacks: const [],
      price: listedPrice ?? 0,
      description: itemKind == 'product'
          ? 'Imported from the Pokoin marketplace product version index.'
          : 'Imported from the Pokoin marketplace version index. Full blueprint data is loaded on card detail.',
      set: setName,
      number: number,
      artist: artist,
      stock: listedQuantity,
      rating: _readWatchlistCount(row).toDouble(),
      reviewCount: 0,
      isFoil: false,
      isHolo: false,
      releaseDate: _parseDate(row['projected_at']),
      tags: [
        setName,
        itemKind == 'product' ? type : rarity,
        type,
        itemKind,
        productType,
        if (trainerName.isNotEmpty) trainerName,
      ],
      condition: 'NM',
      isGraded: isGraded,
      grade: _cleanLabel(row['grade'], fallback: ''),
      gradingCompany: _cleanLabel(
        row['gradingCompany'] ?? row['grading_company'],
        fallback: '',
      ),
      itemKind: itemKind,
      productType: productType,
      trainerName: trainerName,
      expansionSymbolUrl: _normalizeImageUrl(row['expansion_symbol_url']),
      expansionLogoUrl: _normalizeImageUrl(row['expansion_logo_url']),
      canonicalPath: _cleanCanonicalPath(row),
      hasCardTraderListing: hasCardTraderListing,
      cardtraderEligibleListingCount: cardTraderListingCount,
      watchlistCount: _readWatchlistCount(row),
      cartHolderCount: _readCartHolderCount(row),
      cardPalette: _readCardPalette(row),
      emoji: _readEmoji(row),
    );
  }

  PokemonCard _cardFromBlueprint(Map<String, dynamic> row) {
    final blueprint = Map<String, dynamic>.from(row['blueprint'] as Map? ?? {});
    final expansion = Map<String, dynamic>.from(row['expansion'] as Map? ?? {});
    final properties = _readProperties(blueprint);
    final id = '${row['id'] ?? ''}';
    final name = '${row['name'] ?? blueprint['name'] ?? 'Pokemon card'}';
    final setName =
        '${expansion['name'] ?? blueprint['expansion_name'] ?? 'Pokemon'}';
    final number = properties['number'] ??
        properties['collector_number'] ??
        properties['card_number'] ??
        '${row['version'] ?? id}';
    final rarity = _cleanLabel(
      properties['rarity'] ??
          blueprint['rarity'] ??
          properties['collector_rarity'] ??
          '',
      fallback: 'Card',
    );
    final cardType = _cleanLabel(
      properties['card_type'] ??
          properties['type'] ??
          blueprint['type'] ??
          blueprint['category_name'] ??
          '',
      fallback: 'Card',
    );
    final trainerName = _extractTrainerName(name);
    final productType = _classifyProductType(
      name: name,
      setName: setName,
      categoryName: blueprint['category_name'],
      itemType: properties['type'] ?? blueprint['type'],
      number: number,
      version: row['version'],
      id: id,
    );
    final itemKind = productType == 'card' ? 'single' : 'product';
    final type = _marketplaceDisplayType(
      productType,
      fallback: cardType,
    );
    final displayRarity = itemKind == 'product' ? type : rarity;
    final imageUrl = _normalizeImageUrl(
      row['cdn_image_url'] ??
          row['image_url'] ??
          _fullBlueprintImageUrl(blueprint) ??
          blueprint['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'] ?? blueprint['id'],
    );
    final previewImageUrl = _normalizeImageUrl(
      row['preview_image_url'] ??
          row['cdn_preview_image_url'] ??
          row['previewImageUrl'] ??
          row['cdn_image_url'] ??
          row['image_url'] ??
          blueprint['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'] ?? blueprint['id'],
    );
    final homepageImageUrl = _normalizeImageUrl(
      row['homepage_image_url'] ??
          row['homepageImageUrl'] ??
          row['preview_image_url'] ??
          row['cdn_preview_image_url'] ??
          row['previewImageUrl'] ??
          row['cdn_image_url'] ??
          row['image_url'] ??
          blueprint['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'] ?? blueprint['id'],
    );
    final price = _pknPrices[id] ?? 1000 + (_stableSeed(id) % 120000);
    return PokemonCard(
      id: id,
      name: name,
      imageUrl: imageUrl,
      previewImageUrl: previewImageUrl,
      homepageImageUrl: homepageImageUrl,
      rarity: displayRarity,
      type: type,
      hp: 0,
      attacks: const [],
      price: price.toDouble(),
      description:
          'Imported from CardTrader blueprint data. Seller listings are managed on Pokoin.',
      set: setName,
      number: number.toString(),
      artist: '',
      stock: 0,
      rating: 0,
      reviewCount: 0,
      isFoil: itemKind != 'product' && rarity.toLowerCase().contains('holo'),
      isHolo: itemKind != 'product' && rarity.toLowerCase().contains('holo'),
      releaseDate: DateTime.now(),
      tags: [
        setName,
        displayRarity,
        type,
        itemKind,
        productType,
        if (trainerName.isNotEmpty) trainerName,
        if (properties['stage'] != null) '${properties['stage']}',
      ],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
      trainerName: trainerName,
      canonicalPath: _cleanCanonicalPath(row),
      cardPalette: _readCardPalette(row),
      emoji: _readEmoji(row),
      cartHolderCount: _readCartHolderCount(row),
    );
  }

  Map<String, Object?> _readProperties(Map<String, dynamic> blueprint) {
    final properties = <String, Object?>{};
    final editable = blueprint['editable_properties'];
    if (editable is List) {
      for (final item in editable.whereType<Map>()) {
        final key = '${item['name'] ?? item['slug'] ?? item['key'] ?? ''}'
            .toLowerCase()
            .replaceAll(' ', '_');
        if (key.isNotEmpty) {
          properties[key] = item['value'] ?? item['text'];
        }
      }
    }
    for (final entry in blueprint.entries) {
      properties.putIfAbsent(entry.key.toLowerCase(), () => entry.value);
    }
    return properties;
  }

  String? _fullBlueprintImageUrl(Map<String, dynamic> blueprint) {
    final image = blueprint['image'];
    if (image is! Map) {
      return null;
    }

    final rawUrl = '${image['url'] ?? ''}'.trim();
    if (rawUrl.isEmpty || rawUrl.contains('/preview_')) {
      return null;
    }
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    if (rawUrl.startsWith('/')) {
      return 'https://cardtrader.com$rawUrl';
    }
    return rawUrl;
  }

  int _stableSeed(String value) {
    return value.codeUnits.fold<int>(0, (sum, unit) => sum + unit * 31);
  }

  String _cleanLabel(Object? value, {required String fallback}) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text.toLowerCase() == 'pokemon') {
      return fallback;
    }
    return text;
  }

  String _extractTrainerName(String name) {
    final match =
        RegExp(r"^(.+?)'s\s+.+$", caseSensitive: false).firstMatch(name.trim());
    return match?.group(1)?.trim() ?? '';
  }

  DateTime _parseDate(Object? value) {
    return DateTime.tryParse('${value ?? ''}') ?? DateTime.now();
  }

  String _normalizeItemKind(Object? value) {
    return '${value ?? ''}'.trim().toLowerCase() == 'product'
        ? 'product'
        : 'single';
  }

  String _normalizeProductType(Object? value, String itemKind) {
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    const allowed = {
      'card',
      'booster_pack',
      'booster_box',
      'booster_bundle',
      'elite_trainer_box',
      'tin',
      'collection_box',
      'deck',
      'championship_deck',
      'accessory',
      'sealed_product',
    };
    if (allowed.contains(normalized)) {
      return normalized;
    }
    return itemKind == 'product' ? 'sealed_product' : 'card';
  }

  bool _hasCollectorNumber(Object? value) {
    final text = '${value ?? ''}'.trim().toLowerCase();
    return RegExp(r'(^|[^0-9])[0-9]{1,4}[a-z]?/[0-9]{1,4}([^0-9]|$)')
        .hasMatch(text);
  }

  String _itemKindForProjectedRow({
    required Object? itemKind,
    required Object? productType,
    required Object? number,
  }) {
    if (_hasCollectorNumber(number)) {
      return 'single';
    }
    final normalizedProductType = '${productType ?? ''}'.trim().toLowerCase();
    return normalizedProductType == 'card'
        ? 'single'
        : _normalizeItemKind(itemKind);
  }

  String _productTypeForProjectedRow({
    required Object? productType,
    required String itemKind,
    required Object? number,
  }) {
    if (_hasCollectorNumber(number)) {
      return 'card';
    }
    return _normalizeProductType(productType, itemKind);
  }

  String _classifyProductType({
    required String name,
    required String setName,
    required Object? categoryName,
    required Object? itemType,
    required Object? number,
    required Object? version,
    required String id,
  }) {
    final normalizedName = name.toLowerCase();
    final normalizedSet = setName.toLowerCase();
    final normalizedCategory = '${categoryName ?? ''}'.toLowerCase();
    final normalizedType = '${itemType ?? ''}'.toLowerCase();
    final normalizedNumber = '${number ?? ''}'.toLowerCase().trim();
    final normalizedVersion = '${version ?? ''}'.toLowerCase().trim();
    final idText = id.trim();
    final hasCollectorNumber =
        RegExp(r'(^|[^0-9])[0-9]{1,4}[a-z]?/[0-9]{1,4}([^0-9]|$)')
            .hasMatch(normalizedNumber);
    final looksLikeBlueprintNumber = normalizedNumber == idText ||
        RegExp(r'^[0-9]{5,}$').hasMatch(normalizedNumber);
    final hasVersion = normalizedVersion.isNotEmpty;
    final championshipSet =
        RegExp(r'world championship decks|world championships .* deck')
            .hasMatch(normalizedSet);

    bool matches(String pattern) {
      final expression = RegExp('(^|[^a-z0-9])($pattern)([^a-z0-9]|\$)');
      return expression.hasMatch(normalizedName) ||
          expression.hasMatch(normalizedCategory) ||
          expression.hasMatch(normalizedType);
    }

    if (hasCollectorNumber) return 'card';
    if (matches(
        r'coin|sleeves|sleeve|playmat|binder|portfolio|divider|dividers|accessory')) {
      return 'accessory';
    }
    if (matches(r'booster box|display box|sealed box')) return 'booster_box';
    if (matches(r'booster bundle|bundle')) return 'booster_bundle';
    if (matches(r'booster pack|booster|pack')) return 'booster_pack';
    if (matches(r'elite trainer box|etb')) return 'elite_trainer_box';
    if (matches(r'tin|tins')) return 'tin';
    if (matches(
        r'premium collection|special collection|collection box|box set|gift box|card frame box|frame box|collection')) {
      return 'collection_box';
    }
    if (matches(r'theme deck|starter deck|battle deck|deck')) return 'deck';
    if (championshipSet &&
        !hasCollectorNumber &&
        (!hasVersion || looksLikeBlueprintNumber)) {
      return 'championship_deck';
    }
    if (!hasCollectorNumber &&
        matches(r'sealed|sealed product|product|sealed case')) {
      return 'sealed_product';
    }
    return 'card';
  }

  String _marketplaceDisplayType(String productType,
      {required String fallback}) {
    switch (productType) {
      case 'booster_pack':
        return 'Booster pack';
      case 'booster_box':
        return 'Booster box';
      case 'booster_bundle':
        return 'Booster bundle';
      case 'elite_trainer_box':
        return 'Elite Trainer Box';
      case 'tin':
        return 'Tin';
      case 'collection_box':
        return 'Collection box';
      case 'deck':
        return 'Deck';
      case 'championship_deck':
        return 'Championship deck';
      case 'accessory':
        return 'Accessory';
      case 'sealed_product':
        return 'Sealed product';
      default:
        return fallback.toLowerCase() == 'trading card' ? 'Card' : fallback;
    }
  }

  String _normalizeImageUrl(Object? value, {Object? cardId, Object? ctId}) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) {
      return '';
    }
    return rewriteCdnPrefixToOurId(
      _publicCardImageUrl(text),
      pokoinCardId: '${cardId ?? ''}'.trim(),
      ctId: '${ctId ?? ''}'.trim(),
    );
  }

  String _publicCardImageUrl(String value) {
    if (value == _cardImageProxyPrefix ||
        value.startsWith('$_cardImageProxyPrefix/') ||
        value.startsWith('card-images/')) {
      return _cardImageProxyUrl(value);
    }
    try {
      final uri = Uri.parse(value);
      if (uri.hasScheme && uri.host == _cardImageCdnHost) {
        return _cardImageProxyUrl(uri.path, query: uri.query);
      }
      if (uri.hasScheme &&
          uri.host == 'pokoin.com' &&
          (uri.path == _cardImageProxyPrefix ||
              uri.path.startsWith('$_cardImageProxyPrefix/'))) {
        return _cardImageProxyUrl(uri.path, query: uri.query);
      }
      return value;
    } catch (_) {
      return value;
    }
  }

  String _cardImageProxyUrl(String path, {String query = ''}) {
    var imagePath = path.trim();
    if (imagePath.isEmpty) {
      return '';
    }
    if (!imagePath.startsWith('/')) {
      imagePath = '/$imagePath';
    }
    while (imagePath == _cardImageProxyPrefix ||
        imagePath.startsWith('$_cardImageProxyPrefix/')) {
      imagePath = imagePath.substring(_cardImageProxyPrefix.length);
      if (imagePath.isEmpty) {
        imagePath = '/';
      }
    }
    final uri = Uri.parse(_cardImageProxyOrigin)
        .replace(path: '$_cardImageProxyPrefix$imagePath');
    if (query.isEmpty) {
      return uri.toString();
    }
    return uri.replace(query: query).toString();
  }

  Future<void> _saveCardsToLocal(List<PokemonCard> cards) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      await box.clear();
      for (int i = 0; i < cards.length; i++) {
        await box.put(i, cards[i]);
      }
      await _writeCacheMetadata('cards');
    } catch (e) {
      debugPrint('Error saving cards to local storage: $e');
    }
  }

  List<PokemonCard> _normalizeCards(List<PokemonCard> cards) {
    return cards
        .map(
          (card) => card.copyWith(
            stock: card.stock,
            price: _pknPrices[card.id] ?? card.price,
          ),
        )
        .toList();
  }

  Future<PokemonCard?> getCardById(String id) async {
    final cached = await getCachedCardById(id);
    try {
      final projectionCard = await _getMarketplaceProjectionCardById(id);
      if (projectionCard != null) {
        await _upsertCardToLocal(projectionCard);
        return projectionCard;
      }

      return cached;
    } catch (e) {
      debugPrint('Error getting card by ID: $e');
      return cached;
    }
  }

  Future<PokemonCard?> getCardByDetailSlug(String slug) async {
    final normalizedSlug = normalizeCardDetailSlug(slug);
    if (normalizedSlug.isEmpty) {
      return null;
    }

    final cached = await getCachedCardByDetailSlug(normalizedSlug);
    try {
      final projectionCard = await _getMarketplaceProjectionCardBySlug(
        normalizedSlug,
      );
      if (projectionCard != null) {
        await _upsertCardToLocal(projectionCard);
        return projectionCard;
      }

      return cached;
    } catch (e) {
      debugPrint('Error getting card by detail slug: $e');
      return cached;
    }
  }

  Future<MarketplaceCardCanonicalUrl?> getMarketplaceCardCanonicalUrl({
    String? cardId,
    String? path,
    String language = 'en',
  }) async {
    final trimmedCardId = (cardId ?? '').trim();
    final trimmedPath = (path ?? '').trim();
    if (trimmedCardId.isEmpty && trimmedPath.isEmpty) {
      return null;
    }

    try {
      final queryParameters = <String, String>{
        'language': language,
        if (trimmedCardId.isNotEmpty) 'cardId': trimmedCardId,
        if (trimmedPath.isNotEmpty) 'path': trimmedPath,
      };
      final uri = Uri.base.resolve('/api/marketplace-card-url').replace(
            queryParameters: queryParameters,
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return null;
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return null;
      }
      final canonical = MarketplaceCardCanonicalUrl.fromJson(payload);
      if (canonical.canonicalPath.startsWith('/marketplace/') &&
          canonical.canonicalPath.contains('/cards/')) {
        return canonical;
      }
    } catch (error) {
      debugPrint('Marketplace canonical URL lookup failed: $error');
    }
    return null;
  }

  Future<List<CardSaleEvent>> getCardSalesHistory(String cardId) async {
    final trimmedId = cardId.trim();
    if (!RegExp(r'^\d+$').hasMatch(trimmedId)) {
      return const [];
    }

    try {
      final uri = Uri.base.resolve('/api/marketplace-card-sales').replace(
        queryParameters: {
          'cardId': trimmedId,
          'limit': '160',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 400) {
        debugPrint('Marketplace card sales failed: ${response.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(response.body);
      final rows = decoded is Map ? decoded['rows'] : decoded;
      if (rows is! List) {
        return const [];
      }
      return rows
          .whereType<Map>()
          .map((row) => CardSaleEvent.fromJson(Map<String, dynamic>.from(row)))
          .where((event) =>
              event.cardId == trimmedId &&
              event.pricePkn > 0 &&
              event.soldAt.millisecondsSinceEpoch > 0)
          .toList();
    } catch (error) {
      debugPrint('Marketplace card sales failed: $error');
      return const [];
    }
  }

  Future<MarketplaceBlueprintPrice?> getCardTraderSuggestedListingPrice(
    String cardId,
  ) async {
    final trimmedId = cardId.trim();
    if (!RegExp(r'^\d+$').hasMatch(trimmedId)) {
      return null;
    }

    try {
      final uri = Uri.base.resolve('/api/marketplace-blueprint-price').replace(
        queryParameters: {
          'cardId': trimmedId,
          'source': 'cardtrader',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final price = MarketplaceBlueprintPrice.fromJson(decoded);
      return price.hasPrice ? price : null;
    } catch (error) {
      debugPrint('CardTrader suggested listing price failed: $error');
      return null;
    }
  }

  Future<PokemonCard?> getCachedCardById(String id) async {
    await _initHive();
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final meta = await _cacheMetadata('cards');
      final hasLegacyCards = meta == null && box.isNotEmpty;
      if (!_cacheMapIsUsable(meta, _detailCacheTtl,
          allowLegacy: hasLegacyCards)) {
        return null;
      }
      if (hasLegacyCards) {
        await _writeCacheMetadata('cards');
      }
      for (final card in box.values) {
        if (card.id == id) {
          return card;
        }
      }
    } catch (error) {
      debugPrint('Cached card by id failed: $error');
    }
    return null;
  }

  Future<PokemonCard?> getCachedCardByDetailSlug(String slug) async {
    final normalizedSlug = normalizeCardDetailSlug(slug);
    if (normalizedSlug.isEmpty) {
      return null;
    }

    await _initHive();
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final meta = await _cacheMetadata('cards');
      final hasLegacyCards = meta == null && box.isNotEmpty;
      if (!_cacheMapIsUsable(meta, _detailCacheTtl,
          allowLegacy: hasLegacyCards)) {
        return null;
      }
      if (hasLegacyCards) {
        await _writeCacheMetadata('cards');
      }
      for (final card in box.values) {
        if (cardDetailSlugsMatch(cardDetailSlug(card), normalizedSlug) ||
            cardDetailSlugsMatch(legacyCardDetailSlug(card), normalizedSlug)) {
          return card;
        }
      }
    } catch (error) {
      debugPrint('Cached card by detail slug failed: $error');
    }
    return null;
  }

  Future<PokemonCard?> _getMarketplaceProjectionCardById(String id) async {
    final trimmedId = id.trim();
    if (!RegExp(r'^\d+$').hasMatch(trimmedId)) {
      return null;
    }

    try {
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
        queryParameters: {
          'cardId': trimmedId,
          'limit': '1',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return null;
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final maps = rows.whereType<Map>();
      if (maps.isEmpty) {
        return null;
      }
      return _cardFromVersionRow(Map<String, dynamic>.from(maps.first));
    } catch (error) {
      debugPrint('Marketplace projection card by id failed: $error');
      return null;
    }
  }

  Future<PokemonCard?> _getMarketplaceProjectionCardBySlug(String slug) async {
    final normalizedSlug = normalizeCardDetailSlug(slug);
    if (normalizedSlug.isEmpty) {
      return null;
    }

    try {
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
        queryParameters: {
          'cardSlug': normalizedSlug,
          'limit': '120',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return null;
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .where((card) => cardDetailSlugsMatch(
                cardDetailSlug(card),
                normalizedSlug,
              ))
          .toList();
      if (cards.isEmpty) {
        return null;
      }
      return cards.first;
    } catch (error) {
      debugPrint('Marketplace projection card by slug failed: $error');
      return null;
    }
  }

  Future<List<PokemonCard>> getExpansionVersionCards(PokemonCard card) async {
    return getCardsByExpansion(card.set);
  }

  Future<List<PokemonCard>> getOtherVersionCards(String cardId) async {
    final trimmedId = cardId.trim();
    if (!RegExp(r'^\d+$').hasMatch(trimmedId)) {
      return const [];
    }
    final cacheKey = 'versions:$trimmedId';
    final cached = await _cachedCardList(cacheKey);

    try {
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
        queryParameters: {
          'sameAsCardId': trimmedId,
          'productType': 'card',
          'limit': '100',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return const [];
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      final sorted = _sortCardsByCollectorNumber(_dedupeCards(cards));
      await _saveCardList(cacheKey, sorted);
      await _mergeCardsToLocal(sorted);
      return sorted;
    } catch (error) {
      debugPrint('Other version cards failed: $error');
      return cached;
    }
  }

  Future<List<PokemonCard>> getSimilarVersionCards(
    String cardId, {
    List<PokemonCard> versionCards = const [],
  }) async {
    final current = await getCardById(cardId);
    if (current == null || current.set.trim().isEmpty) {
      return const [];
    }
    final excludedVersionCards = versionCards.isEmpty
        ? await getOtherVersionCards(cardId)
        : versionCards;
    final sameNameCards = await searchMarketplaceCards(
      current.name,
      limit: 80,
      productType: 'card',
    );
    final expansionCards = await getCardsByExpansion(current.set);
    final sameNameRanked = sameNameCards
        .where((card) =>
            card.id != current.id &&
            _normalizeCardText(card.name) == _normalizeCardText(current.name))
        .toList()
      ..sort((a, b) {
        final currentSet = _normalizeCardText(current.set);
        final aSameSet = _normalizeCardText(a.set) == currentSet;
        final bSameSet = _normalizeCardText(b.set) == currentSet;
        final setMatch = (bSameSet ? 1 : 0).compareTo(aSameSet ? 1 : 0);
        if (setMatch != 0) {
          return setMatch;
        }
        return _compareCollectorNumberSortKeys(
          _collectorNumberSortKey(a.number),
          _collectorNumberSortKey(b.number),
        );
      });
    final sameNameIds = sameNameRanked.map((card) => card.id).toSet();
    final rankedExpansion = expansionCards
        .where(
            (card) => card.id != current.id && !sameNameIds.contains(card.id))
        .map((card) => (card: card, score: _similarityScore(current, card)))
        .toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) {
          return score;
        }
        return _compareCollectorNumberSortKeys(
          _collectorNumberSortKey(a.card.number),
          _collectorNumberSortKey(b.card.number),
        );
      });
    final filtered = _excludeVersionBlueprintCards(
      current,
      excludedVersionCards,
      _dedupeCards([
        ...sameNameRanked,
        ...rankedExpansion.map((entry) => entry.card),
      ]),
    );
    return filtered.take(16).toList();
  }

  Set<String> _versionBlueprintIds(
    PokemonCard current,
    Iterable<PokemonCard> versionCards,
  ) {
    return {
      current.id.trim(),
      for (final card in versionCards)
        if (card.id.trim().isNotEmpty) card.id.trim(),
    }..remove('');
  }

  List<PokemonCard> _excludeVersionBlueprintCards(
    PokemonCard current,
    Iterable<PokemonCard> versionCards,
    Iterable<PokemonCard> similarCards,
  ) {
    final excludedIds = _versionBlueprintIds(current, versionCards);
    return [
      for (final card in similarCards)
        if (!excludedIds.contains(card.id.trim())) card,
    ];
  }

  Future<List<MarketplaceExpansion>> getMarketplaceExpansions({
    String? slug,
  }) async {
    try {
      final uri = Uri.base.resolve('/api/marketplace-expansions').replace(
        queryParameters: {
          if (slug?.trim().isNotEmpty == true) 'slug': slug!.trim(),
          'limit': '1000',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return const [];
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['expansions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              MarketplaceExpansion.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error) {
      debugPrint('Marketplace expansions failed: $error');
      return const [];
    }
  }

  Future<MarketplaceExpansion?> getMarketplaceExpansionBySlug(
    String slug,
  ) async {
    final expansions = await getMarketplaceExpansions(slug: slug);
    return expansions.isEmpty ? null : expansions.first;
  }

  Future<MarketplaceExpansionSnapshot?> getMarketplaceExpansionSnapshotBySlug(
    String slug,
  ) async {
    try {
      final uri = Uri.base.resolve('/api/marketplace-expansions').replace(
        queryParameters: {
          'slug': slug.trim(),
          'includeCards': '1',
          'productType': 'card',
          'limit': '1200',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return null;
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final expansion = MarketplaceExpansion.fromJson(
        Map<String, dynamic>.from(payload['expansion'] as Map? ?? const {}),
      );
      final cards = (payload['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      return MarketplaceExpansionSnapshot(
        expansion: expansion,
        cards: _sortCardsByCollectorNumber(cards),
      );
    } catch (error) {
      debugPrint('Marketplace expansion snapshot failed: $error');
      return null;
    }
  }

  Future<MarketplaceArtistSnapshot?> getMarketplaceArtistSnapshotBySlug(
    String slug, {
    int limit = _marketplaceArtistSnapshotLimit,
  }) async {
    final normalizedSlug = artistSlug(slug);
    if (normalizedSlug.isEmpty) {
      return null;
    }
    final cacheKey = 'artist:$normalizedSlug:$limit';
    final cached = await _cachedCardList(cacheKey);
    try {
      final uri = Uri.base.resolve('/api/marketplace-artist-cards').replace(
        queryParameters: {
          'artistSlug': normalizedSlug,
          'limit': '$limit',
        },
      );
      final response = await _getMarketplaceArtistCardsResponse(uri);
      if (response.statusCode >= 400) {
        return cached.isEmpty
            ? null
            : MarketplaceArtistSnapshot(
                name: _artistTitleFromSlug(normalizedSlug),
                slug: normalizedSlug,
                cardCount: cached.length,
                cards: cached,
              );
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final artist = Map<String, dynamic>.from(
        payload['artist'] as Map? ?? const {},
      );
      final profile = MarketplaceArtistProfile.fromJson(
        Map<String, dynamic>.from(payload['profile'] as Map? ?? const {}),
      );
      final cards = (payload['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      final sorted = _sortCardsByCollectorNumber(_dedupeCards(cards));
      if (sorted.isNotEmpty) {
        await _saveCardList(cacheKey, sorted);
        await _mergeCardsToLocal(sorted);
      }
      final name = _cleanLabel(artist['name'], fallback: '');
      if (name.isEmpty && sorted.isEmpty) {
        return null;
      }
      return MarketplaceArtistSnapshot(
        name: name.isEmpty ? _artistTitleFromSlug(normalizedSlug) : name,
        slug: _cleanLabel(artist['slug'], fallback: normalizedSlug),
        cardCount: (artist['cardCount'] as num?)?.toInt() ?? sorted.length,
        cards: sorted.isEmpty ? cached : sorted,
        profile: profile,
      );
    } catch (error) {
      debugPrint('Marketplace artist cards failed: $error');
      return cached.isEmpty
          ? null
          : MarketplaceArtistSnapshot(
              name: _artistTitleFromSlug(normalizedSlug),
              slug: normalizedSlug,
              cardCount: cached.length,
              cards: cached,
            );
    }
  }

  Future<http.Response> _getMarketplaceArtistCardsResponse(Uri uri) async {
    var response = await http.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode < 500) {
      return response;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return http.get(uri).timeout(const Duration(seconds: 6));
  }

  Future<List<MarketplaceArtistSummary>> getMarketplaceArtistSummaries() async {
    try {
      final uri = Uri.base.resolve('/api/marketplace-artist-cards').replace(
        queryParameters: {
          'summaries': '1',
          'limit': '1000',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return const [];
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['artists'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => MarketplaceArtistSummary.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .where((artist) =>
              artist.name.isNotEmpty &&
              artist.slug.isNotEmpty &&
              artist.cardCount > 0)
          .toList();
    } catch (error) {
      debugPrint('Marketplace artist summaries failed: $error');
      return const [];
    }
  }

  Future<CompetitiveSnapshot?> getCompetitiveSnapshot({
    String? game,
    String? format,
    int? year,
    String? tournamentId,
    String? deckId,
    String? decklistId,
    int limit = 50,
  }) async {
    try {
      final queryParameters = <String, String>{
        if (decklistId?.trim().isNotEmpty == true)
          'decklistId': decklistId!.trim()
        else if (deckId?.trim().isNotEmpty == true)
          'deckId': deckId!.trim()
        else if (tournamentId?.trim().isNotEmpty == true)
          'tournamentId': tournamentId!.trim()
        else ...{
          'includeGames': '1',
          'limit': '$limit',
          if (game?.trim().isNotEmpty == true) 'game': game!.trim(),
          if (format?.trim().isNotEmpty == true) 'format': format!.trim(),
          if (year != null && year > 0) 'year': '$year',
        },
      };
      final directUri = Uri.parse(
        '${_competitiveApiBaseUrl.replaceFirst(RegExp(r'/$'), '')}/api/marketplace-competitive',
      ).replace(queryParameters: queryParameters);
      final response = await _getCompetitiveSnapshotResponse(
        directUri,
        Uri.base.resolve('/api/marketplace-competitive').replace(
              queryParameters: queryParameters,
            ),
      );
      if (response.statusCode >= 400) {
        debugPrint('Marketplace competitive failed: ${response.statusCode}');
        return null;
      }
      return CompetitiveSnapshot.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (error) {
      debugPrint('Marketplace competitive failed: $error');
      return null;
    }
  }

  Future<http.Response> _getCompetitiveSnapshotResponse(
    Uri directUri,
    Uri fallbackUri,
  ) async {
    try {
      return await http.get(directUri).timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('Marketplace competitive direct API failed: $error');
      return http.get(fallbackUri).timeout(const Duration(seconds: 10));
    }
  }

  Future<List<PokemonCard>> getCardsByExpansion(String expansionName) async {
    final normalizedExpansion = expansionName.trim();
    if (normalizedExpansion.isEmpty) {
      return const [];
    }
    final cacheKey = 'expansion:${normalizedExpansion.toLowerCase()}';
    final cached = await _cachedCardList(cacheKey);

    try {
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
        queryParameters: {
          'expansionName': normalizedExpansion,
          'productType': 'card',
          'limit': '1000',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return const [];
      }
      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      final sorted = _sortCardsByCollectorNumber(_dedupeCards(cards));
      await _saveCardList(cacheKey, sorted);
      await _mergeCardsToLocal(sorted);
      return sorted;
    } catch (error) {
      debugPrint('Expansion cards failed: $error');
      return cached;
    }
  }

  String _artistTitleFromSlug(String slug) {
    final normalizedSlug = artistSlug(slug);
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

  List<PokemonCard> _sortCardsByCollectorNumber(List<PokemonCard> cards) {
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

  int _similarityScore(PokemonCard source, PokemonCard candidate) {
    var score = 0;
    final sourceNumber = _collectorNumberSortKey(source.number).number;
    final candidateNumber = _collectorNumberSortKey(candidate.number).number;
    final distance = (sourceNumber - candidateNumber).abs();
    if (distance <= 2) {
      score += 80;
    } else if (distance <= 6) {
      score += 48;
    } else if (distance <= 12) {
      score += 24;
    }

    if (_normalizeCardText(source.type) == _normalizeCardText(candidate.type)) {
      score += 28;
    }
    if (_normalizeCardText(source.rarity) ==
        _normalizeCardText(candidate.rarity)) {
      score += 18;
    }
    final sourceTokens = _cardNameTokens(source.name);
    final candidateTokens = _cardNameTokens(candidate.name);
    score += sourceTokens.intersection(candidateTokens).length * 12;
    if (source.trainerName.isNotEmpty &&
        source.trainerName == candidate.trainerName) {
      score += 20;
    }
    return score;
  }

  Set<String> _cardNameTokens(String name) {
    return name
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 3)
        .toSet();
  }

  String _normalizeCardText(String value) {
    return value.trim().toLowerCase();
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

  Future<void> _upsertCardToLocal(PokemonCard card) async {
    try {
      await _initHive();
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys.firstWhere(
        (key) => box.get(key)?.id == card.id,
        orElse: () => null,
      );
      if (key == null) {
        await box.add(card);
      } else {
        await box.put(key, card);
      }
      await _writeCacheMetadata('cards');
    } catch (error) {
      debugPrint('Error caching card by id: $error');
    }
  }

  Future<void> _mergeCardsToLocal(List<PokemonCard> cards) async {
    if (cards.isEmpty) {
      return;
    }
    try {
      await _initHive();
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final byId = <String, PokemonCard>{
        for (final card in box.values)
          if (card.id.isNotEmpty) card.id: card,
      };
      for (final card in cards) {
        if (card.id.isNotEmpty) {
          byId[card.id] = card;
        }
      }
      await box.clear();
      var index = 0;
      for (final card in byId.values) {
        await box.put(index++, card);
      }
      await _writeCacheMetadata('cards');
    } catch (error) {
      debugPrint('Error merging cards to local cache: $error');
    }
  }

  Future<List<PokemonCard>> _cachedCardList(String key) async {
    try {
      final box = await Hive.openBox<Map>(_listCacheBoxName);
      final cached = box.get(key);
      if (cached == null) {
        return const [];
      }
      final data = Map<String, dynamic>.from(cached);
      if (!_cacheMapIsUsable(data, _listCacheTtl)) {
        return const [];
      }
      return (data['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => PokemonCard.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } catch (error) {
      debugPrint('Marketplace card list cache load failed: $error');
      return const [];
    }
  }

  Future<void> _saveCardList(String key, List<PokemonCard> cards) async {
    if (cards.isEmpty) {
      return;
    }
    try {
      final box = await Hive.openBox<Map>(_listCacheBoxName);
      await box.put(
        key,
        _withCacheMeta({
          'cards': cards.map((card) => card.toJson()).toList(),
        }),
      );
    } catch (error) {
      debugPrint('Marketplace card list cache save failed: $error');
    }
  }

  Future<Map?> _cacheMetadata(String key) async {
    try {
      final box = await Hive.openBox<Map>(_cacheMetaBoxName);
      return box.get(key);
    } catch (error) {
      debugPrint('Cache metadata load failed: $error');
      return null;
    }
  }

  Future<void> _writeCacheMetadata(String key) async {
    try {
      final box = await Hive.openBox<Map>(_cacheMetaBoxName);
      await box.put(key, _cacheMetadataMap());
    } catch (error) {
      debugPrint('Cache metadata save failed: $error');
    }
  }

  Map<String, dynamic> _withCacheMeta(Map<String, dynamic> data) {
    return {
      ...data,
      ..._cacheMetadataMap(),
    };
  }

  Map<String, dynamic> _cacheMetadataMap() {
    return {
      _cacheSchemaKey: _cacheSchemaVersion,
      _cacheCachedAtKey: DateTime.now().millisecondsSinceEpoch,
    };
  }

  bool _cacheMapIsUsable(
    Map? raw,
    Duration ttl, {
    bool allowLegacy = false,
  }) {
    if (raw == null) {
      return allowLegacy;
    }
    final schema = (raw[_cacheSchemaKey] as num?)?.toInt();
    if (schema != _cacheSchemaVersion) {
      return false;
    }
    final cachedAtMs = (raw[_cacheCachedAtKey] as num?)?.toInt();
    if (cachedAtMs == null || cachedAtMs <= 0) {
      return false;
    }
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(cachedAtMs),
    );
    return age <= ttl;
  }

  Future<List<PokemonCard>> searchCards(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return getAllCards();
    }

    final remote = await searchMarketplaceCards(normalizedQuery, limit: 100);
    if (remote.isNotEmpty) {
      return remote;
    }

    try {
      return _rankLocalCards(await getAllCards(), normalizedQuery, 240);
    } catch (e) {
      debugPrint('Error searching cards: $e');
      return const [];
    }
  }

  Future<List<PokemonCard>> searchMarketplaceCards(
    String query, {
    int limit = 100,
    int offset = 0,
    String? productType,
    String searchLanguage = 'en',
    String? searchSessionId,
  }) async {
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1) {
      return const [];
    }

    final queryLanguage = _tcgdexLanguage(searchLanguage);
    final queries = _searchQueryVariants([normalizedQuery]);
    final results = <PokemonCard>[];

    final pageSize = limit < 1 ? 100 : (limit > 100 ? 100 : limit);
    if (productType != null && productType.trim().isNotEmpty) {
      for (final searchQuery in queries) {
        final rows = await _searchMarketplaceCardVersions(
          searchQuery,
          limit: pageSize,
          productType: productType,
          searchLanguage: queryLanguage,
          searchSessionId: searchSessionId,
        );
        results.addAll(rows);
        if (results.length >= pageSize) {
          break;
        }
      }
      return _dedupeCards(results).take(pageSize).toList();
    }

    final rows = await _searchMarketplaceCandidateRows(
      normalizedQuery,
      limit: pageSize,
      offset: offset < 0 ? 0 : offset,
      searchLanguage: queryLanguage,
      searchSessionId: searchSessionId,
    );
    return _dedupeCards(rows).take(pageSize).toList();
  }

  Future<List<PokemonCard>> _searchMarketplaceCandidateRows(
    String normalizedQuery, {
    required int limit,
    int offset = 0,
    String searchLanguage = 'en',
    String? searchSessionId,
  }) async {
    try {
      final authHeaders =
          await PokoinApiAuthService.instance().authorizationHeaders(
        requireSignedIn: false,
      );
      final response = await http
          .post(
            Uri.base.resolve('/api/marketplace-search-candidates'),
            headers: {
              'content-type': 'application/json',
              ...authHeaders,
            },
            body: jsonEncode({
              'search_term': normalizedQuery,
              'result_limit': limit,
              'result_offset': offset,
              'search_language': searchLanguage,
              if (searchSessionId?.trim().isNotEmpty == true)
                'search_session_id': searchSessionId,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode >= 400) {
        debugPrint(
            'Marketplace candidate search failed: ${response.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(response.body);
      final rows = decoded is Map
          ? (decoded['rows'] as List<dynamic>? ?? const [])
          : decoded is List
              ? decoded
              : const [];
      return _dedupeCards(rows
          .whereType<Map>()
          .map((row) => _cardFromSearchCandidate(Map<String, dynamic>.from(row)))
          .toList());
    } catch (error) {
      debugPrint('Marketplace candidate search failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> lookupDeckCardVersions({
    required String name,
    required String setCode,
    required String collectorNumber,
    int limit = 12,
    String searchLanguage = 'en',
  }) async {
    final normalizedName = name.trim();
    final normalizedSetCode = setCode.trim();
    final normalizedCollectorNumber = collectorNumber.trim();
    if (normalizedName.isEmpty && normalizedCollectorNumber.isEmpty) {
      return const [];
    }

    try {
      final uri = Uri.base.resolve('/api/deck-card-version-lookup').replace(
        queryParameters: {
          if (normalizedName.isNotEmpty) 'name': normalizedName,
          if (normalizedSetCode.isNotEmpty) 'setCode': normalizedSetCode,
          if (normalizedCollectorNumber.isNotEmpty)
            'collectorNumber': normalizedCollectorNumber,
          'limit': '$limit',
          if (_tcgdexLanguage(searchLanguage) != 'en')
            'lang': _tcgdexLanguage(searchLanguage),
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return const [];
      }

      final payload = jsonDecode(response.body);
      final rows = payload is Map
          ? (payload['matches'] as List<dynamic>? ?? const [])
          : payload is List
              ? payload
              : const [];
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      return _dedupeCards(cards).take(limit).toList();
    } catch (error) {
      debugPrint('Deck card version lookup failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> getMarketplaceCardsByProductType(
    String productType, {
    int limit = 240,
  }) async {
    final normalizedType = productType.trim();
    final cacheKey = 'product:$normalizedType:$limit';
    final cached = await _cachedCardList(cacheKey);
    try {
      final cards = await _searchMarketplaceCardVersions(
        '',
        limit: limit,
        productType: normalizedType,
      );
      if (cards.isNotEmpty) {
        await _saveCardList(cacheKey, cards);
        await _mergeCardsToLocal(cards);
      }
      return cards.isEmpty ? cached : cards;
    } catch (error) {
      debugPrint('Product type cards failed: $error');
      return cached;
    }
  }

  Future<List<PokemonCard>> getMarketplaceGradedCards({
    int limit = 240,
  }) async {
    final cacheKey = 'product:graded:$limit';
    final cached = await _cachedCardList(cacheKey);
    try {
      final cards = await _searchMarketplaceCardVersions(
        '',
        limit: limit,
        productType: 'card',
        productCategory: 'graded',
      );
      if (cards.isNotEmpty) {
        await _saveCardList(cacheKey, cards);
        await _mergeCardsToLocal(cards);
      }
      return cards.isEmpty ? cached : cards;
    } catch (error) {
      debugPrint('Graded marketplace cards failed: $error');
      return cached;
    }
  }

  Future<List<MarketplaceProductFacet>> getMarketplaceProductFacets({
    String query = '',
    String searchLanguage = 'en',
  }) async {
    try {
      final queryParameters = <String, String>{'facets': 'products'};
      final normalizedQuery = query.trim();
      if (normalizedQuery.isNotEmpty) {
        queryParameters['query'] = normalizedQuery;
      }
      if (_tcgdexLanguage(searchLanguage) != 'en') {
        queryParameters['search_language'] = _tcgdexLanguage(searchLanguage);
      }
      final uri = Uri.base.resolve('/api/marketplace-cards').replace(
            queryParameters: queryParameters,
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode >= 400) {
        return const [];
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['products'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              MarketplaceProductFacet.fromJson(Map<String, dynamic>.from(row)))
          .where((facet) => facet.productType.isNotEmpty && facet.count > 0)
          .toList();
    } catch (error) {
      debugPrint('Marketplace product facets failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> getHotMarketplaceCards({
    int limit = 1000,
    String window = '24h',
  }) async {
    try {
      final uri = Uri.base.resolve('/api/marketplace-hot-blueprints').replace(
        queryParameters: {
          'window': window,
          'limit': '$limit',
          'includeCards': '1',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) {
        return const [];
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final cardRows = (payload['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
              (row) => _cardFromSearchCandidate(Map<String, dynamic>.from(row)))
          .toList();
      if (cardRows.isNotEmpty) {
        return _dedupeCards(cardRows).take(limit).toList();
      }
      final blueprintCards = (payload['blueprints'] as List<dynamic>? ??
              const [])
          .whereType<Map>()
          .map((row) => _cardFromHotBlueprint(Map<String, dynamic>.from(row)))
          .toList();
      return _dedupeCards(blueprintCards).take(limit).toList();
    } catch (error) {
      debugPrint('Hot marketplace cards failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> searchAutocompleteCards(
    String query, {
    int limit = 20,
    int poolLimit = 15874,
    String searchLanguage = 'en',
    String previewMode = '',
    SearchAutocompleteContext? previousSearchContext,
    SearchTokenPredictionContext? predictionContext,
    String? searchSessionId,
  }) async {
    final result = await searchAutocompleteCardsWithContext(
      query,
      limit: limit,
      poolLimit: poolLimit,
      searchLanguage: searchLanguage,
      previewMode: previewMode,
      previousSearchContext: previousSearchContext,
      predictionContext: predictionContext,
      searchSessionId: searchSessionId,
    );
    return result.cards;
  }

  Future<SearchAutocompleteResult> searchAutocompleteCardsWithContext(
    String query, {
    int limit = 20,
    int poolLimit = 15874,
    String searchLanguage = 'en',
    String previewMode = '',
    SearchAutocompleteContext? previousSearchContext,
    SearchTokenPredictionContext? predictionContext,
    String? searchSessionId,
  }) async {
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1) {
      return const SearchAutocompleteResult(cards: []);
    }
    final canShowAutocomplete = _meaningfulSearchLength(normalizedQuery) >= 1;
    const retryDelays = [Duration.zero];
    Object? lastError;
    for (var attempt = 0; attempt < retryDelays.length; attempt += 1) {
      final delay = retryDelays[attempt];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      try {
        final trace = SearchDebugTrace.instance;
        final debugEnabled = trace.enabled;
        final debugToken = debugEnabled
            ? await PokoinApiAuthService.instance().bearerToken()
            : null;
        final authHeaders = debugToken == null
            ? await PokoinApiAuthService.instance().authorizationHeaders(
                requireSignedIn: false,
              )
            : const <String, String>{};
        final started = DateTime.now();
        trace.record('service.autocomplete.request', {
          'query': normalizedQuery,
          if (searchSessionId?.isNotEmpty == true)
            'searchSessionId': searchSessionId,
          'attempt': attempt + 1,
          'limit': limit,
          'poolLimit': poolLimit,
          'language': _tcgdexLanguage(searchLanguage),
          if (previewMode.isNotEmpty) 'previewMode': previewMode,
          if (previousSearchContext != null)
            'previousContextIds': previousSearchContext.cardIds.length,
          if (predictionContext != null)
            'predictionContextCandidates': predictionContext.candidates.length,
        });
        final normalizedLanguage = _tcgdexLanguage(searchLanguage);
        final response = await http
            .post(
              Uri.base.resolve('/api/marketplace-autocomplete'),
              headers: {
                'content-type': 'application/json',
                ...authHeaders,
                if (debugToken != null) 'authorization': 'Bearer $debugToken',
              },
              body: jsonEncode({
                'search_term': normalizedQuery,
                'result_limit': limit,
                'pool_limit': poolLimit,
                'search_language': normalizedLanguage,
                if (previewMode.isNotEmpty) 'preview_mode': previewMode,
                if (previousSearchContext != null &&
                    previousSearchContext.canRefine(
                      normalizedQuery,
                      normalizedLanguage,
                    ))
                  'previous_search_context': previousSearchContext.toJson(),
                if (predictionContext != null &&
                    predictionContext.canRefine(
                      normalizedQuery,
                      normalizedLanguage,
                    ))
                  'prediction_context': predictionContext.toJson(),
                if (searchSessionId?.isNotEmpty == true)
                  'search_session_id': searchSessionId,
                if (debugEnabled) 'debug': true,
                if (debugEnabled) 'debug_session_id': trace.sessionId,
              }),
            )
            .timeout(const Duration(seconds: 6));
        trace.record('service.autocomplete.response', {
          'query': normalizedQuery,
          'attempt': attempt + 1,
          'statusCode': response.statusCode,
          'elapsedMs': DateTime.now().difference(started).inMilliseconds,
          'serverTiming': response.headers['server-timing'],
        });
        if (response.statusCode >= 400) {
          lastError = 'status ${response.statusCode}';
          if (!canShowAutocomplete || attempt == retryDelays.length - 1) {
            debugPrint(
                'Marketplace autocomplete failed: ${response.statusCode}');
            return const SearchAutocompleteResult(cards: []);
          }
          continue;
        }
        final decoded = jsonDecode(response.body);
        final rows = decoded is Map<String, dynamic>
            ? (decoded['rows'] as List<dynamic>? ?? const [])
            : decoded as List<dynamic>;
        final context =
            decoded is Map<String, dynamic> && decoded['search_context'] is Map
                ? SearchAutocompleteContext.fromJson(
                    Map<String, dynamic>.from(decoded['search_context'] as Map),
                  )
                : null;
        final pool = decoded is Map<String, dynamic> && decoded['pool'] is Map
            ? Map<String, dynamic>.from(decoded['pool'] as Map)
            : const <String, dynamic>{};
        final predictedNameTokens =
            _predictedNameTokensFromResponse(decoded, context);
        if (decoded is Map<String, dynamic>) {
          SearchDebugTrace.instance.record('service.autocomplete.debug', {
            'query': normalizedQuery,
            'debug': decoded['debug'],
            if (predictedNameTokens.isNotEmpty)
              'predictedTokens': predictedNameTokens
                  .map((token) => token.toJson())
                  .toList(growable: false),
          });
        }
        final cards = _searchAutocompletePreviewCardsFromRows(rows, limit);
        if (cards.isNotEmpty ||
            !canShowAutocomplete ||
            attempt == retryDelays.length - 1) {
          SearchDebugTrace.instance.record('service.autocomplete.cards', {
            'query': normalizedQuery,
            'attempt': attempt + 1,
            'count': cards.length,
            'poolSize': (pool['size'] as num?)?.toInt() ?? 0,
            'poolSource': '${pool['source'] ?? ''}',
            'top': cards
                .take(8)
                .map((card) => {
                      'id': card.id,
                      'name': card.name,
                      'set': card.set,
                      'number': card.number,
                    })
                .toList(),
          });
          return SearchAutocompleteResult(
            cards: cards,
            context: context,
            poolSize: (pool['size'] as num?)?.toInt() ?? 0,
            poolSource: '${pool['source'] ?? ''}',
            predictedNameTokens: predictedNameTokens,
          );
        }
      } catch (error) {
        lastError = error;
        SearchDebugTrace.instance.record('service.autocomplete.error', {
          'query': normalizedQuery,
          'attempt': attempt + 1,
          'error': '$error',
        });
        if (!canShowAutocomplete || attempt == retryDelays.length - 1) {
          debugPrint('Marketplace autocomplete failed: $error');
          return const SearchAutocompleteResult(cards: []);
        }
      }
    }
    if (lastError != null) {
      debugPrint('Marketplace autocomplete failed: $lastError');
    }
    return const SearchAutocompleteResult(cards: []);
  }

  Future<List<SearchPredictedNameToken>> predictSearchNameTokens(
    String query, {
    int limit = 5,
    String searchLanguage = 'en',
    SearchTokenPredictionContext? previousPredictionContext,
  }) async {
    final result = await predictSearchNameTokensWithContext(
      query,
      limit: limit,
      searchLanguage: searchLanguage,
      previousPredictionContext: previousPredictionContext,
    );
    return result.tokens;
  }

  Future<SearchTokenPredictionResult> predictSearchNameTokensWithContext(
    String query, {
    int limit = 5,
    String searchLanguage = 'en',
    SearchTokenPredictionContext? previousPredictionContext,
  }) async {
    final normalizedQuery = query.trim();
    if (_meaningfulSearchLength(normalizedQuery) < 1) {
      return const SearchTokenPredictionResult();
    }
    try {
      final trace = SearchDebugTrace.instance;
      final normalizedLanguage = _tcgdexLanguage(searchLanguage);
      final previousContext = previousPredictionContext;
      final canRefineFromPrevious = previousContext?.canRefine(
            normalizedQuery,
            normalizedLanguage,
          ) ??
          false;
      final started = DateTime.now();
      trace.record('service.token_predict.request', {
        'query': normalizedQuery,
        'limit': limit,
        'language': normalizedLanguage,
        if (canRefineFromPrevious)
          'previousPredictionCandidates': previousContext!.candidates.length,
      });
      final response = await http
          .post(
            Uri.base.resolve('/api/searchbar-token-predict'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'query': normalizedQuery,
              'limit': limit,
              'search_language': normalizedLanguage,
              if (canRefineFromPrevious)
                'previous_prediction_context': previousContext!.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 2));
      trace.record('service.token_predict.response', {
        'query': normalizedQuery,
        'statusCode': response.statusCode,
        'elapsedMs': DateTime.now().difference(started).inMilliseconds,
        'payloadBytes': response.bodyBytes.length,
        'serverTiming': response.headers['server-timing'],
      });
      if (response.statusCode >= 400) {
        debugPrint('Search token prediction failed: ${response.statusCode}');
        return const SearchTokenPredictionResult();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const SearchTokenPredictionResult();
      }
      final context = decoded['prediction_context'] is Map
          ? SearchTokenPredictionContext.fromJson(
              Map<String, dynamic>.from(decoded['prediction_context'] as Map),
            )
          : null;
      return SearchTokenPredictionResult(
        tokens: _predictedNameTokensFromJson(
          decoded['predictions'],
          source: 'token_predict',
        ),
        context: context,
      );
    } catch (error) {
      SearchDebugTrace.instance.record('service.token_predict.error', {
        'query': normalizedQuery,
        'error': '$error',
      });
      debugPrint('Search token prediction failed: $error');
      return const SearchTokenPredictionResult();
    }
  }

  Future<SearchFirstCharWarmupResult> warmSearchFirstCharNameTokens({
    int limit = 1,
    String searchLanguage = 'en',
  }) async {
    try {
      final trace = SearchDebugTrace.instance;
      final normalizedLanguage = _tcgdexLanguage(searchLanguage);
      final cleanLimit = math.min(math.max(limit, 1), 5);
      final started = DateTime.now();
      trace.record('service.token_warmup.request', {
        'limit': cleanLimit,
        'language': normalizedLanguage,
      });
      final uri = Uri.base.resolve('/api/searchbar-token-predict').replace(
        queryParameters: {
          'warmup': '1',
          'limit': '$cleanLimit',
          'search_language': normalizedLanguage,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      trace.record('service.token_warmup.response', {
        'statusCode': response.statusCode,
        'elapsedMs': DateTime.now().difference(started).inMilliseconds,
        'payloadBytes': response.bodyBytes.length,
        'serverTiming': response.headers['server-timing'],
      });
      if (response.statusCode >= 400) {
        debugPrint('Search token warmup failed: ${response.statusCode}');
        return SearchFirstCharWarmupResult(
          language: normalizedLanguage,
          generatedAtMs: 0,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return SearchFirstCharWarmupResult(
          language: normalizedLanguage,
          generatedAtMs: 0,
        );
      }
      return SearchFirstCharWarmupResult.fromJson(decoded);
    } catch (error) {
      SearchDebugTrace.instance.record('service.token_warmup.error', {
        'language': searchLanguage,
        'error': '$error',
      });
      debugPrint('Search token warmup failed: $error');
      return SearchFirstCharWarmupResult(
        language: _tcgdexLanguage(searchLanguage),
        generatedAtMs: 0,
      );
    }
  }

  List<SearchPredictedNameToken> _predictedNameTokensFromResponse(
    Object? decoded,
    SearchAutocompleteContext? context,
  ) {
    if (decoded is! Map<String, dynamic>) {
      return context?.predictedNameTokens ?? const <SearchPredictedNameToken>[];
    }
    final sources = [
      context?.predictedNameTokens ?? const <SearchPredictedNameToken>[],
      _predictedNameTokensFromMeta(decoded['meta']),
      _predictedNameTokensFromDebug(decoded['debug']),
    ];
    final merged = <SearchPredictedNameToken>[];
    final seen = <String>{};
    for (final source in sources) {
      for (final token in source) {
        if (token.normalized.isEmpty ||
            token.display.isEmpty ||
            !seen.add(token.normalized)) {
          continue;
        }
        merged.add(token);
        if (merged.length >= 8) {
          return List.unmodifiable(merged);
        }
      }
    }
    return List.unmodifiable(merged);
  }

  List<SearchPredictedNameToken> _predictedNameTokensFromMeta(Object? meta) {
    if (meta is! Map) {
      return const [];
    }
    final predictive = meta['predictive'];
    if (predictive is! Map) {
      return const [];
    }
    return _predictedNameTokensFromJson(
      predictive['predicted_tokens'] ?? predictive['predictedTokens'],
      source: 'meta.predictive',
    );
  }

  List<SearchPredictedNameToken> _predictedNameTokensFromDebug(Object? debug) {
    if (debug is! Map) {
      return const [];
    }
    final predictivePool = debug['predictivePool'];
    if (predictivePool is! Map) {
      return const [];
    }
    return _predictedNameTokensFromJson(
      predictivePool['predictedTokens'] ?? predictivePool['predicted_tokens'],
      source: 'debug.predictivePool',
    );
  }

  PokemonCard _cardFromSearchCandidate(Map<String, dynamic> row) {
    final id = '${row['card_id'] ?? row['id'] ?? ''}';
    final rarity = _cleanLabel(row['rarity'], fallback: 'Card');
    final setName = _cleanLabel(row['set_name'], fallback: 'Pokemon');
    final rawNumber = '${row['card_number'] ?? ''}';
    final productVariant = '${row['product_variant'] ?? row['version'] ?? ''}';
    final itemKind = _itemKindForProjectedRow(
      itemKind: row['item_kind'],
      productType: row['product_type'],
      number: rawNumber,
    );
    final productType = _productTypeForProjectedRow(
      productType: row['product_type'],
      itemKind: itemKind,
      number: rawNumber,
    );
    final number = itemKind == 'product' ? productVariant : rawNumber;
    final trainerName = _cleanLabel(row['trainer_name'], fallback: '');
    final type = _marketplaceDisplayType(
      productType,
      fallback: _cleanLabel(row['card_type'], fallback: 'Card'),
    );
    final imageUrl =
        _normalizeImageUrl(row['cdn_image_url'] ?? row['image_url'], cardId: id, ctId: row['ct_id'] ?? row['ctId']);
    final previewImageUrl = _normalizeImageUrl(
      row['preview_image_url'] ?? row['cdn_image_url'] ?? row['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'],
    );
    final homepageImageUrl = _normalizeImageUrl(
      row['homepage_image_url'] ??
          row['homepageImageUrl'] ??
          row['preview_image_url'] ??
          row['cdn_image_url'] ??
          row['image_url'],
      cardId: id,
      ctId: row['ct_id'] ?? row['ctId'],
    );
    final artist = _cleanLabel(
      row['artist'] ?? row['illustrator'],
      fallback: '',
    );
    return PokemonCard(
      id: id,
      name: '${row['name'] ?? 'Pokemon card'}',
      imageUrl: imageUrl,
      previewImageUrl: previewImageUrl,
      homepageImageUrl: homepageImageUrl,
      rarity: rarity,
      type: type,
      hp: 0,
      attacks: const [],
      price: (_pknPrices[id] ?? 1000 + (_stableSeed(id) % 120000)).toDouble(),
      description: itemKind == 'product'
          ? 'Imported from the Pokoin autocomplete product projection.'
          : 'Imported from the Pokoin autocomplete projection.',
      set: setName,
      number: number,
      artist: artist,
      stock: 0,
      rating: _readWatchlistCount(row).toDouble(),
      reviewCount: 0,
      isFoil: false,
      isHolo: false,
      releaseDate: _parseDate(row['imported_at']),
      tags: [
        setName,
        rarity,
        type,
        itemKind,
        productType,
        if (trainerName.isNotEmpty) trainerName,
      ],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
      trainerName: trainerName,
      canonicalPath: _cleanCanonicalPath(row),
      watchlistCount: _readWatchlistCount(row),
      cartHolderCount: _readCartHolderCount(row),
      cardPalette: _readCardPalette(row),
      emoji: _readEmoji(row),
    );
  }

  List<PokemonCard> _searchAutocompletePreviewCardsFromRows(
    Iterable<dynamic> rows,
    int limit,
  ) {
    return _dedupeCards(rows
        .whereType<Map>()
        .take(limit)
        .map((row) => _cardFromSearchCandidate(Map<String, dynamic>.from(row)))
        .toList());
  }

  PokemonCard _cardFromHotBlueprint(Map<String, dynamic> row) {
    final id =
        '${row['blueprintId'] ?? row['blueprint_id'] ?? row['card_id'] ?? ''}';
    final setName =
        _cleanLabel(row['set'] ?? row['set_name'], fallback: 'Pokemon');
    final rarity = _cleanLabel(row['rarity'], fallback: 'Card');
    final type = _marketplaceDisplayType(
      _normalizeProductType(row['productType'] ?? row['product_type'],
          '${row['itemKind'] ?? row['item_kind'] ?? 'single'}'),
      fallback: _cleanLabel(row['type'] ?? row['card_type'], fallback: 'Card'),
    );
    final itemKind = _normalizeItemKind(row['itemKind'] ?? row['item_kind']);
    final productType = _normalizeProductType(
        row['productType'] ?? row['product_type'], itemKind);
    final artist = _cleanLabel(
      row['artist'] ?? row['illustrator'],
      fallback: '',
    );
    return PokemonCard(
      id: id,
      name: '${row['name'] ?? 'Pokemon card'}',
      imageUrl: _normalizeImageUrl(
          row['cdn_image_url'] ?? row['imageUrl'] ?? row['image_url'],
          cardId: id,
          ctId: row['ct_id'] ?? row['ctId']),
      previewImageUrl: _normalizeImageUrl(
        row['preview_image_url'] ??
            row['previewImageUrl'] ??
            row['cdn_image_url'] ??
            row['imageUrl'] ??
            row['image_url'],
        cardId: id,
        ctId: row['ct_id'] ?? row['ctId'],
      ),
      homepageImageUrl: _normalizeImageUrl(
        row['homepage_image_url'] ??
            row['homepageImageUrl'] ??
            row['preview_image_url'] ??
            row['previewImageUrl'] ??
            row['cdn_image_url'] ??
            row['imageUrl'] ??
            row['image_url'],
        cardId: id,
        ctId: row['ct_id'] ?? row['ctId'],
      ),
      rarity: itemKind == 'product' ? type : rarity,
      type: type,
      hp: 0,
      attacks: const [],
      price: (_pknPrices[id] ?? 1000 + (_stableSeed(id) % 120000)).toDouble(),
      description: 'Imported from Pokoin hot marketplace analytics.',
      set: setName,
      number: '${row['number'] ?? row['card_number'] ?? ''}',
      artist: artist,
      stock: 0,
      rating: _readWatchlistCount(row).toDouble(),
      reviewCount: 0,
      isFoil: false,
      isHolo: rarity.toLowerCase().contains('holo'),
      releaseDate: DateTime.now(),
      tags: [setName, rarity, type, itemKind, productType],
      condition: 'NM',
      isGraded: false,
      itemKind: itemKind,
      productType: productType,
      trainerName: _cleanLabel(row['trainer_name'], fallback: ''),
      canonicalPath: _cleanCanonicalPath(row),
      watchlistCount: _readWatchlistCount(row),
      cartHolderCount: _readCartHolderCount(row),
    );
  }

  int _readWatchlistCount(Map<String, dynamic> row) {
    final analytics = row['analytics'];
    final analyticsMap = analytics is Map
        ? Map<String, dynamic>.from(analytics)
        : const <String, dynamic>{};
    final candidates = [
      row['watchlistCount'],
      row['watchlist_count'],
      analyticsMap['watchlistCount'],
      analyticsMap['watchlist_count'],
      row['rating'],
    ];
    for (final value in candidates) {
      if (value is num && value > 0) {
        return value.toInt();
      }
      final parsed = int.tryParse('${value ?? ''}'.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return 0;
  }

  int _readCartHolderCount(Map<String, dynamic> row) {
    final analytics = row['analytics'];
    final analyticsMap = analytics is Map
        ? Map<String, dynamic>.from(analytics)
        : const <String, dynamic>{};
    final candidates = [
      row['cartHolderCount'],
      row['cart_holder_count'],
      analyticsMap['cartHolderCount'],
      analyticsMap['cart_holder_count'],
    ];
    for (final value in candidates) {
      if (value is num && value > 0) {
        return value.toInt();
      }
      final parsed = int.tryParse('${value ?? ''}'.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return 0;
  }

  String _readEmoji(Map<String, dynamic> row) {
    return _splitEmojiText(row['emoji']).join(' ').trim();
  }

  List<String> _splitEmojiText(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) {
      return const <String>[];
    }
    return RegExp(
      r'\S(?:[\uFE0F\u{1F3FB}-\u{1F3FF}]|\u200D\S)*',
      unicode: true,
    )
        .allMatches(text)
        .map((match) => match.group(0)!.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  String _cleanCanonicalPath(Map<String, dynamic> row) {
    final text =
        '${row['canonicalPath'] ?? row['canonical_path'] ?? row['marketplacePath'] ?? row['marketplace_path'] ?? ''}'
            .trim();
    if (!text.startsWith('/marketplace/') || !text.contains('/cards/')) {
      return '';
    }
    return text.split('?').first.split('#').first;
  }

  bool _readCardTraderAvailability(Map<String, dynamic> row) {
    final explicit =
        row['hasCardTraderListing'] ?? row['has_cardtrader_listing'];
    if (explicit is bool) {
      return explicit;
    }
    if (explicit is num) {
      return explicit > 0;
    }
    final explicitText = '${explicit ?? ''}'.trim().toLowerCase();
    if (const {'true', '1', 'yes', 'y'}.contains(explicitText)) {
      return true;
    }
    return _readCardTraderEligibleListingCount(row) > 0;
  }

  int _readCardTraderEligibleListingCount(Map<String, dynamic> row) {
    final value = row['cardtraderEligibleListingCount'] ??
        row['cardtrader_eligible_listing_count'];
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  bool _readBoolish(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value > 0;
    }
    final text = '${value ?? ''}'.trim().toLowerCase();
    return const {'true', '1', 'yes', 'y'}.contains(text);
  }

  double? _readMarketplaceTilePrice(Map<String, dynamic> row) {
    final values = [
      row['lowest_price_pkn'],
      row['price'],
      row['cardtraderLowestPricePkn'],
      row['cardtrader_lowest_price_pkn'],
    ];
    for (final value in values) {
      if (value is num && value > 0) {
        return value.toDouble();
      }
      final parsed = double.tryParse('${value ?? ''}'.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  Map<String, dynamic> _readCardPalette(Map<String, dynamic> row) {
    final value = row['card_palette'] ?? row['cardPalette'];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  String _tcgdexLanguage(String language) {
    switch (language.trim().toLowerCase()) {
      case 'it':
      case 'fr':
      case 'de':
      case 'es':
      case 'pt':
      case 'nl':
      case 'pl':
      case 'ru':
      case 'ko':
      case 'id':
      case 'th':
        return language.trim().toLowerCase();
      case 'jp':
      case 'ja':
        return 'ja';
      case 'zh':
      case 'zh-cn':
        return 'zh-cn';
      case 'zh-tw':
        return 'zh-tw';
      default:
        return 'en';
    }
  }

  Future<List<PokemonCard>> _searchMarketplaceCardRows(
    String normalizedQuery, {
    required int limit,
    String? productType,
    bool productSearchOnly = false,
    String searchLanguage = 'en',
    String? searchSessionId,
  }) async {
    try {
      final queryParameters = <String, String>{'limit': '$limit'};
      final normalizedProductType = productType?.trim();
      if (normalizedProductType != null && normalizedProductType.isNotEmpty) {
        queryParameters['productType'] = normalizedProductType;
      } else if (productSearchOnly) {
        queryParameters['productSearchOnly'] = '1';
      }
      if (normalizedQuery.isNotEmpty) {
        queryParameters['query'] = normalizedQuery;
      }
      if (_tcgdexLanguage(searchLanguage) != 'en') {
        queryParameters['search_language'] = _tcgdexLanguage(searchLanguage);
      }
      if (searchSessionId?.trim().isNotEmpty == true) {
        queryParameters['search_session_id'] = searchSessionId!.trim();
      }
      final uri = Uri.base.resolve('/api/marketplace-cards').replace(
            queryParameters: queryParameters,
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return const [];
      }

      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromMarketplaceRow(Map<String, dynamic>.from(row)))
          .toList();
      return _dedupeCards(cards).take(limit).toList();
    } catch (error) {
      debugPrint('Marketplace card row search failed: $error');
      return const [];
    }
  }

  Future<List<PokemonCard>> _searchMarketplaceCardVersions(
    String normalizedQuery, {
    required int limit,
    String? productType,
    String? productCategory,
    String searchLanguage = 'en',
    String? searchSessionId,
  }) async {
    try {
      final queryParameters = <String, String>{'limit': '$limit'};
      final normalizedProductType = productType?.trim();
      if (normalizedProductType != null && normalizedProductType.isNotEmpty) {
        queryParameters['productType'] = normalizedProductType;
      }
      final normalizedProductCategory = productCategory?.trim();
      if (normalizedProductCategory != null &&
          normalizedProductCategory.isNotEmpty) {
        queryParameters['productCategory'] = normalizedProductCategory;
      }
      if (normalizedQuery.isNotEmpty) {
        queryParameters['query'] = normalizedQuery;
      }
      if (_tcgdexLanguage(searchLanguage) != 'en') {
        queryParameters['lang'] = _tcgdexLanguage(searchLanguage);
      }
      if (searchSessionId?.trim().isNotEmpty == true) {
        queryParameters['search_session_id'] = searchSessionId!.trim();
      }
      final uri = Uri.base.resolve('/api/marketplace-card-versions').replace(
            queryParameters: queryParameters,
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode >= 400) {
        return const [];
      }

      final rows = jsonDecode(response.body) as List<dynamic>;
      final cards = rows
          .whereType<Map>()
          .map((row) => _cardFromVersionRow(Map<String, dynamic>.from(row)))
          .toList();
      return _dedupeCards(cards).take(limit).toList();
    } catch (error) {
      debugPrint('Marketplace card version search failed: $error');
      return const [];
    }
  }

  Future<void> recordMarketplaceEvent(
    PokemonCard card,
    String eventType, {
    String source = 'web',
    Map<String, Object?> metadata = const {},
  }) async {
    final id = int.tryParse(card.id);
    if (id == null) {
      return;
    }
    final payloadMetadata = _marketplaceEventMetadata(card, metadata);
    try {
      final authHeaders =
          await PokoinApiAuthService.instance().authorizationHeaders(
        requireSignedIn: false,
      );
      await http
          .post(
            Uri.base.resolve('/api/marketplace-event'),
            headers: {
              'content-type': 'application/json',
              ...authHeaders,
            },
            body: jsonEncode({
              'cardId': id,
              'eventType': eventType,
              'source': source,
              'metadata': payloadMetadata,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Analytics must never block the marketplace UX.
    }
  }

  Future<void> cancelSearchSession({
    required String sessionId,
    required String lastQuery,
    String reason = 'exit',
  }) async {
    if (sessionId.trim().isEmpty) {
      return;
    }
    try {
      await http
          .post(
            Uri.base.resolve('/api/searchbar-cancel'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(_searchCancelPayload(
              sessionId: sessionId,
              lastQuery: lastQuery,
              reason: reason,
            )),
          )
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Search exit cancellation is best-effort and must not block navigation.
    }
  }

  Map<String, dynamic> _searchCancelPayload({
    required String sessionId,
    required String lastQuery,
    required String reason,
  }) {
    return {
      'search_session_id': sessionId.trim(),
      'last_query': lastQuery.trim(),
      'reason': reason.trim().isEmpty ? 'exit' : reason.trim(),
      'client': kIsWeb ? 'flutter_web' : 'flutter',
      'locale': ui.PlatformDispatcher.instance.locale.toLanguageTag(),
    };
  }

  Map<String, Object?> _marketplaceEventMetadata(
    PokemonCard card,
    Map<String, Object?> metadata,
  ) {
    final merged = <String, Object?>{
      'name': card.name,
      'set': card.set,
      'number': card.number,
      'rarity': card.rarity,
      'type': card.type,
      'itemKind': card.itemKind,
      'productType': card.productType,
      'trainerName': card.trainerName,
      if (card.tags.isNotEmpty) 'tags': card.tags.take(8).toList(),
      ...metadata,
    };
    merged.removeWhere((_, value) {
      if (value == null) {
        return true;
      }
      if (value is String) {
        return value.trim().isEmpty;
      }
      if (value is Iterable) {
        return value.isEmpty;
      }
      return false;
    });
    return merged.map((key, value) {
      if (value is String) {
        return MapEntry(
            key, value.length > 160 ? value.substring(0, 160) : value);
      }
      return MapEntry(key, value);
    });
  }

  List<PokemonCard> _rankLocalCards(
    List<PokemonCard> cards,
    String query,
    int limit,
  ) {
    return _rankLocalCardsForQueries(
        cards, _searchQueryVariants([query]), limit);
  }

  List<PokemonCard> _rankLocalCardsForQueries(
    List<PokemonCard> cards,
    List<String> queries,
    int limit,
  ) {
    final ranked = cards
        .asMap()
        .entries
        .map((entry) => (
              card: entry.value,
              sourceIndex: entry.key,
              score: queries.fold<int>(
                0,
                (score, query) => math.max(
                  score,
                  _localSearchScore(entry.value, query.toLowerCase()),
                ),
              ),
            ))
        .where((entry) => entry.score > 0)
        .toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) {
          return score;
        }
        return a.sourceIndex.compareTo(b.sourceIndex);
      });
    return ranked.map((entry) => entry.card).take(limit).toList();
  }

  int _localSearchScore(PokemonCard card, String query) {
    final name = card.name.toLowerCase();
    final set = card.set.toLowerCase();
    final trainerName = card.trainerName.toLowerCase();
    final isProduct = card.itemKind == 'product';
    final number = isProduct ? '' : card.number.toLowerCase();
    final tags = card.tags.join(' ').toLowerCase();
    final haystack = isProduct
        ? '$name $set $trainerName $tags'
        : '$name $set $trainerName $number $tags';
    final terms = _searchTerms(query);
    final compactQuery = query.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactName = name.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactSet = set.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactNumber = number.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactTrainerName = trainerName.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final compactTags = tags.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final nameTerms = _searchTerms(name);
    final setTerms = _searchTerms(set);
    final compactHaystack = [
      compactName,
      compactNumber,
      compactSet,
      compactTrainerName,
      compactTags,
    ].where((part) => part.isNotEmpty).join();
    final nameCoverageBonus =
        _characterCoverageScore(compactName, compactQuery);
    final coverageBonus = math.max(
      nameCoverageBonus,
      _characterCoverageScore(compactHaystack, compactQuery) ~/ 2,
    );
    int boost(int score) => score + coverageBonus;
    final hasNumberTerm =
        terms.any((term) => RegExp(r'^[0-9]+$').hasMatch(term));
    final hasVariationTerm = terms.any(_isVariationSearchTerm);
    final hasRarityTerm = terms.any(_isRaritySearchTerm);
    final hasExpansionAliasTerm = terms.any(_isExpansionAliasSearchTerm);
    final hasTextTerm = terms.any(
      (term) =>
          !RegExp(r'^[0-9]+$').hasMatch(term) &&
          !_isVariationSearchTerm(term) &&
          !_isRaritySearchTerm(term) &&
          !_isExpansionAliasSearchTerm(term),
    );
    int applyCompoundPenalty(int score) => math.max(
          0,
          score +
              _compoundNameCoveragePenalty(
                name: name,
                query: query,
                terms: terms,
                nameTerms: nameTerms,
                baseScore: score,
              ),
        );
    final singleVariationTerm =
        terms.length == 1 && _isVariationSearchTerm(terms.first)
            ? terms.first
            : null;
    if (singleVariationTerm != null) {
      if (_cardHasVariation(card, singleVariationTerm)) {
        return boost(1600);
      }
      if (singleVariationTerm == 'vstar' &&
          _cardHasSetToken(card, singleVariationTerm)) {
        return boost(900);
      }
      return 0;
    }
    if (terms.length > 1 &&
        (hasNumberTerm || hasVariationTerm || hasExpansionAliasTerm) &&
        hasTextTerm) {
      var matchedName = false;
      var matchedNumber = false;
      var matchedVariation = false;
      var matchedExpansion = false;
      var matchedSet = false;
      var score = 0;
      for (final term in terms) {
        final compactTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (RegExp(r'^[0-9]+$').hasMatch(term)) {
          final numberTokens = _searchTerms(number);
          if (number == term ||
              compactNumber == compactTerm ||
              numberTokens.contains(term) ||
              nameTerms.contains(term) ||
              setTerms.contains(term)) {
            score += 1600;
            matchedNumber = true;
          } else if (number.startsWith(term) ||
              compactNumber.startsWith(compactTerm) ||
              name.contains(term) ||
              set.startsWith(term)) {
            score += 1300;
            matchedNumber = true;
          } else if (number.contains(term) ||
              compactNumber.contains(compactTerm) ||
              set.contains(term)) {
            score += 900;
            matchedNumber = true;
          }
          continue;
        }
        if (_isVariationSearchTerm(term)) {
          if (_cardHasVariation(card, term)) {
            score += 1500;
            matchedVariation = true;
          }
          continue;
        }
        if (_isExpansionAliasSearchTerm(term)) {
          if (_cardHasExpansionAlias(card, term)) {
            score += 1550;
            matchedExpansion = true;
          }
          continue;
        }
        if (name == term || compactName == compactTerm) {
          score += 1400;
          matchedName = true;
        } else if (name.startsWith(term) ||
            compactName.startsWith(compactTerm)) {
          score += 1150;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 980;
          matchedName = true;
        } else if (_isLikelyNameTypo(compactName, compactTerm)) {
          score += 760;
          matchedName = true;
        } else if (name.contains(term) || compactName.contains(compactTerm)) {
          score += 720;
          matchedName = true;
        } else if (set.startsWith(term) || compactSet.startsWith(compactTerm)) {
          score += 520;
          matchedSet = true;
        } else if (set.contains(term) || compactSet.contains(compactTerm)) {
          score += 360;
          matchedSet = true;
        }
      }
      if (hasVariationTerm && !matchedVariation) {
        return 0;
      }
      if (matchedName && matchedNumber) {
        return applyCompoundPenalty(boost(score + 5200));
      }
      if (matchedName && matchedExpansion) {
        return applyCompoundPenalty(boost(score + 4200));
      }
      if (matchedName && matchedVariation) {
        return applyCompoundPenalty(boost(score + 5000));
      }
      if (matchedName && matchedSet) {
        return applyCompoundPenalty(boost(score + 700));
      }
      if (matchedName && hasVariationTerm) {
        return applyCompoundPenalty(boost(score + 900));
      }
      if (matchedNumber || matchedVariation || matchedExpansion) {
        return 0;
      }
    }
    if (number == query) {
      return boost(980);
    }
    if (number.startsWith(query)) {
      return boost(880);
    }
    if (_wordStartsWith(number, query)) {
      return boost(840);
    }
    if (name == query) {
      return applyCompoundPenalty(boost(1000));
    }
    if (compactQuery.isNotEmpty) {
      final nameDistance = _boundedDamerauLevenshtein(
        compactName,
        compactQuery,
        math.max(2, compactQuery.length ~/ 4),
      );
      if (nameDistance <= 2 && compactQuery.length >= 5) {
        return boost(940 - (nameDistance * 70));
      }
      if (compactName.startsWith(compactQuery)) {
        return applyCompoundPenalty(boost(760));
      }
      final fuzzyName = _fuzzyPrefixScore(compactName, compactQuery);
      if (fuzzyName > 0) {
        if (terms.length <= 1 &&
            compactQuery.length >= 5 &&
            !compactName.contains(compactQuery) &&
            !compactQuery.contains(compactName)) {
          final prefix = compactName.substring(
            0,
            math.min(compactName.length, compactQuery.length),
          );
          final prefixDistance = _boundedDamerauLevenshtein(
            prefix,
            compactQuery,
            2,
          );
          if (prefixDistance > 2) {
            final fullDistance = _boundedDamerauLevenshtein(
              compactName,
              compactQuery,
              2,
            );
            if (fullDistance > 2) {
              return 0;
            }
          }
        }
        return applyCompoundPenalty(boost(fuzzyName));
      }
      final fuzzySet = _fuzzyPrefixScore(compactSet, compactQuery);
      if (fuzzySet > 0) {
        return boost(fuzzySet ~/ 2);
      }
    }
    if (terms.length > 1 && terms.every(haystack.contains)) {
      var score = 520;
      var matchedName = false;
      var matchedSet = false;
      var matchedNumber = false;
      var matchedRarity = false;
      for (final term in terms) {
        if (_isRaritySearchTerm(term) && _cardHasRarityHint(card, term)) {
          score += 220;
          matchedRarity = true;
        } else if (number == term) {
          score += 220;
          matchedNumber = true;
        } else if (nameTerms.contains(term)) {
          score += 260;
          matchedName = true;
        } else if (number.startsWith(term)) {
          score += 190;
          matchedNumber = true;
        } else if (_wordStartsWith(number, term) || setTerms.contains(term)) {
          score += 170;
          matchedNumber = true;
        } else if (number.contains(term)) {
          score += 140;
          matchedNumber = true;
        } else if (name.startsWith(term)) {
          score += 190;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 150;
          matchedName = true;
        } else if (name.contains(term)) {
          score += 80;
          matchedName = true;
        } else if (set.startsWith(term)) {
          score += 180;
          matchedSet = true;
        } else if (_wordStartsWith(set, term)) {
          score += 160;
          matchedSet = true;
        } else if (set.contains(term)) {
          score += 120;
          matchedSet = true;
        } else if (trainerName == term) {
          score += 210;
          matchedName = true;
        } else if (trainerName.startsWith(term)) {
          score += 170;
          matchedName = true;
        } else if (trainerName.contains(term)) {
          score += 120;
          matchedName = true;
        }
      }
      if (matchedName && matchedSet) {
        score += 140;
      }
      if (matchedName && matchedRarity) {
        score += 420;
      }
      if (matchedNumber && matchedName) {
        score += 180;
      } else if (matchedNumber && matchedSet) {
        score += 120;
      }
      return boost(score);
    }
    if (terms.length > 1 && hasRarityTerm && hasTextTerm) {
      var score = 420;
      var matchedName = false;
      var matchedRarity = false;
      for (final term in terms) {
        if (_isRaritySearchTerm(term)) {
          if (_cardHasRarityHint(card, term)) {
            score += 420;
            matchedRarity = true;
          }
        } else if (nameTerms.contains(term)) {
          score += 700;
          matchedName = true;
        } else if (name.startsWith(term)) {
          score += 260;
          matchedName = true;
        } else if (_wordStartsWith(name, term)) {
          score += 220;
          matchedName = true;
        } else if (name.contains(term)) {
          score += 160;
          matchedName = true;
        }
      }
      if (matchedName && matchedRarity) {
        return applyCompoundPenalty(boost(score));
      }
    }
    if (name.startsWith(query)) {
      return applyCompoundPenalty(boost(800));
    }
    if (name.contains(query)) {
      return applyCompoundPenalty(boost(600));
    }
    if (number.contains(query)) {
      return boost(700);
    }
    if (set.contains(query)) {
      return boost(350);
    }
    if (trainerName == query) {
      return boost(760);
    }
    if (trainerName.startsWith(query)) {
      return boost(640);
    }
    if (trainerName.contains(query)) {
      return boost(480);
    }
    if (tags.contains(query)) {
      return boost(180);
    }
    if (_canUseLooseCoverageFallback(
      terms: terms,
      compactQuery: compactQuery,
      compactName: compactName,
      hasStructuredIntent: hasTextTerm &&
          (hasNumberTerm ||
              hasVariationTerm ||
              hasRarityTerm ||
              hasExpansionAliasTerm),
      nameCoverageBonus: nameCoverageBonus,
      coverageBonus: coverageBonus,
    )) {
      return coverageBonus;
    }
    return 0;
  }

  bool _canUseLooseCoverageFallback({
    required List<String> terms,
    required String compactQuery,
    required String compactName,
    required bool hasStructuredIntent,
    required int nameCoverageBonus,
    required int coverageBonus,
  }) {
    if (coverageBonus < 220 || compactQuery.isEmpty) {
      return false;
    }

    // Query parts like "232", "ex", "v", or "sir" are structured intent, not
    // free text. Do not let ordered-character matching override exact fields.
    if (hasStructuredIntent) {
      return false;
    }

    // For complete single-word names, loose ordered-character coverage across
    // name + set + tags admits unrelated cards like "Pokemon Communication" for
    // "porygon". Keep it only for short in-progress typing and strong name hits.
    if (terms.length <= 1 && compactQuery.length >= 5) {
      return compactName.startsWith(compactQuery[0]) &&
          nameCoverageBonus >= 260;
    }

    return true;
  }

  int _fuzzyPrefixScore(String target, String query) {
    if (query.isEmpty || target.isEmpty) {
      return 0;
    }
    final windowLength = math.min(target.length, math.max(query.length + 2, 3));
    final window = target.substring(0, windowLength);
    final subsequence = _orderedCharacterMatchScore(window, query);
    if (subsequence > 0) {
      return subsequence;
    }
    final prefix = target.substring(0, math.min(target.length, query.length));
    final prefixDistance = _boundedDamerauLevenshtein(prefix, query, 2);
    if (prefixDistance <= 1) {
      return 700 - (prefixDistance * 80);
    }
    final distance = _boundedDamerauLevenshtein(window, query, 2);
    if (distance <= 1) {
      return 720 - (distance * 80);
    }
    if ((target.length - query.length).abs() <= 2) {
      final fullDistance = _boundedDamerauLevenshtein(target, query, 2);
      if (fullDistance <= 1) {
        return 720 - (fullDistance * 80);
      }
      if (fullDistance == 2 && query.length >= 5) {
        return 520;
      }
    }
    if (distance == 2 && query.length >= 3) {
      return 520;
    }
    return 0;
  }

  int _orderedCharacterMatchScore(String target, String query) {
    var targetIndex = 0;
    var gaps = 0;
    for (final codeUnit in query.codeUnits) {
      final nextIndex =
          target.indexOf(String.fromCharCode(codeUnit), targetIndex);
      if (nextIndex < 0) {
        return 0;
      }
      gaps += nextIndex - targetIndex;
      targetIndex = nextIndex + 1;
    }
    return math.max(420, 700 - (gaps * 40));
  }

  int _characterCoverageScore(String target, String query) {
    if (target.isEmpty || query.isEmpty) {
      return 0;
    }
    var targetIndex = 0;
    var matched = 0;
    var gaps = 0;
    for (final codeUnit in query.codeUnits) {
      final nextIndex =
          target.indexOf(String.fromCharCode(codeUnit), targetIndex);
      if (nextIndex < 0) {
        continue;
      }
      matched += 1;
      gaps += nextIndex - targetIndex;
      targetIndex = nextIndex + 1;
    }
    if (matched == 0) {
      return 0;
    }
    final coverage = matched / query.length;
    final matchedScore = matched * 34;
    final coverageScore = (coverage * 180).round();
    return math.max(0, matchedScore + coverageScore - (gaps * 4));
  }

  int _boundedDamerauLevenshtein(String a, String b, int maxDistance) {
    if ((a.length - b.length).abs() > maxDistance) {
      return maxDistance + 1;
    }
    final matrix = List.generate(
      a.length + 1,
      (i) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i += 1) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j += 1) {
      matrix[0][j] = j;
    }
    for (var i = 1; i <= a.length; i += 1) {
      var rowMin = maxDistance + 1;
      for (var j = 1; j <= b.length; j += 1) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var value = math.min(
          math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
          matrix[i - 1][j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          value = math.min(value, matrix[i - 2][j - 2] + 1);
        }
        matrix[i][j] = value;
        rowMin = math.min(rowMin, value);
      }
      if (rowMin > maxDistance) {
        return maxDistance + 1;
      }
    }
    return matrix[a.length][b.length];
  }

  List<String> _searchTerms(String query) {
    final rawTerms = _normalizeVariationSearchPhrases(query)
        .toLowerCase()
        .replaceAllMapped(
          RegExp(r'\b([a-z0-9]+)s\b'),
          (match) => "${match.group(1)}'s",
        )
        .split(RegExp(r'[^a-z0-9]+'))
        .map((term) => term.trim())
        .toList();
    return rawTerms
        .where((term) =>
            term.length >= 2 ||
            term == 'v' ||
            term == 'n' ||
            ((term == 'g' || term == 'e') && rawTerms.length > 1))
        .toList();
  }

  String _normalizeVariationSearchPhrases(String value) {
    return value
        .replaceAll('&', ' tagteam ')
        .replaceAll(RegExp(r'\blv\s*\.?\s*x\b', caseSensitive: false), 'lvx')
        .replaceAll(RegExp(r'\blevel\s+x\b', caseSensitive: false), 'lvx')
        .replaceAll(RegExp(r'\bv\s*max\b', caseSensitive: false), 'vmax')
        .replaceAll(RegExp(r'\bv\s*star\b', caseSensitive: false), 'vstar')
        .replaceAll(RegExp(r'\bg\s*x\b', caseSensitive: false), 'gx')
        .replaceAll(RegExp(r'\be\s*x\b', caseSensitive: false), 'ex');
  }

  bool _isVariationSearchTerm(String term) {
    return _variationSearchTargets(term).isNotEmpty;
  }

  bool _cardHasVariation(PokemonCard card, String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final targets = _variationSearchTargets(normalizedTerm);
    if (targets.isNotEmpty && !targets.contains(normalizedTerm)) {
      return targets.any((target) => _cardHasVariation(card, target));
    }
    final text = [
      card.name,
      card.rarity,
      card.type,
      card.productType,
      ...card.tags,
    ].join(' ').toLowerCase();
    switch (normalizedTerm) {
      case 'lvx':
        return RegExp(r'(^|[^a-z0-9])(lv\.?x|level x)([^a-z0-9]|$)')
            .hasMatch(text);
      case 'lv':
        return RegExp(r'(^|[^a-z0-9])lv\.?([0-9]+|x)([^a-z0-9]|$)')
            .hasMatch(text);
      case 'v':
        return RegExp(r'(^|[^a-z0-9])v([^a-z0-9]|$)').hasMatch(text);
      case 'mega':
        return RegExp(r'(^|[^a-z0-9])(mega|m)([^a-z0-9]|$)').hasMatch(text);
      case 'tagteam':
        return RegExp(r'(^|[^a-z0-9])(tag\s*team|tagteam|&)([^a-z0-9]|$)')
            .hasMatch(text);
      default:
        return RegExp('(^|[^a-z0-9])$normalizedTerm([^a-z0-9]|\$)')
            .hasMatch(text);
    }
  }

  List<String> _variationSearchTargets(String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalizedTerm.isEmpty) {
      return const [];
    }
    const variations = [
      'ex',
      'v',
      'vmax',
      'vstar',
      'gx',
      'lvx',
      'lv',
      'mega',
      'break',
      'radiant',
      'shining',
      'shiny',
      'prime',
      'tagteam',
    ];
    if (variations.contains(normalizedTerm)) {
      return [normalizedTerm];
    }
    if (normalizedTerm == 'g' ||
        normalizedTerm == 'e' ||
        normalizedTerm.length >= 2) {
      return variations
          .where((variation) => variation.startsWith(normalizedTerm))
          .toList(growable: false);
    }
    return const [];
  }

  bool _isRaritySearchTerm(String term) {
    const rarities = {
      'sir',
      'ir',
      'ur',
      'sr',
      'rare',
      'ultra',
      'secret',
      'ill',
      'illus',
      'illustration',
      'holo',
      'shiny',
    };
    return rarities.contains(term.replaceAll(RegExp(r'[^a-z0-9]'), ''));
  }

  bool _cardHasSetToken(PokemonCard card, String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalizedTerm.isEmpty) {
      return false;
    }
    return RegExp('(^|[^a-z0-9])$normalizedTerm([^a-z0-9]|\$)')
        .hasMatch(card.set.toLowerCase());
  }

  bool _cardHasRarityHint(PokemonCard card, String term) {
    final normalizedTerm = term.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final text = [
      card.number,
      card.rarity,
      ...card.tags,
    ].join(' ').toLowerCase();
    final normalizedText = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    switch (normalizedTerm) {
      case 'sir':
        return normalizedText.contains('special illustration rare');
      case 'ir':
        return normalizedText.contains('illustration rare');
      case 'ill':
      case 'illus':
      case 'illustration':
        return normalizedText.contains('illustration rare');
      case 'ur':
      case 'ultra':
        return normalizedText.contains('ultra rare');
      case 'sr':
      case 'secret':
        return normalizedText.contains('secret rare');
      default:
        return normalizedText.contains(normalizedTerm);
    }
  }

  List<String> _expansionAliasTargets(String term) {
    const aliases = {
      'col': ['calloflegends'],
      'calllegends': ['calloflegends'],
      'calloflegends': ['calloflegends'],
      'hgss': [
        'heartgoldsoulsilver',
        'unleashed',
        'undaunted',
        'triumphant',
        'calloflegends'
      ],
      'hgs': [
        'heartgoldsoulsilver',
        'unleashed',
        'undaunted',
        'triumphant',
        'calloflegends'
      ],
      'heartgold': [
        'heartgoldsoulsilver',
        'heartgoldcollection',
        'unleashed',
        'undaunted',
        'triumphant',
        'calloflegends'
      ],
      'hearthgold': [
        'heartgoldsoulsilver',
        'heartgoldcollection',
        'unleashed',
        'undaunted',
        'triumphant',
        'calloflegends'
      ],
      'soulsilver': [
        'heartgoldsoulsilver',
        'soulsilvercollection',
        'unleashed',
        'undaunted',
        'triumphant',
        'calloflegends'
      ],
      'heartgoldsoulsilver': [
        'heartgoldsoulsilver',
        'unleashed',
        'undaunted',
        'triumphant',
        'calloflegends'
      ],
      'unleashed': ['unleashed'],
      'undaunted': ['undaunted'],
      'triumphant': ['triumphant'],
      '151': ['151', 'pokemoncard151', 'collect151'],
      'pokemon151': ['pokemoncard151'],
      'pokemoncard151': ['pokemoncard151'],
      'collect151': ['collect151'],
      'cel': ['celebrations'],
      'pal': ['paldeaevolved'],
      'obf': ['obsidianflames'],
      'obs': ['obsidianflames'],
      'svi': ['scarletviolet'],
      'sv': ['scarletviolet'],
    };
    return aliases[term.replaceAll(RegExp(r'[^a-z0-9]'), '')] ?? const [];
  }

  bool _isExpansionAliasSearchTerm(String term) {
    return _expansionAliasTargets(term).isNotEmpty;
  }

  bool _cardHasExpansionAlias(PokemonCard card, String term) {
    final compactSet =
        card.set.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _expansionAliasTargets(term).any(
      (target) =>
          compactSet == target ||
          compactSet.startsWith(target) ||
          target.startsWith(compactSet),
    );
  }

  bool _isLikelyNameTypo(String compactName, String compactTerm) {
    if (compactTerm.length < 5 || compactName.isEmpty) {
      return false;
    }
    return compactName.startsWith(compactTerm.substring(0, 2)) &&
        _boundedDamerauLevenshtein(compactName, compactTerm, 3) <= 3;
  }

  int _compoundNameCoveragePenalty({
    required String name,
    required String query,
    required List<String> terms,
    required List<String> nameTerms,
    required int baseScore,
  }) {
    if (!RegExp(r'(^|[^a-z0-9])(&|and|tag\s*team|tagteam)([^a-z0-9]|$)',
            caseSensitive: false)
        .hasMatch(name)) {
      return 0;
    }
    final queryRoots = _nameRootTokens(query).toSet();
    if (queryRoots.isEmpty) {
      return 0;
    }
    final queryRoot = queryRoots.first;
    final candidateRoots = _nameRootTokens(name).toSet();
    if (candidateRoots.length < 2 || !candidateRoots.contains(queryRoot)) {
      return 0;
    }
    if (queryRoots.length > 1) {
      final missingTypedRoots =
          queryRoots.where((root) => !candidateRoots.contains(root)).length;
      if (missingTypedRoots > 0) {
        return -math.max(
          3600 + (missingTypedRoots * 1200),
          (baseScore * 0.65).round(),
        );
      }
      return 0;
    }
    final typedRoots = terms
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(candidateRoots.contains)
        .toSet();
    final untypedExtraRoots = candidateRoots
        .where((root) => root != queryRoot && !typedRoots.contains(root))
        .length;
    if (untypedExtraRoots <= 0) {
      return 0;
    }
    final queryRootIsExactNameToken = nameTerms
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .contains(queryRoot);
    final coveragePenalty =
        (baseScore * (untypedExtraRoots / candidateRoots.length)).round();
    final fixedPenalty =
        queryRootIsExactNameToken ? 3600 + (untypedExtraRoots * 900) : 1800;
    return -math.max(fixedPenalty, coveragePenalty + 1800);
  }

  List<String> _nameRootTokens(String value) {
    const stopWords = {
      'ex',
      'v',
      'vmax',
      'vstar',
      'gx',
      'lvx',
      'lv',
      'mega',
      'break',
      'radiant',
      'shining',
      'shiny',
      'prime',
      'tagteam',
      'and',
      'gold',
      'star',
      'legend',
      'delta',
      'species',
    };
    return _searchTerms(value)
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((term) =>
            term.length >= 3 &&
            !stopWords.contains(term) &&
            !RegExp(r'^[0-9]+$').hasMatch(term) &&
            !_isRaritySearchTerm(term) &&
            !_isExpansionAliasSearchTerm(term))
        .toList(growable: false);
  }

  List<String> _searchQueryVariants(Iterable<String> queries) {
    final variants = <String>[];
    for (final query in queries) {
      final normalized = query.trim().toLowerCase();
      if (_meaningfulSearchLength(normalized) < 1) {
        continue;
      }
      _addUnique(variants, normalized);
      final expanded = _expandCompactSearchAliases(normalized);
      _addUnique(variants, expanded);
      for (final localizedAlias in _localizedAliasQueryVariants(normalized)) {
        _addUnique(variants, localizedAlias);
      }
      for (final trainerVariant in _trainerQueryVariants(normalized)) {
        _addUnique(variants, trainerVariant);
      }
      for (final alias in _raritySearchAliases.entries) {
        if (_containsCompactAlias(normalized, alias.key)) {
          _addUnique(variants, alias.value);
          _addUnique(
            variants,
            _expandCompactSearchAliases(
              normalized.replaceAll(alias.key, alias.value),
            ),
          );
        }
      }
    }
    return variants;
  }

  int _meaningfulSearchLength(String query) {
    return RegExp(r'[a-z0-9]', caseSensitive: false).allMatches(query).length;
  }

  List<String> _localizedAliasQueryVariants(String query) {
    final terms = _searchTerms(query);
    if (terms.isEmpty) {
      return const [];
    }
    final variants = <String>[];
    for (var i = 0; i < terms.length; i += 1) {
      final canonicalTrainer = _trainerSearchAliases[terms[i]];
      if (canonicalTrainer == null || canonicalTrainer == terms[i]) {
        continue;
      }
      final rewritten = [...terms];
      rewritten[i] = canonicalTrainer;
      _addUnique(variants, rewritten.join(' '));
      _addUnique(variants, canonicalTrainer);
    }
    return variants;
  }

  String _expandCompactSearchAliases(String query) {
    var expanded = query;
    for (final alias in _raritySearchAliases.entries) {
      expanded = expanded.replaceAllMapped(
        RegExp('(^|[^a-z0-9])${alias.key}([^a-z0-9]|\$)'),
        (match) => '${match.group(1)}${alias.value}${match.group(2)}',
      );
    }
    return expanded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _trainerQueryVariants(String query) {
    final terms = _searchTerms(query);
    if (terms.length < 2) {
      return const [];
    }
    final variants = <String>[];
    for (var i = 0; i < terms.length; i += 1) {
      final canonicalTrainer = _trainerSearchAliases[terms[i]];
      if (canonicalTrainer == null) {
        continue;
      }
      final pokemonTerms = [
        for (var j = 0; j < terms.length; j += 1)
          if (j != i && !_ownershipStopWords.contains(terms[j])) terms[j],
      ];
      if (pokemonTerms.isEmpty) {
        _addUnique(variants, canonicalTrainer);
        continue;
      }
      final pokemonQuery = pokemonTerms.join(' ');
      _addUnique(variants, '$pokemonQuery $canonicalTrainer');
      _addUnique(variants, '$canonicalTrainer $pokemonQuery');
      _addUnique(variants, "$canonicalTrainer's $pokemonQuery");
    }
    return variants;
  }

  bool _containsCompactAlias(String query, String alias) {
    return RegExp('(^|[^a-z0-9])$alias([^a-z0-9]|\$)').hasMatch(query);
  }

  void _addUnique(List<String> values, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isNotEmpty && !values.contains(normalized)) {
      values.add(normalized);
    }
  }

  bool _wordStartsWith(String value, String term) {
    return value
        .split(RegExp(r'[^a-z0-9]+'))
        .any((word) => word.startsWith(term));
  }

  List<PokemonCard> _dedupeCards(List<PokemonCard> cards) {
    final seen = <String>{};
    final unique = <PokemonCard>[];
    for (final card in cards) {
      if (seen.add(card.id)) {
        unique.add(card);
      }
    }
    return unique;
  }

  Future<List<PokemonCard>> getCardsByRarity(String rarity) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.rarity == rarity).toList();
    } catch (e) {
      debugPrint('Error getting cards by rarity: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsByType(String type) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.type == type).toList();
    } catch (e) {
      debugPrint('Error getting cards by type: $e');
      return [];
    }
  }

  Future<List<PokemonCard>> getCardsBySet(String setName) async {
    try {
      final allCards = await getAllCards();
      return allCards.where((card) => card.set == setName).toList();
    } catch (e) {
      debugPrint('Error getting cards by set: $e');
      return [];
    }
  }

  Future<void> addCard(PokemonCard card) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      await box.add(card);
    } catch (e) {
      debugPrint('Error adding card: $e');
      rethrow;
    }
  }

  Future<void> updateCard(PokemonCard card) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys
          .firstWhere((key) => box.get(key)?.id == card.id, orElse: () => -1);
      if (key != -1) {
        await box.put(key, card);
      }
    } catch (e) {
      debugPrint('Error updating card: $e');
      rethrow;
    }
  }

  Future<void> deleteCard(String cardId) async {
    try {
      final box = await Hive.openBox<PokemonCard>(_cardsBoxName);
      final key = box.keys
          .firstWhere((key) => box.get(key)?.id == cardId, orElse: () => -1);
      if (key != -1) {
        await box.delete(key);
      }
    } catch (e) {
      debugPrint('Error deleting card: $e');
      rethrow;
    }
  }

  List<PokemonCard> _getSampleCards() {
    return [
      PokemonCard(
        id: '1',
        name: 'Pikachu',
        imageUrl: 'https://images.pokemontcg.io/base1/58_hires.png',
        rarity: 'Common',
        type: 'Lightning',
        hp: 40,
        attacks: ['Thunder Shock', 'Thunder'],
        price: _pknPrices['1']!,
        description: 'A cute electric mouse Pokémon.',
        set: 'Base Set',
        number: '58',
        artist: 'Atsuko Nishida',
        stock: 0,
        rating: 4.5,
        reviewCount: 23,
        isFoil: false,
        isHolo: false,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Lightning', 'Common', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '2',
        name: 'Charizard',
        imageUrl: 'https://images.pokemontcg.io/base1/4_hires.png',
        rarity: 'Rare Holo',
        type: 'Fire',
        hp: 120,
        attacks: ['Fire Spin', 'Flamethrower'],
        price: _pknPrices['2']!,
        description: 'A powerful dragon Pokémon.',
        set: 'Base Set',
        number: '4',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.9,
        reviewCount: 156,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Fire', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '3',
        name: 'Blastoise',
        imageUrl: 'https://images.pokemontcg.io/base1/2_hires.png',
        rarity: 'Rare Holo',
        type: 'Water',
        hp: 100,
        attacks: ['Hydro Pump', 'Rain Dance'],
        price: _pknPrices['3']!,
        description: 'A powerful water turtle Pokémon.',
        set: 'Base Set',
        number: '2',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.7,
        reviewCount: 89,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Water', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '4',
        name: 'Venusaur',
        imageUrl: 'https://images.pokemontcg.io/base1/15_hires.png',
        rarity: 'Rare Holo',
        type: 'Grass',
        hp: 100,
        attacks: ['Solar Beam', 'Razor Leaf'],
        price: _pknPrices['4']!,
        description: 'A powerful grass dinosaur Pokémon.',
        set: 'Base Set',
        number: '15',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.6,
        reviewCount: 67,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Grass', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '5',
        name: 'Alakazam',
        imageUrl: 'https://images.pokemontcg.io/base1/1_hires.png',
        rarity: 'Rare Holo',
        type: 'Psychic',
        hp: 80,
        attacks: ['Confuse Ray', 'Psybeam'],
        price: _pknPrices['5']!,
        description: 'A powerful psychic Pokémon.',
        set: 'Base Set',
        number: '1',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.4,
        reviewCount: 45,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Psychic', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
      PokemonCard(
        id: '6',
        name: 'Machamp',
        imageUrl: 'https://images.pokemontcg.io/base1/8_hires.png',
        rarity: 'Rare Holo',
        type: 'Fighting',
        hp: 100,
        attacks: ['Karate Chop', 'Submission'],
        price: _pknPrices['6']!,
        description: 'A powerful fighting Pokémon.',
        set: 'Base Set',
        number: '8',
        artist: 'Mitsuhiro Arita',
        stock: 0,
        rating: 4.3,
        reviewCount: 34,
        isFoil: true,
        isHolo: true,
        releaseDate: DateTime(1996, 10, 20),
        tags: ['Fighting', 'Rare Holo', 'Base Set'],
        condition: 'NM',
        isGraded: false,
      ),
    ];
  }
}

class MarketplaceHomeSnapshot {
  const MarketplaceHomeSnapshot({
    required this.cards,
    required this.sections,
  });

  final List<PokemonCard> cards;
  final MarketplaceHomeSections sections;

  Map<String, dynamic> toJson() {
    return {
      'cards': cards.map((card) => card.toJson()).toList(),
      'sections': sections.toJson(),
    };
  }
}

class MarketplaceHomeSections {
  const MarketplaceHomeSections({
    required this.recentlySeenIds,
    required this.bestSellerIds,
    required this.featuredIds,
    this.newArrivalIds = const [],
  });

  final List<String> recentlySeenIds;
  final List<String> bestSellerIds;
  final List<String> featuredIds;
  final List<String> newArrivalIds;

  Map<String, dynamic> toJson() {
    return {
      'recentlySeenIds': recentlySeenIds,
      'bestSellerIds': bestSellerIds,
      'featuredIds': featuredIds,
      'newArrivalIds': newArrivalIds,
    };
  }
}
