import 'dart:typed_data';
import 'card.dart';

class ScannerMarketData {
  const ScannerMarketData({this.card, this.suggested});
  final MarketplaceCard? card;
  final double? suggested;
}

class ScannerSaleSlice {
  ScannerSaleSlice(Map<String, dynamic> json)
      : condition = '${json['condition'] ?? ''}',
        language = '${json['language'] ?? ''}',
        day = '${json['day'] ?? ''}',
        reverse = json['reverse'] == true,
        firstEdition = json['firstEdition'] == true,
        graded = json['graded'] == true,
        median = num.tryParse('${json['medianPkn']}')?.toDouble() ?? 0,
        samples = num.tryParse('${json['sampleCount']}')?.toInt() ?? 0,
        listings = num.tryParse('${json['listings']}')?.toInt() ?? 0;
  final String condition, language, day;
  final bool reverse, firstEdition, graded;
  final double median;
  final int samples, listings;
}

class ScannerMarketSnapshot {
  const ScannerMarketSnapshot({this.card, this.slices = const []});
  final MarketplaceCard? card;
  final List<ScannerSaleSlice> slices;
}

enum ScanDestination { collection, listing }

enum ScanMode { single, batch }

/// Only the operation and HTTP status are exposed, never private response data.
class ScannerRequestFailure implements Exception {
  const ScannerRequestFailure(this.action, this.statusCode);
  final String action;
  final int statusCode;

  String get message {
    final phase = switch (action) {
      'item' => 'Aggiornamento della carta',
      'submit' => 'Conferma del salvataggio',
      'ownership' => 'Verifica del possesso',
      'add' => 'Aggiunta della carta',
      _ => 'Richiesta scanner',
    };
    return '$phase: errore HTTP $statusCode. '
        'Le scansioni restano nella linguetta. Riprova la conferma; '
        'se richiesto, premi prima Ricarica.';
  }

  @override
  String toString() => 'ScannerRequestFailure($action, HTTP $statusCode)';
}

class ScannerCandidate {
  const ScannerCandidate(
      {required this.cardId,
      required this.name,
      required this.setName,
      required this.number,
      required this.score});
  final String cardId, name, setName, number;
  final double score;
}

class ScannedCard {
  const ScannedCard(
      {required this.id,
      required this.cardId,
      required this.name,
      required this.setName,
      required this.number,
      required this.imageUrl,
      this.condition = 'NM',
      this.language = 'IT',
      this.quantity = 1,
      this.price = '',
      this.alternatives = const [],
      this.suggestedPrice,
      this.priceSuggested = false,
      this.foilState = 'standard'});
  final String id, cardId, name, setName, number, imageUrl;
  final String condition, language, price, foilState;
  final int quantity;
  final List<ScannerCandidate> alternatives;
  final double? suggestedPrice;
  final bool priceSuggested;
  bool get isLocal => id.startsWith('local:');
  String get facets => '$cardId:$condition:$language:$foilState';
  double? get pricePkn => double.tryParse(price.trim().replaceAll(',', '.'));
  bool get validPrice =>
      pricePkn != null &&
      pricePkn!.isFinite &&
      pricePkn! >= .01 &&
      pricePkn! <= 1e9;
  ScannedCard edit(
          {String? condition,
          String? language,
          String? price,
          int? quantity,
          String? foilState,
          String? id,
          ScannerCandidate? selected,
          List<ScannerCandidate>? alternatives,
          ScannerMarketData? market}) =>
      ScannedCard(
          id: id ?? this.id,
          cardId: selected?.cardId ?? cardId,
          name: selected?.name ?? market?.card?.name ?? name,
          setName: selected?.setName ?? market?.card?.expansion ?? setName,
          number: selected?.number ?? market?.card?.number ?? number,
          imageUrl: selected != null ? '' : market?.card?.imageUrl ?? imageUrl,
          condition: condition ?? this.condition,
          language: language ?? this.language,
          quantity: quantity ?? this.quantity,
          price: price ??
              (selected != null
                  ? ''
                  : market?.suggested != null &&
                          (this.price.isEmpty || priceSuggested)
                      ? market!.suggested!.toStringAsFixed(2)
                      : this.price),
          suggestedPrice:
              selected != null ? null : market?.suggested ?? suggestedPrice,
          priceSuggested: price != null || selected != null
              ? false
              : market?.suggested != null &&
                      (this.price.isEmpty || priceSuggested)
                  ? true
                  : priceSuggested,
          alternatives: alternatives ?? this.alternatives,
          foilState: foilState ?? this.foilState);
  factory ScannedCard.fromJson(Map<String, dynamic> json) => ScannedCard(
      id: '${json['id']}',
      cardId: '${json['cardId']}',
      name: '${json['name'] ?? json['cardName'] ?? json['cardId']}',
      setName: '${json['setName'] ?? ''}',
      number: '${json['collectorNumber'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      condition: '${json['condition'] ?? 'NM'}',
      language: '${json['language'] ?? 'IT'}',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      price: '${json['pricePkn'] ?? ''}',
      priceSuggested: json['priceSuggested'] == true,
      foilState: '${json['foilState'] ?? 'standard'}');
  Map<String, dynamic> get patch => {
        'condition': condition,
        // A cardId patch already sets reviewed=true in the deployed store.
        // confirm=true as well would assign the SQL column reviewed twice.
        'cardId': cardId,
        'language': language,
        'quantity': quantity,
        'pricePkn': price.trim().isEmpty ? null : pricePkn,
        'priceSuggested': priceSuggested,
        'foilState': foilState
      };

