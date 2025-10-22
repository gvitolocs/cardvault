import 'package:hive/hive.dart';
import 'user.dart';

part 'order.g.dart';

@HiveType(typeId: 4)
class Order extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String userId;
  
  @HiveField(2)
  final List<OrderItem> items;
  
  @HiveField(3)
  final double subtotal;
  
  @HiveField(4)
  final double tax;
  
  @HiveField(5)
  final double shipping;
  
  @HiveField(6)
  final double total;
  
  @HiveField(7)
  final OrderStatus status;
  
  @HiveField(8)
  final DateTime orderDate;
  
  @HiveField(9)
  final DateTime? shippedDate;
  
  @HiveField(10)
  final DateTime? deliveredDate;
  
  @HiveField(11)
  final Address shippingAddress;
  
  @HiveField(12)
  final PaymentMethod paymentMethod;
  
  @HiveField(13)
  final String trackingNumber;
  
  @HiveField(14)
  final String notes;
  
  @HiveField(15)
  final List<OrderStatusHistory> statusHistory;

  Order({
    required this.id,
    required this.userId,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.shipping,
    required this.total,
    required this.status,
    required this.orderDate,
    this.shippedDate,
    this.deliveredDate,
    required this.shippingAddress,
    required this.paymentMethod,
    required this.trackingNumber,
    required this.notes,
    required this.statusHistory,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => OrderItem.fromJson(item))
          .toList() ?? [],
      subtotal: (json['subtotal'] ?? 0.0).toDouble(),
      tax: (json['tax'] ?? 0.0).toDouble(),
      shipping: (json['shipping'] ?? 0.0).toDouble(),
      total: (json['total'] ?? 0.0).toDouble(),
      status: OrderStatus.values.firstWhere(
        (e) => e.toString() == 'OrderStatus.${json['status']}',
        orElse: () => OrderStatus.pending,
      ),
      orderDate: DateTime.parse(json['orderDate'] ?? DateTime.now().toIso8601String()),
      shippedDate: json['shippedDate'] != null 
          ? DateTime.parse(json['shippedDate']) 
          : null,
      deliveredDate: json['deliveredDate'] != null 
          ? DateTime.parse(json['deliveredDate']) 
          : null,
      shippingAddress: Address.fromJson(json['shippingAddress'] ?? {}),
      paymentMethod: PaymentMethod.fromJson(json['paymentMethod'] ?? {}),
      trackingNumber: json['trackingNumber'] ?? '',
      notes: json['notes'] ?? '',
      statusHistory: (json['statusHistory'] as List<dynamic>?)
          ?.map((status) => OrderStatusHistory.fromJson(status))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'items': items.map((item) => item.toJson()).toList(),
      'subtotal': subtotal,
      'tax': tax,
      'shipping': shipping,
      'total': total,
      'status': status.toString().split('.').last,
      'orderDate': orderDate.toIso8601String(),
      'shippedDate': shippedDate?.toIso8601String(),
      'deliveredDate': deliveredDate?.toIso8601String(),
      'shippingAddress': shippingAddress.toJson(),
      'paymentMethod': paymentMethod.toJson(),
      'trackingNumber': trackingNumber,
      'notes': notes,
      'statusHistory': statusHistory.map((status) => status.toJson()).toList(),
    };
  }
}

@HiveType(typeId: 5)
class OrderItem extends HiveObject {
  @HiveField(0)
  final String cardId;
  
  @HiveField(1)
  final String cardName;
  
  @HiveField(2)
  final String cardImage;
  
  @HiveField(3)
  final int quantity;
  
  @HiveField(4)
  final double unitPrice;
  
  @HiveField(5)
  final double totalPrice;

  OrderItem({
    required this.cardId,
    required this.cardName,
    required this.cardImage,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      cardId: json['cardId'] ?? '',
      cardName: json['cardName'] ?? '',
      cardImage: json['cardImage'] ?? '',
      quantity: json['quantity'] ?? 1,
      unitPrice: (json['unitPrice'] ?? 0.0).toDouble(),
      totalPrice: (json['totalPrice'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cardId': cardId,
      'cardName': cardName,
      'cardImage': cardImage,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
    };
  }
}

@HiveType(typeId: 6)
class OrderStatusHistory extends HiveObject {
  @HiveField(0)
  final OrderStatus status;
  
  @HiveField(1)
  final DateTime timestamp;
  
  @HiveField(2)
  final String note;

  OrderStatusHistory({
    required this.status,
    required this.timestamp,
    required this.note,
  });

  factory OrderStatusHistory.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistory(
      status: OrderStatus.values.firstWhere(
        (e) => e.toString() == 'OrderStatus.${json['status']}',
        orElse: () => OrderStatus.pending,
      ),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      note: json['note'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.toString().split('.').last,
      'timestamp': timestamp.toIso8601String(),
      'note': note,
    };
  }
}

enum OrderStatus {
  pending,
  confirmed,
  processing,
  shipped,
  delivered,
  cancelled,
  refunded,
}
