class ShippingAddress {
  const ShippingAddress(
      {this.id = '',
      this.label = '',
      this.fullName = '',
      this.addressLine1 = '',
      this.addressLine2 = '',
      this.postalCode = '',
      this.city = '',
      this.countryCode = '',
      this.phoneNumber = '',
      this.isDefault = false});
  final String id,
      label,
      fullName,
      addressLine1,
      addressLine2,
      postalCode,
      city,
      countryCode,
      phoneNumber;
  final bool isDefault;
  factory ShippingAddress.fromJson(Map<String, dynamic> json) =>
      ShippingAddress(
          id: '${json['id'] ?? ''}',
          label: '${json['label'] ?? ''}',
          fullName: '${json['fullName'] ?? ''}',
          addressLine1: '${json['addressLine1'] ?? ''}',
          addressLine2: '${json['addressLine2'] ?? ''}',
          postalCode: '${json['postalCode'] ?? ''}',
          city: '${json['city'] ?? ''}',
          countryCode: '${json['countryCode'] ?? ''}'.trim().toUpperCase(),
          phoneNumber: '${json['phoneNumber'] ?? ''}',
          isDefault: json['isDefault'] == true);
  Map<String, dynamic> toJson() => {
        'label': label.trim(),
        'fullName': fullName.trim(),
        'addressLine1': addressLine1.trim(),
        'addressLine2': addressLine2.trim(),
        'postalCode': postalCode.trim(),
        'city': city.trim(),
        'countryCode': countryCode.trim().toUpperCase(),
        'phoneNumber': phoneNumber.trim(),
        'isDefault': isDefault
      };
  ShippingAddress asDefault() =>
      ShippingAddress.fromJson({...toJson(), 'id': id, 'isDefault': true});
}
