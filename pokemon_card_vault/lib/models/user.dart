import 'package:hive/hive.dart';

part 'user.g.dart';

@HiveType(typeId: 1)
class User extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String email;
  
  @HiveField(2)
  final String name;
  
  @HiveField(3)
  final String? profileImage;
  
  @HiveField(4)
  final String phone;
  
  @HiveField(5)
  final DateTime joinDate;
  
  @HiveField(6)
  final String role;
  
  @HiveField(7)
  final bool isVerified;
  
  @HiveField(8)
  final double rating;
  
  @HiveField(9)
  final int reviewCount;
  
  @HiveField(10)
  final List<String> favoriteCards;
  
  @HiveField(11)
  final List<String> wishlist;
  
  @HiveField(12)
  final Address? defaultAddress;
  
  @HiveField(13)
  final PaymentMethod? defaultPaymentMethod;
  
  @HiveField(14)
  final bool notificationsEnabled;
  
  @HiveField(15)
  final String preferredLanguage;
  
  @HiveField(16)
  final String preferredCurrency;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.profileImage,
    required this.phone,
    required this.joinDate,
    required this.role,
    required this.isVerified,
    required this.rating,
    required this.reviewCount,
    required this.favoriteCards,
    required this.wishlist,
    this.defaultAddress,
    this.defaultPaymentMethod,
    required this.notificationsEnabled,
    required this.preferredLanguage,
    required this.preferredCurrency,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      profileImage: json['profileImage'],
      phone: json['phone'] ?? '',
      joinDate: DateTime.parse(json['joinDate'] ?? DateTime.now().toIso8601String()),
      role: json['role'] ?? 'user',
      isVerified: json['isVerified'] ?? false,
      rating: (json['rating'] ?? 0.0).toDouble(),
      reviewCount: json['reviewCount'] ?? 0,
      favoriteCards: List<String>.from(json['favoriteCards'] ?? []),
      wishlist: List<String>.from(json['wishlist'] ?? []),
      defaultAddress: json['defaultAddress'] != null 
          ? Address.fromJson(json['defaultAddress']) 
          : null,
      defaultPaymentMethod: json['defaultPaymentMethod'] != null 
          ? PaymentMethod.fromJson(json['defaultPaymentMethod']) 
          : null,
      notificationsEnabled: json['notificationsEnabled'] ?? true,
      preferredLanguage: json['preferredLanguage'] ?? 'en',
      preferredCurrency: json['preferredCurrency'] ?? 'USD',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'profileImage': profileImage,
      'phone': phone,
      'joinDate': joinDate.toIso8601String(),
      'role': role,
      'isVerified': isVerified,
      'rating': rating,
      'reviewCount': reviewCount,
      'favoriteCards': favoriteCards,
      'wishlist': wishlist,
      'defaultAddress': defaultAddress?.toJson(),
      'defaultPaymentMethod': defaultPaymentMethod?.toJson(),
      'notificationsEnabled': notificationsEnabled,
      'preferredLanguage': preferredLanguage,
      'preferredCurrency': preferredCurrency,
    };
  }
}

@HiveType(typeId: 2)
class Address extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String street;
  
  @HiveField(2)
  final String city;
  
  @HiveField(3)
  final String state;
  
  @HiveField(4)
  final String zipCode;
  
  @HiveField(5)
  final String country;
  
  @HiveField(6)
  final bool isDefault;

  Address({
    required this.id,
    required this.street,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.country,
    required this.isDefault,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      id: json['id'] ?? '',
      street: json['street'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      zipCode: json['zipCode'] ?? '',
      country: json['country'] ?? '',
      isDefault: json['isDefault'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'street': street,
      'city': city,
      'state': state,
      'zipCode': zipCode,
      'country': country,
      'isDefault': isDefault,
    };
  }
}

@HiveType(typeId: 3)
class PaymentMethod extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String type;
  
  @HiveField(2)
  final String lastFourDigits;
  
  @HiveField(3)
  final String brand;
  
  @HiveField(4)
  final DateTime expiryDate;
  
  @HiveField(5)
  final bool isDefault;

  PaymentMethod({
    required this.id,
    required this.type,
    required this.lastFourDigits,
    required this.brand,
    required this.expiryDate,
    required this.isDefault,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      lastFourDigits: json['lastFourDigits'] ?? '',
      brand: json['brand'] ?? '',
      expiryDate: DateTime.parse(json['expiryDate'] ?? DateTime.now().toIso8601String()),
      isDefault: json['isDefault'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'lastFourDigits': lastFourDigits,
      'brand': brand,
      'expiryDate': expiryDate.toIso8601String(),
      'isDefault': isDefault,
    };
  }
}
