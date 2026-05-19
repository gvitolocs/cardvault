import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ForumCategory {
  const ForumCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.iconName,
    required this.order,
    required this.topicCount,
    required this.postCount,
  });

  final String id;
  final String title;
  final String description;
  final String iconName;
  final int order;
  final int topicCount;
  final int postCount;

  factory ForumCategory.fromJson(Map<String, dynamic> data) {
    return ForumCategory(
      id: data['id'] as String? ?? '',
      title: data['title'] as String? ?? data['id'] as String? ?? '',
      description: data['description'] as String? ?? '',
      iconName: data['icon_name'] as String? ??
          data['iconName'] as String? ??
          'forum',
      order: _readInt(data['sort_order'] ?? data['order'], 999),
      topicCount: _readInt(data['topic_count'] ?? data['topicCount'], 0),
      postCount: _readInt(data['post_count'] ?? data['postCount'], 0),
    );
  }
}

class ForumTopic {
  const ForumTopic({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.body,
    required this.authorUid,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.replyCount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.media = const [],
  });

  final String id;
  final String categoryId;
  final String title;
  final String body;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final int replyCount;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ForumMedia> media;

  factory ForumTopic.fromJson(Map<String, dynamic> data) {
    return ForumTopic(
      id: data['id'] as String? ?? '',
      categoryId:
          data['category_id'] as String? ?? data['categoryId'] as String? ?? '',
      title: data['title'] as String? ?? 'Untitled topic',
      body: data['body'] as String? ?? '',
      authorUid:
          data['author_uid'] as String? ?? data['authorUid'] as String? ?? '',
      authorName: data['author_name'] as String? ??
          data['authorName'] as String? ??
          'Pokoin user',
      authorPhotoUrl: data['author_photo_url'] as String? ??
          data['authorPhotoUrl'] as String?,
      replyCount: _readInt(data['reply_count'] ?? data['replyCount'], 0),
      status: data['status'] as String? ?? 'open',
      createdAt: _readDate(data['created_at'] ?? data['createdAt']),
      updatedAt: _readDate(data['updated_at'] ?? data['updatedAt']),
      media: _readMediaList(data['media']),
    );
  }

  ForumTopic copyWith({List<ForumMedia>? media}) {
    return ForumTopic(
      id: id,
      categoryId: categoryId,
      title: title,
      body: body,
      authorUid: authorUid,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      replyCount: replyCount,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      media: media ?? this.media,
    );
  }
}

class ForumPost {
  const ForumPost({
    required this.id,
    required this.topicId,
    required this.body,
    required this.authorUid,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.createdAt,
    this.media = const [],
  });

  final String id;
  final String topicId;
  final String body;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final DateTime createdAt;
  final List<ForumMedia> media;

  factory ForumPost.fromJson(Map<String, dynamic> data) {
    return ForumPost(
      id: data['id'] as String? ?? '',
      topicId: data['topic_id'] as String? ?? data['topicId'] as String? ?? '',
      body: data['body'] as String? ?? '',
      authorUid:
          data['author_uid'] as String? ?? data['authorUid'] as String? ?? '',
      authorName: data['author_name'] as String? ??
          data['authorName'] as String? ??
          'Pokoin user',
      authorPhotoUrl: data['author_photo_url'] as String? ??
          data['authorPhotoUrl'] as String?,
      createdAt: _readDate(data['created_at'] ?? data['createdAt']),
      media: _readMediaList(data['media']),
    );
  }

  ForumPost copyWith({List<ForumMedia>? media}) {
    return ForumPost(
      id: id,
      topicId: topicId,
      body: body,
      authorUid: authorUid,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      createdAt: createdAt,
      media: media ?? this.media,
    );
  }
}

class ForumService {
  ForumService({http.Client? client, FirebaseAuth? auth})
      : _client = client ?? http.Client(),
        _auth = auth ?? FirebaseAuth.instance;

  final http.Client _client;
  final FirebaseAuth _auth;

  Future<List<ForumCategory>> categories() async {
    try {
      final snapshot = await _homeSnapshot();
      final items = snapshot.categories;
      return items.isEmpty ? defaultForumCategories : items;
    } catch (_) {
      return defaultForumCategories;
    }
  }

  Future<List<ForumTopic>> topics({String? categoryId}) async {
    try {
      final snapshot = await _homeSnapshot(categoryId: categoryId);
      return snapshot.topics;
    } catch (_) {
      return const [];
    }
  }

  Future<ForumTopic?> topic(String topicId) async {
    return _topicSnapshot(topicId).then((snapshot) => snapshot.topic);
  }

  Future<List<ForumPost>> posts(String topicId) async {
    return _topicSnapshot(topicId).then((snapshot) => snapshot.posts);
  }

  Future<String> createTopic({
    required String categoryId,
    required String title,
    required String body,
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.length < 6) {
      throw ArgumentError('Topic title must be at least 6 characters.');
    }
    if (cleanBody.length < 12) {
      throw ArgumentError('Topic body must be at least 12 characters.');
    }

    final data = await _postJson('/api/forum-create-topic', {
      'categoryId': categoryId,
      'title': cleanTitle,
      'body': cleanBody,
    });
    final topic = ForumTopic.fromJson(
      Map<String, dynamic>.from(data['topic'] as Map? ?? const {}),
    );
    return topic.id;
  }

