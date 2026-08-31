import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/pokemon_card.dart';
import '../providers/card_provider.dart';
import '../services/pokoin_api_auth.dart';
import '../services/flutter_debug_log.dart';
import '../utils/card_url.dart';

const List<_AssistantMessage> _initialAssistantMessages = <_AssistantMessage>[
  _AssistantMessage(
    text:
        'Hi hi! I am Poko ✨ Ask me about Pokoin, crypto basics, cute card picks, or report a bug 🐣',
    fromUser: false,
  ),
];

class PokontactChatScreen extends ConsumerStatefulWidget {
  const PokontactChatScreen({super.key});

  @override
  ConsumerState<PokontactChatScreen> createState() =>
      _PokontactChatScreenState();
}

class _PokontactChatScreenState extends ConsumerState<PokontactChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final _AssistantCurrentPagePoller _currentPagePoller;
  final List<_AssistantMessage> _messages =
      List<_AssistantMessage>.of(_initialAssistantMessages);
  bool _sending = false;
  String? _bearerToken;

  @override
  void initState() {
    super.initState();
    _currentPagePoller = _AssistantCurrentPagePoller(
      contextForNavigation: () => context,
      bearerToken: () => _bearerToken,
    )..start();
  }

  @override
  void dispose() {
    _currentPagePoller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050816),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFACC15),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF0B1020),
        ),
        useMaterial3: true,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF050816),
        body: SafeArea(
          child: Column(
            children: [
              _PokontactPageHeader(onBack: () => context.go('/marketplace')),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        return _MessageBubble(
                          message: _messages[index],
                          maxWidth: 620,
                          sessionId: FlutterDebugLog.instance.sessionId,
                          bearerToken: _bearerToken,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AssistantQuickPrompts(onPrompt: _sendPrompt),
                        const SizedBox(height: 10),
                        _AssistantComposer(
                          controller: _controller,
                          focusNode: _inputFocusNode,
                          sending: _sending,
                          onSend: _sendCurrent,
                        ),
                      ],
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

  void _sendPrompt(String prompt) {
    _controller.text = prompt;
    _sendCurrent();
  }

  Future<void> _sendCurrent() async {
    if (!mounted) {
      return;
    }
    await _sendAssistantMessage(
      context: context,
      routeUri: _safeCurrentRouteUri(context),
      cardState: ref.read(cardProvider),
      controller: _controller,
      messages: _messages,
      sending: _sending,
      setSending: (value) => setState(() => _sending = value),
      setBearerToken: (value) => setState(() => _bearerToken = value),
      addMessage: (message) => setState(() => _messages.add(message)),
      scrollToBottom: _scrollToBottom,
    );
  }

  void _scrollToBottom({bool jump = false}) {
    _scrollAssistantMessages(
      mounted: mounted,
      controller: _scrollController,
      jump: jump,
    );
  }
}

class PokoinAssistant extends ConsumerStatefulWidget {
  const PokoinAssistant({super.key, this.router});

  final GoRouter? router;

  @override
  ConsumerState<PokoinAssistant> createState() => _PokoinAssistantState();
}

class _PokoinAssistantState extends ConsumerState<PokoinAssistant> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final _AssistantCurrentPagePoller _currentPagePoller;
  final List<_AssistantMessage> _messages =
      List<_AssistantMessage>.of(_initialAssistantMessages);
  bool _open = false;
  bool _sending = false;
  String? _bearerToken;
  bool _welcomeSeen = false;
  bool _globalPointerListenerActive = false;

  @override
  void initState() {
    super.initState();
    _currentPagePoller = _AssistantCurrentPagePoller(
      contextForNavigation: () => context,
      bearerToken: () => _bearerToken,
      router: () => widget.router,
    )..start();
  }

  @override
  void dispose() {
    _currentPagePoller.dispose();
    _disableGlobalPointerListener();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _openPanel() {
    _enableGlobalPointerListener();
    setState(() {
      _open = true;
      _welcomeSeen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) {
        _inputFocusNode.requestFocus();
        _scrollToBottom(jump: true);
      }
    });
  }

  void _enableGlobalPointerListener() {
    if (_globalPointerListenerActive) {
      return;
    }
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handleGlobalPointer);
    _globalPointerListenerActive = true;
  }

  void _disableGlobalPointerListener() {
    if (!_globalPointerListenerActive) {
      return;
    }
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_handleGlobalPointer);
    _globalPointerListenerActive = false;
  }

  void _handleGlobalPointer(PointerEvent event) {
    if (!_open || event is! PointerDownEvent) {
      return;
    }
    final panelRect = _panelRectFor(MediaQuery.sizeOf(context));
    if (!panelRect.contains(event.position)) {
      _closePanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          if (_open)
            Positioned(
              right: 18,
              bottom: 18,
              child: Material(
                color: Colors.transparent,
                child: RepaintBoundary(
                  child: TweenAnimationBuilder<double>(
                    key: const ValueKey('pokontact-panel-animation'),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0.96, end: 1),
                    builder: (context, scale, child) {
                      return Opacity(
                        opacity: scale.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.bottomRight,
                          child: child,
                        ),
                      );
                    },
                    child: _buildPanel(context),
                  ),
                ),
              ),
            ),
          if (!_open)
            Positioned(
              right: 18,
              bottom: 18,
              child: Material(
                color: Colors.transparent,
                child: RepaintBoundary(child: _buildBubble()),
              ),
            ),
        ],
      ),
    );
  }

  Rect _panelRectFor(Size size) {
    final panelSize = _panelSizeFor(size);
    return Rect.fromLTWH(
      size.width - panelSize.width - 18,
      size.height - panelSize.height - 18,
      panelSize.width,
      panelSize.height,
    );
  }

  Size _panelSizeFor(Size size) {
    return Size(
      size.width < 460 ? size.width - 24 : 390,
      size.height < 720 ? size.height * 0.72 : 560,
    );
  }

  Widget _buildBubble() {
    return Stack(
      key: const ValueKey('pokontact-bubble'),
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          elevation: 12,
          shadowColor: Colors.black54,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _openPanel,
            child: const SizedBox.square(
              dimension: 74,
              child: _PokontactAvatar(size: 74),
            ),
          ),
        ),
        if (!_welcomeSeen)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF050816), width: 2),
              ),
              alignment: Alignment.center,
              child: const Text(
                '1',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _closePanel() {
    _disableGlobalPointerListener();
    setState(() {
      _open = false;
      _welcomeSeen = true;
    });
  }

  Widget _buildPanel(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelSize = _panelSizeFor(size);
    return Container(
      key: const ValueKey('pokontact-panel'),
      width: panelSize.width,
      height: panelSize.height,
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          _AssistantHeader(onClose: _closePanel),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _MessageBubble(
                  message: _messages[index],
                  sessionId: FlutterDebugLog.instance.sessionId,
                  bearerToken: _bearerToken,
                  router: widget.router,
                );
              },
            ),
          ),
          _AssistantQuickPrompts(onPrompt: _sendPrompt),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _AssistantComposer(
              controller: _controller,
              focusNode: _inputFocusNode,
              sending: _sending,
              onSend: _sendCurrent,
            ),
          ),
        ],
      ),
    );
  }

  void _sendPrompt(String prompt) {
    _controller.text = prompt;
    _sendCurrent();
  }

  void _scrollToBottom({bool jump = false}) {
    _scrollAssistantMessages(
      mounted: mounted,
      controller: _scrollController,
      jump: jump,
    );
  }

  Future<void> _sendCurrent() async {
    await _sendAssistantMessage(
      context: context,
      routeUri: _safeCurrentRouteUri(context, router: widget.router),
      router: widget.router,
      cardState: ref.read(cardProvider),
      controller: _controller,
      messages: _messages,
      sending: _sending,
      setSending: (value) => setState(() => _sending = value),
      setBearerToken: (value) => setState(() => _bearerToken = value),
      addMessage: (message) => setState(() => _messages.add(message)),
      scrollToBottom: _scrollToBottom,
    );
  }
}

