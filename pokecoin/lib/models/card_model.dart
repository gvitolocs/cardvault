class CardModel {
  final String id;
  final String name;
  final String imageUrl;
  final double price;
  final String set; // Nome del set

  CardModel({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.set,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'].toString(),
      name: json['name'] ?? 'N/A',
      imageUrl: json['images']?['small'] ?? '',
      price:
          (json['cardmarket']?['prices']?['averageSellPrice'] ?? 0).toDouble(),
      set: json['set']?['name'] ?? 'Unknown', // ✔️ corregge il tipo
    );
  }

  get priceHistory => null;
}