  Map<String, dynamic> toJson() => {
        ...patch,
        'pricePkn': validPrice ? pricePkn : null,
        'id': id,
        'name': name,
        'setName': setName,
        'collectorNumber': number,
        'imageUrl': imageUrl,
        'priceText': price,
        'suggestedPrice': suggestedPrice,
        'alternatives': [
          for (final c in alternatives)
            {
              'cardId': c.cardId,
              'name': c.name,
              'setName': c.setName,
              'number': c.number,
              'score': c.score
            }
        ],
      };

  factory ScannedCard.fromStored(Map<String, dynamic> json) {
    final card = ScannedCard.fromJson(json);
    return ScannedCard(
        id: card.id,
        cardId: card.cardId,
        name: card.name,
        setName: card.setName,
        number: card.number,
        imageUrl: card.imageUrl,
        condition: card.condition,
        language: card.language,
        quantity: card.quantity,
        price: '${json['priceText'] ?? card.price}',
        foilState: card.foilState,
        priceSuggested: card.priceSuggested,
        suggestedPrice: (json['suggestedPrice'] as num?)?.toDouble(),
        alternatives: [
          for (final raw in (json['alternatives'] as List? ?? []))
            if (raw is Map)
              ScannerCandidate(
                  cardId: '${raw['cardId']}',
                  name: '${raw['name'] ?? ''}',
                  setName: '${raw['setName'] ?? ''}',
                  number: '${raw['number'] ?? ''}',
                  score: (raw['score'] as num).toDouble())
        ]);
  }
}

class ScannerBatch {
  ScannerBatch(
      {required this.id,
      required List<ScannedCard> cards,
      this.submitted = false,
      this.submittedDestination})
      : cards = List.unmodifiable(cards);
  final String id;
  final List<ScannedCard> cards;
  final bool submitted;
  final ScanDestination? submittedDestination;
}

/// Immutable copy: camera buffers may be reused before native recognition ends.
class ScannerFrame {
  const ScannerFrame(
      {required this.width,
      required this.height,
      required this.orientation,
      required this.bgra,
      required this.planes,
      required this.strides,
      this.pixelStride = 1});
  final int width, height, orientation, pixelStride;
  final bool bgra;
  final List<Uint8List> planes;
  final List<int> strides;
}