Uri _safeCurrentRouteUri(BuildContext context, {GoRouter? router}) {
  if (router != null) {
    return router.routeInformationProvider.value.uri;
  }
  try {
    return GoRouterState.of(context).uri;
  } catch (_) {
    return Uri.base;
  }
}

void _scrollAssistantMessages({
  required bool mounted,
  required ScrollController controller,
  bool jump = false,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !controller.hasClients) {
      return;
    }
    final target = controller.position.maxScrollExtent;
    if (jump) {
      controller.jumpTo(target);
      return;
    }
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  });
}

Future<void> _sendAssistantMessage({
  required BuildContext context,
  Uri? routeUri,
  GoRouter? router,
  CardState? cardState,
  required TextEditingController controller,
  required List<_AssistantMessage> messages,
  required bool sending,
  required ValueChanged<bool> setSending,
  ValueChanged<String?>? setBearerToken,
  required ValueChanged<_AssistantMessage> addMessage,
  required void Function({bool jump}) scrollToBottom,
  VoidCallback? onNavigate,
}) async {
  final message = controller.text.trim();
  if (message.isEmpty || sending) {
    return;
  }
  setSending(true);
  controller.clear();
  addMessage(_AssistantMessage(text: message, fromUser: true));
  scrollToBottom();

  try {
    final sessionId = FlutterDebugLog.instance.sessionId;
    final currentRouteUri = routeUri ??
        _safeCurrentRouteUri(
          context,
          router: router,
        );
    final token = Firebase.apps.isEmpty
        ? null
        : await PokoinApiAuthService.instance().bearerToken();
    setBearerToken?.call(token);
    final response = await http
        .post(
          Uri.base.resolve('/api/pokoin-assistant'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'message': message,
            'messages': _boundedAssistantHistory(messages),
            'sessionId': sessionId,
            'page': Uri.base.toString(),
            'pageContext': _assistantPageContext(
              currentRouteUri,
              cardState: cardState,
            ),
            'username': Firebase.apps.isEmpty
                ? ''
                : FirebaseAuth.instance.currentUser?.displayName ?? '',
          }),
        );
    final decoded = jsonDecode(response.body);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'error': 'Pokontact returned an invalid response.'};
    if (response.statusCode >= 400) {
      throw StateError(payload['error'] as String? ?? 'Pokontact failed.');
    }
    addMessage(
      _AssistantMessage(
        text: payload['reply'] as String? ??
            'Pokontact made a tiny confused beep 💫',
        fromUser: false,
      ),
    );
    scrollToBottom();
    if (!context.mounted) {
      return;
    }
    _handleAssistantActionsForContext(
      context: context,
      actions: payload['actions'],
      sessionId: sessionId,
      bearerToken: token,
      router: router,
      onNavigate: onNavigate,
    );
  } catch (error) {
    addMessage(
      const _AssistantMessage(
        text:
            'Oopsie, Pokontact tripped on a cable 🧶 Please try again in a moment and add any extra details you can. If this is a bug, I will forward the report to the development team as soon as I can.',
        fromUser: false,
      ),
    );
    scrollToBottom();
  } finally {
    setSending(false);
  }
}

