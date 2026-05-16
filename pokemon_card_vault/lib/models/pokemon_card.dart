import 'package:hive/hive.dart';

part 'pokemon_card.g.dart';

@HiveType(typeId: 0)
class PokemonCard extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String imageUrl;

  @HiveField(3)
  final String rarity;

  @HiveField(4)
  final String type;

  @HiveField(5)
  final int hp;

  @HiveField(6)
  final List<String> attacks;

  @HiveField(7)
  final double price;

  @HiveField(8)
  final String description;

  @HiveField(9)
  final String set;

  @HiveField(10)
  final String number;

  @HiveField(11)
  final String artist;

  @HiveField(12)
  final int stock;

  @HiveField(13)
  final double rating;

  @HiveField(14)
  final int reviewCount;

  @HiveField(15)
  final bool isFoil;

  @HiveField(16)
  final bool isHolo;

  @HiveField(17)
  final DateTime releaseDate;

  @HiveField(18)
  final List<String> tags;

  @HiveField(19)
  final String condition;

  @HiveField(20)
  final bool isGraded;

  @HiveField(21)
  final String? grade;

  @HiveField(22)
  final String? gradingCompany;

  PokemonCard({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.rarity,
    required this.type,
    required this.hp,
    required this.attacks,
    required this.price,
    required this.description,
    required this.set,
    required this.number,
    required this.artist,
    required this.stock,
    required this.rating,
    required this.reviewCount,
    required this.isFoil,
    required this.isHolo,
    required this.releaseDate,
    required this.tags,
    required this.condition,
    required this.isGraded,
    this.grade,
    this.gradingCompany,
  });

  factory PokemonCard.fromJson(Map<String, dynamic> json) {
    return PokemonCard(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      rarity: json['rarity'] ?? '',
      type: json['type'] ?? '',
      hp: json['hp'] ?? 0,
      attacks: List<String>.from(json['attacks'] ?? []),
      price: (json['price'] ?? 0.0).toDouble(),
      description: json['description'] ?? '',
      set: json['set'] ?? '',
      number: json['number'] ?? '',
      artist: json['artist'] ?? '',
      stock: json['stock'] ?? 0,
      rating: (json['rating'] ?? 0.0).toDouble(),
      reviewCount: json['reviewCount'] ?? 0,
      isFoil: json['isFoil'] ?? false,
      isHolo: json['isHolo'] ?? false,
      releaseDate: DateTime.parse(
          json['releaseDate'] ?? DateTime.now().toIso8601String()),
      tags: List<String>.from(json['tags'] ?? []),
      condition: json['condition'] ?? 'NM',
      isGraded: json['isGraded'] ?? false,
      grade: json['grade'],
      gradingCompany: json['gradingCompany'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'rarity': rarity,
      'type': type,
      'hp': hp,
      'attacks': attacks,
      'price': price,
      'description': description,
      'set': set,
      'number': number,
      'artist': artist,
      'stock': stock,
      'rating': rating,
      'reviewCount': reviewCount,
      'isFoil': isFoil,
      'isHolo': isHolo,
      'releaseDate': releaseDate.toIso8601String(),
      'tags': tags,
      'condition': condition,
      'isGraded': isGraded,
      'grade': grade,
      'gradingCompany': gradingCompany,
    };
  }

  PokemonCard copyWith({
    String? id,
    String? name,
    String? imageUrl,
    String? rarity,
    String? type,
    int? hp,
    List<String>? attacks,
    double? price,
    String? description,
    String? set,
    String? number,
    String? artist,
    int? stock,
    double? rating,
    int? reviewCount,
    bool? isFoil,
    bool? isHolo,
    DateTime? releaseDate,
    List<String>? tags,
    String? condition,
    bool? isGraded,
    String? grade,
    String? gradingCompany,
  }) {
    return PokemonCard(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      rarity: rarity ?? this.rarity,
      type: type ?? this.type,
      hp: hp ?? this.hp,
      attacks: attacks ?? this.attacks,
      price: price ?? this.price,
      description: description ?? this.description,
      set: set ?? this.set,
      number: number ?? this.number,
      artist: artist ?? this.artist,
      stock: stock ?? this.stock,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isFoil: isFoil ?? this.isFoil,
      isHolo: isHolo ?? this.isHolo,
      releaseDate: releaseDate ?? this.releaseDate,
      tags: tags ?? this.tags,
      condition: condition ?? this.condition,
      isGraded: isGraded ?? this.isGraded,
      grade: grade ?? this.grade,
      gradingCompany: gradingCompany ?? this.gradingCompany,
    );
  }
}
