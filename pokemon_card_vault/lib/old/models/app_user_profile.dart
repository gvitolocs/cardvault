import 'package:cloud_firestore/cloud_firestore.dart';

class AppUserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String username;
  final String? photoUrl;
  final String? walletAddress;
  final String role;
  final List<String> roles;
  final bool admin;
  final bool isAdmin;
  final bool reserve;
  final bool isReserve;
  final bool hasReserveAccessFlag;
  final DateTime? silverUntil;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.username,
    this.photoUrl,
    this.walletAddress,
    this.role = 'user',
    this.roles = const [],
    this.admin = false,
    this.isAdmin = false,
    this.reserve = false,
    this.isReserve = false,
    this.hasReserveAccessFlag = false,
    this.silverUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppUserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return AppUserProfile(
      uid: snapshot.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Pokoin user',
      username: data['username'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      walletAddress: data['walletAddress'] as String?,
      role: data['role'] as String? ?? 'user',
      roles: _readStringList(data['roles']),
      admin: data['admin'] == true,
      isAdmin: data['isAdmin'] == true,
      reserve: data['reserve'] == true,
      isReserve: data['isReserve'] == true,
      hasReserveAccessFlag: data['hasReserveAccess'] == true,
      silverUntil: _readOptionalDate(data['silverUntil']),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  factory AppUserProfile.fromCache(Map<String, dynamic> data) {
    return AppUserProfile(
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Pokoin user',
      username: data['username'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      walletAddress: data['walletAddress'] as String?,
      role: data['role'] as String? ?? 'user',
      roles: _readStringList(data['roles']),
      admin: data['admin'] == true,
      isAdmin: data['isAdmin'] == true,
      reserve: data['reserve'] == true,
      isReserve: data['isReserve'] == true,
      hasReserveAccessFlag: data['hasReserveAccess'] == true,
      silverUntil: _readOptionalDate(data['silverUntil']),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  bool get hasAdminAccess =>
      admin ||
      isAdmin ||
      role.trim().toLowerCase() == 'admin' ||
      roles.map((entry) => entry.trim().toLowerCase()).contains('admin');

  bool get hasReserveAccess =>
      reserve ||
      isReserve ||
      hasReserveAccessFlag ||
      role.trim().toLowerCase() == 'reserve' ||
      roles.map((entry) => entry.trim().toLowerCase()).contains('reserve');

  bool get hasSilverAccess {
    final expiry = silverUntil;
    return hasAdminAccess ||
        role.trim().toLowerCase() == 'silver' ||
        (expiry != null && expiry.isAfter(DateTime.now()));
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'username': username,
      'photoUrl': photoUrl,
      'walletAddress': walletAddress,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Map<String, dynamic> toCache() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'username': username,
      'photoUrl': photoUrl,
      'walletAddress': walletAddress,
      'role': role,
      'roles': roles,
      'admin': admin,
      'isAdmin': isAdmin,
      'reserve': reserve,
      'isReserve': isReserve,
      'hasReserveAccess': hasReserveAccessFlag,
      'silverUntil': silverUntil?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static DateTime _readDate(Object? value) {
    return _readOptionalDate(value) ?? DateTime.now();
  }

  static DateTime? _readOptionalDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static List<String> _readStringList(Object? value) {
    if (value is Iterable) {
      return value.map((entry) => entry.toString()).toList(growable: false);
    }
    if (value is String) {
      return value
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }
}