List<Map<String, String>> _boundedAssistantHistory(
  List<_AssistantMessage> messages,
) {
  return messages
      .where((entry) => entry.text.trim().isNotEmpty)
      .toList(growable: false)
      .reversed
      .take(12)
      .toList(growable: false)
      .reversed
      .map(
        (entry) => {
          'role': entry.fromUser ? 'user' : 'assistant',
          'text': entry.text.length > 1200
              ? entry.text.substring(0, 1200)
              : entry.text,
        },
      )
      .toList(growable: false);
}

Map<String, Object?> _assistantPageContext(
  Uri routeUri, {
  CardState? cardState,
}) {
  final path = routeUri.path.isEmpty ? '/' : routeUri.path;
  final queryParameters = Map<String, String>.from(routeUri.queryParameters)
    ..removeWhere((key, _) => _isSensitivePageContextKey(key));
  final internalUri = queryParameters.isEmpty
      ? path
      : Uri(path: path, queryParameters: queryParameters).toString();
  final kind = _assistantPageKindForPath(path);
  final context = <String, Object?>{
    'url': _assistantSafeAbsoluteUrl(path, queryParameters),
    'internalUri': internalUri,
    'path': path,
    if (queryParameters.isNotEmpty) 'queryParameters': queryParameters,
    'kind': kind,
    'title': _assistantTitleForPath(path),
  };
  final searchQuery = routeUri.queryParameters['q']?.trim();
  final routeFilters = _assistantFiltersFromRoute(routeUri);
  final stateFilters = cardState == null
      ? const <String, String>{}
      : _assistantFiltersFromCardState(cardState);
  final filters = <String, String>{...stateFilters, ...routeFilters};
  if (searchQuery != null && searchQuery.isNotEmpty) {
    context['searchQuery'] = searchQuery;
  } else if ((kind == 'marketplace' || kind == 'search') &&
      cardState != null &&
      cardState.searchQuery.trim().isNotEmpty) {
    context['searchQuery'] = cardState.searchQuery.trim();
  }
  if (filters.isNotEmpty) {
    context['filters'] = filters;
  }
  if (kind == 'marketplace' || kind == 'search') {
    final visibleCards = _assistantVisibleCardsForContext(cardState, limit: 5);
    if (visibleCards.isNotEmpty) {
      context['visibleCards'] = visibleCards;
      context['visibleCardCount'] = cardState?.filteredCards.length ?? 0;
    }
  }
  final card = _assistantCardContextFromPath(path);
  if (card.cardId.isNotEmpty) {
    context['cardId'] = card.cardId;
    context['activeCard'] = {
      'id': card.cardId,
      if (card.cardTitle.isNotEmpty) 'name': card.cardTitle,
      if (card.canonicalPath.isNotEmpty) 'canonicalPath': card.canonicalPath,
      ..._assistantActiveCardFromState(card.cardId, cardState),
    };
  }
  if (card.cardTitle.isNotEmpty) {
    context['cardTitle'] = card.cardTitle;
  }
  final artist = _assistantArtistContextFromPath(path);
  if (artist.slug.isNotEmpty) {
    context['artistSlug'] = artist.slug;
    context['artist'] = {
      'slug': artist.slug,
      'name': artist.name,
    };
  }
  return context;
}

