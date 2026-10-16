import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';
import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../services/card_service.dart';
import '../services/pokoin_api_client.dart';
import '../widgets/site_footer.dart';

enum _ShardRequestMode {
  cards('cards', 'Card list'),
  deck('deck', 'Deck shard');

  const _ShardRequestMode(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class ParsedDeckCard {
  const ParsedDeckCard({
    required this.quantity,
    required this.name,
    required this.setCode,
    required this.collectorNumber,
    required this.category,
    required this.rawLine,
  });

  final int quantity;
  final String name;
  final String setCode;
  final String collectorNumber;
  final String category;
  final String rawLine;
}

class DecklistParseResult {
  const DecklistParseResult({
    required this.cards,
    required this.warnings,
  });

  final List<ParsedDeckCard> cards;
  final List<String> warnings;
}

DecklistParseResult parseLimitlessDeckList(String deckList) {
  final cards = <ParsedDeckCard>[];
  final warnings = <String>[];
  final declaredCounts = <String, int>{};
  final parsedCounts = <String, int>{};
  var currentCategory = 'Unknown';

  final lines = deckList.replaceAll('\r', '').split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final rawLine = lines[index];
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final headerMatch = RegExp(
      r'^(Pok[eé]mon|Pokemon|Trainer|Energy)\s*:\s*(\d+)?$',
      caseSensitive: false,
    ).firstMatch(line);
    if (headerMatch != null) {
      currentCategory = _normalizeDeckCategory(headerMatch.group(1)!);
      final declaredCount = int.tryParse(headerMatch.group(2) ?? '');
      if (declaredCount != null) {
        declaredCounts[currentCategory] = declaredCount;
      }
      continue;
    }

    final parts = line.split(RegExp(r'\s+'));
    final quantity = parts.isEmpty ? null : int.tryParse(parts.first);
    if (quantity == null || quantity <= 0 || parts.length < 4) {
      warnings.add('Line ${index + 1} was not imported: "$line".');
      continue;
    }

    final collectorNumber = parts.last;
    final setCode = parts[parts.length - 2];
    final name = parts.sublist(1, parts.length - 2).join(' ').trim();
    if (name.isEmpty || setCode.isEmpty || collectorNumber.isEmpty) {
      warnings.add('Line ${index + 1} was not imported: "$line".');
      continue;
    }

    cards.add(
      ParsedDeckCard(
        quantity: quantity,
        name: name,
        setCode: setCode,
        collectorNumber: collectorNumber,
        category: currentCategory,
        rawLine: line,
      ),
    );
    parsedCounts[currentCategory] =
        (parsedCounts[currentCategory] ?? 0) + quantity;
  }

  for (final entry in declaredCounts.entries) {
    final parsedCount = parsedCounts[entry.key] ?? 0;
    if (parsedCount != entry.value) {
      warnings.add(
        '${entry.key} declares ${entry.value} cards but $parsedCount were imported.',
      );
    }
  }

  if (cards.isEmpty && warnings.isEmpty) {
    warnings.add(
        'Paste a Limitless decklist with quantity, name, set, and number lines.');
  }

  return DecklistParseResult(cards: cards, warnings: warnings);
}

String _normalizeDeckCategory(String value) {
  final normalized = value.toLowerCase().replaceAll('é', 'e');
  if (normalized == 'pokemon') {
    return 'Pokemon';
  }
  if (normalized == 'trainer') {
    return 'Trainer';
  }
  if (normalized == 'energy') {
    return 'Energy';
  }
  return 'Unknown';
}

class _DeckCardSelection {
  _DeckCardSelection(this.card)
      : versionController = TextEditingController(
          text: '${card.setCode} ${card.collectorNumber}',
        );

  final ParsedDeckCard card;
  final TextEditingController versionController;
  String? language;
  String? condition;
  DeckCardVersionSuggestion? selectedVersion;
  bool versionEditedManually = false;

  Map<String, dynamic> toPayload() {
    final selected = selectedVersion;
    return {
      'quantity': card.quantity,
      'name': card.name,
      'setCode': card.setCode,
      'collectorNumber': card.collectorNumber,
      'category': card.category,
      'rawLine': card.rawLine,
      'version': selected?.label ?? versionController.text.trim(),
      if (selected != null)
        'selectedVersion': {
          'cardId': selected.card.id,
          'name': selected.card.name,
          'set': selected.card.set,
          'number': selected.card.number,
          'rarity': selected.card.rarity,
          'canonicalPath': selected.card.canonicalPath,
          'imageUrl': selected.imageUrl,
        },
      'language': language,
      'condition': condition,
    };
  }

  void dispose() {
    versionController.dispose();
  }
}

class DeckCardVersionSuggestion {
  const DeckCardVersionSuggestion(this.card);

  final PokemonCard card;

