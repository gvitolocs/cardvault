// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 1;

  @override
  User read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return User(
      id: fields[0] as String,
      email: fields[1] as String,
      name: fields[2] as String,
      profileImage: fields[3] as String?,
      phone: fields[4] as String,
      joinDate: fields[5] as DateTime,
      role: fields[6] as String,
      isVerified: fields[7] as bool,
      rating: fields[8] as double,
      reviewCount: fields[9] as int,
      favoriteCards: (fields[10] as List).cast<String>(),
      wishlist: (fields[11] as List).cast<String>(),
      defaultAddress: fields[12] as Address?,
      defaultPaymentMethod: fields[13] as PaymentMethod?,
      notificationsEnabled: fields[14] as bool,
      preferredLanguage: fields[15] as String,
      preferredCurrency: fields[16] as String,
    );
  }

  @override
  void write(BinaryWriter writer, User obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.email)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.profileImage)
      ..writeByte(4)
      ..write(obj.phone)
      ..writeByte(5)
      ..write(obj.joinDate)
      ..writeByte(6)
      ..write(obj.role)
      ..writeByte(7)
      ..write(obj.isVerified)
      ..writeByte(8)
      ..write(obj.rating)
      ..writeByte(9)
      ..write(obj.reviewCount)
      ..writeByte(10)
      ..write(obj.favoriteCards)
      ..writeByte(11)
      ..write(obj.wishlist)
      ..writeByte(12)
      ..write(obj.defaultAddress)
      ..writeByte(13)
      ..write(obj.defaultPaymentMethod)
      ..writeByte(14)
      ..write(obj.notificationsEnabled)
      ..writeByte(15)
      ..write(obj.preferredLanguage)
      ..writeByte(16)
      ..write(obj.preferredCurrency);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AddressAdapter extends TypeAdapter<Address> {
  @override
  final int typeId = 2;

  @override
  Address read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Address(
      id: fields[0] as String,
      street: fields[1] as String,
      city: fields[2] as String,
      state: fields[3] as String,
      zipCode: fields[4] as String,
      country: fields[5] as String,
      isDefault: fields[6] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Address obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.street)
      ..writeByte(2)
      ..write(obj.city)
      ..writeByte(3)
      ..write(obj.state)
      ..writeByte(4)
      ..write(obj.zipCode)
      ..writeByte(5)
      ..write(obj.country)
      ..writeByte(6)
      ..write(obj.isDefault);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddressAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PaymentMethodAdapter extends TypeAdapter<PaymentMethod> {
  @override
  final int typeId = 3;

  @override
  PaymentMethod read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PaymentMethod(
      id: fields[0] as String,
      type: fields[1] as String,
      lastFourDigits: fields[2] as String,
      brand: fields[3] as String,
      expiryDate: fields[4] as DateTime,
      isDefault: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, PaymentMethod obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.lastFourDigits)
      ..writeByte(3)
      ..write(obj.brand)
      ..writeByte(4)
      ..write(obj.expiryDate)
      ..writeByte(5)
      ..write(obj.isDefault);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentMethodAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
