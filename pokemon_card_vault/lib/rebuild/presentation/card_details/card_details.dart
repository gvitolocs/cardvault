import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../cache/marketplace_image_cache.dart';
import 'component/listing_details.dart';
import '../shared/component/marketplace_cart_sheet.dart';
import '../shared/atomics/marketplace_thumbnail.dart';
import '../shared/atomics/card_illustration.dart';
import '../shared/marketplace_image_url.dart';
import '../../controller/card_details_controller.dart';
import '../../controller/cart_controller.dart';
import '../../model/marketplace_home.dart';
import '../../model/card.dart';
import '../../model/listing.dart';
import '../../style/card_details_style.dart';
import 'component/card_details_header.dart';
import 'component/card_artwork_panel.dart';
import 'atomics/card_artwork_image.dart';
import 'atomics/card_details_panel.dart';
import 'component/card_price_history.dart';
import 'component/card_listing_composer.dart';
import 'component/card_best_deal.dart';

/// La route possiede il controller dettagli; il carrello è condiviso con home.
/// L'interfaccia di mercato resta dimostrativa finché si collegano i prezzi.
class CardDetails extends StatefulWidget {
  const CardDetails(
      {super.key,
      required MarketplaceCardPreview this.preview,
      required CardDetailsController this.controller,
      this.initialColor,
      required this.cart})
      : demoCard = null;

  /// Gli ID demo non sono carte del catalogo: nessuna richiesta HTTP.
  const CardDetails.demo(
      {super.key, required DemoCard card, required this.cart})
      : demoCard = card,
        preview = null,
        initialColor = null,
        controller = null;

  final MarketplaceCardPreview? preview;
  final CardDetailsController? controller;
  final DemoCard? demoCard;
  final CartController cart;
  final Color? initialColor;
  @override
  State<CardDetails> createState() => _CardDetailsState();
}

class _CardDetailsState extends State<CardDetails> {
  Color? _artworkColor;
  bool _favorite = false;
  String? _condition, _language;
  ListingSort _sort = ListingSort.lowestPrice;

  // Identità locali separate dal catalogo: le offerte demo non sono acquistabili.
  static const _sampleOffers = [
    MarketplaceListing(
        id: 'preview-offer-1',
        cardId: 'preview-card',
        sellerName: 'redshakkio',
        country: 'IT',
        condition: 'MP',
        language: 'IT',
        pricePkn: 78,
        stock: 1),
    MarketplaceListing(
        id: 'preview-offer-2',
        cardId: 'preview-card',
        sellerName: 'Card Garden',
        country: 'IT',
        condition: 'NM',
        language: 'IT',
        pricePkn: 190,
        stock: 3,
        attributes: ['Spedizione']),
    MarketplaceListing(
        id: 'preview-offer-3',
        cardId: 'preview-card',
        sellerName: 'TCG Corner',
        country: 'FR',
        condition: 'SP',
        language: 'EN',
        pricePkn: 220,
        stock: 2),
  ];

