// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OrderAdapter extends TypeAdapter<Order> {
  @override
  final int typeId = 4;

  @override
  Order read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Order(
      id: fields[0] as String,
      userId: fields[1] as String,
      items: (fields[2] as List).cast<OrderItem>(),
      subtotal: fields[3] as double,
      tax: fields[4] as double,
      shipping: fields[5] as double,
      total: fields[6] as double,
      status: fields[7] as OrderStatus,
      orderDate: fields[8] as DateTime,
      shippedDate: fields[9] as DateTime?,
      deliveredDate: fields[10] as DateTime?,
      shippingAddress: fields[11] as Address,
      paymentMethod: fields[12] as PaymentMethod,
      trackingNumber: fields[13] as String,
      notes: fields[14] as String,
      statusHistory: (fields[15] as List).cast<OrderStatusHistory>(),
    );
  }

  @override
  void write(BinaryWriter writer, Order obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.items)
      ..writeByte(3)
      ..write(obj.subtotal)
      ..writeByte(4)
      ..write(obj.tax)
      ..writeByte(5)
      ..write(obj.shipping)
      ..writeByte(6)
      ..write(obj.total)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.orderDate)
      ..writeByte(9)
      ..write(obj.shippedDate)
      ..writeByte(10)
      ..write(obj.deliveredDate)
      ..writeByte(11)
      ..write(obj.shippingAddress)
      ..writeByte(12)
      ..write(obj.paymentMethod)
      ..writeByte(13)
      ..write(obj.trackingNumber)
      ..writeByte(14)
      ..write(obj.notes)
      ..writeByte(15)
      ..write(obj.statusHistory);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class OrderItemAdapter extends TypeAdapter<OrderItem> {
  @override
  final int typeId = 5;

  @override
  OrderItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrderItem(
      cardId: fields[0] as String,
      cardName: fields[1] as String,
      cardImage: fields[2] as String,
      quantity: fields[3] as int,
      unitPrice: fields[4] as double,
      totalPrice: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, OrderItem obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.cardId)
      ..writeByte(1)
      ..write(obj.cardName)
      ..writeByte(2)
      ..write(obj.cardImage)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.unitPrice)
      ..writeByte(5)
      ..write(obj.totalPrice);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class OrderStatusHistoryAdapter extends TypeAdapter<OrderStatusHistory> {
  @override
  final int typeId = 6;

  @override
  OrderStatusHistory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrderStatusHistory(
      status: fields[0] as OrderStatus,
      timestamp: fields[1] as DateTime,
      note: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, OrderStatusHistory obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.status)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderStatusHistoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
