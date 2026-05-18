// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pokemon_card.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PokemonCardAdapter extends TypeAdapter<PokemonCard> {
  @override
  final int typeId = 0;

  @override
  PokemonCard read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PokemonCard(
      id: fields[0] as String,
      name: fields[1] as String,
      imageUrl: fields[2] as String,
      rarity: fields[3] as String,
      type: fields[4] as String,
      hp: fields[5] as int,
      attacks: (fields[6] as List).cast<String>(),
      price: fields[7] as double,
      description: fields[8] as String,
      set: fields[9] as String,
      number: fields[10] as String,
      artist: fields[11] as String,
      stock: fields[12] as int,
      rating: fields[13] as double,
      reviewCount: fields[14] as int,
      isFoil: fields[15] as bool,
      isHolo: fields[16] as bool,
      releaseDate: fields[17] as DateTime,
      tags: (fields[18] as List).cast<String>(),
      condition: fields[19] as String,
      isGraded: fields[20] as bool,
      grade: fields[21] as String?,
      gradingCompany: fields[22] as String?,
      previewImageUrl: fields[23] as String?,
      itemKind: fields[24] as String? ?? 'single',
      productType: fields[25] as String? ?? 'card',
    );
  }

  @override
  void write(BinaryWriter writer, PokemonCard obj) {
    writer
      ..writeByte(26)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.imageUrl)
      ..writeByte(3)
      ..write(obj.rarity)
      ..writeByte(4)
      ..write(obj.type)
      ..writeByte(5)
      ..write(obj.hp)
      ..writeByte(6)
      ..write(obj.attacks)
      ..writeByte(7)
      ..write(obj.price)
      ..writeByte(8)
      ..write(obj.description)
      ..writeByte(9)
      ..write(obj.set)
      ..writeByte(10)
      ..write(obj.number)
      ..writeByte(11)
      ..write(obj.artist)
      ..writeByte(12)
      ..write(obj.stock)
      ..writeByte(13)
      ..write(obj.rating)
      ..writeByte(14)
      ..write(obj.reviewCount)
      ..writeByte(15)
      ..write(obj.isFoil)
      ..writeByte(16)
      ..write(obj.isHolo)
      ..writeByte(17)
      ..write(obj.releaseDate)
      ..writeByte(18)
      ..write(obj.tags)
      ..writeByte(19)
      ..write(obj.condition)
      ..writeByte(20)
      ..write(obj.isGraded)
      ..writeByte(21)
      ..write(obj.grade)
      ..writeByte(22)
      ..write(obj.gradingCompany)
      ..writeByte(23)
      ..write(obj.previewImageUrl)
      ..writeByte(24)
      ..write(obj.itemKind)
      ..writeByte(25)
      ..write(obj.productType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PokemonCardAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