Map<String, String> _assistantFiltersFromRoute(Uri routeUri) {
  final filters = <String, String>{};
  for (final key in const ['expansion', 'productType', 'lang']) {
    final value = routeUri.queryParameters[key]?.trim();
    if (value != null && value.isNotEmpty) {
      filters[key] = value;
    }
  }
  return filters;
}

Map<String, String> _assistantFiltersFromCardState(CardState cardState) {
  final filters = <String, String>{};
  void add(String key, String value) {
    final cleanValue = value.trim();
    if (cleanValue.isNotEmpty) {
      filters[key] = cleanValue;
    }
  }

  add('rarity', cardState.selectedRarity);
  add('type', cardState.selectedType);
  add('set', cardState.selectedSet);
  add('sortBy', cardState.sortBy == 'source' ? '' : cardState.sortBy);
  add('language', cardState.searchLanguage);
  if (cardState.showOnlyInStock) {
    filters['inStock'] = 'true';
  }
  if (cardState.minPrice > 0) {
    filters['minPrice'] = cardState.minPrice.toStringAsFixed(0);
  }
  if (cardState.maxPrice < 5000000.0) {
    filters['maxPrice'] = cardState.maxPrice.toStringAsFixed(0);
  }
  return filters;
}

List<Map<String, String>> _assistantVisibleCardsForContext(
  CardState? cardState, {
  int limit = 5,
}) {
  if (cardState == null) {
    return const [];
  }
  final source = cardState.filteredCards.isNotEmpty
      ? cardState.filteredCards
      : cardState.remoteSearchResults;
  return source
      .take(limit)
      .map(_assistantCardSummary)
      .where((card) => card.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _assistantActiveCardFromState(
  String cardId,
  CardState? cardState,
) {
  if (cardState == null || cardId.isEmpty) {
    return const {};
  }
  for (final card in cardState.cards) {
    if (card.id == cardId) {
      return _assistantCardSummary(card);
    }
  }
  for (final card in cardState.filteredCards) {
    if (card.id == cardId) {
      return _assistantCardSummary(card);
    }
  }
  return const {};
}

Map<String, String> _assistantCardSummary(PokemonCard card) {
  final summary = <String, String>{};
  void add(String key, String value) {
    final cleanValue = value.trim();
    if (cleanValue.isNotEmpty) {
      summary[key] = cleanValue;
    }
  }

  add('id', card.id);
  add('name', card.name);
  add('set', card.set);
  add('number', card.number);
  add('rarity', card.rarity);
  add('artist', card.artist);
  add('condition', card.condition);
  if (card.price > 0) {
    add('pricePkn', card.price.toStringAsFixed(2));
  }
  if (card.isMarketAvailable) {
    add('stock',
        card.stock > 0 ? card.stock.toString() : 'CardTrader available');
  }
  add('canonicalPath', card.canonicalPath);
  return summary;
}

({String cardId, String cardTitle, String canonicalPath})
    _assistantCardContextFromPath(String path) {
  final marketplaceMatch = RegExp(
    r'^/marketplace/[a-z]{2}/cards/([0-9]+)(?:/([^/?#]+))?',
    caseSensitive: false,
  ).firstMatch(path);
  if (marketplaceMatch != null) {
    final doubledId = int.tryParse(marketplaceMatch.group(1) ?? '');
    final cardId = doubledId != null && doubledId > 0
        ? '$doubledId'
        : marketplaceMatch.group(1) ?? '';
    return (
      cardId: cardId,
      cardTitle: _assistantTitleFromSlug(marketplaceMatch.group(2) ?? ''),
      canonicalPath: path,
    );
  }
  final rootMatch = RegExp(r'^/([0-9]+)(?:/([^/?#]+))?$').firstMatch(path);
  if (rootMatch != null) {
    return (
      cardId: rootMatch.group(1) ?? '',
      cardTitle: _assistantTitleFromSlug(rootMatch.group(2) ?? ''),
      canonicalPath: path,
    );
  }
  return (cardId: '', cardTitle: '', canonicalPath: '');
}

({String slug, String name}) _assistantArtistContextFromPath(String path) {
  final match = RegExp(
    r'^/(?:marketplace/[a-z]{2}/artists|collection/artists)/([^/?#]+)',
    caseSensitive: false,
  ).firstMatch(path);
  final slug = match?.group(1) ?? '';
  return (slug: slug, name: _assistantTitleFromSlug(slug));
}

String _assistantPageKindForPath(String path) {
  if (path == '/' || path.isEmpty) return 'home';
  if (path == '/marketplace') return 'marketplace';
  if (path == '/marketplace/search' ||
      RegExp(r'^/marketplace/[a-z]{2}/search$', caseSensitive: false)
          .hasMatch(path)) {
    return 'search';
  }
  if (RegExp(r'^/marketplace/[a-z]{2}/cards/[0-9]+', caseSensitive: false)
      .hasMatch(path)) {
    return path.endsWith('/versions') ? 'card_versions' : 'card';
  }
  if (RegExp(r'^/marketplace/[a-z]{2}/artists/', caseSensitive: false)
      .hasMatch(path)) {
    return 'artist';
  }
  if (path.startsWith('/collection')) return 'collection';
  if (path.startsWith('/cart')) return 'cart';
  if (path.startsWith('/checkout')) return 'checkout';
  if (path.startsWith('/orders')) return 'orders';
  if (path.startsWith('/wallet')) return 'wallet';
  if (path.startsWith('/scan') ||
      path.startsWith('/tx/') ||
      path.startsWith('/address/') ||
      path.startsWith('/block/')) {
    return 'scan';
  }
  if (path.startsWith('/profile')) return 'profile';
  if (path.startsWith('/inventory')) return 'inventory';
  if (path.startsWith('/favorites')) return 'favorites';
  if (path.startsWith('/docs')) return 'docs';
  if (path.startsWith('/product/')) return 'product';
  return 'other';
}

bool _isSensitivePageContextKey(String key) {
  final normalized = key.toLowerCase();
  return normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('password') ||
      normalized == 'code' ||
      normalized == 'state';
}

String _assistantSafeAbsoluteUrl(
  String path,
  Map<String, String> queryParameters,
) {
  final base = Uri.base;
  final scheme = base.scheme == 'http' ? 'http' : 'https';
  final host = base.host.isEmpty ? 'pokoin.com' : base.host;
  return Uri(
    scheme: scheme,
    host: host,
    port: base.hasPort ? base.port : null,
    path: path,
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
  ).toString();
}

String _assistantTitleForPath(String path) {
  if (path == '/' || path.isEmpty) return 'Pokoin home';
  if (path == '/marketplace/search') return 'Marketplace search';
  if (path.contains('/marketplace/') && path.contains('/cards/')) {
    return 'Marketplace card detail';
  }
  if (path.contains('/marketplace/') && path.contains('/artists/')) {
    return 'Marketplace artist';
  }
  if (path.startsWith('/collection')) return 'Collection';
  if (path.startsWith('/marketplace')) return 'Marketplace';
  if (path.startsWith('/wallet')) return 'Wallet';
  if (path.startsWith('/scan')) return 'Scan';
  if (path.startsWith('/swap')) return 'Swap';
  if (path.startsWith('/cart')) return 'Cart';
  if (path.startsWith('/orders')) return 'Orders';
  if (path.startsWith('/profile')) return 'Profile';
  if (path.startsWith('/docs')) return 'Docs';
  return 'Pokoin';
}

String _assistantTitleFromSlug(String slug) {
  return slug.split('-').where((part) => part.trim().isNotEmpty).map((part) {
    if (part.length <= 1) {
      return part.toUpperCase();
    }
    return '${part[0].toUpperCase()}${part.substring(1)}';
  }).join(' ');
}

@visibleForTesting
Map<String, Object?> assistantPageContextForTest(
  Uri routeUri, {
  CardState? cardState,
}) {
  return _assistantPageContext(routeUri, cardState: cardState);
}

void _handleAssistantActionsForContext({
  required BuildContext context,
  required dynamic actions,
  required String sessionId,
  String? bearerToken,
  GoRouter? router,
  VoidCallback? onNavigate,
}) {
  final path = _firstAssistantNavigationPath(actions);
  if (path.isEmpty) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    _navigateAssistantContext(
      context: context,
      path: path,
      sessionId: sessionId,
      bearerToken: bearerToken,
      router: router,
      onNavigate: onNavigate,
    );
  });
}