  Future<String> createPost({
    required String topicId,
    required String body,
  }) async {
    final cleanBody = body.trim();
    if (cleanBody.length < 3) {
      throw ArgumentError('Reply must be at least 3 characters.');
    }

    final data = await _postJson('/api/forum-create-post', {
      'topicId': topicId,
      'body': cleanBody,
    });
    final post = ForumPost.fromJson(
      Map<String, dynamic>.from(data['post'] as Map? ?? const {}),
    );
    return post.id;
  }

  Future<ForumMedia> uploadMedia({
    required String topicId,
    String? postId,
    required Uint8List imageBytes,
  }) async {
    final data = await _postJson('/api/forum-upload-media', {
      'topicId': topicId,
      if (postId != null && postId.isNotEmpty) 'postId': postId,
      'imageBase64': base64Encode(imageBytes),
    });
    return ForumMedia.fromJson(
      Map<String, dynamic>.from(data['media'] as Map? ?? const {}),
    );
  }

  Future<_ForumHomeSnapshot> _homeSnapshot({String? categoryId}) async {
    final uri = Uri.base.resolve('/api/forum').replace(
      queryParameters: {
        if (categoryId != null && categoryId.isNotEmpty)
          'categoryId': categoryId,
      },
    );
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 10));
    final data = _decodeResponse(response);
    return _ForumHomeSnapshot.fromJson(data);
  }

  Future<_ForumTopicSnapshot> _topicSnapshot(String topicId) async {
    final uri = Uri.base.resolve('/api/forum').replace(
      queryParameters: {'topicId': topicId},
    );
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 10));
    final data = _decodeResponse(response);
    return _ForumTopicSnapshot.fromJson(data);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in to post in the forum.');
    }
    final token = await user.getIdToken();
    final response = await _client
        .post(
          Uri.base.resolve(path),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    return _decodeResponse(response);
  }
}

DateTime _readDate(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

int _readInt(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

Map<String, dynamic> _decodeResponse(http.Response response) {
  final decoded = response.body.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode >= 400) {
    throw StateError(decoded['error'] as String? ?? 'Forum request failed.');
  }
  return decoded;
}

class ForumMedia {
  const ForumMedia({
    required this.id,
    required this.url,
    required this.mimeType,
    required this.byteSize,
    this.topicId,
    this.postId,
  });

  final String id;
  final String url;
  final String mimeType;
  final int byteSize;
  final String? topicId;
  final String? postId;

  factory ForumMedia.fromJson(Map<String, dynamic> data) {
    return ForumMedia(
      id: data['id'] as String? ?? '',
      url: data['public_url'] as String? ?? data['url'] as String? ?? '',
      mimeType: data['mime_type'] as String? ?? 'image/webp',
      byteSize: _readInt(data['byte_size'], 0),
      topicId: data['topic_id'] as String?,
      postId: data['post_id'] as String?,
    );
  }
}

class _ForumHomeSnapshot {
  const _ForumHomeSnapshot({required this.categories, required this.topics});

  final List<ForumCategory> categories;
  final List<ForumTopic> topics;

  factory _ForumHomeSnapshot.fromJson(Map<String, dynamic> data) {
    return _ForumHomeSnapshot(
      categories: (data['categories'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => ForumCategory.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      topics: (data['topics'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => ForumTopic.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }
}

class _ForumTopicSnapshot {
  const _ForumTopicSnapshot({
    required this.topic,
    required this.posts,
    required this.media,
  });

  final ForumTopic? topic;
  final List<ForumPost> posts;
  final List<ForumMedia> media;

  factory _ForumTopicSnapshot.fromJson(Map<String, dynamic> data) {
    final topicData = data['topic'];
    final media = _readMediaList(data['media']);
    return _ForumTopicSnapshot(
      topic: _topicWithMedia(topicData, media),
      posts: _postsWithMedia(data['posts'], media),
      media: media,
    );
  }

  static ForumTopic? _topicWithMedia(
      Object? topicData, List<ForumMedia> media) {
    if (topicData is! Map) {
      return null;
    }
    final topic = ForumTopic.fromJson(Map<String, dynamic>.from(topicData));
    return topic.copyWith(
      media: media.where((item) => item.postId == null).toList(),
    );
  }

  static List<ForumPost> _postsWithMedia(
    Object? postData,
    List<ForumMedia> media,
  ) {
    return (postData as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => ForumPost.fromJson(Map<String, dynamic>.from(row)))
        .map(
          (post) => post.copyWith(
            media: media.where((item) => item.postId == post.id).toList(),
          ),
        )
        .toList();
  }
}

List<ForumMedia> _readMediaList(Object? value) {
  return (value as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((row) => ForumMedia.fromJson(Map<String, dynamic>.from(row)))
      .toList();
}

const defaultForumCategories = [
  ForumCategory(
    id: 'general',
    title: 'General',
    description: 'Community updates and open discussion.',
    iconName: 'forum',
    order: 10,
    topicCount: 0,
    postCount: 0,
  ),
  ForumCategory(
    id: 'cards',
    title: 'Cards',
    description: 'Collecting, grading, trades and marketplace ideas.',
    iconName: 'cards',
    order: 20,
    topicCount: 0,
    postCount: 0,
  ),
  ForumCategory(
    id: 'pkn',
    title: 'PKN and wPKN',
    description: 'Native PKN, wPKN liquidity and DeFi.',
    iconName: 'token',
    order: 30,
    topicCount: 0,
    postCount: 0,
  ),
  ForumCategory(
    id: 'validators',
    title: 'Validators',
    description: 'Nodes, RPC, staking and network operations.',
    iconName: 'validators',
    order: 40,
    topicCount: 0,
    postCount: 0,
  ),
];