  ListingsState get _shop {
    final visible = _sampleOffers
        .where((offer) =>
            (_condition == null || offer.condition == _condition) &&
            (_language == null || offer.language == _language))
        .toList()
      ..sort((a, b) => _sort == ListingSort.lowestPrice
          ? a.pricePkn.compareTo(b.pricePkn)
          : b.pricePkn.compareTo(a.pricePkn));
    return ListingsState(
        all: _sampleOffers,
        visible: visible,
        loading: false,
        condition: _condition,
        language: _language,
        sort: _sort);
  }

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    if (controller != null) unawaited(controller.load(includeListings: false));
  }

  @override
  void dispose() {
    widget.controller?.dispose();
    super.dispose();
  }

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  void _showInfo(MarketplaceCard? card) {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Informazioni carta',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text(
                          'ID Pokoin: ${card?.id ?? widget.preview?.id ?? widget.demoCard!.id}'),
                      if (card != null) ...[
                        if (card.artist.isNotEmpty)
                          Text('Illustratore: ${card.artist}'),
                        if (card.rarity.isNotEmpty)
                          Text('Rarità: ${card.rarity}'),
                        if (card.productType.isNotEmpty)
                          Text('Tipo: ${card.productType}'),
                        if (card.hp != null) Text('HP: ${card.hp}'),
                        if (card.description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(card.description),
                        ],
                      ],
                      const SizedBox(height: 16),
                      const Text(
                          'Prezzi, grafico e offerte sono dati di esempio.'),
                    ]))));
  }

  @override
  Widget build(BuildContext context) => widget.controller == null
      ? _page(context, const CardInfoState(loading: false))
      : ValueListenableBuilder(
          valueListenable: widget.controller!.info,
          builder: (context, info, _) => _page(context, info));

  Widget _page(BuildContext context, CardInfoState info) => Theme(
        data: CardDetailsStyle.theme(Theme.of(context),
            cardColor: _artworkColor ??
                widget.initialColor ??
                widget.demoCard?.color ??
                CardDetailsStyle.colorForTypes(info.card?.types ?? [])),
        child: Builder(
            builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('Dettagli carta'), actions: [
                    ListenableBuilder(
                        listenable: widget.cart,
                        builder: (context, _) => IconButton(
                            tooltip: 'Apri carrello',
                            onPressed: () => showMarketplaceCartSheet(
                                context: context, controller: widget.cart),
                            icon: Badge(
                                isLabelVisible: widget.cart.itemCount > 0,
                                label: Text('${widget.cart.itemCount}'),
                                child:
                                    const Icon(Icons.shopping_bag_outlined)))),
                  ]),
                  body: SafeArea(
                    child: LayoutBuilder(builder: (context, constraints) {
                      return Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: constraints.maxWidth.clamp(0, 1240).toDouble(),
                          child: CustomScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            slivers: [
                              SliverToBoxAdapter(
                                  child: _overview(context, info.card,
                                      loading: info.loading,
                                      hasError: info.hasError)),
                              ListingDetails(
                                  state: _shop,
                                  previewOnly: true,
                                  cart: widget.cart,
                                  onRetry: () {},
                                  onFilter: ({condition, language, sort}) =>
                                      setState(() {
                                        _condition = condition;
                                        _language = language;
                                        _sort = sort ?? _sort;
                                      })),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                )),
      );

  Widget _overview(BuildContext context, MarketplaceCard? card,
      {bool loading = false, bool hasError = false}) {
    final demo = widget.demoCard;
    final name = card?.name ?? widget.preview?.name ?? demo!.name;
    final expansion =
        card?.expansion ?? widget.preview?.expansion ?? demo!.expansion;
    final number = card?.number ?? widget.preview?.number ?? demo!.number;
    final artwork = CardArtworkPanel(
        number: number,
        rarity: card?.rarity ?? '',
        demoPrice: demo?.price,
        onAddDemo: demo == null
            ? null
            : () {
                widget.cart.addCard(demo);
                Navigator.of(context).pop();
              },
        image: demo != null
            ? CardIllustration(card: demo)
            : LayoutBuilder(builder: (context, constraints) {
                final imageUrl = card?.imageUrl.isNotEmpty == true
                    ? card!.imageUrl
                    : widget.preview!.fullImageUrl.isNotEmpty
                        ? widget.preview!.fullImageUrl
                        : widget.preview!.imageUrl;
                final uri = marketplaceImageUri(imageUrl);
                if (uri == null) {
                  return MarketplaceThumbnail(
                      imageUrl: '',
                      width: constraints.maxWidth,
                      height: constraints.maxHeight);
                }
                if (widget.initialColor != null) {
                  return MarketplaceThumbnail(
                      key: ValueKey(widget.preview!.id),
                      imageUrl: imageUrl,
                      gaplessPlayback: true,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight);
                }
                return CardArtworkImage(
                    key: ValueKey(widget.preview!.id),
                    image: ResizeImage.resizeIfNeeded(
                        (constraints.maxWidth *
                                MediaQuery.devicePixelRatioOf(context))
                            .round()
                            .clamp(1, 768),
                        null,
                        CachedNetworkImageProvider(uri.toString(),
                            cacheManager: MarketplaceImageCache.instance)),
                    onColor: (color) {
                      if (_artworkColor != color) {
                        setState(() => _artworkColor = color);
                      }
                    });
              }),
        onVersions: () =>
            _message('Le altre versioni saranno disponibili prossimamente.'));
    final composer = CardListingComposer(
        onPreview: () => _message(
            'Anteprima pronta. La pubblicazione degli annunci non è ancora disponibile.'));
    const history = CardPriceHistory();
    const bestDeal = CardBestDeal();
    final center =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      history,
      const SizedBox(height: 16),
      composer,
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardDetailsHeader(
            name: name,
            subtitle: [
              expansion,
              number,
              if (card?.artist.isNotEmpty == true) card!.artist
            ].where((part) => part.isNotEmpty).join(' · '),
            types: card?.types ?? [],
            favorite: _favorite,
            onFavorite: () => setState(() => _favorite = !_favorite),
            onInfo: () => _showInfo(card)),
        if (loading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (hasError) ...[
          const SizedBox(height: 12),
          CardDetailsPanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                const Text(
                    'Non è stato possibile caricare le informazioni della carta.'),
                TextButton(
                    onPressed: widget.controller!.retryInfo,
                    child: const Text('Riprova informazioni')),
              ])),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (constraints.maxWidth >= 1000 && scale <= 1.3) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: artwork),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: center),
              const SizedBox(width: 16),
              const Expanded(flex: 3, child: bestDeal),
            ]);
          }
          if (constraints.maxWidth >= 700 && scale <= 1.3) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: artwork),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: center),
                  ]),
                  const SizedBox(height: 16),
                  bestDeal,
                ]);
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                artwork,
                const SizedBox(height: 16),
                history,
                const SizedBox(height: 16),
                composer,
                const SizedBox(height: 16),
                bestDeal,
              ]);
        }),
      ]),
    );
  }
}