String _firstAssistantNavigationPath(dynamic actions) {
  if (actions is! List) {
    return '';
  }
  for (final rawAction in actions) {
    final path = _assistantNavigationPathFromAction(rawAction);
    if (path.isNotEmpty) {
      return path;
    }
  }
  return '';
}

String _assistantNavigationPathFromAction(dynamic rawAction) {
  if (rawAction is! Map) {
    return '';
  }
  final type =
      '${rawAction['type'] ?? rawAction['action'] ?? ''}'.trim().toLowerCase();
  if (type != 'navigate') {
    return '';
  }
  for (final candidate in [
    rawAction['path'],
    rawAction['url'],
    rawAction['href'],
    rawAction['target'],
    rawAction['route'],
    rawAction['to'],
  ]) {
    final path = _internalAssistantPathFromUrl(candidate);
    if (path.isNotEmpty) {
      return path;
    }
  }
  final data = rawAction['data'];
  if (data is Map) {
    for (final candidate in [
      data['canonicalPath'],
      data['canonical_path'],
      data['path'],
      data['url'],
      data['href'],
      data['target'],
      data['route'],
      data['to'],
    ]) {
      final path = _internalAssistantPathFromUrl(candidate);
      if (path.isNotEmpty) {
        return path;
      }
    }
  }
  return '';
}

