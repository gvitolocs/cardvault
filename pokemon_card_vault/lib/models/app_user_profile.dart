import 'package:cloud_firestore/cloud_firestore.dart';

class AppUserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String username;
  final String? photoUrl;
  final String? walletAddress;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.username,
    this.photoUrl,
    this.walletAddress,
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
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
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

  static DateTime _readDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}
