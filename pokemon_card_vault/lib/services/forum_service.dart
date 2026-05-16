import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory ForumCategory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return ForumCategory(
      id: snapshot.id,
      title: data['title'] as String? ?? snapshot.id,
      description: data['description'] as String? ?? '',
      iconName: data['iconName'] as String? ?? 'forum',
      order: data['order'] as int? ?? 999,
      topicCount: data['topicCount'] as int? ?? 0,
      postCount: data['postCount'] as int? ?? 0,
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

  factory ForumTopic.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return ForumTopic(
      id: snapshot.id,
      categoryId: data['categoryId'] as String? ?? '',
      title: data['title'] as String? ?? 'Untitled topic',
      body: data['body'] as String? ?? '',
      authorUid: data['authorUid'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'Pokoin user',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      replyCount: data['replyCount'] as int? ?? 0,
      status: data['status'] as String? ?? 'open',
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
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
  });

  final String id;
  final String topicId;
  final String body;
  final String authorUid;
  final String authorName;
  final String? authorPhotoUrl;
  final DateTime createdAt;

  factory ForumPost.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return ForumPost(
      id: snapshot.id,
      topicId: data['topicId'] as String? ?? '',
      body: data['body'] as String? ?? '',
      authorUid: data['authorUid'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'Pokoin user',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      createdAt: _readDate(data['createdAt']),
    );
  }
}

class ForumService {
  ForumService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<ForumCategory>> categories() {
    return _firestore
        .collection('forum_categories')
        .orderBy('order')
        .limit(20)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(ForumCategory.fromFirestore).toList();
      return items.isEmpty ? defaultForumCategories : items;
    });
  }

  Stream<List<ForumTopic>> topics({String? categoryId}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('forum_topics')
        .where('status', isEqualTo: 'open')
        .limit(25);

    if (categoryId != null && categoryId.isNotEmpty) {
      query = _firestore
          .collection('forum_topics')
          .where('categoryId', isEqualTo: categoryId)
          .where('status', isEqualTo: 'open')
          .limit(25);
    }

    return query.snapshots().map(
      (snapshot) {
        final items = snapshot.docs.map(ForumTopic.fromFirestore).toList();
        items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return items;
      },
    );
  }

  Stream<ForumTopic?> topic(String topicId) {
    return _firestore.collection('forum_topics').doc(topicId).snapshots().map(
          (snapshot) =>
              snapshot.exists ? ForumTopic.fromFirestore(snapshot) : null,
        );
  }

  Stream<List<ForumPost>> posts(String topicId) {
    return _firestore
        .collection('forum_posts')
        .where('topicId', isEqualTo: topicId)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(ForumPost.fromFirestore).toList();
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return items;
    });
  }

  Future<String> createTopic({
    required String categoryId,
    required String title,
    required String body,
    required String authorUid,
    required String authorName,
    required String? authorPhotoUrl,
  }) async {
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.length < 6) {
      throw ArgumentError('Topic title must be at least 6 characters.');
    }
    if (cleanBody.length < 12) {
      throw ArgumentError('Topic body must be at least 12 characters.');
    }

    final categoryRef =
        _firestore.collection('forum_categories').doc(categoryId);
    final topicRef = _firestore.collection('forum_topics').doc();
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      final category = await transaction.get(categoryRef);
      if (!category.exists) {
        final defaultCategory = _defaultCategoryById(categoryId);
        if (defaultCategory == null) {
          throw StateError('Choose a valid forum category.');
        }
        transaction.set(categoryRef, {
          'title': defaultCategory.title,
          'description': defaultCategory.description,
          'iconName': defaultCategory.iconName,
          'order': defaultCategory.order,
          'topicCount': 1,
          'postCount': 1,
          'createdAt': now,
          'updatedAt': now,
        });
      } else {
        transaction.update(categoryRef, {
          'topicCount': FieldValue.increment(1),
          'postCount': FieldValue.increment(1),
          'updatedAt': now,
        });
      }

      transaction.set(topicRef, {
        'categoryId': categoryId,
        'title': cleanTitle,
        'body': cleanBody,
        'authorUid': authorUid,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'replyCount': 0,
        'status': 'open',
        'createdAt': now,
        'updatedAt': now,
      });
    });

    return topicRef.id;
  }

  Future<void> createPost({
    required String topicId,
    required String body,
    required String authorUid,
    required String authorName,
    required String? authorPhotoUrl,
  }) async {
    final cleanBody = body.trim();
    if (cleanBody.length < 3) {
      throw ArgumentError('Reply must be at least 3 characters.');
    }

    final topicRef = _firestore.collection('forum_topics').doc(topicId);
    final postRef = _firestore.collection('forum_posts').doc();
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      final topic = await transaction.get(topicRef);
      if (!topic.exists || topic.data()?['status'] != 'open') {
        throw StateError('This topic is no longer open.');
      }
      final categoryId = topic.data()?['categoryId'] as String? ?? '';

      transaction.set(postRef, {
        'topicId': topicId,
        'categoryId': categoryId,
        'body': cleanBody,
        'authorUid': authorUid,
        'authorName': authorName,
        'authorPhotoUrl': authorPhotoUrl,
        'createdAt': now,
        'updatedAt': now,
      });
      transaction.update(topicRef, {
        'replyCount': FieldValue.increment(1),
        'updatedAt': now,
      });
      if (categoryId.isNotEmpty) {
        transaction
            .update(_firestore.collection('forum_categories').doc(categoryId), {
          'postCount': FieldValue.increment(1),
          'updatedAt': now,
        });
      }
    });
  }
}

DateTime _readDate(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
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

ForumCategory? _defaultCategoryById(String id) {
  for (final category in defaultForumCategories) {
    if (category.id == id) {
      return category;
    }
  }
  return null;
}