void _navigateAssistantContext({
  required BuildContext context,
  required String path,
  required String sessionId,
  String? bearerToken,
  GoRouter? router,
  VoidCallback? onNavigate,
}) {
  final cleanPath = _internalAssistantPathFromUrl(path);
  if (cleanPath.isEmpty || !context.mounted) {
    return;
  }
  _AssistantNavigationReplayGuard.instance.recordLocalNavigation(
    sessionId: sessionId,
    path: cleanPath,
  );
  FlutterDebugLog.instance.record(
    'assistant.navigation.local',
    category: 'navigation',
    routePath: cleanPath,
    payload: {'path': cleanPath},
  );
  CardDetailRouteGuard.instance.markExplicitNavigation(cleanPath);
  unawaited(_updateAssistantCurrentPage(
    path: cleanPath,
    sessionId: sessionId,
    bearerToken: bearerToken,
  ));
  if (router != null) {
    router.go(cleanPath);
  } else {
    context.go(cleanPath);
  }
  onNavigate?.call();
}

Future<void> _updateAssistantCurrentPage({
  required String path,
  required String sessionId,
  String? bearerToken,
}) async {
  final cleanSessionId = sessionId.trim();
  final cleanPath = _internalAssistantPathFromUrl(path);
  if (cleanSessionId.isEmpty || cleanPath.isEmpty) {
    return;
  }
  try {
    await http
        .post(
          Uri.base.resolve('/api/user-current-page'),
          headers: {
            'Content-Type': 'application/json',
            'X-Pokoin-Session-Id': cleanSessionId,
            if (bearerToken != null && bearerToken.trim().isNotEmpty)
              'Authorization': 'Bearer ${bearerToken.trim()}',
          },
          body: jsonEncode({
            'sessionId': cleanSessionId,
            'path': cleanPath,
            'source': 'assistant-navigate',
          }),
        )
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    // Navigation is the user-visible action; page-state persistence is best-effort.
  }
}

bool _isSafeInternalAssistantPath(String path) {
  if (path.isEmpty || !path.startsWith('/')) {
    return false;
  }
  if (path.startsWith('//') || path.contains(RegExp(r'[\r\n]'))) {
    return false;
  }
  return true;
}

String _internalAssistantPathFromUrl(dynamic value) {
  final raw = '$value'.trim();
  if (raw.isEmpty || raw.contains(RegExp(r'[\r\n]'))) {
    return '';
  }
  if (raw.startsWith('/')) {
    return _isSafeInternalAssistantPath(raw) ? raw : '';
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) {
    return '';
  }
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  if ((scheme != 'https' && scheme != 'http') ||
      (host != 'pokoin.com' && host != 'www.pokoin.com')) {
    return '';
  }
  final path = uri.path.isEmpty ? '/' : uri.path;
  final internal = uri.hasQuery ? '$path?${uri.query}' : path;
  return _isSafeInternalAssistantPath(internal) ? internal : '';
}

@visibleForTesting
String internalAssistantPathFromUrlForTest(dynamic value) {
  return _internalAssistantPathFromUrl(value);
}