  String get imageUrl {
    final preview = card.previewImageUrl.trim();
    if (preview.isNotEmpty) {
      return preview;
    }
    final image = card.imageUrl.trim();
    if (image.isNotEmpty) {
      return image;
    }
    return card.homepageImageUrl.trim();
  }

  String get label {
    final set = card.set.trim();
    final number = card.number.trim();
    if (set.isEmpty && number.isEmpty) {
      return card.name.trim();
    }
    return [
      card.name.trim(),
      if (set.isNotEmpty || number.isNotEmpty)
        '(${[set, number].where((part) => part.isNotEmpty).join(' ')})',
    ].where((part) => part.isNotEmpty).join(' ');
  }
}

String deckCardLookupKey(ParsedDeckCard card) {
  return [
    _normalizeDeckLookupText(card.name),
    _normalizeDeckLookupText(card.setCode),
    _normalizeDeckLookupNumber(card.collectorNumber),
  ].join('|');
}

List<DeckCardVersionSuggestion> rankDeckVersionSuggestionsForCard(
  ParsedDeckCard parsedCard,
  List<PokemonCard> cards, {
  int limit = 8,
}) {
  final targetName = _normalizeDeckLookupText(parsedCard.name);
  final targetSetCode = _normalizeDeckLookupText(parsedCard.setCode);
  final targetNumber = _normalizeDeckLookupNumber(parsedCard.collectorNumber);
  final targetSetNames = _deckSetCodeExpansionAliases(targetSetCode);
  final ranked = <({PokemonCard card, int score})>[];
  final seen = <String>{};

  for (final card in cards) {
    final cardName = _normalizeDeckLookupText(card.name);
    final cardNumber = _normalizeDeckLookupNumber(card.number);
    final cardSet = _normalizeDeckLookupText(card.set);
    final imageUrl = DeckCardVersionSuggestion(card).imageUrl;
    if (card.id.trim().isEmpty || imageUrl.isEmpty || !seen.add(card.id)) {
      continue;
    }

    var score = 0;
    if (cardName == targetName) {
      score += 400;
    } else if (cardName.contains(targetName) || targetName.contains(cardName)) {
      score += 120;
    }
    if (cardNumber == targetNumber) {
      score += 220;
    }
    if (_deckSetLooksLikeCodeMatch(cardSet, targetSetCode, targetSetNames)) {
      score += 500;
    }
    if (cardName == targetName &&
        cardNumber == targetNumber &&
        _deckSetLooksLikeCodeMatch(cardSet, targetSetCode, targetSetNames)) {
      score += 1000;
    }
    if (card.productType == 'card' && card.itemKind != 'product') {
      score += 20;
    }
    if (score > 0) {
      ranked.add((card: card, score: score));
    }
  }

  ranked.sort((a, b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) {
      return score;
    }
    final set = a.card.set.compareTo(b.card.set);
    if (set != 0) {
      return set;
    }
    return a.card.number.compareTo(b.card.number);
  });

  return ranked
      .take(limit)
      .map((entry) => DeckCardVersionSuggestion(entry.card))
      .toList();
}

