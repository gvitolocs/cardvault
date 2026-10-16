class MarketplaceExpansion {
  const MarketplaceExpansion({
    required this.name,
    required this.slug,
    required this.cardCount,
    required this.symbolImageUrl,
    required this.logoImageUrl,
    required this.defaultSymbolUrl,
    this.releaseDate,
    this.expansionId,
  });

  factory MarketplaceExpansion.fromJson(Map<String, dynamic> json) {
    return MarketplaceExpansion(
      name: '${json['name'] ?? ''}',
      slug: '${json['slug'] ?? ''}',
      cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
      symbolImageUrl: '${json['symbolImageUrl'] ?? ''}',
      logoImageUrl: '${json['logoImageUrl'] ?? ''}',
      defaultSymbolUrl: '${json['defaultSymbolUrl'] ?? ''}',
      releaseDate: DateTime.tryParse(
          '${json['releaseDate'] ?? json['release_date'] ?? ''}'),
      expansionId:
          int.tryParse('${json['expansionId'] ?? json['expansion_id'] ?? ''}'),
    );
  }

  final String name;
  final String slug;
  final int cardCount;
  final String symbolImageUrl;
  final String logoImageUrl;
  final String defaultSymbolUrl;
  final DateTime? releaseDate;
  final int? expansionId;
}