Future<void> _openAssistantLinkForSession(
  BuildContext context,
  String url, {
  String sessionId = '',
  String? bearerToken,
  GoRouter? router,
  VoidCallback? onNavigate,
}) async {
  final internalPath = _internalAssistantPathFromUrl(url);
  if (internalPath.isNotEmpty) {
    _navigateAssistantContext(
      context: context,
      path: internalPath,
      sessionId: sessionId,
      bearerToken: bearerToken,
      router: router,
      onNavigate: onNavigate,
    );
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      (uri.scheme.toLowerCase() != 'https' &&
          uri.scheme.toLowerCase() != 'http')) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _AssistantCurrentPagePoller {
  _AssistantCurrentPagePoller({
    required this.contextForNavigation,
    required this.bearerToken,
    this.router,
  });

  final BuildContext Function() contextForNavigation;
  final String? Function() bearerToken;
  final GoRouter? Function()? router;
  Timer? _timer;
  bool _polling = false;
  bool _disabled = false;
  String _lastSeenUpdatedAt = '';

  void start() {
    if (_timer != null) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_polling || _disabled) {
      return;
    }
    final context = contextForNavigation();
    if (!context.mounted) {
      return;
    }
    final sessionId = FlutterDebugLog.instance.sessionId;
    if (sessionId.trim().isEmpty) {
      return;
    }
    _polling = true;
    try {
      final response = await http.get(
        Uri.base.resolve(
          '/api/user-current-page?sessionId=${Uri.encodeQueryComponent(sessionId)}',
        ),
        headers: {
          'X-Pokoin-Session-Id': sessionId,
          if (bearerToken()?.trim().isNotEmpty == true)
            'Authorization': 'Bearer ${bearerToken()!.trim()}',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 404 || response.statusCode == 503) {
        _disabled = true;
        return;
      }
      if (response.statusCode >= 400) {
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return;
      }
      final page = decoded['page'];
      if (page is! Map) {
        return;
      }
      final updatedAt = '${page['updatedAt'] ?? ''}'.trim();
      final source = '${page['source'] ?? ''}'.trim();
      final path = _internalAssistantPathFromUrl(page['path']);
      if (updatedAt.isEmpty ||
          updatedAt == _lastSeenUpdatedAt ||
          path.isEmpty ||
          !source.startsWith('assistant')) {
        return;
      }
      if (_AssistantNavigationReplayGuard.instance.shouldIgnoreLocalEcho(
        sessionId: sessionId,
        path: path,
        source: source,
      )) {
        _lastSeenUpdatedAt = updatedAt;
        FlutterDebugLog.instance.record(
          'assistant.current_page.echo_ignored',
          category: 'navigation',
          routePath: path,
          payload: {
            'path': path,
            'source': source,
            'updatedAt': updatedAt,
          },
        );
        return;
      }
      if (_lastSeenUpdatedAt.isEmpty) {
        _lastSeenUpdatedAt = updatedAt;
        return;
      }
      _lastSeenUpdatedAt = updatedAt;
      final navigationContext = contextForNavigation();
      if (!navigationContext.mounted) {
        return;
      }
      final currentRouter = router?.call();
      final routePath = _safeCurrentRouteUri(
        navigationContext,
        router: currentRouter,
      ).toString();
      if (routePath == path) {
        return;
      }
      FlutterDebugLog.instance.record(
        'assistant.current_page.navigate',
        category: 'navigation',
        routePath: path,
        payload: {
          'path': path,
          'source': source,
          'previousRoute': routePath,
          'updatedAt': updatedAt,
        },
      );
      _navigateAssistantContext(
        context: navigationContext,
        path: path,
        sessionId: sessionId,
        bearerToken: bearerToken(),
        router: currentRouter,
      );
    } catch (_) {
      // Current-page polling is best-effort and must never interrupt chat.
    } finally {
      _polling = false;
    }
  }
}

class _AssistantNavigationReplayGuard {
  _AssistantNavigationReplayGuard._();

  static final _AssistantNavigationReplayGuard instance =
      _AssistantNavigationReplayGuard._();
  static const Duration _localEchoWindow = Duration(minutes: 2);

  final Map<String, DateTime> _localNavigations = {};

  void recordLocalNavigation({
    required String sessionId,
    required String path,
    DateTime? now,
  }) {
    final key = _key(sessionId, path);
    if (key.isEmpty) {
      return;
    }
    final timestamp = now ?? DateTime.now().toUtc();
    _prune(timestamp);
    _localNavigations[key] = timestamp;
  }

  bool shouldIgnoreLocalEcho({
    required String sessionId,
    required String path,
    required String source,
    DateTime? now,
  }) {
    if (source.trim() != 'assistant-navigate') {
      return false;
    }
    final key = _key(sessionId, path);
    if (key.isEmpty) {
      return false;
    }
    final timestamp = now ?? DateTime.now().toUtc();
    _prune(timestamp);
    return _localNavigations.containsKey(key);
  }

  void resetForTest() {
    _localNavigations.clear();
  }

  String _key(String sessionId, String path) {
    final cleanSessionId = sessionId.trim();
    final cleanPath = _internalAssistantPathFromUrl(path);
    if (cleanSessionId.isEmpty || cleanPath.isEmpty) {
      return '';
    }
    return '$cleanSessionId\n$cleanPath';
  }

  void _prune(DateTime now) {
    _localNavigations.removeWhere(
      (_, recordedAt) => now.difference(recordedAt) > _localEchoWindow,
    );
  }
}

class _PokontactPageHeader extends StatelessWidget {
  const _PokontactPageHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1020),
        border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: Colors.white70,
            tooltip: 'Back to marketplace',
          ),
          const _PokontactAvatar(size: 44),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pokontact',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Ask Poko about Pokoin, cards, wallet, and marketplace actions.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantComposer extends StatelessWidget {
  const _AssistantComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  void _submit() {
    if (!sending) {
      onSend();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  !HardwareKeyboard.instance.isShiftPressed) {
                _submit();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              enabled: !sending,
              textInputAction: TextInputAction.send,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ask Pokontact...',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                filled: true,
                fillColor: const Color(0xFF111936),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: sending ? null : _submit,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFFACC15),
            foregroundColor: const Color(0xFF111827),
          ),
          icon: sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
        ),
      ],
    );
  }
}