String _normalizeDeckLookupText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _normalizeDeckLookupNumber(String value) {
  final text = value.trim().toLowerCase();
  final match = RegExp(r'[a-z]*0*([0-9]+[a-z]?)(?=\s*(?:/|$)|[^a-z0-9])')
      .firstMatch(text);
  return match?.group(1) ?? text.replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

bool _deckSetLooksLikeCodeMatch(
  String cardSet,
  String targetSetCode, [
  Set<String> targetSetNames = const {},
]) {
  if (cardSet.isEmpty || targetSetCode.isEmpty) {
    return false;
  }
  return targetSetNames.contains(cardSet) ||
      cardSet == targetSetCode ||
      cardSet.startsWith(targetSetCode) ||
      cardSet.contains(targetSetCode);
}

Set<String> _deckSetCodeExpansionAliases(String normalizedSetCode) {
  const aliases = <String, String>{
    'twm': 'Twilight Masquerade',
    'tef': 'Temporal Forces',
    'jtg': 'Journey Together',
    'scr': 'Stellar Crown',
    'sfa': 'Shrouded Fable',
    'svp': 'Scarlet & Violet Black Star Promos',
    'pal': 'Paldea Evolved',
    'obf': 'Obsidian Flames',
    'paf': 'Paldean Fates',
    'par': 'Paradox Rift',
    'sv1': 'Scarlet & Violet',
  };
  final expansionName = aliases[normalizedSetCode];
  if (expansionName == null) {
    return const {};
  }
  return {_normalizeDeckLookupText(expansionName)};
}

class ShardReviewScreen extends ConsumerStatefulWidget {
  const ShardReviewScreen({super.key});

  @override
  ConsumerState<ShardReviewScreen> createState() => _ShardReviewScreenState();
}

class _ShardReviewScreenState extends ConsumerState<ShardReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _cardCountController = TextEditingController();
  final _cardValueController = TextEditingController();
  final _cardListController = TextEditingController();
  final _deckListController = TextEditingController();
  final _languageController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _apiClient = PokoinApiClient();
  final _cardService = CardService();
  final Map<String, Future<List<DeckCardVersionSuggestion>>>
      _deckSuggestionFutures = {};

  bool _submitting = false;
  String? _message;
  bool _messageIsError = false;
  String? _deckImportMessage;
  bool _deckImportIsError = false;
  List<String> _deckParseWarnings = const [];
  final List<_DeckCardSelection> _deckCards = [];
  _ShardRequestMode _requestMode = _ShardRequestMode.cards;
  bool _applyingEmailPrefill = false;
  bool _emailEditedByUser = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_handleEmailChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_handleEmailChanged);
    _emailController.dispose();
    _cardCountController.dispose();
    _cardValueController.dispose();
    _cardListController.dispose();
    _deckListController.dispose();
    _languageController.dispose();
    _conditionsController.dispose();
    _disposeDeckCards();
    super.dispose();
  }

  void _handleEmailChanged() {
    if (!_applyingEmailPrefill) {
      _emailEditedByUser = true;
    }
  }

  void _queueEmailPrefill(String? email) {
    final cleanEmail = email?.trim() ?? '';
    if (cleanEmail.isEmpty ||
        _emailEditedByUser ||
        _emailController.text.trim().isNotEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _emailEditedByUser ||
          _emailController.text.trim().isNotEmpty) {
        return;
      }
      _applyingEmailPrefill = true;
      try {
        _emailController.value = TextEditingValue(
          text: cleanEmail,
          selection: TextSelection.collapsed(offset: cleanEmail.length),
        );
      } finally {
        _applyingEmailPrefill = false;
      }
    });
  }

  String? _currentSignedInEmail() {
    final authEmail = ref.watch(authStateProvider).valueOrNull?.email?.trim();
    if (authEmail != null && authEmail.isNotEmpty) {
      return authEmail;
    }
    final profileEmail =
        ref.watch(userProfileProvider).valueOrNull?.email.trim();
    if (profileEmail != null && profileEmail.isNotEmpty) {
      return profileEmail;
    }
    return null;
  }

  void _disposeDeckCards() {
    for (final deckCard in _deckCards) {
      deckCard.dispose();
    }
    _deckCards.clear();
  }

  Future<List<DeckCardVersionSuggestion>> _versionSuggestionsFor(
    ParsedDeckCard card,
  ) {
    final key = deckCardLookupKey(card);
    return _deckSuggestionFutures.putIfAbsent(
      key,
      () => _loadVersionSuggestions(card),
    );
  }

  Future<List<DeckCardVersionSuggestion>> _loadVersionSuggestions(
    ParsedDeckCard card,
  ) async {
    final structured = await _cardService.lookupDeckCardVersions(
      name: card.name,
      setCode: card.setCode,
      collectorNumber: card.collectorNumber,
      limit: 12,
    );
    if (structured.isNotEmpty) {
      return rankDeckVersionSuggestionsForCard(card, structured);
    }

    final queries = <String>[
      '${card.name} ${card.setCode} ${card.collectorNumber}',
      card.name,
    ];
    final seenQueries = <String>{};
    final candidates = <PokemonCard>[];
    for (final query in queries) {
      final normalizedQuery = query.trim();
      if (normalizedQuery.isEmpty ||
          !seenQueries.add(normalizedQuery.toLowerCase())) {
        continue;
      }
      final results = await _cardService.searchMarketplaceCards(
        normalizedQuery,
        limit: 80,
        productType: 'card',
      );
      candidates.addAll(results);
    }
    return rankDeckVersionSuggestionsForCard(card, candidates);
  }

  int get _deckCardTotal {
    return _deckCards.fold<int>(
      0,
      (total, entry) => total + entry.card.quantity,
    );
  }

  void _setRequestMode(_ShardRequestMode mode) {
    setState(() {
      _requestMode = mode;
      _message = null;
      _deckImportMessage = null;
      _deckImportIsError = false;
    });
    _formKey.currentState?.validate();
  }

  void _importDeckList() {
    final result = parseLimitlessDeckList(_deckListController.text);
    setState(() {
      _disposeDeckCards();
      _deckParseWarnings = result.warnings;
      _deckImportIsError = result.cards.isEmpty;
      if (result.cards.isEmpty) {
        _deckImportMessage = result.warnings.isEmpty
            ? 'Could not import any cards from that decklist.'
            : result.warnings.first;
        return;
      }

      _deckCards.addAll(result.cards.map(_DeckCardSelection.new));
      if (_cardCountController.text.trim().isEmpty) {
        _cardCountController.text = _deckCardTotal.toString();
      }
      _deckImportMessage =
          'Imported ${result.cards.length} deck rows / $_deckCardTotal total cards.';
    });
    _formKey.currentState?.validate();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    if (_requestMode == _ShardRequestMode.deck && _deckCards.isEmpty) {
      setState(() {
        _message = 'Import the decklist before submitting a deck shard review.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _message = null;
      _messageIsError = false;
    });

    try {
      final response = await _apiClient.postJson(
        Uri.base.resolve('/api/earn-pkn'),
        requireAuth: false,
        body: {
          'email': _emailController.text.trim(),
          'numberOfCards': _cardCountController.text.trim(),
          'valueOfCards': _cardValueController.text.trim(),
          'requestMode': _requestMode.apiValue,
          if (_requestMode == _ShardRequestMode.cards) ...{
            'cardList': _cardListController.text.trim(),
            'language': _languageController.text.trim(),
            'conditions': _conditionsController.text.trim(),
          } else ...{
            'deckList': _deckListController.text.trim(),
            'deckCards': _deckCards.map((entry) => entry.toPayload()).toList(),
          },
        },
      );
      final payload = _decodeResponse(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          payload['error'] as String? ?? 'Could not send Earn PKN request.',
        );
      }
      if (!mounted) {
        return;
      }
      _formKey.currentState?.reset();
      _applyingEmailPrefill = true;
      try {
        _emailController.clear();
      } finally {
        _applyingEmailPrefill = false;
        _emailEditedByUser = false;
      }
      _cardCountController.clear();
      _cardValueController.clear();
      _cardListController.clear();
      _deckListController.clear();
      _languageController.clear();
      _conditionsController.clear();
      _disposeDeckCards();
      setState(() {
        _deckParseWarnings = const [];
        _deckImportMessage = null;
        _deckImportIsError = false;
        _message =
            'Thanks. Your PKN shard review request was sent to the Pokoin team.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.toString().replaceFirst('Bad state: ', '');
        _messageIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Keep the user-facing fallback below for non-JSON proxy errors.
    }
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    _queueEmailPrefill(_currentSignedInEmail());

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _EarnTopBar(title: 'Request A PKN Shard Review'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.35,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 44),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _ShardReviewHero(),
                  const SizedBox(height: 18),
                  _EarnFormPanel(
                    formKey: _formKey,
                    emailController: _emailController,
                    cardCountController: _cardCountController,
                    cardValueController: _cardValueController,
                    cardListController: _cardListController,
                    deckListController: _deckListController,
                    languageController: _languageController,
                    conditionsController: _conditionsController,
                    deckCards: _deckCards,
                    deckParseWarnings: _deckParseWarnings,
                    deckImportMessage: _deckImportMessage,
                    deckImportIsError: _deckImportIsError,
                    versionSuggestionsFor: _versionSuggestionsFor,
                    requestMode: _requestMode,
                    onRequestModeChanged: _setRequestMode,
                    onDeckImport: _importDeckList,
                    onOpenDeckImport: () =>
                        _setRequestMode(_ShardRequestMode.deck),
                    submitting: _submitting,
                    message: _message,
                    messageIsError: _messageIsError,
                    onSubmit: _submit,
                  ),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EarnPknScreen extends StatelessWidget {
  const EarnPknScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _EarnTopBar(title: 'Earn PKN'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.35,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 44),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _EarnHero(),
                  const SizedBox(height: 18),
                  const _EarnExplanationGrid(),
                  const SizedBox(height: 18),
                  _EarnActionPanel(
                    onSellerSync: () => context.go('/marketplace/connect'),
                    onReserve: () => context.go('/shard-review'),
                  ),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReserveScreen extends StatelessWidget {
  const ReserveScreen({super.key});

  static Future<void> _openReserveProof() async {
    await launchUrl(
      Uri.parse(ProjectLinks.reserve),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _EarnTopBar(title: 'Reserve'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.25,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 44),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Eyebrow(label: 'Reserve Proof'),
                        const SizedBox(height: 18),
                        const Text(
                          'Pokoin Reserve',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.4,
                            height: 1.06,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const SelectableText(
                          'Use the reserve page to inspect public reserve references, wPKN backing context, and Pokoin network links. The Earn PKN flow turns cards into account value while reserve information keeps the ecosystem verifiable.',
                          style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 16,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _openReserveProof,
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Open reserve proof'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/earn'),
                              icon: const Icon(Icons.savings_outlined),
                              label: const Text('Earn PKN'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EarnTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _EarnTopBar({required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xF2050816),
      elevation: 0,
      titleSpacing: 18,
      title: Row(
        children: [
          Image.network(
            ProjectLinks.logo,
            width: 34,
            height: 34,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.savings_outlined,
              color: Color(0xFFFACC15),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.go('/marketplace'),
          child: const Text('Marketplace'),
        ),
        TextButton(
          onPressed: () => context.go('/profile'),
          child: const Text('Profile'),
        ),
        const SizedBox(width: 10),
      ],
    );
  }
}

class _EarnHero extends StatelessWidget {
  const _EarnHero();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow(label: 'Shard Cards Into PKN'),
          const SizedBox(height: 18),
          const Text(
            'Earn PKN From Cards You Do Not Need',
            style: TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          const SelectableText(
            'PKN is the Pokoin unit for Card Reserve marketplace activity. It is designed to reflect the true value of the Pokemon card market by connecting card identity, condition, language, supply, and comparable marketplace signals.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 16,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('/shard-review'),
                icon: const Icon(Icons.account_balance_outlined),
                label: const Text('Reserve'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/marketplace/connect'),
                icon: const Icon(Icons.sync_alt),
                label: const Text('Seller sync'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShardReviewHero extends StatelessWidget {
  const _ShardReviewHero();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow(label: 'PKN Shard Review'),
          const SizedBox(height: 18),
          const Text(
            'Request A PKN Shard Review',
            style: TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          const SelectableText(
            'Send a card list or a full Pokemon decklist to the Pokoin team. The review helps estimate whether cards can be sharded into PKN for marketplace balance.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 16,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.go('/earn'),
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Back to Earn PKN'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/marketplace/connect'),
                icon: const Icon(Icons.sync_alt),
                label: const Text('Seller sync'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarnExplanationGrid extends StatelessWidget {
  const _EarnExplanationGrid();

  @override
  Widget build(BuildContext context) {
    const cards = [
      _InfoCardData(
        icon: Icons.auto_graph_outlined,
        title: 'Market-aware value',
        body:
            'PKN follows the real Pokemon card economy, where card demand, condition, language, listing depth, and comparable prices matter more than a flat catalog number.',
      ),
      _InfoCardData(
        icon: Icons.grid_view_outlined,
        title: 'Shard extra cards',
        body:
            'Send cards you do not need to the Pokoin team for review. Eligible cards can be sharded into PKN and used toward cards you actually want.',
      ),
      _InfoCardData(
        icon: Icons.shopping_bag_outlined,
        title: 'Buy favorite cards',
        body:
            'Use earned PKN inside Card Reserve marketplace flows, seller listings, wallet tools, and account balance features as the ecosystem expands.',
      ),
    ];

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final card in cards) _InfoCard(data: card),
      ],
    );
  }
}

class _EarnActionPanel extends StatelessWidget {
  const _EarnActionPanel({
    required this.onSellerSync,
    required this.onReserve,
  });

  final VoidCallback onSellerSync;
  final VoidCallback onReserve;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seller And Reserve Tools',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const SelectableText(
            'Seller sync remains available here for collectors who also sell through CardTrader, while Reserve now opens the PKN shard review request.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionCard(
                icon: Icons.sync_alt,
                title: 'Seller sync',
                subtitle: 'Connect CardTrader and manage seller setup.',
                onTap: onSellerSync,
              ),
              _ActionCard(
                icon: Icons.account_balance_outlined,
                title: 'Reserve',
                subtitle: 'Request a PKN shard review.',
                onTap: onReserve,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EarnFormPanel extends StatelessWidget {
  const _EarnFormPanel({
    required this.formKey,
    required this.emailController,
    required this.cardCountController,
    required this.cardValueController,
    required this.cardListController,
    required this.deckListController,
    required this.languageController,
    required this.conditionsController,
    required this.deckCards,
    required this.deckParseWarnings,
    required this.deckImportMessage,
    required this.deckImportIsError,
    required this.versionSuggestionsFor,
    required this.requestMode,
    required this.onRequestModeChanged,
    required this.onDeckImport,
    required this.onOpenDeckImport,
    required this.submitting,
    required this.onSubmit,
    this.message,
    required this.messageIsError,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController cardCountController;
  final TextEditingController cardValueController;
  final TextEditingController cardListController;
  final TextEditingController deckListController;
  final TextEditingController languageController;
  final TextEditingController conditionsController;
  final List<_DeckCardSelection> deckCards;
  final List<String> deckParseWarnings;
  final String? deckImportMessage;
  final bool deckImportIsError;
  final Future<List<DeckCardVersionSuggestion>> Function(ParsedDeckCard)
      versionSuggestionsFor;
  final _ShardRequestMode requestMode;
  final ValueChanged<_ShardRequestMode> onRequestModeChanged;
  final VoidCallback onDeckImport;
  final VoidCallback onOpenDeckImport;
  final bool submitting;
  final VoidCallback onSubmit;
  final String? message;
  final bool messageIsError;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Request A PKN Shard Review',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const SelectableText(
              'Tell us what you want to shard. Choose card list for singles or deck shard for a pasted Pokemon / Trainer / Energy decklist.',
              style: TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
            ),
            const SizedBox(height: 18),
            _ShardModeSelector(
              selectedMode: requestMode,
              onChanged: onRequestModeChanged,
            ),
            const SizedBox(height: 18),
            _CommonShardFields(
              emailController: emailController,
              cardCountController: cardCountController,
              cardValueController: cardValueController,
            ),
            const SizedBox(height: 14),
            if (requestMode == _ShardRequestMode.cards)
              _CardListFields(
                cardListController: cardListController,
                languageController: languageController,
                conditionsController: conditionsController,
                onOpenDeckImport: onOpenDeckImport,
              )
            else
              _DeckShardFields(
                deckListController: deckListController,
                deckCards: deckCards,
                deckParseWarnings: deckParseWarnings,
                deckImportMessage: deckImportMessage,
                deckImportIsError: deckImportIsError,
                versionSuggestionsFor: versionSuggestionsFor,
                onDeckImport: onDeckImport,
              ),
            if (message != null) ...[
              const SizedBox(height: 14),
              _FormMessage(text: message!, error: messageIsError),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.outgoing_mail),
              label: Text(
                submitting ? 'Sending...' : 'Submit shard review request',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                foregroundColor: const Color(0xFF111827),
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _requiredText(String? value) {
    return (value ?? '').trim().isEmpty ? 'Required' : null;
  }

  static String? _requiredDeckList(String? value) {
    final deckList = (value ?? '').trim();
    if (deckList.isEmpty) {
      return 'Paste a decklist';
    }
    if (parseLimitlessDeckList(deckList).cards.isEmpty) {
      return 'Include card quantity lines';
    }
    return null;
  }

  static String? _requiredEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) {
      return 'Required';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email';
    }
    return null;
  }

  static String? _optionalPositiveInteger(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final number = int.tryParse(text);
    if (number == null || number <= 0) {
      return 'Enter a whole number';
    }
    return null;
  }
}

class _CommonShardFields extends StatelessWidget {
  const _CommonShardFields({
    required this.emailController,
    required this.cardCountController,
    required this.cardValueController,
  });

  final TextEditingController emailController;
  final TextEditingController cardCountController;
  final TextEditingController cardValueController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;
        final fieldWidth =
            twoColumns ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: fieldWidth,
              child: _EarnTextField(
                controller: emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: _EarnFormPanel._requiredEmail,
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: _EarnTextField(
                controller: cardCountController,
                label: 'Estimated number of cards (optional)',
                icon: Icons.format_list_numbered,
                keyboardType: TextInputType.number,
                validator: _EarnFormPanel._optionalPositiveInteger,
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: _EarnTextField(
                controller: cardValueController,
                label: 'Estimated price of cards (optional)',
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CardListFields extends StatelessWidget {
  const _CardListFields({
    required this.cardListController,
    required this.languageController,
    required this.conditionsController,
    required this.onOpenDeckImport,
  });

  final TextEditingController cardListController;
  final TextEditingController languageController;
  final TextEditingController conditionsController;
  final VoidCallback onOpenDeckImport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;
        final fieldWidth =
            twoColumns ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpenDeckImport,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Deck import'),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: _EarnTextField(
                    controller: languageController,
                    label: 'Language (optional)',
                    icon: Icons.language_outlined,
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: _EarnTextField(
                    controller: conditionsController,
                    label: 'Conditions (optional)',
                    icon: Icons.verified_outlined,
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth,
                  child: _EarnTextField(
                    controller: cardListController,
                    label: 'List of cards',
                    icon: Icons.style_outlined,
                    minLines: 4,
                    maxLines: 8,
                    validator: _EarnFormPanel._requiredText,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DeckShardFields extends StatelessWidget {
  const _DeckShardFields({
    required this.deckListController,
    required this.deckCards,
    required this.deckParseWarnings,
    required this.deckImportMessage,
    required this.deckImportIsError,
    required this.versionSuggestionsFor,
    required this.onDeckImport,
  });

  final TextEditingController deckListController;
  final List<_DeckCardSelection> deckCards;
  final List<String> deckParseWarnings;
  final String? deckImportMessage;
  final bool deckImportIsError;
  final Future<List<DeckCardVersionSuggestion>> Function(ParsedDeckCard)
      versionSuggestionsFor;
  final VoidCallback onDeckImport;

  @override
  Widget build(BuildContext context) {
    final totalCards = deckCards.fold<int>(
      0,
      (total, entry) => total + entry.card.quantity,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EarnTextField(
          controller: deckListController,
          label: 'Paste Limitless decklist',
          icon: Icons.view_list_outlined,
          helperText:
              'Paste sections like "Pokemon: 18", "Trainer: 27", and "Energy: 15", then import.',
          minLines: 10,
          maxLines: 18,
          validator: _EarnFormPanel._requiredDeckList,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onDeckImport,
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Import decklist'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: const Color(0xFF111827),
            ),
          ),
        ),
        if (deckImportMessage != null) ...[
          const SizedBox(height: 12),
          _FormMessage(text: deckImportMessage!, error: deckImportIsError),
        ],
        if (deckParseWarnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DeckWarnings(warnings: deckParseWarnings),
        ],
        if (deckCards.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Imported deck cards ($totalCards total)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const SelectableText(
            'Pick the matching marketplace version when available. Suggestions prefer the parsed set/number, then same-name versions from other expansions.',
            style: TextStyle(color: Color(0xFF93A4C8), height: 1.45),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < deckCards.length; index += 1) ...[
            _DeckCardSelectionRow(
              key: ValueKey(deckCards[index].card.rawLine),
              selection: deckCards[index],
              index: index,
              suggestionsFuture: versionSuggestionsFor(deckCards[index].card),
            ),
            if (index != deckCards.length - 1) const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _DeckWarnings extends StatelessWidget {
  const _DeckWarnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x22F59E0B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x88F59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deck import warnings',
            style: TextStyle(
              color: Color(0xFFFDE68A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          for (final warning in warnings)
            Text(
              warning,
              style: const TextStyle(color: Color(0xFFFDE68A), height: 1.35),
            ),
        ],
      ),
    );
  }
}

class _DeckCardSelectionRow extends StatelessWidget {
  const _DeckCardSelectionRow({
    super.key,
    required this.selection,
    required this.index,
    required this.suggestionsFuture,
  });

  static const _languageOptions = [
    'English',
    'Japanese',
    'German',
    'French',
    'Italian',
    'Spanish',
    'Portuguese',
    'Korean',
    'Chinese',
    'Other',
  ];

  static const _conditionOptions = [
    'Near Mint',
    'Lightly Played',
    'Moderately Played',
    'Heavily Played',
    'Damaged',
  ];

  final _DeckCardSelection selection;
  final int index;
  final Future<List<DeckCardVersionSuggestion>> suggestionsFuture;

  @override
  Widget build(BuildContext context) {
    final card = selection.card;
    return StatefulBuilder(
      builder: (context, setRowState) {
        void selectSuggestion(DeckCardVersionSuggestion suggestion) {
          setRowState(() {
            selection.selectedVersion = suggestion;
            selection.versionEditedManually = false;
            selection.versionController.text = suggestion.label;
          });
        }

        return FutureBuilder<List<DeckCardVersionSuggestion>>(
          future: suggestionsFuture,
          builder: (context, snapshot) {
            final suggestions = snapshot.data ?? const [];
            if (selection.selectedVersion == null &&
                !selection.versionEditedManually &&
                suggestions.isNotEmpty) {
              final first = suggestions.first;
              selection.selectedVersion = first;
              selection.versionController.text = first.label;
            }

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x99111936),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DeckCardPreview(
                        imageUrl: selection.selectedVersion?.imageUrl ?? '',
                        label: card.setCode,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _DeckCardBadge(label: '${card.quantity}x'),
                            _DeckCardBadge(label: card.category),
                            SelectableText(
                              '${card.name} (${card.setCode} ${card.collectorNumber})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final threeColumns = constraints.maxWidth >= 860;
                      final twoColumns = constraints.maxWidth >= 560;
                      final fieldWidth = threeColumns
                          ? (constraints.maxWidth - 24) / 3
                          : twoColumns
                              ? (constraints.maxWidth - 12) / 2
                              : constraints.maxWidth;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: fieldWidth,
                            child: _EarnTextField(
                              controller: selection.versionController,
                              label: 'Version for ${card.name}',
                              icon: Icons.collections_bookmark_outlined,
                              validator: _EarnFormPanel._requiredText,
                              onChanged: (_) {
                                if (selection.selectedVersion != null ||
                                    !selection.versionEditedManually) {
                                  setRowState(() {
                                    selection.selectedVersion = null;
                                    selection.versionEditedManually = true;
                                  });
                                }
                              },
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: _EarnDropdownField(
                              label: 'Language',
                              icon: Icons.language_outlined,
                              value: selection.language,
                              options: _languageOptions,
                              validator: _EarnFormPanel._requiredText,
                              onChanged: (value) => selection.language = value,
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: _EarnDropdownField(
                              label: 'Condition',
                              icon: Icons.verified_outlined,
                              value: selection.condition,
                              options: _conditionOptions,
                              validator: _EarnFormPanel._requiredText,
                              onChanged: (value) => selection.condition = value,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _DeckVersionSuggestions(
                    snapshot: snapshot,
                    selected: selection.selectedVersion,
                    onSelected: selectSuggestion,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DeckCardPreview extends StatelessWidget {
  const _DeckCardPreview({
    required this.imageUrl,
    required this.label,
  });

  final String imageUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 78,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1228),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.trim().isEmpty
          ? _DeckCardImagePlaceholder(label: label, iconSize: 22)
          : CachedNetworkImage(
              imageUrl: imageUrl.trim(),
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) =>
                  _DeckCardImagePlaceholder(label: label, iconSize: 22),
            ),
    );
  }
}

class _DeckVersionSuggestions extends StatelessWidget {
  const _DeckVersionSuggestions({
    required this.snapshot,
    required this.selected,
    required this.onSelected,
  });

  final AsyncSnapshot<List<DeckCardVersionSuggestion>> snapshot;
  final DeckCardVersionSuggestion? selected;
  final ValueChanged<DeckCardVersionSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Looking up marketplace versions...',
            style: TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
          ),
        ],
      );
    }

    final suggestions = snapshot.data ?? const [];
    if (suggestions.isEmpty) {
      return const Text(
        'No marketplace version image found yet. You can still enter the version manually.',
        style: TextStyle(color: Color(0xFF93A4C8), fontSize: 12, height: 1.35),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final suggestion in suggestions)
          _DeckVersionSuggestionChip(
            suggestion: suggestion,
            selected: selected?.card.id == suggestion.card.id,
            onTap: () => onSelected(suggestion),
          ),
      ],
    );
  }
}

class _DeckVersionSuggestionChip extends StatelessWidget {
  const _DeckVersionSuggestionChip({
    required this.suggestion,
    required this.selected,
    required this.onTap,
  });

  final DeckCardVersionSuggestion suggestion;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = suggestion.card;
    final subtitle = [
      if (card.set.trim().isNotEmpty) card.set.trim(),
      if (card.number.trim().isNotEmpty) card.number.trim(),
      if (card.rarity.trim().isNotEmpty) card.rarity.trim(),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 238,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? const Color(0x26FACC15) : const Color(0xFF111936),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFFFACC15)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            _DeckCardPreview(imageUrl: suggestion.imageUrl, label: card.set),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle.isEmpty ? 'Marketplace version' : subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF93A4C8),
                      fontSize: 11,
                      height: 1.25,
                    ),
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

class _DeckCardImagePlaceholder extends StatelessWidget {
  const _DeckCardImagePlaceholder({
    required this.label,
    required this.iconSize,
  });

  final String label;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final text = label.trim().isEmpty ? '?' : label.trim().toUpperCase();
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      color: const Color(0xFF111936),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.style_outlined,
              color: const Color(0xFFFACC15), size: iconSize),
          const SizedBox(height: 3),
          Text(
            text.length > 5 ? text.substring(0, 5) : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFDE68A),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckCardBadge extends StatelessWidget {
  const _DeckCardBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x1AFACC15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x44FACC15)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EarnTextField extends StatelessWidget {
  const _EarnTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
    this.helperText,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      minLines: minLines,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFFACC15),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        prefixIcon: Icon(icon, color: const Color(0xFFFACC15)),
        filled: true,
        fillColor: const Color(0xFF111936),
        labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFACC15)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
      ),
    );
  }
}

class _EarnDropdownField extends StatelessWidget {
  const _EarnDropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.validator,
  });

  final String label;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      validator: validator,
      dropdownColor: const Color(0xFF111936),
      iconEnabledColor: const Color(0xFFFACC15),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFFFACC15)),
        filled: true,
        fillColor: const Color(0xFF111936),
        labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFACC15)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem<String>(
            value: option,
            child: Text(option),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ShardModeSelector extends StatelessWidget {
  const _ShardModeSelector({
    required this.selectedMode,
    required this.onChanged,
  });

  final _ShardRequestMode selectedMode;
  final ValueChanged<_ShardRequestMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final mode in _ShardRequestMode.values)
          ChoiceChip(
            label: Text(mode.label),
            selected: selectedMode == mode,
            onSelected: (selected) {
              if (selected) {
                onChanged(mode);
              }
            },
            avatar: Icon(
              mode == _ShardRequestMode.deck
                  ? Icons.view_list_outlined
                  : Icons.style_outlined,
              size: 18,
            ),
            selectedColor: const Color(0xFFFACC15),
            labelStyle: TextStyle(
              color:
                  selectedMode == mode ? const Color(0xFF111827) : Colors.white,
              fontWeight: FontWeight.w800,
            ),
            backgroundColor: const Color(0x99111936),
            side: BorderSide(
              color: selectedMode == mode
                  ? const Color(0xFFFACC15)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
      ],
    );
  }
}

class _InfoCardData {
  const _InfoCardData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.data});

  final _InfoCardData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(data.icon, color: const Color(0xFFFACC15), size: 28),
            const SizedBox(height: 14),
            Text(
              data.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              data.body,
              style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0x99111936),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFACC15), size: 24),
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF93A4C8),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF93A4C8)),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1AFACC15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x55FACC15)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _FormMessage extends StatelessWidget {
  const _FormMessage({required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? const Color(0x22F87171) : const Color(0x2234D399),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: error ? const Color(0x88F87171) : const Color(0x8834D399),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? const Color(0xFFFCA5A5) : const Color(0xFFBBF7D0),
          height: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