class _AssistantHeader extends StatelessWidget {
  const _AssistantHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Row(
        children: [
          const _PokontactAvatar(size: 48),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Pokontact ✨',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            color: Colors.white70,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _PokontactAvatar extends StatelessWidget {
  const _PokontactAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        'assets/icons/pokontact-cutout.svg',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Text(
            'PKN',
            style: TextStyle(
              color: Color(0xFFFACC15),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantQuickPrompts extends StatelessWidget {
  const _AssistantQuickPrompts({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    const prompts = [
      'Explain Pokoin simply',
      'Suggest a cute card',
      'What is a wallet?',
      'I found a bug',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final prompt in prompts) ...[
            ActionChip(
              label: Text(prompt),
              onPressed: () => onPrompt(prompt),
              backgroundColor: const Color(0xFF111936),
              labelStyle: const TextStyle(color: Colors.white),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.maxWidth = 310,
    this.sessionId = '',
    this.bearerToken,
    this.router,
  });

  final _AssistantMessage message;
  final double maxWidth;
  final String sessionId;
  final String? bearerToken;
  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    final alignment =
        message.fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final color =
        message.fromUser ? const Color(0xFFFACC15) : const Color(0xFF111936);
    final textColor = message.fromUser ? const Color(0xFF111827) : Colors.white;
    final textStyle = TextStyle(color: textColor, height: 1.35);
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: message.fromUser
            ? Text(message.text, style: textStyle)
            : _AssistantMessageText(
                text: message.text,
                style: textStyle,
                sessionId: sessionId,
                bearerToken: bearerToken,
                router: router,
              ),
      ),
    );
  }
}

class _AssistantMessageText extends StatefulWidget {
  const _AssistantMessageText({
    required this.text,
    required this.style,
    this.sessionId = '',
    this.bearerToken,
    this.router,
  });

  static final _urlPattern = RegExp(r'(?:https?:\/\/|\/marketplace\/)[^\s)]+');

  final String text;
  final TextStyle style;
  final String sessionId;
  final String? bearerToken;
  final GoRouter? router;

  @override
  State<_AssistantMessageText> createState() => _AssistantMessageTextState();
}

class _AssistantMessageTextState extends State<_AssistantMessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final matches = _AssistantMessageText._urlPattern
        .allMatches(widget.text)
        .toList(growable: false);
    if (matches.isEmpty) {
      return Text(widget.text, style: widget.style);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final rawLink = widget.text.substring(match.start, match.end);
      final url = _trimAssistantLink(rawLink);
      final trailing = rawLink.substring(url.length);
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openAssistantLinkForSession(
              context,
              url,
              sessionId: widget.sessionId,
              bearerToken: widget.bearerToken,
              router: widget.router,
            );
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
          style: widget.style.copyWith(
            color: const Color(0xFF38BDF8),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF38BDF8),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
      }
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
    );
  }
}

String _trimAssistantLink(String value) {
  final text = value.trim();
  final trimmed = text.replaceFirst(RegExp(r'[.,!?;:]+$'), '');
  return trimmed.isEmpty ? text : trimmed;
}

@visibleForTesting
String trimAssistantLinkForTest(String value) {
  return _trimAssistantLink(value);
}

@visibleForTesting
List<String> assistantNavigationPathsFromActionsForTest(dynamic actions) {
  if (actions is! List) {
    return const [];
  }
  return actions
      .map(_assistantNavigationPathFromAction)
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
}

@visibleForTesting
void recordAssistantLocalNavigationForTest({
  required String sessionId,
  required String path,
  DateTime? now,
}) {
  _AssistantNavigationReplayGuard.instance.recordLocalNavigation(
    sessionId: sessionId,
    path: path,
    now: now,
  );
}

@visibleForTesting
bool shouldIgnoreAssistantCurrentPageEchoForTest({
  required String sessionId,
  required String path,
  required String source,
  DateTime? now,
}) {
  return _AssistantNavigationReplayGuard.instance.shouldIgnoreLocalEcho(
    sessionId: sessionId,
    path: path,
    source: source,
    now: now,
  );
}

@visibleForTesting
void resetAssistantNavigationReplayGuardForTest() {
  _AssistantNavigationReplayGuard.instance.resetForTest();
}

class _AssistantMessage {
  const _AssistantMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}
